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
g_VR.wheelGripped = false
g_VR.wheelGrippedLeft = false
g_VR.wheelGrippedRight = false
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

-- Net rate: not every engine tick — high-frequency SendToServer stalls VR frames.
local ANALOG_SEND_RATE = 1 / 30 -- 30 Hz is enough for drive feel
local ANALOG_HEARTBEAT = 0.45 -- keep server timeout (1s) alive without spam
local ANALOG_EPSILON = 0.04
local MAX_WHEEL_GRAB_DIST = 15
local MAX_ANGLE = 90
local nextSendTime = 0
local lastAnalogHeartbeat = 0
local neutralOffsets = {}
local sensCache = {}
local nextUpdate = 0
local UPDATE_RATE = 1
local aircraftNeutralAng = nil
local leftGrip, rightGrip = false, false
--local leftHand, rightHand
-- Shared cleanup function for exiting vehicle
local function VRMod_CleanupVehicleExit()
	-- Block DropWeapon BEFORE action-set switch (switch fires grip-release edges → gun becomes a prop)
	g_VR.antiDrop = true
	g_VR.vehicle.inside = false
	g_VR.vehicle.current = nil
	g_VR.vehicle.type = nil
	g_VR.vehicle.wheel_bone = nil
	g_VR.vehicle.glide = false
	g_VR.vehicle.driving = false
	g_VR.vehicle.bone_name = nil
	g_VR.wheelGripped = false
	g_VR.wheelGrippedLeft = false
	g_VR.wheelGrippedRight = false
	VRMOD_SetActiveActionSets("/actions/base", "/actions/main")
	timer.Remove("vrmod_vehicle_watchdog")
	timer.Remove("vrmod_glide_seat_recheck")
	timer.Remove("vrmod_glide_bind_check")
	timer.Create("vrmod_antidrop_after_vehicle", 2, 1, function()
		if g_VR then g_VR.antiDrop = false end
	end)
end

local function ResolveGlideDriving(ply)
	if not IsValid(ply) then return false end
	local seat = 0
	if ply.GlideGetSeatIndex then
		seat = ply:GlideGetSeatIndex() or 0
	end
	-- Driver seat is 1. Seat 0 = API not ready yet → treat as driver until recheck.
	if vrmod.utils and vrmod.utils.GlideSeatIsDriver then
		return vrmod.utils.GlideSeatIsDriver(seat)
	end
	return seat == 1 or seat < 1
end

