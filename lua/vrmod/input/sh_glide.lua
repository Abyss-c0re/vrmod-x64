-- Glide vehicle VR input bridge.
-- Glide removed ply NWEntity "GlideVehicle" (2026-06); resolve via GlideGetVehicle().
g_VR = g_VR or {}

local validVehicleTypes

local function BuildValidVehicleTypes()
	if not Glide or not Glide.VEHICLE_TYPE then return nil end
	local VT = Glide.VEHICLE_TYPE
	return {
		[VT.CAR] = true,
		[VT.MOTORCYCLE] = true,
		[VT.TANK] = true,
		[VT.BOAT] = true,
		[VT.PLANE] = true,
		[VT.HELICOPTER] = true
	}
end

--- Resolve the Glide vehicle and seat for a player.
--- Prefers Glide's public API; falls back to legacy NW entity for old Glide builds.
local function ResolveGlideVehicle(ply)
	if not IsValid(ply) then return nil, 0 end

	local vehicle
	if ply.GlideGetVehicle then
		vehicle = ply:GlideGetVehicle()
	end

	-- Legacy Glide (< ~2026-06) used an NW entity; keep as fallback only.
	if not IsValid(vehicle) then
		vehicle = ply:GetNWEntity("GlideVehicle")
	end

	if not IsValid(vehicle) or not vehicle.IsGlideVehicle then return nil, 0 end

	local seatIndex = 0
	if ply.GlideGetSeatIndex then
		seatIndex = ply:GlideGetSeatIndex() or 0
	end

	if seatIndex < 1 then
		-- Driver seat is always 1; only accept real seat indices from Glide.
		return nil, 0
	end

	return vehicle, seatIndex
end

local function IsSupportedGlideVehicle(vehicle)
	if not IsValid(vehicle) or not vehicle.IsGlideVehicle then return false end
	validVehicleTypes = validVehicleTypes or BuildValidVehicleTypes()
	if not validVehicleTypes then return false end
	return validVehicleTypes[vehicle.VehicleType] == true
end

local function IsAircraft(vehicle)
	if not Glide or not Glide.VEHICLE_TYPE then return false end
	local vType = vehicle.VehicleType
	return vType == Glide.VEHICLE_TYPE.PLANE or vType == Glide.VEHICLE_TYPE.HELICOPTER
end

