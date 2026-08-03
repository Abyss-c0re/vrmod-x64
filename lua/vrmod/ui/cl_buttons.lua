if SERVER then return end
local function InitializeMenuItems()
	g_VR.menuItems = {}
	-- Drop legacy "Mirror" entries so restore Think cannot resurrect them
	g_VR.menuBackup = g_VR.menuBackup or {}
	for id, data in pairs(g_VR.menuBackup) do
		if data and (data.name == "Mirror" or data.name == "mirror") then
			g_VR.menuBackup[id] = nil
		end
	end
	if vrmod.RemoveInGameMenuItem then
		vrmod.RemoveInGameMenuItem("Mirror", nil, true)
	end

	local add = vrmod.AddInGameMenuItem
	-- id is 7th arg — used by Quick Menu pages / settings layout

	local function openSandboxShell(which)
		-- Defer so quick-menu close finishes first (nested menu open)
		-- Toggle only when shell is actually visible+bound (not a blank first-open miss)
		timer.Simple(0.05, function()
			if not g_VR or not g_VR.active then return end
			local p2v = vrmod.panel2vr
			local open = false
			if which == "context" then
				if p2v and p2v.OpenContextMenu then
					open = p2v.OpenContextMenu()
				elseif vrmod.OpenContextMenuVR then
					open = vrmod.OpenContextMenuVR()
				end
			else
				if p2v and p2v.OpenSpawnMenu then
					open = p2v.OpenSpawnMenu()
				elseif vrmod.OpenSpawnMenuVR then
					open = vrmod.OpenSpawnMenuVR()
				end
			end
			-- If open failed (panel late), one more try after sandbox creates it
			if not open then
				timer.Simple(0.2, function()
					if not g_VR or not g_VR.active then return end
					if which == "context" then
						if p2v and p2v.OpenContextMenu then p2v.OpenContextMenu() end
					else
						if p2v and p2v.OpenSpawnMenu then p2v.OpenSpawnMenu() end
					end
				end)
			end
		end)
	end

	-- Row 1 defaults (page 1 via layout file)
	add("Spawn Menu", 0, 0, function() openSandboxShell("spawn") end, true, "open / close", "spawn")

	add("Context Menu", 1, 0, function() openSandboxShell("context") end, true, "open / close", "context")

	add("Chat", 2, 0, function() LocalPlayer():ConCommand("vrmod_chatmode") end, true, nil, "chat")
	add("Numpad", 3, 0, function() LocalPlayer():ConCommand("vrmod_numpad") end, true, nil, "numpad")
	add("Avatar", 4, 0, function()
		timer.Simple(0, function()
			if not g_VR or not g_VR.active then return end
			if vrmod.AvatarMenu_Open then
				vrmod.AvatarMenu_Open()
			elseif VRUtilOpenHeightMenu then
				VRUtilOpenHeightMenu()
			else
				RunConsoleCommand("vrmod_avatar")
			end
		end)
	end, true, "customize twin", "avatar")
	add("Settings", 5, 0, function()
		timer.Simple(0, function()
			if vrmod.Settings_Open then
				vrmod.Settings_Open()
			elseif vrmod.panel2vr and vrmod.panel2vr.OpenSettings then
				vrmod.panel2vr.OpenSettings()
			elseif VRUtilOpenMenu then
				VRUtilOpenMenu()
			end
		end)
	end, true, nil, "settings")

	-- Pause Menu = Cube hub (ESC). Never ActivateGameUI (freezes SP).
	add("Pause Menu", 0, 1, function()
		timer.Simple(0, function()
			if not g_VR or not g_VR.active then return end
			if vrmod.OpenPauseMenuVR then
				vrmod.OpenPauseMenuVR()
			elseif vrmod.VRHub_Open then
				if vrmod.VRUnpauseWorld then vrmod.VRUnpauseWorld() end
				vrmod.VRHub_Open()
			end
		end)
	end, true, "Resume · Settings · ESC", "pause_menu")
	-- New Game = maps only (not a pause dupe)
	add("New Game", 1, 1, function()
		timer.Simple(0, function()
			if not g_VR or not g_VR.active then return end
			if vrmod.OpenNewGameUnpaused then
				vrmod.OpenNewGameUnpaused()
			elseif vrmod.VRNewGame_Open then
				vrmod.VRNewGame_Open()
			else
				RunConsoleCommand("vrmod_newgame")
			end
		end)
	end, true, "maps · gamemode · multiplayer", "newgame")

	-- Row 2 (shifted — launcher takes col 0–1)
	add("Flashlight", 2, 1, function() LocalPlayer():ConCommand("impulse 100") end, true, nil, "flashlight")
	add("Laser pointer", 3, 1, function() LocalPlayer():ConCommand("vrmod_togglelaserpointer") end, true, nil, "laser")
	add("Weapon VR", 4, 1, function()
		timer.Simple(0, function()
			if not g_VR or not g_VR.active then return end
			if vrmod.WeaponSettings_Open then
				vrmod.WeaponSettings_Open()
			else
				RunConsoleCommand("vrmod_weapon_settings")
			end
		end)
	end, true, "hold pose / laser / muzzle", "weapon_vr")
	add("Toggle Noclip", 5, 1, function() LocalPlayer():ConCommand("noclip") end, true, nil, "noclip")
	add("Undo", 0, 2, function() LocalPlayer():ConCommand("gmod_undo") end, true, nil, "undo")
	add("Cleanup", 1, 2, function() LocalPlayer():ConCommand("gmod_cleanup") end, true, nil, "cleanup")
	add("Admin Cleanup", 2, 2, function() LocalPlayer():ConCommand("gmod_admin_cleanup") end, true, nil, "admin_cleanup")

	-- Row 3 / system
	add("Bindings", 3, 2, function()
		timer.Simple(0, function()
			if vrmod.BindingsPanel_Open then
				vrmod.BindingsPanel_Open()
			else
				RunConsoleCommand("vrmod_controller_bindings")
			end
		end)
	end, true, "On foot / Vehicle rebind", "bindings")
	add("Reset Vehicle View", 4, 2, function() VRUtilresetVehicleView() end, true, nil, "vehicle_view")
	-- no "Close Windows" on quick menu (menu button release already closes QM)
	add("Recover Menus", 0, 3, function()
		if vrmod.RecoverLostMenus then
			local n = vrmod.RecoverLostMenus({ toast = true })
			if n == 0 and vrmod.Toast then
				vrmod.Toast("No lost windows", 2, "hint")
			end
		else
			LocalPlayer():ConCommand("vrmod_recover_menus")
		end
	end, true, "far free-float → wrist (no full reset)", "recover_menus")
	add("Reset Layouts", 1, 3, function()
		if vrmod.ResetAllWindowLayouts then
			vrmod.ResetAllWindowLayouts({ reopenQM = true, closeAll = true })
		else
			LocalPlayer():ConCommand("vrmod_reset_window_layouts")
		end
	end, true, "poses · sizes · dock to wrist", "reset_layouts")
	add("UI Reset", 2, 3, function()
		if vrmod.ResetAllWindowLayouts then
			vrmod.ResetAllWindowLayouts({ reopenQM = true, closeAll = true })
		else
			LocalPlayer():ConCommand("vrmod_vgui_reset")
		end
	end, true, "full clear layouts + reopen QM", "ui_reset")
	-- Video Calibration (was Border Cal) — front-page slot via layout id video_cal
	add("Video Calibration", 3, 3, function() LocalPlayer():ConCommand("vrmod_border_calibrate") end, true, "scale · V · H · save", "video_cal")
	add("Toggle blacklist weapon", 4, 3, function() LocalPlayer():ConCommand("vrmod_toggle_blacklist") end, true, nil, "blacklist")
	-- Map Browser aliases New Game (stock-style modes/settings)
	add("Map Browser", 5, 3, function()
		timer.Simple(0, function()
			if vrmod.OpenNewGame then
				vrmod.OpenNewGame()
			elseif isfunction(VRUtilCreateMapBrowserWindow) then
				VRUtilCreateMapBrowserWindow()
			end
		end)
	end, true, "New Game · maps · modes", "map")
	add("RESPAWN", 0, 4, function() LocalPlayer():ConCommand("kill") end, true, nil, "respawn")
	add("VR EXIT", 1, 4, function() LocalPlayer():ConCommand("vrmod_exit") end, true, nil, "vr_exit")
	add("DISCONNECT", 2, 4, function() LocalPlayer():ConCommand("disconnect") end, true, nil, "disconnect")
end

hook.Add("VRMod_Start", "ReloadMenuItems", function() InitializeMenuItems() end)
-- Safe re-init without full VR restart (lua reload / empty registry)
vrmod.RebuildInGameMenuItems = InitializeMenuItems
concommand.Add("vrmod_quickmenu_rebuild_items", function()
	InitializeMenuItems()
	print("[vrmod] quick menu items rebuilt:", g_VR.menuItems and #g_VR.menuItems or 0)
end)
hook.Add("VRMod_Exit", "restore_spawnmenu", function(ply)
	if ply ~= LocalPlayer() then return end
	timer.Simple(0.1, function()
		if IsValid(g_SpawnMenu) and g_SpawnMenu.HorizontalDivider ~= nil then
			g_SpawnMenu.HorizontalDivider:SetLeftWidth(ScrW())
		end
	end)
end)