hook.Add("VRMod_EnterVehicle", "vrmod_switchactionset", function()
	-- MUST block drops before action-set switch (driving set re-fires grip → DropWeapon → gun prop)
	g_VR.antiDrop = true
	timer.Remove("vrmod_antidrop_after_vehicle")

	VRMOD_SetActiveActionSets("/actions/base", "/actions/driving")

	timer.Create("vrmod_enter_vehicle_timer", 0.1, 1, function()
		local ply = LocalPlayer()
		if not IsValid(ply) then return end
		local vehicle, boneId, vType, glide, name = vrmod.utils.GetSteeringInfo(ply)
		g_VR.vehicle.inside = true
		g_VR.vehicle.current = vehicle
		g_VR.vehicle.type = vType
		g_VR.vehicle.wheel_bone = boneId
		g_VR.vehicle.glide = glide
		g_VR.vehicle.bone_name = name
		vrmod.logger.Info("Steer grip type selected: " .. tostring(vType))
		if glide then
			g_VR.vehicle.driving = ResolveGlideDriving(ply)
			timer.Create("vrmod_glide_seat_recheck", 0.6, 1, function()
				if not IsValid(ply) or not g_VR.vehicle.inside or not g_VR.vehicle.glide then return end
				g_VR.vehicle.driving = ResolveGlideDriving(ply)
			end)
			if g_VR.vehicle.driving then
				local expect = (vrmod.utils and vrmod.utils.Glide_HmdExpect)
						and vrmod.utils.Glide_HmdExpect({
							in_vehicle = true,
							is_glide = true,
							is_driver = true,
							steer_source = "stick",
							has_steer_action = true,
						})
					or nil
				g_VR._glideHmdExpect = expect
				g_VR._glideStatusLabel = (expect and vrmod.utils.Glide_StatusLabel
					and vrmod.utils.Glide_StatusLabel(expect)) or nil
				if expect and expect.checklist and vrmod.logger then
					vrmod.logger.Info("G14 HMD %s", tostring(expect.checklist))
				end
				if vrmod.Toast and vrmod.utils and vrmod.utils.Glide_ShouldToastEnter
					and vrmod.utils.Glide_ShouldToastEnter(expect, g_VR._glideEnterToasted) then
					g_VR._glideEnterToasted = true
					local t = vrmod.utils.Glide_EnterToast and vrmod.utils.Glide_EnterToast(expect)
					if t then vrmod.Toast(t, 5, "hint") end
				elseif vrmod.Toast then
					vrmod.Toast("Glide seat — use thumbstick; wheel is optional", 5, "hint")
				end
				timer.Create("vrmod_glide_bind_check", 1.5, 1, function()
					if not g_VR.vehicle.inside or not g_VR.vehicle.glide or not g_VR.vehicle.driving then return end
					local inp = g_VR.input
					local bound = inp and inp.vector2_steer ~= nil
					if not bound and vrmod.Toast then
						vrmod.Toast(
							"Glide inputs unbound — rebind /actions/driving or reinstall module",
							7,
							"error"
						)
					end
				end)
			end
		else
			g_VR.vehicle.driving = true
		end
		timer.Create("vrmod_vehicle_watchdog", 1, 0, function()
			if not IsValid(ply) or not ply:InVehicle() or not IsValid(g_VR.vehicle.current) then
				VRMod_CleanupVehicleExit()
			end
		end)
	end)
end)

