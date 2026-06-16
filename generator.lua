-- World generator and base orchestrator for the enclave mod
local STORAGE = minetest.get_mod_storage()
local S = minetest.get_translator("enclave")

-- Safe stone sound definition
local stone_sounds = {
    footstep = {name = "default_node_footstep", gain = 0.5},
    dig = {name = "default_node_dig", gain = 0.6},
    dug = {name = "default_node_dug", gain = 0.8},
    place = {name = "default_node_place", gain = 1.0},
}

-- Load schematics at startup
local function load_schematic(filepath)
    local f = io.open(filepath, "r")
    if not f then
        minetest.log("error", "[enclave] Failed to open schematic: " .. filepath)
        return nil
    end
    local content = f:read("*a")
    f:close()
    
    -- Strip WorldEdit version prefix if present (e.g. "5:local...")
    local clean_content = content:gsub("^%d+:", "")
    
    local chunk, err = loadstring(clean_content)
    if not chunk then
        minetest.log("error", "[enclave] Failed to load schematic chunk: " .. tostring(err))
        return nil
    end
    
    return chunk()
end

local modpath = minetest.get_modpath("enclave")
local schem_grenzabschnitt = load_schematic(modpath .. "/schematics/grenzabschnitt.we")
local schem_grenzecke = load_schematic(modpath .. "/schematics/grenzecke.we")

-- Coordinate rotation helper
local function rotate_point(lx, lz, size_x, size_z, rot)
    if rot == 0 then
        return lx, lz
    elseif rot == 90 then
        return size_z - 1 - lz, lx
    elseif rot == 180 then
        return size_x - 1 - lx, size_z - 1 - lz
    elseif rot == 270 then
        return lz, size_x - 1 - lx
    end
end

-- Param2 (facedir) rotation helper
local function rotate_param2(name, param2, rot)
    local reg = minetest.registered_nodes[name]
    if reg and reg.paramtype2 == "facedir" then
        local axis = math.floor(param2 / 4)
        local dir = param2 % 4
        
        local rot_index = 0
        if rot == 90 then rot_index = 1
        elseif rot == 180 then rot_index = 2
        elseif rot == 270 then rot_index = 3 end
        
        local new_dir = (dir + rot_index) % 4
        return axis * 4 + new_dir
    end
    return param2
end

-- Raycast ground-height scanner (ignoring liquid/foliage/trees/ignore/air)
local function get_ground_level(x, z, center_y)
    local start_y = center_y + 80
    local end_y = center_y - 80
    for y = start_y, end_y, -1 do
        local node = minetest.get_node_or_nil({x = x, y = y, z = z})
        if node and node.name ~= "ignore" and node.name ~= "air" then
            local def = minetest.registered_nodes[node.name]
            if def and def.walkable 
                    and not def.groups.liquid 
                    and not def.groups.leaves 
                    and not def.groups.tree 
                    and not def.groups.cactus 
                    and not def.groups.flora then
                return y
            end
        end
    end
    return center_y
end

