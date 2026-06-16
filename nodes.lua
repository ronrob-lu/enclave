-- Nodes and recipes for the enclave mod
local S = minetest.get_translator("enclave")

-- Safe stone sound definition
local stone_sounds = {
    footstep = {name = "default_node_footstep", gain = 0.5},
    dig = {name = "default_node_dig", gain = 0.6},
    dug = {name = "default_node_dug", gain = 0.8},
    place = {name = "default_node_place", gain = 1.0},
}

-- ----------------------------------------------------
-- 1. Berlin Wall Nodes
-- ----------------------------------------------------

-- Search Light Block (emits light with intensity 10)
minetest.register_node("enclave:search_light", {
    description = S("Search Light"),
    tiles = {"search-light.png"},
    is_ground_content = false,
    light_source = 10,
    groups = {cracky = 3, not_in_creative_inventory = 0},
    sounds = stone_sounds,
    stack_max = 99,
})

-- Fence Site Block (for tower tops)
minetest.register_node("enclave:fence_site", {
    description = S("Fence Site"),
    tiles = {"fence-site.png"},
    is_ground_content = false,
    groups = {cracky = 3, fence = 1},
    sounds = stone_sounds,
    use_texture_alpha = "clip",
    stack_max = 99,
})

-- Grenzmauer 75 Top Block (semi-circular concrete pipe top)
minetest.register_node("enclave:grenzmauer_top", {
    description = S("Grenzmauer 75 Top (Round Pipe)"),
    tiles = {
        "round-wall-top-sites.png",  -- top
        "round-wall-top-sites.png",  -- bottom
        "wall-block-side-with-round-flat.png",  -- side
        "wall-block-side-with-round-flat.png",  -- side
        "wall-block-front-and-back-with-round-flat.png",  -- front
        "wall-block-front-and-back-with-round-flat.png",  -- back
    },
    is_ground_content = false,
    groups = {cracky = 3},
    sounds = stone_sounds,
    use_texture_alpha = "clip",
    paramtype2 = "facedir",
    on_place = function(itemstack, placer, pointed_thing)
        local node_under = minetest.get_node_or_nil(pointed_thing.under)
        if not node_under then
            return itemstack
        end
        
        -- Get the direction the player is facing
        local dir = placer:get_look_dir()
        local yaw = math.deg(math.atan2(dir.x, -dir.z))
        
        -- Normalize yaw to 0-360 range
        if yaw < 0 then
            yaw = yaw + 360
        end
        
        -- Restrict to 2 horizontal directions only (N/S or E/W)
        local facedir
        if (yaw >= 315 or yaw < 45) or (yaw >= 135 and yaw < 225) then
            -- North/South direction
            if yaw >= 315 or yaw < 45 then
                facedir = 0  -- North
            else
                facedir = 2  -- South
            end
        else
            -- East/West direction
            if yaw >= 45 and yaw < 135 then
                facedir = 1  -- East
            else
                facedir = 3  -- West
            end
        end
        
        local pos = pointed_thing.above
        local node = {name = "enclave:grenzmauer_top", param2 = facedir}
        
        if minetest.settings:get_bool("creative_mode") or minetest.setting_getbool("creative_mode") then
            minetest.set_node(pos, node)
        else
            minetest.set_node(pos, node)
            itemstack:take_item(1)
        end
        
        return itemstack
    end,
    on_rotate = function(pos, node, user, mode)
        local current_param2 = node.param2
        local dir = user:get_look_dir()
        local yaw = math.deg(math.atan2(dir.x, -dir.z))
        
        -- Normalize yaw to 0-360 range
        if yaw < 0 then
            yaw = yaw + 360
        end
        
        -- Determine which of the 2 allowed orientations to use based on player facing
        local new_facedir
        if (yaw >= 315 or yaw < 45) or (yaw >= 135 and yaw < 225) then
            -- Player facing N/S - use N/S orientation
            if current_param2 == 0 or current_param2 == 2 then
                new_facedir = current_param2  -- Already N/S, keep it
            elseif yaw >= 315 or yaw < 45 then
                new_facedir = 0  -- Switch to North
            else
                new_facedir = 2  -- Switch to South
            end
        else
            -- Player facing E/W - use E/W orientation
            if current_param2 == 1 or current_param2 == 3 then
                new_facedir = current_param2  -- Already E/W, keep it
            elseif yaw >= 45 and yaw < 135 then
                new_facedir = 1  -- Switch to East
            else
                new_facedir = 3  -- Switch to West
            end
        end
        
        node.param2 = new_facedir
        minetest.set_node(pos, node)
        return true
    end,
})

-- Standard Wall Block (normal stone block on all sides)
minetest.register_node("enclave:wall_block", {
    description = S("Berlin Wall Block"),
    tiles = {"wall-block-front-and-back.png"},
    is_ground_content = false,
    groups = {cracky = 3},
    sounds = stone_sounds,
    stack_max = 99,
})

-- ----------------------------------------------------
-- 2. Barbwire Fence Nodes
-- ----------------------------------------------------

