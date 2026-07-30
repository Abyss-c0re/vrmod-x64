g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}
local cl_effectmodel = CreateClientConVar("vrmod_melee_fist_collisionmodel", "models/props_junk/PopCan01a.mdl", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
-- Extra clearance beyond hand/weapon hull when stopped against a wall (units)
local cv_hand_push = CreateClientConVar("vrmod_hand_collision_push", "0.75", true, FCVAR_ARCHIVE, "Wall collision push-out padding for VR hands/weapons (units)", 0, 8)
--GLOBALS
vrmod.SMOOTHING_FACTOR = 0.98
vrmod.DEFAULT_RADIUS = 2.2
vrmod.DEFAULT_REACH = 5.0
vrmod.DEFAULT_MINS = Vector(-0.75, -0.75, -1.25)
vrmod.DEFAULT_MAXS = Vector(0.75, 0.75, 11)
vrmod.DEFAULT_ANGLES = Angle(0, 0, 0)
vrmod.DEFAULT_OFFSET = 5
vrmod.MODEL_OVERRIDES = {
    weapon_physgun = "models/weapons/w_physics.mdl",
    weapon_physcannon = "models/weapons/w_physics.mdl",
}

vrmod.modelCache = {}
vrmod.collisionSpheres = {}
vrmod.collisionBoxes = {}
local pending = {}
local lastPreCheckLeft = Vector(0, 0, 0)
local lastPreCheckRight = Vector(0, 0, 0)
local lastPreCheckResult = false
local PRECHECK_MOVE_THRESHOLD = 0.8 -- units (tune 0.5–2.0)
local lastCheckedHandPos = {
    left = Vector(),
    right = Vector()
}

local POS_TOLERANCE = 0.05
local ANG_TOLERANCE = 1.0
local lastCheckedHandAng = {
    left = Angle(),
    right = Angle()
}

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

-- Cached debug convar (avoid GetConVar every collision call)
local cv_debug_physics
local function DebugEnabled()
    if cv_debug_physics == nil then
        cv_debug_physics = GetConVar("vrmod_debug_physics")
    end
    return cv_debug_physics and cv_debug_physics:GetBool() or false
end

-- Reused hull extents for broadphase / sphere probes (cut per-call Vector allocs)
local tmpHullPos = Vector()
local tmpHullNeg = Vector()
local ZERO_UP = Vector(0, 0, 1)

local function SetSymmetricHull(radius)
    tmpHullPos.x, tmpHullPos.y, tmpHullPos.z = radius, radius, radius
    tmpHullNeg.x, tmpHullNeg.y, tmpHullNeg.z = -radius, -radius, -radius
    return tmpHullNeg, tmpHullPos
end

--- Cheap brush overlap only (no penetration resolve). Used for broadphase.
local function WorldBrushOverlaps(pos, radius)
    local mins, maxs = SetSymmetricHull(radius)
    local tr = util.TraceHull({
        start = pos,
        endpos = pos,
        mins = mins,
        maxs = maxs,
        mask = MASK_SOLID_BRUSHONLY
    })
    return tr.Hit and tr.HitWorld
end

--- Reach sweep hit test only (no push-out iterations).
local function BoxSweepHitsWorld(pos, ang, mins, maxs, reach)
    local tr = util.TraceHull({
        start = pos,
        endpos = pos + ang:Forward() * reach,
        angles = ang,
        mins = mins,
        maxs = maxs,
        mask = MASK_SOLID_BRUSHONLY
    })
    return tr.Hit and tr.HitWorld
end

local MIN_BOX_SIZE = vrmod.DEFAULT_RADIUS * 0.5

local function EnforceMinBoxSize(mins, maxs)
    mins.x = math.min(mins.x, -MIN_BOX_SIZE)
    mins.y = math.min(mins.y, -MIN_BOX_SIZE)
    mins.z = math.min(mins.z, -MIN_BOX_SIZE)
    maxs.x = math.max(maxs.x, MIN_BOX_SIZE)
    maxs.y = math.max(maxs.y, MIN_BOX_SIZE)
    maxs.z = math.max(maxs.z, MIN_BOX_SIZE)
    return mins, maxs
end

--- Build both hand-space collision boxes from a single AABB (half-extents).
--- Horizontal = forward-aligned weapon; vertical = upright melee.
local function BoxesFromAABB(amin, amax)
    local ex = (amax.x - amin.x) * 0.5
    local ey = (amax.y - amin.y) * 0.5
    local ez = (amax.z - amin.z) * 0.5

    local hMins = Vector(-ex * 0.8, -ey * 0.35, -ez * 0.35)
    local hMaxs = Vector(ex * 0.8, ey * 0.35, ez * 0.35)
    EnforceMinBoxSize(hMins, hMaxs)

    local vMins = Vector(-ez * 0.35, -ey * 0.35, -ex)
    local vMaxs = Vector(ez * 0.35, ey * 0.35, ex)
    EnforceMinBoxSize(vMins, vMaxs)

    return hMins, hMaxs, vMins, vMaxs, ex, ey, ez
end

-- Kept for any external callers expecting the old single-orientation helper
local function GetWeaponCollisionBox(phys, isVertical)
    local amin, amax = phys:GetAABB()
    if not amin or not amax then
        if DebugEnabled() then vrmod.logger.Debug("GetWeaponCollisionBox: Invalid AABB, returning defaults") end
        return vrmod.DEFAULT_MINS, vrmod.DEFAULT_MAXS, isVertical, vrmod.DEFAULT_MINS, vrmod.DEFAULT_MAXS
    end
    local hMins, hMaxs, vMins, vMaxs = BoxesFromAABB(amin, amax)
    if isVertical then
        return vMins, vMaxs, true, amin, amax
    end
    return hMins, hMaxs, false, amin, amax
end

--- Sphere vs world. Returns isClipped, hitNormal, pushOutPos.
--- resolve=false skips push-out iterations (overlap test only).
local function SphereCollidesWithWorld(pos, radius, resolve)
    local mins, maxs = SetSymmetricHull(radius)
    local tr = util.TraceHull({
        start = pos,
        endpos = pos,
        mins = mins,
        maxs = maxs,
        mask = MASK_SOLID_BRUSHONLY
    })

    if not tr.Hit or not tr.HitWorld then return false, ZERO_UP, pos end
    if resolve == false then return true, tr.HitNormal, pos end

    local pushPos = pos
    local hitNormal = tr.HitNormal
    for _ = 1, 2 do
        local pushTrace = util.TraceHull({
            start = pushPos,
            endpos = pushPos + hitNormal * radius * 1.1,
            mins = mins,
            maxs = maxs,
            mask = MASK_SOLID_BRUSHONLY
        })

        if not pushTrace.Hit then
            pushPos = pushTrace.EndPos
            break
        end
        pushPos = pushTrace.HitPos + pushTrace.HitNormal * 0.1
        hitNormal = pushTrace.HitNormal
    end
    return true, hitNormal, pushPos
end

--- Box vs world (optional reach sweep). Returns isClipped, hitNormal, pushOutPos.
--- When resolve=false, skips push-out (boolean hit only).
local function BoxCollidesWithWorld(pos, ang, mins, maxs, reach, resolve)
    ang = ang or angle_zero
    local endPos = reach and (pos + ang:Forward() * reach) or pos
    local tr = util.TraceHull({
        start = pos,
        endpos = endPos,
        angles = ang,
        mins = mins,
        maxs = maxs,
        mask = MASK_SOLID_BRUSHONLY
    })

    if not tr.Hit or not tr.HitWorld then return false, ZERO_UP, pos end
    if resolve == false then return true, tr.HitNormal, pos end

    local hitNormal = tr.HitNormal
    local pushPos
    if not tr.StartSolid then
        if tr.StartPos and tr.EndPos and tr.Fraction then
            pushPos = tr.StartPos + (tr.EndPos - tr.StartPos) * tr.Fraction - tr.HitNormal * 0.1
        else
            pushPos = pos - (hitNormal:IsZero() and ZERO_UP or hitNormal) * 0.1
        end
    else
        if hitNormal:LengthSqr() < 0.1 then
            hitNormal = ZERO_UP
        end
        local boxSize = math.max(maxs.x - mins.x, maxs.y - mins.y, maxs.z - mins.z) * 0.5
        pushPos = pos
        for _ = 1, 2 do
            local pushTrace = util.TraceHull({
                start = pushPos,
                endpos = pushPos + hitNormal * boxSize * 1.1,
                angles = ang,
                mins = mins,
                maxs = maxs,
                mask = MASK_SOLID_BRUSHONLY
            })

            if not pushTrace.Hit then
                pushPos = pushTrace.EndPos
                break
            end
            pushPos = pushTrace.HitPos + pushTrace.HitNormal * 0.1
            hitNormal = pushTrace.HitNormal
        end
    end
    return true, hitNormal, pushPos
end

-- Reused corner vectors for offsetAng AABB transform (no per-call allocs)
local meleeCorners = {
    Vector(), Vector(), Vector(), Vector(),
    Vector(), Vector(), Vector(), Vector()
}

local MELEE_NAME_HINTS = {
    crowbar = true, knife = true, melee = true, bat = true,
    katana = true, sword = true, axe = true, machete = true, club = true
}

local function ModelNameLooksMelee(modelPath)
    local lower = string.lower(modelPath or "")
    for hint in pairs(MELEE_NAME_HINTS) do
        if string.find(lower, hint, 1, true) then return true end
    end
    return false
end

--- Melee detection from AABB sizes (optionally rotated into hand space).
--- Uses precomputed amin/amax — no second GetAABB.
local function DetectMeleeFromAABB(modelPath, amin, amax, offsetAng)
    if ModelNameLooksMelee(modelPath) then return true end
    if not amin or not amax then return false end

    local sizeX = amax.x - amin.x
    local sizeY = amax.y - amin.y
    local sizeZ = amax.z - amin.z

    -- Only rotate the box when offsetAng is meaningful
    local ang = offsetAng
    if ang and (ang.p ~= 0 or ang.y ~= 0 or ang.r ~= 0) then
        local i = 1
        for ix = 0, 1 do
            local x = ix == 0 and amin.x or amax.x
            for iy = 0, 1 do
                local y = iy == 0 and amin.y or amax.y
                for iz = 0, 1 do
                    local z = iz == 0 and amin.z or amax.z
                    local v = meleeCorners[i]
                    v.x, v.y, v.z = x, y, z
                    v:Rotate(ang)
                    i = i + 1
                end
            end
        end
        local mnX, mnY, mnZ = meleeCorners[1].x, meleeCorners[1].y, meleeCorners[1].z
        local mxX, mxY, mxZ = mnX, mnY, mnZ
        for j = 2, 8 do
            local v = meleeCorners[j]
            if v.x < mnX then mnX = v.x end
            if v.y < mnY then mnY = v.y end
            if v.z < mnZ then mnZ = v.z end
            if v.x > mxX then mxX = v.x end
            if v.y > mxY then mxY = v.y end
            if v.z > mxZ then mxZ = v.z end
        end
        sizeX, sizeY, sizeZ = mxX - mnX, mxY - mnY, mxZ - mnZ
    end

    local longest = math.max(sizeX, sizeY, sizeZ)
    local shortest = math.min(sizeX, sizeY, sizeZ)
    if shortest < 0.01 then return false end
    -- Long/thin with longest axis along Z (hand up) → melee
    return sizeZ == longest and (longest / shortest) >= 4.5
end

local function MakeDefaultParams(isMelee)
    return {
        radius = vrmod.DEFAULT_RADIUS,
        reach = vrmod.DEFAULT_REACH,
        mins_horizontal = vrmod.DEFAULT_MINS,
        maxs_horizontal = vrmod.DEFAULT_MAXS,
        mins_vertical = vrmod.DEFAULT_MINS,
        maxs_vertical = vrmod.DEFAULT_MAXS,
        angles = vrmod.DEFAULT_ANGLES,
        computed = true,
        isMelee = isMelee or false
    }
end

local function ScheduleModelCompute(modelPath, ply, offsetAng)
    if not modelPath or modelPath == "" then return end
    if vrmod.modelCache[modelPath] and vrmod.modelCache[modelPath].computed then return end
    if pending[modelPath] then return end
    pending[modelPath] = {
        attempts = 0
    }
    timer.Simple(0, function()
        vrmod.utils.ComputePhysicsParams(modelPath)
        local cache = vrmod.modelCache[modelPath]
        if cache and cache.computed and IsValid(ply) then
            vrmod.utils.GetModelParams(modelPath, ply, offsetAng)
        end
    end)
    if DebugEnabled() then vrmod.logger.Debug("ScheduleModelCompute: queued %s", modelPath) end
end

-- COLLISIONS
function vrmod.utils.ComputePhysicsParams(modelPath)
    if not modelPath or modelPath == "" then
        if DebugEnabled() then vrmod.logger.Warn("Invalid or empty model path, caching defaults") end
        vrmod.modelCache[modelPath or ""] = MakeDefaultParams(false)
        return
    end

    local originalModelPath = modelPath
    local existing = vrmod.modelCache[originalModelPath]
    if existing and existing.computed then return end

    -- Prefer world models for c_ viewmodels (better phys AABB)
    if modelPath:match("^models/weapons/c_") then
        local baseName = modelPath:match("models/weapons/c_(.-)%.mdl")
        if baseName then
            local fallback = "models/weapons/w_" .. baseName .. ".mdl"
            if file.Exists(fallback, "GAME") then
                if DebugEnabled() then vrmod.logger.Debug("Replacing %s with valid worldmodel %s", modelPath, fallback) end
                modelPath = fallback
            else
                if DebugEnabled() then vrmod.logger.Debug("No valid fallback for %s, caching defaults", modelPath) end
                vrmod.modelCache[originalModelPath] = MakeDefaultParams(false)
                pending[originalModelPath] = nil
                return
            end
        end
    end

    pending[originalModelPath] = pending[originalModelPath] or {
        attempts = 0
    }

    if pending[originalModelPath].attempts >= 2 then
        if DebugEnabled() then vrmod.logger.Warn("Max retries (2) reached for %s, caching defaults", originalModelPath) end
        vrmod.modelCache[originalModelPath] = MakeDefaultParams(false)
        pending[originalModelPath] = nil
        return
    end

    pending[originalModelPath].attempts = pending[originalModelPath].attempts + 1
    util.PrecacheModel(modelPath)
    local ent = CLIENT and ents.CreateClientProp(modelPath) or ents.Create("prop_physics")
    if not IsValid(ent) then
        if DebugEnabled() then vrmod.logger.Err("Failed to spawn %s (attempt %d)", modelPath, pending[originalModelPath].attempts) end
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
        -- Single GetAABB for everything: melee detect, both boxes, reach
        local amin, amax = phys:GetAABB()
        if amin and amax then
            local offsetAng = vrmod.DEFAULT_ANGLES
            if g_VR and g_VR.currentvmi and g_VR.currentvmi.offsetAng then
                offsetAng = g_VR.currentvmi.offsetAng
            end

            local isMelee = DetectMeleeFromAABB(modelPath, amin, amax, offsetAng)
            local hMins, hMaxs, vMins, vMaxs = BoxesFromAABB(amin, amax)

            if isMelee then
                -- Melee uses vertical box; keep horizontal as defaults for non-melee callers
                hMins, hMaxs = vrmod.DEFAULT_MINS, vrmod.DEFAULT_MAXS
            end

            local sizeX = amax.x - amin.x
            local sizeY = amax.y - amin.y
            local sizeZ = amax.z - amin.z
            local reach = math.Clamp(math.max(sizeX, sizeY, sizeZ) * 0.75, 6.6, 50)

            vrmod.modelCache[originalModelPath] = {
                radius = reach,
                reach = reach,
                mins_horizontal = hMins,
                maxs_horizontal = hMaxs,
                mins_vertical = vMins,
                maxs_vertical = vMaxs,
                angles = vrmod.DEFAULT_ANGLES,
                computed = true,
                isMelee = isMelee
            }

            -- Also cache under the resolved world-model path so lookups by either key hit
            if modelPath ~= originalModelPath then
                vrmod.modelCache[modelPath] = vrmod.modelCache[originalModelPath]
            end

            if DebugEnabled() then
                vrmod.logger.Info("Computed collision boxes for %s → reach: %.2f units, melee: %s", modelPath, reach, tostring(isMelee))
            end
        else
            if DebugEnabled() then vrmod.logger.Warn("Empty AABB for %s, attempt %d", modelPath, pending[originalModelPath].attempts) end
        end
    else
        if DebugEnabled() then vrmod.logger.Warn("No valid physobj for %s, attempt %d", modelPath, pending[originalModelPath].attempts) end
    end

    ent:Remove()
    pending[originalModelPath].lastAttempt = CurTime()
    if vrmod.modelCache[originalModelPath] and vrmod.modelCache[originalModelPath].computed then
        pending[originalModelPath] = nil
    elseif pending[originalModelPath].attempts >= 2 then
        pending[originalModelPath] = nil
        if not vrmod.modelCache[originalModelPath] then
            vrmod.modelCache[originalModelPath] = MakeDefaultParams(false)
        end
    end
end

local function SyncModelParamsOnce(modelPath, cache, mins, maxs)
    if cache.sent then return end
    local isDefault = mins == vrmod.DEFAULT_MINS
        and maxs == vrmod.DEFAULT_MAXS
        and cache.radius == vrmod.DEFAULT_RADIUS
        and cache.reach == vrmod.DEFAULT_REACH
    if isDefault then
        if DebugEnabled() then vrmod.logger.Info("GetModelParams: Skipping sync for %s due to default parameters", modelPath) end
        return
    end

    net.Start("vrmod_sync_model_params")
    net.WriteString(modelPath)
    net.WriteFloat(cache.radius)
    net.WriteFloat(cache.reach)
    net.WriteVector(mins)
    net.WriteVector(maxs)
    net.WriteVector(cache.mins_vertical)
    net.WriteVector(cache.maxs_vertical)
    net.WriteAngle(cache.angles)
    if CLIENT then
        net.SendToServer()
    else
        net.Broadcast()
    end
    cache.sent = true
    if DebugEnabled() then vrmod.logger.Info("GetModelParams: Synced params for %s", modelPath) end
end

function vrmod.utils.GetModelParams(modelPath, ply, offsetAng)
    local cache = modelPath and vrmod.modelCache[modelPath]
    if cache and cache.computed then
        local mins = cache.isMelee and cache.mins_vertical or cache.mins_horizontal
        local maxs = cache.isMelee and cache.maxs_vertical or cache.maxs_horizontal
        SyncModelParamsOnce(modelPath, cache, mins, maxs)
        local ang = IsValid(ply) and vrmod.GetRightHandAng(ply) or vrmod.DEFAULT_ANGLES
        return cache.radius, cache.reach, mins, maxs, ang, cache.isMelee
    end

    ScheduleModelCompute(modelPath, ply, offsetAng)
    local ang = IsValid(ply) and vrmod.GetRightHandAng(ply) or vrmod.DEFAULT_ANGLES
    return vrmod.DEFAULT_RADIUS, vrmod.DEFAULT_REACH, vrmod.DEFAULT_MINS, vrmod.DEFAULT_MAXS, ang, false
end

-- Per-weapon model path cache (avoids WepInfo + string work every frame)
local wepModelCache = setmetatable({}, {
    __mode = "k"
}) -- weak keys: weapon entities

local function ResolveWeaponModel(wep, hand)
    if hand ~= "right" then
        return cl_effectmodel:GetString(), vrmod.DEFAULT_ANGLES
    end
    if not IsValid(wep) then return nil, vrmod.DEFAULT_ANGLES end

    local cached = wepModelCache[wep]
    if cached then return cached.model, cached.offsetAng end

    local class, vm = vrmod.utils.WepInfo(wep)
    if not class then return nil, vrmod.DEFAULT_ANGLES end

    local model, offsetAng
    if CLIENT then
        local vmInfo = g_VR.viewModelInfo and g_VR.viewModelInfo[class]
        offsetAng = vmInfo and vmInfo.offsetAng or vrmod.DEFAULT_ANGLES
        model = vm
    else
        offsetAng = vrmod.DEFAULT_ANGLES
        model = vrmod.MODEL_OVERRIDES[class] or wep:GetModel()
    end

    wepModelCache[wep] = {
        model = model,
        offsetAng = offsetAng,
        class = class
    }
    return model, offsetAng
end

function vrmod.utils.GetWeaponMeleeParams(wep, ply, hand)
    local model, offsetAng = ResolveWeaponModel(wep, hand or "right")
    if not model then return vrmod.DEFAULT_RADIUS, vrmod.DEFAULT_REACH, vrmod.DEFAULT_MINS, vrmod.DEFAULT_MAXS, vrmod.DEFAULT_ANGLES, false end
    return vrmod.utils.GetModelParams(model, ply, offsetAng)
end

function vrmod.utils.GetCachedWeaponParams(wep, ply, side)
    if not vrmod.utils.IsValidWep(wep) then return nil end

    local model, offsetAng = ResolveWeaponModel(wep, side or "right")
    if not model then return nil end

    local cache = vrmod.modelCache[model]
    if cache and cache.computed then
        local mins = cache.isMelee and cache.mins_vertical or cache.mins_horizontal
        local maxs = cache.isMelee and cache.maxs_vertical or cache.maxs_horizontal
        return cache.radius, cache.reach, mins, maxs, cache.angles, cache.isMelee
    end

    -- Still computing / failed recently
    local p = pending[model]
    if p and CurTime() - (p.lastAttempt or 0) < 2 and p.attempts > 0 and not (vrmod.modelCache[model] and vrmod.modelCache[model].computed) then
        if DebugEnabled() then vrmod.logger.Debug("GetCachedWeaponParams: waiting on %s", model) end
        return nil
    end

    ScheduleModelCompute(model, ply, offsetAng)
    return nil
end

function vrmod.utils.AdjustCollisionsBox(pos, ang, isMelee)
    local forwardOffset = isMelee and 3 or 10
    local leftOffset = isMelee and 1 or 1.5
    local upOffset = 4
    local adjustedPos = pos + ang:Forward() * forwardOffset - ang:Right() * leftOffset + ang:Up() * upOffset
    return adjustedPos
end

function vrmod.utils.GetClimbingGripState()
    local climb = vrmod and vrmod.climbing
    if not climb or not climb.IsHoldingLeft or not climb.IsHoldingRight then return false, false end
    return climb.IsHoldingLeft(), climb.IsHoldingRight()
end

local PRECHECK_MOVE_SQR = PRECHECK_MOVE_THRESHOLD * PRECHECK_MOVE_THRESHOLD
local POS_TOLERANCE_SQR = POS_TOLERANCE * POS_TOLERANCE

function vrmod.utils.CollisionsPreCheck(leftPos, rightPos)
    local ply = LocalPlayer()
    if not IsValid(ply) or not g_VR.active or not ply:GetNWBool("vrmod_server_enforce_collision", true) or ply:GetMoveType() == MOVETYPE_NOCLIP or not ply:Alive() or not vrmod.IsPlayerInVR(ply) or ply:InVehicle() then
        vrmod._collisionNearby = false
        lastPreCheckResult = false
        return
    end

    -- === MOVEMENT-BASED SKIP ===
    local leftMoved = leftPos:DistToSqr(lastPreCheckLeft) > PRECHECK_MOVE_SQR
    local rightMoved = rightPos:DistToSqr(lastPreCheckRight) > PRECHECK_MOVE_SQR
    if not leftMoved and not rightMoved then
        vrmod._collisionNearby = lastPreCheckResult
        return
    end

    lastPreCheckLeft:Set(leftPos)
    lastPreCheckRight:Set(rightPos)
    -- Broadphase only: single hull each, no push-out resolve
    local bigRadius = vrmod.utils.IsValidWep(ply:GetActiveWeapon()) and 69 or 30
    lastPreCheckResult = WorldBrushOverlaps(leftPos, 30) or WorldBrushOverlaps(rightPos, bigRadius)
    vrmod._collisionNearby = lastPreCheckResult
end

--- World collision for a hand/weapon sample.
--- One clip resolve + optional cheap reach sweep (was up to 3 full resolves).
function vrmod.utils.CheckWorldCollisions(pos, radius, mins, maxs, ang, hand, reach, gripping)
    if gripping == nil then
        local leftGrip, rightGrip = vrmod.utils.GetClimbingGripState()
        gripping = hand == "left" and leftGrip or hand == "right" and rightGrip
    end

    radius = radius or vrmod.DEFAULT_RADIUS
    local shapeMins = mins
    local shapeMaxs = maxs
    if not shapeMins or not shapeMaxs then
        shapeMins = Vector(-radius, -radius, -radius)
        shapeMaxs = Vector(radius, radius, radius)
    end
    ang = ang or angle_zero

    local isClipped, hitNormal, resolvedPos
    if mins and maxs then
        isClipped, hitNormal, resolvedPos = BoxCollidesWithWorld(pos, ang, shapeMins, shapeMaxs, nil, true)
        if DebugEnabled() and isClipped then
            vrmod.logger.Debug("Box collision for:", hand, "Pos:", pos, "Angles:", ang, "Mins:", shapeMins, "Maxs:", shapeMaxs, "Hit:", isClipped)
        end
    else
        isClipped, hitNormal, resolvedPos = SphereCollidesWithWorld(pos, radius, true)
        if DebugEnabled() and isClipped then
            vrmod.logger.Debug("Sphere collision for:", hand, "Pos:", pos, "Radius:", radius, "Hit:", isClipped)
        end
    end

    local pushOutPos = pos
    if isClipped and not gripping then
        -- Prefer last free sample (blocks pass-through), else depenetration result
        if lastNonClippedPos[hand] then
            pushOutPos = lastNonClippedPos[hand]
        elseif resolvedPos and isvector(resolvedPos) then
            pushOutPos = resolvedPos
            if hitNormal and not hitNormal:IsZero() then
                pushOutPos = pushOutPos + hitNormal * 0.25
            end
        else
            pushOutPos = pos + (hitNormal or ZERO_UP) * (radius or vrmod.DEFAULT_RADIUS)
        end
        cachedPushOutPos[hand] = pushOutPos
    else
        lastNonClippedPos[hand] = pos
        cachedPushOutPos[hand] = nil
    end

    local reachHit = false
    if reach and reach > 0 then
        if mins and maxs then
            reachHit = BoxSweepHitsWorld(pos, ang, shapeMins, shapeMaxs, reach)
        else
            local tr = util.TraceLine({
                start = pos,
                endpos = pos + ang:Forward() * reach,
                mask = MASK_SOLID_BRUSHONLY
            })
            reachHit = tr.Hit and tr.HitWorld or false
        end
    end

    return {
        pos = pos,
        radius = radius,
        mins = shapeMins,
        maxs = shapeMaxs,
        angles = ang,
        hit = reachHit,
        pushOutPos = pushOutPos,
        isClipped = isClipped,
        hitNormal = hitNormal,
        -- Same as clip probe (was a full third Box/Sphere resolve)
        hitWorld = isClipped
    }
end

-- Weapon box free-sample (same sweep idea as hands). Corrections are applied to the
-- *hand* pose so the gun stays locked to g_VR.tracking.pose_righthand.
local wepWall = {
    lastFree = Vector(),
    hasFree = false
}

--- Push-out clearance *beyond* the hull surface (from vrmod_hand_collision_push).
--- This is the full pad applied along hit normal at rest — not "added on top of radius"
--- twice (old code used radius+push which made the slider feel dead).
local function GetWallPushPad()
    local cv = cv_hand_push
    if not cv then return 0.75 end
    return math.Clamp(cv:GetFloat(), 0, 8)
end

--- True if v is a usable Vector-like (engine Vector or plain table with x/y/z).
local function IsVec(v)
	return v ~= nil and v.x ~= nil and v.y ~= nil and v.z ~= nil
end

--- Rest position just outside a brush hit. Never returns nil.
local function WallRestPos(hitPos, hitNormal, pad, fallback)
	if not IsVec(hitPos) then
		return fallback
	end
	local n = hitNormal
	if not IsVec(n) or n:LengthSqr() < 0.01 then
		n = ZERO_UP
	end
	return hitPos + n * (pad or 0)
end

-- ONLY abandon wall correction for absurd teleports (safe sample far beyond arm reach
-- of the HMD). Do NOT compare safe vs desired — that distance IS penetration depth,
-- and releasing there made hands pass through walls as soon as you pressed in.
local WALL_RELEASE_FROM_HMD_SQR = 100 * 100 -- ~100u past arm-length absurdity

local function ShouldReleaseWallLock(safePos, _desiredPos)
	if not IsVec(safePos) then return true end
	local hmd = g_VR.tracking and g_VR.tracking.hmd and g_VR.tracking.hmd.pos
	if IsVec(hmd) and safePos:DistToSqr(hmd) > WALL_RELEASE_FROM_HMD_SQR then
		return true
	end
	return false
end

--- Default gun hull when model AABB cache is not ready (long enough to block barrel cheat)
local DEFAULT_GUN_MINS = Vector(-2, -2.5, -2)
local DEFAULT_GUN_MAXS = Vector(20, 2.5, 2.5) -- extends along local forward (X)
-- Hands/gun hull: brush world only (cheap). Props as walls are rare; tip line can use SOLID.
local WEP_HULL_MASK = MASK_SOLID_BRUSHONLY
local WEP_TIP_MASK = MASK_SOLID_BRUSHONLY

--- Filter for wall traces: never hit held mags/props/viewmodels (mag-hold flicker).
local function WallFilter(ply)
	if vrmod.utils.WallCollisionFilter then
		return vrmod.utils.WallCollisionFilter(ply)
	end
	return ply
end

--- Mutate pose Vector in place when possible (Cube SoT: override g_VR.tracking.* fields).
--- Never allocate a parallel truth; callers that hold pose.pos see the block immediately.
local function AddPosInPlace(pos, delta)
	if not IsVec(pos) or not IsVec(delta) then return pos end
	if delta:LengthSqr() < 0.0001 then return pos end
	if pos.Add then
		pos:Add(delta)
		return pos
	end
	return pos + delta
end

--- Sweep weapon collision box + barrel tip.
--- Cube law: OVERRIDE the hand Vector that lives on g_VR.tracking (SoT).
--- rawTracking is never touched — device energy stays pure elsewhere.
local function ApplyWeaponWallToHand(handPos, handAng, ply)
    if not IsValid(ply) or not IsVec(handPos) or handAng == nil then return handPos, handAng end
    local wep = ply:GetActiveWeapon()
    if not vrmod.utils.IsValidWep(wep) then
        wepWall.hasFree = false
        table.Empty(vrmod.collisionBoxes)
        return handPos, handAng
    end

    local radius, reach, mins, maxs, _, isMelee = vrmod.utils.GetCachedWeaponParams(wep, ply, "right")
    if not mins or not maxs then
        mins = DEFAULT_GUN_MINS
        maxs = DEFAULT_GUN_MAXS
        radius = radius or 4
        reach = reach or 22
        isMelee = false
    else
        radius = radius or vrmod.DEFAULT_RADIUS
        reach = reach or vrmod.DEFAULT_REACH
        if not isnumber(reach) then
            reach = math.max(math.abs(maxs.x), math.abs(maxs.y), math.abs(maxs.z)) * 2
        end
    end

    local desired = vrmod.utils.AdjustCollisionsBox(handPos, handAng, isMelee)
    if not IsVec(desired) then return handPos, handAng end
    local pad = math.max(0.05, GetWallPushPad())
    local startPos = (wepWall.hasFree and IsVec(wepWall.lastFree) and wepWall.lastFree) or desired
    local fwd = handAng:Forward()
    local filter = WallFilter(ply)

    local function hullSweep(from, to)
        return util.TraceHull({
            start = from,
            endpos = to,
            angles = handAng,
            mins = mins,
            maxs = maxs,
            mask = WEP_HULL_MASK,
            filter = filter
        })
    end

    local tr = hullSweep(startPos, desired)

    local clipped = false
    local safe = desired
    local normal = ZERO_UP

    if tr.StartSolid or tr.AllSolid then
        clipped = true
        normal = (IsVec(tr.HitNormal) and tr.HitNormal:LengthSqr() > 0.01) and tr.HitNormal or ZERO_UP
        if wepWall.hasFree and IsVec(wepWall.lastFree) then
            safe = Vector(wepWall.lastFree)
        else
            local push = Vector(desired)
            -- Cap depenetrate steps (was 10 — latency spikes when buried in brush)
            for _ = 1, 5 do
                local t2 = hullSweep(push, push + normal * math.max(8, radius * 3))
                if not t2.StartSolid then
                    if t2.Hit then
                        safe = WallRestPos(t2.HitPos, t2.HitNormal, pad, desired)
                        normal = (IsVec(t2.HitNormal) and t2.HitNormal:LengthSqr() > 0.01) and t2.HitNormal or normal
                    else
                        safe = (IsVec(t2.EndPos) and t2.EndPos) or push
                    end
                    break
                end
                if IsVec(t2.HitNormal) and t2.HitNormal:LengthSqr() > 0.01 then
                    normal = t2.HitNormal
                end
                push = push + normal * math.max(2, radius)
            end
        end
    elseif tr.Hit then
        clipped = true
        normal = (IsVec(tr.HitNormal) and tr.HitNormal:LengthSqr() > 0.01) and tr.HitNormal or ZERO_UP
        safe = WallRestPos(tr.HitPos, normal, pad, desired)
    end

    if not IsVec(safe) then
        safe = desired
        clipped = false
    end

    if clipped and ShouldReleaseWallLock(safe, desired) then
        wepWall.hasFree = false
        if not IsVec(safe) or safe:DistToSqr(desired) < 0.01 then
            clipped = false
            safe = desired
        end
    end

    if clipped then
        handPos = AddPosInPlace(handPos, safe - desired)
    end

    -- Single tip ray (was mid+tip = 2 traces/frame) — palm free but barrel through wall
    local tipLen = math.max(reach, math.abs(maxs.x), 18)
    local tipEnd = handPos + fwd * tipLen + handAng:Up() * 1.5
    local tipTr = util.TraceLine({
        start = handPos,
        endpos = tipEnd,
        mask = WEP_TIP_MASK,
        filter = filter
    })
    if tipTr.Hit and not tipTr.StartSolid and tipTr.Fraction < 0.995 then
        local n = tipTr.HitNormal
        if not IsVec(n) or n:LengthSqr() < 0.01 then n = ZERO_UP end
        local tipDelta = (tipTr.HitPos - fwd * 0.75 + n * pad) - tipEnd
        local plen = tipDelta:LengthSqr()
        if plen > 0.0001 and plen < (48 * 48) then
            handPos = AddPosInPlace(handPos, tipDelta)
            clipped = true
            normal = n
        end
    end

    if not clipped then
        if not wepWall.lastFree then wepWall.lastFree = Vector() end
        wepWall.lastFree:Set(desired)
        wepWall.hasFree = true
    end

    vrmod.collisionBoxes = {{
        pos = desired,
        radius = radius,
        mins = mins,
        maxs = maxs,
        angles = handAng,
        hit = clipped,
        pushOutPos = handPos,
        isClipped = clipped,
        hitNormal = normal,
        hitWorld = clipped
    }}

    return handPos, handAng
end

--- Legacy name: still used by foregrip / utils. Always corrects the *hand* pose.
function vrmod.utils.CheckWeaponPushout(pos, ang)
    local ply = LocalPlayer()
    if not IsValid(ply)
        or not g_VR.active
        or not ply:GetNWBool("vrmod_server_enforce_collision", true)
        or ply:GetMoveType() == MOVETYPE_NOCLIP
        or not ply:Alive()
        or ply:InVehicle()
    then
        return pos, ang
    end
    return ApplyWeaponWallToHand(pos, ang, ply)
end

local handShapeStore = {
    left = nil,
    right = nil
}

-- Per-hand free-space sample (climbing-style sweep start). Never feed corrected poses
-- back as "desired" — that fights tracking and causes flicker/pass-through.
local handWall = {
    left = {
        lastFree = Vector(),
        hasFree = false
    },
    right = {
        lastFree = Vector(),
        hasFree = false
    }
}

-- If lastFree is farther than this from desired, path-to-desired can cross solid
-- (doors, corners, map loads) and permanently "tie" the hand to the old free sample.
local MAX_LASTFREE_DIST_SQR = 28 * 28
-- Never pull the hand more than this from device intent (anti-tether)
local MAX_HAND_CORRECTION = 18

--- Hull-sweep from last free sample → desired sample (same idea as
--- vrmod_climbing ResolveCameraOriginCollision). Returns safeSample, clipped, normal.
--- safeSample is always a Vector (never nil) when desiredSample is valid.
local function ResolveHandWallSweep(desiredSample, handKey, radius, filter)
	if not IsVec(desiredSample) then
		return Vector(), false, nil
	end

	local mins, maxs = SetSymmetricHull(radius)
	-- Hull already has radius; slider is pure extra push-out past the surface
	local pad = GetWallPushPad()
	local st = handWall[handKey]
	if not st then
		return desiredSample, false, nil
	end
	if not IsVec(st.lastFree) then
		st.lastFree = Vector()
		st.hasFree = false
	end

	local HAND_MASK = MASK_SOLID_BRUSHONLY

	local function isFree(pos)
		local t = util.TraceHull({
			start = pos,
			endpos = pos,
			mins = mins,
			maxs = maxs,
			mask = HAND_MASK,
			filter = filter
		})
		return not (t.StartSolid or t.AllSolid)
	end

	-- Drop stale free anchors — they are the "hands tied" bug (sweep from old room
	-- always hits something between lastFree and the controller).
	if st.hasFree and IsVec(st.lastFree) then
		if st.lastFree:DistToSqr(desiredSample) > MAX_LASTFREE_DIST_SQR or not isFree(st.lastFree) then
			st.hasFree = false
		end
	end

	-- Desired free + no valid continuous lastFree → pure tracking (device energy wins)
	if isFree(desiredSample) and not st.hasFree then
		return desiredSample, false, nil
	end

	-- Prefer last free → desired sweep (climbing-style). If lastFree is itself
	-- buried (player teleported / map change), drop it and depenetrate from desired.
	local startPos = desiredSample
	if st.hasFree and IsVec(st.lastFree) and isFree(st.lastFree) then
		startPos = st.lastFree
	else
		st.hasFree = false
	end

	-- Desired free, lastFree nearby: if short path is clear, unlock fully
	if isFree(desiredSample) and startPos == st.lastFree then
		local clear = util.TraceHull({
			start = startPos,
			endpos = desiredSample,
			mins = mins,
			maxs = maxs,
			mask = HAND_MASK,
			filter = filter
		})
		if not clear.Hit and not clear.StartSolid and not clear.AllSolid then
			return desiredSample, false, nil
		end
	end

	local tr = util.TraceHull({
		start = startPos,
		endpos = desiredSample,
		mins = mins,
		maxs = maxs,
		mask = HAND_MASK,
		filter = filter
	})

	-- Stuck in solid at the start of the sweep
	if tr.StartSolid or tr.AllSolid then
		-- Prefer known free sample over raw desired (desired is still in the wall)
		if st.hasFree and IsVec(st.lastFree) and isFree(st.lastFree) then
			local n = tr.HitNormal
			if not IsVec(n) or n:LengthSqr() < 0.01 then n = ZERO_UP end
			return Vector(st.lastFree), true, n
		end

		local n = tr.HitNormal
		if not IsVec(n) or n:LengthSqr() < 0.01 then
			n = ZERO_UP
		end
		local push = Vector(desiredSample)
		for _ = 1, 6 do
			local t2 = util.TraceHull({
				start = push,
				endpos = push + n * (radius * 3),
				mins = mins,
				maxs = maxs,
				mask = HAND_MASK,
				filter = filter
			})
			if not t2.StartSolid then
				if t2.Hit then
					return WallRestPos(t2.HitPos, t2.HitNormal, pad, push), true, (IsVec(t2.HitNormal) and t2.HitNormal) or n
				end
				local endp = (IsVec(t2.EndPos) and t2.EndPos) or push
				return endp, true, n
			end
			if IsVec(t2.HitNormal) and t2.HitNormal:LengthSqr() > 0.01 then
				n = t2.HitNormal
			end
			push = push + n * math.max(radius, 1)
		end
		-- Still solid: hold last free if any, else try a hard normal kick from desired
		if st.hasFree and IsVec(st.lastFree) then
			return Vector(st.lastFree), true, n
		end
		return desiredSample + n * (radius + pad + 2), true, n
	end

	if tr.Hit then
		-- Contact: rest just outside the wall (climbing-style). This is the
		-- path that must always block — never pass desired through.
		local n = tr.HitNormal
		if not IsVec(n) or n:LengthSqr() < 0.01 then
			n = ZERO_UP
		end
		-- vrmod_hand_collision_push is the full extra clearance past the surface
		local restPad = math.max(0.05, pad)
		return WallRestPos(tr.HitPos, n, restPad, startPos), true, n
	end

	return desiredSample, false, nil
end

local function MakeHandShape(samplePos, radius, ang, clipped, pushOut, normal, reachHit)
    return {
        pos = samplePos,
        radius = radius,
        mins = Vector(-radius, -radius, -radius),
        maxs = Vector(radius, radius, radius),
        angles = ang,
        hit = reachHit or false,
        pushOutPos = pushOut or samplePos,
        isClipped = clipped and true or false,
        hitNormal = normal,
        hitWorld = clipped and true or false
    }
end

local function ClearHandWallState(handKey)
    handWall[handKey].hasFree = false
    lastNonClippedPos[handKey] = nil
    lastNonClippedNormal[handKey] = nil
    cachedPushOutPos[handKey] = nil
end

--- Real-time hand wall collisions.
---
--- Cube Truth Matrix:
---   • g_VR.rawTracking  = device energy (NEVER written here)
---   • g_VR.tracking     = Source of Truth — OVERRIDDEN in place
--- Guns / ArcVR / hands read g_VR.tracking directly (not only the API).
--- So we mutate pose.pos / pose.ang Vectors on tracking; we do not invent a
--- parallel return-only truth that callers can forget to WritePose.
---
--- Call with no args to override tracking SoT. Optional pos/ang args still
--- supported; when they are the same Vector as tracking.pos, in-place wins.
function vrmod.utils.UpdateHandCollisions(lefthandPos, lefthandAng, righthandPos, righthandAng)
    local ply = LocalPlayer()
    local leftT = g_VR.tracking and g_VR.tracking.pose_lefthand
    local rightT = g_VR.tracking and g_VR.tracking.pose_righthand

    -- Default: operate on tracking SoT fields (what the gun actually reads)
    local inPlace = (lefthandPos == nil)
    if inPlace then
        if not leftT or not rightT or not IsVec(leftT.pos) or not IsVec(rightT.pos) then
            return nil, nil, nil, nil
        end
        lefthandPos, lefthandAng = leftT.pos, leftT.ang
        righthandPos, righthandAng = rightT.pos, rightT.ang
    end

    local function passthrough()
        table.Empty(vrmod.collisionSpheres)
        handShapeStore.left = nil
        handShapeStore.right = nil
        vrmod._collisionShapeByHand = handShapeStore
        ClearHandWallState("left")
        ClearHandWallState("right")
        vrmod._lastGoodShapeLeft = nil
        vrmod._lastGoodShapeRight = nil
        return lefthandPos, lefthandAng, righthandPos, righthandAng
    end

    if not IsVec(lefthandPos) or not IsVec(righthandPos) or lefthandAng == nil or righthandAng == nil then
        return passthrough()
    end

    local cvCol = GetConVar("vrmod_collisions")
    local colOn = (not cvCol or cvCol:GetBool()) and ply:GetNWBool("vrmod_server_enforce_collision", true)
    if not IsValid(ply)
        or not g_VR.active
        or not colOn
        or ply:GetMoveType() == MOVETYPE_NOCLIP
        or not ply:Alive()
        or not vrmod.IsPlayerInVR(ply)
        or ply:InVehicle()
    then
        wepWall.hasFree = false
        return passthrough()
    end

    local holdingGun = vrmod.utils.IsValidWep(ply:GetActiveWeapon())
    if not holdingGun then
        table.Empty(vrmod.collisionBoxes)
        wepWall.hasFree = false
    end

    local leftGrip, rightGrip = vrmod.utils.GetClimbingGripState()
    -- Keep hull modest — oversized radius permanently clips near floors/walls ("tied")
    local radius = math.max(vrmod.DEFAULT_RADIUS or 2.2, 2.2)
    local offset = math.min(vrmod.DEFAULT_OFFSET or 5, 2.5)
    -- Ignore held mags/props — otherwise left-hand mag reloads fight wall push (flicker)
    local filter = WallFilter(ply)

    table.Empty(vrmod.collisionSpheres)
    handShapeStore.left = nil
    handShapeStore.right = nil
    vrmod._collisionShapeByHand = handShapeStore

    local function processHand(handKey, trackPos, trackAng, gripping)
        if not IsVec(trackPos) or trackAng == nil then
            return trackPos, trackAng
        end

        if gripping then
            ClearHandWallState(handKey)
            if handKey == "left" then
                vrmod._lastGoodShapeLeft = nil
            else
                vrmod._lastGoodShapeRight = nil
            end
            return trackPos, trackAng
        end

        local desiredSample = trackPos + trackAng:Forward() * offset
        local safeSample, clipped, normal = ResolveHandWallSweep(desiredSample, handKey, radius, filter)
        if not IsVec(safeSample) then
            safeSample = desiredSample
            clipped = false
        end

        -- Reach probe only when debug shapes need it (saves a TraceLine every hand every frame)
        local reachHit = false
        if DebugEnabled() then
            local trReach = util.TraceLine({
                start = desiredSample,
                endpos = desiredSample + trackAng:Forward() * vrmod.DEFAULT_REACH,
                mask = MASK_SOLID_BRUSHONLY,
                filter = filter
            })
            reachHit = trReach.Hit or false
        end

        local shape = MakeHandShape(desiredSample, radius, trackAng, clipped, safeSample, normal, reachHit)
        vrmod.collisionSpheres[#vrmod.collisionSpheres + 1] = shape
        handShapeStore[handKey] = shape

        if handKey == "left" then
            vrmod._lastGoodShapeLeft = shape
        else
            vrmod._lastGoodShapeRight = shape
        end

        if clipped and ShouldReleaseWallLock(safeSample, desiredSample) then
            ClearHandWallState(handKey)
        end

        if clipped then
            -- IN-PLACE override of the tracking Vector (gun/hands see this immediately)
            local delta = safeSample - desiredSample
            -- Cap correction so a bad lastFree cannot tether hands far from controllers
            local dlen = delta:Length()
            if dlen > MAX_HAND_CORRECTION then
                delta = delta * (MAX_HAND_CORRECTION / dlen)
                -- Stale lock — drop free anchor so next frame re-evaluates from tracking
                ClearHandWallState(handKey)
            end
            trackPos = AddPosInPlace(trackPos, delta)
            cachedPushOutPos[handKey] = safeSample
            lastNonClippedNormal[handKey] = normal
        else
            local st = handWall[handKey]
            if st then
                if not IsVec(st.lastFree) then
                    st.lastFree = Vector()
                end
                st.lastFree:Set(desiredSample)
                st.hasFree = true
            end
            lastNonClippedPos[handKey] = desiredSample
            cachedPushOutPos[handKey] = nil
        end

        return trackPos, trackAng
    end

    lefthandPos, lefthandAng = processHand("left", lefthandPos, lefthandAng, leftGrip)
    righthandPos, righthandAng = processHand("right", righthandPos, righthandAng, rightGrip)

    -- Gun block: same right-hand tracking Vector (shared with g_VR.tracking.pose_righthand.pos)
    if holdingGun and not rightGrip then
        righthandPos, righthandAng = ApplyWeaponWallToHand(righthandPos, righthandAng, ply)
    end

    -- If caller passed non-tracking vectors, still push result into SoT so gun sees it
    if not inPlace and leftT and rightT then
        if IsVec(lefthandPos) and leftT.pos and leftT.pos.Set and lefthandPos ~= leftT.pos then
            leftT.pos:Set(lefthandPos)
        end
        if IsVec(righthandPos) and rightT.pos and rightT.pos.Set and righthandPos ~= rightT.pos then
            rightT.pos:Set(righthandPos)
        end
        if lefthandAng and leftT.ang and leftT.ang.Set and lefthandAng ~= leftT.ang then
            leftT.ang:Set(lefthandAng)
        end
        if righthandAng and rightT.ang and rightT.ang.Set and righthandAng ~= rightT.ang then
            rightT.ang:Set(righthandAng)
        end
    end

    return lefthandPos, lefthandAng, righthandPos, righthandAng
end

function vrmod.utils.SphereCollidesWithProp(pos, radius, filter)
    local mins, maxs = SetSymmetricHull(radius)
    local tr = util.TraceHull({
        start = pos,
        endpos = pos,
        mins = mins,
        maxs = maxs,
        mask = MASK_SOLID,
        filter = filter
    })

    if not tr.Hit or not IsValid(tr.Entity) then return false end
    if tr.Entity:IsWorld() then return false end
    return tr.Entity, tr.HitNormal
end