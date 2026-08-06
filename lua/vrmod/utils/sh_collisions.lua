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

--- True if brush-climb addon is enabled (convar may be absent when addon disabled).
local function BrushClimbEnabled()
    local cv = GetConVar("vrmod_brushclimb_enable")
    return cv and cv:GetBool() or false
end

--- Climb grab intent from live VR input (mirrors vrmod_climbing bind modes).
--- 0=grip+trigger, 1=grip, 2=trigger. Used so wall push does not move hands
--- while the player is trying to grab (before IsHolding becomes true).
local function ClimbGrabIntentFromInput(handKey)
    if not BrushClimbEnabled() then return false end
    if not g_VR or not g_VR.input then return false end
    local inp = g_VR.input
    local modeCv = GetConVar("vrmod_brushclimb_bind_mode")
    local mode = modeCv and modeCv:GetInt() or 0

    local grip, trigger
    if handKey == "left" then
        grip = inp.boolean_left_pickup
        trigger = inp.boolean_reload or inp.boolean_left_primaryfire or inp.boolean_left_secondaryfire
        if not trigger then
            local a = inp.vector1_left_primaryfire
            if isnumber(a) and a > 0.6 then trigger = true end
        end
    else
        grip = inp.boolean_right_pickup
        trigger = inp.boolean_primaryfire or inp.boolean_secondaryfire
        if not trigger then
            local a = inp.vector1_primaryfire
            if isnumber(a) and a > 0.6 then trigger = true end
        end
    end
    grip = grip and true or false
    trigger = trigger and true or false
    if mode == 1 then return grip end
    if mode == 2 then return trigger end
    return grip and trigger
end

--- Floor/ceiling hits must not lock hands — they yank grabs to the floor and fight climb.
local function IsFloorOrCeilingNormal(n)
    if vrmod.utils.IsFloorOrCeilingNormal then
        return vrmod.utils.IsFloorOrCeilingNormal(n, 0.55)
    end
    if not n or n.z == nil then return false end
    return math.abs(n.z) > 0.55
end

--- Per-hand: climb is holding OR player is actively grab-binding this hand.
--- When true, wall push must not rewrite tracking (climb + grab height stay real).
function vrmod.utils.GetClimbingGripState()
    local left, right = false, false
    local climb = vrmod and vrmod.climbing
    if climb then
        if isfunction(climb.IsHoldingLeft) then left = climb.IsHoldingLeft() and true or false end
        if isfunction(climb.IsHoldingRight) then right = climb.IsHoldingRight() and true or false end
    end
    -- Pre-grab frames: IsHolding is still false but buttons are down — wall push
    -- was sliding the sample down walls/floors so grabs attached near the floor.
    if not left and ClimbGrabIntentFromInput("left") then left = true end
    if not right and ClimbGrabIntentFromInput("right") then right = true end
    return left, right
end

--- True when seated in stock vehicle, Glide, or VR vehicle state.
local function IsSeatedInVehicle(ply)
	if not IsValid(ply) then return false end
	if ply:InVehicle() then return true end
	-- Glide often leaves InVehicle() false while seated
	if ply.GlideGetVehicle then
		local ok, veh = pcall(function() return ply:GlideGetVehicle() end)
		if ok and IsValid(veh) then return true end
	end
	if CLIENT and g_VR and g_VR.vehicle then
		if g_VR.vehicle.inside or g_VR.vehicle.driving then return true end
		if g_VR.vehicle.glide and IsValid(g_VR.vehicle.current) then return true end
	end
	return false
end

--- True when hand/head wall push must not run (vehicle, mag hold, wheel grip).
local function ShouldSkipHandWall(ply)
	if not IsValid(ply) then return true end
	if IsSeatedInVehicle(ply) then return true end
	-- Steering wheel grip — wall push fights bone-follow / wheel pose
	if g_VR and (g_VR.wheelGripped or g_VR.wheelGrippedLeft or g_VR.wheelGrippedRight) then
		return true
	end
	-- Held mag/clip: wall push fights reload (hand + mag near gun/cabin)
	if CLIENT and g_VR then
		local L, R = g_VR.heldEntityLeft, g_VR.heldEntityRight
		if IsValid(L) and vrmod.utils.IsMagazine and vrmod.utils.IsMagazine(L) then return true end
		if IsValid(R) and vrmod.utils.IsMagazine and vrmod.utils.IsMagazine(R) then return true end
	end
	return false
