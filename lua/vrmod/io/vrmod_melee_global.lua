----------------------------------------
-- VRMod Melee System 
-- CONVARS -----------------------------
local cv_allowgunmelee = CreateConVar("vrmod_melee_gunmelee", "1", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeVelThreshold = CreateConVar("vrmod_melee_velthreshold", "1.2", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeDamage = CreateConVar("vrmod_melee_damage", "80", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeDelay = CreateConVar("vrmod_melee_delay", "0.15", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cl_usefist = CreateClientConVar("vrmod_melee_usefist", "1", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local cl_usekick = CreateClientConVar("vrmod_melee_usekick", "0", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local cl_fistvisible = CreateClientConVar("vrmod_melee_fist_visible", "0", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local cl_effectmodel = CreateClientConVar("vrmod_melee_fist_collisionmodel", "models/hunter/misc/sphere025x025.mdl", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
-- UTILITIES ---------------------------
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
    ent:SetNotSolid(false)
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

local function SendMeleeAttack(src, dir, speed)
    net.Start("VRMod_MeleeAttack")
    net.WriteFloat(src.x)
    net.WriteFloat(src.y)
    net.WriteFloat(src.z)
    net.WriteVector(dir)
    net.WriteFloat(speed)
    net.SendToServer()
end

-- CLIENTSIDE --------------------------
if CLIENT then
    local meleeBoxes = {}
    local meleeBoxLifetime = 0.1
    local NextMeleeTime = 0
    hook.Add("VRMod_Tracking", "VRMeleeAttacks", function()
        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:Alive() or not vrmod.IsPlayerInVR(ply) then return end
        if NextMeleeTime > CurTime() then return end
        local function IsHoldingProp(ply, hand)
            if ply ~= LocalPlayer() then return false end
            if hand == "left" then
                return IsValid(g_VR.heldEntityLeft)
            elseif hand == "right" then
                return IsValid(g_VR.heldEntityRight)
            end
            return false
        end

        local function TryAttack(pos, vel, useWeaponModel)
            local normVel = vel:GetNormalized()
            local speed = vel:Length()
            local tr = util.TraceLine({
                start = pos,
                endpos = pos,
                filter = ply
            })

            local src = tr.HitPos + tr.HitNormal * -2
            local tr2 = util.TraceLine({
                start = src,
                endpos = src + normVel * 8,
                filter = ply
            })

            local model, ang
            local fallbackModel = "models/hunter/misc/sphere025x025.mdl"
            if useWeaponModel then
                local wep = ply:GetActiveWeapon()
                if IsValid(wep) and wep:GetClass() ~= "weapon_vrmod_empty" then
                    model = wep:GetModel() local model, ang
            if useWeaponModel then
                local wep = ply:GetActiveWeapon()
                model = IsValid(wep) and wep:GetModel() or cl_effectmodel:GetString()
                ang = vrmod.GetRightHandAng(ply) or Angle(0, 0, 0)
            else
                model = cl_effectmodel:GetString()
                ang = tr2.HitNormal:Angle()
            end
                else
                    local convarModel = cl_effectmodel:GetString()
                    if util.IsValidModel(convarModel) then
                        model = convarModel
                    else
                        model = fallbackModel
                        print("VRMOD: Incorrect collision model, using default")
                    end
                end

                ang = vrmod.GetRightHandAng(ply) or Angle(0, 0, 0)
            else
                local convarModel = cl_effectmodel:GetString()
                if util.IsValidModel(convarModel) then
                    model = convarModel
                else
                    model = fallbackModel
                end

                ang = tr2.HitNormal:Angle()
            end

            local ent = CreateCollisionBox(src, ang, model, cl_fistvisible:GetBool())
            table.insert(meleeBoxes, {
                ent = ent,
                time = CurTime()
            })

            if tr2.Hit then SendMeleeAttack(src, normVel, speed) end
        end

        -- Gun Melee
        if cv_allowgunmelee:GetBool() then
            local rightVel = vrmod.GetRightHandVelocity(ply):Length() / 40
            if rightVel >= cv_meleeVelThreshold:GetFloat() then
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
                        TryAttack(vm:GetPos(), vrmod.GetRightHandVelocity(ply), true)
                    end
                end
            end
        end

        -- Fist Melee
        if cl_usefist:GetBool() then
            local leftVel = vrmod.GetLeftHandVelocity(ply):Length() / 40
            local rightVel = vrmod.GetRightHandVelocity(ply):Length() / 40
            if leftVel >= cv_meleeVelThreshold:GetFloat() and not IsHoldingProp(ply, "left") then
                NextMeleeTime = CurTime() + cv_meleeDelay:GetFloat()
                TryAttack(vrmod.GetLeftHandPos(ply), vrmod.GetLeftHandVelocity(ply), false)
            elseif rightVel >= cv_meleeVelThreshold:GetFloat() and not IsHoldingProp(ply, "right") then
                NextMeleeTime = CurTime() + cv_meleeDelay:GetFloat()
                TryAttack(vrmod.GetRightHandPos(ply), vrmod.GetRightHandVelocity(ply), true)
            end
        end

        -- Kick Melee
        if cl_usekick:GetBool() then
            local data = g_VR.net[ply:SteamID()]
            if not data or not data.lerpedFrame then return end
            local frame = data.lerpedFrame
            local lf = frame.leftfootPos
            local rf = frame.rightfootPos
            if not lf or not rf then return end
            local function TryKick(footPos)
                local vel = footPos:Length() / 40
                if vel < cv_meleeVelThreshold:GetFloat() then return end
                local tr = util.TraceLine({
                    start = footPos,
                    endpos = footPos,
                    filter = ply
                })

                local src = tr.HitPos + tr.HitNormal * -2
                local tr2 = util.TraceLine({
                    start = src,
                    endpos = src + footPos:GetNormalized() * 8,
                    filter = ply
                })

                local ent = CreateCollisionBox(src, tr2.HitNormal:Angle(), cl_effectmodel:GetString(), cl_fistvisible:GetBool())
                table.insert(meleeBoxes, {
                    ent = ent,
                    time = CurTime()
                })

                if tr2.Hit then
                    NextMeleeTime = CurTime() + cv_meleeDelay:GetFloat()
                    SendMeleeAttack(src, footPos:GetNormalized(), vel * 40)
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
        local dir = net.ReadVector()
        local speed = net.ReadFloat()
        local base = cv_meleeDamage:GetFloat()
        local scaled = math.Clamp((speed / 80) ^ 2, 0.1, 6.0)
        local damage = base * scaled * 0.1
        ply:LagCompensation(true)
        ply:FireBullets({
            Attacker = ply,
            Damage = damage,
            Force = damage,
            Num = 1,
            Tracer = 0,
            Dir = dir,
            Src = src
        })

        ply:LagCompensation(false)
    end)
end