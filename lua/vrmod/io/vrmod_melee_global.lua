----------------------------------------
-- VRMod Melee System (Trace‑Based)
----------------------------------------
-- CONVARS -----------------------------
local cv_allowgunmelee = CreateConVar("vrmod_melee_gunmelee", "1", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeVelThreshold = CreateConVar("vrmod_melee_velthreshold", "1.5", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeDamage = CreateConVar("vrmod_melee_damage", "100", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeDelay = CreateConVar("vrmod_melee_delay", "0.45", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cl_usefist = CreateClientConVar("vrmod_melee_usefist", "1", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local cl_usekick = CreateClientConVar("vrmod_melee_usekick", "0", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local cl_fistvisible = CreateClientConVar("vrmod_melee_fist_visible", "0", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local cl_effectmodel = CreateClientConVar("vrmod_melee_fist_collisionmodel", "models/props_junk/PopCan01a.mdl", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local impactSounds = {
    fist = {"physics/body/body_medium_impact_hard1.wav", "physics/body/body_medium_impact_hard2.wav", "physics/body/body_medium_impact_hard3.wav",},
    blunt = {"physics/metal/metal_barrel_impact_hard1.wav", "physics/metal/metal_barrel_impact_hard2.wav", "physics/metal/metal_solid_impact_hard1.wav",},
}

--SHARED CACHE
local modelRadiusCache = {}
local collisionSpheres = {}
local pending = {}
-- SHARED FILTER
local magCache = {}
local function IsMagazine(ent)
    local class = ent:GetClass()
    if magCache[class] ~= nil then return magCache[class] end
    local isMag = string.StartWith(class, "avrmag_")
    magCache[class] = isMag
    return isMag
end

local function MeleeFilter(ent, ply, hand)
    if not IsValid(ent) then return true end
    if ent:GetNWBool("isVRHand", false) then return false end
    if IsMagazine(ent) then return false end
    if IsValid(ply) and (hand == "left" or hand == "right") then
        local held = vrmod.GetHeldEntity(ply, hand)
        if IsValid(held) and held == ent then return false end
    end
    return true
end

local function TraceSphereApprox(data)
    local best = {
        Hit = false,
        Fraction = 1
    }

    local dirs = {Vector(0, 0, 0), Vector(1, 0, 0), Vector(-1, 0, 0), Vector(0, 1, 0), Vector(0, -1, 0), Vector(0, 0, 1), Vector(0, 0, -1),}
    -- add more sample points if you like
    for _, offset in ipairs(dirs) do
        local origin = data.start + offset * data.radius
        local tr = util.TraceLine({
            start = origin,
            endpos = origin + (data.endpos - data.start):GetNormalized() * (data.endpos - data.start):Length(),
            filter = data.filter,
            mask = data.mask,
        })

        if tr.Hit and tr.Fraction < best.Fraction then
            best = tr
            best.Hit = true
        end
    end
    return best
end

-- CLIENTSIDE --------------------------
if CLIENT then
    local NextMeleeTime = 0
    local function IsHoldingValidWeapon(ply)
        local wep = ply:GetActiveWeapon()
        return IsValid(wep) and wep:GetClass() ~= "weapon_vrmod_empty"
    end

    -- Internal: runs off‑render to compute & cache
    local function ComputePhysicsRadius(modelPath)
        local prop = ents.CreateClientProp(modelPath)
        if not IsValid(prop) then
            modelRadiusCache[modelPath] = 5
            print("[ModelRadius][Deferred] spawn failed → default 5 for", modelPath)
            pending[modelPath] = nil
            return
        end

        prop:SetNoDraw(true)
        prop:PhysicsInit(SOLID_VPHYSICS)
        prop:SetMoveType(MOVETYPE_NONE)
        prop:Spawn()
        local phys = prop:GetPhysicsObject()
        if IsValid(phys) then
            local amin, amax = phys:GetAABB()
            -- schedule removal next tick to avoid render‑time errors
            timer.Simple(0, function() if IsValid(prop) then prop:Remove() end end)
            if amin:Length() > 0 and amax:Length() > 0 then
                local r = (amax - amin):Length() * 0.5
                modelRadiusCache[modelPath] = r
                print(string.format("[ModelRadius][Deferred] physics‑prop AABB → %s  Radius: %.2f", tostring(amin) .. " / " .. tostring(amax), r))
            else
                modelRadiusCache[modelPath] = 5
                print("[ModelRadius][Deferred] zero AABB → default 5 for", modelPath)
            end
        else
            prop:Remove()
            modelRadiusCache[modelPath] = 5
            print("[ModelRadius][Deferred] no physobj → default 5 for", modelPath)
        end

        pending[modelPath] = nil
    end

    local function GetModelRadius(modelPath)
        -- 1) Immediate cache hit?
        if modelRadiusCache[modelPath] then return modelRadiusCache[modelPath] end
        -- 2) If not already computing, defer it
        if not pending[modelPath] then
            pending[modelPath] = true
            timer.Simple(0, function() ComputePhysicsRadius(modelPath) end)
        end
        -- 3) Return a small provisional sphere
        return 5
    end

    -- Send hit data to server
    local function SendMeleeAttack(src, dir, speed, radius, reach, soundType, hand)
        net.Start("VRMod_MeleeAttack")
        net.WriteVector(src)
        net.WriteVector(dir)
        net.WriteFloat(speed)
        net.WriteFloat(radius)
        net.WriteFloat(reach)
        net.WriteString(soundType)
        net.WriteString(hand or "") -- send empty string if no hand
        net.SendToServer()
    end

    -- Determine sweep radius
    local function GetSweepRadius(useWeapon)
        local ply = LocalPlayer()
        local model = cl_effectmodel:GetString()
        if useWeapon and IsHoldingValidWeapon(ply) then
            local wep = ply:GetActiveWeapon()
            model = wep:GetWeaponWorldModel() or wep:GetModel()
        end
        return GetModelRadius(model)
    end

    -- Add wireframe sphere to be drawn
    local function AddDebugSphere(pos, radius)
        table.insert(collisionSpheres, {
            pos = pos,
            radius = radius,
            die = CurTime() + 0.15
        })
    end

    local function EstimateWeaponReach(wep)
        if not IsValid(wep) then return 5 end
        local mins, maxs = wep:GetModelBounds()
        local size = (maxs - mins):Length() * 0.5
        return math.Clamp(size, 5, 50)
    end

    -- Core melee logic
    local function TryMelee(pos, relativeVel, useWeapon, hand)
        local ply = LocalPlayer()
        if not vrmod or not vrmod.GetHMDVelocity then return end
        if not IsValid(ply) or not ply:Alive() then return end
        if not MeleeFilter(ent, ply, hand) then return end
        if useWeapon and not IsHoldingValidWeapon(ply) then useWeapon = false end
        -- Speed check
        local relativeSpeed = relativeVel:Length()
        if relativeSpeed / 40 < cv_meleeVelThreshold:GetFloat() then return end
        -- Cooldown
        if NextMeleeTime > CurTime() then return end
        -- Quick line trace to get a good source point
        local tr0 = util.TraceLine({
            start = pos,
            endpos = pos,
            filter = ply
        })

        local src = tr0.HitPos + tr0.HitNormal * -2
        -- Build hull trace, passing our filter the optional hand
        local dir = relativeVel:GetNormalized()
        local wep = ply:GetActiveWeapon()
        local reach = EstimateWeaponReach(wep)
        local radius = GetSweepRadius(useWeapon)
        local tr = TraceSphereApprox{
            start = src,
            endpos = src + dir * reach,
            radius = radius,
            filter = function(ent) return MeleeFilter(ent, ply, hand) end,
            mask = MASK_SHOT
        }

        if cl_fistvisible:GetBool() then AddDebugSphere(src, radius) end
        -- If we hit, send full data including hand
        if tr.Hit then
            NextMeleeTime = CurTime() + cv_meleeDelay:GetFloat()
            local soundType = useWeapon and "blunt" or "fist"
            SendMeleeAttack(tr.HitPos, dir, relativeSpeed, radius, reach, soundType, hand)
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
        local hmdVel = vrmod.GetHMDVelocity()
        local leftRelVel = vrmod.GetLeftHandVelocity() - hmdVel
        local rightRelVel = vrmod.GetRightHandVelocity() - hmdVel
        if cl_usefist:GetBool() then
            TryMelee(vrmod.GetLeftHandPos(ply), leftRelVel, false, "left")
            TryMelee(vrmod.GetRightHandPos(ply), rightRelVel, cv_allowgunmelee:GetBool(), "right")
        end

        if cl_usekick:GetBool() and g_VR.sixPoints then
            local data = g_VR.net[ply:SteamID()]
            if data and data.lerpedFrame then
                local leftFootRelVel = data.lerpedFrame.leftfootVel - hmdVel
                local rightFootRelVel = data.lerpedFrame.rightfootVel - hmdVel
                TryMelee(data.lerpedFrame.leftfootPos, leftFootRelVel, false)
                TryMelee(data.lerpedFrame.rightfootPos, rightFootRelVel, false)
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
        local swingSpeed = net.ReadFloat()
        local radius = net.ReadFloat()
        local reach = net.ReadFloat()
        local soundType = net.ReadString()
        local hand = net.ReadString()
        if hand == "" then hand = nil end
        local base = cv_meleeDamage:GetFloat()
        local tr = TraceSphereApprox{
            start = src,
            endpos = src + dir * reach,
            radius = radius,
            filter = function(ent)
                if ent == ply then return false end
                return MeleeFilter(ent, ply, hand)
            end,
            mask = MASK_SHOT
        }

        local decalName = "Impact.Concrete"
        local matType = tr.MatType
        if matType == MAT_METAL then
            decalName = "Impact.Metal"
        elseif matType == MAT_WOOD then
            decalName = "Impact.Wood"
        elseif matType == MAT_FLESH then
            decalName = "Impact.Flesh"
        elseif matType == MAT_DIRT then
            decalName = "Impact.Dust"
        elseif matType == MAT_SAND then
            decalName = "Impact.Dust"
        elseif matType == MAT_GLASS then
            decalName = "GlassBreak"
        elseif matType == MAT_TILE then
            decalName = "Impact.Concrete"
        end

        if not tr.Hit then return end
        -- Calculate relative velocity: attacker's swing speed minus target's velocity projected onto swing direction
        local targetVel = tr.Entity.GetVelocity and tr.Entity:GetVelocity() or Vector(0, 0, 0)
        local relativeSpeed = math.max(0, swingSpeed - targetVel:Dot(dir))
        -- Scale damage based on relative speed
        local scaled = math.Clamp((relativeSpeed / 80) ^ 2, 0.1, 6.0)
        local dmgAmt = base * scaled * 0.1
        if soundType == "blunt" then dmgAmt = dmgAmt * 1.25 end
        -- Apply damage
        local dmgInfo = DamageInfo()
        dmgInfo:SetAttacker(ply)
        dmgInfo:SetInflictor(ply)
        dmgInfo:SetDamage(dmgAmt)
        dmgInfo:SetDamageType(bit.bor(DMG_CLUB, DMG_BLAST))
        dmgInfo:SetDamagePosition(tr.HitPos)
        tr.Entity:TakeDamageInfo(dmgInfo)
        -- Apply physics force
        local phys = tr.Entity:GetPhysicsObject()
        if IsValid(phys) then phys:ApplyForceCenter(dir * dmgAmt) end
        -- Play impact sound
        local list = impactSounds[soundType]
        if list then
            local snd = list[math.random(#list)]
            sound.Play(snd, tr.HitPos, 75, 100, 1)
        end

        util.Decal(decalName, tr.HitPos + tr.HitNormal * 2, tr.HitPos - tr.HitNormal * 2)
        if IsValid(tr.Entity) and tr.Entity ~= game.GetWorld() then util.Decal(decalName, tr.HitPos + tr.HitNormal * 2, tr.HitPos - tr.HitNormal * 2, tr.Entity) end
        local attackerName = ply:Nick() or "Unknown"
        local targetName = IsValid(tr.Entity) and (tr.Entity:GetName() ~= "" and tr.Entity:GetName() or tr.Entity:GetClass()) or "World"
        print(string.format("%s smashed %s for %.1f damage!", attackerName, targetName, dmgAmt))
    end)
end