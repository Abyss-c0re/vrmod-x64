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
if SERVER then util.AddNetworkString("vrmod_pickuplists_reload") end
local function DebugEnabled()
    local cv = GetConVar("vrmod_debug_pickup")
    return cv and cv:GetBool() or false
end

vrmod.pickupLists = vrmod.pickupLists or {
    whitelist = {},
    blacklist = {}
}

local listPath = "vrmod/pickup_lists.json"
local function LoadPickupLists()
    if CLIENT then
        if not file.Exists("vrmod/pickup_lists.json", "DATA") then return end
        local data = util.JSONToTable(file.Read("vrmod/pickup_lists.json", "DATA") or "")
        if istable(data) then
            vrmod.pickupLists.whitelist = data.whitelist or {}
            vrmod.pickupLists.blacklist = data.blacklist or {}
        end

        pickupableCache = {}
        print("[VRMod] Pickup lists hot-reloaded (client)")
    end
end

local function SavePickupLists()
    file.Write(listPath, util.TableToJSON(vrmod.pickupLists, true))
end

local function IsReAgdollHiddenNPC(ent)
    if not IsValid(ent) then return false end
    return ent.ReAgdoll_HiddenNPC == true or ent:GetNWBool("ReAgdoll_HiddenNPC", false) == true
end

