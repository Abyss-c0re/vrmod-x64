if not Glide then return end
g_VR = g_VR or {}
local validVehicleTypes = {
    [Glide.VEHICLE_TYPE.CAR] = true,
    [Glide.VEHICLE_TYPE.MOTORCYCLE] = true,
    [Glide.VEHICLE_TYPE.TANK] = true,
    [Glide.VEHICLE_TYPE.BOAT] = true,
    [Glide.VEHICLE_TYPE.PLANE] = true,
    [Glide.VEHICLE_TYPE.HELICOPTER] = true
}

if SERVER then
    local cvar = GetConVar("glide_ragdoll_enable")
    if cvar then
        cvar:SetInt(0)
        timer.Create("ForceGlideRagdollDisable", 30, 0, function() if g_VR.active and cvar:GetInt() ~= 0 then cvar:SetInt(0) end end)
    end

    util.AddNetworkString("glide_vr_input")
    net.Receive("glide_vr_input", function(_, ply)
        if not IsValid(ply) then return end
        local vehicle = ply:GetNWEntity("GlideVehicle")
        local seatIndex = ply.GlideGetSeatIndex and ply:GlideGetSeatIndex() or 1
        if not IsValid(vehicle) or not validVehicleTypes[vehicle.VehicleType] then return end
        local action = net.ReadString()
        if action == "analog" then
            -- Read client inputs
            local throttle = net.ReadFloat()
            local brake = net.ReadFloat()
            local steer = net.ReadFloat()
            local pitch = net.ReadFloat()
            local yaw = net.ReadFloat()
            local roll = net.ReadFloat()
            -- Lerp current vehicle input towards new client input
            local lerpFactor = 0.2 -- tweak for smoothing
            local currentThrottle = vehicle:GetInputFloat(seatIndex, vehicle.VehicleType == Glide.VEHICLE_TYPE.PLANE or vehicle.VehicleType == Glide.VEHICLE_TYPE.HELICOPTER and "throttle" or "accelerate") or 0
            local currentBrake = vehicle:GetInputFloat(seatIndex, "brake") or 0
            local currentSteer = vehicle:GetInputFloat(seatIndex, "steer") or 0
            local currentPitch = vehicle:GetInputFloat(seatIndex, "pitch") or 0
            local currentYaw = vehicle:GetInputFloat(seatIndex, "yaw") or 0
            local currentRoll = vehicle:GetInputFloat(seatIndex, "roll") or 0
            local newThrottle = Lerp(lerpFactor, currentThrottle, throttle)
            local newBrake = Lerp(lerpFactor, currentBrake, brake)
            local newSteer = Lerp(lerpFactor, currentSteer, steer)
            local newPitch = Lerp(lerpFactor, currentPitch, pitch)
            local newYaw = Lerp(lerpFactor, currentYaw, yaw)
            local newRoll = Lerp(lerpFactor, currentRoll, roll)
            -- Apply smoothed values to vehicle
            vehicle:SetInputFloat(seatIndex, "brake", newBrake)
            vehicle:SetInputFloat(seatIndex, "steer", newSteer)
            if vehicle.VehicleType == Glide.VEHICLE_TYPE.PLANE or vehicle.VehicleType == Glide.VEHICLE_TYPE.HELICOPTER then
                vehicle:SetInputFloat(seatIndex, "throttle", math.Clamp(newThrottle, -1, 1))
                vehicle:SetInputFloat(seatIndex, "pitch", math.Clamp(newPitch, -1, 1))
                vehicle:SetInputFloat(seatIndex, "yaw", math.Clamp(newYaw, -1, 1))
                vehicle:SetInputFloat(seatIndex, "roll", math.Clamp(newRoll, -1, 1))
            else
                vehicle:SetInputFloat(seatIndex, "accelerate", newThrottle)
            end

            vrmod.logger.Debug(string.format("Server applied - Throttle: %.2f, Brake: %.2f, Steer: %.2f, Pitch: %.2f, Yaw: %.2f, Roll: %.2f", newThrottle, newBrake, newSteer, newPitch, newYaw, newRoll))
            return
        end

        local pressed = net.ReadBool()
        if action == "boolean_handbrake" then
            vehicle:SetInputBool(seatIndex, "handbrake", pressed)
        elseif action == "boolean_lights" then
            if pressed then
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
        elseif action == "boolean_turret" or vehicle.VehicleType == Glide.VEHICLE_TYPE.TANK and action == "boolean_right_pickup" then
            vehicle:SetInputBool(seatIndex, "attack", pressed)
        elseif action == "boolean_alt_turret" or vehicle.VehicleType == Glide.VEHICLE_TYPE.TANK and action == "boolean_left_pickup" then
            vehicle:SetInputBool(seatIndex, "attack_alt", pressed)
        elseif action == "boolean_switch_weapon" then
            vehicle:SetInputBool(seatIndex, "switch_weapon", pressed)
        elseif action == "boolean_siren" then
            vehicle:SetInputBool(seatIndex, "siren", pressed)
        elseif action == "boolean_signal_left" then
            if vehicle.VehicleType == Glide.VEHICLE_TYPE.PLANE or vehicle.VehicleType == Glide.VEHICLE_TYPE.HELICOPTER then
                vehicle:SetInputBool(seatIndex, "landing_gear", pressed)
            else
                vehicle:SetInputBool(seatIndex, "signal_left", pressed)
            end
        elseif action == "boolean_signal_right" then
            if vehicle.VehicleType == Glide.VEHICLE_TYPE.PLANE or vehicle.VehicleType == Glide.VEHICLE_TYPE.HELICOPTER then
                vehicle:SetInputBool(seatIndex, "countermeasures", pressed)
            else
                vehicle:SetInputBool(seatIndex, "signal_right", pressed)
            end
        elseif action == "boolean_toggle_engine" then
            vehicle:SetInputBool(seatIndex, "toggle_engine", pressed)
        elseif action == "boolean_switch_weapon" then
            vehicle:SetInputBool(seatIndex, "switch_weapon", pressed)
        elseif action == "boolen_detach_trailer" then
            vehicle:SetInputBool(seatIndex, "detach_trailer", pressed)
        end
    end)
