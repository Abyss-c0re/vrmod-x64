g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}
local pickupList = pickupList or {}
local pickupCount = pickupCount or 0
local pickupController
local _, convarValues = vrmod.GetConvars()
local blacklistedClasses = {
    ["npc_turret_floor"] = true,
    ["info_particle_system"] = true,
    ["item_healthcharger"] = true,
    ["item_suitcharger"] = true,
    ["item_ammo_crate"] = true,
}

local blacklistedPatterns = {"beam", "button", "dynamic", "func_", "c_base", "laser", "info_", "sprite", "env_", "fire", "trail", "light", "spotlight", "streetlight", "traffic", "texture", "shadow", "keypad"}
local pickupableCache = {}
local invalidPickupCache = {}
local function DebugEnabled()
    local cv = GetConVar("vrmod_debug_pickup")
    return cv and cv:GetBool() or false
end

--=======================================================================
-- Validation and Eligibility
--=======================================================================
function vrmod.utils.IsImportantPickup(ent)
    local class = ent:GetClass()
    return class:find("^item_") or class:find("^spawned_") or class:find("^vr_item") or vrmod.utils.IsWeaponEntity(ent)
end

function vrmod.utils.HasHeldWeaponRight(ply)
    return vrmod.utils.IsValidWep(ply:GetActiveWeapon())
end

function vrmod.utils.IsNonPickupable(ent)
    if not IsValid(ent) then
        vrmod.logger.Debug("IsNonPickupable: Entity is invalid")
        return true
    end

    local class = ent:GetClass():lower()
    local model = (ent:GetModel() or ""):lower()
    local key = class .. "|" .. model
    if pickupableCache[key] ~= nil then
        vrmod.logger.Debug("IsNonPickupable: Cache hit for " .. key .. " -> " .. tostring(pickupableCache[key]))
        return pickupableCache[key]
    end

    -- Class blacklist (exact match)
    if blacklistedClasses[class] then
        vrmod.logger.Debug("IsNonPickupable: Class is blacklisted -> " .. class)
        pickupableCache[key] = true
        return true
    end

    -- Pattern blacklists
    for _, pattern in ipairs(blacklistedPatterns) do
        pattern = pattern:lower()
        if class:find(pattern, 1, true) or model:find(pattern, 1, true) then
            vrmod.logger.Debug("IsNonPickupable: Class or model matches blacklist pattern '" .. pattern .. "' -> " .. class .. ", " .. model)
            pickupableCache[key] = true
            return true
        end
    end

    -- Weapon or important item overrides
    if vrmod.utils.IsWeaponEntity(ent) or class:find("prop_") or vrmod.utils.IsImportantPickup(ent) then
        vrmod.logger.Debug("IsNonPickupable: Entity is a weapon, prop, or important pickup -> " .. class)
        pickupableCache[key] = false
        return false
    end

    local npcPickupAllowed = (convarValues and convarValues.vrmod_pickup_npcs or 0) >= 1
    if npcPickupAllowed and (ent:IsNPC() or ent:IsNextBot()) then
        vrmod.logger.Debug("IsNonPickupable: NPC pickup allowed, entity is NPC/NextBot -> " .. class)
        pickupableCache[key] = false
        return false
    end

    -- Physics check
    if ent:GetMoveType() ~= MOVETYPE_VPHYSICS then
        vrmod.logger.Debug("IsNonPickupable: Non-physics entity -> " .. class .. " | MoveType: " .. tostring(ent:GetMoveType()))
        pickupableCache[key] = true
        return true
    end

    pickupableCache[key] = false
    return false
end

