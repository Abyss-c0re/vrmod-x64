----------------------------------------
-- VRMod Melee System - Refactored
----------------------------------------

-- UTILITIES ---------------------------
local convars, convarValues = vrmod.GetConvars()

local function IsPlayerInVR(ply) return vrmod.IsPlayerInVR(ply) end
local function GetRightHandVel() return vrmod.GetRightHandVelocity():Length() / 40 end
local function GetLeftHandVel() return vrmod.GetLeftHandVelocity():Length() / 40 end

local function GetLeftHandNormalizedVel() return vrmod.GetLeftHandVelocity():GetNormalized() end
local function GetRightHandNormalizedVel() return vrmod.GetRightHandVelocity():GetNormalized() end

local function CreateCollisionBox(pos, ang, model, visible)
    local ent = ents.CreateClientProp()
    ent:SetModel(model)
    ent:SetPos(pos)
    ent:SetAngles(ang)
    ent:Spawn()
    ent:SetSolid(SOLID_VPHYSICS)
    ent:SetMoveType(MOVETYPE_VPHYSICS)
    ent:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE)
    ent:SetRenderMode(visible and RENDERMODE_NORMAL or RENDERMODE_ENVIROMENTAL)
    ent:SetNotSolid(true)

    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetMass(100)
        phys:SetDamping(0, 0)
        phys:EnableGravity(false)
        phys:EnableCollisions(true)
        phys:EnableMotion(true)
    end

    return ent
end

local function SendMeleeAttack(src, dir)
    net.Start("VRMod_MeleeAttack")
    net.WriteFloat(src.x)
    net.WriteFloat(src.y)
    net.WriteFloat(src.z)
    net.WriteVector(dir)
    net.SendToServer()
end

