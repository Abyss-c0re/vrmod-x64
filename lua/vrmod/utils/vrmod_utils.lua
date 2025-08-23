local cl_effectmodel = CreateClientConVar("vrmod_melee_fist_collisionmodel", "models/props_junk/PopCan01a.mdl", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local cv_debug = CreateConVar("vrmod_debug", "0", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Enable detailed melee debug logging (0 = off, 1 = on)")
local cl_debug_collisions = CreateClientConVar("vrmod_debug_collisions", "0", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
g_VR = g_VR or {}
g_VR.enhanced = true
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}
--GLOBALS
vrmod.SMOOTHING_FACTOR = 0.98
vrmod.DEFAULT_RADIUS = 2.75
vrmod.DEFAULT_REACH = 5.5
vrmod.DEFAULT_MINS = Vector(-0.75, -0.75, -1.25)
vrmod.DEFAULT_MAXS = Vector(0.75, 0.75, 11)
vrmod.DEFAULT_ANGLES = Angle(0, 0, 0)
vrmod.DEFAULT_OFFSET = 4
vrmod.MODEL_OVERRIDES = {
    weapon_physgun = "models/weapons/w_physics.mdl",
    weapon_physcannon = "models/weapons/w_physics.mdl",
}

vrmod.suppressViewModelUpdates = false
local magCache = {}
local modelCache = {}
local pending = {}
local collisionSpheres = {}
local collisionBoxes = {}
local lastLeftPos = Vector(0, 0, 0)
local lastRightPos = Vector(0, 0, 0)
local lastRightAng = Angle(0, 0, 0)
local lastNonClippedPos = {
    left = nil,
    right = nil
}

local lastNonClippedNormal = {
    left = nil,
    right = nil
}

local cachedPushOutPos = {
    left = nil,
    right = nil
}

local trackedRagdolls = trackedRagdolls or {}
local lastDamageTime = {}
local cachedBonePos, cachedBoneAng, cachedFrame = nil, nil, 0
-- HELPERS
local function tostr(v)
    if istable(v) then
        local parts = {}
        for k, val in pairs(v) do
            table.insert(parts, tostring(k) .. "=" .. tostr(val))
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif IsEntity and IsEntity(v) and v:IsValid() then
        return string.format("Entity[%s:%s]", v:GetClass(), v:EntIndex())
    elseif IsEntity and IsEntity(v) then
        return "Entity[INVALID]"
    elseif isvector and isvector(v) then
        return string.format("Vector(%.2f, %.2f, %.2f)", v.x, v.y, v.z)
    elseif isangle and isangle(v) then
        return string.format("Angle(%.2f, %.2f, %.2f)", v.p, v.y, v.r)
    else
        return tostring(v)
    end
end

local function IsMagazine(ent)
    local class = ent:GetClass()
    if magCache[class] ~= nil then return magCache[class] end
    local isMag = string.StartWith(class, "avrmag_")
    magCache[class] = isMag
    return isMag
end

local function GetWeaponCollisionBox(phys, isVertical)
    local mins, maxs = phys:GetAABB()
    if not mins or not maxs then
        vrmod.utils.DebugPrint("GetWeaponCollisionBox: Invalid AABB, returning defaults")
        return vrmod.DEFAULT_MINS, vrmod.DEFAULT_MAXS, isVertical, vrmod.DEFAULT_MINS, vrmod.DEFAULT_MAXS
    end

    local amin, amax = mins, maxs -- Store raw AABB for return
    -- Calculate the extents of the AABB
    local extents = (maxs - mins) * 0.5
    if isVertical then
        -- Vertical alignment: prioritize z-axis, swap x and z extents
        mins = Vector(-extents.z * 0.35, -extents.y * 0.35, -extents.x)
        maxs = Vector(extents.z * 0.35, extents.y * 0.35, extents.x)
        vrmod.utils.DebugPrint("GetWeaponCollisionBox: Vertical-aligned (z-axis) | Mins: %s, Maxs: %s", tostring(mins), tostring(maxs))
    else
        -- Forward alignment: prioritize x-axis
        mins = Vector(-extents.x * 0.8, -extents.y * 0.35, -extents.z * 0.35)
        maxs = Vector(extents.x * 0.8, extents.y * 0.35, extents.z * 0.35)
        vrmod.utils.DebugPrint("GetWeaponCollisionBox: Forward-aligned (x-axis) | Mins: %s, Maxs: %s", tostring(mins), tostring(maxs))
    end

    -- Ensure the box isn't too small by enforcing minimum dimensions
    local minSize = vrmod.DEFAULT_RADIUS * 0.5
    mins.x = math.min(mins.x, -minSize)
    mins.y = math.min(mins.y, -minSize)
    mins.z = math.min(mins.z, -minSize)
    maxs.x = math.max(maxs.x, minSize)
    maxs.y = math.max(maxs.y, minSize)
    maxs.z = math.max(maxs.z, minSize)
    return mins, maxs, isVertical, amin, amax
end

local function SphereCollidesWithWorld(pos, radius)
    local hullSize = Vector(radius, radius, radius)
    -- First: detect overlap
    local tr = util.TraceHull({
        start = pos,
        endpos = pos,
        mins = -hullSize,
        maxs = hullSize,
        mask = MASK_SOLID_BRUSHONLY
    })

    if not tr.Hit or not tr.HitWorld then return false, Vector(0, 0, 1) end
    -- Second: iterative push-out (resolve penetration)
    local maxIterations = 5
    local pushPos = pos
    local hitNormal = tr.HitNormal
    for _ = 1, maxIterations do
        local pushTrace = util.TraceHull({
            start = pushPos,
            endpos = pushPos + hitNormal * radius * 1.1,
            mins = -hullSize,
            maxs = hullSize,
            mask = MASK_SOLID_BRUSHONLY
        })

        if not pushTrace.Hit then
            pushPos = pushTrace.EndPos
            break
        else
            pushPos = pushTrace.HitPos + pushTrace.HitNormal * 0.1
            hitNormal = pushTrace.HitNormal
        end
    end
    return true, hitNormal, pushPos
end

local function BoxCollidesWithWorld(pos, ang, mins, maxs, reach)
    ang = ang or Angle()
    ang:Normalize()
    local hullMins, hullMaxs
    local tr
    if not reach then
        hullMins = Vector(mins.x, mins.y, mins.z)
        hullMaxs = Vector(maxs.x, maxs.y, maxs.z)
        tr = util.TraceHull({
            start = pos,
            endpos = pos,
            angles = ang,
            mins = hullMins,
            maxs = hullMaxs,
            mask = MASK_SOLID_BRUSHONLY
        })
    else
        hullMins = Vector(mins.x, mins.y, mins.z)
        hullMaxs = Vector(maxs.x, maxs.y, maxs.z)
        local sweepEnd = pos + ang:Forward() * reach
        tr = util.TraceHull({
            start = pos,
            endpos = sweepEnd,
            angles = ang,
            mins = hullMins,
            maxs = hullMaxs,
            mask = MASK_SOLID_BRUSHONLY
        })
    end

    if not tr.Hit or not tr.HitWorld then return false, Vector(0, 0, 1), pos end
    local hitNormal = tr.HitNormal
    local pushPos
    if not tr.StartSolid then
        -- Started free, hit during movement/sweep: back off slightly from contact center pos
        if tr.StartPos and tr.EndPos and tr.Fraction then
            local contactCenter = tr.StartPos + (tr.EndPos - tr.StartPos) * tr.Fraction
            pushPos = contactCenter - tr.HitNormal * 0.1
        else
            -- Fallback if trace data is invalid
            pushPos = pos - (hitNormal:IsZero() and Vector(0, 0, 1) or hitNormal) * 0.1
        end
    else
        -- Started in solid: iterative resolution to find free pos
        if hitNormal:LengthSqr() < 0.1 then
            hitNormal = Vector(0, 0, 1) -- Default to up if no valid initial normal
        end

        local boxSize = math.max(hullMaxs.x - hullMins.x, hullMaxs.y - hullMins.y, hullMaxs.z - hullMins.z) / 2
        pushPos = pos
        local maxIterations = 5
        for _ = 1, maxIterations do
            local pushTrace = util.TraceHull({
                start = pushPos,
                endpos = pushPos + hitNormal * boxSize * 1.1,
                angles = ang,
                mins = hullMins,
                maxs = hullMaxs,
                mask = MASK_SOLID_BRUSHONLY
            })

            if not pushTrace.Hit then
                pushPos = pushTrace.EndPos
                break
            else
                pushPos = pushTrace.HitPos + pushTrace.HitNormal * 0.1
                hitNormal = pushTrace.HitNormal
            end
        end
    end
    return true, hitNormal, pushPos
end

local function DetectMeleeFromModel(modelPath, phys, offsetAng)
    if not IsValid(phys) then return false end
    -- 1. Filename hints
    local lowerPath = string.lower(modelPath)
    if lowerPath:find("crowbar") or lowerPath:find("knife") or lowerPath:find("melee") or lowerPath:find("bat") or lowerPath:find("katana") or lowerPath:find("sword") then return true end
    -- 2. Get raw bounding box verts
    local mins, maxs = phys:GetAABB()
    local verts = {Vector(mins.x, mins.y, mins.z), Vector(mins.x, mins.y, maxs.z), Vector(mins.x, maxs.y, mins.z), Vector(mins.x, maxs.y, maxs.z), Vector(maxs.x, mins.y, mins.z), Vector(maxs.x, mins.y, maxs.z), Vector(maxs.x, maxs.y, mins.z), Vector(maxs.x, maxs.y, maxs.z)}
    -- 3. Apply VRMod offsetAng if provided (align model to hand space)
    local ang = offsetAng or Angle(0, 0, 0)
    for i = 1, #verts do
        verts[i]:Rotate(ang)
    end

    -- 4. Measure extents in aligned space
    local minAligned = Vector(verts[1].x, verts[1].y, verts[1].z)
    local maxAligned = Vector(verts[1].x, verts[1].y, verts[1].z)
    for i = 2, #verts do
        minAligned.x = math.min(minAligned.x, verts[i].x)
        minAligned.y = math.min(minAligned.y, verts[i].y)
        minAligned.z = math.min(minAligned.z, verts[i].z)
        maxAligned.x = math.max(maxAligned.x, verts[i].x)
        maxAligned.y = math.max(maxAligned.y, verts[i].y)
        maxAligned.z = math.max(maxAligned.z, verts[i].z)
    end

    local sizeX = maxAligned.x - minAligned.x
    local sizeY = maxAligned.y - minAligned.y
    local sizeZ = maxAligned.z - minAligned.z
    local longest = math.max(sizeX, sizeY, sizeZ)
    local shortest = math.min(sizeX, sizeY, sizeZ)
    if shortest < 0.01 then return false end
    local aspect = longest / shortest
    -- 5. Melee = longest axis is aligned Z (up in hand space) + long/thin shape
    if sizeZ == longest and aspect >= 4.5 then return true end
    return false
end

local function GetApproximateBoneId(vehicle, targetNames)
    if not IsValid(vehicle) then return nil end
    local boneCount = vehicle:GetBoneCount()
    if boneCount <= 0 then return nil end
    for i = 0, boneCount - 1 do
        local boneName = vehicle:GetBoneName(i)
        if boneName then
            for _, target in ipairs(targetNames) do
                if string.find(string.lower(boneName), string.lower(target), 1, true) then return i end
            end
        end
    end
    return nil
end

--MATH
function vrmod.utils.VecAlmostEqual(v1, v2, threshold)
    if not v1 or not v2 then return false end
    return v1:DistToSqr(v2) < (threshold or 0.001) ^ 2
end

function vrmod.utils.AngAlmostEqual(a1, a2, threshold)
    if not a1 or not a2 then return false end
    threshold = threshold or 0.1 -- degrees
    return math.abs(math.AngleDifference(a1.p, a2.p)) < threshold and math.abs(math.AngleDifference(a1.y, a2.y)) < threshold and math.abs(math.AngleDifference(a1.r, a2.r)) < threshold
end

function vrmod.utils.LengthSqr(v)
    return v.x * v.x + v.y * v.y + v.z * v.z
end

function vrmod.utils.SubVec(a, b)
    return Vector(a.x - b.x, a.y - b.y, a.z - b.z)
end

function vrmod.utils.SmoothVector(current, target, smoothingFactor)
    return current + (target - current) * smoothingFactor
end

function vrmod.utils.LerpAngleWrap(factor, current, target)
    local diff = math.AngleDifference(target, current) -- handles ±180 wrap
    return current + diff * factor
end

function vrmod.utils.SmoothAngle(current, target, smoothingFactor)
    local diff = target - current
    diff.p = math.NormalizeAngle(diff.p)
    diff.y = math.NormalizeAngle(diff.y)
    diff.r = math.NormalizeAngle(diff.r)
    return current + diff * smoothingFactor
end

-- SYSTEM
function vrmod.utils.CalculateProjectionParams(projMatrix, worldScale)
    local xscale = projMatrix[1][1]
    local xoffset = projMatrix[1][3]
    local yscale = projMatrix[2][2]
    local yoffset = projMatrix[2][3]
    -- ** Normalize vertical sign: **
    if not system.IsWindows() then
        -- On Linux/OpenGL: invert the sign so + means “down” just like on Windows
        yoffset = -yoffset
    end

    -- now the rest is identical on both platforms:
    local tan_px = math.abs((1 - xoffset) / xscale)
    local tan_nx = math.abs((-1 - xoffset) / xscale)
    local tan_py = math.abs((1 - yoffset) / yscale)
    local tan_ny = math.abs((-1 - yoffset) / yscale)
    local w = (tan_px + tan_nx) / worldScale
    local h = (tan_py + tan_ny) / worldScale
    return {
        HorizontalFOV = math.deg(2 * math.atan(w / 2)),
        AspectRatio = w / h,
        HorizontalOffset = xoffset,
        VerticalOffset = yoffset,
        Width = w,
        Height = h,
    }
end

function vrmod.utils.ComputeSubmitBounds(leftCalc, rightCalc, hOffset, vOffset, scaleFactor, renderOffset)
    local isWindows = system.IsWindows()
    local hFactor, vFactor = 0, 0
    -- average half‐eye extents in tangent space
    if renderOffse then
        local wAvg = (leftCalc.Width + rightCalc.Width) * 0.5
        local hAvg = (leftCalc.Height + rightCalc.Height) * 0.5
        hFactor = 0.5 / wAvg
        vFactor = 1.0 / hAvg
    else
        --original calues
        hFactor = 0.25
        vFactor = 0.5
    end

    hFactor = hFactor * scaleFactor
    vFactor = vFactor * scaleFactor
    -- UV origin flip only affects V‐range endpoints, not the offset sign:
    local vMin, vMax = isWindows and 0 or 1, isWindows and 1 or 0
    local function calcVMinMax(offset)
        local adj = offset * vFactor
        return vMin - adj, vMax - adj
    end

    -- U bounds
    local uMinLeft = 0.0 + (leftCalc.HorizontalOffset + hOffset) * hFactor
    local uMaxLeft = 0.5 + (leftCalc.HorizontalOffset + hOffset) * hFactor
    local uMinRight = 0.5 + (rightCalc.HorizontalOffset + hOffset) * hFactor
    local uMaxRight = 1.0 + (rightCalc.HorizontalOffset + hOffset) * hFactor
    -- V bounds
    local vMinLeft, vMaxLeft = calcVMinMax(leftCalc.VerticalOffset + vOffset)
    local vMinRight, vMaxRight = calcVMinMax(rightCalc.VerticalOffset + vOffset)
    return uMinLeft, vMinLeft, uMaxLeft, vMaxLeft, uMinRight, vMinRight, uMaxRight, vMaxRight
end

function vrmod.utils.ComputeDesktopCrop(desktopView, w, h)
    local vmargin = (1 - ScrH() / ScrW() * w / 2 / h) / 2
    local hoffset = desktopView == 3 and 0.5 or 0
    return vmargin, hoffset
end

function vrmod.utils.AdjustFOV(proj, fovScaleX, fovScaleY)
    local clone = {}
    for i = 1, 4 do
        clone[i] = {proj[i][1], proj[i][2], proj[i][3], proj[i][4]}
    end

    -- scale the FOV (diagonal terms)
    clone[1][1] = clone[1][1] * fovScaleX
    clone[2][2] = clone[2][2] * fovScaleY
    -- scale the center offset (asymmetry) terms
    clone[1][3] = clone[1][3] * fovScaleX
    clone[2][3] = clone[2][3] * fovScaleY
    return clone
end

function vrmod.utils.DrawDeathAnimation(rtWidth, rtHeight)
    if not g_VR.deathTime then g_VR.deathTime = CurTime() end
    local fadeAlpha = 0
    local fadeDuration = 3.5
    local maxAlpha = 200
    local progress = math.min((CurTime() - g_VR.deathTime) / fadeDuration, 1)
    fadeAlpha = math.min(progress * maxAlpha, maxAlpha)
    cam.Start2D()
    surface.SetDrawColor(120, 0, 0, fadeAlpha)
    surface.DrawRect(0, 0, rtWidth, rtHeight)
    cam.End2D()
end

function vrmod.utils.ConvertToRelativeFrame(absFrame)
    local lp = LocalPlayer()
    if not IsValid(lp) then return nil end
    local vehicle = lp:GetNWEntity("GlideVehicle")
    local plyAng
    if IsValid(vehicle) then
        plyAng = vehicle:GetAngles()
    elseif lp:InVehicle() then
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
    return true
end

function vrmod.utils.GetHandCursorOnPlane(ply, hand, planeOffset)
    planeOffset = planeOffset or 50 -- units in front of eyes
    local startPos, dir
    if hand == "left" then
        startPos = vrmod.GetLeftHandPos(ply)
        local ang = vrmod.GetLeftHandAng(ply)
        if not startPos or not ang then return nil end
        local ang2 = Angle(ang.p, ang.y, ang.r + 180)
        dir = ang2:Forward()
    else
        startPos = vrmod.GetRightHandPos(ply)
        local ang = vrmod.GetRightHandAng(ply)
        if not startPos or not ang then return nil end
        dir = ang:Forward()
    end

    -- fallback to head if hand is missing
    if not startPos or not dir then
        startPos = ply:EyePos()
        dir = ply:EyeAngles():Forward()
    end

    local planeNormal = ply:EyeAngles():Forward()
    local planePoint = ply:EyePos() + planeNormal * planeOffset
    local denom = planeNormal:Dot(dir)
    if math.abs(denom) < 0.0001 then return nil end
    local t = (planePoint - startPos):Dot(planeNormal) / denom
    if t < 0 then return nil end
    local hitPos = startPos + dir * t
    local screenPos = hitPos:ToScreen()
    if not screenPos then return nil end
    return screenPos.x, screenPos.y
end

-- WEP UTILS
function vrmod.utils.IsValidWep(wep, get)
    if not IsValid(wep) then return false end
    local class = wep:GetClass()
    local vm
    vm = vrmod.MODEL_OVERRIDES[class] or wep:GetWeaponViewModel()
    if class == "weapon_vrmod_empty" or vm == "" or vm == "models/weapons/c_arms.mdl" then return false end
    if get then
        return class, vm
    else
        return true
    end
end

function vrmod.utils.IsWeaponEntity(ent)
    if not IsValid(ent) then return false end
    local c = ent:GetClass()
    return ent:IsWeapon() or c:find("weapon_") or c == "prop_physics" and ent:GetModel():find("w_")
end

function vrmod.utils.WepInfo(wep)
    local class, vm = vrmod.utils.IsValidWep(wep, true)
    if class and vm then return class, vm end
end

function vrmod.utils.UpdateViewModelPos(pos, ang, override)
    local ply = LocalPlayer()
    if vrmod.suppressViewModelUpdates and not override then
        vrmod.utils.UpdateViewModel()
        return
    end

    pos, ang = vrmod.utils.CheckWeaponPushout(pos, ang)
    if not IsValid(ply) or not g_VR.active then return end
    if not ply:Alive() or ply:InVehicle() then return end
    local currentvmi = g_VR.currentvmi
    local modelPos = pos
    if currentvmi then
        local collisionShape = vrmod._collisionShapeByHand and vrmod._collisionShapeByHand.right
        if collisionShape and collisionShape.isClipped and collisionShape.pushOutPos then
            modelPos = collisionShape.pushOutPos
            vrmod.utils.DebugPrint("[VRMod] Applying collision-corrected pos for viewmodel:", modelPos)
        end

        local offsetPos, offsetAng = LocalToWorld(currentvmi.offsetPos, currentvmi.offsetAng, modelPos, ang)
        g_VR.viewModelPos = offsetPos
        g_VR.viewModelAng = offsetAng
        vrmod.utils.UpdateViewModel()
    end
end

function vrmod.utils.UpdateViewModel()
    local vm = g_VR.viewModel
    if IsValid(vm) then
        if not g_VR.usingWorldModels then
            vm:SetPos(g_VR.viewModelPos)
            vm:SetAngles(g_VR.viewModelAng)
            vm:SetupBones()
        end

        g_VR.viewModelMuzzle = vm:GetAttachment(1)
    end
end

--FILTERS AND TRACE UTILS
function vrmod.utils.HitFilter(ent, ply, hand)
    if not IsValid(ent) then return false end
    if ent == ply then return end
    if ent:GetNWBool("isVRHand", false) then return false end
    if IsValid(ply) and (hand == "left" or hand == "right") then
        local held = vrmod.GetHeldEntity(ply, hand)
        if IsValid(held) and held == ent then return false end
    end
    return true
end

function vrmod.utils.MeleeFilter(ent, ply, hand)
    return vrmod.utils.HitFilter(ent, ply, hand) and not IsMagazine(ent)
end

function vrmod.utils.TraceHand(ply, hand)
    local startPos, ang, dir
    if hand == "left" then
        startPos = vrmod.GetLeftHandPos(ply)
        ang = vrmod.GetLeftHandAng(ply)
        if not ang then return nil end
        local ang2 = Angle(ang.p, ang.y, ang.r + 180)
        dir = ang2:Forward()
    else
        startPos = vrmod.GetRightHandPos(ply)
        ang = vrmod.GetRightHandAng(ply)
        if not ang then return nil end
        dir = ang:Forward()
    end

    if not startPos or not dir then return nil end
    local ignore = {}
    local maxDepth = 10
    for i = 1, maxDepth do
        local tr = util.TraceLine({
            start = startPos,
            endpos = startPos + dir * 32768,
            filter = ignore
        })

        if not tr.Entity or not IsValid(tr.Entity) then return tr end
        if vrmod.utils.HitFilter(tr.Entity, ply, hand) then
            return tr
        else
            table.insert(ignore, tr.Entity)
            startPos = tr.HitPos + dir * 1 -- Avoid infinite loops on same surface
        end
    end
    return nil -- Nothing valid hit after maxDepth
end

function vrmod.utils.TraceBoxOrSphere(data)
    local best = {
        Hit = false,
        Fraction = 1
    }

    if data.mins and data.maxs then
        -- Box trace
        local tr = util.TraceHull({
            start = data.start,
            endpos = data.endpos,
            mins = data.mins,
            maxs = data.maxs,
            filter = data.filter,
            mask = data.mask
        })

        if tr.Hit then
            best = tr
            best.Hit = true
        end
    else
        -- Sphere approximation with single hull trace
        local radius = data.radius or vrmod.DEFAULT_RADIUS
        local tr = util.TraceHull({
            start = data.start,
            endpos = data.endpos,
            mins = Vector(-radius, -radius, -radius),
            maxs = Vector(radius, radius, radius),
            filter = data.filter,
            mask = data.mask
        })

        if tr.Hit then
            best = tr
            best.Hit = true
        end
    end
    return best
end

-- COLLISIONS
function vrmod.utils.ComputePhysicsParams(modelPath)
    if not modelPath or modelPath == "" then
        vrmod.utils.DebugPrint("Invalid or empty model path, caching defaults")
        modelCache[modelPath] = {
            radius = vrmod.DEFAULT_RADIUS,
            reach = vrmod.DEFAULT_REACH,
            mins_horizontal = vrmod.DEFAULT_MINS,
            maxs_horizontal = vrmod.DEFAULT_MAXS,
            mins_vertical = vrmod.DEFAULT_MINS,
            maxs_vertical = vrmod.DEFAULT_MAXS,
            angles = vrmod.DEFAULT_ANGLES,
            computed = true,
            isMelee = false
        }
        return
    end

    local originalModelPath = modelPath
    -- Fallback for c_models to w_models
    if modelPath:match("^models/weapons/c_") then
        local baseName = modelPath:match("models/weapons/c_(.-)%.mdl")
        if baseName then
            local fallback = "models/weapons/w_" .. baseName .. ".mdl"
            if file.Exists(fallback, "GAME") then
                vrmod.utils.DebugPrint("Replacing %s with valid worldmodel %s", modelPath, fallback)
                modelPath = fallback
            else
                vrmod.utils.DebugPrint("No valid fallback for %s, caching defaults", modelPath)
                modelCache[originalModelPath] = {
                    radius = vrmod.DEFAULT_RADIUS,
                    reach = vrmod.DEFAULT_REACH,
                    mins_horizontal = vrmod.DEFAULT_MINS,
                    maxs_horizontal = vrmod.DEFAULT_MAXS,
                    mins_vertical = vrmod.DEFAULT_MINS,
                    maxs_vertical = vrmod.DEFAULT_MAXS,
                    angles = vrmod.DEFAULT_ANGLES,
                    computed = true,
                    isMelee = false
                }
                return
            end
        end
    end

    -- Already computed?
    if modelCache[originalModelPath] and modelCache[originalModelPath].computed then return end
    -- Retry protection
    pending[originalModelPath] = pending[originalModelPath] or {
        attempts = 0
    }

    if pending[originalModelPath].attempts >= 2 then
        vrmod.utils.DebugPrint("Max retries (2) reached for %s, caching defaults", originalModelPath)
        modelCache[originalModelPath] = {
            radius = vrmod.DEFAULT_RADIUS,
            reach = vrmod.DEFAULT_REACH,
            mins_horizontal = vrmod.DEFAULT_MINS,
            maxs_horizontal = vrmod.DEFAULT_MAXS,
            mins_vertical = vrmod.DEFAULT_MINS,
            maxs_vertical = vrmod.DEFAULT_MAXS,
            angles = vrmod.DEFAULT_ANGLES,
            computed = true,
            isMelee = false
        }

        pending[originalModelPath] = nil
        return
    end

    pending[originalModelPath].attempts = pending[originalModelPath].attempts + 1
    util.PrecacheModel(modelPath)
    local ent = CLIENT and ents.CreateClientProp(modelPath) or ents.Create("prop_physics")
    if not IsValid(ent) then
        vrmod.utils.DebugPrint("Failed to spawn %s (attempt %d)", modelPath, pending[originalModelPath].attempts)
        pending[originalModelPath].lastAttempt = CurTime()
        return
    end

    ent:SetModel(modelPath)
    ent:SetNoDraw(true)
    ent:PhysicsInit(SOLID_VPHYSICS)
    ent:SetMoveType(MOVETYPE_NONE)
    ent:Spawn()
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        local ang = Angle(0, 0, 0)
        local currentvmi = g_VR.currentvmi
        if currentvmi then ang = currentvmi.offsetAng end
        local isMelee = DetectMeleeFromModel(modelPath, phys, ang)
        local mins_horizontal, maxs_horizontal, mins_vertical, maxs_vertical
        if isMelee then
            mins_vertical, maxs_vertical = GetWeaponCollisionBox(phys, true)
            mins_horizontal, maxs_horizontal = vrmod.DEFAULT_MINS, vrmod.DEFAULT_MAXS
        else
            mins_horizontal, maxs_horizontal, _, amin, amax = GetWeaponCollisionBox(phys, false)
            mins_vertical, maxs_vertical = GetWeaponCollisionBox(phys, true)
        end

        local mins, maxs = phys:GetAABB()
        local reach = math.max(maxs.x - mins.x, maxs.y - mins.y, maxs.z - mins.z) * 0.5
        reach = math.Clamp(reach * 1.5, 6.6, 50)
        modelCache[originalModelPath] = {
            radius = reach,
            reach = reach,
            mins_horizontal = mins_horizontal or vrmod.DEFAULT_MINS,
            maxs_horizontal = maxs_horizontal or vrmod.DEFAULT_MAXS,
            mins_vertical = mins_vertical or vrmod.DEFAULT_MINS,
            maxs_vertical = maxs_vertical or vrmod.DEFAULT_MAXS,
            angles = vrmod.DEFAULT_ANGLES,
            computed = true,
            isMelee = isMelee
        }

        vrmod.utils.DebugPrint("Computed collision boxes for %s → reach: %.2f units, melee: %s", modelPath, reach, tostring(isMelee))
    else
        vrmod.utils.DebugPrint("No valid physobj for %s, attempt %d", modelPath, pending[originalModelPath].attempts)
    end

    ent:Remove()
    pending[originalModelPath].lastAttempt = CurTime()
    if pending[originalModelPath].attempts >= 2 then pending[originalModelPath] = nil end
end

function vrmod.utils.GetModelParams(modelPath, ply, offsetAng)
    if modelCache[modelPath] and modelCache[modelPath].computed then
        local cache = modelCache[modelPath]
        local ang = vrmod.GetRightHandAng(ply)
        local mins = cache.isMelee and cache.mins_vertical or cache.mins_horizontal
        local maxs = cache.isMelee and cache.maxs_vertical or cache.maxs_horizontal
        -- Validate that parameters aren't just defaults
        local isDefault = mins == vrmod.DEFAULT_MINS and maxs == vrmod.DEFAULT_MAXS and cache.radius == vrmod.DEFAULT_RADIUS and cache.reach == vrmod.DEFAULT_REACH
        if not isDefault then
            -- Only send once per model
            if not cache.sent then
                if CLIENT then
                    net.Start("vrmod_sync_model_params")
                    net.WriteString(modelPath)
                    net.WriteFloat(cache.radius)
                    net.WriteFloat(cache.reach)
                    net.WriteVector(mins)
                    net.WriteVector(maxs)
                    net.WriteVector(cache.mins_vertical)
                    net.WriteVector(cache.maxs_vertical)
                    net.WriteAngle(cache.angles)
                    net.SendToServer()
                    vrmod.utils.DebugPrint("GetModelParams: Sent computed params for %s to server", modelPath)
                elseif SERVER then
                    net.Start("vrmod_sync_model_params")
                    net.WriteString(modelPath)
                    net.WriteFloat(cache.radius)
                    net.WriteFloat(cache.reach)
                    net.WriteVector(mins)
                    net.WriteVector(maxs)
                    net.WriteVector(cache.mins_vertical)
                    net.WriteVector(cache.maxs_vertical)
                    net.WriteAngle(cache.angles)
                    net.Broadcast()
                    vrmod.utils.DebugPrint("GetModelParams: Sent computed params for %s to clients", modelPath)
                end

                -- mark as sent
                cache.sent = true
            end
        else
            vrmod.utils.DebugPrint("GetModelParams: Skipping sync for %s due to default parameters", modelPath)
        end
        return cache.radius, cache.reach, mins, maxs, ang, cache.isMelee
    end

    -- Schedule computation if needed
    if not pending[modelPath] then
        pending[modelPath] = {
            attempts = 0
        }

        timer.Simple(0, function()
            vrmod.utils.ComputePhysicsParams(modelPath)
            -- Optionally re-call GetModelParams to trigger sync after computation
            if modelCache[modelPath] and modelCache[modelPath].computed then vrmod.utils.GetModelParams(modelPath, ply, offsetAng) end
        end)

        vrmod.utils.DebugPrint("GetModelParams: Scheduled computation for %s", modelPath)
    end
    return vrmod.DEFAULT_RADIUS, vrmod.DEFAULT_REACH, vrmod.DEFAULT_MINS, vrmod.DEFAULT_MAXS, vrmod.GetRightHandAng(ply), false
end

function vrmod.utils.GetWeaponMeleeParams(wep, ply, hand)
    local model = cl_effectmodel:GetString()
    local offsetAng = vrmod.DEFAULT_ANGLES
    if hand == "right" then
        local class, vm = vrmod.utils.WepInfo(wep)
        if not class then return vrmod.DEFAULT_RADIUS, vrmod.DEFAULT_REACH end
        if CLIENT then
            local vmInfo = g_VR.viewModelInfo[class]
            offsetAng = vmInfo and vmInfo.offsetAng or vrmod.DEFAULT_ANGLES
            model = vm
        else
            model = vrmod.MODEL_OVERRIDES[class] or wep:GetModel()
        end
        return vrmod.utils.GetModelParams(model, ply, offsetAng)
    else
        return vrmod.utils.GetModelParams(model, ply, offsetAng)
    end
end

function vrmod.utils.GetCachedWeaponParams(wep, ply, side)
    if not vrmod.utils.IsValidWep(wep) then return nil end
    local radius, reach, mins, maxs, angles, isMelee = vrmod.utils.GetWeaponMeleeParams(wep, ply, side)
    local model = vrmod.utils.WepInfo(wep)
    if SERVER and modelCache[model] and modelCache[model].computed then
        local c = modelCache[model]
        vrmod.utils.DebugPrint("GetCachedWeaponParams: Using server-side synced params for %s", model)
        return c.radius, c.reach, c.mins_horizontal, c.maxs_horizontal, c.angles, c.isMelee
    end

    if pending[model] and CurTime() - (pending[model].lastAttempt or 0) < 2 then
        vrmod.utils.DebugPrint("GetCachedWeaponParams: Computation pending for %s, waiting", model)
        return nil
    end

    if radius ~= vrmod.DEFAULT_RADIUS or reach ~= vrmod.DEFAULT_REACH or mins ~= vrmod.DEFAULT_MINS then return radius, reach, mins, maxs, angles, isMelee end
    if not pending[model] then
        vrmod.utils.DebugPrint("GetCachedWeaponParams: Scheduling computation for %s", model)
        timer.Simple(0, function() vrmod.utils.ComputePhysicsParams(model) end)
    end
    return nil
end

function vrmod.utils.AdjustCollisionsBox(pos, ang, isMelee)
    local forwardOffset = isMelee and 3 or 10
    local leftOffset = isMelee and 1 or 1.5
    local upOffset = 4
    local adjustedPos = pos + ang:Forward() * forwardOffset - ang:Right() * leftOffset + ang:Up() * upOffset
    return adjustedPos
end

function vrmod.utils.CollisionsPreCheck(leftPos, rightPos)
    local ply = LocalPlayer()
    if not IsValid(ply) or not g_VR.active or not ply:GetNWBool("vrmod_server_enforce_collision", true) or not ply:Alive() or not vrmod.IsPlayerInVR(ply) or ply:InVehicle() then
        vrmod._collisionNearby = false
        return
    end

    -- Use your accessor functions — they return world-space vectors
    local bigRadius = vrmod.utils.IsValidWep(ply:GetActiveWeapon()) and 69 or 30
    local leftNearby = SphereCollidesWithWorld(leftPos, 30)
    local rightNearby = SphereCollidesWithWorld(rightPos, bigRadius)
    vrmod._collisionNearby = leftNearby or rightNearby
end

function vrmod.utils.CheckWorldCollisions(pos, radius, mins, maxs, ang, hand, reach)
    local shapeMins = mins or Vector(-radius, -radius, -radius)
    local shapeMaxs = maxs or Vector(radius, radius, radius)
    ang = ang or Angle(0, 0, 0) -- Fallback to zero angle
    ang:Normalize()
    local isClipped, hitNormal
    if mins and maxs then
        -- Clipping check: full box, no reach
        --isClipped, hitNormal = SphereCollidesWithWorld(pos, reach)
        isClipped, hitNormal = BoxCollidesWithWorld(pos, ang, shapeMins, shapeMaxs)
        if isClipped then vrmod.utils.DebugPrint("[VRMod] Box collision for:", hand, "Pos:", pos, "Angles:", ang, "Mins:", shapeMins, "Maxs:", shapeMaxs, "Hit:", isClipped) end
    else
        if not radius then radius = vrmod.DEFAULT_RADIUS end
        isClipped, hitNormal = SphereCollidesWithWorld(pos, radius)
        if isClipped then vrmod.utils.DebugPrint("[VRMod] Sphere collision for:", hand, "Pos:", pos, "Radius:", radius, "Hit:", isClipped) end
    end

    local pushOutPos = pos
    if isClipped then
        if lastNonClippedPos[hand] then
            pushOutPos = lastNonClippedPos[hand]
        else
            local traceOut = util.TraceHull({
                start = pos,
                endpos = pos + hitNormal * 2, -- Increase trace distance
                mins = shapeMins, -- Smaller hull for correction
                maxs = shapeMaxs,
                mask = MASK_SOLID_BRUSHONLY
            })

            pushOutPos = traceOut.Hit and traceOut.HitPos + traceOut.HitNormal or pos + hitNormal
        end

        cachedPushOutPos[hand] = pushOutPos
    else
        lastNonClippedPos[hand] = pos
        cachedPushOutPos[hand] = nil
    end

    local reachHit
    if mins and maxs then
        reachHit, _ = BoxCollidesWithWorld(pos, ang, shapeMins, shapeMaxs, reach)
    else
        local tr = util.TraceLine({
            start = pos,
            endpos = pos + ang:Forward() * reach,
            mask = MASK_SOLID_BRUSHONLY
        })

        reachHit = tr.Hit and tr.HitWorld or false
    end

    local shape = {
        pos = pos,
        radius = radius,
        mins = shapeMins,
        maxs = shapeMaxs,
        angles = ang,
        hit = reachHit,
        pushOutPos = pushOutPos,
        isClipped = isClipped,
        hitNormal = hitNormal
    }

    shape.hitWorld = mins and maxs and BoxCollidesWithWorld(pos, ang, shapeMins, shapeMaxs) or SphereCollidesWithWorld(pos, radius or vrmod.DEFAULT_RADIUS)
    return shape
end

function vrmod.utils.CheckWeaponPushout(pos, ang)
    --local pos, ang = g_VR.viewModelPos, g_VR.viewModelAng
    -- Early out if no collision broad-phase
    if not vrmod._collisionNearby then
        collisionBoxes = {}
        return pos, ang
    end

    local ply = LocalPlayer()
    if not IsValid(ply) then return pos, ang end
    local wep = ply:GetActiveWeapon()
    if not vrmod.utils.IsValidWep(wep) then return pos, ang end
    local radius, reach, mins, maxs, _, isMelee = vrmod.utils.GetCachedWeaponParams(wep, ply, "right")
    radius = radius or vrmod.DEFAULT_RADIUS
    mins = mins or vrmod.DEFAULT_MINS
    maxs = maxs or vrmod.DEFAULT_MAXS
    reach = reach or vrmod.DEFAULT_REACH
    --print(isMelee)
    if not isnumber(reach) then reach = math.max(math.abs(maxs.x), math.abs(maxs.y), math.abs(maxs.z)) * 2 end
    local adjustedPos = vrmod.utils.AdjustCollisionsBox(pos, ang, isMelee)
    local shape = vrmod.utils.CheckWorldCollisions(adjustedPos, nil, mins, maxs, ang, "right", reach)
    collisionBoxes = {} -- Reset collisionBoxes
    if shape then
        collisionBoxes[1] = shape -- Update collisionBoxes with the weapon shape
    end

    if shape and shape.isClipped and shape.pushOutPos and type(shape.pushOutPos) == "Vector" then
        local normal = shape.hitNormal
        local plyPos = g_VR.tracking.hmd.pos or Vector()
        local distanceSqr = (shape.pushOutPos - plyPos):LengthSqr()
        if distanceSqr > 500 then
            collisionBoxes = {} -- Clear collisionBoxes on reset
            return pos, ang
        end

        -- Calculate corrected position
        local correctedPos = Vector(pos.x, pos.y, pos.z)
        local absX, absY, absZ = math.abs(normal.x), math.abs(normal.y), math.abs(normal.z)
        local penetrationVec = pos - shape.pushOutPos
        local penetrationDepth = penetrationVec:Dot(normal)
        local correctionFactor = 1
        if absX > absY and absX > absZ and absX > 0.45 then
            correctedPos.x = shape.pushOutPos.x + normal.x * penetrationDepth * correctionFactor
        elseif absY > absX and absY > absZ and absY > 0.45 then
            correctedPos.y = shape.pushOutPos.y + normal.y * penetrationDepth * correctionFactor
        elseif absZ > absX and absZ > absY and absZ > 0.45 then
            correctedPos.z = shape.pushOutPos.z + normal.z * penetrationDepth * correctionFactor
        else
            correctedPos = shape.pushOutPos + normal * penetrationDepth * correctionFactor
        end

        -- Calculate corrected angle
        local correctedAng = Angle(ang.pitch, ang.yaw, ang.roll)
        local forward = ang:Forward()
        local dot = forward:Dot(normal)
        if math.abs(dot) > 0.1 then -- Only adjust if not already nearly perpendicular
            -- Project forward onto plane perpendicular to normal
            local adjustedForward = forward - normal * dot
            adjustedForward:Normalize()
            -- Reconstruct angle from adjusted forward vector, preserving right and up as much as possible
            local newRight = adjustedForward:Cross(normal)
            newRight:Normalize()
            local newUp = newRight:Cross(adjustedForward)
            newUp:Normalize()
            correctedAng = adjustedForward:Angle()
            correctedAng:RotateAroundAxis(newRight, ang:Up():Dot(newUp) < 0 and -90 or 90)
        end

        vrmod.utils.DebugPrint("[VRMod] Weapon clipping detected. Push-out pos:", correctedPos, "angle:", correctedAng)
        return correctedPos, correctedAng
    end
    return pos, ang
end

function vrmod.utils.UpdateHandCollisions(lefthandPos, lefthandAng, righthandPos, righthandAng)
    -- Early out if no collision broad-phase
    if not vrmod._collisionNearby then
        if next(collisionSpheres) or next(collisionBoxes) then
            collisionSpheres = {}
            collisionBoxes = {}
            vrmod._collisionShapeByHand = {
                left = nil,
                right = nil
            }

            lastNonClippedPos.left = nil
            lastNonClippedPos.right = nil
            lastNonClippedNormal.left = nil
            lastNonClippedNormal.right = nil
            cachedPushOutPos.left = nil
            cachedPushOutPos.right = nil
        end
        return lefthandPos, lefthandAng, righthandPos, righthandAng
    end

    local ply = LocalPlayer()
    if not IsValid(ply) then return lefthandPos, lefthandAng, righthandPos, righthandAng end
    local wep = ply:GetActiveWeapon()
    if not vrmod.utils.IsValidWep(wep) then collisionBoxes = {} end
    -- Calculate offset positions for collision queries (absolute space)
    local leftPos = lefthandPos + lefthandAng:Forward() * vrmod.DEFAULT_OFFSET
    local rightPos = righthandPos + righthandAng:Forward() * vrmod.DEFAULT_OFFSET
    -- Reset containers for this update
    collisionSpheres = {}
    vrmod._collisionShapeByHand = {
        left = nil,
        right = nil
    }

    vrmod._lastRelFrame = vrmod._lastRelFrame or {}
    local POS_TOLERANCE = 0.05
    local ANG_TOLERANCE = 1.0
    for _, hand in ipairs({"left", "right"}) do
        local pos = hand == "left" and leftPos or rightPos
        local ang = hand == "left" and lefthandAng or righthandAng
        -- Calculate relative pose using g_VR.tracking.hmd
        local hmdPos = g_VR.tracking.hmd.pos or Vector()
        local characterYaw = ply:InVehicle() and ply:EyeAngles().yaw or g_VR.characterYaw
        local yawAng = Angle(0, characterYaw, 0)
        local relPos, relAng = WorldToLocal(pos, ang, hmdPos, yawAng)
        local prevRel = vrmod._lastRelFrame[hand]
        local moved = true
        if prevRel then
            local posEqual = vrmod.utils.VecAlmostEqual(relPos, prevRel.pos, POS_TOLERANCE)
            local angEqual = vrmod.utils.AngAlmostEqual(relAng, prevRel.ang, ANG_TOLERANCE)
            moved = not (posEqual and angEqual)
        end

        local clippedLastFrame = cachedPushOutPos[hand] ~= nil
        local sameNormal = lastNonClippedNormal[hand] and vrmod.utils.VecAlmostEqual(lastNonClippedNormal[hand], pos, 0.3)
        if not moved and clippedLastFrame and sameNormal then
            -- Use cached push-out position
            if hand == "left" then
                lefthandPos = cachedPushOutPos[hand]
            else
                righthandPos = cachedPushOutPos[hand]
            end

            vrmod._lastRelFrame[hand] = {
                pos = relPos,
                ang = relAng
            }
        else
            -- Update last known positions
            if hand == "left" then
                lastLeftPos:Set(leftPos)
            else
                lastRightPos:Set(rightPos)
                lastRightAng:Set(ang)
            end

            -- Perform collision check (always use sphere for hands)
            local radius = vrmod.DEFAULT_RADIUS
            local reach = vrmod.DEFAULT_REACH
            local shape = vrmod.utils.CheckWorldCollisions(pos, radius, nil, nil, ang, hand, reach)
            collisionSpheres[#collisionSpheres + 1] = shape
            vrmod._collisionShapeByHand[hand] = shape
            if shape and shape.isClipped then
                g_VR._cachedFrameRelative = nil
                g_VR._cachedFrameAbsolute = nil
                local normal = shape.hitNormal
                local corrected = Vector(pos.x, pos.y, pos.z)
                local absX, absY, absZ = math.abs(normal.x), math.abs(normal.y), math.abs(normal.z)
                local useLastNonClipped = lastNonClippedPos[hand] and lastNonClippedNormal[hand] and vrmod.utils.VecAlmostEqual(normal, lastNonClippedNormal[hand], 0.1)
                local plyPos = g_VR.tracking.hmd.pos or Vector()
                if shape.pushOutPos and type(shape.pushOutPos) == "Vector" and IsValid(ply) then
                    local distanceSqr = (shape.pushOutPos - plyPos):LengthSqr()
                    if distanceSqr > 500 then
                        lastNonClippedPos[hand] = nil
                        lastNonClippedNormal[hand] = nil
                        cachedPushOutPos[hand] = nil
                        shape.isClipped = false
                    else
                        local penetrationVec = pos - shape.pushOutPos
                        local penetrationDepth = penetrationVec:Dot(normal)
                        local correctionFactor = 2
                        if absX > absY and absX > absZ and absX > 0.45 then
                            corrected.x = useLastNonClipped and lastNonClippedPos[hand].x or shape.pushOutPos.x + normal.x * penetrationDepth * correctionFactor
                        elseif absY > absX and absY > absZ and absY > 0.45 then
                            corrected.y = useLastNonClipped and lastNonClippedPos[hand].y or shape.pushOutPos.y + normal.y * penetrationDepth * correctionFactor
                        elseif absZ > absX and absZ > absY and absZ > 0.45 then
                            corrected.z = useLastNonClipped and lastNonClippedPos[hand].z or shape.pushOutPos.z + normal.z * penetrationDepth * correctionFactor
                        else
                            corrected = useLastNonClipped and Vector(lastNonClippedPos[hand].x, lastNonClippedPos[hand].y, lastNonClippedPos[hand].z) or shape.pushOutPos + normal * penetrationDepth * correctionFactor
                        end

                        if hand == "left" then
                            lefthandPos = corrected
                        else
                            righthandPos = corrected
                        end

                        cachedPushOutPos[hand] = corrected
                        vrmod.utils.DebugPrint("[VRMod] Clipping detected for:", hand, "Push-out pos:", corrected)
                    end
                else
                    lastNonClippedPos[hand] = nil
                    lastNonClippedNormal[hand] = nil
                    cachedPushOutPos[hand] = nil
                    shape.isClipped = false
                    vrmod.utils.DebugPrint("[VRMod] Invalid pushOutPos or player for:", hand)
                end

                if not shape.isClipped then
                    lastNonClippedPos[hand] = Vector(pos.x, pos.y, pos.z)
                    lastNonClippedNormal[hand] = Vector(normal.x, normal.y, normal.z)
                end
            end

            vrmod._lastRelFrame[hand] = {
                pos = relPos,
                ang = relAng
            }
        end
    end
    return lefthandPos, lefthandAng, righthandPos, righthandAng
end

function vrmod.utils.PatchOwnerCollision(ent, ply)
    if not IsValid(ent) then return end
    -- Unpatch if already patched
    if ent._originalShouldCollide then
        ent.ShouldCollide = ent._originalShouldCollide
        ent._originalShouldCollide = nil
        ent._pickupOwner = nil
        ent:SetCustomCollisionCheck(false)
        hook.Remove("ShouldCollide", ent)
        return
    end

    -- Store original ShouldCollide
    ent._originalShouldCollide = ent.ShouldCollide
    ent._pickupOwner = ply
    -- Enable custom collision checking
    ent:SetCustomCollisionCheck(true)
    -- Override ShouldCollide for normal engine collisions
    function ent:ShouldCollide(other)
        if other == self._pickupOwner then return false end
        if self._originalShouldCollide then return self._originalShouldCollide(self, other) end
        return true
    end

    -- Hook global ShouldCollide for physics engine
    hook.Add("ShouldCollide", ent, function(a, b)
        if not IsValid(ent._pickupOwner) then return end
        -- Skip owner only
        if a == ent and b == ent._pickupOwner or b == ent and a == ent._pickupOwner then return false end
    end)
end

-- NPC2RAG
function vrmod.utils.SetBoneMass(ent, mass, damp, vel, angvel, resetmotion, delay)
    if not IsValid(ent) or not IsValid(ent:GetPhysicsObject()) then return end
    if not delay then delay = 0 end
    timer.Simple(delay, function()
        for i = 0, ent:GetPhysicsObjectCount() - 1 do
            local phys = ent:GetPhysicsObjectNum(i)
            if not IsValid(phys) then continue end
            if resetmotion then
                phys:EnableMotion(false)
            else
                phys:EnableMotion(true)
            end

            phys:SetMass(mass)
            phys:SetDamping(damp, damp)
            if vel then phys:SetVelocity(vel) end
            if angvel then phys:AddAngleVelocity(VectorRand() * angvel) end
            phys:EnableGravity(true)
            phys:Wake()
        end
    end)
end

function vrmod.utils.ForwardRagdollDamage(ent, dmginfo)
    if not (ent:IsRagdoll() and trackedRagdolls[ent]) then return end
    if ent.noDamage then return end
    local now = CurTime()
    local last = lastDamageTime[ent] or 0
    if now - last < 1 then return end
    lastDamageTime[ent] = now
    local npc = trackedRagdolls[ent]
    if not IsValid(npc) then
        trackedRagdolls[ent] = nil
        return
    end

    local dmg = dmginfo:GetDamage()
    npc:SetHealth(math.max(0, npc:Health() - dmg))
    --Apply force to ragdoll
    local force = dmginfo:GetDamageForce() or Vector()
    if not force:IsZero() then
        for i = 0, ent:GetPhysicsObjectCount() - 1 do
            local phys = ent:GetPhysicsObjectNum(i)
            if IsValid(phys) then phys:ApplyForceCenter(force) end
        end
    end
end

function vrmod.utils.SpawnPickupRagdoll(ply, npc)
    if not IsValid(npc) then return end
    local rag = ents.Create("prop_ragdoll")
    if not IsValid(rag) then return end
    rag:SetModel(npc:GetModel())
    rag:SetPos(npc:GetPos())
    rag:SetAngles(npc:GetAngles())
    rag:SetNWBool("is_npc_ragdoll", true)
    rag:Spawn()
    rag:Activate()
    if IsValid(ply) then
        rag:SetOwner(ply)
        cleanup.Add(ply, "props", rag)
        undo.Create("VRMod NPC Ragdoll")
        undo.AddEntity(rag)
        undo.SetPlayer(ply)
        undo.Finish()
    end

    -- Register tracking + AI disable
    trackedRagdolls[rag] = npc
    rag.original_npc = npc
    rag.dropped_manually = false
    npc:SetNoDraw(true)
    npc:SetNotSolid(true)
    npc:SetMoveType(MOVETYPE_NONE)
    npc:SetCollisionGroup(COLLISION_GROUP_VEHICLE)
    npc:ClearSchedule()
    if npc.StopMoving then npc:StopMoving() end
    npc:AddEFlags(EFL_NO_THINK_FUNCTION)
    if npc.SetNPCState then npc:SetNPCState(NPC_STATE_NONE) end
    npc:SetSaveValue("m_bInSchedule", false)
    if npc.GetActiveWeapon and IsValid(npc:GetActiveWeapon()) then npc:GetActiveWeapon():Remove() end
    rag:AddCallback("PhysicsCollide", function(self, data)
        if rag.picked then return end
        local impactVel = data.OurOldVelocity.z
        local speed = math.abs(impactVel)
        local threshold = 250
        if speed > threshold then
            local damage = speed - threshold
            local dmginfo = DamageInfo()
            dmginfo:SetDamage(math.abs(damage))
            dmginfo:SetDamageType(DMG_FALL)
            dmginfo:SetAttacker(game.GetWorld())
            dmginfo:SetInflictor(game.GetWorld())
            dmginfo:SetDamageForce(Vector(0, 0, -speed * 100))
            vrmod.utils.SetBoneMass(rag, 50, 25, nil, nil, true)
            vrmod.utils.SetBoneMass(rag, 50, 0.5, nil, nil, false, 0.01)
            rag.noDamage = false
            vrmod.utils.ForwardRagdollDamage(rag, dmginfo)
        end
    end)

    -- Handle cleanup & respawn logic
    rag:CallOnRemove("vrmod_cleanup_npc_" .. rag:EntIndex(), function()
        trackedRagdolls[rag] = nil
        if not IsValid(npc) then return end
        npc:RemoveEFlags(EFL_NO_THINK_FUNCTION)
        if rag.dropped_manually then
            npc:SetPos(rag:GetPos())
            npc:SetAngles(rag:GetAngles())
            npc:SetNoDraw(false)
            npc:SetNotSolid(false)
            npc:SetMoveType(MOVETYPE_STEP)
            npc:SetCollisionGroup(COLLISION_GROUP_NONE)
            npc:ClearSchedule()
            npc:SetSaveValue("m_bInSchedule", false)
            if npc.SetNPCState then npc:SetNPCState(NPC_STATE_ALERT) end
            npc:DropToFloor()
            if npc.BehaveStart then pcall(npc.BehaveStart, npc) end
            npc:SetSchedule(SCHED_IDLE_STAND)
            npc:NextThink(CurTime())
        else
            npc:Remove()
        end
    end)

    -- Monitor for gibbing in a Think hook
    hook.Add("Think", "VRMod_MonitorRagdollGibbing_" .. rag:EntIndex(), function()
        if not IsValid(rag) then
            hook.Remove("Think", "VRMod_MonitorRagdollGibbing_" .. rag:EntIndex())
            return
        end

        if vrmod.utils.IsRagdollGibbed(rag) then
            print("Ragdoll gibbed during runtime, removing")
            rag:Remove()
            hook.Remove("Think", "VRMod_MonitorRagdollGibbing_" .. rag:EntIndex())
        end
    end)
    return rag
end

function vrmod.utils.IsRagdollGibbed(ent)
    -- 1) Missing or invalid entity → treat as gibbed
    if not IsValid(ent) then return true end
    -- 2) Look for Zippy’s health table, only if it exists
    local hpTable = ent.ZippyGoreMod3_PhysBoneHPs
    if type(hpTable) == "table" then
        for boneIndex, hp in pairs(hpTable) do
            if hp == -1 then return true end
        end
    end

    -- 3) Look for Zippy’s gib‑flag table, only if it exists
    local gibTable = ent.ZippyGoreMod3_GibbedPhysBones
    if type(gibTable) == "table" then
        for boneIndex, wasGibbed in pairs(gibTable) do
            if wasGibbed then return true end
        end
    end

    -- 4) If neither table is there, Zippy is disabled or not applied—assume “not gibbed”
    if hpTable == nil and gibTable == nil then return false end
    -- 5) Physics‐object count heuristic (only if we have a hpTable)
    if type(hpTable) == "table" then
        local expectedBones = table.Count(hpTable)
        if ent:GetPhysicsObjectCount() < expectedBones then return true end
    end
    -- No evidence of gibbing
    return false
