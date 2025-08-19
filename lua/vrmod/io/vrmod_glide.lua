if not Glide then return end
g_VR = g_VR or {}
local _, convarValues = vrmod.GetConvars()
local validVehicleTypes = {
    [Glide.VEHICLE_TYPE.CAR] = true,
    [Glide.VEHICLE_TYPE.MOTORCYCLE] = true,
    [Glide.VEHICLE_TYPE.TANK] = true
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
            local steering = net.ReadFloat()
            vehicle:SetInputFloat(1, "accelerate", throttle)
            vehicle:SetInputFloat(1, "brake", brake)
            vehicle:SetInputFloat(1, "steer", steering)
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
        elseif action == "boolean_up" then
            vehicle:SetInputBool(1, "shift_up", pressed)
        elseif action == "boolean_down" then
            vehicle:SetInputBool(1, "shift_down", pressed)
        elseif action == "boolean_center" then
            vehicle:SetInputBool(1, "shift_neutral", pressed)
        end
    end)
else -- CLIENT
    local inputsToSend = {
        boolean_up = true,
        boolean_down = true,
        boolean_center = true,
        boolean_handbrake = true,
        boolean_horn = true,
        boolean_lights = true
    }

    -- Unified state tracking for booleans and analogs
    local lastInputState = {
        throttle = 0,
        brake = 0,
        steer = 0
    }

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

    -- Analog input monitoring
    timer.Create("glide_vr_analog", 1 / convarValues.vrmod_net_tickrate, 0, function()
        if not g_VR.active or not g_VR.input then return end
        local ply = LocalPlayer()
        local vehicle = ply:GetNWEntity("GlideVehicle")
        if not IsValid(vehicle) or not validVehicleTypes[vehicle.VehicleType] then return end
        local throttle = g_VR.input.vector1_forward or 0
        local brake = g_VR.input.vector1_reverse or 0
        local steer = g_VR.input.vector2_steer and g_VR.input.vector2_steer.x or 0
        local changed = throttle ~= lastInputState.throttle or brake ~= lastInputState.brake or steer ~= lastInputState.steer
        -- Only send if changed or any axis is active
        if changed or throttle ~= 0 or brake ~= 0 or steer ~= 0 then
            lastInputState.throttle = throttle
            lastInputState.brake = brake
            lastInputState.steer = steer
            if throttle ~= 0 or brake ~= 0 or steer ~= 0 or changed then
                net.Start("glide_vr_input")
                net.WriteString("analog")
                net.WriteFloat(throttle)
                net.WriteFloat(brake)
                net.WriteFloat(steer)
                net.SendToServer()
            end
        end
    end)
end