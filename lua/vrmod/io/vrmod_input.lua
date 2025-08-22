local cl_pickupdisable = CreateClientConVar("vr_pickup_disable_client", 0, true, FCVAR_ARCHIVE)
local cl_hudonlykey = CreateClientConVar("vrmod_hud_visible_quickmenukey", 0, true, FCVAR_ARCHIVE)
if SERVER then return end
-- Initialize global VR table
g_VR = g_VR or {}
-- Vehicle-related variables
g_VR.vehicle = g_VR.vehicle or {
	current = nil,
	type = nil,
	wheel_bone = nil
}

-- Analog input variables
g_VR.analog_input = g_VR.analog_input or {
	steer = 0,
	pitch = 0,
	yaw = 0,
	roll = 0
}

-- Sensitivity and smoothing settings
local SENSITIVITY = {
	pitch = 0.75,
	yaw = 0.35,
	roll = 0.15,
	steer = {
		car = 0.25,
		motorcycle = 0.35
	}
}

local SMOOTH_FACTOR = 0.4
local smoothedPitch, smoothedYaw, smoothedRoll = 0, 0, 0
local neutralOffsets = {}
local leftGrip, rightGrip = false, false
-- Switch action set when entering vehicle
hook.Add("VRMod_EnterVehicle", "vrmod_switchactionset", function()
	local vehicle, boneId, vType = vrmod.utils.GetSteeringInfo(LocalPlayer())
	g_VR.vehicle.current = vehicle
	g_VR.vehicle.type = vType
	g_VR.vehicle.wheel_bone = boneId
	print("Vehicle type: " .. tostring(vType))
	VRMOD_SetActiveActionSets("/actions/base", "/actions/driving")
end)

-- Reset vehicle data and switch action set when exiting vehicle
hook.Add("VRMod_ExitVehicle", "vrmod_switchactionset", function()
	g_VR.vehicle.current = nil
	g_VR.vehicle.type = nil
	g_VR.vehicle.wheel_bone = nil
	VRMOD_SetActiveActionSets("/actions/base", "/actions/main")
end)

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

	if action == "boolean_forward" then
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
		if g_VR.vehicle.wheel_bone then leftGrip = pressed end
		if cl_pickupdisable:GetBool() then return end
		vrmod.Pickup(true, not pressed)
		return
	end

	if action == "boolean_right_pickup" then
		if g_VR.vehicle.wheel_bone or g_VR.vehicle.type == "aircraft" then rightGrip = pressed end
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

hook.Add("VRMod_Tracking", "glide_vr_tracking", function()
	if not g_VR.active or not g_VR.tracking then return end
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local vehicle = ply:GetVehicle() or ply:GetNWEntity("GlideVehicle")
	if not IsValid(vehicle) then return end
	if g_VR.vehicle.type == "aircraft" and rightGrip then
		local ang = g_VR.tracking.pose_righthand.ang
		if ang then
			local targetPitch = ang.pitch / 90 * SENSITIVITY.pitch
			local targetYaw = ang.yaw / 90 * SENSITIVITY.yaw
			local targetRoll = ang.roll / 90 * SENSITIVITY.roll
			-- Smooth the inputs
			smoothedPitch = Lerp(SMOOTH_FACTOR, smoothedPitch, targetPitch)
			smoothedYaw = Lerp(SMOOTH_FACTOR, smoothedYaw, targetYaw)
			smoothedRoll = Lerp(SMOOTH_FACTOR, smoothedRoll, targetRoll)
			g_VR.analog_input.pitch = smoothedPitch
			g_VR.analog_input.yaw = smoothedYaw
			g_VR.analog_input.roll = smoothedRoll
		else
			g_VR.analog_input.pitch = 0
			g_VR.analog_input.yaw = 0
			g_VR.analog_input.roll = 0
		end
	else
		g_VR.analog_input.pitch = 0
		g_VR.analog_input.yaw = 0
		g_VR.analog_input.roll = 0
	end
end)

