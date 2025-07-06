----------------------------------------
-- VRMod Melee System (Trace‑Based)
----------------------------------------
-- CONVARS -----------------------------
local cv_allowgunmelee = CreateConVar("vrmod_melee_gunmelee", "1", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeVelThreshold = CreateConVar("vrmod_melee_velthreshold", "1.2", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeDamage = CreateConVar("vrmod_melee_damage", "80", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeDelay = CreateConVar("vrmod_melee_delay", "0.15", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cl_usefist = CreateClientConVar("vrmod_melee_usefist", "1", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local cl_usekick = CreateClientConVar("vrmod_melee_usekick", "0", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local cl_fistvisible = CreateClientConVar("vrmod_melee_fist_visible", "0", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local cl_effectmodel = CreateClientConVar("vrmod_melee_fist_collisionmodel", "models/hunter/misc/sphere025x025.mdl", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)

-- SHARED FILTER
local function MeleeFilter(ent)
    if not IsValid(ent) then return true end
    if ent:GetNWBool("isVRHand", false) then return false end
    return true
end

-- CLIENTSIDE --------------------------
if CLIENT then
    local NextMeleeTime = 0
    local modelRadiusCache = {}
    local collisionSpheres = {}

    -- Cache model radius
    local function GetModelRadius(modelPath)
        if modelRadiusCache[modelPath] then return modelRadiusCache[modelPath] end
        local tmp = ClientsideModel(modelPath, RENDERGROUP_BOTH)
        if not IsValid(tmp) then return 10 end
        tmp:InvalidateBoneCache()
        local mn, mx = tmp:OBBMins(), tmp:OBBMaxs()
        tmp:Remove()
        local radius = (mx - mn):Length() / 2
        radius = math.Clamp(radius, 5, 50)
        modelRadiusCache[modelPath] = radius
        return radius
    end

    -- Send hit data to server
    local function SendMeleeAttack(src, dir, speed)
        net.Start("VRMod_MeleeAttack")
        net.WriteVector(src)
        net.WriteVector(dir)
        net.WriteFloat(speed)
        net.SendToServer()
    end

    -- Determine sweep radius
    local function GetSweepRadius(useWeapon)
        if useWeapon then
            local wep = LocalPlayer():GetActiveWeapon()
            if IsValid(wep) and wep:GetClass() ~= "weapon_vrmod_empty"then
                local mn, mx = wep:OBBMins(), wep:OBBMaxs()
                local ext = mx - mn
                return math.Clamp(math.max(ext.x, ext.y, ext.z) / 2, 5, 30)
            end
        end
        return GetModelRadius(cl_effectmodel:GetString())
    end

    -- Add wireframe sphere to be drawn
    local function AddDebugSphere(pos, radius)
        table.insert(collisionSpheres, {
            pos = pos,
            radius = radius,
            die = CurTime() + 0.15
        })
    end

    -- Core melee logic
    local function TryMelee(pos, vel, useWeapon)
        local ply = LocalPlayer()
        local speedRaw = vel:Length()
        local speedChk = speedRaw / 40
        if speedChk < cv_meleeVelThreshold:GetFloat() then return end
        if NextMeleeTime > CurTime() then return end

        local tr0 = util.TraceLine({
            start = pos,
            endpos = pos,
            filter = ply
        })

        local src = tr0.HitPos + tr0.HitNormal * -2
        local dir = vel:GetNormalized()
        local reach = 8
        local radius = GetSweepRadius(useWeapon)
        local tr = util.TraceHull({
            start = src,
            endpos = src + dir * reach,
            mins = Vector(-radius, -radius, -radius),
            maxs = Vector(radius, radius, radius),
            filter = MeleeFilter
        })

        if cl_fistvisible:GetBool() then
            AddDebugSphere(src, radius)
        end

        if tr.Hit then
            NextMeleeTime = CurTime() + cv_meleeDelay:GetFloat()
            SendMeleeAttack(tr.HitPos, dir, speedRaw)
        end
    end

    -- Draw wireframe debug spheres
    hook.Add("PostDrawOpaqueRenderables", "VRMeleeDebugSpheres", function()
        local now = CurTime()
        for i = #collisionSpheres, 1, -1 do
            local s = collisionSpheres[i]
            if now > s.die then
                table.remove(collisionSpheres, i)
            else
                render.SetColorMaterial()
                render.DrawWireframeSphere(s.pos, s.radius, 16, 16, Color(255, 0, 0, 150))
            end
        end
    end)

    -- Hook into VRMod
    hook.Add("VRMod_Tracking", "VRMeleeTrace", function()
        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:Alive() or not vrmod.IsPlayerInVR(ply) then return end

        if cv_allowgunmelee:GetBool() then
            local vel = vrmod.GetRightHandVelocity(ply)
            local vm = ply:GetViewModel()
            if IsValid(vm) then
                local tr = util.TraceHull({
                    start = vm:GetPos(),
                    endpos = vm:GetPos(),
                    mins = vm:OBBMins(),
                    maxs = vm:OBBMaxs(),
                    filter = ply
                })
                if tr.Hit then TryMelee(vm:GetPos(), vel, true) end
            end
        end

        if cl_usefist:GetBool() then
            TryMelee(vrmod.GetLeftHandPos(ply), vrmod.GetLeftHandVelocity(ply), false)
            TryMelee(vrmod.GetRightHandPos(ply), vrmod.GetRightHandVelocity(ply), false)
        end

        if cl_usekick:GetBool() then
            local data = g_VR.net[ply:SteamID()]
            if data and data.lerpedFrame then
                TryMelee(data.lerpedFrame.leftfootPos, data.lerpedFrame.leftfootVel, false)
                TryMelee(data.lerpedFrame.rightfootPos, data.lerpedFrame.rightfootVel, false)
            end
        end
    end)
end

-- SERVERSIDE --------------------------
if SERVER then
    util.AddNetworkString("VRMod_MeleeAttack")
    net.Receive("VRMod_MeleeAttack", function(_, ply)
        if not IsValid(ply) or not ply:Alive() then return end
        local src = net.ReadVector()
        local dir = net.ReadVector()
        local speed = net.ReadFloat()
        local base = cv_meleeDamage:GetFloat()
        local scaled = math.Clamp((speed / 80) ^ 2, 0.1, 6.0)
        local dmgAmt = base * scaled * 0.1
        local reach = 8
        local radius = 5

        local tr = util.TraceHull({
            start = src,
            endpos = src + dir * reach,
            mins = Vector(-radius, -radius, -radius),
            maxs = Vector(radius, radius, radius),
            filter = function(ent)
                if ent == ply then return false end
                if ent:GetNWBool("isVRHand", false) then return false end
                return true
            end
        })

        if not tr.Hit or not IsValid(tr.Entity) then return end
        local dmgInfo = DamageInfo()
        dmgInfo:SetAttacker(ply)
        dmgInfo:SetInflictor(ply)
        dmgInfo:SetDamage(dmgAmt)
        dmgInfo:SetDamageType(DMG_CLUB)
        dmgInfo:SetDamagePosition(tr.HitPos)
        tr.Entity:TakeDamageInfo(dmgInfo)
        local phys = tr.Entity:GetPhysicsObject()
        if IsValid(phys) then phys:ApplyForceCenter(dir * dmgAmt * 50) end
    end)
end
