local convars, convarValues = vrmod.GetConvars()
local function IsPlayerInVR(ply)
    return vrmod.IsPlayerInVR(ply)
end

local function GetHMDPos(ply)
    return vrmod.GetHMDPos(ply)
end

local function GetHMDAng(ply)
    return vrmod.GetHMDAng(ply)
end

local function GetLeftHandPos(ply)
    return vrmod.GetLeftHandPos(ply)
end

local function GetLeftHandAng(ply)
    return vrmod.GetLeftHandAng(ply)
end

local function GetRightHandPos(ply)
    return vrmod.GetRightHandPos(ply)
end

local function GetRightHandAng(ply)
    return vrmod.GetRightHandAng(ply)
end


local function GetLeftHandVelocity(ply)
    return vrmod.GetLeftHandVelocity(ply)
end

local function GetLeftRightVelocity(ply)
    return vrmod.GetLeftRightVelocity(ply)
end

--models/hunter/plates/plate.mdl
local cv_allowgunmelee = CreateConVar("vrmelee_gunmelee", "1", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Allow melee attacks with gun?")
local cv_allowfist = CreateConVar("vrmelee_fist", "1", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Allow fist attacks?")
local cv_allowkick = CreateConVar("vrmelee_kick", "1", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Allow kick attacks? (Requires full body tracking)")
local cv_meleeVelThreshold = CreateConVar("vrmelee_velthreshold", "2.0", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeDamage = CreateConVar("vrmelee_damage", "15", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeDelay = CreateConVar("vrmelee_delay", "0.01", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cl_usegunmelee = CreateClientConVar("vrmelee_usegunmelee", "1", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE, "Use melee attacks with gun?")
local cl_usefist = CreateClientConVar("vrmelee_usefist", "1", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE, "Use fist attacks?")
local cl_usekick = CreateClientConVar("vrmelee_usekick", "0", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE, "Use kick attacks? (Requires full body tracking)")
local cl_fisteffect = CreateClientConVar("vrmelee_fist_collision", "0", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE, "Use Fist attack Collision?")
local cl_fistvisible = CreateClientConVar("vrmelee_fist_visible", "0", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE, "Visible Fist Attack Collision Model?")
local cl_effectmodel = CreateClientConVar("vrmelee_fist_collisionmodel", "models/Gibs/HGIBS.mdl", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE, "Fist Attack Collision Model Config")
local NextMeleeTime = 0
if CLIENT then
    local meleeBoxes = {}
    local meleeBoxLifetime = 0.1
    local isAttacking = false
    local attackBox = nil

    
    hook.Add(
        "VRMod_Tracking",
        "VRMeleeAttacks",
        function(action, pressed)
            if not IsValid(LocalPlayer()) then return end
            local ply = LocalPlayer()
            if not ply:Alive() or not IsPlayerInVR(ply) then return end
            if NextMeleeTime > CurTime() then return end
            if cv_allowgunmelee:GetBool() and cl_usegunmelee:GetBool() then
                local wep = ply:GetActiveWeapon()
                if IsValid(wep) then
                    local vm = ply:GetViewModel()
                    if IsValid(vm) then
                        local vel = vrmod.GetRightHandVelocity():Length() / 40
                        if vel >= cv_meleeVelThreshold:GetFloat() then
                            local tr = util.TraceHull(
                                {
                                    start = vm:GetPos(),
                                    endpos = vm:GetPos(),
                                    filter = ply,
                                    mins = vm:OBBMins(),
                                    maxs = vm:OBBMaxs()
                                }
                            )

                            if tr.Hit then
                                NextMeleeTime = CurTime() + cv_meleeDelay:GetFloat()
                                local src = tr.HitPos + (tr.HitNormal * -2)
                                local tr2 = util.TraceLine(
                                    {
                                        start = src,
                                        endpos = src + (vrmod.GetRightHandVelocity():GetNormalized() * 8),
                                        filter = ply
                                    }
                                )

                                if tr2.Hit then
                                    net.Start("VRMod_MeleeAttack")
                                    net.WriteFloat(src[1])
                                    net.WriteFloat(src[2])
                                    net.WriteFloat(src[3])
                                    net.WriteVector(vrmod.GetRightHandVelocity():GetNormalized())
                                    net.SendToServer()
                                end
                            end
                        end
                    end
                end
            end

            if cv_allowfist:GetBool() and cl_usefist:GetBool() then
                local lhvel = vrmod.GetLeftHandVelocity():Length() / 40
                local rhvel = vrmod.GetRightHandVelocity():Length() / 40
                if lhvel >= cv_meleeVelThreshold:GetFloat() then
                    local src = vrmod.GetLeftHandPos(ply)
                    local tr = util.TraceLine(
                        {
                            start = src,
                            endpos = src,
                            filter = ply
                        }
                    )

                    NextMeleeTime = CurTime() + cv_meleeDelay:GetFloat()
                    local src = tr.HitPos + (tr.HitNormal * -2)
                    local tr2 = util.TraceLine(
                        {
                            start = src,
                            endpos = src + (vrmod.GetLeftHandVelocity():GetNormalized() * 8),
                            filter = ply
                        }
                    )

                    if cl_fisteffect:GetBool() then
                        -- Spawn invisible collision box for left fist
                        local ent = ents.CreateClientProp()
                        ent:SetModel(cl_effectmodel:GetString())
                        ent:SetPos(src)
                        ent:SetAngles(tr2.HitNormal:Angle())
                        ent:Spawn()
                        ent:SetSolid(SOLID_VPHYSICS)
                        ent:SetMoveType(MOVETYPE_VPHYSICS)
                        ent:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE)
                        if cl_fistvisible:GetBool() then
                            ent:SetRenderMode(RENDERMODE_NORMAL)
                        else
                            ent:SetRenderMode(RENDERMODE_ENVIROMENTAL)
                        end

                        ent:SetNotSolid(true)
                        local phys = ent:GetPhysicsObject()
                        if IsValid(phys) then
                            phys:SetMass(100)
                            phys:SetDamping(0, 0)
                            phys:EnableGravity(false)
                            phys:EnableCollisions(true)
                            phys:EnableMotion(true)
                        end

                        table.insert(
                            meleeBoxes,
                            {
                                ent = ent,
                                time = CurTime()
                            }
                        )
                    end

                    -- Spawn invisible collision box end
                    if tr2.Hit then
                        net.Start("VRMod_MeleeAttack")
                        net.WriteFloat(src[1])
                        net.WriteFloat(src[2])
                        net.WriteFloat(src[3])
                        net.WriteVector(vrmod.GetLeftHandVelocity():GetNormalized())
                        net.SendToServer()
                    end
                end

                if rhvel >= cv_meleeVelThreshold:GetFloat() then
                    local src = vrmod.GetRightHandPos(ply)
                    local tr = util.TraceLine(
                        {
                            start = src,
                            endpos = src,
                            filter = ply
                        }
                    )

                    NextMeleeTime = CurTime() + cv_meleeDelay:GetFloat()
                    local src = tr.HitPos + (tr.HitNormal * -2)
                    local tr2 = util.TraceLine(
                        {
                            start = src,
                            endpos = src + (vrmod.GetRightHandVelocity():GetNormalized() * 8),
                            filter = ply
                        }
                    )

                    if cl_fisteffect:GetBool() then
                        -- Spawn invisible collision box for right fist
                        local ent = ents.CreateClientProp()

                        
                        -- local weapon = ply:GetActiveWeapon() -- Get the currently equipped weapon                                       
                        -- if IsValid(weapon) then -- Check if the weapon is valid                                                         
                        --     ent:SetModel(weapon:GetModel())
                        --     ent:SetAngles(0)
                        -- else                                                                                                            
                        --     ent:SetModel(cl_effectmodel:GetString())
                        --     ent:SetAngles(tr2.HitNormal:Angle())                                                                  
                        -- end   

                        ent:SetModel(cl_effectmodel:GetString())
                        ent:SetAngles(tr2.HitNormal:Angle()) 
                        ent:SetPos(src)
                        
                        ent:Spawn()
                        ent:SetSolid(SOLID_BSP)
                        ent:SetMoveType(MOVETYPE_VPHYSICS)
                        ent:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE)
                        if cl_fistvisible:GetBool() then
                            ent:SetRenderMode(RENDERMODE_NORMAL)
                        else
                            ent:SetRenderMode(RENDERMODE_ENVIROMENTAL)
                        end

                        ent:SetNotSolid(true)
                        local phys = ent:GetPhysicsObject()
                        if IsValid(phys) then
                            phys:SetMass(100)
                            phys:SetDamping(0, 0)
                            phys:EnableGravity(false)
                            phys:EnableCollisions(true)
                            phys:EnableMotion(true)
                        end

                        table.insert(
                            meleeBoxes,
                            {
                                ent = ent,
                                time = CurTime()
                            }
                        )
                    end

                    -- Spawn invisible collision box end
                    if tr2.Hit then
                        net.Start("VRMod_MeleeAttack")
                        net.WriteFloat(src[1])
                        net.WriteFloat(src[2])
                        net.WriteFloat(src[3])
                        net.WriteVector(vrmod.GetRightHandVelocity():GetNormalized())
                        net.SendToServer()
                    end
                end
            end

            if cv_allowkick:GetBool() and cl_usekick:GetBool() then
                if not g_VR.net[ply:SteamID()] or not g_VR.net[ply:SteamID()].lerpedFrame then return end
                local lfvel = g_VR.net[ply:SteamID()].lerpedFrame.leftfootPos:Length() / 40
                local rfvel = g_VR.net[ply:SteamID()].lerpedFrame.rightfootPos:Length() / 40
                if lfvel >= cv_meleeVelThreshold:GetFloat() then
                    local src = g_VR.net[ply:SteamID()].lerpedFrame.leftfootPos
                    local tr = util.TraceLine(
                        {
                            start = src,
                            endpos = src,
                            filter = ply
                        }
                    )

                    -- Spawn invisible collision box for left foot
                    if cl_fisteffect:GetBool() then
                        local ent = ents.CreateClientProp()
                        ent:SetModel(cl_effectmodel:GetString())
                        ent:SetPos(src)
                        ent:SetAngles(tr2.HitNormal:Angle())
                        ent:Spawn()
                        ent:SetSolid(SOLID_BSP)
                        ent:SetMoveType(MOVETYPE_VPHYSICS)
                        ent:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE)
                        if cl_fistvisible:GetBool() then
                            ent:SetRenderMode(RENDERMODE_NORMAL)
                        else
                            ent:SetRenderMode(RENDERMODE_ENVIROMENTAL)
                        end

                        ent:SetNotSolid(true)
                        local phys = ent:GetPhysicsObject()
                        if IsValid(phys) then
                            phys:SetMass(100)
                            phys:SetDamping(0, 0)
                            phys:EnableGravity(false)
                            phys:EnableCollisions(true)
                            phys:EnableMotion(true)
                        end

                        table.insert(
                            meleeBoxes,
                            {
                                ent = ent,
                                time = CurTime()
                            }
                        )
                    end

                    -- Spawn invisible collision box end
                    if tr.Hit then
                        NextMeleeTime = CurTime() + cv_meleeDelay:GetFloat()
                        local src = tr.HitPos + (tr.HitNormal * -2)
                        local tr2 = util.TraceLine(
                            {
                                start = src,
                                endpos = src + (g_VR.net[ply:SteamID()].lerpedFrame.leftfootPos:GetNormalized() * 8),
                                filter = ply
                            }
                        )

                        if tr2.Hit then
                            net.Start("VRMod_MeleeAttack")
                            net.WriteFloat(src[1])
                            net.WriteFloat(src[2])
                            net.WriteFloat(src[3])
                            net.WriteVector(g_VR.net[ply:SteamID()].lerpedFrame.leftfootPos:GetNormalized())
                            net.SendToServer()
                        end
                    end
                end

                if rfvel >= cv_meleeVelThreshold:GetFloat() then
                    local src = g_VR.net[ply:SteamID()].lerpedFrame.rightfootPos
                    local tr = util.TraceLine(
                        {
                            start = src,
                            endpos = src,
                            filter = ply
                        }
                    )

                    -- Spawn invisible collision box for right foot  
                    if cl_fisteffect:GetBool() then
                        local ent = ents.CreateClientProp()
                        ent:SetModel(cl_effectmodel:GetString())
                        ent:SetPos(src)
                        ent:SetAngles(tr2.HitNormal:Angle())
                        ent:Spawn()
                        ent:SetSolid(SOLID_BSP)
                        ent:SetMoveType(MOVETYPE_VPHYSICS)
                        ent:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE)
                        if cl_fistvisible:GetBool() then
                            ent:SetRenderMode(RENDERMODE_NORMAL)
                        else
                            ent:SetRenderMode(RENDERMODE_ENVIROMENTAL)
                        end

                        ent:SetNotSolid(true)
                        local phys = ent:GetPhysicsObject()
                        if IsValid(phys) then
                            phys:SetMass(100)
                            phys:SetDamping(0, 0)
                            phys:EnableGravity(false)
                            phys:EnableCollisions(true)
                            phys:EnableMotion(false)
                        end

                        table.insert(
                            meleeBoxes,
                            {
                                ent = ent,
                                time = CurTime()
                            }
                        )
                    end

                    if tr.Hit then
                        NextMeleeTime = CurTime() + cv_meleeDelay:GetFloat()
                        local src = tr.HitPos + (tr.HitNormal * -2)
                        local tr2 = util.TraceLine(
                            {
                                start = src,
                                endpos = src + (g_VR.net[ply:SteamID()].lerpedFrame.rightfootPos:GetNormalized() * 8),
                                filter = ply
                            }
                        )

                        -- Spawn invisible collision box end
                        if tr2.Hit then
                            net.Start("VRMod_MeleeAttack")
                            net.WriteFloat(src[1])
                            net.WriteFloat(src[2])
                            net.WriteFloat(src[3])
                            net.WriteVector(g_VR.net[ply:SteamID()].lerpedFrame.rightfootPos:GetNormalized())
                            net.SendToServer()
                        end
                    end
                end
            end
        end
    )

    hook.Add(
        "Think",
        "VRMeleeBoxes",
        function()
            local curTime = CurTime()
            for i = #meleeBoxes, 1, -1 do
                local box = meleeBoxes[i]
                if curTime - box.time > meleeBoxLifetime then
                    if IsValid(box.ent) then
                        box.ent:Remove()
                    end

                    table.remove(meleeBoxes, i)
                end
            end
        end
    )
end

if SERVER then
    util.AddNetworkString("VRMod_MeleeAttack")
    net.Receive(
        "VRMod_MeleeAttack",
        function(len, ply)
            if not IsValid(ply) or not ply:Alive() then return end
            local src = Vector()
            src[1] = net.ReadFloat()
            src[2] = net.ReadFloat()
            src[3] = net.ReadFloat()
            local vel = net.ReadVector()
            local player_speed = (ply:GetVelocity():Length()/100)
            local fist_speed = (vel:Length()/2) 
            local damage  = cv_meleeDamage:GetFloat()
            local total = damage*(player_speed+fist_speed)
            print("hit -")
            print(total)
            ply:LagCompensation(true)

            ply:FireBullets(
                {
                    Attacker = ply,
                    Damage = total,
                    Force = 1,
                    Num = 1,
                    Tracer = 0,
                    Dir = vel,
                    Src = src
                }
            )

            ply:LagCompensation(false)
        end
    )
end