if SERVER then
	local lastInputTime = {}

	local cvar = GetConVar("glide_ragdoll_enable")
	if cvar then
		cvar:SetInt(0)
		timer.Create("ForceGlideRagdollDisable", 30, 0, function()
			if g_VR and g_VR.active and cvar:GetInt() ~= 0 then
				cvar:SetInt(0)
			end
		end)
	end

	util.AddNetworkString("glide_vr_input")

	net.Receive("glide_vr_input", function(_, ply)
		if not IsValid(ply) then return end

		local vehicle, seatIndex = ResolveGlideVehicle(ply)
		if not vehicle or not IsSupportedGlideVehicle(vehicle) then return end

		-- Only the driver seat receives VR drive/fly inputs
		if seatIndex ~= 1 then return end

		lastInputTime[ply] = CurTime()
		local action = net.ReadString()

		if action == "analog" then
			-- Client always writes 6 floats (throttle, brake, steer, pitch, yaw, roll)
			local throttle = net.ReadFloat()
			local brake = net.ReadFloat()
			local steer = net.ReadFloat()
			local pitch = net.ReadFloat()
			local yaw = net.ReadFloat()
			local roll = net.ReadFloat()

			local lerpFactor = 0.2
			local function LerpOrReset(current, new)
				if new == 0 then return 0 end
				return Lerp(lerpFactor, current, new)
			end

			local aircraft = IsAircraft(vehicle)
			local throttleAction = aircraft and "throttle" or "accelerate"

			local currentThrottle = vehicle:GetInputFloat(seatIndex, throttleAction) or 0
			local currentBrake = vehicle:GetInputFloat(seatIndex, "brake") or 0
			local currentSteer = vehicle:GetInputFloat(seatIndex, "steer") or 0
			local currentPitch = vehicle:GetInputFloat(seatIndex, "pitch") or 0
			local currentYaw = vehicle:GetInputFloat(seatIndex, "yaw") or 0
			local currentRoll = vehicle:GetInputFloat(seatIndex, "roll") or 0

			local newThrottle = LerpOrReset(currentThrottle, throttle)
			local newBrake = LerpOrReset(currentBrake, brake)
			local newSteer = LerpOrReset(currentSteer, steer)
			local newPitch = LerpOrReset(currentPitch, pitch)
			local newYaw = LerpOrReset(currentYaw, yaw)
			local newRoll = LerpOrReset(currentRoll, roll)

			vehicle:SetInputFloat(seatIndex, "brake", newBrake)
			vehicle:SetInputFloat(seatIndex, "steer", newSteer)

			if aircraft then
				vehicle:SetInputFloat(seatIndex, "throttle", math.Clamp(newThrottle, -1, 1))
				vehicle:SetInputFloat(seatIndex, "pitch", math.Clamp(newPitch, -1, 1))
				vehicle:SetInputFloat(seatIndex, "yaw", math.Clamp(newYaw, -1, 1))
				vehicle:SetInputFloat(seatIndex, "roll", math.Clamp(newRoll, -1, 1))
			else
				vehicle:SetInputFloat(seatIndex, "accelerate", newThrottle)
			end

			vrmod.logger.Debug(string.format(
				"Server applied - Throttle: %.2f, Brake: %.2f, Steer: %.2f, Pitch: %.2f, Yaw: %.2f, Roll: %.2f",
				newThrottle, newBrake, newSteer, newPitch, newYaw, newRoll
			))
			return
		end

		local pressed = net.ReadBool()
		local vType = vehicle.VehicleType
		local isTank = Glide and vType == Glide.VEHICLE_TYPE.TANK
		local aircraft = IsAircraft(vehicle)

		if action == "boolean_handbrake" then
			vehicle:SetInputBool(seatIndex, "handbrake", pressed)
		elseif action == "boolean_lights" then
			if pressed and vehicle.GetHeadlightState and vehicle.ChangeHeadlightState then
				local newState = vehicle:GetHeadlightState() == 0 and 2 or 0
				vehicle:ChangeHeadlightState(newState)
			end
		elseif action == "boolean_horn" then
			vehicle:SetInputBool(seatIndex, "horn", pressed)
		elseif action == "boolean_shift_up" then
			vehicle:SetInputBool(seatIndex, "shift_up", pressed)
		elseif action == "boolean_shift_down" then
			vehicle:SetInputBool(seatIndex, "shift_down", pressed)
		elseif action == "boolean_shift_neutral" then
			vehicle:SetInputBool(seatIndex, "shift_neutral", pressed)
		elseif action == "boolean_turret" or (isTank and action == "boolean_right_pickup") then
			vehicle:SetInputBool(seatIndex, "attack", pressed)
		elseif action == "boolean_alt_turret" or (isTank and action == "boolean_left_pickup") then
			vehicle:SetInputBool(seatIndex, "attack_alt", pressed)
		elseif action == "boolean_switch_weapon" then
			vehicle:SetInputBool(seatIndex, "switch_weapon", pressed)
		elseif action == "boolean_siren" then
			vehicle:SetInputBool(seatIndex, "siren", pressed)
		elseif action == "boolean_signal_left" then
			if aircraft then
				vehicle:SetInputBool(seatIndex, "landing_gear", pressed)
			else
				vehicle:SetInputBool(seatIndex, "signal_left", pressed)
			end
		elseif action == "boolean_signal_right" then
			if aircraft then
				vehicle:SetInputBool(seatIndex, "countermeasures", pressed)
			else
				vehicle:SetInputBool(seatIndex, "signal_right", pressed)
			end
		elseif action == "boolean_toggle_engine" then
			vehicle:SetInputBool(seatIndex, "toggle_engine", pressed)
		elseif action == "boolen_detach_trailer" or action == "boolean_detach_trailer" then
			vehicle:SetInputBool(seatIndex, "detach_trailer", pressed)
		end
	end)

	hook.Add("Think", "GlideVRInputTimeout", function()
		local now = CurTime()
		for ply, t in pairs(lastInputTime) do
			if not IsValid(ply) then
				lastInputTime[ply] = nil
				continue
			end

			if not vrmod.IsPlayerInVR(ply) then continue end

			if now - t > 1 then
				local vehicle, seatIndex = ResolveGlideVehicle(ply)
				if vehicle and seatIndex == 1 then
					vehicle:SetInputFloat(seatIndex, "throttle", 0)
					vehicle:SetInputFloat(seatIndex, "accelerate", 0)
					vehicle:SetInputFloat(seatIndex, "brake", 0)
					vehicle:SetInputFloat(seatIndex, "steer", 0)
					vehicle:SetInputFloat(seatIndex, "pitch", 0)
					vehicle:SetInputFloat(seatIndex, "yaw", 0)
					vehicle:SetInputFloat(seatIndex, "roll", 0)
				end
				lastInputTime[ply] = nil
			end
		end
	end)
