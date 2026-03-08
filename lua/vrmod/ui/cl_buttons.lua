if SERVER then return end
local function InitializeMenuItems()
    g_VR.menuItems = {}

    -- Row 1
    vrmod.AddInGameMenuItem("Spawn Menu", 0, 0, function()
        if not IsValid(g_SpawnMenu) then return end
        g_SpawnMenu:Open()
        hook.Add("VRMod_OpenQuickMenu", "close_spawnmenu", function()
            hook.Remove("VRMod_OpenQuickMenu", "close_spawnmenu")
            g_SpawnMenu:Close()
            return false
        end)
    end, true)

    vrmod.AddInGameMenuItem("Context Menu", 1, 0, function()
        if not IsValid(g_ContextMenu) then return end
        g_ContextMenu:Open()
        hook.Add("VRMod_OpenQuickMenu", "closecontextmenu", function()
            hook.Remove("VRMod_OpenQuickMenu", "closecontextmenu")
            g_ContextMenu:Close()
            return false
        end)
    end, true)

    vrmod.AddInGameMenuItem("Chat", 2, 0, function() LocalPlayer():ConCommand("vrmod_chatmode") end, true)
    vrmod.AddInGameMenuItem("Numpad", 3, 0, function() LocalPlayer():ConCommand("vrmod_numpad") end, true)
    vrmod.AddInGameMenuItem("Mirror", 4, 0, function() VRUtilOpenHeightMenu() end, true)
    vrmod.AddInGameMenuItem("Settings", 5, 0, function()
        local frame = VRUtilOpenMenu()
        hook.Add("VRMod_OpenQuickMenu", "closesettings", function()
            hook.Remove("VRMod_OpenQuickMenu", "closesettings")
            if IsValid(frame) then frame:Remove() end
            return false
        end)
    end, true)

    -- Row 2
    vrmod.AddInGameMenuItem("Flashlight", 0, 1, function() LocalPlayer():ConCommand("impulse 100") end, true)
    vrmod.AddInGameMenuItem("Laser pointer", 1, 1, function() LocalPlayer():ConCommand("vrmod_togglelaserpointer") end, true)
    vrmod.AddInGameMenuItem("Toggle Noclip", 2, 1, function() LocalPlayer():ConCommand("noclip") end, true)
    vrmod.AddInGameMenuItem("Undo", 3, 1, function() LocalPlayer():ConCommand("gmod_undo") end, true)
    vrmod.AddInGameMenuItem("Cleanup", 4, 1, function() LocalPlayer():ConCommand("gmod_cleanup") end, true)
    vrmod.AddInGameMenuItem("Admin Cleanup", 5, 1, function() LocalPlayer():ConCommand("gmod_admin_cleanup") end, true)

    -- Row 3
    vrmod.AddInGameMenuItem("Reset Vehicle View", 0, 2, function() VRUtilresetVehicleView() end, true)
    vrmod.AddInGameMenuItem("UI Reset", 1, 2, function() LocalPlayer():ConCommand("vrmod_vgui_reset") end, true)
    vrmod.AddInGameMenuItem("Toggle blacklist weapon", 2, 2, function() LocalPlayer():ConCommand("vrmod_toggle_blacklist") end, true)
    vrmod.AddInGameMenuItem("Map Browser", 3, 2, function()
        local window = VRUtilCreateMapBrowserWindow()
        hook.Add("VRMod_OpenQuickMenu", "closemapbrowser", function()
            hook.Remove("VRMod_OpenQuickMenu", "closemapbrowser")
            if IsValid(window) then window:Remove() end
            return false
        end)
    end, true)
    vrmod.AddInGameMenuItem("RESPAWN", 4, 2, function() LocalPlayer():ConCommand("kill") end, true)
    vrmod.AddInGameMenuItem("VR EXIT", 5, 2, function() LocalPlayer():ConCommand("vrmod_exit") end, true)
    vrmod.AddInGameMenuItem("DISCONNECT", 5, 2, function() LocalPlayer():ConCommand("disconnect") end, true)
end

hook.Add("VRMod_Start", "ReloadMenuItems", function() InitializeMenuItems() end)
hook.Add("VRMod_Exit", "restore_spawnmenu", function(ply)
    if ply ~= LocalPlayer() then return end
    timer.Simple(0.1, function()
        if IsValid(g_SpawnMenu) and g_SpawnMenu.HorizontalDivider ~= nil then
            g_SpawnMenu.HorizontalDivider:SetLeftWidth(ScrW())
        end
    end)
end)