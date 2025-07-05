print("Running VR physical hands system.")
if CLIENT then return end
-- Per-player hand tracking
local vrHands = {}
-- Spawns invisible physical hands for a player
local function SpawnVRHands(ply)
    if not IsValid(ply) or not ply:Alive() or not vrmod.IsPlayerInVR(ply) then return end
    if not vrHands[ply] then vrHands[ply] = {} end
    local hands = vrHands[ply]
    for _, side in ipairs({"right", "left"}) do
        local hand = ents.Create("base_anim")
        if not IsValid(hand) then continue end
        hand:SetModel("models/props_junk/PopCan01a.mdl")
        hand:Spawn()
        hand:PhysicsInitSphere(2.7, "metal_bouncy")
        hand:SetPersistent(true)
        hand:Activate()
        hand:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)
        hand:SetPos(ply:GetPos())
        hand:SetNoDraw(true)
        hand:SetNWBool("isVRHand", true) 
        local phys = hand:GetPhysicsObject()
        if IsValid(phys) then phys:SetMass(20) end
        hands[side] = {
            ent = hand,
            phys = phys
        }
    end
end

-- Removes hands for a player
local function RemoveVRHands(ply)
    if not IsValid(ply) or not ply:Alive() then return end
    local hands = vrHands[ply]
    if not hands then return end
    for _, side in pairs(hands) do
        if IsValid(side.ent) then side.ent:Remove() end
    end

    vrHands[ply] = nil
end

-- Handles physics every tick
hook.Add("PlayerTick", "VRHand_PhysicsUpdate", function(ply)
    local hands = vrHands[ply]
    if not hands or not hands.right or not hands.left then
        RemoveVRHands(ply)
        SpawnVRHands(ply)
        return
    end

    local function UpdateHand(side, getPos, getAng)
        local data = hands[side]
        if not data or not IsValid(data.ent) or not IsValid(data.phys) then return end
        local pos, ang = LocalToWorld(Vector(2, 0, 0), Angle(0, 0, 0), getPos(ply), getAng(ply))
        local center = data.ent:LocalToWorld(data.phys:GetMassCenter())
        local velocity = (pos - center) * 60 + ply:GetVelocity()
        data.phys:SetVelocity(velocity)
        local _, angVel = WorldToLocal(Vector(), ang, Vector(), data.phys:GetAngles())
        local targetAngVel = Vector(angVel.roll, angVel.pitch, angVel.yaw) * 30
        data.phys:AddAngleVelocity(targetAngVel - data.phys:GetAngleVelocity())
    end

    UpdateHand("right", vrmod.GetRightHandPos, vrmod.GetRightHandAng)
    UpdateHand("left", vrmod.GetLeftHandPos, vrmod.GetLeftHandAng)
    if ply:GetPos():DistToSqr(hands.right.ent:GetPos()) > 10000 then
        hands.right.ent:SetPos(ply:GetPos())
        hands.left.ent:SetPos(ply:GetPos())
    end
end)


-- Prevent pickup of hand entities
hook.Add("VRMod_Pickup", "VRHand_BlockPickup", function(ply, ent)
    local hands = vrHands[ply]
    if not hands then return end
    if ent == hands.right.ent or ent == hands.left.ent then return false end
end)

-- On VR session start
hook.Add("VRMod_Start", "VRHand_OnVRStart", function(ply) SpawnVRHands(ply) end)
-- On player spawn
hook.Add("PlayerSpawn", "VRHand_OnSpawn", function(ply) if vrmod.IsPlayerInVR(ply) then timer.Simple(0.1, function() if IsValid(ply) then SpawnVRHands(ply) end end) end end)
-- On player death
hook.Add("PlayerDeath", "VRHand_OnDeath", function(ply) RemoveVRHands(ply) end)
-- On VR session end
hook.Add("VRMod_Exit", "VRHand_OnVRExit", function(ply) RemoveVRHands(ply) end)
-- On disconnect
hook.Add("PlayerDisconnected", "VRHand_OnDisconnect", function(ply) RemoveVRHands(ply) end)
-- Handle cleanup manually before map cleanup wipes entities
hook.Add("PreCleanupMap", "VRHand_OnCleanup", function()
    for ply, _ in pairs(vrHands) do
        RemoveVRHands(ply)
    end
end)

-- Handle avrmag_ pickup collision change
hook.Add("VRMod_Pickup", "VRHand_AVRMagSet", function(ply, ent)
    if not IsValid(ent) then return end
    if not string.match(ent:GetClass(), "avrmag_") then return end
    local hands = vrHands[ply]
    if hands and hands.left and IsValid(hands.left.ent) then hands.left.ent:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE) end
end)

-- Restore collision group on drop
hook.Add("VRMod_Drop", "VRHand_AVRMagRestore", function(ply, ent)
    if not IsValid(ent) then return end
    if not string.match(ent:GetClass(), "avrmag_") then return end
    local hands = vrHands[ply]
    if hands and hands.left and IsValid(hands.left.ent) then hands.left.ent:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR) end
end)