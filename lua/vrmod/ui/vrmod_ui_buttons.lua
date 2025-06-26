if SERVER then return end
--0,0 map browser
vrmod.AddInGameMenuItem("Spawn Menu", 1, 0, function()
	if not IsValid(g_SpawnMenu) then return end
	g_SpawnMenu:Open()
	hook.Add("VRMod_OpenQuickMenu", "close_spawnmenu", function()
		hook.Remove("VRMod_OpenQuickMenu", "close_spawnmenu")
		g_SpawnMenu:Close()
		return false
	end)
end)

vrmod.AddInGameMenuItem("Context Menu", 2, 0, function()
	if not IsValid(g_ContextMenu) then return end
	g_ContextMenu:Open()
	hook.Add("VRMod_OpenQuickMenu", "closecontextmenu", function()
		hook.Remove("VRMod_OpenQuickMenu", "closecontextmenu")
		g_ContextMenu:Close()
		return false
	end)
end)

vrmod.AddInGameMenuItem("Chat", 3, 0, function() LocalPlayer():ConCommand("vrmod_chatmode") end)
--4,0 settings
vrmod.AddInGameMenuItem("Flashlight", 5, 0, function() LocalPlayer():ConCommand("impulse 100") end)
vrmod.AddInGameMenuItem("Undo", 1, 1, function() LocalPlayer():ConCommand("gmod_undo") end)
--2,1 noclip 
--3,1 Reset Vehicle
vrmod.AddInGameMenuItem("Cleanup", 4, 1, function() LocalPlayer():ConCommand("gmod_cleanup") end)
vrmod.AddInGameMenuItem("Admin Cleanup", 5, 1, function() LocalPlayer():ConCommand("gmod_admin_cleanup") end)
vrmod.AddInGameMenuItem("Mirror", 0, 2, function() VRUtilOpenHeightMenu() end)
vrmod.AddInGameMenuItem("UI Reset", 1, 2, function() LocalPlayer():ConCommand("vrmod_vgui_reset") end)
vrmod.AddInGameMenuItem("Laser pointer", 2, 2, function() LocalPlayer():ConCommand("vrmod_togglelaserpointer") end)
vrmod.AddInGameMenuItem("Toggle blacklist weapon", 2, 2, function() LocalPlayer():ConCommand("vrmod_toggle_blacklist") end)
vrmod.AddInGameMenuItem("Respawn", 4, 2, function() LocalPlayer():ConCommand("kill") end)
--more space
vrmod.AddInGameMenuItem("VR EXIT", 5, 2, function() LocalPlayer():ConCommand("vrmod_exit") end)
hook.Add("VRMod_Exit", "restore_spawnmenu", function(ply)
	if ply ~= LocalPlayer() then return end
	timer.Simple(0.1, function() if IsValid(g_SpawnMenu) and g_SpawnMenu.HorizontalDivider ~= nil then g_SpawnMenu.HorizontalDivider:SetLeftWidth(ScrW()) end end)
end)