end

function vrmod.utils.IsRagdollDead(ent)
    if not IsValid(ent) then return true end
    local npc = ent.original_npc
    if IsValid(npc) and npc:Health() <= 0 then return true end
    return vrmod.utils.IsRagdollGibbed(ent)
end

--Vehicles/Glide
function vrmod.utils.GetVehicleBonePosition(vehicle, boneId)
    if not IsValid(vehicle) or not boneId then return nil, nil end
    if vehicle.IsGlideVehicle then return vehicle:GetBonePosition(boneId) end
    if cachedFrame == FrameNumber() then return cachedBonePos, cachedBoneAng end
    local m = vehicle:GetBoneMatrix(boneId)
    if not m then return nil, nil end
    cachedBonePos, cachedBoneAng = m:GetTranslation(), m:GetAngles()
    cachedFrame = FrameNumber()
    return cachedBonePos, cachedBoneAng
end

function vrmod.utils.GetSteeringInfo(ply)
    if not IsValid(ply) or not ply:InVehicle() then return nil, nil, nil end
    local vehicle = ply:GetVehicle() or ply:GetNWEntity("GlideVehicle")
    if not IsValid(vehicle) then return nil, nil, nil end
    local glideVeh = ply:GetNWEntity("GlideVehicle")
    local seatIndex = ply.GlideGetSeatIndex and ply:GlideGetSeatIndex() or 1
    local sitSeq = glideVeh and glideVeh.GetPlayerSitSequence and glideVeh:GetPlayerSitSequence(seatIndex)
    local bonePriority = {
        {
            names = {"handlebars", "handles", "Airboat.Steer", "handle"},
            type = "motorcycle"
        },
        {
            names = {"steering_wheel", "steering", "Rig_Buggy.Steer_Wheel", "car.steer_wheel", "steer"},
            type = "car"
        }
    }

    -- Find steering bone (always attempt, needed for pose alignment)
    local boneId, boneType
    local candidates = {}
    if IsValid(glideVeh) then table.insert(candidates, glideVeh) end
    table.insert(candidates, vehicle)
    for _, candidate in ipairs(candidates) do
        for _, entry in ipairs(bonePriority) do
            for _, name in ipairs(entry.names) do
                local id = candidate:LookupBone(name)
                if id then
                    boneId, boneType = id, entry.type
                    break
                end
            end

            if not boneId then
                local id = GetApproximateBoneId(candidate, entry.names)
                if id then boneId, boneType = id, entry.type end
            end

            if boneId then break end
        end

        if boneId then break end
    end

    -- Glide type takes precedence over boneType
    if IsValid(glideVeh) then
        local vType = glideVeh.VehicleType
        if vType == Glide.VEHICLE_TYPE.MOTORCYCLE or sitSeq == "drive_airboat" then
            return glideVeh, boneId, "motorcycle"
        elseif vType == Glide.VEHICLE_TYPE.BOAT then
            return glideVeh, boneId, "boat"
        elseif vType == Glide.VEHICLE_TYPE.CAR then
            return glideVeh, boneId, "car"
        elseif vType == Glide.VEHICLE_TYPE.PLANE or vType == Glide.VEHICLE_TYPE.HELICOPTER then
            return glideVeh, boneId, "aircraft"
        elseif vType == Glide.VEHICLE_TYPE.TANK then
            return glideVeh, boneId, "tank"
        end
    end

    -- If no Glide type, fall back to bone-derived type (if any)
    if boneId then return vehicle, boneId, boneType end
    -- Otherwise, nothing known
    return vehicle, nil, "unknown"
