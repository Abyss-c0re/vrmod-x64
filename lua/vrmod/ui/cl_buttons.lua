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

	-- Row 2
	add("Flashlight", 0, 1, function() LocalPlayer():ConCommand("impulse 100") end, true, nil, "flashlight")
	add("Laser pointer", 1, 1, function() LocalPlayer():ConCommand("vrmod_togglelaserpointer") end, true, nil, "laser")
	add("Weapon VR", 2, 1, function()
		timer.Simple(0, function()
			if not g_VR or not g_VR.active then return end
			if vrmod.WeaponSettings_Open then
				vrmod.WeaponSettings_Open()
			else
				RunConsoleCommand("vrmod_weapon_settings")
			end
		end)
	end, true, "hold pose / laser / muzzle", "weapon_vr")
	add("Toggle Noclip", 3, 1, function() LocalPlayer():ConCommand("noclip") end, true, nil, "noclip")
	add("Undo", 4, 1, function() LocalPlayer():ConCommand("gmod_undo") end, true, nil, "undo")
	add("Cleanup", 5, 1, function() LocalPlayer():ConCommand("gmod_cleanup") end, true, nil, "cleanup")
	add("Admin Cleanup", 0, 2, function() LocalPlayer():ConCommand("gmod_admin_cleanup") end, true, nil, "admin_cleanup")

	-- Row 3 / system (page 2 via layout) — col0 is Admin Cleanup above
	add("Reset Vehicle View", 1, 2, function() VRUtilresetVehicleView() end, true, nil, "vehicle_view")
	add("Close Windows", 2, 2, function()
		-- Spawn / context / Glide / settings — leave quick menu open
		if vrmod.CloseAllWindows then
			vrmod.CloseAllWindows()
		else
			LocalPlayer():ConCommand("vrmod_close_all_windows")
		end
	end, true, "close spawn · context · glide · popups", "close_windows")
	add("Reset Layouts", 3, 2, function()
		-- Poses, sizes, free-float anchors → wrist defaults; reopens QM if gone
		if vrmod.ResetAllWindowLayouts then
			vrmod.ResetAllWindowLayouts({ reopenQM = true, closeAll = true })
		else
			LocalPlayer():ConCommand("vrmod_reset_window_layouts")
		end
	end, true, "poses · sizes · dock to wrist", "reset_layouts")
	add("UI Reset", 4, 2, function()
		if vrmod.ResetAllWindowLayouts then
			vrmod.ResetAllWindowLayouts({ reopenQM = true, closeAll = true })
		else
			LocalPlayer():ConCommand("vrmod_vgui_reset")
		end
	end, true, "same as reset layouts (recovery)", "ui_reset")
	add("Border Cal", 5, 2, function() LocalPlayer():ConCommand("vrmod_border_calibrate") end, true, nil, "border_cal")
	add("Toggle blacklist weapon", 0, 3, function() LocalPlayer():ConCommand("vrmod_toggle_blacklist") end, true, nil, "blacklist")
	add("Map Browser", 1, 3, function()
		local window = VRUtilCreateMapBrowserWindow()
		hook.Add("VRMod_OpenQuickMenu", "closemapbrowser", function()
			hook.Remove("VRMod_OpenQuickMenu", "closemapbrowser")
			if IsValid(window) then window:Remove() end
			return false
		end)
	end, true, nil, "map")
	add("RESPAWN", 2, 3, function() LocalPlayer():ConCommand("kill") end, true, nil, "respawn")
	add("VR EXIT", 3, 3, function() LocalPlayer():ConCommand("vrmod_exit") end, true, nil, "vr_exit")
	add("DISCONNECT", 4, 3, function() LocalPlayer():ConCommand("disconnect") end, true, nil, "disconnect")
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
