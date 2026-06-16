-- Enclave mod entrypoint
-- Author: ronrob-lu

enclave = {}

-- Load active enclaves from persistent storage
local STORAGE = minetest.get_mod_storage()
local data = STORAGE:get_string("active_enclaves")
if data ~= "" then
    enclave.active_enclaves = minetest.deserialize(data) or {}
else
    enclave.active_enclaves = {}
end

-- Load submodules
local modpath = minetest.get_modpath("enclave")
dofile(modpath .. "/nodes.lua")
dofile(modpath .. "/mobs.lua")
dofile(modpath .. "/generator.lua")

minetest.log("action", "[Enclave] Mod loaded successfully!")