end

function vrmod.utils.GetGlideBoneAng(ply, boneName)
    if not IsValid(ply) then return Angle(0, 0, 0) end
    local vehicle = ply:GetNWEntity("GlideVehicle")
    if not IsValid(vehicle) or type(vehicle.GetSeatBoneManipulations) ~= "function" then return Angle(0, 0, 0) end
    local seatPose = vehicle:GetSeatBoneManipulations(ply:GlideGetSeatIndex())
    if not seatPose or type(seatPose) ~= "table" then return Angle(0, 0, 0) end
    local ang = seatPose[boneName]
    if not ang then return Angle(0, 0, 0) end
    return ang
end

function vrmod.utils.GetGlideHandOffset(ply, side)
    local vehicle = ply:GetNWEntity("GlideVehicle")
    -- Define vehicle-specific offsets
    local wheelOffset = Vector(0, 0, 0)
    local wheelDistance = 0
    local angleOffset = Angle(0, 0, 0)
    if not IsValid(vehicle) then return wheelOffset, wheelDistance, angleOffset end
    if vehicle.VehicleType == Glide.VEHICLE_TYPE.MOTORCYCLE or vehicle:GetPlayerSitSequence(1) == "drive_airboat" then
        wheelOffset = Vector(20, 0, -5)
        wheelDistance = 12
        angleOffset = side == "left" and Angle(0, 0, 90) or Angle(0, 0, -90)
    elseif vehicle.VehicleType == Glide.VEHICLE_TYPE.PLANE or vehicle.VehicleType == Glide.VEHICLE_TYPE.HELICOPTER then
        wheelOffset = Vector(15, 0, -10)
        wheelDistance = 3
        angleOffset = Angle(0, 0, 0)
    elseif vehicle.VehicleType == Glide.VEHICLE_TYPE.TANK then
        wheelOffset = Vector(10, 0, -3)
        wheelDistance = 8
        angleOffset = Angle(0, 0, 0)
    else
        wheelOffset = Vector(20, 0, -3)
        wheelDistance = 8
        angleOffset = Angle(0, 0, 0)
    end
    return wheelOffset, wheelDistance, angleOffset
