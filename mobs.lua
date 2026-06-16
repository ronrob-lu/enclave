-- Mobs and spawning control for the enclave mod
local STORAGE = minetest.get_mod_storage()
local kills = tonumber(STORAGE:get_string("kills")) or 0
local MAX_KILLS = 1000
local MAX_ACTIVE = 15
local spawn_timer = 0
local SPEED = 3.5

-- Compatibility alias for the entity name
minetest.register_alias_force("estado_totalitario:npc", "enclave:npc")

-- Helper function to check if a position is inside the perimeter corridor of any active enclave
-- The corridor is between 92 (inner wall) and 121 (outer wall) blocks from the center
function enclave.get_corridor_at(pos)
    for _, enc in ipairs(enclave.active_enclaves) do
        local dx = math.abs(pos.x - enc.x)
        local dz = math.abs(pos.z - enc.z)
        if dx <= 121 and dz <= 121 and (dx >= 92 or dz >= 92) then
            return enc
        end
    end
    return nil
end

minetest.register_entity("enclave:npc", {
    hp_max = 20,
    physical = true,
    collide_with_objects = true,
    collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.7, 0.3},
    stepheight = 0.6,
    visual = "mesh",
    mesh = "character.b3d",
    textures = {"estado_char.png"},
    visual_size = {x=1, y=1},
    automatic_rotate = 0,
    makes_footstep_sound = true,
    counted = false,
    attack_cd = 0,
    anim_timer = 0,
    jump_cd = 0,
    enclave_center = nil,
    patrol_target = nil,
    patrol_timer = 0,

    on_activate = function(self, staticdata, dtime_s)
        self.object:set_armor_groups({fleshy=100})
        self.object:set_acceleration({x=0, y=-9.8, z=0})
        self.attack_cd = 0
        self.anim_timer = 0
        self.jump_cd = 0
        self.patrol_timer = 0

        if staticdata and staticdata ~= "" then
            local data = minetest.deserialize(staticdata)
            if data then
                self.enclave_center = data.enclave_center
                self.patrol_target = data.patrol_target
                self.counted = data.counted
            end
        end
    end,

    get_staticdata = function(self)
        local data = {
            enclave_center = self.enclave_center,
            patrol_target = self.patrol_target,
            counted = self.counted,
        }
        return minetest.serialize(data)
    end,

    update_anim = function(self, hspeed)
        if hspeed > 0.5 then
            self.object:set_animation({x = 168, y = 188}, 30, 0, true)
        else
            self.object:set_animation({x = 0,   y = 79},  30, 0, true)
        end
    end,

    on_step = function(self, dtime)
        if self.counted then return end
        local pos = self.object:get_pos()
        if not pos then return end

        local vel = self.object:get_velocity() or {x=0, y=0, z=0}
        local hp = self.object:get_hp()
        local hspeed = math.sqrt(vel.x*vel.x + vel.z*vel.z)

        -- Animation tick
        self.anim_timer = self.anim_timer + dtime
        if self.anim_timer >= 0.2 then
            self:update_anim(hspeed)
            self.anim_timer = 0
        end

        -- Liquid damage
        local node = minetest.get_node(pos)
        local def = minetest.registered_nodes[node.name]
        if def and def.groups.liquid then
            local dmg = node.name:find("lava") and 4 or 1
            hp = hp - dmg
            self.object:set_hp(math.max(0, hp))
            if self.object:get_hp() <= 0 then
                if not self.counted then
                    kills = kills + 1
                    STORAGE:set_string("kills", tostring(kills))
                    self.counted = true
                end
                self.object:remove()
                return
            end
        end

        -- Boundary clamping (Prevent escaping outer wall & entering inner courtyard)
        if self.enclave_center then
            local dx = pos.x - self.enclave_center.x
            local dz = pos.z - self.enclave_center.z

            -- 1. Clamp to outer boundaries
            local clamped_x = math.max(-121, math.min(121, dx))
            local clamped_z = math.max(-121, math.min(121, dz))

            -- 2. Push out of central courtyard if inside (width [-91, 91])
            local abs_cx = math.abs(clamped_x)
            local abs_cz = math.abs(clamped_z)
            if abs_cx < 92 and abs_cz < 92 then
                -- Push to nearest wall boundary
                local push_x = 92 - abs_cx
                local push_z = 92 - abs_cz
                if push_x < push_z then
                    clamped_x = (clamped_x >= 0) and 92 or -92
                else
                    clamped_z = (clamped_z >= 0) and 92 or -92
                end
            end

            local px = self.enclave_center.x + clamped_x
            local pz = self.enclave_center.z + clamped_z

            if px ~= pos.x or pz ~= pos.z then
                self.object:set_pos({x = px, y = pos.y, z = pz})
                pos.x = px
                pos.z = pz
                -- Stop horizontal velocity on collision
                local vx = (px ~= pos.x) and 0 or vel.x
                local vz = (pz ~= pos.z) and 0 or vel.z
                self.object:set_velocity({x = vx, y = vel.y, z = vz})
                vel.x = vx
                vel.z = vz
                self.patrol_target = nil -- pick new target
            end
        end

        -- Find nearest player
        local target = nil
        local min_dist = 80
        for _, plr in ipairs(minetest.get_connected_players()) do
            local ppos = plr:get_pos()
            if ppos then
                local d = vector.distance(pos, ppos)
                if d < min_dist then 
                    min_dist = d
                    target = plr 
                end
            end
        end

        -- Target coordinate to move towards
        local target_pos = nil
        if target then
            target_pos = target:get_pos()
            self.patrol_target = nil
        elseif self.enclave_center then
            -- Patrol only inside the corridor
            if not self.patrol_target or not self.patrol_timer or self.patrol_timer <= 0 then
                -- Select a random corridor side: 1=East, 2=West, 3=North, 4=South
                local side = math.random(1, 4)
                local tx, tz
                if side == 1 then -- East
                    tx = math.random(92, 120)
                    tz = math.random(-120, 120)
                elseif side == 2 then -- West
                    tx = math.random(-120, -92)
                    tz = math.random(-120, 120)
                elseif side == 3 then -- North
                    tx = math.random(-120, 120)
                    tz = math.random(92, 120)
                else -- South
                    tx = math.random(-120, 120)
                    tz = math.random(-120, -92)
                end

                local world_tx = self.enclave_center.x + tx
                local world_tz = self.enclave_center.z + tz
                
                -- Find ground level at target near mob's current y
                local ty = nil
                for y = pos.y + 15, pos.y - 15, -1 do
                    local name = minetest.get_node({x=world_tx, y=y, z=world_tz}).name
                    if name ~= "ignore" and name ~= "air" then
                        local d = minetest.registered_nodes[name]
                        if d and d.walkable and not d.groups.liquid and not d.groups.leaves and not d.groups.flora then
                            ty = y
                            break
                        end
                    end
                end
                
                if ty then
                    self.patrol_target = {x = world_tx, y = ty + 1.5, z = world_tz}
                    self.patrol_timer = 20
                end
            else
                self.patrol_timer = self.patrol_timer - dtime
                target_pos = self.patrol_target
            end
        end

        if target_pos then
            local dx = target_pos.x - pos.x
            local dz = target_pos.z - pos.z
            local flat_dist = math.sqrt(dx*dx + dz*dz)

            if flat_dist > 0.8 then
                local inv = 1 / flat_dist
                local dirx = dx * inv
                local dirz = dz * inv

                -- Smooth rotation
                local want_yaw = math.atan2(-dirx, dirz)
                local cur_yaw  = self.object:get_yaw() or 0
                local diff = want_yaw - cur_yaw
                if diff >  math.pi then diff = diff - 2 * math.pi end
                if diff < -math.pi then diff = diff + 2 * math.pi end
                self.object:set_yaw(cur_yaw + diff * math.min(dtime * 12, 1))

                -- Multi-point liquid scan
                local liquid_ahead = false
                for dist = 0.4, 1.0, 0.3 do
                    for y_off = 0.0, -1.0, -0.5 do
                        local c = {x=pos.x+dirx*dist, y=pos.y+y_off, z=pos.z+dirz*dist}
                        local n = minetest.get_node(c)
                        local d = minetest.registered_nodes[n.name]
                        if d and d.groups.liquid then
                            liquid_ahead = true
                        end
                    end
                end

                -- Solid obstacle scan
                local solid_ahead = false
                local can_jump_over = false
                for dist = 0.6, 1.0, 0.2 do
                    local c = {x=pos.x+dirx*dist, y=pos.y+0.5, z=pos.z+dirz*dist}
                    local n = minetest.get_node(c)
                    local d = minetest.registered_nodes[n.name]
                    if d and d.walkable and not d.groups.liquid then
                        solid_ahead = true
                        local c_up = {x=c.x, y=c.y+1.2, z=c.z}
                        local n_up = minetest.get_node(c_up)
                        local d_up = minetest.registered_nodes[n_up.name]
                        if not d_up or (not d_up.walkable and not d_up.groups.liquid) then
                            can_jump_over = true
                        end
                    end
                end

                -- Ground check
                local below = {x=pos.x, y=pos.y-0.1, z=pos.z}
                local below_def = minetest.registered_nodes[minetest.get_node(below).name]
                local on_ground = below_def and below_def.walkable and math.abs(vel.y) < 0.1

                -- Movement decision tree
                if liquid_ahead then
                    self.object:set_velocity({x = 0, y = vel.y, z = 0})
                    self.jump_cd = 1.0
                    self.patrol_target = nil
                elseif solid_ahead and can_jump_over and on_ground and self.jump_cd <= 0 then
                    self.object:set_velocity({x = dirx * SPEED, y = 5.0, z = dirz * SPEED})
                    self.jump_cd = 1.5
                elseif not solid_ahead then
                    self.object:set_velocity({x = dirx * SPEED, y = vel.y, z = dirz * SPEED})
                    if self.jump_cd > 0 then self.jump_cd = self.jump_cd - dtime end
                else
                    -- Blocked
                    self.object:set_velocity({x = dirx * SPEED * 0.2, y = vel.y, z = dirz * SPEED * 0.2})
                    if self.jump_cd > 0 then self.jump_cd = self.jump_cd - dtime end
                    self.patrol_target = nil
                end
            else
                -- Reached target
                self.object:set_velocity({x = 0, y = vel.y, z = 0})
                if not target then
                    self.patrol_target = nil
                end
            end

            -- Contact attack (only if target is player)
            if target then
                self.attack_cd = self.attack_cd - dtime
                if min_dist < 1.5 and self.attack_cd <= 0 then
                    target:set_hp(target:get_hp() - 2)
                    self.attack_cd = 0.8
                end
            end
        else
            -- Idle friction
            self.object:set_velocity({x = vel.x * 0.85, y = vel.y, z = vel.z * 0.85})
        end
    end,

    on_punch = function(self, puncher, _, tool_caps)
        if self.counted then return end
        local dmg = (tool_caps and tool_caps.damage_groups.fleshy) or 4
        self.object:set_hp(math.max(0, self.object:get_hp() - dmg))
    end,

    on_deactivate = function(self)
        if not self.counted and self.object:get_hp() <= 0 then
            kills = kills + 1
            STORAGE:set_string("kills", tostring(kills))
            self.counted = true
        end
    end
})

