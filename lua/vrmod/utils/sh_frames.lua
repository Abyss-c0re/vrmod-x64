g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}
-- FRAME UTILS
function vrmod.utils.CopyFrame(srcFrame)
    if not srcFrame then return nil end
    local copy = {}
    -- Copy primitive values directly
    copy.characterYaw = srcFrame.characterYaw
    -- Copy fingers
    for i = 1, 10 do
        copy["finger" .. i] = srcFrame["finger" .. i]
    end

    -- Helper for copying Vector/Angle safely
    local function copyPosAng(posKey, angKey)
        local pos = srcFrame[posKey]
        local ang = srcFrame[angKey]
        if pos then copy[posKey] = Vector(pos) end
        if ang then copy[angKey] = Angle(ang) end
    end

    -- Main tracked points
    copyPosAng("hmdPos", "hmdAng")
    copyPosAng("lefthandPos", "lefthandAng")
    copyPosAng("righthandPos", "righthandAng")
    -- Six point tracking, if present
    if srcFrame.waistPos or srcFrame.leftfootPos or srcFrame.rightfootPos then
        copyPosAng("waistPos", "waistAng")
        copyPosAng("leftfootPos", "leftfootAng")
        copyPosAng("rightfootPos", "rightfootAng")
    end
    return copy
end

--- World → origin-local frame (reusable for player net, NPC retarget, braincube).
-- originPos / originAng default to LocalPlayer when CLIENT; must be passed on SERVER.
function vrmod.utils.FrameToRelative(absFrame, originPos, originAng)
    if not absFrame then return nil end
    if not originPos or not originAng then
        if CLIENT then
            local lp = LocalPlayer()
            if not IsValid(lp) then return nil end
            originPos = originPos or lp:GetPos()
            if not originAng then
                if lp:InVehicle() then
                    local veh = lp:GetVehicle()
                    originAng = IsValid(veh) and veh:GetAngles() or Angle()
                else
                    originAng = Angle()
                end
            end
        else
            return nil
        end
    end
    if isnumber(originAng) then originAng = Angle(0, originAng, 0) end

    local relFrame = {
        characterYaw = absFrame.characterYaw,
        ts = absFrame.ts,
    }
    for i = 1, 10 do
        relFrame["finger" .. i] = absFrame["finger" .. i]
    end

    local function convertPosAng(posKey, angKey)
        local pos = absFrame[posKey]
        local ang = absFrame[angKey]
        if pos and ang then
            local localPos, localAng = WorldToLocal(pos, ang, originPos, originAng)
            relFrame[posKey] = localPos
            relFrame[angKey] = localAng
        end
    end

    convertPosAng("hmdPos", "hmdAng")
    convertPosAng("lefthandPos", "lefthandAng")
    convertPosAng("righthandPos", "righthandAng")
    if absFrame.waistPos or absFrame.leftfootPos or absFrame.rightfootPos then
        convertPosAng("waistPos", "waistAng")
        convertPosAng("leftfootPos", "leftfootAng")
        convertPosAng("rightfootPos", "rightfootAng")
    end
    return relFrame
end

--- Origin-local → world (NPC stand / retarget).
function vrmod.utils.FrameToAbsolute(relFrame, originPos, originAng)
    if not relFrame or not originPos then return nil end
    if not originAng then originAng = Angle() end
    if isnumber(originAng) then originAng = Angle(0, originAng, 0) end

    local absFrame = {
        characterYaw = (originAng.yaw or 0) + (relFrame.characterYaw or 0),
        ts = relFrame.ts,
    }
    -- characterYaw stored relative is often absolute yaw already — prefer explicit
    if relFrame.characterYawAbsolute then
        absFrame.characterYaw = relFrame.characterYaw
    end
    for i = 1, 10 do
        absFrame["finger" .. i] = relFrame["finger" .. i]
    end

    local function convertPosAng(posKey, angKey)
        local pos = relFrame[posKey]
        local ang = relFrame[angKey]
        if pos and ang then
            absFrame[posKey], absFrame[angKey] = LocalToWorld(pos, ang, originPos, originAng)
        end
    end

    convertPosAng("hmdPos", "hmdAng")
    convertPosAng("lefthandPos", "lefthandAng")
    convertPosAng("righthandPos", "righthandAng")
    if relFrame.waistPos or relFrame.leftfootPos or relFrame.rightfootPos then
        convertPosAng("waistPos", "waistAng")
        convertPosAng("leftfootPos", "leftfootAng")
        convertPosAng("rightfootPos", "rightfootAng")
    end
    return absFrame
end

--- Feet+yaw origin for a VR frame (pelvis/feet proxy from HMD when no feet).
function vrmod.utils.FrameOrigin(absFrame, fallbackPos)
    if not absFrame then return fallbackPos or Vector(), Angle() end
    local yaw = absFrame.characterYaw or 0
    local z = fallbackPos and fallbackPos.z or 0
    local x, y = fallbackPos and fallbackPos.x or 0, fallbackPos and fallbackPos.y or 0
    if absFrame.waistPos then
        x, y, z = absFrame.waistPos.x, absFrame.waistPos.y, absFrame.waistPos.z
    elseif absFrame.hmdPos then
        x, y = absFrame.hmdPos.x, absFrame.hmdPos.y
        z = absFrame.hmdPos.z - 66.8
    end
    return Vector(x, y, z), Angle(0, yaw, 0)
end

-- Back-compat: player-relative (CLIENT)
function vrmod.utils.ConvertToRelativeFrame(absFrame)
    return vrmod.utils.FrameToRelative(absFrame, nil, nil)
end

function vrmod.utils.FramesAreEqual(f1, f2)
    if not f1 or not f2 then return false end
    local function equalVec(a, b)
        return vrmod.utils.VecAlmostEqual(a, b, 0.05)
    end

    local function equalAng(a, b)
        return vrmod.utils.AngAlmostEqual(a, b)
    end

    if f1.characterYaw ~= f2.characterYaw then return false end
    for i = 1, 10 do
        if f1["finger" .. i] ~= f2["finger" .. i] then return false end
    end

    if not equalVec(f1.hmdPos, f2.hmdPos) then return false end
    if not equalAng(f1.hmdAng, f2.hmdAng) then return false end
    if not equalVec(f1.lefthandPos, f2.lefthandPos) then return false end
    if not equalAng(f1.lefthandAng, f2.lefthandAng) then return false end
    if not equalVec(f1.righthandPos, f2.righthandPos) then return false end
    if not equalAng(f1.righthandAng, f2.righthandAng) then return false end
    if f1.waistPos then
        if not f2.waistPos then return false end
        if not equalVec(f1.waistPos, f2.waistPos) then return false end
        if not equalAng(f1.waistAng, f2.waistAng) then return false end
        if not equalVec(f1.leftfootPos, f2.leftfootPos) then return false end
        if not equalAng(f1.leftfootAng, f2.leftfootAng) then return false end
        if not equalVec(f1.rightfootPos, f2.rightfootPos) then return false end
        if not equalAng(f1.rightfootAng, f2.rightfootAng) then return false end
    end
    return true
end