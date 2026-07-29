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

local function GetWeaponCollisionBox(phys, isVertical)
    local mins, maxs = phys:GetAABB()
    if not mins or not maxs then
        if DebugEnabled() then vrmod.logger.Debug("GetWeaponCollisionBox: Invalid AABB, returning defaults") end
        return vrmod.DEFAULT_MINS, vrmod.DEFAULT_MAXS, isVertical, vrmod.DEFAULT_MINS, vrmod.DEFAULT_MAXS
    end

    local amin, amax = mins, maxs -- Store raw AABB for return
    -- Calculate the extents of the AABB
    local extents = (maxs - mins) * 0.5
    if isVertical then
        -- Vertical alignment: prioritize z-axis, swap x and z extents
        mins = Vector(-extents.z * 0.35, -extents.y * 0.35, -extents.x)
        maxs = Vector(extents.z * 0.35, extents.y * 0.35, extents.x)
        if DebugEnabled() then vrmod.logger.Debug("GetWeaponCollisionBox: Vertical-aligned (z-axis) | Mins: %s, Maxs: %s", tostring(mins), tostring(maxs)) end
    else
        -- Forward alignment: prioritize x-axis
        mins = Vector(-extents.x * 0.8, -extents.y * 0.35, -extents.z * 0.35)
        maxs = Vector(extents.x * 0.8, extents.y * 0.35, extents.z * 0.35)
        if DebugEnabled() then vrmod.logger.Debug("GetWeaponCollisionBox: Forward-aligned (x-axis) | Mins: %s, Maxs: %s", tostring(mins), tostring(maxs)) end
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

