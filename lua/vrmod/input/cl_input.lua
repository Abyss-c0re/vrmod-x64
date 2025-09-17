local cl_pickupdisable = CreateClientConVar("vr_pickup_disable_client", 0, true, FCVAR_ARCHIVE)
local cl_hudonlykey = CreateClientConVar("vrmod_hud_visible_quickmenukey", 0, true, FCVAR_ARCHIVE)
if SERVER then return end
-- Pitch
local cv_pitch = CreateConVar("vrmod_sens_pitch", "1.5", FCVAR_ARCHIVE, "VRMod pitch sensitivity")
local cv_pitch_smooth = CreateConVar("vrmod_sens_pitch_smooth", "0.1", FCVAR_ARCHIVE, "VRMod pitch smoothing factor")
-- Yaw
local cv_yaw = CreateConVar("vrmod_sens_yaw", "1.25", FCVAR_ARCHIVE, "VRMod yaw sensitivity")
local cv_yaw_smooth = CreateConVar("vrmod_sens_yaw_smooth", "0.1", FCVAR_ARCHIVE, "VRMod yaw smoothing factor")
-- Roll
local cv_roll = CreateConVar("vrmod_sens_roll", "0.15", FCVAR_ARCHIVE, "VRMod roll sensitivity")
local cv_roll_smooth = CreateConVar("vrmod_sens_roll_smooth", "0.1", FCVAR_ARCHIVE, "VRMod roll smoothing factor")
-- Car steering
local cv_steer_car = CreateConVar("vrmod_sens_steer_car", "0.75", FCVAR_ARCHIVE, "VRMod car steering sensitivity")
local cv_steer_car_smooth = CreateConVar("vrmod_sens_steer_car_smooth", "0.15", FCVAR_ARCHIVE, "VRMod car steering smoothing factor")
local cv_steer_car_rot = CreateConVar("vrmod_rot_range_car", "900", FCVAR_ARCHIVE, "VRMod car rotation range")
-- Motorcycle steering
local cv_steer_bike = CreateConVar("vrmod_sens_steer_motorcycle", "0.30", FCVAR_ARCHIVE, "VRMod motorcycle steering sensitivity")
local cv_steer_bike_smooth = CreateConVar("vrmod_sens_steer_motorcycle_smooth", "0.15", FCVAR_ARCHIVE, "VRMod motorcycle steering smoothing factor")
local cv_steer_bike_rot = CreateConVar("vrmod_rot_range_motorcycle", "360", FCVAR_ARCHIVE, "VRMod motorcycle rotation range")
-- Initialize global VR table
g_VR = g_VR or {}
g_VR.antiDrop = false
-- Vehicle-related variables
g_VR.vehicle = g_VR.vehicle or {
	current = nil,
	type = nil,
	glide = false,
	driving = false,
	wheel_bone = nil,
	bone_name = nil
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

local ANALOG_SEND_RATE = 0.095
local ANALOG_EPSILON = 0.05
local MAX_WHEEL_GRAB_DIST = 13
local MAX_ANGLE = 90
local nextSendTime = 0
local neutralOffsets = {}
local sensCache = {}
local nextUpdate = 0
local UPDATE_RATE = 1
local aircraftNeutralAng = nil
local leftGrip, rightGrip = false, false
--local leftHand, rightHand
hook.Add("VRMod_EnterVehicle", "vrmod_switchactionset", function()
	-- Cancel/restart a single timer tied to this hook
	timer.Create("vrmod_enter_vehicle_timer", 0.1, 1, function()
		local ply = LocalPlayer()
		if not IsValid(ply) then return end
		g_VR.antiDrop = true
		local vehicle, boneId, vType, glide, name = vrmod.utils.GetSteeringInfo(ply)
		g_VR.vehicle.inside = true
		g_VR.vehicle.current = vehicle
		g_VR.vehicle.type = vType
		g_VR.vehicle.wheel_bone = boneId
		g_VR.vehicle.glide = glide
		g_VR.vehicle.bone_name = name
		vrmod.logger.Info("Steer grip type selected: " .. tostring(vType))
		if glide and ply:GlideGetSeatIndex() == 1 or not glide then g_VR.vehicle.driving = true end
	end)

	VRMOD_SetActiveActionSets("/actions/base", "/actions/driving")
end)

-- Reset vehicle data and switch action set when exiting vehicle
hook.Add("VRMod_ExitVehicle", "vrmod_switchactionset", function()
	g_VR.vehicle.inside = false
	g_VR.vehicle.current = nil
	g_VR.vehicle.type = nil
	g_VR.vehicle.wheel_bone = nil
	g_VR.vehicle.glide = false
	g_VR.vehicle.driving = false
	g_VR.vehicle.bone_name = name
	VRMOD_SetActiveActionSets("/actions/base", "/actions/main")
	timer.Simple(1, function() g_VR.antiDrop = false end)
end)

hook.Add("VRMod_Input", "vrutil_hook_defaultinput", function(action, pressed)
	if hook.Call("VRMod_AllowDefaultAction", nil, action) == false then return end
	vrmod.logger.Debug("Input changed: %s = %s", action, pressed)
	if (action == "boolean_primaryfire" or action == "boolean_turret") and not g_VR.menuFocus then
		LocalPlayer():ConCommand(pressed and "+attack" or "-attack")
		return
	end

	if (action == "boolean_secondaryfire" or action == "boolean_alt_turret") and not g_VR.menuFocus then
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

hook.Add("Think", "VRMOD_UpdateSensCache", function()
	if not g_VR.vehicle.current then return end
	if CurTime() < nextUpdate then return end
	nextUpdate = CurTime() + UPDATE_RATE
	sensCache.pitch = {
		value = cv_pitch:GetFloat(),
		smooth = cv_pitch_smooth:GetFloat()
	}

	sensCache.yaw = {
		value = cv_yaw:GetFloat(),
		smooth = cv_yaw_smooth:GetFloat()
	}

	sensCache.roll = {
		value = cv_roll:GetFloat(),
		smooth = cv_roll_smooth:GetFloat()
	}

	sensCache.steer = {
		car = {
			value = cv_steer_car:GetFloat(),
			smooth = cv_steer_car_smooth:GetFloat(),
			rotationRange = cv_steer_car_rot:GetFloat()
		},
		motorcycle = {
			value = cv_steer_bike:GetFloat(),
			smooth = cv_steer_bike_smooth:GetFloat(),
			rotationRange = cv_steer_bike_rot:GetFloat()
		}
	}
end)

hook.Add("VRMod_Tracking", "glide_vr_tracking", function()
	if not g_VR.active or not g_VR.tracking or not g_VR.vehicle.driving then return end
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

			-- Fetch sensitivities from sensCache
			local pitchSens = sensCache.pitch.value or 1
			local yawSens = sensCache.yaw.value or 1
			local rollSens = sensCache.roll.value or 1
			local targetPitch = math.Clamp(delta.pitch / MAX_ANGLE * pitchSens, -1, 1)
			local targetYaw = math.Clamp(delta.yaw / yawSens, -1, 1)
			local targetRoll = math.Clamp(delta.roll / MAX_ANGLE * rollSens, -1, 1)
			-- Smooth
			local pitchSmooth = sensCache.pitch.smooth or 0.1
			local yawSmooth = sensCache.yaw.smooth or 0.1
			local rollSmooth = sensCache.roll.smooth or 0.1
			g_VR.analog_input.pitch = Lerp(FrameTime() / pitchSmooth, g_VR.analog_input.pitch or 0, targetPitch)
			g_VR.analog_input.yaw = -Lerp(FrameTime() / yawSmooth * 5, g_VR.analog_input.yaw or 0, targetYaw)
			g_VR.analog_input.roll = Lerp(FrameTime() / rollSmooth, g_VR.analog_input.roll or 0, targetRoll)
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
			-- === Debug before sending ===
			if g_VR.vehicle.type == "aircraft" then
				vrmod.logger.Debug(string.format("Client sending - Throttle: %.2f, Brake: %.2f, Steer: %.2f, Pitch: %.2f, Yaw: %.2f, Roll: %.2f", throttle, brake, steer, pitch, yaw, roll))
			else
				vrmod.logger.Debug(string.format("Client sending - Throttle: %.2f, Brake: %.2f, Steer: %.2f", throttle, brake, steer))
			end

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
		if g_VR.analog_input.steer ~= 0 then vrmod.logger.Debug("Steering reset: no grip or VR inactive") end
		neutralOffsets = {}
		g_VR.analog_input.steer = 0
		return
	end

	local vehicle = g_VR.vehicle.current
	local vehicleType = g_VR.vehicle.type
	if not IsValid(vehicle) or not vrmod.utils.GetVehicleBonePosition(vehicle, g_VR.vehicle.wheel_bone) then
		vrmod.logger.Debug("Steering reset: invalid vehicle or wheel bone missing")
		neutralOffsets = {}
		g_VR.analog_input.steer = 0
		return
	end

	local hmdPos, hmdAng = vrmod.GetHMDPose(ply)
	if not hmdPos then
		vrmod.logger.Debug("Steering reset: HMD pose not available")
		neutralOffsets = {}
		g_VR.analog_input.steer = 0
		return
	end

	local leftPos, leftAng = vrmod.GetLeftHandPose(ply)
	local rightPos, rightAng = vrmod.GetRightHandPose(ply)
	if not leftPos or not rightPos then
		vrmod.logger.Debug("Steering reset: hand poses not available")
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
		if not neutralOffsets[handName] or (relativePos - neutralOffsets[handName]):Length() < 0.02 then
			neutralOffsets[handName] = relativePos
			vrmod.logger.Debug("Neutral offset recalibrated for " .. handName .. " hand")
		end

		local delta = relativePos - neutralOffsets[handName]
		-- Fetch sensitivity and rotation range from sensCache
		local sens = sensCache.steer[vehicleType].value or 1
		local wheelRotationRange = sensCache.steer[vehicleType].rotationRange or 360
		sens = sens * 360 / wheelRotationRange -- Scale sensitivity by wheel rotation range
		local steer = 0
		local weight = 1
		if vehicleType == "motorcycle" then
			if math.abs(delta.y) > deadzone then
				steer = (delta.y - sign(delta.y) * deadzone) * sens
				vrmod.logger.Debug(string.format("Motorcycle steer (%s hand): delta.y=%.3f steer=%.3f", handName, delta.y, steer))
			end
		elseif vehicleType == "car" then
			local multiplier = handName == "left" and 0.75 or -0.75
			if math.abs(delta.z) > deadzone then
				steer = multiplier * (delta.z - sign(delta.z) * deadzone) * sens
				weight = math.min(1, delta:Length() / 0.5)
				vrmod.logger.Debug(string.format("Car steer (%s hand): delta.z=%.3f steer=%.3f weight=%.2f", handName, delta.z, steer, weight))
			end
		end

		steerInput = steerInput + steer * weight
		totalWeight = totalWeight + weight
	end

	if totalWeight > 0 then steerInput = math.Clamp(steerInput / totalWeight, -1, 1) end
	-- Apply frame-time-based smoothing using sensCache
	local smoothingFactor = sensCache.steer[vehicleType].smooth or 0.1
	local prevSteer = g_VR.analog_input.steer or 0
	g_VR.analog_input.steer = Lerp(FrameTime() / smoothingFactor, prevSteer, steerInput)
	if math.abs(g_VR.analog_input.steer - prevSteer) > 0.01 then vrmod.logger.Debug(string.format("Smoothed steer updated: %.3f -> %.3f (target=%.3f)", prevSteer, g_VR.analog_input.steer, steerInput)) end
end)

hook.Add("VRMod_PreRender", "SteeringGripTransform", function()
	local ply = LocalPlayer()
	if not IsValid(ply) or not g_VR.active or not g_VR.vehicle.driving then return end
	-- Special case: tanks (center stick-like grip)
	if g_VR.vehicle.type == "tank" then
		local glideVeh = g_VR.vehicle.current
		local attachPos = glideVeh:GetPos() + glideVeh:GetUp() * -20
		local attachAng = glideVeh:GetAngles()
		vrmod.SetLeftHandPose(attachPos, attachAng)
		vrmod.SetRightHandPose(attachPos, attachAng)
		return
	end

	local veh = g_VR.vehicle.current
	if not IsValid(veh) or not g_VR.vehicle.wheel_bone then
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

	local bonePos, boneAng = vrmod.utils.GetVehicleBonePosition(veh, g_VR.vehicle.wheel_bone)
	if not bonePos then
		g_VR.wheelGripped = false
		neutralOffsets = {}
		return
	end

	local heldLeft = g_VR.heldEntityLeft
	local heldRight = vrmod.utils.IsValidWep(ply:GetActiveWeapon())
	g_VR.steeringGrip = g_VR.steeringGrip or {}
	local anyGrip = false
	for handName, gripPressed in pairs({
		left = leftGrip,
		right = rightGrip
	}) do
		if handName == "left" and heldLeft then continue end
		if handName == "right" and heldRight then continue end
		local handPose = handName == "left" and leftHand or rightHand
		if not handPose then continue end
		g_VR.steeringGrip[handName] = g_VR.steeringGrip[handName] or {}
		local gripData = g_VR.steeringGrip[handName]
		-- Track previous button state
		local prevPressed = gripData.prevPressed or false
		gripData.prevPressed = gripPressed
		-- Release instantly if grip released
		if not gripPressed then
			gripData.offset = nil
			gripData.angOffset = nil
			neutralOffsets[handName] = nil
			continue
		end

		-- Only try to attach on rising edge (false -> true)
		if gripPressed and not prevPressed then
			local dist
			local maxDist = MAX_WHEEL_GRAB_DIST
			if g_VR.vehicle.bone_name == "Airboat.Steer" then maxDist = maxDist * 1.5 end
			if g_VR.vehicle.type == "motorcycle" and g_VR.vehicle.bone_name ~= "Airboat.Steer" and g_VR.vehicle.current.VehicleType ~= Glide.VEHICLE_TYPE.BOAT then
				local gripPos = veh:GetPos() + veh:GetUp() * 1.15
				dist = handPose.pos:Distance(gripPos)
				if dist <= 30 then gripData.offset, gripData.angOffset = WorldToLocal(handPose.pos, handPose.ang, bonePos, boneAng) end
			elseif g_VR.vehicle.type == "motorcycle" and g_VR.vehicle.current.VehicleType == Glide.VEHICLE_TYPE.BOAT then
				gripData.offset, gripData.angOffset = WorldToLocal(handPose.pos, handPose.ang, bonePos, boneAng)
			else
				dist = handPose.pos:Distance(bonePos)
				if dist <= maxDist then gripData.offset, gripData.angOffset = WorldToLocal(handPose.pos, handPose.ang, bonePos, boneAng) end
			end
		end

		-- Apply pose only if currently attached
		if gripData.offset then
			anyGrip = true
			local attachedPos, attachedAng = LocalToWorld(gripData.offset, gripData.angOffset or Angle(0, 0, 0), bonePos, boneAng)
			if handName == "left" then
				if g_VR.vehicle.type ~= "airplane" then vrmod.SetLeftHandPose(attachedPos, attachedAng) end
			else
				vrmod.SetRightHandPose(attachedPos, attachedAng)
			end
		end
	end

	g_VR.wheelGripped = anyGrip
end)