end

local PRECHECK_MOVE_SQR = PRECHECK_MOVE_THRESHOLD * PRECHECK_MOVE_THRESHOLD
local POS_TOLERANCE_SQR = POS_TOLERANCE * POS_TOLERANCE

function vrmod.utils.CollisionsPreCheck(leftPos, rightPos)
    local ply = LocalPlayer()
    if not IsValid(ply) or not g_VR.active or not ply:GetNWBool("vrmod_server_enforce_collision", true) or ply:GetMoveType() == MOVETYPE_NOCLIP or not ply:Alive() or not vrmod.IsPlayerInVR(ply) or ShouldSkipHandWall(ply) then
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

local HAND_MASK = MASK_SOLID_BRUSHONLY
local DEPEN_DIRS = {
	Vector(1, 0, 0), Vector(-1, 0, 0),
	Vector(0, 1, 0), Vector(0, -1, 0),
	Vector(0, 0, 1), Vector(0, 0, -1),
}

--- Multi-direction depenetrate when buried in brush (force-push recovery).
local function DepenetrateFromSolid(pos, radius, pad, filter, preferredNormal)
	local mins, maxs = SetSymmetricHull(radius)
	local n = preferredNormal
	if not IsVec(n) or n:LengthSqr() < 0.01 then n = ZERO_UP end
	local push = Vector(pos)
	for _ = 1, 12 do
		local t2 = util.TraceHull({
			start = push,
			endpos = push + n * math.max(radius * 2.5, 4),
			mins = mins,
			maxs = maxs,
			mask = HAND_MASK,
			filter = filter
		})
		if not t2.StartSolid and not t2.AllSolid then
			if t2.Hit then
				return WallRestPos(t2.HitPos, t2.HitNormal, pad, push), true,
					(IsVec(t2.HitNormal) and t2.HitNormal) or n
			end
			return (IsVec(t2.EndPos) and t2.EndPos) or push, true, n
		end
		if IsVec(t2.HitNormal) and t2.HitNormal:LengthSqr() > 0.01 then
			n = t2.HitNormal
		end
		push = push + n * math.max(radius * 1.25, 2)
	end
	local best, bestN, bestDist
	for i = 1, #DEPEN_DIRS do
		local dir = DEPEN_DIRS[i]
		local t3 = util.TraceHull({
			start = pos,
			endpos = pos + dir * (radius * 8 + 16),
			mins = mins,
			maxs = maxs,
			mask = HAND_MASK,
			filter = filter
		})
		if not t3.StartSolid and not t3.AllSolid then
			local endp = t3.Hit and WallRestPos(t3.HitPos, t3.HitNormal, pad, pos)
				or (IsVec(t3.EndPos) and t3.EndPos or pos)
			local d = pos:DistToSqr(endp)
			if not best or d < bestDist then
				best, bestDist = endp, d
				bestN = (IsVec(t3.HitNormal) and t3.HitNormal) or dir
			end
		end
	end
	if best then return best, true, bestN end
	return pos + n * (radius + pad + 4), true, n
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
            -- Strong multi-dir depenetrate (force-push recovery for gun hull)
            safe, _, normal = DepenetrateFromSolid(desired, math.max(radius, 3), pad, filter, normal)
            if not IsVec(safe) then safe = desired end
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
        or ShouldSkipHandWall(ply)
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

-- If lastFree is farther than this from desired AND desired is free, re-acquire.
-- When desired is still solid we KEEP lastFree (dropping it was the force-through bug).
local MAX_LASTFREE_DIST_SQR = 48 * 48
-- Cap extreme tethers; still full block at wall (never partial-scale into solid).
local MAX_HAND_CORRECTION = 40
-- Ignore micro-corrections (steering / hull noise) to stop hand flicker
local MIN_HAND_CORRECTION_SQR = 0.35 * 0.35

