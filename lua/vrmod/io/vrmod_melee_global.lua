----------------------------------------
-- VRMod Melee System (Trace-Based)
----------------------------------------
-- CONVARS -----------------------------
local cv_allowgunmelee = CreateConVar("vrmod_melee_gunmelee", "1", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeVelThreshold = CreateConVar("vrmod_melee_velthreshold", "1.5", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeDamage = CreateConVar("vrmod_melee_damage", "100", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeDelay = CreateConVar("vrmod_melee_delay", "0.45", FCVAR_REPLICATED + FCVAR_ARCHIVE)
local cv_meleeSpeedScale = CreateConVar("vrmod_melee_speedscale", "0.05", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Multiplier for relative speed in melee damage calculation")
local cl_usefist = CreateClientConVar("vrmod_melee_usefist", "1", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
--local cl_usekick = CreateClientConVar("vrmod_melee_usekick", "0", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local cl_effectmodel = CreateClientConVar("vrmod_melee_fist_collisionmodel", "models/props_junk/PopCan01a.mdl", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local cv_meleeDebug = CreateConVar("vrmod_melee_debug", "0", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Enable detailed melee debug logging (0 = off, 1 = on)")
local cl_fistvisible = CreateClientConVar("vrmod_melee_fist_visible", "0", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
-- Updated impactSounds with verified sound paths
local impactSounds = {
    fist = {"physics/body/body_medium_impact_hard1.wav", "physics/body/body_medium_impact_hard2.wav", "physics/body/body_medium_impact_hard3.wav", "physics/body/body_medium_impact_soft1.wav"},
    -- Suitable for unarmed punches or light hand strikes
    blunt = {"physics/metal/metal_box_impact_hard1.wav", "physics/metal/metal_box_impact_hard2.wav", "physics/metal/metal_box_impact_hard3.wav"},
    -- For clubs, hammers, crowbars, or other heavy, non-sharp weapons
    stunstick = {"weapons/stunstick/stunstick_impact1.wav", "weapons/stunstick/stunstick_impact2.wav", "weapons/stunstick/stunstick_fleshhit1.wav", "weapons/stunstick/stunstick_fleshhit2.wav"},
    -- For Combine stun batons, with electric, high-tech impact sounds
    sharp = {"physics/flesh/flesh_squishy_impact_hard1.wav", "physics/flesh/flesh_squishy_impact_hard2.wav", "weapons/knife/knife_hit1.wav", "weapons/knife/knife_hit2.wav"},
    -- For swords, knives, or other bladed weapons with cutting/slicing effects
    piercing = {"physics/flesh/flesh_bloody_impact_hard1.wav", "physics/flesh/flesh_bloody_impact_hard2.wav", "weapons/crossbow/hitbod1.wav", "weapons/crossbow/hitbod2.wav"},
    -- For spears, arrows, or other penetrating weapons
    heavy = {"physics/metal/metal_barrel_impact_hard1.wav", "physics/metal/metal_barrel_impact_hard2.wav", "physics/concrete/concrete_impact_hard1.wav", "physics/concrete/concrete_impact_hard2.wav"},
    -- For massive weapons like sledgehammers or large melee objects
    energy = {"weapons/physcannon/energy_bounce1.wav", "weapons/physcannon/energy_bounce2.wav", "weapons/physcannon/energy_sing_flyby1.wav", "weapons/physcannon/energy_sing_flyby2.wav"},
    -- For sci-fi/energy-based weapons, like plasma blades or magical effects
    explosive = {"weapons/explode3.wav", "weapons/explode4.wav", "ambient/explosions/explode_1.wav", "ambient/explosions/explode_2.wav"}
    -- For explosive or high-impact melee effects, like a rocket hammer
}


-- SHARED CACHE
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

    local dirs = {Vector(0, 0, 0), Vector(1, 0, 0), Vector(-1, 0, 0), Vector(0, 1, 0), Vector(0, -1, 0), Vector(0, 0, 1), Vector(0, 0, -1)}
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
            timer.Simple(0, function() if IsValid(prop) then prop:Remove() end end)
            if amin:Length() > 0 and amax:Length() > 0 then
                local r = (amax - amin):Length() * 0.5
                modelRadiusCache[modelPath] = r
                print(string.format("[ModelRadius][Deferred] physics-prop AABB → %s  Radius: %.2f", tostring(amin) .. " / " .. tostring(amax), r))
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
        if modelRadiusCache[modelPath] then return modelRadiusCache[modelPath] end
        if not pending[modelPath] then
            pending[modelPath] = true
            timer.Simple(0, function() ComputePhysicsRadius(modelPath) end)
        end
        return 5
    end

    local function SendMeleeAttack(src, dir, speed, radius, reach, impactType, hand)
        net.Start("VRMod_MeleeAttack")
        net.WriteVector(src)
        net.WriteVector(dir)
        net.WriteFloat(speed)
        net.WriteFloat(radius)
        net.WriteFloat(reach)
        net.WriteString(impactType)
        net.WriteString(hand or "")
        net.SendToServer()
    end

    local function GetSweepRadius(useWeapon)
        local ply = LocalPlayer()
        local model = cl_effectmodel:GetString()
        if useWeapon and IsHoldingValidWeapon(ply) then
            local wep = ply:GetActiveWeapon()
            model = wep:GetWeaponWorldModel() or wep:GetModel()
        end
        return GetModelRadius(model)
    end

    local function AddDebugSphere(pos, radius)
        table.insert(collisionSpheres, {
            pos = pos,
            radius = radius,
            die = CurTime() + 0.15
        })
    end

    local function EstimateWeaponReach(ply)
        if not IsHoldingValidWeapon(ply) then return 6.6 end
        local wep = ply:GetActiveWeapon()
        local mins, maxs = wep:GetModelBounds()
        local size = (maxs - mins):Length() * 0.5
        return math.Clamp(size, 6.6, 50)
    end

    local function TryMelee(pos, relativeVel, useWeapon, hand)
        local ply = LocalPlayer()
        if not vrmod or not vrmod.GetHMDVelocity then return end
        if not IsValid(ply) or not ply:Alive() then return end
        if not MeleeFilter(ply, ply, hand) then return end
        if useWeapon and not IsHoldingValidWeapon(ply) then useWeapon = false end
        local relativeSpeed = relativeVel:Length()
        if relativeSpeed / 40 < cv_meleeVelThreshold:GetFloat() then return end
        if NextMeleeTime > CurTime() then return end
        -- Handle swing sound with VRMod_MeleeSwing hook
        local swingSound = nil
        if useWeapon then
            local wep = ply:GetActiveWeapon()
            local wepClass = wep:GetClass()
            -- Default swing sound for crowbar
            if wepClass == "weapon_crowbar" or wepClass == "arcticvr_hl2_crowbar" then swingSound = "Weapon_Crowbar.Single" end
            -- Allow overriding via hook
            local swingData = {
                Player = ply,
                Weapon = wep,
                Hand = hand,
                Position = pos,
                RelativeVelocity = relativeVel,
                RelativeSpeed = relativeSpeed
            }

            hook.Run("VRMod_MeleeSwing", swingData, function(soundPath) swingSound = soundPath end)
            -- Play swing sound if defined
            if swingSound then sound.Play(swingSound, pos, 75, 100, 1) end
        end

        local tr0 = util.TraceLine({
            start = pos,
            endpos = pos,
            filter = ply
        })

        local src = tr0.HitPos + tr0.HitNormal * -2
        local dir = relativeVel:GetNormalized()
        local reach = EstimateWeaponReach(ply)
        local radius = GetSweepRadius(useWeapon)
        local tr = TraceSphereApprox{
            start = src,
            endpos = src + dir * reach,
            radius = radius,
            filter = function(ent) return MeleeFilter(ent, ply, hand) end,
            mask = MASK_SHOT
        }

        if cl_fistvisible:GetBool() then AddDebugSphere(src, radius) end
        if tr.Hit then
            NextMeleeTime = CurTime() + cv_meleeDelay:GetFloat()
            local impactType = useWeapon and "blunt" or "fist"
            SendMeleeAttack(tr.HitPos, dir, relativeSpeed, radius, reach, impactType, hand)
        end
    end

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
        -- I don't have FBT, so can't do much in here.
        -- if cl_usekick:GetBool() and g_VR.sixPoints then
        --     local data = g_VR.net[ply:SteamID()]
        --     if data and data.lerpedFrame then
        --         local leftFootRelVel = data.lerpedFrame.leftfootVel - hmdVel
        --         local rightFootRelVel = data.lerpedFrame.rightfootVel - hmdVel
        --         TryMelee(data.lerpedFrame.leftfootPos, leftFootRelVel, false)
        --         TryMelee(data.lerpedFrame.rightfootPos, rightFootRelVel, false)
        --     end
        -- end
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
        local impactType = net.ReadString()
        local hand = net.ReadString()
        if hand == "" then hand = nil end
        -- Perform the trace with initial radius and reach
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

        if not tr.Hit then return end
        -- Default decal based on material type
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

        -- Damage calculation with linear scaling and cap
        local base = cv_meleeDamage:GetFloat() -- Default 5
        local targetVel = tr.Entity.GetVelocity and tr.Entity:GetVelocity() or Vector(0, 0, 0)
        local relativeSpeed = math.max(0, swingSpeed) -- Ignore target velocity
        local speedScale = cv_meleeSpeedScale:GetFloat() -- Default 0.03
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
        -- Universal hook for customizing melee hit
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
            if soundPath then customSound = soundPath end
            if newDecal then customDecal = newDecal end
            if newDamage then customDamage = newDamage end
            if newDamageMultiplier then customDamageMultiplier = newDamageMultiplier end
            if newDamageType then customDamageType = newDamageType end
            if newReach then customReach = newReach end
            if newRadius then customRadius = newRadius end
            if newImpactType then customImpactType = newImpactType end
        end)

        -- Recalculate damage if impactType or multiplier was overridden
        if customImpactType ~= impactType or customDamageMultiplier ~= damageMultiplier or customDamage ~= dmgAmt then
            if customImpactType ~= impactType and not customDamageMultiplier and not customDamageType then
                if customImpactType == "blunt" then
                    customDamageMultiplier = 1.25
                    customDamageType = bit.bor(DMG_CLUB, DMG_BLAST)
                elseif customImpactType == "stunstick" then
                    customDamageMultiplier = 1.1
                    customDamageType = bit.bor(DMG_CLUB, DMG_SHOCK)
                elseif customImpactType == "sharp" then
                    customDamageMultiplier = 1.5
                    customDamageType = DMG_SLASH
                elseif customImpactType == "piercing" then
                    customDamageMultiplier = 1.3
                    customDamageType = DMG_BULLET
                elseif customImpactType == "heavy" then
                    customDamageMultiplier = 2.0
                    customDamageType = bit.bor(DMG_CLUB, DMG_CRUSH)
                elseif customImpactType == "energy" then
                    customDamageMultiplier = 1.4
                    customDamageType = bit.bor(DMG_ENERGYBEAM, DMG_SHOCK)
                elseif customImpactType == "explosive" then
                    customDamageMultiplier = 2.5
                    customDamageType = bit.bor(DMG_BLAST, DMG_CLUB)
                else
                    customDamageMultiplier = 1.0
                    customDamageType = bit.bor(DMG_CLUB, DMG_BLAST)
                end
            end

            customDamage = customDamage or base * speedFactor * customDamageMultiplier -- Unified linear scaling
        end

        -- Apply damage
        local dmgInfo = DamageInfo()
        dmgInfo:SetAttacker(ply)
        dmgInfo:SetInflictor(ply)
        dmgInfo:SetDamage(customDamage)
        dmgInfo:SetDamageType(customDamageType)
        dmgInfo:SetDamagePosition(tr.HitPos)
        tr.Entity:TakeDamageInfo(dmgInfo)
        -- Apply physics force
        local phys = tr.Entity:GetPhysicsObject()
        if IsValid(phys) then phys:ApplyForceCenter(dir * customDamage * 10) end
        -- Play impact sound
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
        -- Apply decal
        util.Decal(customDecal, tr.HitPos + tr.HitNormal * 2, tr.HitPos - tr.HitNormal * 2)
        if IsValid(tr.Entity) and tr.Entity ~= game.GetWorld() then util.Decal(customDecal, tr.HitPos + tr.HitNormal * 2, tr.HitPos - tr.HitNormal * 2, tr.Entity) end
        -- Log the hit with enhanced debugging
        local attackerName = ply:Nick() or "Unknown"
        local targetName = IsValid(tr.Entity) and (tr.Entity:GetName() ~= "" and tr.Entity:GetName() or tr.Entity:GetClass()) or "World"
        if cv_meleeDebug:GetBool() then
            local targetVelDot = targetVel:Dot(dir)
            print(string.format("[VRMod_Melee][Server] %s smashed %s for %.1f damage (impact: %s, multiplier: %.2f, type: %d, reach: %.2f, radius: %.2f, swingSpeed: %.1f, targetVelDot: %.1f, relativeSpeed: %.1f, speedFactor: %.2f, sound: %s)!", attackerName, targetName, customDamage, customImpactType, customDamageMultiplier, customDamageType, customReach, customRadius, swingSpeed, targetVelDot, relativeSpeed, speedFactor, snd or "none"))
        else
            print(string.format("[VRMod_Melee][Server] %s smashed %s for %.1f damage", attackerName, targetName, customDamage))
        end
    end)
end
-- --Example Hook
-- hook.Add("VRMod_MeleeHit", "CustomStunstickHit", function(hitData, callback)
--     if hitData.ImpactType == "blunt" and IsValid(hitData.Attacker:GetActiveWeapon()) and hitData.Attacker:GetActiveWeapon():GetClass() == "weapon_stunstick" then
--         callback(
--             nil,                     -- Use default stunstick sound
--             "Impact.Metal",          -- Custom decal
--             nil,                     -- Keep calculated damage (~13.75–27.5)
--             nil,                     -- Keep default multiplier (1.1)
--             nil,                     -- Keep default damage type
--             hitData.Reach * 1.1,     -- Slightly increase reach
--             hitData.Radius,          -- Keep default radius
--             "stunstick"              -- Override to stunstick
--         )
--     end
-- end)