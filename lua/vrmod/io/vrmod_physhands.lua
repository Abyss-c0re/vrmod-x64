print ("running vr physhands")
if CLIENT then return end

local function vrmodspawnhands(ply)
        if VRMODHandPlayer == true then
    VEERhand = ents.Create("prop_physics")
    VEERhand:SetModel("models/hunter/plates/plate.mdl")
    VEERhand:Spawn()
    VEERhand:Activate()
    VEERhand:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)
    VEERhandPhys = VEERhand:GetPhysicsObject()
    VEERhandPhys:SetMass(20)
    VEERhand:SetPos(ply:GetPos())
    VEERhand:SetNoDraw(true)

    VEERhandLEFT = ents.Create("prop_physics")
    VEERhandLEFT:SetModel("models/hunter/plates/plate.mdl")
    VEERhandLEFT:Spawn()
    VEERhandLEFT:Activate()
    VEERhandLEFT:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)
    VEERhandPhysLEFT = VEERhandLEFT:GetPhysicsObject()
    VEERhandPhysLEFT:SetMass(20)
    VEERhandLEFT:SetPos(ply:GetPos())
    VEERhandLEFT:SetNoDraw(true)
        end
    end


    local function vrmodremovehands(ply)
        if IsValid(VEERhand) and IsValid (VEERhandLEFT) then
                VEERhand:Remove()
                VEERhandLEFT:Remove()
        end
end


    hook.Add("PlayerTick", "physhandphys", function (ply)
        if VRMODHandPlayer == true and IsValid(VEERhand) and IsValid(VEERhandLEFT) then


local righthandtargetpos = vrmod.GetRightHandPos(ply)
local righthandtargetang = vrmod.GetRightHandAng(ply)

        local targetPos, targetAng = LocalToWorld(Vector(3, -0, 0), Angle(90.0, 0.0, 0.0), righthandtargetpos, righthandtargetang)

        local targetVel = ( targetPos - VEERhand:LocalToWorld(VEERhandPhys:GetMassCenter()) ) * 30 + ply:GetVelocity()


            VEERhandPhys:SetVelocity(targetVel)


            local _,tempangvel = WorldToLocal (Vector(), targetAng, Vector(), VEERhandPhys:GetAngles())
            targetAngVel = Vector(tempangvel.roll, tempangvel.pitch, tempangvel.yaw) * 30
            VEERhandPhys:AddAngleVelocity(targetAngVel-VEERhandPhys:GetAngleVelocity())


                if IsValid(VEERhandLEFT) then

            local lefthandtargetpos = vrmod.GetLeftHandPos(ply)
local lefthandtargetang = vrmod.GetLeftHandAng(ply)

        local targetPosleft, targetAngleft = LocalToWorld(Vector(3, -0, 0), Angle(90.0, 0.0, 0.0), lefthandtargetpos, lefthandtargetang)

        local targetVelleft = ( targetPosleft - VEERhandLEFT:LocalToWorld(VEERhandPhysLEFT:GetMassCenter()) ) * 30 + ply:GetVelocity()


            VEERhandPhysLEFT:SetVelocity(targetVelleft)


            local _,tempangvelleft = WorldToLocal (Vector(), targetAngleft, Vector(), VEERhandPhysLEFT:GetAngles())
            targetAngVelleft = Vector(tempangvelleft.roll, tempangvelleft.pitch, tempangvelleft.yaw) * 30
            VEERhandPhysLEFT:AddAngleVelocity(targetAngVelleft-VEERhandPhysLEFT:GetAngleVelocity())
                end
        end


        if IsValid(VEERhand) and IsValid (VEERhandLEFT) then
                if ply:GetPos():DistToSqr(VEERhand:GetPos()) > 10000 then
                        VEERhand:SetPos(ply:GetPos())
                        VEERhandLEFT:SetPos(ply:GetPos())
                
                end
        end
        if VRMODHandPlayer == true then
        if not IsValid(VEERhand) or not IsValid (VEERhandLEFT) then
                vrmodremovehands(ply)
                vrmodspawnhands(ply)
        end
end
    end)


    hook.Add("VRMod_Pickup", "physhandnopickup", function (ply, ent)

            if ent == VEERhand then return false
            end

            if ent == VEERhandLEFT then return false
            end

    end)

    hook.Add("VRMod_Start", "physhandinit1", function (ply)

        VRMODHandPlayer = true
        vrmodspawnhands(ply)

end)

hook.Add("PlayerSpawn", "physhandinit2", function (ply)

        if VRMODHandPlayer == true then
                vrmodspawnhands(ply)
        end


end)


    hook.Add("PlayerDeath", "physhandshutdown2", function (ply)

        if IsValid(VEERhand) and IsValid (VEERhandLEFT) then
                vrmodremovehands(ply)
        end
end)

hook.Add("VRMod_Exit", "physhandshutdown", function (ply)

        VRMODHandPlayer = false
        if IsValid(VEERhand) and IsValid (VEERhandLEFT) then
                vrmodremovehands(ply)
        end
end)



hook.Add("VRMod_Pickup", "avrmagdetector", function (ply, ent)
        if not IsValid(ent) then return end	
        local tomatch = ent:GetClass()

        if string.match( tomatch, "avrmag_") then
                VEERhandLEFT:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
--                 print ("collision group changed")


        end

end)

hook.Add("VRMod_Drop", "avrmagdetectorrestore", function (ply, ent)
        if not IsValid(ent) then return end	
        local tomatch = ent:GetClass()

        if IsValid(tomatch) then                                                                                                
                if string.match( tomatch, "avrmag_") then
                        VEERhandLEFT:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)

                end                                                                         
        else                                                                                                                
                                                
        print("Attemt to drop empty object!")                                                                         
        end      
        
end)