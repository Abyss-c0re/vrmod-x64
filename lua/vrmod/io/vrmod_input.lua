local cl_bothkey = CreateClientConVar("vrmod_vehicle_bothkeymode", 0, true, FCVAR_ARCHIVE)
local cl_pickupdisable = CreateClientConVar("vr_pickup_disable_client", 0, true, FCVAR_ARCHIVE)
local cl_hudonlykey = CreateClientConVar("vrmod_hud_visible_quickmenukey", 0, true, FCVAR_ARCHIVE)
if SERVER then return end


hook.Add("VRMod_EnterVehicle", "vrmod_switchactionset", function()
	if cl_bothkey:GetBool() then
		LocalPlayer():ConCommand("vrmod_keymode_both")
	else
		VRMOD_SetActiveActionSets("/actions/base", "/actions/driving")
	end
end)

hook.Add("VRMod_ExitVehicle", "vrmod_switchactionset", function() VRMOD_SetActiveActionSets("/actions/base", "/actions/main") end)
hook.Add("VRMod_Input", "vrutil_hook_defaultinput", function(action, pressed)
	if hook.Call("VRMod_AllowDefaultAction", nil, action) == false then return end
	if (action == "boolean_primaryfire" or action == "boolean_turret") and not g_VR.menuFocus then
		LocalPlayer():ConCommand(pressed and "+attack" or "-attack")
		return
	end

	if action == "boolean_secondaryfire" then
		LocalPlayer():ConCommand(pressed and "+attack2" or "-attack2")
		return
	end

	if action == "boolean_forword" then
		LocalPlayer():ConCommand(pressed and "+forward" or "-forward")
		return
	end

	if action == "boolean_back" then
		LocalPlayer():ConCommand(pressed and "+back" or "-back")
		return
	end

	if action == "boolean_left" then
		LocalPlayer():ConCommand(pressed and "+moveleft" or "-moveleft")
		return
	end

	if action == "boolean_right" then
		LocalPlayer():ConCommand(pressed and "+moveright" or "-moveright")
		return
	end

	if action == "boolean_left_pickup" then
		if cl_pickupdisable:GetBool() then return end
		vrmod.Pickup(true, not pressed)
		return
	end

	if action == "boolean_right_pickup" then
		if cl_pickupdisable:GetBool() then return end
		vrmod.Pickup(false, not pressed)
		return
	end

	if action == "boolean_changeweapon" then
		if pressed then
			VRUtilWeaponMenuOpen()
			if cl_hudonlykey:GetBool() then LocalPlayer():ConCommand("vrmod_hud 1") end
		else
			VRUtilWeaponMenuClose()
			if cl_hudonlykey:GetBool() then LocalPlayer():ConCommand("vrmod_hud 0") end
		end
		return
	end

	if action == "boolean_flashlight" and pressed then
		LocalPlayer():ConCommand("impulse 100")
		return
	end

	if action == "boolean_reload" then
		LocalPlayer():ConCommand(pressed and "+reload" or "-reload")
		return
	end

	if action == "boolean_undo" then
		if pressed then LocalPlayer():ConCommand("gmod_undo") end
		return
	end

	if action == "boolean_spawnmenu" then
		if pressed then
			g_VR.MenuOpen()
			if cl_hudonlykey:GetBool() then LocalPlayer():ConCommand("vrmod_hud 1") end
		else
			g_VR.MenuClose()
			if cl_hudonlykey:GetBool() then LocalPlayer():ConCommand("vrmod_hud 0") end
		end
		return
	end

	if action == "boolean_chat" then
		LocalPlayer():ConCommand(pressed and "+zoom" or "-zoom")
		return
	end

	if action == "boolean_walkkey" then
		LocalPlayer():ConCommand(pressed and "+walk" or "-walk")
		return
	end

	if action == "boolean_menucontext" then
		LocalPlayer():ConCommand(pressed and "+menu_context" or "-menu_context")
		return
	end

	for i = 1, #g_VR.CustomActions do
		if action == g_VR.CustomActions[i][1] then
			local commands = string.Explode(";", g_VR.CustomActions[i][pressed and 2 or 3], false)
			for j = 1, #commands do
				local args = string.Explode(" ", commands[j], false)
				RunConsoleCommand(args[1], unpack(args, 2))
			end
		end
	end
end)