end

function vrmod.utils.PatchGlideCamera()
    local Camera = Glide.Camera
    if not Camera then return end
    local Config = Glide.Config
    if not Config then print("[VRMod] Warning: Glide.Config not found, using fallback values") end
    -- Store original functions
    if not Camera._OrigCalcView then Camera._OrigCalcView = Camera.CalcView end
    if not Camera._OrigCreateMove then Camera._OrigCreateMove = Camera.CreateMove end
    -- Override CalcView
    function Camera:CalcView()
        local vehicle = self.vehicle
        if not IsValid(vehicle) then return end
        local user = self.user
        if vrmod and vrmod.IsPlayerInVR and vrmod.IsPlayerInVR(user) then
            -- VR mode: Use g_VR.view for camera position and orientation
            local hmdPos, hmdAng = g_VR.view.origin, g_VR.view.angles
            if self.isInFirstPerson then
                -- First-person: Align camera with HMD pose relative to vehicle
                local localEyePos = vehicle:WorldToLocal(hmdPos)
                local localPos = vehicle:GetFirstPersonOffset(self.seatIndex, localEyePos)
                self.origin = vehicle:LocalToWorld(localPos)
                self.angles = hmdAng
            else
                -- Third-person: Position camera behind vehicle, adjusted by HMD orientation
                local fraction = self.traceFraction
                -- Fallback values if Config is nil
                local cameraDistance = Config and Config.cameraDistance or 100
                local cameraHeight = Config and Config.cameraHeight or 50
                local offset = self.shakeOffset + vehicle.CameraOffset * Vector(cameraDistance, 1, cameraHeight) * fraction
                local startPos = vehicle:LocalToWorld(vehicle.CameraCenterOffset + vehicle.CameraTrailerOffset * self.trailerFraction)
                -- Use HMD angles instead of mouse-based angles
                self.angles = hmdAng + vehicle.CameraAngleOffset
                local endPos = startPos + self.angles:Forward() * offset[1] * (1 + self.trailerFraction * vehicle.CameraTrailerDistanceMultiplier) + self.angles:Right() * offset[2] + self.angles:Up() * offset[3]
                local dir = endPos - startPos
                dir:Normalize()
                -- Check for wall collisions
                local tr = util.TraceLine({
                    start = startPos,
                    endpos = endPos + dir * 10,
                    mask = 16395 -- MASK_SOLID_BRUSHONLY
                })

                if tr.Hit then
                    endPos = tr.HitPos - dir * 10
                    if tr.Fraction < fraction then self.traceFraction = tr.Fraction end
                end

                self.origin = endPos
            end

            -- Update aim position and entity using HMD angles
            local tr = util.TraceLine({
                start = user:GetShootPos(), -- Start from weapon shoot position
                endpos = user:GetShootPos() + hmdAng:Forward() * 50000,
                filter = {user, vehicle}
            })

            self.lastAimEntity = tr.Entity
            self.lastAimPos = tr.HitPos
            self.viewAngles = hmdAng
            -- Sync player's EyeAngles with HMD for weapon aiming
            user:SetEyeAngles(hmdAng)
            return {
                origin = self.origin,
                angles = self.angles + self.punchAngle,
                fov = self.fov,
                drawviewer = not self.isInFirstPerson
            }
        else
            -- Non-VR mode: Call original CalcView
            return self:_OrigCalcView()
        end
    end

    -- Override CreateMove
    function Camera:CreateMove(cmd)
        if vrmod and vrmod.IsPlayerInVR and vrmod.IsPlayerInVR(self.user) then
            -- VR mode: Set command angles to HMD angles for weapon firing
            cmd:SetViewAngles(g_VR.view.angles)
            return
        end

        -- Non-VR mode: Call original CreateMove
        self:_OrigCreateMove(cmd)
    end

    print("[VRMod] Patched Glide.Camera for VR support")