-- COLLISIONS
function vrmod.utils.ComputePhysicsParams(modelPath)
    if not modelPath or modelPath == "" then
        if DebugEnabled() then vrmod.logger.Warn("Invalid or empty model path, caching defaults") end
        vrmod.modelCache[modelPath] = {
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
                if DebugEnabled() then vrmod.logger.Debug("Replacing %s with valid worldmodel %s", modelPath, fallback) end
                modelPath = fallback
            else
                if DebugEnabled() then vrmod.logger.Debug("No valid fallback for %s, caching defaults", modelPath) end
                vrmod.modelCache[originalModelPath] = {
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
    if vrmod.modelCache[originalModelPath] and vrmod.modelCache[originalModelPath].computed then return end
    -- Retry protection
    pending[originalModelPath] = pending[originalModelPath] or {
        attempts = 0
    }

    if pending[originalModelPath].attempts >= 2 then
        if DebugEnabled() then vrmod.logger.Warn("Max retries (2) reached for %s, caching defaults", originalModelPath) end
        vrmod.modelCache[originalModelPath] = {
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
        vrmod.modelCache[originalModelPath] = {
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

        if DebugEnabled() then vrmod.logger.Info("Computed collision boxes for %s → reach: %.2f units, melee: %s", modelPath, reach, tostring(isMelee)) end
    else
        if DebugEnabled() then vrmod.logger.Warn("No valid physobj for %s, attempt %d", modelPath, pending[originalModelPath].attempts) end
    end

    ent:Remove()
    pending[originalModelPath].lastAttempt = CurTime()
    if pending[originalModelPath].attempts >= 2 then pending[originalModelPath] = nil end
end

function vrmod.utils.GetModelParams(modelPath, ply, offsetAng)
    if vrmod.modelCache[modelPath] and vrmod.modelCache[modelPath].computed then
        local cache = vrmod.modelCache[modelPath]
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
                    if DebugEnabled() then vrmod.logger.Info("GetModelParams: Sent computed params for %s to server", modelPath) end
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
                    if DebugEnabled() then vrmod.logger.Info("GetModelParams: Sent computed params for %s to clients", modelPath) end
                end

                -- mark as sent
                cache.sent = true
            end
        else
            if DebugEnabled() then vrmod.logger.Info("GetModelParams: Skipping sync for %s due to default parameters", modelPath) end
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
            if vrmod.modelCache[modelPath] and vrmod.modelCache[modelPath].computed then vrmod.utils.GetModelParams(modelPath, ply, offsetAng) end
        end)

        if DebugEnabled() then vrmod.logger.Debug("GetModelParams: Scheduled computation for %s", modelPath) end
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
    if SERVER and vrmod.modelCache[model] and vrmod.modelCache[model].computed then
        local c = vrmod.modelCache[model]
        if DebugEnabled() then vrmod.logger.Info("GetCachedWeaponParams: Using server-side synced params for %s", model) end
        return c.radius, c.reach, c.mins_horizontal, c.maxs_horizontal, c.angles, c.isMelee
    end

    if pending[model] and CurTime() - (pending[model].lastAttempt or 0) < 2 then
        if DebugEnabled() then vrmod.logger.Debug("GetCachedWeaponParams: Computation pending for %s, waiting", model) end
        return nil
    end

    if radius ~= vrmod.DEFAULT_RADIUS or reach ~= vrmod.DEFAULT_REACH or mins ~= vrmod.DEFAULT_MINS then return radius, reach, mins, maxs, angles, isMelee end
    if not pending[model] then
        if DebugEnabled() then
            vrmod.logger.Debug("GetCachedWeaponParams: Scheduling computation for %s", model)
            timer.Simple(0, function() vrmod.utils.ComputePhysicsParams(model) end)
        end
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
        -- Prefer last free sample; else use resolve result from the clip probe (no extra trace)
        if lastNonClippedPos[hand] then
            pushOutPos = lastNonClippedPos[hand]
        else
            pushOutPos = resolvedPos or (pos + (hitNormal or ZERO_UP))
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
        local moved = leftPos:DistToSqr(lastCheckedHandPos.left) > POS_TOLERANCE_SQR
            or math.abs(lefthandAng.pitch - lastCheckedHandAng.left.pitch) > ANG_TOLERANCE
            or math.abs(lefthandAng.yaw - lastCheckedHandAng.left.yaw) > ANG_TOLERANCE
        local shape
        if moved then
            shape = vrmod.utils.CheckWorldCollisions(leftPos, vrmod.DEFAULT_RADIUS, nil, nil, lefthandAng, "left", vrmod.DEFAULT_REACH, leftGrip)
            lastCheckedHandPos.left:Set(leftPos)
            lastCheckedHandAng.left:Set(lefthandAng)
        else
            shape = vrmod._lastGoodShapeLeft or handShapeStore.left
        end

        if shape and shape.isClipped and shape.pushOutPos then
            lefthandPos = shape.pushOutPos
            cachedPushOutPos.left = lefthandPos
            lastNonClippedNormal.left = shape.hitNormal
            vrmod._lastGoodShapeLeft = shape
        else
            vrmod._lastGoodShapeLeft = nil
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
        local moved = rightPos:DistToSqr(lastCheckedHandPos.right) > POS_TOLERANCE_SQR
            or math.abs(righthandAng.pitch - lastCheckedHandAng.right.pitch) > ANG_TOLERANCE
            or math.abs(righthandAng.yaw - lastCheckedHandAng.right.yaw) > ANG_TOLERANCE
        local shape
        if moved then
            shape = vrmod.utils.CheckWorldCollisions(rightPos, vrmod.DEFAULT_RADIUS, nil, nil, righthandAng, "right", vrmod.DEFAULT_REACH, rightGrip)
            lastCheckedHandPos.right:Set(rightPos)
            lastCheckedHandAng.right:Set(righthandAng)
        else
            shape = vrmod._lastGoodShapeRight or handShapeStore.right
        end

        if shape and shape.isClipped and shape.pushOutPos then
            righthandPos = shape.pushOutPos
            cachedPushOutPos.right = righthandPos
            lastNonClippedNormal.right = shape.hitNormal
            vrmod._lastGoodShapeRight = shape
        else
            vrmod._lastGoodShapeRight = nil
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