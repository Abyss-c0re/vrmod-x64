if CLIENT then return end
print("[VRHand] Running VR physical hands system.")
local vrHands = {}
-- Utility to get cached physics data from weapon
local function GetCachedWeaponParams(wep, ply, side)
    if not IsValid(wep) or not wep.GetClass then return end
    local radius, reach, mins, maxs, angles = GetWeaponMeleeParams(wep, ply, side)
    if radius == 5 and reach == 6.6 then return nil end
    return radius, reach, mins, maxs, angles
end

-- Applies sphere collision
local function ApplySphere(hand, handData, radius)
    if not IsValid(hand) then return end
    hand:PhysicsInitSphere(radius, "metal_bouncy")
    local phys = hand:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetMass(20)
        handData.phys = phys
    end
end

-- Applies box collision
local function ApplyBox(hand, handData, mins, maxs, angles)
    if not IsValid(hand) then return end
    hand:PhysicsInitBox(mins, maxs)
    hand:SetAngles(angles)
    local phys = hand:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetMass(20)
        handData.phys = phys
    end
end

-- Apply appropriate collision shape based on weapon
local function UpdateWeaponCollisionShape(ply, wep)
    if not IsValid(ply) or not IsValid(wep) then return end
    if not vrmod.IsPlayerInVR(ply) then return end
    local hands = vrHands[ply]
    if not hands or not hands.right or not IsValid(hands.right.ent) then return end
    local right = hands.right
    local hand = right.ent
    local function Retry()
        timer.Simple(0, function() UpdateWeaponCollisionShape(ply, wep) end)
    end

    if wep:GetClass() == "weapon_vrmod_empty" then
        timer.Simple(0, function() ApplySphere(hand, right, 2.8) end)
        return
    end

    local radius, reach, mins, maxs, angles = GetCachedWeaponParams(wep, ply, "right")
    if not radius or not mins or not maxs or not angles then
        Retry()
        return
    end

    timer.Simple(0, function()
        if mins and maxs and angles then
            ApplyBox(hand, right, mins, maxs, angles)
        else
            ApplySphere(hand, right, 2.8)
        end
    end)
end

-- Triggers on weapon switch
hook.Add("PlayerSwitchWeapon", "VRHand_UpdateCollisionOnWeaponSwitch", function(ply, oldWep, newWep) UpdateWeaponCollisionShape(ply, newWep) end)
local function SpawnVRHands(ply)
    if not IsValid(ply) or not ply:Alive() or not vrmod.IsPlayerInVR(ply) then return end
    if not vrHands[ply] then vrHands[ply] = {} end
    local hands = vrHands[ply]
    for _, side in ipairs({"right", "left"}) do
        timer.Simple(0, function()
            if not IsValid(ply) or not ply:Alive() then return end
            local handData = hands[side]
            local hand = handData and IsValid(handData.ent) and handData.ent or nil
            if not IsValid(hand) then
                hand = ents.Create("base_anim")
                if not IsValid(hand) then return end
                hand:SetModel("models/props_junk/PopCan01a.mdl")
                hand:SetPos(ply:GetPos())
                hand:Spawn()
                hand:SetPersistent(true)
                hand:SetNoDraw(true)
                hand:SetNWBool("isVRHand", true)
                hands[side] = {
                    ent = hand
                }
            end

            hand:PhysicsInitSphere(2.8, "metal_bouncy")
            hand:SetCollisionGroup(COLLISION_GROUP_WEAPON)
            hand:Activate()
            local phys = hand:GetPhysicsObject()
            if IsValid(phys) then
                phys:SetMass(20)
                hands[side].phys = phys
            end
        end)
    end

    timer.Simple(0.1, function()
        if IsValid(ply) and hands.right and IsValid(hands.right.ent) then
            local wep = ply:GetActiveWeapon()
            if IsValid(wep) then UpdateWeaponCollisionShape(ply, wep) end
        end
    end)
end

local function RemoveVRHands(ply)
    if not IsValid(ply) then return end
    local hands = vrHands[ply]
    if not hands then return end
    for _, side in pairs(hands) do
        local ent = side.ent
        if IsValid(ent) then
            ent:SetNoDraw(true)
            ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
            ent:SetPos(Vector(0, 0, -99999))
            if IsValid(side.phys) then
                side.phys:EnableMotion(false)
                side.phys:Sleep()
            end
        end
    end