end

--DEBUG
function vrmod.utils.DebugPrint(fmt, ...)
    if not cv_debug:GetBool() then return end
    local prefix = string.format("[VRMod:][%s]", CLIENT and "Client" or "Server")
    if select("#", ...) > 0 then
        if type(fmt) == "string" and fmt:find("%%") then
            -- format mode
            local args = {...}
            for i = 1, #args do
                args[i] = tostr(args[i])
            end

            print(prefix, string.format(fmt, unpack(args)))
        else
            -- print mode
            local args = {fmt, ...}
            for i = 1, #args do
                args[i] = tostr(args[i])
            end

            print(prefix, unpack(args))
        end
    else
        -- single argument only
        print(prefix, tostr(fmt))
    end
end

if SERVER then
    CreateConVar("vrmod_collisions", "1", FCVAR_ARCHIVE + FCVAR_NOTIFY + FCVAR_REPLICATED, "Enable VR hand collision correction")
    util.AddNetworkString("vrmod_sync_model_params")
    net.Receive("vrmod_sync_model_params", function(len, ply)
        local modelPath = net.ReadString()
        local params = {
            radius = net.ReadFloat(),
            reach = net.ReadFloat(),
            mins_horizontal = net.ReadVector(),
            maxs_horizontal = net.ReadVector(),
            mins_vertical = net.ReadVector(),
            maxs_vertical = net.ReadVector(),
            angles = net.ReadAngle(),
            computed = true,
            sent = true
        }

        -- Only update + rebroadcast if different or unseen
        local old = modelCache[modelPath]
        if not old or old.radius ~= params.radius or old.reach ~= params.reach or old.mins_horizontal ~= params.mins_horizontal or old.maxs_horizontal ~= params.maxs_horizontal or old.mins_vertical ~= params.mins_vertical or old.maxs_vertical ~= params.maxs_vertical or old.angles ~= params.angles then
            vrmod.utils.DebugPrint("Server received NEW collision params for %s from %s", modelPath, ply:Nick())
            modelCache[modelPath] = params
            net.Start("vrmod_sync_model_params")
            net.WriteString(modelPath)
            net.WriteFloat(params.radius)
            net.WriteFloat(params.reach)
            net.WriteVector(params.mins_horizontal)
            net.WriteVector(params.maxs_horizontal)
            net.WriteVector(params.mins_vertical)
            net.WriteVector(params.maxs_vertical)
            net.WriteAngle(params.angles)
            net.Broadcast()
            vrmod.utils.DebugPrint("Broadcasted collision params for %s to all clients", modelPath)
        else
            vrmod.utils.DebugPrint("Ignored duplicate collision params for %s from %s", modelPath, ply:Nick())
        end
    end)

    hook.Add("PlayerInitialSpawn", "VRMod_SendModelCache", function(ply)
        for modelPath, params in pairs(modelCache) do
            if params.computed then
                net.Start("vrmod_sync_model_params")
                net.WriteString(modelPath)
                net.WriteFloat(params.radius)
                net.WriteFloat(params.reach)
                net.WriteVector(params.mins_horizontal)
                net.WriteVector(params.maxs_horizontal)
                net.WriteVector(params.mins_vertical)
                net.WriteVector(params.maxs_vertical)
                net.WriteAngle(params.angles)
                net.Send(ply)
                vrmod.utils.DebugPrint("Synced cached collision params for %s to %s", modelPath, ply:Nick())
            end
        end
    end)

    cvars.AddChangeCallback("vrmod_collisions", function(cvar, old, new)
        for _, ply in ipairs(player.GetAll()) do
            ply:SetNWBool("vrmod_server_enforce_collision", tobool(new))
        end
    end)

    hook.Add("VRMod_Start", "SendCollisionState", function(ply) ply:SetNWBool("vrmod_server_enforce_collision", GetConVar("vrmod_collisions"):GetBool()) end)
    if not (hook.GetTable()["EntityTakeDamage"] or {})["VRMod_ForwardRagdollDamage"] then hook.Add("EntityTakeDamage", "VRMod_ForwardRagdollDamage", function(ent, dmginfo) vrmod.utils.ForwardRagdollDamage(ent, dmginfo) end) end
    timer.Create("VRMod_Cleanup_DeadRagdolls", 60, 0, function()
        for rag, npc in pairs(trackedRagdolls) do
            if not IsValid(rag) or not IsValid(npc) then trackedRagdolls[rag] = nil end
        end
    end)