function vrmod.utils.IsValidPickupTarget(ent, ply, bLeftHand)
    if not IsValid(ent) then
        if not invalidPickupCache[ent] then
            vrmod.logger.Debug("IsValidPickupTarget: Entity invalid")
            invalidPickupCache[ent] = false
        end
        return false
    end

    if invalidPickupCache[ent] ~= nil then
        return invalidPickupCache[ent] -- Return cached result without logging
    end

    if ent:GetNoDraw() then
        vrmod.logger.Debug("IsValidPickupTarget: Entity has NoDraw -> " .. ent:GetClass())
        invalidPickupCache[ent] = false
        return false
    end

    if ent:IsDormant() then
        vrmod.logger.Debug("IsValidPickupTarget: Entity is dormant -> " .. ent:GetClass())
        invalidPickupCache[ent] = false
        return false
    end

    if vrmod.utils.IsNonPickupable(ent) then
        vrmod.logger.Debug("IsValidPickupTarget: Entity is non-pickupable -> " .. ent:GetClass())
        invalidPickupCache[ent] = false
        return false
    end

    if ent:GetNWBool("is_npc_ragdoll", false) then
        vrmod.logger.Debug("IsValidPickupTarget: Entity is NPC ragdoll -> " .. ent:GetClass())
        invalidPickupCache[ent] = false
        return false
    end

    if bLeftHand and ent == g_VR.heldEntityLeft then
        vrmod.logger.Debug("IsValidPickupTarget: Already held in left hand -> " .. ent:GetClass())
        invalidPickupCache[ent] = false
        return false
    end

    if not bLeftHand and ent == g_VR.heldEntityRight then
        vrmod.logger.Debug("IsValidPickupTarget: Already held in right hand -> " .. ent:GetClass())
        invalidPickupCache[ent] = false
        return false
    end

    if ent:IsWeapon() and ent:GetOwner() == ply then
        vrmod.logger.Debug("IsValidPickupTarget: Weapon already owned by player -> " .. ent:GetClass())
        invalidPickupCache[ent] = false
        return false
    end

    vrmod.logger.Debug("IsValidPickupTarget: Valid pickup -> " .. ent:GetClass())
    invalidPickupCache[ent] = true
    return true
end

function vrmod.utils.IsIgnoredProp(ent)
    if not IsValid(ent) then return true end
    local class = ent:GetClass() or ""
    if class == "prop_ragdoll" then return true end
    if vrmod.utils.IsImportantPickup(ent) then return true end
    if string.StartWith(class, "avrmag_") then return true end
    return false
end

function vrmod.utils.CanPickupEntity(v, ply, cv)
    if not IsValid(v) or v == ply or ply:InVehicle() then return false end
    if cv.vrmod_pickup_npcs == 1 then if v:IsNPC() or v:IsNextBot() then return true end end
    -- Only do physics mass check server-side
    if SERVER then
        local phys = v:GetPhysicsObject()
        if not IsValid(phys) then return false end
        if cv.vrmod_pickup_limit == 1 then return v:GetMoveType() == MOVETYPE_VPHYSICS and phys:GetMass() <= cv.vrmod_pickup_weight end
    end
    return true
end

function vrmod.utils.ValidatePickup(ply, bLeftHand, ent)
    local sid = ply:SteamID()
    if not IsValid(ply) then
        vrmod.logger.Debug("ValidatePickup: Invalid player")
        return false
    end

    if not IsValid(ent) then
        vrmod.logger.Debug("ValidatePickup: Invalid entity")
        return false
    end

    if g_VR[sid] and g_VR[sid].heldItems and g_VR[sid].heldItems[bLeftHand and 1 or 2] then
        vrmod.logger.Debug("ValidatePickup: Player already holding an item")
        return false
    end

    if not vrmod.utils.CanPickupEntity(ent, ply, convarValues) then
        vrmod.logger.Debug("ValidatePickup: vrmod.utils.CanPickupEntity returned false")
        return false
    end

    if hook.Call("VRMod_Pickup", nil, ply, ent) == false then
        vrmod.logger.Debug("ValidatePickup: Blocked by VRMod_Pickup hook")
        return false
    end
    return true
end

function vrmod.utils.FindPickupTarget(ply, bLeftHand, handPos, handAng, pickupRange)
    if type(pickupRange) ~= "number" or pickupRange <= 0 then pickupRange = 1.2 end
    local ent
    local offsetPos = handPos + handAng:Forward() * vrmod.DEFAULT_OFFSET
    -- Sphere search first
    local sphereEnt, _ = vrmod.utils.SphereCollidesWithProp(offsetPos, 5, ply)
    if IsValid(sphereEnt) and sphereEnt ~= ply and vrmod.utils.IsValidPickupTarget(sphereEnt, ply, bLeftHand) and vrmod.utils.CanPickupEntity(sphereEnt, ply, convarValues or vrmod.GetConvars()) then ent = sphereEnt end
    -- Fallback to trace if sphere failed validation
    if not IsValid(ent) then
        local hand = bLeftHand and "left" or "right"
        local tr = vrmod.utils.TraceHand(ply, hand, true)
        if tr and IsValid(tr.Entity) then
            local e = tr.Entity
            if e ~= ply and vrmod.utils.IsValidPickupTarget(e, ply, bLeftHand) and vrmod.utils.CanPickupEntity(e, ply, convarValues or vrmod.GetConvars()) then ent = e end
        end
    end

    if not IsValid(ent) then return nil end
    -- Range check with boost
    local boost = 1.0
    if vrmod.utils.IsImportantPickup(ent) then
        boost = 5.0
    else
        if ent:IsNPC() then boost = 3.0 end
    end

    local maxDist = pickupRange * 10 * boost
    if (ent:GetPos() - handPos):LengthSqr() > maxDist ^ 2 then return nil end
    -- Weapon-specific rules
    if vrmod.utils.IsWeaponEntity(ent) then
        local aw = ply:GetActiveWeapon()
        if IsValid(aw) and aw:GetClass() == ent:GetClass() then return nil end
        if not bLeftHand and vrmod.utils.IsValidWep(ply:GetActiveWeapon()) then return nil end
    end
    return ent