--- Hull-sweep from last free sample → desired sample (climbing-style).
--- Never returns a position still inside solid when a free sample is known.
local function ResolveHandWallSweep(desiredSample, handKey, radius, filter)
	if not IsVec(desiredSample) then
		return Vector(), false, nil
	end

	local mins, maxs = SetSymmetricHull(radius)
	local pad = GetWallPushPad()
	local st = handWall[handKey]
	if not st then
		return desiredSample, false, nil
	end
	if not IsVec(st.lastFree) then
		st.lastFree = Vector()
		st.hasFree = false
	end

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

	local desiredFree = isFree(desiredSample)

	-- Drop stale free anchors only when desired is free (re-acquire) or lastFree invalid.
	-- If desired is solid, KEEP lastFree even when far — that stops force-through.
	if st.hasFree and IsVec(st.lastFree) then
		if not isFree(st.lastFree) then
			st.hasFree = false
		elseif desiredFree and st.lastFree:DistToSqr(desiredSample) > MAX_LASTFREE_DIST_SQR then
			st.hasFree = false
		end
	end

	if desiredFree and not st.hasFree then
		return desiredSample, false, nil
	end

	local startPos = desiredSample
	if st.hasFree and IsVec(st.lastFree) and isFree(st.lastFree) then
		startPos = st.lastFree
	else
		st.hasFree = false
	end

	-- Desired free, continuous lastFree: clear path → unlock
	if desiredFree and st.hasFree and startPos == st.lastFree then
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

	if tr.StartSolid or tr.AllSolid then
		if st.hasFree and IsVec(st.lastFree) and isFree(st.lastFree) then
			local n = tr.HitNormal
			if not IsVec(n) or n:LengthSqr() < 0.01 then n = ZERO_UP end
			return Vector(st.lastFree), true, n
		end
		local n = tr.HitNormal
		if not IsVec(n) or n:LengthSqr() < 0.01 then n = ZERO_UP end
		return DepenetrateFromSolid(desiredSample, radius, pad, filter, n)
	end

	if tr.Hit then
		local n = tr.HitNormal
		if not IsVec(n) or n:LengthSqr() < 0.01 then
			n = ZERO_UP
		end
		-- Floors/ceilings: allow free vertical motion (climb/grab), but only if
		-- the rest position is not still inside a wall brush.
		if IsFloorOrCeilingNormal(n) then
			if desiredFree then
				return desiredSample, false, nil
			end
			-- Desired still solid (e.g. pressed into floor+wall joint) → depenetrate
			return DepenetrateFromSolid(desiredSample, radius, pad, filter, n)
		end
		local restPad = math.max(0.15, pad)
		local rest = WallRestPos(tr.HitPos, n, restPad, startPos)
		-- Guarantee rest is free; if not, fall back to lastFree / depenetrate
		if not isFree(rest) then
			if st.hasFree and IsVec(st.lastFree) and isFree(st.lastFree) then
				return Vector(st.lastFree), true, n
			end
			return DepenetrateFromSolid(desiredSample, radius, pad, filter, n)
		end
		return rest, true, n
	end

	-- No hit but desired solid (degenerate hull / thin wall): still block
	if not desiredFree then
		if st.hasFree and IsVec(st.lastFree) and isFree(st.lastFree) then
			return Vector(st.lastFree), true, ZERO_UP
		end
		return DepenetrateFromSolid(desiredSample, radius, pad, filter, ZERO_UP)
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
    if not handWall[handKey] then return end
    handWall[handKey].hasFree = false
    lastNonClippedPos[handKey] = nil
    lastNonClippedNormal[handKey] = nil
    cachedPushOutPos[handKey] = nil
end