-- Handle steering grip transform
hook.Add("VRMod_PreRender", "SteeringGripTransform", function()
	local ply = LocalPlayer()
	local netFrame = g_VR.net and g_VR.net[ply:SteamID()] and g_VR.net[ply:SteamID()].lerpedFrame
	if g_VR.vehicle.type == "tank" then
		local glideVeh = g_VR.vehicle.current
		if netFrame then
			netFrame.lefthandPos = glideVeh:GetPos() + glideVeh:GetUp() * -20
			netFrame.lefthandAng = glideVeh:GetAngles()
			netFrame.righthandPos = glideVeh:GetPos() + glideVeh:GetUp() * -20
			netFrame.righthandAng = glideVeh:GetAngles()
		end
		return
	end

	if not g_VR.vehicle.wheel_bone then
		g_VR.wheelGripped = false
		neutralOffsets = {}
		return
	end

	local leftHand = g_VR.tracking.pose_lefthand
	local rightHand = g_VR.tracking.pose_righthand
	if not leftHand and not rightHand then
		g_VR.wheelGripped = false
		neutralOffsets = {}
		return
	end

	local bonePos, boneAng = vrmod.utils.GetVehicleBonePosition(g_VR.vehicle.current, g_VR.vehicle.wheel_bone)
	if not bonePos then
		g_VR.wheelGripped = false
		neutralOffsets = {}
		return
	end

	g_VR.steeringGrip = g_VR.steeringGrip or {}
	local anyGrip = false
	for handName, state in pairs({
		left = leftGrip,
		right = rightGrip
	}) do
		if not state then
			neutralOffsets[handName] = nil
			if g_VR.steeringGrip[handName] then
				g_VR.steeringGrip[handName].offset = nil
				g_VR.steeringGrip[handName].angOffset = nil
			end

			continue
		end

		local handPose = handName == "left" and leftHand or rightHand
		if not handPose then continue end
		anyGrip = true
		g_VR.steeringGrip[handName] = g_VR.steeringGrip[handName] or {}
		if not g_VR.steeringGrip[handName].offset then g_VR.steeringGrip[handName].offset, g_VR.steeringGrip[handName].angOffset = WorldToLocal(handPose.pos, handPose.ang, bonePos, boneAng) end
		local attachedPos, attachedAng = LocalToWorld(g_VR.steeringGrip[handName].offset, g_VR.steeringGrip[handName].angOffset or Angle(0, 0, 0), bonePos, boneAng)
		if netFrame then
			if handName == "left" then
				netFrame.lefthandPos = attachedPos
				netFrame.lefthandAng = attachedAng
			else
				netFrame.righthandPos = attachedPos
				netFrame.righthandAng = attachedAng
			end
		end
	end

	g_VR.wheelGripped = anyGrip
end)

-- Handle steering grip input
hook.Add("VRMod_Tracking", "SteeringGripInput", function()
	if not g_VR.active or not g_VR.wheelGripped or not g_VR.vehicle.type then
		neutralOffsets = {}
		g_VR.analog_input.steer = 0
		return
	end

	local ply = LocalPlayer()
	local leftHand = g_VR.tracking.pose_lefthand
	local rightHand = g_VR.tracking.pose_righthand
	if not leftHand and not rightHand then
		neutralOffsets = {}
		g_VR.analog_input.steer = 0
		print("VRMod: No hand tracking data")
		return
	end

	local bonePos = vrmod.utils.GetVehicleBonePosition(g_VR.vehicle.current, g_VR.vehicle.wheel_bone)
	if not bonePos then
		neutralOffsets = {}
		g_VR.analog_input.steer = 0
		print("VRMod: No vehicle bone position")
		return
	end

	local hmdPos, hmdAng = vrmod.GetHMDPose(ply)
	local steerInput = 0
	local contributingHands = 0
	local leftGrip = g_VR.wheelGrippedLeft or g_VR.wheelGripped or false
	local rightGrip = g_VR.wheelGrippedRight or g_VR.wheelGripped or false
	for handName, state in pairs({
		left = leftGrip,
		right = rightGrip
	}) do
		if not state then continue end
		local handPose = handName == "left" and leftHand or rightHand
		if not handPose then continue end
		local relativePos = WorldToLocal(handPose.pos, handPose.ang, hmdPos, hmdAng)
		if not neutralOffsets[handName] then neutralOffsets[handName] = relativePos end
		local delta = relativePos - neutralOffsets[handName]
		local multiplier = handName == "left" and 1 or 1
		local steer = 0
		local sens = SENSITIVITY.steer[g_VR.vehicle.type] or 1
		if g_VR.vehicle.type == "motorcycle" then
			steer = multiplier * delta.y * sens
		elseif g_VR.vehicle.type == "car" then
			multiplier = handName == "left" and 1 or -1
			steer = multiplier * delta.z * sens
		end

		steerInput = steerInput + steer
		contributingHands = contributingHands + 1
	end

	if contributingHands > 0 then steerInput = math.Clamp(steerInput / contributingHands, -1, 1) end
	-- Smooth steering input
	g_VR.analog_input.steer = Lerp(0.15, g_VR.analog_input.steer or 0, steerInput)
end)