else -- CLIENT
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
        boolean_left_pickup = true,
        boolean_right_pickup = true,
    }

    local lastInputState = {}
    local function ApplyMouseFlyMode(mode)
        if not Glide or not Glide.Config then return end
        local cfg = Glide.Config
        cfg.mouseFlyMode = mode
        -- Save & sync
        if cfg.Save then cfg:Save() end
        if cfg.TransmitInputSettings then cfg:TransmitInputSettings(true) end
        if SetupFlyMouseModeSettings then SetupFlyMouseModeSettings() end
        if Glide.MouseInput and Glide.MouseInput.Activate then Glide.MouseInput:Activate() end
    end

    -- Boolean input monitoring
    hook.Add("VRMod_Input", "glide_vr_input", function(action, pressed)
        if not g_VR.active or not g_VR.input or not g_VR.vehicle.driving or not g_VR.vehicle.current.IsGlideVehicle then return end
        local vehicle = g_VR.vehicle.current
        if not IsValid(vehicle) or not validVehicleTypes[vehicle.VehicleType] then return end
        if not inputsToSend[action] then return end
        if lastInputState[action] ~= pressed then
            lastInputState[action] = pressed
            net.Start("glide_vr_input")
            net.WriteString(action)
            net.WriteBool(pressed)
            net.SendToServer()
        end
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

        -- Store and force mouse fly mode
        if cfg.mouseFlyMode ~= 2 then
            originalMouseFlyMode = cfg.mouseFlyMode
            vrmod.logger.Debug(string.format("[Glide] Saving original mode %s, forcing mode 2", tostring(originalMouseFlyMode)))
            ApplyMouseFlyMode(2)
        else
            vrmod.logger.Debug("[Glide] Mouse fly mode already 2")
        end

        if not Glide or not Glide.Camera then return end
        vrmod.utils.PatchGlideCamera()
        vrmod.logger.Debug("[Glide] Patched Glide.Camera for VR support")
    end)

    -- When VR exits
    hook.Add("VRMod_Exit", "Glide_RestoreMouseFlyMode", function()
        if not (Glide and Glide.Config) then
            vrmod.logger.Debug("[Glide] Glide not loaded, cannot restore")
            return
        end

        local cfg = Glide.Config
        -- Restore original mouse fly mode
        if originalMouseFlyMode ~= nil then
            vrmod.logger.Debug(string.format("[Glide] Restoring original mouse fly mode %s", tostring(originalMouseFlyMode)))
            ApplyMouseFlyMode(originalMouseFlyMode)
            originalMouseFlyMode = nil
        end

        -- Restore original ragdoll mode
        if originalRagdollEnable ~= nil then
            vrmod.logger.Debug(string.format("[Glide] Restoring original ragdoll mode %s", tostring(originalRagdollEnable)))
            cfg.glide_ragdoll_enable = originalRagdollEnable
            originalRagdollEnable = nil
        end
    end)
end