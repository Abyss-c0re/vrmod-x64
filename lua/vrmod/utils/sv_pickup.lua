g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}
local function DebugEnabled()
    local cv = GetConVar("vrmod_debug_pickup")
    return cv and cv:GetBool() or false
end

function vrmod.utils.PatchOwnerCollision(ent, ply)
    if not IsValid(ent) or not IsValid(ply) then return end
    if ent._collisionPatched then return end
    -- Mark ownership
    ent._pickupOwner = ply
    -- Add nocollide constraint
    local nc = constraint.NoCollide(ent, ply, 0, 0)
    ent._nocollideConstraint = nc
    ent._collisionPatched = true
    if DebugEnabled() then vrmod.logger.Debug("Added nocollide constraint between", ent, "and", ply) end
end

function vrmod.utils.UnpatchOwnerCollision(ent)
    if not IsValid(ent) or not ent._collisionPatched then return end
    local ply = ent._pickupOwner
    ent._pickupOwner = nil
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end
    -- Temporarily disable collisions between player and prop
    if IsValid(ply) then
        ent:SetCustomCollisionCheck(true)
        ply:SetCustomCollisionCheck(true)
        phys:EnableCollisions(false)
    end

    -- Remove nocollide constraint after a short delay
    if IsValid(ent._nocollideConstraint) then
        timer.Simple(0.01, function()
            if IsValid(ent._nocollideConstraint) then
                ent._nocollideConstraint:Remove()
                ent._nocollideConstraint = nil
            end

            -- Re-enable collisions
            if IsValid(phys) then phys:EnableCollisions(true) end
            if IsValid(ply) then
                ent:SetCustomCollisionCheck(false)
                ply:SetCustomCollisionCheck(false)
            end
        end)
    end

    ent._collisionPatched = nil
    if DebugEnabled() then vrmod.logger.Debug("Unpatched collision for", ent) end
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