end

hook.Add("PlayerTick", "VRHand_PhysicsSync", function(ply)
    local hands = vrHands[ply]
    if not hands or not hands.right or not hands.left then
        RemoveVRHands(ply)
        SpawnVRHands(ply)
        return
    end

    local function UpdateHand(side, getPos, getAng)
        local hand = hands[side]
        if not hand or not IsValid(hand.ent) or not IsValid(hand.phys) then return end
        local pos, ang = LocalToWorld(Vector(2, 0, 0), Angle(), getPos(ply), getAng(ply))
        local center = hand.ent:LocalToWorld(hand.phys:GetMassCenter())
        local velocity = (pos - center) * 60 + ply:GetVelocity()
        hand.phys:SetVelocity(velocity)
        local _, angVel = WorldToLocal(Vector(), ang, Vector(), hand.phys:GetAngles())
        local targetAngVel = Vector(angVel.roll, angVel.pitch, angVel.yaw) * 30
        hand.phys:AddAngleVelocity(targetAngVel - hand.phys:GetAngleVelocity())
    end

    UpdateHand("right", vrmod.GetRightHandPos, vrmod.GetRightHandAng)
    UpdateHand("left", vrmod.GetLeftHandPos, vrmod.GetLeftHandAng)
end)

hook.Add("VRMod_Pickup", "VRHand_BlockPickup", function(ply, ent)
    local hands = vrHands[ply]
    if hands and (ent == hands.right.ent or ent == hands.left.ent) then return false end
end)

hook.Add("VRMod_Start", "VRHand_VRStart", function(ply) SpawnVRHands(ply) end)
hook.Add("PlayerSpawn", "VRHand_PlayerSpawn", function(ply) if vrmod.IsPlayerInVR(ply) then timer.Simple(0.1, function() if IsValid(ply) then SpawnVRHands(ply) end end) end end)
hook.Add("PlayerDeath", "VRHand_PlayerDeath", function(ply) RemoveVRHands(ply) end)
hook.Add("VRMod_Exit", "VRHand_VREnd", function(ply) RemoveVRHands(ply) end)
hook.Add("PlayerDisconnected", "VRHand_Disconnect", function(ply)
    if vrHands[ply] then
        for _, side in pairs(vrHands[ply]) do
            if IsValid(side.ent) then side.ent:Remove() end
        end

        vrHands[ply] = nil
    end
end)

hook.Add("PreCleanupMap", "VRHand_PreCleanup", function()
    for ply, _ in pairs(vrHands) do
        RemoveVRHands(ply)
    end
end)

hook.Add("PostCleanupMap", "VRHand_PostCleanup", function()
    for _, ply in ipairs(player.GetHumans()) do
        if IsValid(ply) and vrmod.IsPlayerInVR(ply) then SpawnVRHands(ply) end
    end
end)

hook.Add("Think", "VRHand_ThinkRespawn", function()
    for ply, hands in pairs(vrHands) do
        if not IsValid(ply) or not ply:Alive() or not vrmod.IsPlayerInVR(ply) then continue end
        local repair = false
        for _, side in ipairs({"right", "left"}) do
            if not hands[side] or not IsValid(hands[side].ent) then
                repair = true
                break
            end
        end

        if repair then SpawnVRHands(ply) end
    end
end)

hook.Add("VRMod_Pickup", "VRHand_AVRMagPickup", function(ply, ent)
    if not IsValid(ent) or not string.match(ent:GetClass(), "avrmag_") then return end
    local hands = vrHands[ply]
    if hands and hands.left and IsValid(hands.left.ent) then hands.left.ent:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE) end
end)

hook.Add("VRMod_Drop", "VRHand_AVRMagDrop", function(ply, ent)
    if not IsValid(ent) or not string.match(ent:GetClass(), "avrmag_") then return end
    local hands = vrHands[ply]
    if hands and hands.left and IsValid(hands.left.ent) then hands.left.ent:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR) end
end)