-- Helper function to create fence node definitions
local function create_fence_node(name, def)
    minetest.register_node("enclave:" .. name, {
        description = def.description,
        drawtype = "nodebox",
        paramtype = "light",
        paramtype2 = "facedir",
        sunlight_propagates = true,
        walkable = true,
        pointable = true,
        diggable = true,
        climbable = false,
        buildable_to = false,
        floodable = true,
        is_ground_content = false,
        groups = {
            fence = 1,
            cracky = 1,
            oddly_breakable_by_hand = 2,
            level = 2
        },
        sounds = {
            footstep = {name = "metal_footstep", gain = 0.5},
            dig = {name = "metal_dig", gain = 0.5},
            place = {name = "metal_place", gain = 0.5},
        },
        tiles = def.tiles,
        use_texture_alpha = def.use_texture_alpha or "clip",
        node_box = def.node_box,
        selection_box = def.selection_box,
        on_rotate = screwdriver and screwdriver.rotate_face or nil,
    })
end

-- Node box definitions for 2-block high fence (Y ranges from -0.5 to 1.5)
local chainlink_nodebox = {
    {-0.05, -0.5, -0.05, 0.05, 1.5, 0.05},
}

local barbwire_nodebox = {
    {-0.5, 1.2, -0.05, 0.5, 1.25, 0.05},
    {-0.5, 1.0, -0.05, 0.5, 1.05, 0.05},
    {-0.5, 0.8, -0.05, 0.5, 0.85, 0.05},
    {-0.5, 1.2, -0.1, -0.4, 1.2, 0.1},
    {-0.3, 1.2, -0.1, -0.2, 1.2, 0.1},
    {-0.1, 1.2, -0.1, 0.0, 1.2, 0.1},
    {0.1, 1.2, -0.1, 0.2, 1.2, 0.1},
    {0.3, 1.2, -0.1, 0.4, 1.2, 0.1},
}

local combined_nodebox = {
    {-0.05, -0.5, -0.05, 0.05, 0.75, 0.05},
    {-0.5, 1.2, -0.05, 0.5, 1.25, 0.05},
    {-0.5, 1.0, -0.05, 0.5, 1.05, 0.05},
    {-0.5, 0.8, -0.05, 0.5, 0.85, 0.05},
}

local chainlink_selectionbox = {-0.1, -0.5, -0.1, 0.1, 1.5, 0.1}
local barbwire_selectionbox = {-0.5, 0.75, -0.1, 0.5, 1.5, 0.1}
local combined_selectionbox = {-0.1, -0.5, -0.1, 0.1, 1.5, 0.1}

-- Register Chainlink Fence Node
create_fence_node("chainlink", {
    description = S("Chainlink Fence"),
    tiles = {
        "chainlink-32px-32px.png",
    },
    use_texture_alpha = "clip",
    node_box = chainlink_nodebox,
    selection_box = chainlink_selectionbox,
})

-- Register Barbwire Fence Node
create_fence_node("barbwire", {
    description = S("Barbwire Strand"),
    tiles = {
        "barbwire-32px-32px.png",
    },
    use_texture_alpha = "clip",
    node_box = barbwire_nodebox,
    selection_box = barbwire_selectionbox,
})

-- Register Combined Chainlink + Barbwire Fence Node
create_fence_node("chainlink_barbwire", {
    description = S("Chainlink Fence with Barbwire"),
    tiles = {
        "chainlink-32px-32px.png^barbwire-32px-32px.png",
    },
    use_texture_alpha = "clip",
    node_box = combined_nodebox,
    selection_box = combined_selectionbox,
})

-- ----------------------------------------------------
-- 3. Crafting Recipes
-- ----------------------------------------------------

minetest.register_craft({
    output = "enclave:chainlink 4",
    recipe = {
        {"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
        {"default:steel_ingot", "", "default:steel_ingot"},
        {"default:steel_ingot", "", "default:steel_ingot"},
    }
})

minetest.register_craft({
    output = "enclave:barbwire 4",
    recipe = {
        {"default:steel_ingot", "default:stick", "default:steel_ingot"},
        {"default:steel_ingot", "default:stick", "default:steel_ingot"},
        {"", "", ""},
    }
})

minetest.register_craft({
    output = "enclave:chainlink_barbwire 4",
    recipe = {
        {"default:steel_ingot", "default:stick", "default:steel_ingot"},
        {"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
        {"default:steel_ingot", "", "default:steel_ingot"},
    }
})

minetest.register_craft({
    type = "fuel",
    recipe = "enclave:chainlink",
    burntime = 2,
})

minetest.register_craft({
    type = "fuel",
    recipe = "enclave:barbwire",
    burntime = 2,
})

minetest.register_craft({
    type = "fuel",
    recipe = "enclave:chainlink_barbwire",
    burntime = 2,
})

-- ----------------------------------------------------
-- 4. Compatibility Aliases (Map & Schematic resolution)
-- ----------------------------------------------------
minetest.register_alias("berlin_wall:search_light", "enclave:search_light")
minetest.register_alias("berlin_wall:fence_site", "enclave:fence_site")
minetest.register_alias("berlin_wall:grenzmauer_top", "enclave:grenzmauer_top")
minetest.register_alias("berlin_wall:wall_block", "enclave:wall_block")
minetest.register_alias("barbwire_fence:chainlink", "enclave:chainlink")
minetest.register_alias("barbwire_fence:barbwire", "enclave:barbwire")
minetest.register_alias("barbwire_fence:chainlink_barbwire", "enclave:chainlink_barbwire")
