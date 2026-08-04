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
        if not self:InVehicle() then return _GetAimVector(self) end
        -- Shared VR data access
        if g_VR then
            if SERVER then
                -- Server: VR state is per-player table
                local vrData = g_VR[self:SteamID()]
                if vrData and vrData.muzzleAng then return vrData.muzzleAng:Forward() end
            else
                -- Client: VR viewmodel muzzle
                if g_VR.viewModelMuzzle and g_VR.viewModelMuzzle.Ang then return g_VR.viewModelMuzzle.Ang:Forward() end
            end
        end

        -- Fallback to right hand pose
        if vrmod and vrmod.GetRightHandPose then
            local hand = g_VR and g_VR.tracking and g_VR.tracking.pose_righthand
            if hand and hand.Pos and hand.Ang then return (hand.Ang + HAND_CORRECTION):Forward() end
        end
        -- Fallback to default
        return _GetAimVector(self)
    end
end

PatchVRVehicleAim()
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
    -- Menu-first: freefloat real MainMenu/GameUI (default launcher path)
    vrmod.AddCallbackedConvar("vrmod_menu_vr", nil, "0", FCVAR_ARCHIVE,
        "1 = menu-first VR: freefloat real MainMenu / GameUI cinema", nil, nil, tobool)
    -- Hub: Cube launcher surface fallback (or force with vrmod_hub 1 alone)
    vrmod.AddCallbackedConvar("vrmod_hub", nil, "0", FCVAR_ARCHIVE,
        "1 = open VR hub after auto-start (fallback; menu-first preferred)", nil, nil, tobool)
    vrmod.AddCallbackedConvar("vrmod_scale", nil, "32.7")
    vrmod.AddCallbackedConvar("vrmod_heightmenu", nil, "1")
    vrmod.AddCallbackedConvar("vrmod_floatinghands", nil, "0")
    -- Used by ArcVR (and worldmodel VM path); must exist or ArcVR PostDrawViewModel nils
    vrmod.AddCallbackedConvar("vrmod_useworldmodels", nil, "0")
    -- 1=none 2=left eye 3=right eye 4=invisible follow camera (broadcast seam)
    vrmod.AddCallbackedConvar("vrmod_desktopview", nil, "3", FCVAR_ARCHIVE,
        "Desktop view: 1=none 2=left 3=right 4=follow camera", 1, 4, tonumber)
    vrmod.AddCallbackedConvar("vrmod_laserpointer", nil, "0")
    vrmod.AddCallbackedConvar("vrmod_znear", nil, "1")
    vrmod.AddCallbackedConvar("vrmod_renderoffset", nil, "1")
    vrmod.AddCallbackedConvar("vrmod_viewscale", nil, "1.0")
    vrmod.AddCallbackedConvar("vrmod_fovscale_x", nil, "1")
    vrmod.AddCallbackedConvar("vrmod_fovscale_y", nil, "1")
    -- Render supersample: multiplies per-eye RT vs raw HMD recommended (1=native, 1.5 crisp, 2.0 heavy).
    -- Requires VR restart. Lua applies SS then clamps SBS ≤ 4096.
    vrmod.AddCallbackedConvar("vrmod_supersample", nil, "1.5", FCVAR_ARCHIVE, "VR render supersample 0.5–2.0 (restart VR)", 0.5, 2.0, tonumber)
    vrmod.AddCallbackedConvar("vrmod_scalefactor", nil, "1", FCVAR_ARCHIVE, "Submit UV scale factor (border crop)", 0.05, 4.0, tonumber)
    -- Synthetic IPD multiplier when eye mode is synthetic (2) or auto falls back.
    -- 1.0 = full headset IPD; 0.5 = half (legacy default). Live while VR active.
    vrmod.AddCallbackedConvar("vrmod_eyescale", nil, "0.5", FCVAR_ARCHIVE,
        "Synthetic eye IPD scale 0–1 (1=full IPD). Used when stereo_eye_mode forces synthetic", 0.0, 1.0, tonumber)
    -- Stereo eye placement (head-tilt / roll warp dial):
    --   0 auto      = OpenXR locateViews eyes if valid, else synthetic head-Right()
    --   1 xr        = force OpenXR eye positions (shared HMD orientation)
    --   2 synthetic = force pure translation along head Right() (best roll test)
    vrmod.AddCallbackedConvar("vrmod_stereo_eye_mode", nil, "0", FCVAR_ARCHIVE,
        "Stereo eyes: 0=auto 1=OpenXR poses 2=synthetic head-Right IPD", 0, 2, tonumber)
    -- Per-eye submit UV (C++ XR_SetSubmitCropMode). NEVER leave FOV_CROP on by default.
    --   0 safe     = full per-eye rect; SBS uses Lua bounds (default, stable)
    --   1 full     = force full-eye UV (debug borders)
    --   2 fov_crop = experimental asymmetric FOV crop (can cross stereo — opt-in only)
    vrmod.AddCallbackedConvar("vrmod_submit_crop", nil, "0", FCVAR_ARCHIVE,
        "Submit UV: 0=safe 1=full 2=fov_crop experimental", 0, 2, tonumber)
    -- Workshop: inverted stereo / "seeing double" (PSVR2 etc.) — swap SBS halves without dual pose truth
    vrmod.AddCallbackedConvar("vrmod_swap_eyes", nil, "0", FCVAR_ARCHIVE, "Swap left/right eye submit halves", nil, nil, tobool)
    vrmod.AddCallbackedConvar("vrmod_verticaloffset", nil, "0", FCVAR_ARCHIVE, "Submit UV vertical offset", -1.0, 1.0, tonumber)
    vrmod.AddCallbackedConvar("vrmod_horizontaloffset", nil, "0", FCVAR_ARCHIVE, "Submit UV horizontal offset", -1.0, 1.0, tonumber)
    vrmod.AddCallbackedConvar("vrmod_oldcharacteryaw", nil, "0")
    vrmod.AddCallbackedConvar("vrmod_postprocess", nil, "0", nil, nil, nil, nil, tobool, function(val) if g_VR.view then g_VR.view.dopostprocess = val end end)
    -- Dual binaries: gmcl_vrmod_xr_* (OpenXR) + gmcl_vrmod_* (OpenVR) may both live in lua/bin.
    -- auto = prefer OpenXR if installed, else OpenVR. Force with openxr|openvr.
    vrmod.AddCallbackedConvar("vrmod_prefer_backend", nil, "auto", FCVAR_ARCHIVE,
        "Native module prefer: auto | openxr | openvr (both DLLs may coexist)", nil, nil, tostring)
    -- mat_queue_mode: engine cvar only (no vrmod_mat_*). VR never SetInt's it —
    -- changing workers mid-session = Illegal termination of CThread.
    -- Desktop window focus: default OFF so HMD play works alt-tabbed / Wayland compositor focus loss.
    vrmod.AddCallbackedConvar("vrmod_require_window_focus", nil, "0", FCVAR_ARCHIVE,
        "1 = pause VR when GMod window unfocused; 0 = keep playing in headset without desktop focus", nil, nil, tobool)
    -- Prefer engine mat_queue_mode (0/1/2). Never SetInt from VR settings mid-map (CThread crash).
    -- User must apply engine mat_queue_mode themselves at a safe time (console before map / after changelevel).
    vrmod.AddCallbackedConvar("vrmod_prefer_mat_queue", nil, "1", FCVAR_ARCHIVE,
        "Preferred mat_queue_mode (display only; apply engine mat_queue_mode at safe idle)", 0, 2, tonumber)
    vrmod.AddCallbackedConvar("vrmod_prefer_mcore", nil, "0", FCVAR_ARCHIVE,
        "Preferred gmod_mcore_test (display only; do not thrash mid-session)", 0, 1, tonumber)
    -- Mode 2: one engine RenderView (left) only — dual nested RenderView races MatQueue workers.
    vrmod.AddCallbackedConvar("vrmod_mq2_single_pass", nil, "1", FCVAR_ARCHIVE,
        "Under mat_queue_mode 2: 1 = single-pass stereo (safer), 0 = dual RenderView (may crash)", nil, nil, tobool)
    vrmod.AddCallbackedConvar("vrmod_skybox", nil, "0", nil, nil, nil, nil, tobool, function(val) RunConsoleCommand("r_3dsky", val and "1" or "0") end)
    vrmod.AddCallbackedConvar("vrmod_controlleroffset_x", nil, "-15")
    vrmod.AddCallbackedConvar("vrmod_controlleroffset_y", nil, "-1")
    vrmod.AddCallbackedConvar("vrmod_controlleroffset_z", nil, "5")
    vrmod.AddCallbackedConvar("vrmod_controlleroffset_pitch", nil, "50")
    vrmod.AddCallbackedConvar("vrmod_controlleroffset_yaw", nil, "0")
    vrmod.AddCallbackedConvar("vrmod_controlleroffset_roll", nil, "0")
    vrmod.AddCallbackedConvar("vrmod_smoothturn", "smoothTurn", "1", nil, nil, nil, nil, tobool)
    vrmod.AddCallbackedConvar("vrmod_smoothturnrate", "smoothTurnRate", "180", nil, nil, nil, nil, tonumber)
    vrmod.AddCallbackedConvar("vrmod_crouchthreshold", "crouchThreshold", "40", nil, nil, nil, nil, tonumber)
    -- Cube locomotion: full-stick auto sprint (Workshop: forced walk / no sprint)
    vrmod.AddCallbackedConvar("vrmod_autosprint", "autoSprint", "1", FCVAR_ARCHIVE, "Auto-sprint when move stick fully deflected", nil, nil, tobool)
    vrmod.AddCallbackedConvar("vrmod_autosprint_threshold", "autoSprintThreshold", "0.82", FCVAR_ARCHIVE, "Stick magnitude for auto-sprint", 0.5, 1.0, tonumber)
    vrmod.AddCallbackedConvar("vrmod_charactereyeheight", "characterEyeHeight", "66.8", FCVAR_ARCHIVE, "Character eye height", 30, 100, tonumber)
    vrmod.AddCallbackedConvar("vrmod_characterheadtohmddist", "characterHeadToHmdDist", "6.3", FCVAR_ARCHIVE, "Head to HMD distance", 0, 20, tonumber)
    vrmod.AddCallbackedConvar("vrmod_characterik", "characterIK", "1", FCVAR_ARCHIVE, "Enable character IK", nil, nil, tobool)
    vrmod.AddCallbackedConvar("vrmod_armstretcher", "armStretcher", "0", FCVAR_ARCHIVE, "Enable arm stretching", nil, nil, tobool)
    ----------------------------------------------------------------------------
    concommand.Add("vrmod_start", function(ply, cmd, args)
        -- force / Cube hub / OpenXR wrapper: never wait for cursor (loading logo has cursor)
        local force = args and (args[1] == "force" or args[1] == "1")
        local menuVR = GetConVar("vrmod_menu_vr")
        local hub = GetConVar("vrmod_hub")
        local auto = GetConVar("vrmod_autostart")
        local launch = vrmod.IsOpenXRLaunchSession and vrmod.IsOpenXRLaunchSession()
        local cube = force or launch
            or (hub and hub:GetBool())
            or (menuVR and menuVR:GetBool())
            or (auto and auto:GetBool() and launch)
        if cube or force or launch or (menuVR and menuVR:GetBool()) or (hub and hub:GetBool()) then
            print("[gVRMod] vrmod_start Cube/force path (no cursor wait)")
            if isfunction(VRUtilClientStart) then pcall(VRUtilClientStart) end
            return
        end
        if vgui.CursorVisible() then
            print("vrmod: waiting for unpause (or use vrmod_start force)")
        end
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
end