g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}
local function DebugEnabled()
    local cv = GetConVar("vrmod_debug_pickup")
    return cv and cv:GetBool() or false
end

-- Damage filter: prevent self-harm from own prop
hook.Add("EntityTakeDamage", "VRMod_PreventOwnerSelfDamage", function(target, dmg)
    local inflictor = dmg:GetInflictor()
    if IsValid(inflictor) and inflictor._pickupOwner == target then
        return true -- block damage from owned prop
    end
end)

-- Collision filter: ignore only owner + their VR hands
hook.Add("ShouldCollide", "VRMod_IgnoreOwnerAndHandCollisions", function(ent1, ent2)
    if not (IsValid(ent1) and IsValid(ent2)) then return end
    -- Case 1: ent1 is a patched prop
    if ent1._collisionPatched then
        if ent2 == ent1._pickupOwner then return false end
        if ent2:GetNWBool("isVRHand", false) and ent2:GetOwner() == ent1._pickupOwner then return false end
    end

    -- Case 2: ent2 is a patched prop
    if ent2._collisionPatched then
        if ent1 == ent2._pickupOwner then return false end
        if ent1:GetNWBool("isVRHand", false) and ent1:GetOwner() == ent2._pickupOwner then return false end
    end
end)

-- Apply "owner safe" state + reduced pushback + floaty fix
function vrmod.utils.PatchOwnerCollision(ent, ply)
    if not IsValid(ent) or not IsValid(ply) then return end
    if ent._collisionPatched then return end
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        -- Save original physics settings
        ent._oldMass = phys:GetMass()
        ent._oldDampingLinear, ent._oldDampingAngular = phys:GetDamping()
        local mass = ent._oldMass or 10
        -- Clamp minimum mass so light props aren't floaty
        local newMass = math.max(mass, 20)
        -- Scale damping: lighter objects get less damping so they're responsive
        local newLinearDamp, newAngularDamp
        if newMass <= 30 then
            newLinearDamp, newAngularDamp = 1, 1 -- light props: low damping
        elseif newMass <= 80 then
            newLinearDamp, newAngularDamp = 5, 5 -- medium props
        else
            newLinearDamp, newAngularDamp = 10, 10 -- heavy props
        end

        -- Reduce pushback by lowering effective mass while held
        phys:SetMass(math.max(1, newMass * 0.5))
        phys:SetDamping(newLinearDamp, newAngularDamp)
    end

    ent._pickupOwner = ply
    ent._collisionPatched = true
    if DebugEnabled() then vrmod.logger.Debug("Patched collisions for", ent, "(owner:", ply, ") mass/damping adjusted for floaty fix + pushback reduction") end
end

-- Restore normal collision behavior + physics
function vrmod.utils.UnpatchOwnerCollision(ent)
    if not IsValid(ent) or not ent._collisionPatched then return end
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        -- Restore original mass/damping if saved
        if ent._oldMass then
            phys:SetMass(ent._oldMass)
            ent._oldMass = nil
        end

        if ent._oldDampingLinear and ent._oldDampingAngular then
            phys:SetDamping(ent._oldDampingLinear, ent._oldDampingAngular)
            ent._oldDampingLinear, ent._oldDampingAngular = nil, nil
        end
    end

    ent._pickupOwner = nil
    ent._collisionPatched = nil
    if DebugEnabled() then vrmod.logger.Debug("Unpatched collisions + restored physics for", ent) end
end

function vrmod.utils.SnapEntityToHand(ent, handPos, handAng)
    if not IsValid(ent) then return false end
    -- safe defaults for DEFAULT_OFFSET
    local DEFAULT_OFFSET = vrmod and vrmod.DEFAULT_OFFSET or 5
    -- Collision bounds -> compute entity radius/tolerance (mirror client)
    local mins, maxs = ent:GetCollisionBounds()
    if mins and maxs then
        local entitySize = (maxs - mins):Length() * 0.5
        local tolerance = entitySize * 1.2
        local distSqr = handPos:DistToSqr(ent:GetPos())
        if distSqr < tolerance * tolerance then
            -- Too close → do not snap; keep entity where it is
            return false
        end
    end

    local forward = handAng:Forward()
    local finalPos = handPos + forward
    local toEntity = finalPos - handPos
    local dist = toEntity:Length()
    local entityRadius = 0
    if mins and maxs then entityRadius = (maxs - mins):Length() * 0.2 end
    local safeDistance = math.max(entityRadius, DEFAULT_OFFSET) * 1.2
    if dist < safeDistance then
        if dist == 0 then
            toEntity = forward
            dist = 1
        end

        finalPos = handPos + toEntity:GetNormalized() * safeDistance
    end

    -- Ragdoll: set each physics object to its stored per-phys offset (if present),
    -- but use finalPos as the anchor instead of handPos so the whole ragdoll sits in front.
    if ent:GetClass() == "prop_ragdoll" and ent.vrmod_physOffsets then
        for i = 0, ent:GetPhysicsObjectCount() - 1 do
            local phys = ent:GetPhysicsObjectNum(i)
            if IsValid(phys) and ent.vrmod_physOffsets[i] then
                local offset = ent.vrmod_physOffsets[i]
                local targetPos, targetAng = LocalToWorld(offset.localPos, offset.localAng, finalPos, handAng)
                phys:Wake()
                phys:SetPos(targetPos)
                phys:SetAngles(targetAng)
                phys:SetVelocity(Vector(0, 0, 0))
                phys:SetAngleVelocity(Vector(0, 0, 0))
            end
        end

        -- also move the entity root to match phys positions so ent:GetPos() matches clients
        ent:SetPos(finalPos)
        ent:SetAngles(handAng) -- keep a sensible orientation; you can change to ent:GetAngles() if you prefer
        if ent.InvalidateBoneCache then ent:InvalidateBoneCache() end
        if ent.SetupBones then ent:SetupBones() end
        return true
    end

    -- Non-ragdolls: move root physics object and entity to finalPos (do not place at hand origin)
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:SetPos(finalPos)
        -- keep entity orientation stable — preserve current angles instead of forcing handAng
        phys:SetAngles(ent:GetAngles())
        phys:SetVelocity(Vector(0, 0, 0))
        phys:SetAngleVelocity(Vector(0, 0, 0))
        ent:SetPos(finalPos)
        ent:SetAngles(ent:GetAngles())
    else
        -- fallback: set entity transform directly
        ent:SetPos(finalPos)
        -- keep original orientation
        ent:SetAngles(ent:GetAngles())
    end

    if ent.InvalidateBoneCache then ent:InvalidateBoneCache() end
    if ent.SetupBones then ent:SetupBones() end
    return true
end