end

if CLIENT then
    net.Receive("vrmod_sync_model_params", function()
        local modelPath = net.ReadString()
        local params = {
            radius = net.ReadFloat(),
            reach = net.ReadFloat(),
            mins_horizontal = net.ReadVector(),
            maxs_horizontal = net.ReadVector(),
            mins_vertical = net.ReadVector(),
            maxs_vertical = net.ReadVector(),
            angles = net.ReadAngle(),
            computed = true
        }

        vrmod.utils.DebugPrint("Received synced collision params for %s from server", modelPath)
        modelCache[modelPath] = params
    end)

    hook.Add("PostDrawOpaqueRenderables", "VRMod_HandDebugShapes", function()
        if not cl_debug_collisions:GetBool() or not g_VR.active then return end
        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:Alive() or not vrmod.IsPlayerInVR(ply) then return end
        render.SetColorMaterial()
        for i = 1, #collisionSpheres do
            local s = collisionSpheres[i]
            render.DrawWireframeSphere(s.pos, s.radius, 16, 16, s.hit and Color(255, 255, 0, 100) or Color(255, 0, 0, 150))
        end

        for i = 1, #collisionBoxes do
            local b = collisionBoxes[i]
            render.DrawWireframeBox(b.pos, b.angles, b.mins, b.maxs, b.hit and Color(255, 255, 0, 100) or Color(0, 255, 0, 150))
        end
    end)
end