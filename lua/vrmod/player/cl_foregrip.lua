if SERVER then return end
-- ===================== BLOCK OLD BROKEN FOREGRIP ADDON =====================
-- This completely disables the old vrmod_foregrip.lua and Universal ForeGrip addon
local function BlockOldForegripAddon()
    local blocked = false
    -- Remove all old hooks
    if hook.GetTable()["VRMod_Input"] and hook.GetTable()["VRMod_Input"]["Foregrip"] then
        hook.Remove("VRMod_Input", "Foregrip")
        blocked = true
    end

    if hook.GetTable()["VRMod_PreRender"] and hook.GetTable()["VRMod_PreRender"]["ForegripTransform"] then
        hook.Remove("VRMod_PreRender", "ForegripTransform")
        blocked = true
    end

    if hook.GetTable()["VRMod_Exit"] and hook.GetTable()["VRMod_Exit"]["ForegripExit"] then
        hook.Remove("VRMod_Exit", "ForegripExit")
        blocked = true
    end

    -- Remove old test command
    if concommand.GetTable and concommand.GetTable()["vrmod_foregrip_test"] then concommand.Remove("vrmod_foregrip_test") end
    if blocked and vrmod.logger then vrmod.logger.Warn("Delete Universal ForeGrip addon, vrmod now has a proper implementation") end
end

BlockOldForegripAddon()
timer.Simple(0.5, BlockOldForegripAddon)
timer.Simple(2, BlockOldForegripAddon)
timer.Simple(10, BlockOldForegripAddon)
-- ===================== CONFIG =====================
local GRIP_DISTANCE = 12 -- Units to start grip (hand proximity)
local GUIDE_BLEND = 0.45
-- ===================== STATE =====================
local state = {
    gripping = false,
    offsetPos = Vector(),
    offsetAng = Angle(),
    lastWep = nil,
    weaponBox = nil, -- real collision box from vrmod.utils
}

local function GetCachedWeaponParams(wep, ply, side)
    local radius, reach, mins, maxs, angles = vrmod.utils.GetWeaponMeleeParams(wep, ply, side)
    if radius == vrmod.DEFAULT_RADIUS and reach == vrmod.DEFAULT_REACH then return nil end
    return radius, reach, mins, maxs, angles
end

local function UpdateWeaponCollisionShape(ply, wep)
    timer.Simple(0.1, function()
        if not IsValid(ply) or not vrmod.IsPlayerInVR(ply) then return end
        local radius, reach, mins, maxs, angles = GetCachedWeaponParams(wep, ply, "right")
        -- state.weaponBox shall be assigned **once** the values are properly computed
        if radius and mins and maxs and angles and radius ~= vrmod.DEFAULT_RADIUS then
            -- still not computed → schedule one fallback assignment
            timer.Simple(0, function()
                if not IsValid(ply) or not vrmod.IsPlayerInVR(ply) then return end
                state.weaponBox = {
                    mins = mins or Vector(-10, -10, -10),
                    maxs = maxs or Vector(10, 10, 10),
                    reach = reach or 20
                }
            end)
        end
    end)
end

-- ===================== HELPERS =====================
local function IsValidForegripWeapon(wep)
    if not IsValid(wep) then return false end
    local class = wep:GetClass():lower()
    return not (string.find(class, "weapon_fists") or string.find(class, "arcticvr_") or class == "weapon_vrmod_empty")
end

-- Slave of pose pipeline: write guided pose into tracking, then lock gun to hand
local function UpdateViewModelPos(pos, ang, override)
    if not g_VR.active then return end
    -- Keep g_VR.tracking as single source of truth for the right hand
    if g_VR.tracking and g_VR.tracking.pose_righthand and pos and ang then
        g_VR.tracking.pose_righthand.pos = pos
        g_VR.tracking.pose_righthand.ang = ang
    end
    if vrmod.utils and vrmod.utils.UpdateViewModelPos then
        vrmod.utils.UpdateViewModelPos(pos, ang, override or true)
    end
end

-- Two-handed pose with real weapon collision box awareness
local function GetGuidedWeaponPose(rightPos, rightAng, leftPos, leftAng, box)
    if GUIDE_BLEND <= 0 then return rightPos, rightAng end
    local toLeft = leftPos - rightPos
    local dist = toLeft:Length()
    local maxDist = box and box.reach and box.reach * 1.55 or 26
    if dist > maxDist then return rightPos, rightAng end
    local minDist = box and box.mins and math.max(math.abs(box.mins.y), 4.5) or 5.5
    if dist < minDist then return rightPos, rightAng end
    local targetAng = toLeft:GetNormalized():Angle()
    local newAng = LerpAngle(GUIDE_BLEND, rightAng, targetAng)
    newAng.r = rightAng.r
    return rightPos, newAng
end

-- ===================== HOOKS =====================
hook.Add("VRMod_Input", "vrmod_foregrip", function(action, pressed)
    if not g_VR.active or not g_VR.tracking.pose_lefthand or not g_VR.tracking.pose_righthand then return end
    if action ~= "boolean_left_pickup" then return end
    local left = g_VR.tracking.pose_lefthand
    local right = g_VR.tracking.pose_righthand
    local wep = LocalPlayer():GetActiveWeapon()
    if pressed and left.pos:Distance(right.pos) <= GRIP_DISTANCE and IsValidForegripWeapon(wep) and g_VR.currentvmi then
        state.gripping = true
        state.lastWep = wep
        state.weaponBox = nil
        if IsValid(wep) then UpdateWeaponCollisionShape(LocalPlayer(), wep) end
        local wepWorldPos, wepWorldAng = LocalToWorld(g_VR.currentvmi.offsetPos or Vector(), g_VR.currentvmi.offsetAng or Angle(), right.pos, right.ang)
        state.offsetPos, state.offsetAng = WorldToLocal(left.pos, left.ang, wepWorldPos, wepWorldAng)
    else
        state.gripping = false
    end
end)

hook.Add("VRMod_PreRender", "vrmod_foregrip", function()
    if not state.gripping or not g_VR.currentvmi then
        state.gripping = false
        return
    end

    local left = g_VR.tracking.pose_lefthand
    local right = g_VR.tracking.pose_righthand
    if not left or not right then
        state.gripping = false
        return
    end

    -- Box-aware safety release
    local maxDist = state.weaponBox and state.weaponBox.reach and state.weaponBox.reach * 1.35 or 20
    if left.pos:Distance(right.pos) > maxDist then
        state.gripping = false
        return
    end

    local guidedPos, guidedAng = GetGuidedWeaponPose(right.pos, right.ang, left.pos, left.ang, state.weaponBox)
    -- Proper viewmodel update with collision handling
    UpdateViewModelPos(guidedPos, guidedAng, true)
    -- Attach left hand to weapon
    local attachPos, attachAng = LocalToWorld(state.offsetPos, state.offsetAng, g_VR.viewModelPos, g_VR.viewModelAng)
    vrmod.SetLeftHandPose(attachPos, attachAng)
    -- Network sync
    local netData = g_VR.net and g_VR.net[LocalPlayer():SteamID()]
    if netData and netData.lerpedFrame then
        netData.lerpedFrame.lefthandPos = attachPos
        netData.lerpedFrame.lefthandAng = attachAng
    end
end)

hook.Add("VRMod_Exit", "vrmod_foregrip", function() state.gripping = false end)
hook.Add("PlayerSwitchWeapon", "vrmod_foregrip", function(ply) if ply == LocalPlayer() then state.gripping = false end end)