-- Global Step Spawning Logic: Restricted to inside the corridor
minetest.register_globalstep(function(dtime)
    if kills >= MAX_KILLS then return end
    spawn_timer = spawn_timer + dtime
    if spawn_timer < 5 then return end
    spawn_timer = 0

    local active = 0
    for _, obj in pairs(minetest.luaentities) do
        if obj.name == "enclave:npc" then active = active + 1 end
    end
    if active >= MAX_ACTIVE then return end

    local players = minetest.get_connected_players()
    if #players == 0 then return end

    local plr = players[math.random(#players)]
    local ppos = plr:get_pos()
    if not ppos then return end

    local angle = math.random() * math.pi * 2
    local dist = 92 + math.random() * 25 -- Keep spawn within the corridor radius
    local sx = ppos.x + math.cos(angle) * dist
    local sz = ppos.z + math.sin(angle) * dist
    local spawn_pos = {x=sx, y=ppos.y, z=sz}

    -- Restriction: Check if the spawn position is in the corridor of an enclave
    local enc = enclave.get_corridor_at(spawn_pos)
    if not enc then return end

    -- Find ground Y
    local ground_y = nil
    for y = ppos.y + 20, ppos.y - 30, -1 do
        local name = minetest.get_node({x=sx, y=y, z=sz}).name
        if name ~= "ignore" then
            local def = minetest.registered_nodes[name]
            if def and def.walkable then
                ground_y = y
                break
            end
        end
    end
    if not ground_y then return end

    spawn_pos.y = ground_y + 1.5
    for i = 1, 10 do
        local check = minetest.get_node(spawn_pos)
        local check_def = minetest.registered_nodes[check.name]
        if check_def and check_def.walkable then
            spawn_pos.y = spawn_pos.y + 1
        else
            break
        end
    end

    local eye = {x=ppos.x, y=ppos.y + 1.6, z=ppos.z}
    local chest = {x=spawn_pos.x, y=spawn_pos.y + 0.8, z=spawn_pos.z}

    if not minetest.line_of_sight(eye, chest) then
        local obj = minetest.add_entity(spawn_pos, "enclave:npc")
        if obj then
            obj:set_rotation({x=0, y=angle + math.pi, z=0})
            local lua_ent = obj:get_luaentity()
            if lua_ent then
                lua_ent.enclave_center = {x=enc.x, z=enc.z}
            end
        end
    end
end)

-- Admin commands
minetest.register_chatcommand("reset_enclave_kills", {
    description = "Resets the enclave mob kill counter",
    privs = {server = true},
    func = function(name)
        kills = 0
        STORAGE:set_string("kills", "0")
        minetest.chat_send_player(name, "[Enclave] Kill counter reset.")
    end
})

minetest.register_chatcommand("clear_enclave_mobs", {
    description = "Removes all active enclave NPCs",
    privs = {server = true},
    func = function(name)
        local count = 0
        for _, obj in pairs(minetest.luaentities) do
            if obj.name == "enclave:npc" then
                obj.object:remove()
                count = count + 1
            end
        end
        minetest.chat_send_player(name, "[Enclave] Removed " .. count .. " NPCs.")
    end
})
