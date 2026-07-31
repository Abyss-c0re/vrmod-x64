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
		-- Spawn/context stay open when QM reopens — close only via X or toggle item
		timer.Simple(0, function()
			if not g_VR or not g_VR.active then return end
			local p2v = vrmod.panel2vr
			-- Toggle same item: second pick closes that shell only
			if p2v and p2v.IsShellOpen and p2v.IsShellOpen(which) then
				if p2v.CloseSandboxShell then p2v.CloseSandboxShell(which) end
				return
			end
			local ok = false
			if which == "context" then
				if p2v and p2v.OpenContextMenu then
					ok = p2v.OpenContextMenu()
				elseif vrmod.OpenContextMenuVR then
					ok = vrmod.OpenContextMenuVR()
				end
			else
				if p2v and p2v.OpenSpawnMenu then
					ok = p2v.OpenSpawnMenu()
				elseif vrmod.OpenSpawnMenuVR then
					ok = vrmod.OpenSpawnMenuVR()
				end
			end
			if not ok and vrmod.logger then
				vrmod.logger.Warn("[QM] %s menu open failed (valid=%s)",
					which, tostring(IsValid(which == "context" and g_ContextMenu or g_SpawnMenu)))
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
	add("Toggle Noclip", 2, 1, function() LocalPlayer():ConCommand("noclip") end, true, nil, "noclip")
	add("Undo", 3, 1, function() LocalPlayer():ConCommand("gmod_undo") end, true, nil, "undo")
	add("Cleanup", 4, 1, function() LocalPlayer():ConCommand("gmod_cleanup") end, true, nil, "cleanup")
	add("Admin Cleanup", 5, 1, function() LocalPlayer():ConCommand("gmod_admin_cleanup") end, true, nil, "admin_cleanup")

	-- Row 3 / system (page 2 via layout)
	add("Reset Vehicle View", 0, 2, function() VRUtilresetVehicleView() end, true, nil, "vehicle_view")
	add("UI Reset", 1, 2, function() LocalPlayer():ConCommand("vrmod_vgui_reset") end, true, nil, "ui_reset")
	add("Border Cal", 2, 2, function() LocalPlayer():ConCommand("vrmod_border_calibrate") end, true, nil, "border_cal")
	add("Toggle blacklist weapon", 3, 2, function() LocalPlayer():ConCommand("vrmod_toggle_blacklist") end, true, nil, "blacklist")
	add("Map Browser", 4, 2, function()
		local window = VRUtilCreateMapBrowserWindow()
		hook.Add("VRMod_OpenQuickMenu", "closemapbrowser", function()
			hook.Remove("VRMod_OpenQuickMenu", "closemapbrowser")
			if IsValid(window) then window:Remove() end
			return false
		end)
	end, true, nil, "map")
	add("RESPAWN", 0, 3, function() LocalPlayer():ConCommand("kill") end, true, nil, "respawn")
	add("VR EXIT", 1, 3, function() LocalPlayer():ConCommand("vrmod_exit") end, true, nil, "vr_exit")
	add("DISCONNECT", 2, 3, function() LocalPlayer():ConCommand("disconnect") end, true, nil, "disconnect")
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
