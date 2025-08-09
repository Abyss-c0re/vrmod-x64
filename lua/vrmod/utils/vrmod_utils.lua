g_VR = g_VR or {}
g_VR.enhanced = true
vrmod = vrmod or {}
vrmod.data = vrmod.data or {}
vrmod.utils = vrmod.utils or {}
local magCache = {}
local modelCache = {}
local pending = {}
local lastPlayerPos = Vector(0, 0, 0)
local collisionNearbyCache = nil
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
--GLOBALS
vrmod.SMOOTHING_FACTOR = 0.98
vrmod.DEFAULT_RADIUS = 3.5
vrmod.DEFAULT_REACH = 5.5
vrmod.DEFAULT_MINS = Vector(-0.75, -0.75, -1.25)
vrmod.DEFAULT_MAXS = Vector(0.75, 0.75, 11)
vrmod.DEFAULT_ANGLES = Angle(0, 0, 0)
vrmod.DEFAULT_OFFSET = 4
vrmod.MODEL_OVERRIDES = {
    weapon_physgun = "models/weapons/w_physics.mdl",
    weapon_physcannon = "models/weapons/w_physics.mdl",
}

local cl_effectmodel = CreateClientConVar("vrmod_melee_fist_collisionmodel", "models/props_junk/PopCan01a.mdl", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local cv_debug = CreateConVar("vrmod_debug", "0", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Enable detailed melee debug logging (0 = off, 1 = on)")
local cl_debug_collisions = CreateClientConVar("vrmod_debug_collisions", "0", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
-- HELPERS
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
    -- Scale the extents to make the collision box larger (1.2x for better coverage)
    local scaleFactor = 1.0
    extents = extents * scaleFactor
    -- Adjust box based on orientation
    if isVertical then
        -- Vertical alignment: prioritize z-axis, swap x and z extents
        mins = Vector(-extents.z * 0.5, -extents.y * 0.5, -extents.x * 1.2)
        maxs = Vector(extents.z * 0.5, extents.y * 0.5, extents.x * 1.2)
        vrmod.utils.DebugPrint("GetWeaponCollisionBox: Vertical-aligned (z-axis) | Mins: %s, Maxs: %s", tostring(mins), tostring(maxs))
    else
        -- Forward alignment: prioritize x-axis
        mins = Vector(-extents.x * 1.2, -extents.y * 0.5, -extents.z * 0.5)
        maxs = Vector(extents.x * 1.2, extents.y * 0.5, extents.z * 0.5)
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
    if not reach then
        local reducedMins = Vector(mins.x, mins.y, mins.z)
        local reducedMaxs = Vector(maxs.x, maxs.y, maxs.z)
        local tr = util.TraceHull({
            start = pos,
            endpos = pos,
            angles = ang,
            mins = reducedMins,
            maxs = reducedMaxs,
            mask = MASK_SOLID_BRUSHONLY
        })
        return tr.Hit and tr.HitWorld, tr.HitNormal or Vector(0, 0, 1)
    end

    local newMins = Vector(mins.x, mins.y * 0.5, mins.z * reach * 1.5)
    local newMaxs = Vector(maxs.x, maxs.y * 0.5, maxs.z * reach * 1.5)
    -- With reach: sweep the hull forward
    local sweepEnd = pos + ang:Forward() * reach * 1.5
    local tr = util.TraceHull({
        start = pos,
        endpos = sweepEnd,
        angles = ang,
        mins = newMins,
        maxs = newMaxs,
        mask = MASK_SOLID_BRUSHONLY
    })
    return tr.Hit and tr.HitWorld, tr.HitNormal or Vector(0, 0, 1)
end

--DEBUG
function vrmod.utils.DebugPrint(fmt, ...)
    if cv_debug:GetBool() then print(string.format("[VRMod:][%s] " .. fmt, CLIENT and "Client" or "Server", ...)) end
end

--MATH
function vrmod.utils.vecAlmostEqual(v1, v2, threshold)
    if not v1 or not v2 then return false end
    return v1:DistToSqr(v2) < (threshold or 0.001) ^ 2
end

function vrmod.utils.angAlmostEqual(a1, a2, threshold)
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

function vrmod.utils.SmoothAngle(current, target, smoothingFactor)
    local diff = target - current
    diff.p = math.NormalizeAngle(diff.p)
    diff.y = math.NormalizeAngle(diff.y)
    diff.r = math.NormalizeAngle(diff.r)
    return current + diff * smoothingFactor
end

-- SYSTEM
function vrmod.utils.calculateProjectionParams(projMatrix, worldScale)
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

function vrmod.utils.computeSubmitBounds(leftCalc, rightCalc, hOffset, vOffset, scaleFactor, renderOffset)
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

function vrmod.utils.adjustFOV(proj, fovScaleX, fovScaleY)
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

function vrmod.utils.WepInfo(wep)
    local class, vm = vrmod.utils.IsValidWep(wep, true)
    if class and vm then return class, vm end
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
        local ang2 = Angle(ang.p, ang.y, ang.r + 180)
        dir = ang2:Forward()
    else
        startPos = vrmod.GetRightHandPos(ply)
        ang = vrmod.GetRightHandAng(ply)
        dir = ang:Forward()
    end

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
            computed = true
        }
        return
    end

    local originalModelPath = modelPath
    -- Fallback for known bad viewmodels (c_models)
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
                    computed = true
                }
                return
            end
        end
    end

    -- Already computed?
    if modelCache[originalModelPath] and modelCache[originalModelPath].computed then return end
    -- Retry protection (reduced max attempts to 2)
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
            computed = true
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
        local mins_horizontal, maxs_horizontal, _, amin, amax = GetWeaponCollisionBox(phys, false)
        local mins_vertical, maxs_vertical = GetWeaponCollisionBox(phys, true)
        if amin:Length() > 0 and amax:Length() > 0 then
            local reach = math.max(math.abs(amax.x - amin.x), math.abs(amax.y - amin.y), math.abs(amax.z - amin.z)) * 0.5
            reach = math.Clamp(reach * 1.5, 6.6, 50)
            modelCache[originalModelPath] = {
                radius = reach,
                reach = reach,
                mins_horizontal = mins_horizontal or vrmod.DEFAULT_MINS,
                maxs_horizontal = maxs_horizontal or vrmod.DEFAULT_MAXS,
                mins_vertical = mins_vertical or vrmod.DEFAULT_MINS,
                maxs_vertical = maxs_vertical or vrmod.DEFAULT_MAXS,
                angles = vrmod.DEFAULT_ANGLES,
                computed = true
            }

            vrmod.utils.DebugPrint("Computed collision boxes for %s (actual: %s) → reach: %.2f units", originalModelPath, modelPath, reach)
        else
            vrmod.utils.DebugPrint("Invalid AABB for %s, attempt %d", modelPath, pending[originalModelPath].attempts)
        end
    else
        vrmod.utils.DebugPrint("No valid physobj for %s, attempt %d", modelPath, pending[originalModelPath].attempts)
    end

    -- Immediate cleanup
    ent:Remove()
    pending[originalModelPath].lastAttempt = CurTime()
    if pending[originalModelPath].attempts >= 2 then pending[originalModelPath] = nil end
end

function vrmod.utils.GetModelParams(modelPath, ply, offsetAng)
    local ang = vrmod.GetRightHandAng(ply)
    local isVertical = offsetAng and (math.abs(math.NormalizeAngle(offsetAng.x)) > 45 or math.abs(math.NormalizeAngle(offsetAng.y)) > 45 or math.abs(math.NormalizeAngle(offsetAng.z)) > 45) or false
    vrmod.utils.DebugPrint("GetModelParams: offsetAng=%s, isVertical=%s (pitch=%.2f, yaw=%.2f, roll=%.2f)", tostring(offsetAng), tostring(isVertical), offsetAng and math.abs(math.NormalizeAngle(offsetAng.x)) or 0, offsetAng and math.abs(math.NormalizeAngle(offsetAng.y)) or 0, offsetAng and math.abs(math.NormalizeAngle(offsetAng.z)) or 0)
    if modelCache[modelPath] and modelCache[modelPath].computed then
        local cache = modelCache[modelPath]
        vrmod.utils.DebugPrint("GetModelParams: Cache found for %s", modelPath)
        local mins = isVertical and cache.mins_vertical or cache.mins_horizontal
        local maxs = isVertical and cache.maxs_vertical or cache.maxs_horizontal
        return cache.radius, cache.reach, mins, maxs, ang
    end

    -- Avoid scheduling if computation is pending and recent
    if pending[modelPath] and CurTime() - (pending[modelPath].lastAttempt or 0) < 1 then
        vrmod.utils.DebugPrint("GetModelParams: Computation already pending for %s", modelPath)
        return vrmod.DEFAULT_RADIUS, vrmod.DEFAULT_REACH, vrmod.DEFAULT_MINS, vrmod.DEFAULT_MAXS, ang
    end

    vrmod.utils.DebugPrint("GetModelParams: No cache for %s, scheduling computation", modelPath)
    pending[modelPath] = pending[modelPath] or {
        attempts = 0
    }

    timer.Simple(0, function() vrmod.utils.ComputePhysicsParams(modelPath) end)
    return vrmod.DEFAULT_RADIUS, vrmod.DEFAULT_REACH, vrmod.DEFAULT_MINS, vrmod.DEFAULT_MAXS, ang
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
    if not vrmod.utils.IsValidWep(wep) or side == "left" then return nil end
    local radius, reach, mins, maxs, angles = vrmod.utils.GetWeaponMeleeParams(wep, ply, side)
    -- Check if computation is pending and hasn't timed out
    local model = vrmod.utils.WepInfo(wep)
    if pending[model] and CurTime() - (pending[model].lastAttempt or 0) < 2 then
        vrmod.utils.DebugPrint("GetCachedWeaponParams: Computation pending for %s, waiting", model)
        return nil -- Return nil to indicate params aren't ready yet
    end

    -- Only return params if they're not defaults or if computation is complete
    if radius ~= vrmod.DEFAULT_RADIUS or reach ~= vrmod.DEFAULT_REACH or mins ~= vrmod.DEFAULT_MINS then return radius, reach, mins, maxs, angles end
    -- Schedule computation if not already pending
    if not pending[model] then
        vrmod.utils.DebugPrint("GetCachedWeaponParams: Scheduling computation for %s", model)
        timer.Simple(0, function() vrmod.utils.ComputePhysicsParams(model) end)
    end
    return nil -- Indicate params aren't ready
end

function vrmod.utils.checkWorldCollisions(pos, radius, mins, maxs, ang, hand, reach)
    local shapeMins = mins or Vector(-radius, -radius, -radius)
    local shapeMaxs = maxs or Vector(radius, radius, radius)
    ang = ang or Angle(0, 0, 0) -- Fallback to zero angle
    ang:Normalize()
    local isClipped, hitNormal
    if mins and maxs then
        -- Clipping check: full box, no reach
        isClipped, hitNormal = BoxCollidesWithWorld(pos, ang, shapeMins, shapeMaxs)
        vrmod.utils.DebugPrint("[VRMod] Box collision for:", hand, "Pos:", pos, "Angles:", ang, "Mins:", shapeMins, "Maxs:", shapeMaxs, "Hit:", isClipped)
    else
        if not radius then radius = vrmod.DEFAULT_RADIUS end
        isClipped, hitNormal = SphereCollidesWithWorld(pos, radius)
        vrmod.utils.DebugPrint("[VRMod] Sphere collision for:", hand, "Pos:", pos, "Radius:", radius, "Hit:", isClipped)
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

            pushOutPos = traceOut.Hit and traceOut.HitPos + traceOut.HitNormal * 0.1 or pos + hitNormal * 0.2
        end

        cachedPushOutPos[hand] = pushOutPos
    else
        lastNonClippedPos[hand] = pos
        cachedPushOutPos[hand] = nil
    end

    local reachHit
    if mins and maxs then
        reachHit, _ = BoxCollidesWithWorld(pos, ang, shapeMins, shapeMaxs, reach)
        vrmod.utils.DebugPrint("[VRMod] Box reach check for:", hand, "Pos:", pos, "Reach:", reach, "Hit:", reachHit)
    else
        local tr = util.TraceLine({
            start = pos,
            endpos = pos + ang:Forward() * reach,
            mask = MASK_SOLID_BRUSHONLY
        })

        reachHit = tr.Hit and tr.HitWorld or false
        vrmod.utils.DebugPrint("[VRMod] Sphere reach check for:", hand, "Start:", pos, "End:", pos + ang:Forward() * reach, "Hit:", reachHit, "HitPos:", tr.HitPos)
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

function vrmod.utils.UpdateHandCollisionShapes(frame)
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
        return frame
    end

    local ply = LocalPlayer()
    --local relFrame =  VRUtilNetUpdateLocalPly(true)
    local leftPos = frame.lefthandPos + frame.lefthandAng:Forward() * vrmod.DEFAULT_OFFSET
    local rightPos = frame.righthandPos + frame.righthandAng:Forward() * vrmod.DEFAULT_OFFSET
    local rightAng = frame.righthandAng
    -- Process each hand independently
    collisionSpheres = {}
    collisionBoxes = {}
    vrmod._collisionShapeByHand = {
        left = nil,
        right = nil
    }

    local wep = ply:GetActiveWeapon()
    for _, hand in ipairs({"left", "right"}) do
        local pos = hand == "left" and leftPos or rightPos
        local ang = hand == "left" and frame.lefthandAng or rightAng
        local posKey = hand .. "handPos"
        if not vrmod._lastRelFrame then vrmod._lastRelFrame = {} end
        local relFrame = VRUtilNetUpdateLocalPly(true)
        local relPosKey = hand .. "handPos"
        local relAngKey = hand .. "handAng"
        -- Previous relative frame for this hand
        local prevRel = vrmod._lastRelFrame[hand]
        -- Movement check: only skip if the hand has not moved or rotated
        local moved = true
        if prevRel then moved = not (vrmod.utils.vecAlmostEqual(relFrame[relPosKey], prevRel.pos, 0.1) and vrmod.utils.angAlmostEqual(relFrame[relAngKey], prevRel.ang, 1.0)) end
        local clippedLastFrame = cachedPushOutPos[hand] ~= nil
        local sameNormal = lastNonClippedNormal[hand] and vrmod.utils.vecAlmostEqual(lastNonClippedNormal[hand], frame[posKey], 0.3)
        if not moved and clippedLastFrame and sameNormal then
            frame[posKey] = cachedPushOutPos[hand]
            vrmod.utils.DebugPrint("[VRMod] Using cached push-out for:", hand, "at", cachedPushOutPos[hand])
            -- Cache current relFrame for next tick
            vrmod._lastRelFrame[hand] = {
                pos = relFrame[relPosKey],
                ang = relFrame[relAngKey]
            }

            continue -- skip re-tracing and shape creation
        end

        -- Update cache for next movement check
        vrmod._lastRelFrame[hand] = {
            pos = relFrame[relPosKey],
            ang = relFrame[relAngKey]
        }

        if hand == "left" then
            lastLeftPos:Set(leftPos)
        else
            lastRightPos:Set(rightPos)
            lastRightAng:Set(rightAng)
        end

        local radius, _, mins, maxs = vrmod.utils.GetCachedWeaponParams(wep, ply, hand)
        radius = radius or vrmod.DEFAULT_RADIUS
        mins = mins or vrmod.DEFAULT_MINS
        maxs = maxs or vrmod.DEFAULT_MAXS
        local reach = vrmod.utils.GetWeaponMeleeParams(wep, ply, hand)
        if not isnumber(reach) then reach = math.max(math.abs(maxs.x), math.abs(maxs.y), math.abs(maxs.z)) * 2 end
        local shape
        if vrmod.utils.IsValidWep(wep) and hand == "right" then
            shape = vrmod.utils.checkWorldCollisions(rightPos, nil, mins, maxs, rightAng, "right", reach)
            collisionBoxes[1] = shape
        else
            shape = vrmod.utils.checkWorldCollisions(pos, radius, nil, nil, ang, hand, reach)
            collisionSpheres[#collisionSpheres + 1] = shape
        end

        vrmod._collisionShapeByHand[hand] = shape
        if shape and shape.isClipped then
            g_VR._cachedFrameRelative = nil
            g_VR._cachedFrameAbsolute = nil
            local handPos = frame[posKey]
            local normal = shape.hitNormal
            local corrected = Vector(handPos.x, handPos.y, handPos.z)
            local absX, absY, absZ = math.abs(normal.x), math.abs(normal.y), math.abs(normal.z)
            local useLastNonClipped = lastNonClippedPos[hand] and lastNonClippedNormal[hand] and vrmod.utils.vecAlmostEqual(normal, lastNonClippedNormal[hand], 0.1)
            -- Check distance between pushOutPos and player position
            local plyPos = frame.hmdPos
            if shape.pushOutPos and type(shape.pushOutPos) == "Vector" and IsValid(ply) then
                local distanceSqr = (shape.pushOutPos - plyPos):LengthSqr()
                if distanceSqr > 450 then
                    -- Reset clipping state if too far from player
                    lastNonClippedPos[hand] = nil
                    lastNonClippedNormal[hand] = nil
                    cachedPushOutPos[hand] = nil
                    shape.isClipped = false
                    vrmod.utils.DebugPrint("[VRMod] Reset clipping for:", hand, "DistanceSqr:", distanceSqr, "Distance:", math.sqrt(distanceSqr), "Push-out pos:", shape.pushOutPos, "Player pos:", plyPos)
                else
                    -- Calculate penetration depth along the normal
                    local penetrationVec = handPos - shape.pushOutPos
                    local penetrationDepth = penetrationVec:Dot(normal) -- Project penetration vector onto normal
                    local correctionFactor = 2
                    -- Apply correction based on penetration depth along the dominant axis
                    if absX > absY and absX > absZ and absX > 0.5 then
                        corrected.x = useLastNonClipped and lastNonClippedPos[hand].x or shape.pushOutPos.x + normal.x * penetrationDepth * correctionFactor
                    elseif absY > absX and absY > absZ and absY > 0.5 then
                        corrected.y = useLastNonClipped and lastNonClippedPos[hand].y or shape.pushOutPos.y + normal.y * penetrationDepth * correctionFactor
                    elseif absZ > absX and absZ > absY and absZ > 0.5 then
                        corrected.z = useLastNonClipped and lastNonClippedPos[hand].z or shape.pushOutPos.z + normal.z * penetrationDepth * correctionFactor
                    else
                        -- Fallback for non-axis-aligned normals
                        corrected = useLastNonClipped and Vector(lastNonClippedPos[hand].x, lastNonClippedPos[hand].y, lastNonClippedPos[hand].z) or shape.pushOutPos + normal * penetrationDepth * correctionFactor
                    end

                    frame[posKey] = corrected
                    cachedPushOutPos[hand] = corrected -- Cache the corrected position
                    vrmod.utils.DebugPrint("[VRMod] Clipping detected for:", hand, "Normal:", normal, "Original pos:", handPos, "Push-out pos:", corrected, "Penetration depth:", penetrationDepth, "DistanceSqr:", distanceSqr)
                end
            else
                -- Fallback if pushOutPos is invalid or player is invalid
                lastNonClippedPos[hand] = nil
                lastNonClippedNormal[hand] = nil
                cachedPushOutPos[hand] = nil
                shape.isClipped = false
                vrmod.utils.DebugPrint("[VRMod] Invalid pushOutPos or player for:", hand, "Push-out pos:", shape.pushOutPos, "Player:", ply)
            end

            if not shape.isClipped then
                lastNonClippedPos[hand] = Vector(pos.x, pos.y, pos.z)
                lastNonClippedNormal[hand] = Vector(normal.x, normal.y, normal.z)
            end
        end
    end
    return frame
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

if SERVER then
    CreateConVar("vrmod_collisions", "1", FCVAR_ARCHIVE + FCVAR_NOTIFY + FCVAR_REPLICATED, "Enable VR hand collision correction")
    cvars.AddChangeCallback("vrmod_collisions", function(cvar, old, new)
        for _, ply in ipairs(player.GetAll()) do
            ply:SetNWBool("vrmod_server_enforce_collision", tobool(new))
        end
    end)

    hook.Add("VRMod_Start", "SendCollisionState", function(ply) ply:SetNWBool("vrmod_server_enforce_collision", GetConVar("vrmod_collisions"):GetBool()) end)
    if not hook.GetTable()["EntityTakeDamage"]["VRMod_ForwardRagdollDamage"] then hook.Add("EntityTakeDamage", "VRMod_ForwardRagdollDamage", function(ent, dmginfo) vrmod.utils.ForwardRagdollDamage(ent, dmginfo) end) end
    timer.Create("VRMod_Cleanup_DeadRagdolls", 60, 0, function()
        for rag, npc in pairs(trackedRagdolls) do
            if not IsValid(rag) or not IsValid(npc) then trackedRagdolls[rag] = nil end
        end
    end)
end

if CLIENT then
    hook.Add("VRMod_Tracking", "VRMod_CollisionBroadPhaseCheck", function()
        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:GetNWBool("vrmod_server_enforce_collision", true) or not ply:Alive() or not vrmod.IsPlayerInVR(ply) or ply:InVehicle() then
            vrmod._collisionNearby = false
            collisionNearbyCache = nil
            return
        end

        local plyPos = ply:GetPos()
        if collisionNearbyCache ~= nil and vrmod.utils.vecAlmostEqual(plyPos, lastPlayerPos, 3) then
            vrmod._collisionNearby = collisionNearbyCache
            return
        end

        lastPlayerPos:Set(plyPos)
        local leftPos = vrmod.GetLeftHandPos(ply)
        local rightPos = vrmod.GetRightHandPos(ply)
        local bigRadius = 20
        local leftNearby = SphereCollidesWithWorld(leftPos, bigRadius)
        local rightNearby = SphereCollidesWithWorld(rightPos, bigRadius)
        vrmod._collisionNearby = leftNearby or rightNearby
        collisionNearbyCache = vrmod._collisionNearby
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