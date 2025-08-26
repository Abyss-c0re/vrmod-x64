vrmod = vrmod or {}
vrmod.status = {
    api = false,
    utils = false,
    core = false,
    network = false,
    input = false,
    player = false,
    physics = false,
    pickup = false,
    combat = false,
    ui = false,
}

local subsystemOrder = {"api", "utils", "core", "network", "input", "player", "physics", "pickup", "combat", "ui"}
local baseFolder = "vrmod/"
local function LoadAllSubsystems()
    for _, sub in ipairs(subsystemOrder) do
        local folderPath = baseFolder .. sub
        if VRMod_Loader then
            VRMod_Loader(folderPath)
        else
            print("[VRMod] VRMod_Loader missing for subsystem:", sub)
        end
    end
end

-- Fire the hook once loader.lua has completed
hook.Add("VRMod_PostLoader", "LoadSubsystems", LoadAllSubsystems)
-- Force include logger first
if SERVER then AddCSLuaFile("vrmod/logger.lua") end
include("vrmod/logger.lua")
-- Then loader
if SERVER then AddCSLuaFile("vrmod/loader.lua") end
include("vrmod/loader.lua")
hook.Run("VRMod_PostLoader")
-- ConCommand to print subsystem status
concommand.Add("vrmod_status", function(ply, cmd, args)
    print("[VRMod] Subsystem Status:")
    for _, sub in ipairs(subsystemOrder) do
        local status = vrmod.status[sub] and "[Running]" or "[Stopped]"
        print(string.format("%s: %s", string.upper(sub), status))
    end
end)