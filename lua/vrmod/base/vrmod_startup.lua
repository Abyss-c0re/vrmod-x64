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
    --- LASER POINTER ---
    -- Default laser color
    local laserColor = Color(255, 0, 0, 255)
    -- Custom laser beam material with vertex color support
    local LaserMaterial = Material("cable/red") -- fallback
    do
        local matData = {
            ["$basetexture"] = "color/white",
            ["$additive"] = "1", -- Glowing effect
            ["$vertexcolor"] = "1", -- Use per-vertex color
            ["$vertexalpha"] = "1", -- Use per-vertex alpha
            ["$nocull"] = "1", -- Make it visible from both sides
            ["$ignorez"] = "0", -- Depth-aware (optional)
        }

        local success, customMat = pcall(CreateMaterial, "CustomLaserMaterial", "UnlitGeneric", matData)
        if success and customMat then LaserMaterial = customMat end
    end

    -- Glow sprite material
    local GlowSprite = Material("sprites/glow04_noz")
    -- Update laserColor from convar string
    local function UpdateLaserColor(colorString)
        local r, g, b, a = string.match(colorString, "(%d+),(%d+),(%d+),(%d+)")
        if not (r and g and b and a) then return end
        laserColor = Color(tonumber(r), tonumber(g), tonumber(b), tonumber(a))
    end

    -- ConVar listener for dynamic updates
    vrmod.AddCallbackedConvar("vrmod_laser_color", nil, "255,0,0,255", nil, "", nil, nil, nil, function(newValue) UpdateLaserColor(newValue) end)
    -- Flicker width for beam animation
    local function getFlickerWidth()
        return 0.05 + math.abs(math.sin(CurTime() * 40)) * 0.05
    end

    -- Beam + glow rendering
    local function drawLaser()
        if not g_VR.viewModelMuzzle or g_VR.menuFocus then return end
        local startPos = g_VR.viewModelMuzzle.Pos
        local dir = g_VR.viewModelMuzzle.Ang:Forward()
        local endPos = startPos + dir * 10000
        local tr = util.TraceLine({
            start = startPos,
            endpos = endPos,
            filter = LocalPlayer(),
        })

        local function ScaleAlpha(col, scale)
            return Color(col.r, col.g, col.b, math.Clamp(col.a * scale, 0, 255))
        end

        -- Draw laser beam
        render.SetMaterial(LaserMaterial)
        render.DrawBeam(startPos, tr.HitPos, getFlickerWidth(), 0, 1, laserColor)
        -- Draw muzzle glow (slightly smaller)
        render.SetMaterial(GlowSprite)
        render.DrawSprite(startPos, 3, 3, laserColor)
        -- Draw hit glow if beam hits something
        if tr.Hit then render.DrawSprite(tr.HitPos + tr.HitNormal * 1, 8, 8, ScaleAlpha(laserColor, 1.2)) end
    end

    local function setLaserEnabled(enabled)
        if enabled then
            hook.Add("PostDrawTranslucentRenderables", "vr_laserpointer", drawLaser)
        else
            hook.Remove("PostDrawTranslucentRenderables", "vr_laserpointer")
        end

        -- Persist state in convar
        RunConsoleCommand("vrmod_laserpointer", enabled and "1" or "0")
    end

    -- Console command to toggle laser
    concommand.Add("vrmod_togglelaserpointer", function()
        local enabled = GetConVar("vrmod_laserpointer"):GetBool()
        setLaserEnabled(not enabled)
    end)

    -- Activate laser if convar is set on VR start
    hook.Add("VRMod_Start", "laserOn", function()
        timer.Simple(0.1, function()
            if GetConVar("vrmod_laserpointer"):GetBool() then setLaserEnabled(true) end
            -- Force update laser color from current convar value
            local laserColorConvar = GetConVar("vrmod_laser_color")
            if laserColorConvar then UpdateLaserColor(laserColorConvar:GetString()) end
        end)
    end)

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
    hook.Add("GravGunOnPickedUp", "VR_TrackHeldEntity", function(ply, ent)
        if not vrmod.IsPlayerInVR(ply) then return end
        -- Store held entity
        ply.VRHeldEnt = ent
        -- Add Think hook to apply rotation every frame
        hook.Add("Think", "VR_ApplyRotation_" .. ply:SteamID(), function()
            if not IsValid(ply) or not IsValid(ply.VRHeldEnt) then
                -- Remove hook if player or entity is invalid
                hook.Remove("Think", "VR_ApplyRotation_" .. ply:SteamID())
                return
            end

            local phys = ply.VRHeldEnt:GetPhysicsObject()
            if IsValid(phys) then
                phys:SetAngleVelocityInstantaneous(Vector(0, 0, 0))
                phys:SetAngles(vrmod.GetRightHandAng(ply))
            else
                ply.VRHeldEnt:SetAngles(vrmod.GetRightHandAng(ply))
            end
        end)
    end)

    hook.Add("GravGunOnDropped", "VR_ClearHeldEntity", function(ply, ent)
        if ply.VRHeldEnt == ent then
            ply.VRHeldEnt = nil
            hook.Remove("Think", "VR_ApplyRotation_" .. ply:SteamID())
        end
    end)
end