else -- CLIENT
	local ANALOG_SEND_RATE = engine.TickInterval() or 0.015
	local nextSendTime = 0
	local originalMouseFlyMode = nil
	local originalRagdollEnable = nil
	local inputsToSend = {
		boolean_handbrake = true,
		boolean_lights = true,
		boolean_horn = true,
		boolean_shift_up = true,
		boolean_shift_down = true,
		boolean_shift_neutral = true,
		boolean_turret = true,
		boolean_alt_turret = true,
		boolean_switch_weapon = true,
		boolean_siren = true,
		boolean_signal_left = true,
		boolean_signal_right = true,
		boolean_toggle_engine = true,
		boolen_detach_trailer = true,
		boolean_detach_trailer = true,
		boolean_left_pickup = true,
		boolean_right_pickup = true,
	}

	local lastInputState = {}

	local function ApplyMouseFlyMode(mode)
		if not Glide or not Glide.Config then return end
		local cfg = Glide.Config
		cfg.mouseFlyMode = mode
		if cfg.Save then cfg:Save() end
		if cfg.TransmitInputSettings then cfg:TransmitInputSettings(true) end
		if SetupFlyMouseModeSettings then SetupFlyMouseModeSettings() end
		if Glide.MouseInput and Glide.MouseInput.Activate then Glide.MouseInput:Activate() end
	end

	-- Boolean input monitoring
	hook.Add("VRMod_Input", "glide_vr_input", function(action, pressed)
		if not g_VR.active or not g_VR.input or not g_VR.vehicle.driving then return end
		local vehicle = g_VR.vehicle.current
		if not IsValid(vehicle) or not vehicle.IsGlideVehicle then return end
		if not IsSupportedGlideVehicle(vehicle) then return end
		if not inputsToSend[action] then return end
		if CurTime() < nextSendTime then return end

		if lastInputState[action] ~= pressed then
			lastInputState[action] = pressed
			net.Start("glide_vr_input")
			net.WriteString(action)
			net.WriteBool(pressed)
			net.SendToServer()
		end

		nextSendTime = CurTime() + ANALOG_SEND_RATE
	end)

	hook.Add("VRMod_Start", "Glide_ForceMouseFlyMode", function()
		if not (Glide and Glide.Config) then
			vrmod.logger.Debug("[Glide] Glide not loaded, skipping mode change")
			return
		end

		local cfg = Glide.Config

		-- Store and disable ragdoll mode for VR
		if originalRagdollEnable == nil then
			originalRagdollEnable = cfg.glide_ragdoll_enable
			if originalRagdollEnable ~= 0 then
				vrmod.logger.Debug("[Glide] Disabling Glide ragdoll mode for VR")
				cfg.glide_ragdoll_enable = 0
			end
		end

		-- Free camera so Glide mouse fly logic does not overwrite VR pitch/yaw/roll floats
		if cfg.mouseFlyMode ~= 2 then
			originalMouseFlyMode = cfg.mouseFlyMode
			vrmod.logger.Debug(string.format("[Glide] Saving original mode %s, forcing mode 2", tostring(originalMouseFlyMode)))
			ApplyMouseFlyMode(2)
		else
			vrmod.logger.Debug("[Glide] Mouse fly mode already 2")
		end

		if Glide.Camera and vrmod.utils.PatchGlideCamera then
			vrmod.utils.PatchGlideCamera()
			vrmod.logger.Debug("[VRMod] Glide camera override installed")
		end
		-- Engine sound: VRMod-only overrides (cl_glide_audio) — never edit Glide files
		if vrmod.utils.PatchGlideAudio then
			vrmod.utils.PatchGlideAudio()
		end
	end)

	hook.Add("VRMod_Exit", "Glide_RestoreMouseFlyMode", function()
		if not (Glide and Glide.Config) then
			vrmod.logger.Debug("[Glide] Glide not loaded, cannot restore")
			return
		end

		local cfg = Glide.Config

		if originalMouseFlyMode ~= nil then
			vrmod.logger.Debug(string.format("[Glide] Restoring original mouse fly mode %s", tostring(originalMouseFlyMode)))
			ApplyMouseFlyMode(originalMouseFlyMode)
			originalMouseFlyMode = nil
		end

		if originalRagdollEnable ~= nil then
			vrmod.logger.Debug(string.format("[Glide] Restoring original ragdoll mode %s", tostring(originalRagdollEnable)))
			cfg.glide_ragdoll_enable = originalRagdollEnable
			originalRagdollEnable = nil
		end
	end)
end