--- Drop free-sample anchors so climb grab does not inherit a wall-push tether.
function vrmod.utils.ClearHandWallCollision(hand)
    if hand == "both" or hand == "all" or hand == true then
        ClearHandWallState("left")
        ClearHandWallState("right")
        vrmod._lastGoodShapeLeft = nil
        vrmod._lastGoodShapeRight = nil
        return
    end
    if hand == "left" or hand == 1 then
        ClearHandWallState("left")
        vrmod._lastGoodShapeLeft = nil
    elseif hand == "right" or hand == 2 then
        ClearHandWallState("right")
        vrmod._lastGoodShapeRight = nil
    end
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
        or ShouldSkipHandWall(ply)
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
    -- Per-hand wheel grip (steering) — same skip as climb grip
    if g_VR then
        if g_VR.wheelGrippedLeft then leftGrip = true end
        if g_VR.wheelGrippedRight then rightGrip = true end
        if g_VR.wheelGripped then leftGrip, rightGrip = true, true end
    end
    -- Modest hull: oversized radius caused StartSolid flicker near props / dashboards
    local radius = math.max(vrmod.DEFAULT_RADIUS or 2.2, 2.35)
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

        -- Floor/ceiling "walls" yank hands to the ground (climb then grabs near floor).
        -- Only treat vertical-ish surfaces as hand walls.
        if clipped and IsFloorOrCeilingNormal(normal) then
            clipped = false
            safeSample = desiredSample
            normal = nil
            ClearHandWallState(handKey)
        end

        -- Only reject strong downward pulls when the hit is floor-like — never cancel
        -- a vertical wall block (that allowed force-push through walls).
        if clipped and IsVec(safeSample) and IsVec(desiredSample) and IsFloorOrCeilingNormal(normal) then
            local drop = desiredSample.z - safeSample.z
            if drop > 8 then
                clipped = false
                safeSample = desiredSample
                normal = nil
                ClearHandWallState(handKey)
            end
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

        if clipped then
            local delta = safeSample - desiredSample
            local dlenSqr = delta:LengthSqr()
            -- Dead-zone: hull noise / steering micro-hits must not jitter the hand
            if dlenSqr >= MIN_HAND_CORRECTION_SQR then
                local dlen = math.sqrt(dlenSqr)
                if dlen > MAX_HAND_CORRECTION then
                    delta = delta * (MAX_HAND_CORRECTION / dlen)
                end
                trackPos = AddPosInPlace(trackPos, delta)
            end
            cachedPushOutPos[handKey] = safeSample
            lastNonClippedNormal[handKey] = normal
            -- CRITICAL: do NOT write wall rest into lastFree — that caused
            -- StartSolid oscillation (flicker) next frame. Keep pre-contact free sample.
            local st = handWall[handKey]
            if st and not st.hasFree and IsVec(safeSample) then
                -- Only seed if we had nothing (first contact after teleport)
                if not IsVec(st.lastFree) then st.lastFree = Vector() end
                st.lastFree:Set(safeSample)
                st.hasFree = true
            end
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

------------------------------------------------------------------------
-- HMD / head wall collision — playspace origin shift (climbing-style)
------------------------------------------------------------------------
local cv_head_coll = CreateClientConVar("vrmod_head_collision", "1", true, FCVAR_ARCHIVE,
	"Block HMD/head from pushing through world brushes (shifts playspace)", 0, 1)
local cv_head_radius = CreateClientConVar("vrmod_head_collision_radius", "6", true, FCVAR_ARCHIVE,
	"Head collision hull radius (units)", 3, 14)

local hmdWall = {
	lastFree = Vector(),
	hasFree = false,
}

local function ShiftPlayspaceWorld(delta)
	if not IsVec(delta) or delta:LengthSqr() < 0.0001 then return end
	if g_VR.origin and g_VR.origin.Add then
		g_VR.origin:Add(delta)
	elseif g_VR.origin then
		g_VR.origin = g_VR.origin + delta
	end
	-- Tracking is already world-space this frame — keep SoT coherent with new origin
	local function shiftTable(t)
		if not t then return end
		for _, pose in pairs(t) do
			if pose and IsVec(pose.pos) then
				if pose.pos.Add then
					pose.pos:Add(delta)
				else
					pose.pos = pose.pos + delta
				end
			end
		end
	end
	shiftTable(g_VR.tracking)
	-- Do NOT shift rawTracking (device energy) — next frame rebuilds from origin
end