end

-- Find a pickup entry by steamid and hand boolean. Returns index and info or nil.
function vrmod.utils.FindPickupBySteamIDAndHand(steamid, bLeft)
    for i = 1, pickupCount do
        local t = pickupList[i]
        if t and t.steamid == steamid and t.left == bLeft then return i, t end
    end
    return nil, nil
end

-- Internal helper: finalizes removal of a pickup entry (clears g_VR, removes from list, updates pickupCount, stops controller if empty)
function vrmod.utils._FinalizePickupRemoval(index, info)
    if not index or not info then return end
    -- clear held item reference
    if g_VR[info.steamid] and g_VR[info.steamid].heldItems then g_VR[info.steamid].heldItems[info.left and 1 or 2] = nil end
    -- remove entry and update counter
    table.remove(pickupList, index)
    pickupCount = math.max(0, pickupCount - 1)
    -- mark entity as not picked
    if IsValid(info.ent) then info.ent.picked = false end
    -- stop and remove controller if nobody else is holding
    if pickupCount == 0 and IsValid(pickupController) then
        vrmod.logger.Debug("FinalizePickupRemoval: stopping and removing pickupController")
        pickupController:StopMotionController()
        pickupController:Remove()
        pickupController = nil
    end
end

-- Releases a pickup entry (detaches phys from controller, handles NPC ragdoll specifics, network notifications, and hooks)
-- Accepts either the info table or index+info; returns true on success.
function vrmod.utils.ReleasePickupEntry(index, info, handVel)
    if not info then return false end
    handVel = handVel or Vector(0, 0, 0)
    vrmod.logger.Debug(string.format("ReleasePickupEntry: index=%s ent=%s steamid=%s left=%s", tostring(index), tostring(info.ent), tostring(info.steamid), tostring(info.left)))
    local ent = info.ent
    -- remove physics object from controller if present
    if IsValid(pickupController) and IsValid(info.phys) then
        vrmod.logger.Debug("ReleasePickupEntry: removing phys from motion controller")
        pickupController:RemoveFromMotionController(info.phys)
    end

    -- NPC ragdoll special handling
    if IsValid(ent) and ent.original_npc then
        local npc = ent.original_npc
        vrmod.logger.Debug("ReleasePickupEntry: handling npc ragdoll - npc=" .. tostring(npc))
        if IsValid(npc) and not vrmod.utils.IsRagdollDead(ent) then
            -- manually dropped alive NPC: mark and inflate bone mass briefly
            ent.dropped_manually = true
            ent.noDamage = true
            vrmod.logger.Debug("ReleasePickupEntry: inflating bone mass for ragdoll")
            vrmod.utils.SetBoneMass(ent, 300, 0, handVel, 5)
            -- notify clients using existing utility
            vrmod.utils.SendPickupNetMessage(info.ply, npc, nil)
            -- remove ragdoll shortly (user expectation / original behaviour)
            timer.Simple(3.0, function() if IsValid(ent) then ent:Remove() end end)
        else
            -- dead or invalid original NPC: restore to prop behaviour
            ent.dropped_manually = false
            if IsValid(ent) then
                ent:SetNWBool("is_npc_ragdoll", false)
                ent:SetCollisionGroup(COLLISION_GROUP_NONE)
            end

            vrmod.utils.SendPickupNetMessage(info.ply, ent, nil)
        end
    elseif IsValid(ent) then
        if GetConVar("vrmod_pickup_no_phys"):GetBool() then ent:SetCollisionGroup(COLLISION_GROUP_NONE) end
        -- Normal entity drop path
        local phys = IsValid(info.phys) and info.phys or IsValid(ent) and ent:GetPhysicsObject() or nil
        if IsValid(phys) and IsValid(pickupController) then
            vrmod.logger.Debug("ReleasePickupEntry: removing physics object from controller (normal ent)")
            pickupController:RemoveFromMotionController(phys)
        end

        -- network notify
        vrmod.utils.SendPickupNetMessage(info.ply, ent, nil)
    else
        -- entity is invalid / already removed
        vrmod.utils.SendPickupNetMessage(info.ply, nil, nil)
    end

    -- unpatch owner collision for non-ragdoll
    if IsValid(ent) and ent:GetClass() ~= "prop_ragdoll" and not GetConVar("vrmod_pickup_no_phys"):GetBool() then vrmod.utils.UnpatchOwnerCollision(ent) end
    -- call hook
    hook.Call("VRMod_Drop", nil, info.ply, ent)
    -- finalize removal from lists and controller cleanup
    vrmod.utils._FinalizePickupRemoval(index, info)
    return true
