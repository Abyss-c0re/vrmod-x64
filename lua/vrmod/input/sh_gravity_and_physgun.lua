if CLIENT then
    local lastHandPos = nil
    local lastHandAng = nil
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

    hook.Add("VRMod_Input", "physgun_controll", function(action, pressed)
        if hook.Call("VRMod_AllowDefaultAction", nil, action) == false then return end
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
    end)
elseif SERVER then
    hook.Add("GravGunOnPickedUp", "VR_TrackHeldEntity", function(ply, ent)
        if not vrmod.IsPlayerInVR(ply) then return end
        ply.VRHeldEnt = ent
        ply.VRTargetAngles = ent:GetAngles()
        hook.Add("Think", "VR_ApplyRotation_" .. ply:SteamID(), function()
            if not IsValid(ply) or not IsValid(ply.VRHeldEnt) then
                hook.Remove("Think", "VR_ApplyRotation_" .. ply:SteamID())
                return
            end

            local phys = ply.VRHeldEnt:GetPhysicsObject()
            local targetAngles = vrmod.GetRightHandAng(ply)
            ply.VRTargetAngles = LerpAngle(0.15, ply.VRTargetAngles or targetAngles, targetAngles)
            if IsValid(phys) then
                phys:SetAngleVelocityInstantaneous(Vector(0, 0, 0))
                phys:SetAngles(ply.VRTargetAngles)
            else
                ply.VRHeldEnt:SetAngles(ply.VRTargetAngles)
            end
        end)
    end)

    hook.Add("GravGunOnDropped", "VR_ClearHeldEntity", function(ply, ent)
        if ply.VRHeldEnt == ent then
            ply.VRHeldEnt = nil
            ply.VRTargetAngles = nil
            hook.Remove("Think", "VR_ApplyRotation_" .. ply:SteamID())
        end
    end)
end