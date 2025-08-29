g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}
local cl_effectmodel = CreateClientConVar("vrmod_melee_fist_collisionmodel", "models/props_junk/PopCan01a.mdl", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
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

vrmod.modelCache = {}
vrmod.collisionSpheres = {}
vrmod.collisionBoxes = {}
local pending = {}
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

local function DebugEnabled()
    local cv = GetConVar("vrmod_debug_physics")
    return cv and cv:GetBool() or false
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
        if DebugEnabled() then vrmod.logger.Info("No valid physobj for %s, attempt %d", modelPath, pending[originalModelPath].attempts) end
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

function vrmod.utils.CollisionsPreCheck(leftPos, rightPos)
    local ply = LocalPlayer()
    if not IsValid(ply) or not g_VR.active or not ply:GetNWBool("vrmod_server_enforce_collision", true) or ply:GetMoveType() == MOVETYPE_NOCLIP or not ply:Alive() or not vrmod.IsPlayerInVR(ply) or ply:InVehicle() then
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
        if DebugEnabled() then if isClipped then vrmod.logger.Debug("Box collision for:", hand, "Pos:", pos, "Angles:", ang, "Mins:", shapeMins, "Maxs:", shapeMaxs, "Hit:", isClipped) end end
    else
        if not radius then radius = vrmod.DEFAULT_RADIUS end
        isClipped, hitNormal = SphereCollidesWithWorld(pos, radius)
        if DebugEnabled() then if isClipped then vrmod.logger.Debug("Sphere collision for:", hand, "Pos:", pos, "Radius:", radius, "Hit:", isClipped) end end
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
        vrmod.collisionBoxes = {}
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
    if not isnumber(reach) then reach = math.max(math.abs(maxs.x), math.abs(maxs.y), math.abs(maxs.z)) * 2 end
    local adjustedPos = vrmod.utils.AdjustCollisionsBox(pos, ang, isMelee)
    local shape = vrmod.utils.CheckWorldCollisions(adjustedPos, nil, mins, maxs, ang, "right", reach)
    vrmod.collisionBoxes = {} -- Reset vrmod.collisionBoxes
    if shape then
        vrmod.collisionBoxes[1] = shape -- Update vrmod.collisionBoxes with the weapon shape
    end

    if shape and shape.isClipped and shape.pushOutPos and type(shape.pushOutPos) == "Vector" then
        local normal = shape.hitNormal
        local plyPos = g_VR.tracking.hmd.pos or Vector()
        local distanceSqr = (shape.pushOutPos - plyPos):LengthSqr()
        if distanceSqr > 500 then
            vrmod.collisionBoxes = {} -- Clear vrmod.collisionBoxes on reset
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

        if DebugEnabled() then vrmod.logger.Debug("Weapon clipping detected. Push-out pos:", correctedPos, "angle:", correctedAng) end
        return correctedPos, correctedAng
    end
    return pos, ang
end

function vrmod.utils.UpdateHandCollisions(lefthandPos, lefthandAng, righthandPos, righthandAng)
    -- Early out if no collision broad-phase
    if not vrmod._collisionNearby then
        if next(vrmod.collisionSpheres) or next(vrmod.collisionBoxes) then
            vrmod.collisionSpheres = {}
            vrmod.collisionBoxes = {}
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
    if not vrmod.utils.IsValidWep(wep) then vrmod.collisionBoxes = {} end
    -- Calculate offset positions for collision queries (absolute space)
    local leftPos = lefthandPos + lefthandAng:Forward() * vrmod.DEFAULT_OFFSET
    local rightPos = righthandPos + righthandAng:Forward() * vrmod.DEFAULT_OFFSET
    -- Reset containers for this update
    vrmod.collisionSpheres = {}
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
            vrmod.collisionSpheres[#vrmod.collisionSpheres + 1] = shape
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

                        if DebugEnabled() then vrmod.logger.Debug("Clipping detected for:", hand, "Push-out pos:", corrected) end
                    end
                else
                    lastNonClippedPos[hand] = nil
                    lastNonClippedNormal[hand] = nil
                    cachedPushOutPos[hand] = nil
                    shape.isClipped = false
                    if DebugEnabled() then vrmod.logger.Debug("Invalid pushOutPos or player for:", hand) end
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
    -- ========== UNPATCH ==========
    if ent._collisionPatched then
        -- Restore ShouldCollide
        if ent._originalShouldCollide then
            ent.ShouldCollide = ent._originalShouldCollide
            ent._originalShouldCollide = nil
        end

        -- Remove nocollide constraint
        if IsValid(ent._nocollideConstraint) then
            ent._nocollideConstraint:Remove()
            ent._nocollideConstraint = nil
            if DebugEnabled() then vrmod.logger.Debug("Removed nocollide constraint for", ent) end
        end

        -- Cleanup bookkeeping
        ent._pickupOwner = nil
        ent:SetCustomCollisionCheck(false)
        hook.Remove("ShouldCollide", ent)
        ent._collisionPatched = nil
        if DebugEnabled() then vrmod.logger.Debug("Unpatched collision for", ent) end
        return
    end

    -- ========== PATCH ==========
    ent._pickupOwner = ply
    ent._originalShouldCollide = ent.ShouldCollide
    local nc = constraint.NoCollide(ent, ply, 0, 0)
    ent._nocollideConstraint = nc
    if DebugEnabled() then vrmod.logger.Debug("Added nocollide constraint between", ent, "and", ply) end
    ent:SetCustomCollisionCheck(true)
    if DebugEnabled() then vrmod.logger.Debug("Patched collision for", ent, "owned by", ply) end
    function ent:ShouldCollide(other)
        if other == self._pickupOwner then
            if DebugEnabled() then vrmod.logger.Debug("(Entity) Blocked collision with owner:", self, other) end
            return false
        end

        if IsValid(other) and other:GetNWBool("isVRHand", false) then
            if DebugEnabled() then vrmod.logger.Debug("(Entity) Allowed collision with VRHand:", self, other) end
            return true
        end

        if self._originalShouldCollide then return self._originalShouldCollide(self, other) end
        return true
    end

    hook.Add("ShouldCollide", ent, function(a, b)
        if not IsValid(ent._pickupOwner) then return end
        local owner = ent._pickupOwner
        if a == ent and b == owner or b == ent and a == owner then
            if DebugEnabled() then vrmod.logger.Debug("(Global) Blocked ent ↔ owner collision:", a, b) end
            return false
        end

        if IsValid(a) and a:GetNWBool("isVRHand", false) or IsValid(b) and b:GetNWBool("isVRHand", false) then
            if DebugEnabled() then vrmod.logger.Debug("(Global) Allowed collision with VRHand:", a, b) end
            return true
        end
    end)

    ent._collisionPatched = true
end