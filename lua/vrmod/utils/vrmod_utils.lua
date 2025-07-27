g_VR = g_VR or {}
g_VR.enhanced = true
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}
if SERVER then
    function vrmod.utils.ForwardRagdollDamage(ent, dmginfo)
        if not (ent:IsRagdoll() and IsValid(ent.original_npc)) then return end
        local npc = ent.original_npc
        local dmg = dmginfo:GetDamage()
        npc:SetHealth(math.max(0, npc:Health() - dmg))
        local force = dmginfo:GetDamageForce() or Vector(0, 0, 0)
        if not force:IsZero() then
            local physCount = ent:GetPhysicsObjectCount()
            for i = 0, physCount - 1 do
                local phys = ent:GetPhysicsObjectNum(i)
                if IsValid(phys) then phys:ApplyForceCenter(force) end
            end
        end
    end

    function vrmod.utils.SpawnPickupRagdoll(npc)
        if not IsValid(npc) then return end
        -- 1) Create the ragdoll immediately
        local rag = ents.Create("prop_ragdoll")
        if not IsValid(rag) then return end
        rag:SetModel(npc:GetModel())
        rag:SetNWBool("is_npc_ragdoll", true)
        rag:SetPos(npc:GetPos())
        rag:SetAngles(npc:GetAngles())
        rag:Spawn()
        rag:Activate()
        -- 2) Copy bones in a next-tick timer
        timer.Simple(0, function()
            if not (IsValid(npc) and IsValid(rag)) then return end
            if npc.SetupBones then npc:SetupBones() end
            for i = 0, (npc.GetBoneCount and npc:GetBoneCount() or 0) - 1 do
                local pos, ang = npc:GetBonePosition(i)
                if pos and ang and rag.SetBonePosition then rag:SetBonePosition(i, pos, ang) end
            end

            for i = 0, (rag.GetPhysicsObjectCount and rag:GetPhysicsObjectCount() or 0) - 1 do
                local phys = rag:GetPhysicsObjectNum(i)
                if IsValid(phys) then
                    phys:EnableMotion(true)
                    phys:Wake()
                end
            end
        end)

        -- 3) Fully disable & hide the original NPC
        rag.original_npc = npc
        rag.dropped_manually = false
        hook.Add("EntityTakeDamage", "VRMod_ForwardRagdollDamage", vrmod.utils.ForwardRagdollDamage)
        npc:SetNoDraw(true)
        npc:SetNotSolid(true)
        npc:SetMoveType(MOVETYPE_NONE)
        npc:SetCollisionGroup(COLLISION_GROUP_VEHICLE)
        npc:ClearSchedule()
        if npc.StopMoving then npc:StopMoving() end
        -- **Silence AI & thinking completely**
        npc:AddEFlags(EFL_NO_THINK_FUNCTION) -- stops Think() calls
        if npc.SetNPCState then npc:SetNPCState(NPC_STATE_NONE) end
        npc:SetSaveValue("m_bInSchedule", false) -- stop any running schedule
        if npc.GetActiveWeapon and IsValid(npc:GetActiveWeapon()) then npc:GetActiveWeapon():Remove() end
        -- 4) On rag removal, restore or remove the NPC
        rag:CallOnRemove("vrmod_cleanup_npc_" .. rag:EntIndex(), function()
            if not IsValid(npc) then return end
            -- re-enable thinking
            npc:RemoveEFlags(EFL_NO_THINK_FUNCTION)
            if rag.dropped_manually then
                -- Restore NPC at rag’s last pose
                local p, a = rag:GetPos(), rag:GetAngles()
                npc:SetPos(p)
                npc:SetAngles(a)
                npc:SetNoDraw(false)
                npc:SetNotSolid(false)
                npc:SetMoveType(MOVETYPE_STEP)
                npc:SetCollisionGroup(COLLISION_GROUP_NONE)
                npc:ClearSchedule()
                npc:SetSaveValue("m_bInSchedule", false)
                if npc.SetNPCState then npc:SetNPCState(NPC_STATE_ALERT) end
                npc:DropToFloor()
                -- Restart thinking/AI
                if npc.BehaveStart then pcall(npc.BehaveStart, npc) end
                npc:SetSchedule(SCHED_IDLE_STAND)
                npc:NextThink(CurTime())
            else
                -- Rag was gibbed: kill the NPC too
                npc:Remove()
            end

            hook.Remove("EntityTakeDamage", "VRMod_ForwardRagdollDamage")
        end)
        return rag
    end

    function vrmod.utils.IsRagdollGibbed(ent)
        -- 0) Missing or invalid entity → treat as gibbed
        if not IsValid(ent) then return true end
        -- 0) Zero HP is gibbed too
        local npc = ent.original_npc
        if IsValid(npc) and npc:Health() <= 0 then return true end
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
end