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

function vrmod.utils.ConvertToRelativeFrame(absFrame)
    local lp = LocalPlayer()
    if not IsValid(lp) then return nil end
    local plyAng
    if lp:InVehicle() then
        local veh = lp:GetVehicle()
        if IsValid(veh) then
            plyAng = veh:GetAngles()
        else
            plyAng = Angle()
        end
    else
        plyAng = Angle()
    end

    local plyPos = lp:GetPos()
    local relFrame = {
        characterYaw = absFrame.characterYaw
    }

    -- Fingers
    for i = 1, 10 do
        relFrame["finger" .. i] = absFrame["finger" .. i]
    end

    local function convertPosAng(posKey, angKey)
        local pos = absFrame[posKey]
        local ang = absFrame[angKey]
        if pos and ang then
            local localPos, localAng = WorldToLocal(pos, ang, plyPos, plyAng)
            relFrame[posKey] = localPos
            relFrame[angKey] = localAng
        end
    end

    -- Main tracked points
    convertPosAng("hmdPos", "hmdAng")
    convertPosAng("lefthandPos", "lefthandAng")
    convertPosAng("righthandPos", "righthandAng")
    if g_VR.sixPoints then
        convertPosAng("waistPos", "waistAng")
        convertPosAng("leftfootPos", "leftfootAng")
        convertPosAng("rightfootPos", "rightfootAng")
    end
    return relFrame
end

function vrmod.utils.FramesAreEqual(f1, f2)
    if not f1 or not f2 then return false end
    local function equalVec(a, b)
        return vrmod.utils.VecAlmostEqual(a, b, 0.0001)
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

    vrmod.utils.DebugPrint("Equal frame detected")
    return true
end