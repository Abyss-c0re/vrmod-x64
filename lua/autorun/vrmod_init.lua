vrmod = vrmod or {}
vrmod.status = {
    api = false,
    utils = false,
    core = false,
    newtwork = false,
    input = false,
    player = false,
    physics = false,
    pickup = false,
    combat = false,
    ui = false,
}

AddCSLuaFile()
include("vrmod/logger.lua")
include("vrmod/loader.lua")
local subsystemOrder = {"api", "utils", "core", "network", "input", "player", "physics", "pickup", "combat", "ui",}
local baseFolder = "vrmod/"
-- Load subsystems in the order defined above
for _, sub in ipairs(subsystemOrder) do
    local folderPath = baseFolder .. sub
    VRMod_Loader(folderPath)
end

-- ConCommand to print status of all subsystems
concommand.Add("vrmod_status", function(ply, cmd, args)
    print("[VRMod] Subsystem Status:")
    for _, sub in ipairs(subsystemOrder) do
        local status = vrmod.status[sub] and "[Running]" or "[Stopped]"
        print(string.format("%s: %s", string.upper(sub), status))
    end
end)