vrmod.LoadPickupLists = LoadPickupLists
vrmod.SavePickupLists = SavePickupLists
if CLIENT then net.Receive("vrmod_pickuplists_reload", function() vrmod.LoadPickupLists() end) end
hook.Add("Initialize", "VRMod_LoadPickupLists", LoadPickupLists)
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
    if vrmod.pickupLists then
        if vrmod.pickupLists.whitelist[key] then return false end
        if vrmod.pickupLists.blacklist[key] then return true end
    end

    if pickupableCache[key] ~= nil then
        vrmod.logger.Debug("IsNonPickupable: Cache hit for " .. key .. " -> " .. tostring(pickupableCache[key]))
        return pickupableCache[key]
    end

    -- Weapon or important item overrides (allow all prop_*, weapons, important pickups FIRST,
    -- so that prop_dynamic, prop_physics, etc. are not killed by the "dynamic" pattern below)
    if vrmod.utils.IsWeaponEntity(ent) or class:find("prop_") or vrmod.utils.IsImportantPickup(ent) then
        vrmod.logger.Debug("IsNonPickupable: Entity is a weapon, prop, or important pickup -> " .. class)
        pickupableCache[key] = false
        return false
    end

    -- Class blacklist (exact match)
    if blacklistedClasses[class] then
        vrmod.logger.Debug("IsNonPickupable: Class is blacklisted -> " .. class)
        pickupableCache[key] = true
        return true
    end

    -- Pattern blacklists (now safe: won't catch prop_dynamic etc. because of the override above)
    for _, pattern in ipairs(blacklistedPatterns) do
        pattern = pattern:lower()
        if class:find(pattern, 1, true) or model:find(pattern, 1, true) then
            vrmod.logger.Debug("IsNonPickupable: Class or model matches blacklist pattern '" .. pattern .. "' -> " .. class .. ", " .. model)
            pickupableCache[key] = true
            return true
        end
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

    -- Weapons change owner and NoDraw when dropped. A sticky cache kept the
    -- in-hand result and the grip never found the same gun on the ground.
    local cacheable = not ent:IsWeapon()
    if cacheable and invalidPickupCache[ent] ~= nil then
        return invalidPickupCache[ent]
    end

    if ent:GetNoDraw() then
        vrmod.logger.Debug("IsValidPickupTarget: Entity has NoDraw -> " .. ent:GetClass())
        if cacheable then invalidPickupCache[ent] = false end
        return false
    end

    if ent:IsDormant() then
        vrmod.logger.Debug("IsValidPickupTarget: Entity is dormant -> " .. ent:GetClass())
        if cacheable then invalidPickupCache[ent] = false end
        return false
    end

    if vrmod.utils.IsNonPickupable(ent) then
        vrmod.logger.Debug("IsValidPickupTarget: Entity is non-pickupable -> " .. ent:GetClass())
        if cacheable then invalidPickupCache[ent] = false end
        return false
    end

    if ent:GetNWBool("is_npc_ragdoll", false) then
        vrmod.logger.Debug("IsValidPickupTarget: Entity is NPC ragdoll -> " .. ent:GetClass())
        invalidPickupCache[ent] = false
        return false
    end

    if IsReAgdollHiddenNPC(ent) then return false end
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
        return false
    end

    vrmod.logger.Debug("IsValidPickupTarget: Valid pickup -> " .. ent:GetClass())
    if cacheable then invalidPickupCache[ent] = true end
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
    if not IsValid(v) or v == ply then return false end
    -- Block picking up the exact chair the player is currently sitting in
    if ply:InVehicle() and v == ply:GetVehicle() then return false end
    if cv.vrmod_pickup_npcs == 1 then if v:IsNPC() or v:IsNextBot() then return true end end
    local class = v:GetClass():lower()
    local model = (v:GetModel() or ""):lower()
    local key = class .. "|" .. model
    if vrmod.pickupLists then
        if vrmod.pickupLists.whitelist[key] then return true end
        if vrmod.pickupLists.blacklist[key] then return false end
    end

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
    local searchRadius = 35
    local nearby = ents.FindInSphere(handPos, searchRadius)
    local bestEnt = nil
    local bestDist = math.huge
    for _, e in ipairs(nearby) do
        if IsValid(e) and e ~= ply and vrmod.utils.IsValidPickupTarget(e, ply, bLeftHand) and vrmod.utils.CanPickupEntity(e, ply, convarValues or vrmod.GetConvars()) then
            local closest = e:NearestPoint(handPos)
            local dist = (closest - handPos):Length()
            if dist < bestDist and dist <= searchRadius then
                local tr = util.TraceLine({
                    start = handPos,
                    endpos = closest + (closest - handPos):GetNormalized() * 1.5,
                    filter = ply,
                    mask = MASK_SHOT
                })

                if tr.Entity == e or not tr.Hit or tr.Fraction > 0.95 then
                    bestDist = dist
                    bestEnt = e
                end
            end
        end
    end

    if IsValid(bestEnt) and bestDist <= 18 then return bestEnt end
    local ent
    local offsetPos = handPos + handAng:Forward() * vrmod.DEFAULT_OFFSET
    local sphereEnt, _ = vrmod.utils.SphereCollidesWithProp(offsetPos, 5, ply)
    if IsValid(sphereEnt) and sphereEnt ~= ply and vrmod.utils.IsValidPickupTarget(sphereEnt, ply, bLeftHand) and vrmod.utils.CanPickupEntity(sphereEnt, ply, convarValues or vrmod.GetConvars()) then ent = sphereEnt end
    if not IsValid(ent) then
        local hand = bLeftHand and "left" or "right"
        local tr = vrmod.utils.TraceHand(ply, hand, true)
        if tr and IsValid(tr.Entity) then
            local e = tr.Entity
            if e ~= ply and vrmod.utils.IsValidPickupTarget(e, ply, bLeftHand) and vrmod.utils.CanPickupEntity(e, ply, convarValues or vrmod.GetConvars()) then ent = e end
        end
    end

    if not IsValid(ent) then return nil end
    local closestFinal = ent:NearestPoint(handPos)
    local finalDist = (closestFinal - handPos):Length()
    local boost = vrmod.utils.IsImportantPickup(ent) and 5 or ent:IsNPC() and 3 or 1
    local maxDist = pickupRange * 12 * boost
    if finalDist > maxDist then return nil end
    if vrmod.utils.IsWeaponEntity(ent) then
        local aw = ply:GetActiveWeapon()
        if IsValid(aw) and aw:GetClass() == ent:GetClass() then return nil end
        if not bLeftHand and vrmod.utils.IsValidWep(aw) then return nil end
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
            if ent2:GetNWBool("isVRProxy", false) then return false end
        end

        -- Case 2: ent2 is a patched prop
        if ent2._collisionPatched then
            if ent1 == ent2._pickupOwner then return false end
            if ent1:GetNWBool("isVRProxy", false) then return false end
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
        -- NEW: Use NearestPoint for realistic "holding on surface" feel (prevents hand inside prop)
        local gripPoint = ent:NearestPoint(handPos)
        local gripToRoot = ent:GetPos() - gripPoint
        local targetPos = handPos + gripToRoot
        vrmod.logger.Debug("SnapEntityToHand: Using surface grip. gripPoint=" .. tostring(gripPoint) .. " targetPos=" .. tostring(targetPos))
        -- Ragdoll: set each physics object to its stored per-phys offset (if present),
        -- but use targetPos as the anchor instead of handPos so the whole ragdoll sits naturally.
        if ent:GetClass() == "prop_ragdoll" and ent.vrmod_physOffsets then
            for i = 0, ent:GetPhysicsObjectCount() - 1 do
                local phys = ent:GetPhysicsObjectNum(i)
                if IsValid(phys) and ent.vrmod_physOffsets[i] then
                    local offset = ent.vrmod_physOffsets[i]
                    local targetPhysPos, targetPhysAng = LocalToWorld(offset.localPos, offset.localAng, targetPos, handAng)
                    phys:Wake()
                    phys:SetPos(targetPhysPos)
                    phys:SetAngles(targetPhysAng)
                    phys:SetVelocity(Vector(0, 0, 0))
                    phys:SetAngleVelocity(Vector(0, 0, 0))
                end
            end

            -- also move the entity root to match phys positions so ent:GetPos() matches clients
            ent:SetPos(targetPos)
            ent:SetAngles(handAng)
            if ent.InvalidateBoneCache then ent:InvalidateBoneCache() end
            if ent.SetupBones then ent:SetupBones() end
            return true
        end

        -- Non-ragdolls: move root physics object and entity to targetPos (surface-aligned)
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:Wake()
            phys:SetPos(targetPos)
            -- preserve original orientation for natural hold
            phys:SetAngles(ent:GetAngles())
            phys:SetVelocity(Vector(0, 0, 0))
            phys:SetAngleVelocity(Vector(0, 0, 0))
            ent:SetPos(targetPos)
            ent:SetAngles(ent:GetAngles())
        else
            -- fallback: set entity transform directly
            ent:SetPos(targetPos)
            ent:SetAngles(ent:GetAngles())
        end

        if ent.InvalidateBoneCache then ent:InvalidateBoneCache() end
        if ent.SetupBones then ent:SetupBones() end
        return true
    end
end