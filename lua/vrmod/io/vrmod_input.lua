local cl_bothkey = CreateClientConVar("vrmod_vehicle_bothkeymode", 0, true, FCVAR_ARCHIVE)
local cl_pickupdisable = CreateClientConVar("vr_pickup_disable_client", 0, true, FCVAR_ARCHIVE)
local cl_hudonlykey = CreateClientConVar("vrmod_hud_visible_quickmenukey", 0, true, FCVAR_ARCHIVE)
if SERVER then return end
-- Internal state for hand tracking
local lastHandPos = nil
local lastHandAng = nil
-- Function to control physgun with hand movement
local function VRPhysgunControl(cmd)
	local hand = g_VR.tracking.pose_lefthand
	if not hand then return end
	local newPos = hand.pos
	local newAng = hand.ang
	local deltaPos = newPos - lastHandPos
	local deltaAng = Angle(math.AngleDifference(newAng.pitch, lastHandAng.pitch), math.AngleDifference(newAng.yaw, lastHandAng.yaw), math.AngleDifference(newAng.roll, lastHandAng.roll))
	-- Forward/backward motion detection
	local forward = EyeAngles():Forward()
	local forwardDelta = forward:Dot(deltaPos) * 10
	if forwardDelta > 0.3 then
		cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_FORWARD))
	elseif forwardDelta < -0.3 then
		cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_BACK))
	end

	-- Mouse movement from hand rotation
	cmd:SetMouseX(deltaAng.yaw * 50)
	cmd:SetMouseY(-deltaAng.pitch * 50)
	-- Update for next frame
	lastHandPos = newPos
	lastHandAng = newAng
end

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

	if action == "boolean_use" or action == "boolean_exit" then
		if pressed then
			LocalPlayer():ConCommand("+use")
			local wep = LocalPlayer():GetActiveWeapon()
			if IsValid(wep) and wep:GetClass() == "weapon_physgun" then
				lastHandPos = g_VR.tracking.pose_lefthand.pos
				lastHandAng = g_VR.tracking.pose_lefthand.ang
				hook.Add("CreateMove", "vrutil_hook_cmphysguncontrol", VRPhysgunControl)
			end
		else
			LocalPlayer():ConCommand("-use")
			hook.Remove("CreateMove", "vrutil_hook_cmphysguncontrol")
		end
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