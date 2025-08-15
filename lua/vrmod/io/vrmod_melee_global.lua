----------------------------------------
-- VRMod Melee System (Trace-Based)
----------------------------------------
-- CONVARS -----------------------------
local cv_allowgunmelee = CreateConVar("vrmod_melee_gunmelee", "1", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeVelThreshold = CreateConVar("vrmod_melee_velthreshold", "1.5", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeDamage = CreateConVar("vrmod_melee_damage", "3", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeDelay = CreateConVar("vrmod_melee_delay", "0.45", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeSpeedScale = CreateConVar("vrmod_melee_speedscale", "0.05", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Multiplier for relative speed in melee damage calculation")
local cl_usefist = CreateClientConVar("vrmod_melee_usefist", "1", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local cv_debug = GetConVar("vrmod_debug"):GetBool()
-- Updated impactSounds with verified sound paths
local impactSounds = {
    fist = {"physics/body/body_medium_impact_hard1.wav", "physics/body/body_medium_impact_hard2.wav", "physics/body/body_medium_impact_hard3.wav", "physics/body/body_medium_impact_soft1.wav"},
    blunt = {"physics/metal/metal_box_impact_hard1.wav", "physics/metal/metal_box_impact_hard2.wav", "physics/metal/metal_box_impact_hard3.wav"},
    stunstick = {"weapons/stunstick/stunstick_impact1.wav", "weapons/stunstick/stunstick_impact2.wav", "weapons/stunstick/stunstick_fleshhit1.wav", "weapons/stunstick/stunstick_fleshhit2.wav"},
    sharp = {"physics/flesh/flesh_squishy_impact_hard1.wav", "physics/flesh/flesh_squishy_impact_hard2.wav", "weapons/knife/knife_hit1.wav", "weapons/knife/knife_hit2.wav"},
    piercing = {"physics/flesh/flesh_bloody_impact_hard1.wav", "physics/flesh/flesh_bloody_impact_hard2.wav", "weapons/crossbow/hitbod1.wav", "weapons/crossbow/hitbod2.wav"},
    heavy = {"physics/metal/metal_barrel_impact_hard1.wav", "physics/metal/metal_barrel_impact_hard2.wav", "physics/concrete/concrete_impact_hard1.wav", "physics/concrete/concrete_impact_hard2.wav"},
    energy = {"weapons/physcannon/energy_bounce1.wav", "weapons/physcannon/energy_bounce2.wav", "weapons/physcannon/energy_sing_flyby1.wav", "weapons/physcannon/energy_sing_flyby2.wav"},
    explosive = {"weapons/explode3.wav", "weapons/explode4.wav", "ambient/explosions/explode_1.wav", "ambient/explosions/explode_2.wav"}
}

-- CLIENTSIDE --------------------------
if CLIENT then
    local NextMeleeTime = 0
    local PrecomputedMelee = {}
    local function SendMeleeAttack(src, dir, radius, reach, mins, maxs, angles, impactType, hand)
        net.Start("VRMod_MeleeAttack")
        net.WriteVector(src)
        net.WriteVector(dir)
        net.WriteFloat(radius)
        net.WriteFloat(reach)
        net.WriteVector(mins or Vector(0, 0, 0))
        net.WriteVector(maxs or Vector(0, 0, 0))
        net.WriteAngle(angles or Angle(0, 0, 0))
        net.WriteString(impactType)
        net.WriteString(hand)
        net.SendToServer()
    end

    local function TryMelee(params, hand)
        local ply = LocalPlayer()
        if NextMeleeTime > CurTime() then return end
        -- Determine if we're using a weapon and valid
        local useWeapon = params.useWeapon and IsValid(params.weapon) and vrmod.utils.IsValidWep(params.weapon)
        local isMelee = params.isMelee
        -- Compute hit source position, adjust if weapon or melee
        local src = params.pos
        if hand == "right" and (useWeapon or isMelee) then src = vrmod.utils.AdjustCollisionsBox(src, params.ang, isMelee) end
        -- Compute direction
        local dir = params.dir
        -- Trace setup
        local traceData = {
            start = src,
            endpos = src + dir * params.reach,
            radius = params.radius,
            mins = params.mins,
            maxs = params.maxs,
            filter = function(ent) return vrmod.utils.MeleeFilter(ent, ply, hand) end,
            mask = MASK_SHOT
        }

        local tr = vrmod.utils.TraceBoxOrSphere(traceData)
        if tr.Hit then
            NextMeleeTime = CurTime() + cv_meleeDelay:GetFloat()
            -- Play swing sound only for right-hand weapon
            if hand == "right" and useWeapon then
                local swingSound
                local wepClass = params.weapon:GetClass()
                if wepClass == "weapon_crowbar" or wepClass == "arcticvr_hl2_crowbar" then swingSound = "Weapon_Crowbar.Single" end
                local swingData = {
                    Player = ply,
                    Weapon = params.weapon,
                    Hand = hand,
                    Position = params.pos
                }

                hook.Run("VRMod_MeleeSwing", swingData, function(soundPath) swingSound = soundPath end)
                if swingSound then sound.Play(swingSound, params.pos, 75, 100, 1) end
            end

            -- Determine impact type AFTER everything else
            local impactType = hand == "right" and useWeapon and "blunt" or "fist"
            -- **Finally** send the melee attack
            SendMeleeAttack(tr.HitPos, dir, params.radius, params.reach, params.mins, params.maxs, params.ang, impactType, hand)
        end
    end

    hook.Add("VRMod_Tracking", "VRMeleeTrace", function()
        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:Alive() or not vrmod.IsPlayerInVR(ply) then return end
        -- Precompute left hand (always fist)
        local leftAng = vrmod.GetLeftHandAng(ply)
        local leftPos = vrmod.GetLeftHandPos(ply) + leftAng:Forward() * 5
        local leftRadius, leftReach, leftMins, leftMaxs, leftAngParam = vrmod.utils.GetWeaponMeleeParams(nil, ply, "left")
        PrecomputedMelee.left = {
            radius = leftRadius,
            reach = leftReach,
            mins = leftMins,
            maxs = leftMaxs,
            ang = leftAngParam,
            dir = leftAng:Forward(),
            useWeapon = false,
            pos = leftPos
        }

        -- Precompute right hand (may have weapon)
        local rightAng = vrmod.GetRightHandAng(ply)
        local rightPos = vrmod.GetRightHandPos(ply) + rightAng:Forward() * 5
        local rightWep = ply:GetActiveWeapon()
        local useWeapon = IsValid(rightWep) and vrmod.utils.IsValidWep(rightWep)
        local rightRadius, rightReach, rightMins, rightMaxs, rightAngParam, rightIsMelee = vrmod.utils.GetWeaponMeleeParams(useWeapon and rightWep or nil, ply, "right")
        PrecomputedMelee.right = {
            radius = rightRadius,
            reach = rightReach,
            mins = rightMins,
            maxs = rightMaxs,
            ang = rightAngParam,
            dir = rightAng:Forward(),
            useWeapon = useWeapon,
            weapon = rightWep,
            isMelee = rightIsMelee, -- only for collision adjustment
            pos = rightPos
        }

        -- Threshold check (velocity-based) happens **after** precomputation
        local leftVel = vrmod.GetLeftHandVelocityRelative() or Vector(0, 0, 0)
        local rightVel = vrmod.GetRightHandVelocityRelative() or Vector(0, 0, 0)
        local threshold = cv_meleeVelThreshold:GetFloat() * 50
        if leftVel:Length() < threshold and rightVel:Length() < threshold then return end
        if not cl_usefist:GetBool() then return end
        -- Try melee for both hands
        TryMelee(PrecomputedMelee.left, "left")
        TryMelee(PrecomputedMelee.right, "right")
    end)
end

-- SERVERSIDE --------------------------
if SERVER then
    util.AddNetworkString("VRMod_MeleeAttack")
    net.Receive("VRMod_MeleeAttack", function(_, ply)
        if not IsValid(ply) or not ply:Alive() then return end
        local src = net.ReadVector()
        local dir = net.ReadVector()
        local radius = net.ReadFloat()
        local reach = net.ReadFloat()
        local mins = net.ReadVector()
        local maxs = net.ReadVector()
        local angles = net.ReadAngle()
        local impactType = net.ReadString()
        local hand = net.ReadString()
        local swingSpeed
        if hand == "left" then
            swingSpeed = vrmod.GetLeftHandVelocityRelative(ply)
        else
            swingSpeed = vrmod.GetRightHandVelocityRelative(ply)
        end

        if swingSpeed then swingSpeed = swingSpeed:Length() end
        local traceData = {
            start = src,
            endpos = src + dir * reach,
            radius = radius,
            mins = mins,
            max = maxs,
            filter = function(ent) return vrmod.utils.MeleeFilter(ent, ply, hand) end,
            mask = MASK_SHOT
        }

        local tr = vrmod.utils.TraceBoxOrSphere(traceData)
        if not tr.Hit then return end
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

        local base = cv_meleeDamage:GetFloat()
        local targetVel = tr.Entity.GetVelocity and tr.Entity:GetVelocity() or Vector(0, 0, 0)
        local relativeSpeed = math.max(0, swingSpeed)
        local speedScale = cv_meleeSpeedScale:GetFloat()
        local damageMultiplier = 1.0
        local damageType = bit.bor(DMG_CLUB, DMG_BLAST)
        if impactType == "blunt" then
            damageMultiplier = 1.25
        elseif impactType == "stunstick" then
            damageMultiplier = 1.1
            damageType = bit.bor(DMG_CLUB, DMG_SHOCK)
        elseif impactType == "sharp" then
            damageMultiplier = 1.5
            damageType = DMG_SLASH
        elseif impactType == "piercing" then
            damageMultiplier = 1.3
            damageType = DMG_BULLET
        elseif impactType == "heavy" then
            damageMultiplier = 2.0
            damageType = bit.bor(DMG_CLUB, DMG_CRUSH)
        elseif impactType == "energy" then
            damageMultiplier = 1.4
            damageType = bit.bor(DMG_ENERGYBEAM, DMG_SHOCK)
        elseif impactType == "explosive" then
            damageMultiplier = 2.5
            damageType = bit.bor(DMG_BLAST, DMG_CLUB)
        end

        local speedFactor = math.min(5.0, 1.0 + relativeSpeed * speedScale)
        local dmgAmt = base * speedFactor * damageMultiplier
        local customSound = nil
        local customDecal = decalName
        local customDamage = dmgAmt
        local customDamageMultiplier = damageMultiplier
        local customDamageType = damageType
        local customReach = reach
        local customRadius = radius
        local customImpactType = impactType
        local hitData = {
            Attacker = ply,
            HitEntity = tr.Entity,
            HitPos = tr.HitPos,
            Damage = dmgAmt,
            ImpactType = impactType,
            Hand = hand,
            RelativeSpeed = relativeSpeed,
            MaterialType = matType,
            DecalName = decalName,
            DamageMultiplier = damageMultiplier,
            DamageType = damageType,
            Reach = reach,
            Radius = radius
        }

        hook.Run("VRMod_MeleeHit", hitData, function(soundPath, newDecal, newDamage, newDamageMultiplier, newDamageType, newReach, newRadius, newImpactType)
            if hand == "left" then return end
            if soundPath then customSound = soundPath end
            if newDecal then customDecal = newDecal end
            if newDamage then customDamage = newDamage end
            if newDamageMultiplier then customDamageMultiplier = newDamageMultiplier end
            if newDamageType then customDamageType = newDamageType end
            if newReach then customReach = newReach end
            if newRadius then customRadius = newRadius end
            if newImpactType then customImpactType = newImpactType end
        end)

        if not customDamageType and customImpactType then
            if customImpactType == "blunt" then
                customDamageMultiplier = customDamageMultiplier or 1.25
                customDamageType = bit.bor(DMG_CLUB, DMG_BLAST)
            elseif customImpactType == "stunstick" then
                customDamageMultiplier = customDamageMultiplier or 1.1
                customDamageType = bit.bor(DMG_CLUB, DMG_SHOCK)
            elseif customImpactType == "sharp" then
                customDamageMultiplier = customDamageMultiplier or 1.5
                customDamageType = DMG_SLASH
            elseif customImpactType == "piercing" then
                customDamageMultiplier = customDamageMultiplier or 1.3
                customDamageType = DMG_BULLET
            elseif customImpactType == "heavy" then
                customDamageMultiplier = customDamageMultiplier or 2.0
                customDamageType = bit.bor(DMG_CLUB, DMG_CRUSH)
            elseif customImpactType == "energy" then
                customDamageMultiplier = customDamageMultiplier or 1.4
                customDamageType = bit.bor(DMG_ENERGYBEAM, DMG_SHOCK)
            elseif customImpactType == "explosive" then
                customDamageMultiplier = customDamageMultiplier or 2.5
                customDamageType = bit.bor(DMG_BLAST, DMG_CLUB)
            else
                customDamageMultiplier = customDamageMultiplier or 1.0
                customDamageType = bit.bor(DMG_CLUB, DMG_BLAST)
            end
        end

        -- Always recalculate damage if not explicitly set
        customDamage = base * speedFactor * (customDamageMultiplier or 1.0)
        local dmgInfo = DamageInfo()
        dmgInfo:SetAttacker(ply)
        dmgInfo:SetInflictor(ply)
        dmgInfo:SetDamage(customDamage)
        dmgInfo:SetDamageType(customDamageType)
        dmgInfo:SetDamagePosition(tr.HitPos)
        tr.Entity:TakeDamageInfo(dmgInfo)
        local phys = tr.Entity:GetPhysicsObject()
        if IsValid(phys) then phys:ApplyForceCenter(dir * customDamage * 10) end
        local snd
        if customSound then
            snd = customSound
        else
            local list = impactSounds[customImpactType]
            if not list then
                list = impactSounds.fist
                print("[VRMod_Melee] Warning: Invalid impactType '" .. tostring(customImpactType) .. "', falling back to 'fist'")
            end

            snd = list[math.random(#list)]
        end

        sound.Play(snd, tr.HitPos, 75, 100, 1)
        util.Decal(customDecal, tr.HitPos + tr.HitNormal * 2, tr.HitPos - tr.HitNormal * 2)
        if IsValid(tr.Entity) and tr.Entity ~= game.GetWorld() then util.Decal(customDecal, tr.HitPos + tr.HitNormal * 2, tr.HitPos - tr.HitNormal * 2, tr.Entity) end
        local attackerName = ply:Nick() or "Unknown"
        local targetName = IsValid(tr.Entity) and (tr.Entity:GetName() ~= "" and tr.Entity:GetName() or tr.Entity:GetClass()) or "World"
        if cv_debug then
            local targetVelDot = targetVel:Dot(dir)
            print(string.format("[VRMod_Melee][Server] %s smashed %s for %.1f damage (impact: %s, multiplier: %.2f, type: %d, reach: %.2f, radius: %.2f, mins: %s, maxs: %s, angles: %s, swingSpeed: %.1f, targetVelDot: %.1f, relativeSpeed: %.1f, speedFactor: %.2f, sound: %s)!", attackerName, targetName, customDamage, customImpactType, customDamageMultiplier, customDamageType, customReach, customRadius, tostring(mins or Vector(0, 0, 0)), tostring(maxs or Vector(0, 0, 0)), tostring(angles or Angle(0, 0, 0)), swingSpeed, targetVelDot, relativeSpeed, speedFactor, snd or "none"))
        else
            print(string.format("[VRMod_Melee][Server] %s smashed %s for %.1f damage", attackerName, targetName, customDamage))
        end
    end)
end