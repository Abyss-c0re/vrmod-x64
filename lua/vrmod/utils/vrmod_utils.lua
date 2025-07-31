g_VR = g_VR or {}
g_VR.viewModelInfo = g_VR.viewModelInfo or {}
g_VR.enhanced = true
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}
local cl_effectmodel = CreateClientConVar("vrmod_melee_fist_collisionmodel", "models/props_junk/PopCan01a.mdl", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local cv_meleeDebug = CreateConVar("vrmod_melee_debug", "0", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Enable detailed melee debug logging (0 = off, 1 = on)")
local magCache = {}
local modelCache = {}
local pending = {}
local DEFAULT_RADIUS = 5
local DEFAULT_REACH = 6.6
local DEFAULT_MINS = Vector(-0.75, -0.75, -1.25)
local DEFAULT_MAXS = Vector(0.75, 0.75, 11)
local DEFAULT_ANGLES = Angle(0, 0, 0)
-- HELPERS
local function DebugPrint(fmt, ...)
    if cv_meleeDebug:GetBool() then print(string.format("[VRMod:][%s] " .. fmt, CLIENT and "Client" or "Server", ...)) end
end

local function IsMagazine(ent)
    local class = ent:GetClass()
    if magCache[class] ~= nil then return magCache[class] end
    local isMag = string.StartWith(class, "avrmag_")
    magCache[class] = isMag
    return isMag
end

local function ApplyBoxFromRadius(radius, isVertical)
    local forward = radius
    local side = radius * 0.15
    local mins, maxs
    if isVertical then
        mins = Vector(-side, -side, -forward * 0.25)
        maxs = Vector(side, side, forward * 2.3)
        DebugPrint("ApplyBoxFromRadius: radius %.2f | Vertical-aligned (z-axis) | Mins: %s, Maxs: %s", radius, tostring(mins), tostring(maxs))
    else
        mins = Vector(-forward * 0.35, -side, -side)
        maxs = Vector(forward * 2.3, side, side)
        DebugPrint("ApplyBoxFromRadius: radius %.2f | Forward-aligned (x-axis) | Mins: %s, Maxs: %s", radius, tostring(mins), tostring(maxs))
    end
    return mins, maxs, isVertical
end

-- WEP UTILS
function vrmod.utils.IsValidWep(wep, get)
    if not IsValid(wep) then return false end
    local class = wep:GetClass()
    local vm = wep:GetWeaponViewModel()
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

-- MELEE UTILS
function vrmod.utils.ComputePhysicsRadius(modelPath)
    if not modelPath or modelPath == "" then
        DebugPrint("Invalid or empty model path, caching defaults")
        modelCache[modelPath] = {
            radius = DEFAULT_RADIUS,
            reach = DEFAULT_REACH,
            mins = DEFAULT_MINS,
            maxs = DEFAULT_MAXS,
            angles = DEFAULT_ANGLES,
            isVertical = false,
            computed = true
        }
        return
    end

    local originalModelPath = modelPath
    -- Fallback for known bad viewmodels (c_models)
    if modelPath:lower():match("^models/weapons/c_") then
        local baseName = modelPath:match("models/weapons/c_(.-)%.mdl")
        if baseName then
            local fallback = "models/weapons/w_" .. baseName .. ".mdl"
            if file.Exists(fallback, "GAME") then
                DebugPrint("Replacing %s with valid worldmodel %s", modelPath, fallback)
                modelPath = fallback
            else
                DebugPrint("No valid fallback for %s (attempted %s), using defaults", modelPath, fallback)
                modelCache[originalModelPath] = {
                    radius = DEFAULT_RADIUS,
                    reach = DEFAULT_REACH,
                    mins = DEFAULT_MINS,
                    maxs = DEFAULT_MAXS,
                    angles = DEFAULT_ANGLES,
                    isVertical = false,
                    computed = true
                }
                return
            end
        end
    end

    -- Already computed?
    if modelCache[originalModelPath] and modelCache[originalModelPath].computed then return end
    -- Retry protection
    if pending[originalModelPath] and pending[originalModelPath].attempts >= 3 then
        DebugPrint("Max retries reached for %s, caching defaults", originalModelPath)
        modelCache[originalModelPath] = {
            radius = DEFAULT_RADIUS,
            reach = DEFAULT_REACH,
            mins = DEFAULT_MINS,
            maxs = DEFAULT_MAXS,
            angles = DEFAULT_ANGLES,
            isVertical = false,
            computed = true
        }

        pending[originalModelPath] = nil
        return
    end

    pending[originalModelPath] = pending[originalModelPath] or {
        attempts = 0
    }

    pending[originalModelPath].attempts = pending[originalModelPath].attempts + 1
    util.PrecacheModel(modelPath)
    local ent = CLIENT and ents.CreateClientProp(modelPath) or ents.Create("prop_physics")
    if not IsValid(ent) then
        DebugPrint("Failed to spawn %s (attempt %d)", modelPath, pending[originalModelPath].attempts)
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
        local amin, amax = phys:GetAABB()
        if amin:Length() > 0 and amax:Length() > 0 then
            local radius = (amax - amin):Length() * 0.5
            local reach = math.Clamp(radius, 6.6, 50)
            local isVertical = false
            local mins, maxs = ApplyBoxFromRadius(radius, isVertical)
            modelCache[originalModelPath] = {
                radius = radius,
                reach = reach,
                mins = mins or DEFAULT_MINS,
                maxs = maxs or DEFAULT_MAXS,
                angles = DEFAULT_ANGLES,
                isVertical = isVertical,
                computed = true
            }

            DebugPrint("Computed radius for %s (actual: %s) → %.2f units", originalModelPath, modelPath, radius)
        else
            DebugPrint("Invalid AABB for %s, attempt %d", modelPath, pending[originalModelPath].attempts)
        end
    else
        DebugPrint("No valid physobj for %s, attempt %d", modelPath, pending[originalModelPath].attempts)
    end

    timer.Simple(0, function() if IsValid(ent) then ent:Remove() end end)
    pending[originalModelPath].lastAttempt = CurTime()
end

function vrmod.utils.GetModelRadius(modelPath, ply, offsetAng)
    local ang = vrmod.GetRightHandAng(ply)
    -- Check for significant offset in any direction (pitch, yaw, or roll)
    local isVertical = offsetAng and (math.abs(math.NormalizeAngle(offsetAng.x)) > 45 or math.abs(
        -- Pitch
        math.NormalizeAngle(offsetAng.y)) > 45 or math.abs(
        -- Yaw
        math.NormalizeAngle(offsetAng.z)) > 45) or false

    -- Roll
    DebugPrint("GetModelRadius: offsetAng=%s, isVertical=%s (pitch=%.2f, yaw=%.2f, roll=%.2f)", tostring(offsetAng), tostring(isVertical), offsetAng and math.abs(math.NormalizeAngle(offsetAng.x)) or 0, offsetAng and math.abs(math.NormalizeAngle(offsetAng.y)) or 0, offsetAng and math.abs(math.NormalizeAngle(offsetAng.z)) or 0)
    if modelCache[modelPath] and modelCache[modelPath].computed then
        local cache = modelCache[modelPath]
        DebugPrint("GetModelRadius: Cache found for %s, cached isVertical=%s", modelPath, tostring(cache.isVertical))
        if isVertical ~= cache.isVertical then
            DebugPrint("GetModelRadius: Alignment mismatch (isVertical=%s, cache.isVertical=%s), recalculating mins/maxs", tostring(isVertical), tostring(cache.isVertical))
            local mins, maxs = ApplyBoxFromRadius(cache.radius, isVertical)
            return cache.radius, cache.reach, mins, maxs, ang
        end
        return cache.radius, cache.reach, cache.mins, cache.maxs, ang
    end

    DebugPrint("GetModelRadius: No cache for %s, scheduling computation", modelPath)
    if not pending[modelPath] or pending[modelPath] and CurTime() - (pending[modelPath].lastAttempt or 0) > 1 then
        pending[modelPath] = {
            attempts = 0
        }

        timer.Simple(0, function() vrmod.utils.ComputePhysicsRadius(modelPath) end)
    end
    return DEFAULT_RADIUS, DEFAULT_REACH, DEFAULT_MINS, DEFAULT_MAXS, ang
end

function vrmod.utils.GetWeaponMeleeParams(wep, ply, hand)
    local model = cl_effectmodel:GetString()
    local offsetAng = DEFAULT_ANGLES
    if hand == "right" then
        local class, vm = vrmod.utils.WepInfo(wep)
        if not class or not vm then return vrmod.utils.GetModelRadius(model, ply, offsetAng) end
        model = vm
        if CLIENT then
            local vmInfo = g_VR.viewModelInfo[class]
            offsetAng = vmInfo and vmInfo.offsetAng or DEFAULT_ANGLES
        end
        return vrmod.utils.GetModelRadius(model, ply, offsetAng)
    else
        return vrmod.utils.GetModelRadius(model, ply, offsetAng)
    end
end

function vrmod.utils.HitFilter(ent, ply, hand)
    if not IsValid(ent) then return false end
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

if SERVER then
    -- NPC2RAG
    local trackedRagdolls = trackedRagdolls or {}
    local lastDamageTime = {}
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

    -- Add hook once
    if not hook.GetTable()["EntityTakeDamage"]["VRMod_ForwardRagdollDamage"] then hook.Add("EntityTakeDamage", "VRMod_ForwardRagdollDamage", function(ent, dmginfo) vrmod.utils.ForwardRagdollDamage(ent, dmginfo) end) end
    function vrmod.utils.SpawnPickupRagdoll(npc)
        if not IsValid(npc) then return end
        local rag = ents.Create("prop_ragdoll")
        if not IsValid(rag) then return end
        rag:SetModel(npc:GetModel())
        rag:SetPos(npc:GetPos())
        rag:SetAngles(npc:GetAngles())
        rag:SetNWBool("is_npc_ragdoll", true)
        rag:Spawn()
        rag:Activate()
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

    timer.Create("VRMod_Cleanup_DeadRagdolls", 60, 0, function()
        for rag, npc in pairs(trackedRagdolls) do
            if not IsValid(rag) or not IsValid(npc) then trackedRagdolls[rag] = nil end
        end
    end)
end