-- Reset vehicle data and switch action set when exiting vehicle
hook.Add("VRMod_ExitVehicle", "vrmod_switchactionset", function() VRMod_CleanupVehicleExit() end)
hook.Add("VRMod_Input", "vrutil_hook_defaultinput", function(action, pressed)
	if hook.Call("VRMod_AllowDefaultAction", nil, action) == false then return end
	vrmod.logger.Debug("Input changed: %s = %s", action, pressed)
	-- Never shoot when any VR UI is focused (DispatchUIClick / laser on menu)
	local uiFocus = g_VR.menuFocus or (vrmod.IsUIFocused and vrmod.IsUIFocused())
	if action == "boolean_primaryfire" or action == "boolean_turret" then
		if not uiFocus then
			LocalPlayer():ConCommand(pressed and "+attack" or "-attack")
		end
		return
	end
	if action == "boolean_secondaryfire" or action == "boolean_alt_turret" then
		if not uiFocus then
			LocalPlayer():ConCommand(pressed and "+attack2" or "-attack2")
		end
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
		-- Exact pre-breakage order (e91d04d): menu grab → ArcVR probe → stock FG → pickup
		if vrmod.TryMenuGrab and vrmod.TryMenuGrab("left", pressed) then return end
		if g_VR.menuGrabActive then return end

		local awep = LocalPlayer():GetActiveWeapon()
		local arcFG = IsValid(awep) and awep.ArcticVR and awep.ForegripGrabbed
		local arcNearFG = false
		if pressed and IsValid(awep) and awep.ArcticVR and awep.TwoHanded and not arcFG then
			if awep.LeftHandInForegrip then
				arcNearFG = awep:LeftHandInForegrip(awep.ForegripMins, awep.ForegripMaxs) and true or false
			elseif awep.LeftHandNearForegrip then
				arcNearFG = awep:LeftHandNearForegrip(18) and true or false
			end
		end

		-- Stock two-hand foregrip claims left grip before world prop pickup
		if vrmod.TryForegripGrab and vrmod.TryForegripGrab(pressed) then
			-- Still track grip pressed for aircraft/etc; transform frees hand when FG active
			if g_VR.vehicle.wheel_bone then leftGrip = pressed end
			return
		end
		if arcFG or arcNearFG or g_VR.foregripActive or (vrmod.IsForegripActive and vrmod.IsForegripActive()) then
			if g_VR.vehicle.wheel_bone then leftGrip = pressed end
			return
		end
		if g_VR.avatarSteerTwin then return end
		local twin = vrmod.avatar and vrmod.avatar.Get and vrmod.avatar.Get("avatar")
		if twin and twin.active and twin.mode == "free" and not g_VR.menuFocus then return end
		-- Steering: don't claim wheel while LH holds a mag (reload)
		if g_VR.vehicle.wheel_bone then
			leftGrip = pressed and not IsValid(g_VR.heldEntityLeft)
		end
		if cl_pickupdisable:GetBool() then return end
		vrmod.Pickup(true, not pressed)
		return
	end

	if action == "boolean_right_pickup" then
		if vrmod.TryMenuGrab and vrmod.TryMenuGrab("right", pressed) then return end
		if g_VR.menuGrabActive then return end
		if g_VR.avatarSteerTwin then return end
		local twin = vrmod.avatar and vrmod.avatar.Get and vrmod.avatar.Get("avatar")
		if twin and twin.active and twin.mode == "free" and not g_VR.menuFocus then return end
		if g_VR.vehicle.wheel_bone or g_VR.vehicle.type == "aircraft" then
			rightGrip = pressed and not IsValid(g_VR.heldEntityRight)
		end
		if cl_pickupdisable:GetBool() then return end
		vrmod.Pickup(false, not pressed)
		return
	end

	if action == "boolean_changeweapon" then
		if pressed then
			-- Hold mode (bind). Sticky open from Quick Menu "Select Weapon" stays until click.
			if isfunction(VRUtilWeaponMenuOpen) then
				VRUtilWeaponMenuOpen({ sticky = false })
			end
			if cl_hudonlykey:GetBool() then LocalPlayer():ConCommand("vrmod_hud 1") end
		else
			-- Do not dismiss sticky inventory opened from Quick Menu
			if not (isfunction(VRUtilWeaponMenuIsSticky) and VRUtilWeaponMenuIsSticky()) then
				if isfunction(VRUtilWeaponMenuClose) then VRUtilWeaponMenuClose() end
			end
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
		-- 3× tap within ~1s → reset all window poses/sizes/anchors (then reopen QM)
		if pressed then
			g_VR._qmTapTimes = g_VR._qmTapTimes or {}
			local taps = g_VR._qmTapTimes
			local now = SysTime()
			local window = 1.0
			while #taps > 0 and (now - taps[1]) > window do
				table.remove(taps, 1)
			end
			taps[#taps + 1] = now
			if #taps >= 3 then
				g_VR._qmTapTimes = {}
				if g_VR.MenuClose then pcall(g_VR.MenuClose) end
				if vrmod.ResetAllWindowLayouts then
					vrmod.ResetAllWindowLayouts({ reopenQM = true, closeAll = true })
				elseif isfunction(RunConsoleCommand) then
					RunConsoleCommand("vrmod_reset_window_layouts")
				end
				if vrmod.Toast then
					vrmod.Toast("3× menu — layouts reset to wrist defaults", 3, "ok")
				end
				return
			end
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
	local planeGrip = g_VR.vehicle.type == "aircraft" and rightGrip
	-- === Aircraft pitch/yaw/roll — every tracking frame (smooth); net is rate-limited below
	if planeGrip then
		local ang = g_VR.tracking.pose_righthand.ang
		if ang then
			if not aircraftNeutralAng then aircraftNeutralAng = Angle(ang.pitch, ang.yaw, ang.roll) end
			local delta = ang - aircraftNeutralAng
			delta:Normalize()
			if delta.yaw > 180 then
				delta.yaw = delta.yaw - 360
			elseif delta.yaw < -180 then
				delta.yaw = delta.yaw + 360
			end
			local pitchSens = sensCache.pitch and sensCache.pitch.value or 1
			local yawSens = sensCache.yaw and sensCache.yaw.value or 1
			local rollSens = sensCache.roll and sensCache.roll.value or 1
			local targetPitch = math.Clamp(delta.pitch / MAX_ANGLE * pitchSens, -1, 1)
			local targetYaw = math.Clamp(delta.yaw / yawSens, -1, 1)
			local targetRoll = math.Clamp(delta.roll / MAX_ANGLE * rollSens, -1, 1)
			local pitchSmooth = (sensCache.pitch and sensCache.pitch.smooth) or 0.1
			local yawSmooth = (sensCache.yaw and sensCache.yaw.smooth) or 0.1
			local rollSmooth = (sensCache.roll and sensCache.roll.smooth) or 0.1
			local ft = FrameTime()
			g_VR.analog_input.pitch = Lerp(ft / pitchSmooth, g_VR.analog_input.pitch or 0, targetPitch)
			g_VR.analog_input.yaw = -Lerp(ft / yawSmooth * 5, g_VR.analog_input.yaw or 0, targetYaw)
			g_VR.analog_input.roll = Lerp(ft / rollSmooth, g_VR.analog_input.roll or 0, targetRoll)
		else
			g_VR.analog_input.pitch = 0
			g_VR.analog_input.yaw = 0
			g_VR.analog_input.roll = 0
		end
	else
		aircraftNeutralAng = nil
		g_VR.analog_input.pitch = 0
		g_VR.analog_input.yaw = 0
		g_VR.analog_input.roll = 0
	end

	if not (Glide and g_VR.vehicle.glide) then return end
	if CurTime() < nextSendTime then return end

	-- === Steering / throttle / brake ===
	local inp = g_VR.input or {}
	local throttle = inp.vector1_forward or 0
	local brake = inp.vector1_reverse or 0
	-- Laser on menu: triggers are UI click, not drive (cl_ui intercepts vector1_*)
	if vrmod.MenuBlocksVehicleDrive and vrmod.MenuBlocksVehicleDrive() then
		throttle, brake = 0, 0
	end
	local stickX = (inp.vector2_steer and inp.vector2_steer.x) or 0
	local stickY = (inp.vector2_steer and inp.vector2_steer.y) or 0
	local wheelSteer = (g_VR.wheelGripped and g_VR.analog_input.steer) or 0
	local steer = stickX
	local steerSrc = "stick"
	if vrmod.utils and vrmod.utils.GlidePreferStickSteer then
		steer, steerSrc = vrmod.utils.GlidePreferStickSteer(stickX, wheelSteer)
	elseif math.abs(stickX) < 0.05 and math.abs(wheelSteer) > 0.02 then
		steer = wheelSteer
		steerSrc = "wheel"
	end
	g_VR._glideSteerSource = steerSrc
	if g_VR.vehicle.type == "aircraft" then throttle = throttle - brake end
	local pitch = (g_VR.analog_input.pitch or 0) + stickY
	local yaw = (g_VR.analog_input.yaw or 0) + stickX
	local roll = g_VR.analog_input.roll or 0

	local changed = math.abs(throttle - lastInputState.throttle) > ANALOG_EPSILON
		or math.abs(brake - lastInputState.brake) > ANALOG_EPSILON
		or math.abs(steer - lastInputState.steer) > ANALOG_EPSILON
		or math.abs(pitch - lastInputState.pitch) > ANALOG_EPSILON
		or math.abs(yaw - lastInputState.yaw) > ANALOG_EPSILON
		or math.abs(roll - lastInputState.roll) > ANALOG_EPSILON
	local anyInput = throttle ~= 0 or brake ~= 0 or steer ~= 0 or pitch ~= 0 or yaw ~= 0 or roll ~= 0
	local now = CurTime()
	-- Only net on change, or heartbeat while holding inputs (server timeout 1s)
	local needHeartbeat = anyInput and (now - lastAnalogHeartbeat) >= ANALOG_HEARTBEAT
	if not changed and not needHeartbeat then
		nextSendTime = now + ANALOG_SEND_RATE
		return
	end

	lastInputState.throttle = throttle
	lastInputState.brake = brake
	lastInputState.steer = steer
	lastInputState.pitch = pitch
	lastInputState.yaw = yaw
	lastInputState.roll = roll
	lastAnalogHeartbeat = now

	net.Start("glide_vr_input")
	net.WriteString("analog")
	net.WriteFloat(throttle)
	net.WriteFloat(brake)
	net.WriteFloat(steer)
	net.WriteFloat(pitch)
	net.WriteFloat(yaw)
	net.WriteFloat(roll)
	net.SendToServer()

	nextSendTime = now + ANALOG_SEND_RATE
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
	local leftGrip = g_VR.wheelGrippedLeft or false
	local rightGrip = g_VR.wheelGrippedRight or false
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

-- Left hand owns wheel unless it is *actually* doing weapon work.
-- Do NOT free steer just because the gun is near the wheel hand (cabin is tight).
local function LeftHandBusyWithWeapon(ply)
	if IsValid(g_VR.heldEntityLeft) then return true end -- mag / prop in LH
	local wep = IsValid(ply) and ply:GetActiveWeapon() or NULL
	if IsValid(wep) and wep.ArcticVR then
		if wep.ForegripGrabbed or wep.SlideGrabbed or wep.BeltGrabbed or wep.DustCoverGrabbed then
			return true
		end
	end
	if g_VR.foregripActive or (vrmod.IsForegripActive and vrmod.IsForegripActive()) then
		return true
	end
	return false
end

-- Once per stereo frame (NOT per eye). Dual PreRender was 2× bone + 2× hand write
-- on the VR render path and delayed OpenXR submit.
local function SteeringGripTransformOnce()
	local ply = LocalPlayer()
	if not IsValid(ply) or not g_VR.active or not g_VR.vehicle.driving then return end
	local vehicle = g_VR.vehicle
	local veh, vtype = vehicle.current, vehicle.type
	-- Tank: don't collapse a hand that holds a prop/mag
	if vtype == "tank" then
		if not IsValid(veh) then return end
		local attachPos = veh:GetPos() + veh:GetUp() * -20
		local attachAng = veh:GetAngles()
		if not IsValid(g_VR.heldEntityLeft) then
			vrmod.SetLeftHandPose(attachPos, attachAng)
		end
		if not IsValid(g_VR.heldEntityRight) then
			vrmod.SetRightHandPose(attachPos, attachAng)
		end
		g_VR.wheelGrippedLeft = false
		g_VR.wheelGrippedRight = false
		return
	end

	if not IsValid(veh) or not vehicle.wheel_bone then
		g_VR.wheelGripped = false
		g_VR.wheelGrippedLeft = false
		g_VR.wheelGrippedRight = false
		neutralOffsets = {}
		return
	end

	local bonePos, boneAng = vrmod.utils.GetVehicleBonePosition(veh, vehicle.wheel_bone)
	if not bonePos then
		g_VR.wheelGripped = false
		g_VR.wheelGrippedLeft = false
		g_VR.wheelGrippedRight = false
		neutralOffsets = {}
		return
	end

	local leftHand, rightHand = g_VR.tracking.pose_lefthand, g_VR.tracking.pose_righthand
	if not leftHand and not rightHand then
		g_VR.wheelGripped = false
		g_VR.wheelGrippedLeft = false
		g_VR.wheelGrippedRight = false
		neutralOffsets = {}
		return
	end

	-- Right: gun out or held prop → never wheel-glue (gun stays on free RH)
	local heldRight = IsValid(g_VR.heldEntityRight)
		or (vrmod.utils.IsValidWep and vrmod.utils.IsValidWep(ply:GetActiveWeapon()))
	-- Left: free only for real mag/FG/slide — not "gun nearby"
	local heldLeft = LeftHandBusyWithWeapon(ply)

	local steeringGrip = g_VR.steeringGrip or {}
	g_VR.steeringGrip = steeringGrip
	local anyGrip = false
	g_VR.wheelGrippedLeft = false
	g_VR.wheelGrippedRight = false
	local WorldToLocal, LocalToWorld = WorldToLocal, LocalToWorld
	local angle_zero = angle_zero

	local function processHand(handName, handPose, gripPressed, isHeld)
		if not handPose then return end
		local gripData = steeringGrip[handName] or {}
		steeringGrip[handName] = gripData

		-- Mag/FG owns the hand — clear wheel attach
		if isHeld then
			gripData.offset, gripData.angOffset = nil, nil
			gripData.prevPressed = gripPressed
			neutralOffsets[handName] = nil
			return
		end

		local prevPressed = gripData.prevPressed or false
		gripData.prevPressed = gripPressed
		-- Sticky: only unglue when grip is released (not when hand moves off the rim)
		if not gripPressed then
			gripData.offset, gripData.angOffset = nil, nil
			neutralOffsets[handName] = nil
			return
		end

		-- Rising edge near wheel → lock offset; stay locked while grip held
		if gripPressed and not prevPressed then
			local maxDist = MAX_WHEEL_GRAB_DIST
			if vehicle.bone_name == "Airboat.Steer" then maxDist = maxDist * 1.5 end
			if vtype == "motorcycle" then
				local isBoat = Glide and veh.VehicleType and Glide.VEHICLE_TYPE
					and veh.VehicleType == Glide.VEHICLE_TYPE.BOAT
				if not isBoat then
					local gripPos = veh:GetPos() + veh:GetUp() * 1.35
					if handPose.pos:DistToSqr(gripPos) <= 1200 then
						gripData.offset, gripData.angOffset = WorldToLocal(handPose.pos, handPose.ang, bonePos, boneAng)
					end
				else
					gripData.offset, gripData.angOffset = WorldToLocal(handPose.pos, handPose.ang, bonePos, boneAng)
				end
			else
				if handPose.pos:DistToSqr(bonePos) <= maxDist * maxDist then
					gripData.offset, gripData.angOffset = WorldToLocal(handPose.pos, handPose.ang, bonePos, boneAng)
				end
			end
		end

		if gripData.offset then
			anyGrip = true
			local attachedPos, attachedAng = LocalToWorld(gripData.offset, gripData.angOffset or angle_zero, bonePos, boneAng)
			if handName == "left" then
				g_VR.wheelGrippedLeft = true
				if vtype ~= "airplane" then vrmod.SetLeftHandPose(attachedPos, attachedAng) end
			else
				g_VR.wheelGrippedRight = true
				vrmod.SetRightHandPose(attachedPos, attachedAng)
			end
		end
	end

	processHand("left", leftHand, leftGrip, heldLeft)
	processHand("right", rightHand, rightGrip, heldRight)
	g_VR.wheelGripped = anyGrip
end

hook.Add("VRMod_PreStereo", "SteeringGripTransform", function()
	if g_VR then g_VR._steerGripFrame = g_VR.stereoFrame end
	SteeringGripTransformOnce()
end)
-- Fallback if PreStereo did not run: left eye only (never both eyes)
hook.Add("VRMod_PreRender", "SteeringGripTransform", function(eye)
	if eye and eye ~= "left" then return end
	if g_VR and g_VR._steerGripFrame == g_VR.stereoFrame then return end
	if g_VR then g_VR._steerGripFrame = g_VR.stereoFrame end
	SteeringGripTransformOnce()
end)