end

--=======================================================================
-- NPC Handling / Ragdoll Conversion
--=======================================================================
function vrmod.utils.HandleNPCRagdoll(ply, ent)
    if ent:IsNPC() then
        vrmod.logger.Debug("HandleNPCRagdoll: Spawning pickup ragdoll for NPC: " .. tostring(ent))
        ent = vrmod.utils.SpawnPickupRagdoll(ply, ent)
    end
    return ent
end

--=======================================================================
-- Hand Transform Retrieval
--=======================================================================
function vrmod.utils.GetHandTransform(ply, bLeftHand)
    local handPos, handAng
    if bLeftHand then
        handPos = vrmod.GetLeftHandPos(ply)
        handAng = vrmod.GetLeftHandAng(ply)
    else
        handPos = vrmod.GetRightHandPos(ply)
        handAng = vrmod.GetRightHandAng(ply)
    end

    vrmod.logger.Debug(string.format("GetHandTransform: %s hand pos=%s ang=%s", bLeftHand and "Left" or "Right", tostring(handPos), tostring(handAng)))
    return handPos, handAng
end

--=======================================================================
-- Ragdoll Bone Offsets
--=======================================================================
function vrmod.utils.BuildRagdollOffsets(ent, handPos, handAng)
    local physOffsets = {}
    for i = 0, ent:GetPhysicsObjectCount() - 1 do
        local phys = ent:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            local physPos, physAng = phys:GetPos(), phys:GetAngles()
            local lpos, lang = WorldToLocal(physPos, physAng, handPos, handAng)
            physOffsets[i] = {
                localPos = lpos,
                localAng = lang
            }

            vrmod.logger.Debug("BuildRagdollOffsets: Index=" .. i .. " localPos=" .. tostring(lpos) .. " localAng=" .. tostring(lang))
        end
    end

    vrmod.logger.Debug("BuildRagdollOffsets: Completed for entity " .. tostring(ent))
    return physOffsets
end

--=======================================================================
-- Pickup Controller Initialization
--=======================================================================
function vrmod.utils.InitPickupController()
    if IsValid(pickupController) then return pickupController end
    vrmod.logger.Debug("InitPickupController: Creating new pickup motion controller")
    pickupController = ents.Create("vrmod_pickup")
    pickupController.ShadowParams = {
        secondstoarrive = engine.TickInterval(),
        maxangular = 5000,
        maxangulardamp = 5000,
        maxspeed = 2000000,
        maxspeeddamp = 20000,
        dampfactor = 0.3,
        teleportdistance = 2000,
        deltatime = 0,
    }

    function pickupController:PhysicsSimulate(phys, dt)
        local ent = phys:GetEntity()
        local info = ent.vrmod_pickup_info
        if not info then return end
        local ply = info.ply
        if not IsValid(ply) then return end
        local handPos, handAng
        if info.left then
            handPos = vrmod.GetLeftHandPos(ply)
            handAng = vrmod.GetLeftHandAng(ply)
        else
            handPos = vrmod.GetRightHandPos(ply)
            handAng = vrmod.GetRightHandAng(ply)
        end

        if not handPos or not handAng then return end
        local targetPos, targetAng
        if ent:GetClass() == "prop_ragdoll" and ent.vrmod_physOffsets then
            for i = 0, ent:GetPhysicsObjectCount() - 1 do
                if ent:GetPhysicsObjectNum(i) == phys then
                    local offset = ent.vrmod_physOffsets[i]
                    if offset then targetPos, targetAng = LocalToWorld(offset.localPos, offset.localAng, handPos, handAng) end
                    break
                end
            end
        else
            targetPos, targetAng = LocalToWorld(info.localPos, info.localAng, handPos, handAng)
        end

        if not targetPos then return end
        self.ShadowParams.pos = targetPos
        self.ShadowParams.angle = targetAng
        phys:ComputeShadowControl(self.ShadowParams)
    end

    pickupController:StartMotionController()
    return pickupController
