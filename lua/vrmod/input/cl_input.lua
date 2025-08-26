local cl_pickupdisable = CreateClientConVar("vr_pickup_disable_client", 0, true, FCVAR_ARCHIVE)
local cl_hudonlykey = CreateClientConVar("vrmod_hud_visible_quickmenukey", 0, true, FCVAR_ARCHIVE)
if SERVER then return end
-- Initialize global VR table
g_VR = g_VR or {}
-- Vehicle-related variables
g_VR.vehicle = g_VR.vehicle or {
	current = nil,
	type = nil,
	glide = false,
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
local lastInputState = {
	throttle = 0,
	brake = 0,
	steer = 0,
	pitch = 0,
	yaw = 0,
	roll = 0
}

local SENSITIVITY = {
	pitch = 0.9,
	yaw = 0.7,
	roll = 0.15,
	steer = {
		car = 0.75,
		motorcycle = 0.25,
	},
	rotationRange = {
		car = 900,
		motorcycle = 360,
	}
}

local ANALOG_SEND_RATE = 0.066 -- 15 Hz
local ANALOG_EPSILON = 0.05
local MAX_WHEEL_GRAB_DIST = 13
local MAX_ANGLE = 90
local nextSendTime = 0
local neutralOffsets = {}
-- Seconds
local aircraftNeutralAng = nil
local leftGrip, rightGrip = false, false
--local leftHand, rightHand
-- Switch action set when entering vehicle
hook.Add("VRMod_EnterVehicle", "vrmod_switchactionset", function()
	timer.Simple(0.1, function()
		local ply = LocalPlayer()
		local vehicle, boneId, vType, glide = vrmod.utils.GetSteeringInfo(ply)
		g_VR.vehicle.current = vehicle
		g_VR.vehicle.type = vType
		g_VR.vehicle.wheel_bone = boneId
		g_VR.vehicle.glide = glide
		vrmod.logger.Info("Steer grip type: " .. tostring(vType))
	end)

	VRMOD_SetActiveActionSets("/actions/base", "/actions/driving")
end)

-- Reset vehicle data and switch action set when exiting vehicle
hook.Add("VRMod_ExitVehicle", "vrmod_switchactionset", function()
	g_VR.vehicle.current = nil
	g_VR.vehicle.type = nil
	g_VR.vehicle.wheel_bone = nil
	g_VR.vehicle.glide = false
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
	if not g_VR.active or not g_VR.tracking or not g_VR.vehicle.current then return end
	if CurTime() < nextSendTime then return end
	local planeGrip = g_VR.vehicle.type == "aircraft" and rightGrip
	-- === Aircraft pitch/yaw/roll relative control ===
	if planeGrip then
		local ang = g_VR.tracking.pose_righthand.ang
		if ang then
			-- Initialize neutral orientation
			if not aircraftNeutralAng then aircraftNeutralAng = Angle(ang.pitch, ang.yaw, ang.roll) end
			-- Calculate delta from neutral
			local delta = ang - aircraftNeutralAng
			delta:Normalize()
			if delta.yaw > 180 then
				delta.yaw = delta.yaw - 360
			elseif delta.yaw < -180 then
				delta.yaw = delta.yaw + 360
			end

			local targetPitch = math.Clamp(delta.pitch / MAX_ANGLE * SENSITIVITY.pitch, -1, 1)
			local targetYaw = math.Clamp(delta.yaw / SENSITIVITY.yaw, -1, 1)
			local targetRoll = math.Clamp(delta.roll / MAX_ANGLE * SENSITIVITY.roll, -1, 1)
			-- Smooth
			g_VR.analog_input.pitch = Lerp(0.35, g_VR.analog_input.pitch or 0, targetPitch)
			g_VR.analog_input.yaw = -Lerp(0.55, g_VR.analog_input.yaw or 0, targetYaw)
			g_VR.analog_input.roll = Lerp(0.9, g_VR.analog_input.roll or 0, targetRoll)
		else
			g_VR.analog_input.pitch = 0
			g_VR.analog_input.yaw = 0
			g_VR.analog_input.roll = 0
		end
	else
		-- Reset neutral if not in aircraft
		aircraftNeutralAng = nil
		g_VR.analog_input.pitch = 0
		g_VR.analog_input.yaw = 0
		g_VR.analog_input.roll = 0
	end

	if Glide and g_VR.vehicle.glide then
		-- === Steering / throttle / brake ===
		local throttle = g_VR.input.vector1_forward or 0
		local brake = g_VR.input.vector1_reverse or 0
		local steer = g_VR.wheelGripped and g_VR.analog_input.steer or g_VR.input.vector2_steer.x or 0
		if g_VR.vehicle.type == "aircraft" then throttle = throttle - brake end
		local pitch = g_VR.analog_input.pitch + g_VR.input.vector2_steer.y or 0
		local yaw = g_VR.analog_input.yaw + g_VR.input.vector2_steer.x or 0
		local roll = g_VR.analog_input.roll or 0
		-- === Send to server if significant change ===
		local changed = math.abs(throttle - lastInputState.throttle) > ANALOG_EPSILON or math.abs(brake - lastInputState.brake) > ANALOG_EPSILON or math.abs(steer - lastInputState.steer) > ANALOG_EPSILON or math.abs(pitch - lastInputState.pitch) > ANALOG_EPSILON or math.abs(yaw - lastInputState.yaw) > ANALOG_EPSILON or math.abs(roll - lastInputState.roll) > ANALOG_EPSILON
		if changed or throttle ~= 0 or brake ~= 0 or steer ~= 0 or pitch ~= 0 or yaw ~= 0 or roll ~= 0 then
			lastInputState.throttle = throttle
			lastInputState.brake = brake
			lastInputState.steer = steer
			lastInputState.pitch = pitch
			lastInputState.yaw = yaw
			lastInputState.roll = roll
			net.Start("glide_vr_input")
			net.WriteString("analog")
			net.WriteFloat(throttle)
			net.WriteFloat(brake)
			net.WriteFloat(steer)
			if g_VR.vehicle.type == "aircraft" then
				net.WriteFloat(pitch)
				net.WriteFloat(yaw)
				net.WriteFloat(roll)
			end

			net.SendToServer()
		end

		nextSendTime = CurTime() + ANALOG_SEND_RATE
	end
end)

-- Handle steering grip input
hook.Add("VRMod_Tracking", "SteeringGripInput", function()
	local ply = LocalPlayer()
	if not IsValid(ply) or not g_VR.active or not g_VR.wheelGripped then
		neutralOffsets = {}
		g_VR.analog_input.steer = 0
		return
	end

	local bonePos = vrmod.utils.GetVehicleBonePosition(g_VR.vehicle.current, g_VR.vehicle.wheel_bone)
	if not IsValid(g_VR.vehicle.current) or not bonePos then
		neutralOffsets = {}
		g_VR.analog_input.steer = 0
		return
	end

	local hmdPos, hmdAng = vrmod.GetHMDPose(ply)
	if not hmdPos then
		neutralOffsets = {}
		g_VR.analog_input.steer = 0
		return
	end

	local leftPos, leftAng = vrmod.GetLeftHandPose(ply)
	local rightPos, rightAng = vrmod.GetRightHandPose(ply)
	if not leftPos or not rightPos then
		neutralOffsets = {}
		g_VR.analog_input.steer = 0
		return
	end

	local function sign(x)
		return x > 0 and 1 or x < 0 and -1 or 0
	end

	local steerInput = 0
	local totalWeight = 0
	local leftGrip = g_VR.wheelGrippedLeft or g_VR.wheelGripped or false
	local rightGrip = g_VR.wheelGrippedRight or g_VR.wheelGripped or false
	local deadzone = 0.05 -- Deadzone threshold in meters
	for handName, state in pairs({
		left = leftGrip,
		right = rightGrip
	}) do
		if not state then continue end
		local handPos = handName == "left" and leftPos or rightPos
		local handAng = handName == "left" and leftAng or rightAng
		local relativePos = WorldToLocal(handPos, handAng, hmdPos, hmdAng)
		-- Dynamic neutral offset recalibration
		if not neutralOffsets[handName] or (relativePos - neutralOffsets[handName]):Length() < 0.02 then neutralOffsets[handName] = relativePos end
		local delta = relativePos - neutralOffsets[handName]
		local sens = SENSITIVITY.steer[g_VR.vehicle.type] or 1
		local wheelRotationRange = SENSITIVITY.rotationRange[g_VR.vehicle.type] or 360
		sens = sens * 360 / wheelRotationRange -- Scale sensitivity by wheel rotation range
		local steer = 0
		local weight = 1
		if g_VR.vehicle.type == "motorcycle" then
			if math.abs(delta.y) > deadzone then steer = (delta.y - sign(delta.y) * deadzone) * sens end
		elseif g_VR.vehicle.type == "car" then
			local multiplier = handName == "left" and 0.75 or -0.75
			if math.abs(delta.z) > deadzone then
				steer = multiplier * (delta.z - sign(delta.z) * deadzone) * sens
				weight = math.min(1, delta:Length() / 0.5) -- Weight by movement distance
			end
		end

		steerInput = steerInput + steer * weight
		totalWeight = totalWeight + weight
	end

	if totalWeight > 0 then steerInput = math.Clamp(steerInput / totalWeight, -1, 1) end
	-- Frame-time-based smoothing
	local smoothingFactor = g_VR.vehicle.type == "motorcycle" and 0.03 or 0.05
	g_VR.analog_input.steer = Lerp(FrameTime() / smoothingFactor, g_VR.analog_input.steer or 0, steerInput)
end)

-- Handle steering grip transform
hook.Add("VRMod_PreRender", "SteeringGripTransform", function()
	if not g_VR.active or not g_VR.vehicle.current then return end
	-- Special case for tanks
	if g_VR.vehicle.type == "tank" then
		local glideVeh = g_VR.vehicle.current
		local attachPos = glideVeh:GetPos() + glideVeh:GetUp() * -20
		local attachAng = glideVeh:GetAngles()
		vrmod.SetLeftHandPose(attachedPos, attachedAng)
		vrmod.SetLeftRightPose(attachedPos, attachedAng)
		netFrame.lefthandPos, netFrame.lefthandAng = attachPos, attachAng
		netFrame.righthandPos, netFrame.righthandAng = attachPos, attachAng
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
			-- grip released
			neutralOffsets[handName] = nil
			if g_VR.steeringGrip[handName] then
				g_VR.steeringGrip[handName].offset = nil
				g_VR.steeringGrip[handName].angOffset = nil
			end

			continue
		end

		local handPose = handName == "left" and leftHand or rightHand
		if not handPose then continue end
		g_VR.steeringGrip[handName] = g_VR.steeringGrip[handName] or {}
		if not g_VR.steeringGrip[handName].offset then
			if g_VR.vehicle.type == "car" then
				local dist = handPose.pos:Distance(bonePos)
				if dist > MAX_WHEEL_GRAB_DIST then continue end
			end

			g_VR.steeringGrip[handName].offset, g_VR.steeringGrip[handName].angOffset = WorldToLocal(handPose.pos, handPose.ang, bonePos, boneAng)
		end

		if g_VR.steeringGrip[handName].offset then
			anyGrip = true
			local attachedPos, attachedAng = LocalToWorld(g_VR.steeringGrip[handName].offset, g_VR.steeringGrip[handName].angOffset or Angle(0, 0, 0), bonePos, boneAng)
			if handName == "left" then
				if g_VR.vehicle.type ~= "airplane" then vrmod.SetLeftHandPose(attachedPos, attachedAng) end
			else
				vrmod.SetRightHandPose(attachedPos, attachedAng)
			end
		end
	end

	g_VR.wheelGripped = anyGrip
end)