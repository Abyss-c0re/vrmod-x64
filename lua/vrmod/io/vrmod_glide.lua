if not Glide then return end
g_VR = g_VR or {}
local _, convarValues = vrmod.GetConvars()
-- Updated vehicle types to include boat, plane, and helicopter
local validVehicleTypes = {
    [Glide.VEHICLE_TYPE.CAR] = true,
    [Glide.VEHICLE_TYPE.MOTORCYCLE] = true,
    [Glide.VEHICLE_TYPE.TANK] = true,
    [Glide.VEHICLE_TYPE.BOAT] = true,
    [Glide.VEHICLE_TYPE.PLANE] = true,
    [Glide.VEHICLE_TYPE.HELICOPTER] = true
}

if SERVER then
    util.AddNetworkString("glide_vr_input")
    net.Receive("glide_vr_input", function(_, ply)
        if not IsValid(ply) then return end
        local vehicle = ply:GetNWEntity("GlideVehicle")
        if not IsValid(vehicle) or not validVehicleTypes[vehicle.VehicleType] then return end
        local action = net.ReadString()
        if action == "analog" then
            local throttle = net.ReadFloat()
            local brake = net.ReadFloat()
            local steer = net.ReadFloat()
            local pitch = net.ReadFloat()
            local yaw = net.ReadFloat()
            local roll = net.ReadFloat()
            vehicle:SetInputFloat(1, "brake", brake)
            vehicle:SetInputFloat(1, "steer", steer)
            if vehicle.VehicleType == Glide.VEHICLE_TYPE.PLANE or vehicle.VehicleType == Glide.VEHICLE_TYPE.HELICOPTER then
                vrmod.utils.DebugPrint("Server received - Pitch: " .. pitch .. ", Yaw: " .. yaw .. ", Roll: " .. roll)
                vehicle:SetInputFloat(1, "throttle", math.Clamp(throttle, -1, 1))
                vehicle:SetInputFloat(1, "pitch", math.Clamp(pitch, -1, 1))
                vehicle:SetInputFloat(1, "yaw", math.Clamp(yaw, -1, 1))
                vehicle:SetInputFloat(1, "roll", math.Clamp(roll, -1, 1))
            else
                vehicle:SetInputFloat(1, "accelerate", throttle)
            end
            return
        end

        local pressed = net.ReadBool()
        if action == "boolean_handbrake" then
            vehicle:SetInputBool(1, "handbrake", pressed)
        elseif action == "boolean_lights" then
            if pressed then
                local newState = vehicle:GetHeadlightState() == 0 and 2 or 0
                vehicle:ChangeHeadlightState(newState)
            end
        elseif action == "boolean_horn" then
            vehicle:SetInputBool(1, "horn", pressed)
        elseif action == "boolean_shift_up" then
            vehicle:SetInputBool(1, "shift_up", pressed)
        elseif action == "boolean_shift_down" then
            vehicle:SetInputBool(1, "shift_down", pressed)
        elseif action == "boolean_shift_neutral" then
            vehicle:SetInputBool(1, "shift_neutral", pressed)
        elseif action == "boolean_turret" then
            vehicle:SetInputBool(1, "attack", pressed)
        elseif action == "boolean_alt_turret" then
            vehicle:SetInputBool(1, "attack", pressed)
        elseif action == "boolean_switch_weapon" then
            vehicle:SetInputBool(1, "switch_weapon", pressed)
        elseif action == "boolean_siren" then
            vehicle:SetInputBool(1, "siren", pressed)
        elseif action == "boolean_signal_left" then
            if vehicle.VehicleType == Glide.VEHICLE_TYPE.PLANE or vehicle.VehicleType == Glide.VEHICLE_TYPE.HELICOPTER then
                vehicle:SetInputBool(1, "landing_gear", pressed)
            else
                vehicle:SetInputBool(1, "signal_left", pressed)
            end
        elseif action == "boolean_signal_right" then
            if vehicle.VehicleType == Glide.VEHICLE_TYPE.PLANE or vehicle.VehicleType == Glide.VEHICLE_TYPE.HELICOPTER then
                vehicle:SetInputBool(1, "countermeasures", pressed)
            else
                vehicle:SetInputBool(1, "signal_right", pressed)
            end
        elseif action == "boolean_toggle_engine" then
            vehicle:SetInputBool(1, "toggle_engine", pressed)
        elseif action == "boolean_switch_weapon" then
            vehicle:SetInputBool(1, "switch_weapon", pressed)
        elseif action == "boolen_detach_trailer" then
            vehicle:SetInputBool(1, "detach_trailer", pressed)
        end
    end)