-- Places a straight wall segment (adapting to local ground level column-by-column and filling foundations)
local function place_straight_segment(center, x_off, z_off, rot, spawn_points)
    -- Calculate tower center world coordinates to place the tower flat
    local rx_t, rz_t = rotate_point(12, 11, 31, 86, rot)
    local tower_wx = center.x + x_off + rx_t
    local tower_wz = center.z + z_off + rz_t
    -- We add +2 so the tower floor sits exactly on top of the ground (with 1 block foundation buffer)
    local tower_y = get_ground_level(tower_wx, tower_wz, center.y) + 2

    local ground_cache = {}
    local function get_cached_ground(wx, wz)
        local key = wx .. "," .. wz
        if not ground_cache[key] then
            ground_cache[key] = get_ground_level(wx, wz, center.y)
        end
        return ground_cache[key]
    end

    -- Pre-populate ground cache for all columns in this segment before placing any blocks
    for _, entry in ipairs(schem_grenzabschnitt) do
        local rx, rz = rotate_point(entry.x, entry.z, 31, 86, rot)
        local world_x = center.x + x_off + rx
        local world_z = center.z + z_off + rz
        get_cached_ground(world_x, world_z)
    end

    -- First pass: Clear columns from gy + 1 up to gy + 25
    local cleared_cols = {}
    for _, entry in ipairs(schem_grenzabschnitt) do
        local rx, rz = rotate_point(entry.x, entry.z, 31, 86, rot)
        local world_x = center.x + x_off + rx
        local world_z = center.z + z_off + rz
        local key = world_x .. "," .. world_z
        if not cleared_cols[key] then
            local is_tower = (entry.x >= 10 and entry.x <= 14 and entry.z >= 9 and entry.z <= 13)
            local gy = get_cached_ground(world_x, world_z)
            local clear_start_y = gy + 1
            if is_tower then
                clear_start_y = math.min(tower_y, gy + 1)
            end
            for y = clear_start_y, clear_start_y + 25 do
                minetest.set_node({x = world_x, y = y, z = world_z}, {name = "air"})
            end
            cleared_cols[key] = true
        end
    end

    -- Find the minimum Y for each local (x, z)
    local min_y_map = {}
    for _, entry in ipairs(schem_grenzabschnitt) do
        local col_key = entry.x .. "," .. entry.z
        if not min_y_map[col_key] or entry.y < min_y_map[col_key] then
            min_y_map[col_key] = entry.y
        end
    end

    -- Second pass: Place nodes and fill foundations
    for _, entry in ipairs(schem_grenzabschnitt) do
        local rx, rz = rotate_point(entry.x, entry.z, 31, 86, rot)
        local world_x = center.x + x_off + rx
        local world_z = center.z + z_off + rz
        
        local is_tower = (entry.x >= 10 and entry.x <= 14 and entry.z >= 9 and entry.z <= 13)
        local base_y = is_tower and tower_y or (get_cached_ground(world_x, world_z) + 2)
        local world_y = base_y + entry.y
        local pos = {x = world_x, y = world_y, z = world_z}
        
        local rname = minetest.registered_aliases[entry.name] or entry.name
        
        -- Ignore plants
        local is_plant = rname:find("^flowers:") or 
                         rname:find("^butterflies:") or 
                         rname:find("^default:grass_") or 
                         rname:find("^default:fern_") or 
                         rname:find("^default:bush_") or 
                         rname:find("^default:dry_shrub")
                         
        if not is_plant then
            if entry.name == "default:bookshelf" then
                table.insert(spawn_points, {x = world_x, y = world_y, z = world_z})
                minetest.set_node(pos, {name = "air"})
            else
                local param2 = rotate_param2(entry.name, entry.param2 or 0, rot)
                
                -- Calculate foundation filling before placing the node
                local col_key = entry.x .. "," .. entry.z
                local fill_down_to = nil
                if entry.y == min_y_map[col_key] then
                    local gy = get_cached_ground(world_x, world_z)
                    if world_y > gy + 1 then
                        local is_fillable = (rname == "enclave:wall_block") or
                                            (rname == "default:silver_sandstone_block") or
                                            (rname == "default:obsidian") or
                                            (rname == "stairs:slab_obsidian") or
                                            (rname == "enclave:chainlink") or
                                            (rname == "enclave:chainlink_barbwire") or
                                            (rname == "default:silver_sand")
                        if is_fillable then
                            fill_down_to = gy + 1
                        end
                    end
                end
                
                -- Place block
                minetest.set_node(pos, {
                    name = entry.name,
                    param1 = entry.param1 or 0,
                    param2 = param2,
                })
                
                -- Place foundation downwards if needed
                if fill_down_to then
                    for fill_y = world_y - 1, fill_down_to, -1 do
                        minetest.set_node({x = world_x, y = fill_y, z = world_z}, {name = entry.name})
                    end
                end

                -- Set metadata
                if entry.meta then
                    local meta = minetest.get_meta(pos)
                    if entry.meta.fields then
                        for k, v in pairs(entry.meta.fields) do
                            meta:set_string(k, v)
                        end
                    end
                    if entry.meta.inventory then
                        local inv = meta:get_inventory()
                        for listname, list in pairs(entry.meta.inventory) do
                            inv:set_size(listname, #list)
                            for idx, item in ipairs(list) do
                                inv:set_stack(listname, idx, item)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Places a corner segment (adapting to local ground level column-by-column and filling foundations)
local function place_corner_segment(center, x_off, z_off, rot)
    local ground_cache = {}
    local function get_cached_ground(wx, wz)
        local key = wx .. "," .. wz
        if not ground_cache[key] then
            ground_cache[key] = get_ground_level(wx, wz, center.y)
        end
        return ground_cache[key]
    end

    -- Pre-populate ground cache for all columns in this segment
    for _, entry in ipairs(schem_grenzecke) do
        local rx, rz = rotate_point(entry.x, entry.z, 37, 37, rot)
        local world_x = center.x + x_off + rx
        local world_z = center.z + z_off + rz
        get_cached_ground(world_x, world_z)
    end

    -- First pass: Clear columns from gy + 1 up to gy + 25
    local cleared_cols = {}
    for _, entry in ipairs(schem_grenzecke) do
        local rx, rz = rotate_point(entry.x, entry.z, 37, 37, rot)
        local world_x = center.x + x_off + rx
        local world_z = center.z + z_off + rz
        local key = world_x .. "," .. world_z
        if not cleared_cols[key] then
            local gy = get_cached_ground(world_x, world_z)
            for y = gy + 1, gy + 25 do
                minetest.set_node({x = world_x, y = y, z = world_z}, {name = "air"})
            end
            cleared_cols[key] = true
        end
    end

    -- Find the minimum Y for each local (x, z)
    local min_y_map = {}
    for _, entry in ipairs(schem_grenzecke) do
        local col_key = entry.x .. "," .. entry.z
        if not min_y_map[col_key] or entry.y < min_y_map[col_key] then
            min_y_map[col_key] = entry.y
        end
    end

    -- Second pass: Place nodes and fill foundations
    for _, entry in ipairs(schem_grenzecke) do
        local rx, rz = rotate_point(entry.x, entry.z, 37, 37, rot)
        local world_x = center.x + x_off + rx
        local world_z = center.z + z_off + rz
        
        local base_y = get_cached_ground(world_x, world_z) + 2
        local world_y = base_y + entry.y
        local pos = {x = world_x, y = world_y, z = world_z}
        
        local rname = minetest.registered_aliases[entry.name] or entry.name
        
        -- Ignore plants
        local is_plant = rname:find("^flowers:") or 
                         rname:find("^butterflies:") or 
                         rname:find("^default:grass_") or 
                         rname:find("^default:fern_") or 
                         rname:find("^default:bush_") or 
                         rname:find("^default:dry_shrub")
                         
        if not is_plant then
            local param2 = rotate_param2(entry.name, entry.param2 or 0, rot)
            
            -- Calculate foundation filling before placing the node
            local col_key = entry.x .. "," .. entry.z
            local fill_down_to = nil
            if entry.y == min_y_map[col_key] then
                local gy = get_cached_ground(world_x, world_z)
                if world_y > gy + 1 then
                    local is_fillable = (rname == "enclave:wall_block") or
                                        (rname == "enclave:chainlink") or
                                        (rname == "enclave:chainlink_barbwire")
                    if is_fillable then
                        fill_down_to = gy + 1
                    end
                end
            end
            
            -- Place block
            minetest.set_node(pos, {
                name = entry.name,
                param1 = entry.param1 or 0,
                param2 = param2,
            })
            
            -- Place foundation downwards if needed
            if fill_down_to then
                for fill_y = world_y - 1, fill_down_to, -1 do
                    minetest.set_node({x = world_x, y = fill_y, z = world_z}, {name = entry.name})
                end
            end

            -- Set metadata
            if entry.meta then
                local meta = minetest.get_meta(pos)
                if entry.meta.fields then
                    for k, v in pairs(entry.meta.fields) do
                        meta:set_string(k, v)
                    end
                end
                if entry.meta.inventory then
                    local inv = meta:get_inventory()
                    for listname, list in pairs(entry.meta.inventory) do
                        inv:set_size(listname, #list)
                        for idx, item in ipairs(list) do
                            inv:set_stack(listname, idx, item)
                        end
                    end
                end
            end
        end
    end
end

-- Main generator function
local function generate_enclave(center)
    local spawn_points = {}
    local W = 122
    
    -- 1. Corners (placed contour-adaptive)
    place_corner_segment(center, W - 36, -W, 0)
    place_corner_segment(center, -W, -W, 270)
    place_corner_segment(center, -W, W - 36, 180)
    place_corner_segment(center, W - 36, W - 36, 90)
    
    -- 2. Straight wall segments (placed contour-adaptive)
    place_straight_segment(center, W - 30, -86, 0, spawn_points)
    place_straight_segment(center, W - 30, 0, 0, spawn_points)
    
    place_straight_segment(center, 0, W - 30, 90, spawn_points)
    place_straight_segment(center, -86, W - 30, 90, spawn_points)
    
    place_straight_segment(center, -W, 0, 180, spawn_points)
    place_straight_segment(center, -W, -86, 180, spawn_points)
    
    place_straight_segment(center, -86, -W, 270, spawn_points)
    place_straight_segment(center, 0, -W, 270, spawn_points)
    
    -- Persist active enclave center
    table.insert(enclave.active_enclaves, {x = center.x, z = center.z})
    STORAGE:set_string("active_enclaves", minetest.serialize(enclave.active_enclaves))
    
    -- Spawn NPCs at spawn points (bookshelf positions)
    for _, sp in ipairs(spawn_points) do
        local spawn_pos = {x = sp.x, y = sp.y + 0.5, z = sp.z}
        local obj = minetest.add_entity(spawn_pos, "enclave:npc")
        if obj then
            local lua_ent = obj:get_luaentity()
            if lua_ent then
                lua_ent.enclave_center = {x = center.x, z = center.z}
            end
        end
    end
end

-- Register Enclave Core Block
minetest.register_node("enclave:enclave", {
    description = S("Enclave Generator Core"),
    tiles = {"wall-block-front-and-back.png^default_mese_block.png"},
    is_ground_content = false,
    groups = {cracky = 1, level = 3},
    sounds = stone_sounds,
    stack_max = 9,
    
    after_place_node = function(pos, placer, itemstack, pointed_thing)
        local placer_name = placer and placer:get_player_name() or "Unknown"
        minetest.chat_send_all("[Enclave] " .. placer_name .. " placed an Enclave Core at (" .. pos.x .. ", " .. pos.y .. ", " .. pos.z .. ")! Emerging area...")
        
        -- Emerge a 260x260 area around the core
        local p1 = {x = pos.x - 130, y = pos.y - 80, z = pos.z - 130}
        local p2 = {x = pos.x + 130, y = pos.y + 80, z = pos.z + 130}
        
        minetest.emerge_area(p1, p2, function(blockpos, action, calls_remaining, param)
            if calls_remaining == 0 then
                minetest.chat_send_all("[Enclave] Emerge complete. Generating structure...")
                generate_enclave(pos)
                minetest.chat_send_all("[Enclave] Fortress generation complete!")
            end
        end)
    end
})
