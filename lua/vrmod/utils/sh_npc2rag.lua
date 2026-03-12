g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}
local trackedRagdolls = trackedRagdolls or {}
local lastDamageTime = {}
-- NPC2RAG
-- Returns either a single mass (if physIndex provided) or a table of masses indexed by phys-index.
function vrmod.utils.GetBoneMass(ent, physIndex)
    if not IsValid(ent) then return nil end
    local physCount = 0
    -- Try to get a safe count; fallback to single physics object
    if ent.GetPhysicsObjectCount then physCount = ent:GetPhysicsObjectCount() or 0 end
    -- If there's no count but there's a physics object, treat it as one
    if physCount <= 0 then
        local p = ent:GetPhysicsObject()
        if not IsValid(p) then return nil end
        if physIndex == nil then
            return {
                [0] = p:GetMass()
            }
        else
            return physIndex == 0 and p:GetMass() or nil
        end
    end

    -- If a specific index requested, return that mass (or nil)
    if physIndex ~= nil then
        local p = ent:GetPhysicsObjectNum(physIndex)
        if IsValid(p) then return p:GetMass() end
        return nil
    end

    -- Otherwise return all masses as a table
    local masses = {}
    for i = 0, physCount - 1 do
        local p = ent:GetPhysicsObjectNum(i)
        if IsValid(p) then masses[i] = p:GetMass() end
    end
    return masses
end

-- Cache original masses on the entity (stored as ent.vrmod_original_masses).
-- If force==true it will overwrite an existing cache.
function vrmod.utils.CacheBoneMasses(ent, force)
    if not IsValid(ent) then return end
    if ent.vrmod_original_masses and not force then return end
    ent.vrmod_original_masses = vrmod.utils.GetBoneMass(ent) or {}
end

-- Restore cached masses. delay (seconds) optional.
-- Accepts same motion/damping/vel/angvel flags similar to your SetBoneMass logic.
function vrmod.utils.RestoreBoneMasses(ent, delay, damp, vel, angvel, resetmotion)
    if not IsValid(ent) then return end
    local original = ent.vrmod_original_masses
    if not original then return end
    local function doRestore()
        if not IsValid(ent) then return end
        for i, mass in pairs(original) do
            local phys = ent:GetPhysicsObjectNum(i)
            if not IsValid(phys) then
                -- fallback to primary phys if index 0 missing
                if i == 0 then phys = ent:GetPhysicsObject() end
            end

            if IsValid(phys) then
                if resetmotion then
                    phys:EnableMotion(false)
                else
                    phys:EnableMotion(true)
                end

                phys:SetMass(mass)
                if damp then phys:SetDamping(damp, damp) end
                if vel then phys:SetVelocity(vel) end
                if angvel then phys:AddAngleVelocity(VectorRand() * angvel) end
                phys:EnableGravity(true)
                phys:Wake()
            end
        end
    end

    if delay and delay > 0 then
        timer.Simple(delay, doRestore)
    else
        doRestore()
    end
end

-- Clear the cached mass table (call after restore if you want to free it)
function vrmod.utils.ClearCachedBoneMasses(ent)
    if not IsValid(ent) then return end
    ent.vrmod_original_masses = nil
end

-- Utility: Temporarily set damping, also clamp material to reduce bounce
function vrmod.utils.TempSetDamping(ent, highDamp, restoreDamp, delay)
    if not IsValid(ent) then return end
    if not delay then delay = 0.01 end
    for i = 0, ent:GetPhysicsObjectCount() - 1 do
        local phys = ent:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:SetDamping(highDamp, highDamp)
            -- prevent "bouncy" ragdolls
            phys:SetMaterial("default_silent") -- low restitution material
            phys:Wake()
        end
    end

    timer.Simple(delay, function()
        if not IsValid(ent) then return end
        for i = 0, ent:GetPhysicsObjectCount() - 1 do
            local phys = ent:GetPhysicsObjectNum(i)
            if IsValid(phys) then
                phys:SetDamping(restoreDamp, restoreDamp)
                phys:SetMaterial("flesh") -- typical ragdoll material
                phys:Wake()
            end
        end
    end)
end

function vrmod.utils.SetBoneMass(ent, mass, damp, vel, angvel, resetmotion, delay)
    if not IsValid(ent) or not IsValid(ent:GetPhysicsObject()) then return end
    if not delay then delay = 0 end
    timer.Simple(delay, function()
        for i = 0, ent:GetPhysicsObjectCount() - 1 do
            local phys = ent:GetPhysicsObjectNum(i)
            if not IsValid(phys) then continue end
            if resetmotion then
                phys:EnableMotion(false)
                phys:EnableMotion(true)
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
            -- Temporary high damping, no freeze
            vrmod.utils.TempSetDamping(rag, 25, 0.5, 0.01)
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
            vrmod.logger.Info("Ragdoll gibbed during runtime, removing")
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
    if not (hook.GetTable()["EntityTakeDamage"] or {})["VRMod_ForwardRagdollDamage"] then hook.Add("EntityTakeDamage", "VRMod_ForwardRagdollDamage", function(ent, dmginfo) vrmod.utils.ForwardRagdollDamage(ent, dmginfo) end) end
    timer.Create("VRMod_Cleanup_DeadRagdolls", 60, 0, function()
        for rag, npc in pairs(trackedRagdolls) do
            if not IsValid(rag) or not IsValid(npc) then trackedRagdolls[rag] = nil end
        end
    end)
end