else -- CLIENT
    local originalMouseFlyMode = nil
    local originalRagdollEnable = nil
    local pitchSensitivity = 1.0 -- Adjust as needed (e.g., 0.5 for less sensitive, 2.0 for more sensitive)
    local yawSensitivity = 0.5
    local rollSensitivity = 0.5
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
        boolen_detach_trailer = true
    }

    -- Unified state tracking for booleans and analogs
    local lastInputState = {
        throttle = 0,
        brake = 0,
        steer = 0,
        pitch = 0,
        yaw = 0,
        roll = 0
    }

    local pitch, yaw, roll = 0, 0, 0
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
        if not g_VR.active or not g_VR.input then return end
        local ply = LocalPlayer()
        local vehicle = ply:GetNWEntity("GlideVehicle")
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

    -- Analog input monitoring with hand tracking
    timer.Create("glide_vr_analog", 1 / convarValues.vrmod_net_tickrate, 0, function()
        if not g_VR.active or not g_VR.input then return end
        local ply = LocalPlayer()
        local vehicle = ply:GetNWEntity("GlideVehicle")
        if not IsValid(vehicle) or not validVehicleTypes[vehicle.VehicleType] then return end
        -- Throttle + brake
        local throttle = g_VR.input.vector1_forward or 0
        local brake = g_VR.input.vector1_reverse or 0
        local steer = g_VR.input.vector2_steer and g_VR.input.vector2_steer.x or 0
        if vehicle.VehicleType == Glide.VEHICLE_TYPE.PLANE or vehicle.VehicleType == Glide.VEHICLE_TYPE.HELICOPTER then
            local fwd = g_VR.input.vector1_forward or 0
            local rev = g_VR.input.vector1_reverse or 0
            throttle = fwd - rev
            steer = g_VR.input.vector2_steer and g_VR.input.vector2_steer.x or 0 -- if needed
        end

        -- Check if anything changed
        local changed = throttle ~= lastInputState.throttle or brake ~= lastInputState.brake or steer ~= lastInputState.steer or pitch ~= lastInputState.pitch or yaw ~= lastInputState.yaw or roll ~= lastInputState.roll
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
            net.WriteFloat(pitch)
            net.WriteFloat(yaw)
            net.WriteFloat(roll)
            net.SendToServer()
        end
    end)

    -- Track right hand orientation for aircraft controls
    hook.Add("VRMod_Tracking", "glide_vr_tracking", function()
        if not g_VR.active or not g_VR.tracking then return end
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local vehicle = ply:GetNWEntity("GlideVehicle")
        if IsValid(vehicle) then
            --     local x, y = vrmod.utils.GetHandCursorOnPlane(ply, "right")
            --     input.SetCursorPos(x, y)
            -- end
            if vehicle.VehicleType == Glide.VEHICLE_TYPE.PLANE or vehicle.VehicleType == Glide.VEHICLE_TYPE.HELICOPTER then
                local ang = g_VR.tracking.pose_righthand.ang
                if ang then
                    pitch = ang.pitch / 90 * pitchSensitivity
                    yaw = -ang.yaw / 90 * yawSensitivity
                    roll = ang.roll / 90 * rollSensitivity
                else
                    pitch, yaw, roll = 0, 0, 0
                end
            else
                pitch, yaw, roll = 0, 0, 0
            end
        end
    end)

    hook.Add("VRMod_Start", "Glide_ForceMouseFlyMode", function()
        if not (Glide and Glide.Config) then
            print("[Glide VR] Glide not loaded, skipping mode change")
            return
        end

        local cfg = Glide.Config
        -- Store and disable ragdoll mode for VR
        if originalRagdollEnable == nil then
            originalRagdollEnable = cfg.glide_ragdoll_enable
            if originalRagdollEnable ~= 0 then
                print("[Glide VR] Disabling Glide ragdoll mode for VR")
                cfg.glide_ragdoll_enable = 0
            end
        end

        -- Store and force mouse fly mode
        if cfg.mouseFlyMode ~= 2 then
            originalMouseFlyMode = cfg.mouseFlyMode
            print(string.format("[Glide VR] Saving original mode %s, forcing mode 2", tostring(originalMouseFlyMode)))
            ApplyMouseFlyMode(2)
        else
            print("[Glide VR] Mouse fly mode already 2")
        end
    end)

    -- When VR exits
    hook.Add("VRMod_Exit", "Glide_RestoreMouseFlyMode", function()
        if not (Glide and Glide.Config) then
            print("[Glide VR] Glide not loaded, cannot restore")
            return
        end

        local cfg = Glide.Config
        -- Restore original mouse fly mode
        if originalMouseFlyMode ~= nil then
            print(string.format("[Glide VR] Restoring original mouse fly mode %s", tostring(originalMouseFlyMode)))
            ApplyMouseFlyMode(originalMouseFlyMode)
            originalMouseFlyMode = nil
        end

        -- Restore original ragdoll mode
        if originalRagdollEnable ~= nil then
            print(string.format("[Glide VR] Restoring original ragdoll mode %s", tostring(originalRagdollEnable)))
            cfg.glide_ragdoll_enable = originalRagdollEnable
            originalRagdollEnable = nil
        end
    end)
end