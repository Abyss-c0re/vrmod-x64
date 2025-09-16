if CLIENT then
    local convars = vrmod.GetConvars()
    vrmod.AddCallbackedConvar("vrmod_configversion", nil, "5")
    if convars.vrmod_configversion:GetString() ~= convars.vrmod_configversion:GetDefault() then
        timer.Simple(1, function()
            for k, v in pairs(convars) do
                pcall(function() v:Revert() end)
            end
        end)
    end

    vrmod.AddCallbackedConvar("vrmod_althead", nil, "0")
    vrmod.AddCallbackedConvar("vrmod_autostart", nil, "0")
    vrmod.AddCallbackedConvar("vrmod_scale", nil, "32.7")
    vrmod.AddCallbackedConvar("vrmod_heightmenu", nil, "1")
    vrmod.AddCallbackedConvar("vrmod_floatinghands", nil, "0")
    vrmod.AddCallbackedConvar("vrmod_desktopview", nil, "3")
    vrmod.AddCallbackedConvar("vrmod_useworldmodels", nil, "0")
    vrmod.AddCallbackedConvar("vrmod_laserpointer", nil, "0")
    vrmod.AddCallbackedConvar("vrmod_znear", nil, "1")
    vrmod.AddCallbackedConvar("vrmod_renderoffset", nil, "1")
    vrmod.AddCallbackedConvar("vrmod_viewscale", nil, "1.0")
    vrmod.AddCallbackedConvar("vrmod_fovscale_x", nil, "1")
    vrmod.AddCallbackedConvar("vrmod_fovscale_y", nil, "1")
    vrmod.AddCallbackedConvar("vrmod_scalefactor", nil, "1")
    vrmod.AddCallbackedConvar("vrmod_eyescale", nil, "0.5")
    vrmod.AddCallbackedConvar("vrmod_verticaloffset", nil, "0")
    vrmod.AddCallbackedConvar("vrmod_horizontaloffset", nil, "0")
    vrmod.AddCallbackedConvar("vrmod_oldcharacteryaw", nil, "0")
    vrmod.AddCallbackedConvar("vrmod_controlleroffset_x", nil, "-15")
    vrmod.AddCallbackedConvar("vrmod_controlleroffset_y", nil, "-1")
    vrmod.AddCallbackedConvar("vrmod_controlleroffset_z", nil, "5")
    vrmod.AddCallbackedConvar("vrmod_controlleroffset_pitch", nil, "50")
    vrmod.AddCallbackedConvar("vrmod_controlleroffset_yaw", nil, "0")
    vrmod.AddCallbackedConvar("vrmod_controlleroffset_roll", nil, "0")
    vrmod.AddCallbackedConvar("vrmod_postprocess", nil, "0", nil, nil, nil, nil, tobool, function(val) if g_VR.view then g_VR.view.dopostprocess = val end end)
    ----------------------------------------------------------------------------
    concommand.Add("vrmod_start", function(ply, cmd, args)
        if vgui.CursorVisible() then print("vrmod: attempting startup when game is unpaused") end
        timer.Create("vrmod_start", 0.1, 0, function()
            if not vgui.CursorVisible() then
                timer.Remove("vrmod_start")
                VRUtilClientStart()
            end
        end)
    end)

    concommand.Add("vrmod_exit", function(ply, cmd, args)
        if timer.Exists("vrmod_start") then timer.Remove("vrmod_start") end
        if isfunction(VRUtilClientExit) then VRUtilClientExit() end
    end)

    concommand.Add("vrmod_reset", function(ply, cmd, args)
        for k, v in pairs(vrmod.GetConvars()) do
            pcall(function() v:Revert() end)
        end

        hook.Call("VRMod_Reset")
    end)

    concommand.Add("vrmod_info", function()
        -- simple banner and key–value printer
        local function banner()
            print(("="):rep(72))
        end

        local function kv(label, val)
            print(string.format("| %-30s %s", label, val))
        end

        banner()
        -- General info
        kv("Addon Version:", vrmod.GetVersion())
        kv("Module Version:", vrmod.GetModuleVersion())
        kv("GMod Version:", VERSION .. " (Branch: " .. BRANCH .. ")")
        kv("Operating System:", system.IsWindows() and "Windows" or system.IsLinux() and "Linux" or system.IsOSX() and "OSX" or "Unknown")
        kv("Server Type:", game.SinglePlayer() and "Single Player" or "Multiplayer")
        kv("Server Name:", GetHostName())
        kv("Server Address:", game.GetIPAddress())
        kv("Gamemode:", GAMEMODE_NAME)
        -- Addon counts
        local wcount = 0
        for _, a in ipairs(engine.GetAddons()) do
            if a.mounted then wcount = wcount + 1 end
        end

        kv("Workshop Addons:", wcount)
        local _, folders = file.Find("addons/*", "GAME")
        local blacklist = {
            checkers = true,
            chess = true,
            common = true,
            go = true,
            hearts = true,
            spades = true
        }

        local lcount = 0
        for _, name in ipairs(folders) do
            if not blacklist[name] then lcount = lcount + 1 end
        end

        kv("Legacy Addons:", lcount)
        print("|" .. ("-"):rep(70))
        -- CRC of data/vrmod and lua/bin
        local function dumpCRC(path)
            for _, entry in ipairs(file.Find(path .. "/*", "GAME")) do
                local full = path .. "/" .. entry
                if file.IsDir(full, "GAME") then
                    dumpCRC(full)
                else
                    local crc = util.CRC(file.Read(full, "GAME") or "")
                    kv(full, string.format("%X", crc))
                end
            end
        end

        dumpCRC("data/vrmod")
        print("|" .. ("-"):rep(70))
        dumpCRC("lua/bin")
        print("|" .. ("-"):rep(70))
        -- Convar list
        local names = {}
        for _, cv in pairs(convars) do
            names[#names + 1] = cv:GetName()
        end

        table.sort(names)
        for _, n in ipairs(names) do
            local cv = GetConVar(n)
            local val = cv:GetString()
            kv(n, val .. (val ~= cv:GetDefault() and " *" or ""))
        end

        banner()
    end)

    concommand.Add("vrmod", function(ply, cmd, args)
        if vgui.CursorVisible() then print("vrmod: menu will open when game is unpaused") end
        timer.Create("vrmod_open_menu", 0.1, 0, function()
            if not vgui.CursorVisible() then
                VRUtilOpenMenu()
                timer.Remove("vrmod_open_menu")
            end
        end)
    end)
elseif SERVER then
    -- Mark player on spawn
    hook.Add("PlayerSpawn", "VRMarkPlayerForEmptyWeapon", function(ply) if g_VR and g_VR[ply:SteamID()] then ply:SetNWBool("vr_switch_empty", true) end end)
    -- Switch weapon in Think hook
    hook.Add("Think", "VRSwitchToEmptyWeapon", function()
        for _, ply in ipairs(player.GetAll()) do
            if ply:GetNWBool("vr_switch_empty") and IsValid(ply) and ply:Alive() then
                if ply:HasWeapon("weapon_vrmod_empty") then
                    ply:SelectWeapon("weapon_vrmod_empty")
                    ply:SetNWBool("vr_switch_empty", false)
                end
            end
        end
    end)

    hook.Add("EntityFireBullets", "VRMod_NoShootOwnVehicle", function(ply, data)
        if not ply:IsPlayer() or not ply:InVehicle() then return end
        local veh = ply:GetVehicle()
        if not IsValid(veh) then return end
        -- Walk to top-level vehicle
        while IsValid(veh:GetParent()) do
            veh = veh:GetParent()
        end

        -- Build ignore list (vehicle + welded children)
        local ignore = {veh}
        for _, c in ipairs(veh:GetChildren()) do
            table.insert(ignore, c)
        end

        if constraint then
            for _, c in ipairs(constraint.GetTable(veh) or {}) do
                if IsValid(c.Ent1) then table.insert(ignore, c.Ent1) end
                if IsValid(c.Ent2) then table.insert(ignore, c.Ent2) end
            end
        end

        -- Merge with existing IgnoreEntity
        if not data.IgnoreEntity then
            data.IgnoreEntity = ignore
        elseif type(data.IgnoreEntity) == "Entity" then
            data.IgnoreEntity = {data.IgnoreEntity}
            for _, e in ipairs(ignore) do
                table.insert(data.IgnoreEntity, e)
            end
        elseif type(data.IgnoreEntity) == "table" then
            for _, e in ipairs(ignore) do
                table.insert(data.IgnoreEntity, e)
            end
        end
        return true, data
    end)

    -- Shared VRMod Vehicle Aim Fix with debug prints
    local _vrVehicleAimPatched = false
    local function PatchVRVehicleAim()
        if _vrVehicleAimPatched then return end
        _vrVehicleAimPatched = true
        local plyMeta = FindMetaTable("Player")
        if not plyMeta then return end
        local HAND_CORRECTION = Angle(2, 6, 0) -- adjust after testing
        local _GetAimVector = plyMeta.GetAimVector
        function plyMeta:GetAimVector()
            -- Only override for VR players in vehicles
            if self:InVehicle() then
                local vrData = g_VR and g_VR[self:SteamID()]
                -- Prefer muzzle if available
                if vrData and vrData.muzzlePos and vrData.muzzleAng then return vrData.muzzleAng:Forward() end
                -- Fallback to hand pose
                if vrmod and vrmod.GetRightHandPose then
                    local hand = g_VR.tracking.pose_righthand
                    local handPos, handAng = hand.Pos, hand.Ang
                    --= vrmod.GetRightHandPose(self)
                    if handPos and handAng then
                        local dir = (handAng + HAND_CORRECTION):Forward()
                        return dir
                    end
                end
            end
            -- Fallback to normal GetAimVector
            return _GetAimVector(self)
        end
    end

    PatchVRVehicleAim()
end