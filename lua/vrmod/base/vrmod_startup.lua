if SERVER then return end
local convars = vrmod.GetConvars()
vrmod.AddCallbackedConvar("vrmod_configversion", nil, "5")
if convars.vrmod_configversion:GetString() ~= convars.vrmod_configversion:GetDefault() then
    timer.Simple(1, function()
        for k, v in pairs(convars) do
            pcall(function()
                v:Revert() --reverting certain convars makes error
            end)
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
vrmod.AddCallbackedConvar("vrmod_oldcharacteryaw", nil, "0")
vrmod.AddCallbackedConvar("vrmod_controlleroffset_x", nil, "-15")
vrmod.AddCallbackedConvar("vrmod_controlleroffset_y", nil, "-1")
vrmod.AddCallbackedConvar("vrmod_controlleroffset_z", nil, "5")
vrmod.AddCallbackedConvar("vrmod_controlleroffset_pitch", nil, "50")
vrmod.AddCallbackedConvar("vrmod_controlleroffset_yaw", nil, "0")
vrmod.AddCallbackedConvar("vrmod_controlleroffset_roll", nil, "0")
vrmod.AddCallbackedConvar("vrmod_postprocess", nil, "0", nil, nil, nil, nil, tobool, function(val) if g_VR.view then g_VR.view.dopostprocess = val end end)
vrmod.AddCallbackedConvar("vrmod_pickup_limit", nil, 1, FCVAR_REPLICATED + FCVAR_NOTIFY + FCVAR_ARCHIVE, "", 0, 3, tonumber)
vrmod.AddCallbackedConvar("vrmod_pickup_range", nil, 1.2, FCVAR_REPLICATED + FCVAR_ARCHIVE, "", 0.0, 999.0, tonumber)
vrmod.AddCallbackedConvar("vrmod_pickup_weight", nil, 150, FCVAR_REPLICATED + FCVAR_ARCHIVE, "", 0, 10000, tonumber)
vrmod.AddCallbackedConvar("vrmod_seatedoffset", nil, "0", nil, nil, nil, nil, tonumber, function(val) updateOffsetHook() end)
vrmod.AddCallbackedConvar("vrmod_seated", nil, "0", nil, nil, nil, nil, tobool, function(val) updateOffsetHook() end)
local matLaser = Material("cable/redlaser")
local function drawLaser()
    if g_VR.viewModelMuzzle and not g_VR.menuFocus then
        render.SetMaterial(matLaser)
        render.DrawBeam(g_VR.viewModelMuzzle.Pos, g_VR.viewModelMuzzle.Pos + g_VR.viewModelMuzzle.Ang:Forward() * 10000, 1, 0, 1, Color(255, 255, 255, 255))
    end
end

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

local function setLaserEnabled(enabled)
    if enabled then
        hook.Add("PostDrawTranslucentRenderables", "vr_laserpointer", drawLaser)
        if IsValid(LocalPlayer()) then
            LocalPlayer():ConCommand("vrmod_laserpointer 1")
        else
            timer.Simple(0, function() if IsValid(LocalPlayer()) then LocalPlayer():ConCommand("vrmod_laserpointer 1") end end)
        end
    else
        hook.Remove("PostDrawTranslucentRenderables", "vr_laserpointer")
        if IsValid(LocalPlayer()) then LocalPlayer():ConCommand("vrmod_laserpointer 0") end
    end
end

concommand.Add("vrmod", function(ply, cmd, args)
    if vgui.CursorVisible() then print("vrmod: menu will open when game is unpaused") end
    timer.Create("vrmod_open_menu", 0.1, 0, function()
        if not vgui.CursorVisible() then
            VRUtilOpenMenu()
            timer.Remove("vrmod_open_menu")
        end
    end)
end)

concommand.Add("vrmod_togglelaserpointer", function()
    local enabled = GetConVar("vrmod_laserpointer"):GetBool()
    setLaserEnabled(not enabled)
end)

hook.Add("VRMod_Start", "laserOn", function()
    timer.Simple(0.1, function() end)
    if convars.vrmod_laserpointer:GetBool() then setLaserEnabled(true) end
end)