--- Block head through walls by sliding the room origin (camera + hands stay outside).
function vrmod.utils.UpdateHeadCollisions()
	if not cv_head_coll:GetBool() then return end
	local ply = LocalPlayer()
	local hmd = g_VR.tracking and g_VR.tracking.hmd
	if not IsValid(ply) or not g_VR.active or not hmd or not IsVec(hmd.pos) then return end
	local cvCol = GetConVar("vrmod_collisions")
	local colOn = (not cvCol or cvCol:GetBool()) and ply:GetNWBool("vrmod_server_enforce_collision", true)
	-- Never shift playspace while driving / Glide / wheel — fights steering & seats
	if not colOn
		or ply:GetMoveType() == MOVETYPE_NOCLIP
		or not ply:Alive()
		or not vrmod.IsPlayerInVR(ply)
		or ShouldSkipHandWall(ply)
	then
		hmdWall.hasFree = false
		return
	end

	local desired = hmd.pos
	-- Slightly smaller default than before — less false StartSolid near low ceilings
	local radius = math.Clamp(cv_head_radius:GetFloat(), 3, 14)
	if radius > 8 then radius = 8 end
	local pad = math.max(0.75, GetWallPushPad() * 0.75)
	local mins, maxs = SetSymmetricHull(radius)
	local filter = WallFilter(ply)

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

	if hmdWall.hasFree and IsVec(hmdWall.lastFree) then
		if not isFree(hmdWall.lastFree) or hmdWall.lastFree:DistToSqr(desired) > (120 * 120) then
			hmdWall.hasFree = false
		end
	end

	local desiredFree = isFree(desired)
	if desiredFree and not hmdWall.hasFree then
		hmdWall.lastFree:Set(desired)
		hmdWall.hasFree = true
		return
	end

	local startPos = desired
	if hmdWall.hasFree and IsVec(hmdWall.lastFree) and isFree(hmdWall.lastFree) then
		startPos = hmdWall.lastFree
	end

	if desiredFree and hmdWall.hasFree then
		local clear = util.TraceHull({
			start = startPos,
			endpos = desired,
			mins = mins,
			maxs = maxs,
			mask = HAND_MASK,
			filter = filter
		})
		if not clear.Hit and not clear.StartSolid and not clear.AllSolid then
			hmdWall.lastFree:Set(desired)
			hmdWall.hasFree = true
			return
		end
	end

	local tr = util.TraceHull({
		start = startPos,
		endpos = desired,
		mins = mins,
		maxs = maxs,
		mask = HAND_MASK,
		filter = filter
	})

	local safe = desired
	local blocked = false

	if tr.StartSolid or tr.AllSolid then
		blocked = true
		if hmdWall.hasFree and IsVec(hmdWall.lastFree) and isFree(hmdWall.lastFree) then
			safe = Vector(hmdWall.lastFree)
		else
			local n = (IsVec(tr.HitNormal) and tr.HitNormal:LengthSqr() > 0.01) and tr.HitNormal or ZERO_UP
			safe = DepenetrateFromSolid(desired, radius, pad, filter, n)
			if not IsVec(safe) then safe = desired + n * (radius + pad) end
		end
	elseif tr.Hit then
		blocked = true
		local n = (IsVec(tr.HitNormal) and tr.HitNormal:LengthSqr() > 0.01) and tr.HitNormal or ZERO_UP
		safe = WallRestPos(tr.HitPos, n, pad, startPos)
		if not isFree(safe) then
			if hmdWall.hasFree and isFree(hmdWall.lastFree) then
				safe = Vector(hmdWall.lastFree)
			else
				safe = DepenetrateFromSolid(desired, radius, pad, filter, n)
			end
		end
	elseif not desiredFree then
		blocked = true
		if hmdWall.hasFree and isFree(hmdWall.lastFree) then
			safe = Vector(hmdWall.lastFree)
		else
			safe = DepenetrateFromSolid(desired, radius, pad, filter, ZERO_UP)
		end
	end

	if not blocked or not IsVec(safe) then
		if desiredFree then
			hmdWall.lastFree:Set(desired)
			hmdWall.hasFree = true
		end
		return
	end

	local delta = safe - desired
	local dlenSqr = delta:LengthSqr()
	-- Dead-zone: tiny origin shoves caused whole-body hand flicker with steering
	if dlenSqr < (0.6 * 0.6) then
		if hmdWall.hasFree then return end
		hmdWall.lastFree:Set(desired)
		hmdWall.hasFree = true
		return
	end
	local dlen = math.sqrt(dlenSqr)
	if dlen > 48 then
		if hmdWall.hasFree and IsVec(hmdWall.lastFree) then
			delta = hmdWall.lastFree - desired
			dlen = delta:Length()
		else
			delta = delta * (48 / dlen)
		end
	end
	-- Dampen multi-frame chatter (0.55 = not full shove every frame)
	delta = delta * 0.55
	ShiftPlayspaceWorld(delta)
	-- Keep last free as pre-block sample when we have one; else seed from safe
	if not hmdWall.hasFree then
		hmdWall.lastFree:Set(safe)
		hmdWall.hasFree = true
	end
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