-- CONVARS -----------------------------
local cv_allowgunmelee = CreateConVar("vrmelee_gunmelee", "1", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_allowfist     = CreateConVar("vrmelee_fist", "1", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_allowkick     = CreateConVar("vrmelee_kick", "1", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeVelThreshold = CreateConVar("vrmelee_velthreshold", "2.0", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeDamage       = CreateConVar("vrmelee_damage", "15", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeDelay        = CreateConVar("vrmelee_delay", "0.01", FCVAR_REPLICATED + FCVAR_ARCHIVE)

local cl_usegunmelee   = CreateClientConVar("vrmelee_usegunmelee", "1", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local cl_usefist       = CreateClientConVar("vrmelee_usefist", "1", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local cl_usekick       = CreateClientConVar("vrmelee_usekick", "0", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local cl_fisteffect    = CreateClientConVar("vrmelee_fist_collision", "0", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local cl_fistvisible   = CreateClientConVar("vrmelee_fist_visible", "0", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local cl_effectmodel   = CreateClientConVar("vrmelee_fist_collisionmodel", "models/hunter/plates/plate.mdl", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)

local NextMeleeTime = 0

-- CLIENTSIDE --------------------------
if CLIENT then
    local meleeBoxes = {}
    local meleeBoxLifetime = 0.1

    hook.Add("VRMod_Tracking", "VRMeleeAttacks", function()
        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:Alive() or not IsPlayerInVR(ply) then return end
        if NextMeleeTime > CurTime() then return end

        local function TryAttack(pos, vel, useWeaponModel)
            local normVel = vel:GetNormalized()
            local tr = util.TraceLine({ start = pos, endpos = pos, filter = ply })
            local src = tr.HitPos + (tr.HitNormal * -2)
            local tr2 = util.TraceLine({
                start = src,
                endpos = src + normVel * 8,
                filter = ply
            })

            if cl_fisteffect:GetBool() then
                local model, ang
                if useWeaponModel then
                    local wep = ply:GetActiveWeapon()
                    model = IsValid(wep) and wep:GetModel() or cl_effectmodel:GetString()
                    
                    -- Use the VR controller's actual orientation
                    ang = vrmod.GetRightHandAng(ply) or Angle(0, 0, 0)
                else
                    model = cl_effectmodel:GetString()
                    ang = tr2.HitNormal:Angle()
                end

                local ent = CreateCollisionBox(src, ang, model, cl_fistvisible:GetBool())
                table.insert(meleeBoxes, { ent = ent, time = CurTime() })
            end

            if tr2.Hit then
                SendMeleeAttack(src, normVel)
            end
        end

        -- Gun Melee
        if cv_allowgunmelee:GetBool() and cl_usegunmelee:GetBool() then
            if GetRightHandVel() >= cv_meleeVelThreshold:GetFloat() then
                local vm = ply:GetViewModel()
                if IsValid(vm) then
                    local tr = util.TraceHull({
                        start = vm:GetPos(),
                        endpos = vm:GetPos(),
                        filter = ply,
                        mins = vm:OBBMins(),
                        maxs = vm:OBBMaxs()
                    })

                    if tr.Hit then
                        NextMeleeTime = CurTime() + cv_meleeDelay:GetFloat()
                        TryAttack(vm:GetPos(), vrmod.GetRightHandVelocity(), true)
                    end
                end
            end
        end

        -- Fist Melee (left & right)
        if cv_allowfist:GetBool() and cl_usefist:GetBool() then
            if GetLeftHandVel() >= cv_meleeVelThreshold:GetFloat() then
                NextMeleeTime = CurTime() + cv_meleeDelay:GetFloat()
                TryAttack(vrmod.GetLeftHandPos(ply), vrmod.GetLeftHandVelocity(), false)
            elseif GetRightHandVel() >= cv_meleeVelThreshold:GetFloat() then
                NextMeleeTime = CurTime() + cv_meleeDelay:GetFloat()
                TryAttack(vrmod.GetRightHandPos(ply), vrmod.GetRightHandVelocity(), true)
            end
        end

        -- Kick Melee
        if cv_allowkick:GetBool() and cl_usekick:GetBool() then
            local data = g_VR.net[ply:SteamID()]
            if not data or not data.lerpedFrame then return end
            local frame = data.lerpedFrame
            local lf = frame.leftfootPos
            local rf = frame.rightfootPos

            local function TryKick(footPos)
                local vel = footPos:Length() / 40
                if vel < cv_meleeVelThreshold:GetFloat() then return end

                local tr = util.TraceLine({ start = footPos, endpos = footPos, filter = ply })
                local src = tr.HitPos + (tr.HitNormal * -2)
                local tr2 = util.TraceLine({ start = src, endpos = src + footPos:GetNormalized() * 8, filter = ply })

                if cl_fisteffect:GetBool() then
                    local ent = CreateCollisionBox(src, tr2.HitNormal:Angle(), cl_effectmodel:GetString(), cl_fistvisible:GetBool())
                    table.insert(meleeBoxes, { ent = ent, time = CurTime() })
                end

                if tr2.Hit then
                    NextMeleeTime = CurTime() + cv_meleeDelay:GetFloat()
                    SendMeleeAttack(src, footPos:GetNormalized())
                end
            end

            TryKick(lf)
            TryKick(rf)
        end
    end)

    hook.Add("Think", "VRMeleeBoxes", function()
        local now = CurTime()
        for i = #meleeBoxes, 1, -1 do
            if now - meleeBoxes[i].time > meleeBoxLifetime then
                if IsValid(meleeBoxes[i].ent) then meleeBoxes[i].ent:Remove() end
                table.remove(meleeBoxes, i)
            end
        end
    end)
end

-- SERVERSIDE --------------------------
if SERVER then
    util.AddNetworkString("VRMod_MeleeAttack")

    net.Receive("VRMod_MeleeAttack", function(_, ply)
        if not IsValid(ply) or not ply:Alive() then return end

        local src = Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat())
        local vel = net.ReadVector()

        local speedMod = (ply:GetVelocity():Length() / 100) + (vel:Length() / 2)
        local dmg = cv_meleeDamage:GetFloat() * speedMod

        ply:LagCompensation(true)
        ply:FireBullets({
            Attacker = ply,
            Damage = dmg,
            Force = 1,
            Num = 1,
            Tracer = 0,
            Dir = vel,
            Src = src
        })
        ply:LagCompensation(false)
    end)
end