g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}
local cl_effectmodel = CreateClientConVar("vrmod_melee_fist_collisionmodel", "models/props_junk/PopCan01a.mdl", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
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
        -- Prefer surface resolve (smooth slide along wall). lastNonClipped is only a
        -- fallback — always snapping there causes hand flicker when the free sample
        -- and the wall alternate under small tracking noise.
        if resolvedPos and isvector(resolvedPos) then
            pushOutPos = resolvedPos
        elseif lastNonClippedPos[hand] then
            pushOutPos = lastNonClippedPos[hand]
        else
            pushOutPos = pos + (hitNormal or ZERO_UP)
        end
        -- Small outward bias so the next frame does not immediately re-penetrate
        if hitNormal and not hitNormal:IsZero() then
            pushOutPos = pushOutPos + hitNormal * 0.15
        end
        cachedPushOutPos[hand] = pushOutPos
    else
        lastNonClippedPos[hand] = Vector(pos)
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

-- Weapon pushout input/output cache (UpdateViewModelPos runs every frame)
local lastWepInPos = Vector()
local lastWepInAng = Angle()
local lastWepOutPos = Vector()
local lastWepOutAng = Angle()
local hasWepCache = false
local WEP_POS_EPS_SQR = 0.0025 -- 0.05^2
local WEP_ANG_EPS = 0.75

function vrmod.utils.CheckWeaponPushout(pos, ang)
    if not vrmod._collisionNearby then
        vrmod.collisionBoxes = {}
        hasWepCache = false
        return pos, ang
    end

    -- Reuse last correction when the hand barely moved (big win at 90 Hz viewmodel updates)
    if hasWepCache
        and pos:DistToSqr(lastWepInPos) < WEP_POS_EPS_SQR
        and math.abs(ang.pitch - lastWepInAng.pitch) < WEP_ANG_EPS
        and math.abs(ang.yaw - lastWepInAng.yaw) < WEP_ANG_EPS
        and math.abs(ang.roll - lastWepInAng.roll) < WEP_ANG_EPS
    then
        return lastWepOutPos, lastWepOutAng
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
    if not isnumber(reach) then reach = math.max(math.abs(maxs.x), math.abs(maxs.y), math.abs(maxs.z)) * 2 end
    local adjustedPos = vrmod.utils.AdjustCollisionsBox(pos, ang, isMelee)
    local shape = vrmod.utils.CheckWorldCollisions(adjustedPos, nil, mins, maxs, ang, "right", reach, false)
    vrmod.collisionBoxes = {}
    if shape then
        vrmod.collisionBoxes[1] = shape
    end

    local outPos, outAng = pos, ang
    if shape and shape.isClipped and shape.pushOutPos and isvector(shape.pushOutPos) then
        local normal = shape.hitNormal or ZERO_UP
        local plyPos = g_VR.tracking.hmd and g_VR.tracking.hmd.pos or vector_origin
        if shape.pushOutPos:DistToSqr(plyPos) > 500 then
            vrmod.collisionBoxes = {}
            hasWepCache = false
            return pos, ang
        end

        local correctedPos = Vector(pos.x, pos.y, pos.z)
        local absX, absY, absZ = math.abs(normal.x), math.abs(normal.y), math.abs(normal.z)
        local penetrationDepth = (pos - shape.pushOutPos):Dot(normal)
        if absX > absY and absX > absZ and absX > 0.45 then
            correctedPos.x = shape.pushOutPos.x + normal.x * penetrationDepth
        elseif absY > absX and absY > absZ and absY > 0.45 then
            correctedPos.y = shape.pushOutPos.y + normal.y * penetrationDepth
        elseif absZ > absX and absZ > absY and absZ > 0.45 then
            correctedPos.z = shape.pushOutPos.z + normal.z * penetrationDepth
        else
            correctedPos = shape.pushOutPos + normal * penetrationDepth
        end

        local correctedAng = Angle(ang.pitch, ang.yaw, ang.roll)
        local forward = ang:Forward()
        local dot = forward:Dot(normal)
        if math.abs(dot) > 0.1 then
            local adjustedForward = forward - normal * dot
            adjustedForward:Normalize()
            local newRight = adjustedForward:Cross(normal)
            newRight:Normalize()
            correctedAng = adjustedForward:Angle()
            correctedAng:RotateAroundAxis(newRight, ang:Up():Dot(newRight:Cross(adjustedForward)) < 0 and -90 or 90)
        end

        if DebugEnabled() then vrmod.logger.Debug("Weapon clipping detected. Push-out pos:", correctedPos, "angle:", correctedAng) end
        outPos, outAng = correctedPos, correctedAng
    end

    lastWepInPos:Set(pos)
    lastWepInAng:Set(ang)
    lastWepOutPos:Set(outPos)
    lastWepOutAng:Set(outAng)
    hasWepCache = true
    return outPos, outAng
end

local handShapeStore = {
    left = nil,
    right = nil
}

function vrmod.utils.UpdateHandCollisions(lefthandPos, lefthandAng, righthandPos, righthandAng)
    if not vrmod._collisionNearby then
        table.Empty(vrmod.collisionSpheres)
        table.Empty(vrmod.collisionBoxes)
        handShapeStore.left = nil
        handShapeStore.right = nil
        vrmod._collisionShapeByHand = handShapeStore
        lastNonClippedPos.left = nil
        lastNonClippedPos.right = nil
        lastNonClippedNormal.left = nil
        lastNonClippedNormal.right = nil
        cachedPushOutPos.left = nil
        cachedPushOutPos.right = nil
        hasWepCache = false
        return lefthandPos, lefthandAng, righthandPos, righthandAng
    end

    local ply = LocalPlayer()
    if not IsValid(ply) then return lefthandPos, lefthandAng, righthandPos, righthandAng end
    if not vrmod.utils.IsValidWep(ply:GetActiveWeapon()) then
        table.Empty(vrmod.collisionBoxes)
    end

    local leftGrip, rightGrip = vrmod.utils.GetClimbingGripState()
    local leftPos = lefthandPos + lefthandAng:Forward() * vrmod.DEFAULT_OFFSET
    local rightPos = righthandPos + righthandAng:Forward() * vrmod.DEFAULT_OFFSET

    table.Empty(vrmod.collisionSpheres)
    handShapeStore.left = nil
    handShapeStore.right = nil
    vrmod._collisionShapeByHand = handShapeStore

    -- ==================== LEFT HAND ====================
    if leftGrip then
        cachedPushOutPos.left = nil
        lastNonClippedPos.left = nil
        lastNonClippedNormal.left = nil
        vrmod._lastGoodShapeLeft = nil
    else
        -- Always re-trace when clipped last frame so we track the wall continuously;
        -- only skip traces when free and the hand barely moved.
        local wasClipped = vrmod._lastGoodShapeLeft and vrmod._lastGoodShapeLeft.isClipped
        local moved = leftPos:DistToSqr(lastCheckedHandPos.left) > POS_TOLERANCE_SQR
            or math.abs(lefthandAng.pitch - lastCheckedHandAng.left.pitch) > ANG_TOLERANCE
            or math.abs(lefthandAng.yaw - lastCheckedHandAng.left.yaw) > ANG_TOLERANCE
        local shape
        if moved or wasClipped then
            shape = vrmod.utils.CheckWorldCollisions(leftPos, vrmod.DEFAULT_RADIUS, nil, nil, lefthandAng, "left", vrmod.DEFAULT_REACH, leftGrip)
            lastCheckedHandPos.left:Set(leftPos)
            lastCheckedHandAng.left:Set(lefthandAng)
        else
            shape = vrmod._lastGoodShapeLeft or handShapeStore.left
        end

        if shape and shape.isClipped and shape.pushOutPos then
            -- Apply offset from sample point (leftPos) back onto tracking origin
            lefthandPos = lefthandPos + (shape.pushOutPos - leftPos)
            cachedPushOutPos.left = shape.pushOutPos
            lastNonClippedNormal.left = shape.hitNormal
            vrmod._lastGoodShapeLeft = shape
        else
            vrmod._lastGoodShapeLeft = shape
        end

        if shape then
            vrmod.collisionSpheres[#vrmod.collisionSpheres + 1] = shape
            handShapeStore.left = shape
        end
    end

    -- ==================== RIGHT HAND ====================
    if rightGrip then
        cachedPushOutPos.right = nil
        lastNonClippedPos.right = nil
        lastNonClippedNormal.right = nil
        vrmod._lastGoodShapeRight = nil
    else
        local wasClipped = vrmod._lastGoodShapeRight and vrmod._lastGoodShapeRight.isClipped
        local moved = rightPos:DistToSqr(lastCheckedHandPos.right) > POS_TOLERANCE_SQR
            or math.abs(righthandAng.pitch - lastCheckedHandAng.right.pitch) > ANG_TOLERANCE
            or math.abs(righthandAng.yaw - lastCheckedHandAng.right.yaw) > ANG_TOLERANCE
        local shape
        if moved or wasClipped then
            shape = vrmod.utils.CheckWorldCollisions(rightPos, vrmod.DEFAULT_RADIUS, nil, nil, righthandAng, "right", vrmod.DEFAULT_REACH, rightGrip)
            lastCheckedHandPos.right:Set(rightPos)
            lastCheckedHandAng.right:Set(righthandAng)
        else
            shape = vrmod._lastGoodShapeRight or handShapeStore.right
        end

        if shape and shape.isClipped and shape.pushOutPos then
            righthandPos = righthandPos + (shape.pushOutPos - rightPos)
            cachedPushOutPos.right = shape.pushOutPos
            lastNonClippedNormal.right = shape.hitNormal
            vrmod._lastGoodShapeRight = shape
        else
            vrmod._lastGoodShapeRight = shape
        end

        if shape then
            vrmod.collisionSpheres[#vrmod.collisionSpheres + 1] = shape
            handShapeStore.right = shape
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