end

--=======================================================================
-- Pickup Registration
--=======================================================================
function vrmod.utils.CreatePickupInfo(ply, bLeftHand, ent, handPos, handAng)
    local sid = ply:SteamID()
    local index = pickupCount + 1
    for k, v in ipairs(pickupList) do
        if v.ent == ent then
            index = k
            g_VR[v.steamid].heldItems[v.left and 1 or 2] = nil
            break
        end
    end

    if index > pickupCount then
        pickupCount = pickupCount + 1
        if ent:GetClass() == "prop_ragdoll" then
            vrmod.utils.CacheBoneMasses(ent)
            vrmod.utils.SetBoneMass(ent, 35, 0.5)
        end
    end

    local didSnap = vrmod.utils.SnapEntityToHand(ent, handPos, handAng)
    local lpos, lang
    if ent:GetClass() ~= "prop_ragdoll" then
        lpos, lang = WorldToLocal(ent:GetPos(), ent:GetAngles(), handPos, handAng)
    else
        lpos, lang = Vector(0, 0, 0), Angle(0, 0, 0)
    end

    local info = {
        ent = ent,
        phys = ent:GetPhysicsObject(),
        left = bLeftHand,
        localPos = lpos,
        localAng = lang,
        collisionGroup = ent:GetCollisionGroup(),
        steamid = sid,
        ply = ply,
        snapped = didSnap
    }

    pickupList[index] = info
    g_VR[sid].heldItems = g_VR[sid].heldItems or {}
    g_VR[sid].heldItems[bLeftHand and 1 or 2] = info
    ent.vrmod_pickup_info = info
    vrmod.logger.Debug("CreatePickupInfo: Registered pickup entry " .. index .. " for " .. tostring(ent))
    return info
end

--=======================================================================
-- Physics Controller Attachment
--=======================================================================
function vrmod.utils.AttachPhysicsToController(info, controller)
    if not info or not IsValid(info.ent) or not IsValid(controller) then return end
    local phys = info.phys or info.ent:GetPhysicsObject()
    if IsValid(phys) then
        controller:AddToMotionController(phys)
        phys:Wake()
        vrmod.logger.Debug("AttachPhysicsToController: Added phys for " .. tostring(info.ent))
    end
end

--=======================================================================
-- Networking
--=======================================================================
function vrmod.utils.SendPickupNetMessage(ply, ent, bLeftHand)
    net.Start("vrmod_pickup")
    net.WriteEntity(ply)
    net.WriteEntity(ent)
    net.WriteBool(false)
    net.WriteBool(bLeftHand)
    net.Broadcast()
    vrmod.logger.Debug("SendPickupNetMessage: Sent for " .. tostring(ply) .. " -> " .. tostring(ent))
end

if SERVER then
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
            if ent2:GetNWBool("isVRHand", false) then return false end
        end

        -- Case 2: ent2 is a patched prop
        if ent2._collisionPatched then
            if ent1 == ent2._pickupOwner then return false end
            if ent1:GetNWBool("isVRHand", false) then return false end
        end
    end)

    -- Apply "owner safe" state + reduced pushback + floaty fix
    function vrmod.utils.PatchOwnerCollision(ent, ply)
        if not IsValid(ent) or not IsValid(ply) then return end
        if ent._collisionPatched then return end
        ent._pickupOwner = ply
        ent._collisionPatched = true
        if DebugEnabled() then vrmod.logger.Debug("Patched collisions for", ent, "(owner:", ply, ") mass/damping adjusted for floaty fix + pushback reduction") end
    end

    -- Restore normal collision behavior + physics
    function vrmod.utils.UnpatchOwnerCollision(ent)
        if not IsValid(ent) or not ent._collisionPatched then return end
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
            local entitySize = (maxs - mins):Length()
            local tolerance = entitySize * 0.5
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
        local safeDistance = entityRadius or DEFAULT_OFFSET
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
end