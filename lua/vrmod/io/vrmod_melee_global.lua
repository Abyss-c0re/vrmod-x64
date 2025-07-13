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
local cl_effectmodel = CreateClientConVar("vrmod_melee_fist_collisionmodel", "models/props_junk/PopCan01a.mdl", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
local cv_meleeDebug = CreateConVar("vrmod_melee_debug", "0", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Enable detailed melee debug logging (0 = off, 1 = on)")
local cl_fistvisible = CreateClientConVar("vrmod_melee_fist_visible", "0", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
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

-- SHARED CACHE
local modelCache = {} -- Now stores {radius, reach, mins, maxs, angles, computed} for weapons, {radius, reach, computed} for fists
local collisionSpheres = {}
local collisionBoxes = {} -- Added for box visualization
local pending = {}
-- SHARED FILTER
local magCache = {}
local function IsHoldingValidWeapon(ply)
    local wep = ply:GetActiveWeapon()
    return IsValid(wep) and wep:GetClass() ~= "weapon_vrmod_empty" and wep or false
end

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

-- Modified to handle both sphere and box traces
local function TraceBoxOrSphere(data)
    local best = {
        Hit = false,
        Fraction = 1
    }

    if data.mins and data.maxs then
        -- Box trace for weapons
        local tr = util.TraceHull({
            start = data.start,
            endpos = data.endpos,
            mins = data.mins,
            maxs = data.maxs,
            filter = data.filter,
            mask = data.mask
        })

        if tr.Hit then
            best = tr
            best.Hit = true
        end
    else
        -- Sphere trace approximation for hands
        local dirs = {Vector(0, 0, 0), Vector(1, 0, 0), Vector(-1, 0, 0), Vector(0, 1, 0), Vector(0, -1, 0), Vector(0, 0, 1), Vector(0, 0, -1)}
        for _, offset in ipairs(dirs) do
            local origin = data.start + offset * data.radius
            local tr = util.TraceLine({
                start = origin,
                endpos = origin + (data.endpos - data.start):GetNormalized() * (data.endpos - data.start):Length(),
                filter = data.filter,
                mask = data.mask
            })

            if tr.Hit and tr.Fraction < best.Fraction then
                best = tr
                best.Hit = true
            end
        end
    end
    return best
end

-- Integrated ApplyBoxFromRadius for weapons
local function ApplyBoxFromRadius(radius, ply, wep)
    local forward = radius
    local side = radius * 0.15
    local mins = Vector(-forward * 0.35, -side, -side)
    local maxs = Vector(forward * 2.4, side, side)
    local vmInfo = g_VR.viewModelInfo[wep]
    local offsetAng = vmInfo and vmInfo.offsetAng
    local handAng = vrmod.GetRightHandAng(ply)
    local angle = offsetAng and handAng + offsetAng or handAng
    if cv_meleeDebug:GetBool() then print(string.format("[VRHand] BOX radius %.2f | Forward-aligned mins: %s, maxs: %s, angles: %s", radius, tostring(mins), tostring(maxs), tostring(angle))) end
    return mins, maxs, angle
end

local function ComputePhysicsRadius(modelPath, ply, wep)
    if not modelPath or modelPath == "" then
        if cv_meleeDebug:GetBool() then print("[ModelRadius][Deferred] Invalid or empty model path, skipping") end
        return
    end

    if modelCache[modelPath] and modelCache[modelPath].computed then return end
    if pending[modelPath] and pending[modelPath].attempts >= 3 then
        modelCache[modelPath] = {
            radius = 5,
            reach = 6.6,
            computed = true
        }

        if cv_meleeDebug:GetBool() then print("[ModelRadius][Deferred] Max retries reached for", modelPath, "caching defaults radius=5, reach=6.6") end
        pending[modelPath] = nil
        return
    end

    pending[modelPath] = pending[modelPath] or {
        attempts = 0
    }

    pending[modelPath].attempts = pending[modelPath].attempts + 1
    local isClient = CLIENT
    util.PrecacheModel(modelPath)
    local ent = isClient and ents.CreateClientProp(modelPath) or ents.Create("prop_physics")
    if not IsValid(ent) then
        if cv_meleeDebug:GetBool() then print("[ModelRadius][Deferred] Spawn failed for", modelPath, "attempt", pending[modelPath].attempts, "of 3") end
        pending[modelPath].lastAttempt = CurTime()
        return
    end

    ent:SetModel(modelPath)
    ent:SetNoDraw(true)
    ent:PhysicsInit(SOLID_VPHYSICS)
    ent:SetMoveType(MOVETYPE_NONE)
    ent:Spawn()
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        local amin, amax = phys:GetAABB()
        if amin:Length() > 0 and amax:Length() > 0 then
            local radius = (amax - amin):Length() * 0.5
            local reach = math.Clamp(radius, 6.6, 50)
            local mins, maxs, angles = ApplyBoxFromRadius(radius, ply, wep)
            modelCache[modelPath] = {
                radius = radius,
                reach = reach,
                mins = mins,
                maxs = maxs,
                angles = angles,
                computed = true
            }

            if cv_meleeDebug:GetBool() then print(string.format("[ModelRadius][%s] AABB → %s Radius: %.2f, Reach: %.2f, Mins: %s, Maxs: %s, Angles: %s for %s", isClient and "Client" or "Server", tostring(amin) .. " / " .. tostring(amax), radius, reach, tostring(mins), tostring(maxs), tostring(angles), modelPath)) end
        else
            if cv_meleeDebug:GetBool() then print("[ModelRadius][Deferred] Zero AABB for", modelPath, "attempt", pending[modelPath].attempts, "of 3") end
        end
    else
        if cv_meleeDebug:GetBool() then print("[ModelRadius][Deferred] No physobj for", modelPath, "attempt", pending[modelPath].attempts, "of 3") end
    end

    timer.Simple(0, function() if IsValid(ent) then ent:Remove() end end)
    pending[modelPath].lastAttempt = CurTime()
end

local function GetModelRadius(modelPath, ply, wep)
    if modelCache[modelPath] and modelCache[modelPath].computed then return modelCache[modelPath].radius, modelCache[modelPath].reach, modelCache[modelPath].mins, modelCache[modelPath].maxs, modelCache[modelPath].angles end
    if not modelPath or modelPath == "" then return 5, 6.6 end
    if not pending[modelPath] or pending[modelPath] and CurTime() - (pending[modelPath].lastAttempt or 0) > 1 then
        pending[modelPath] = {
            attempts = 0
        }

        timer.Simple(0, function() ComputePhysicsRadius(modelPath, ply, wep) end)
    end
    return 5, 6.6
end

function GetWeaponMeleeParams(wep, ply, hand)
    local model = cl_effectmodel:GetString()
    local radius, reach, mins, maxs, angles
    if hand == "right" and IsValid(wep) and wep:GetClass() ~= "weapon_vrmod_empty" then
        model = wep:GetWeaponWorldModel() or wep:GetModel() or model
        radius, reach, mins, maxs, angles = GetModelRadius(model, ply, wep)
    else
        radius, reach = GetModelRadius(model)
    end

    if cv_meleeDebug:GetBool() then print(string.format("[VRMod_Melee][%s] Melee params: weapon=%s, hand=%s, radius=%.2f, reach=%.2f, mins=%s, maxs=%s, angles=%s, model=%s", CLIENT and "Client" or "Server", IsValid(wep) and wep:GetClass() or "unarmed", hand or "none", radius, reach, tostring(mins or Vector(0, 0, 0)), tostring(maxs or Vector(0, 0, 0)), tostring(angles or Angle(0, 0, 0)), model)) end
    return radius, reach, mins, maxs, angles
end

-- CLIENTSIDE --------------------------
if CLIENT then
    local NextMeleeTime = 0
    local lastWeapon = nil
    local lastWeaponCheck = 0
    local function SendMeleeAttack(src, dir, speed, radius, reach, mins, maxs, angles, impactType, hand)
        net.Start("VRMod_MeleeAttack")
        net.WriteVector(src)
        net.WriteVector(dir)
        net.WriteFloat(speed)
        net.WriteFloat(radius)
        net.WriteFloat(reach)
        net.WriteVector(mins or Vector(0, 0, 0))
        net.WriteVector(maxs or Vector(0, 0, 0))
        net.WriteAngle(angles or Angle(0, 0, 0))
        net.WriteString(impactType)
        net.WriteString(hand or "")
        net.SendToServer()
    end

    local function AddDebugShape(pos, radius, mins, maxs, angles)
        if mins and maxs and angles then
            table.insert(collisionBoxes, {
                pos = pos,
                mins = mins,
                maxs = maxs,
                angles = angles,
                die = CurTime() + 0.15
            })
        else
            table.insert(collisionSpheres, {
                pos = pos,
                radius = radius,
                die = CurTime() + 0.15
            })
        end
    end

    local function TryMelee(pos, relativeVel, useWeapon, hand)
        local ply = LocalPlayer()
        if not vrmod or not vrmod.GetHMDVelocity then return end
        if not IsValid(ply) or not ply:Alive() then return end
        if not MeleeFilter(ply, ply, hand) then return end
        local wep = IsHoldingValidWeapon(ply)
        if useWeapon and not wep then useWeapon = false end
        local relativeSpeed = relativeVel:Length()
        if relativeSpeed / 40 < cv_meleeVelThreshold:GetFloat() then return end
        if NextMeleeTime > CurTime() then return end
        local swingSound
        if useWeapon and IsValid(wep) then
            local wepClass = wep:GetClass()
            if wepClass == "weapon_crowbar" or wepClass == "arcticvr_hl2_crowbar" then swingSound = "Weapon_Crowbar.Single" end
            local swingData = {
                Player = ply,
                Weapon = wep,
                Hand = hand,
                Position = pos,
                RelativeVelocity = relativeVel,
                RelativeSpeed = relativeSpeed
            }

            hook.Run("VRMod_MeleeSwing", swingData, function(soundPath) swingSound = soundPath end)
            if swingSound then sound.Play(swingSound, pos, 75, 100, 1) end
        end

        local tr0 = util.TraceLine({
            start = pos,
            endpos = pos,
            filter = ply
        })

        local src = tr0.HitPos + tr0.HitNormal * -2
        local dir = relativeVel:GetNormalized()
        local radius, reach, mins, maxs, angles = GetWeaponMeleeParams(wep, ply, hand)
        local traceData = {
            start = src,
            endpos = src + dir * reach,
            radius = radius,
            mins = mins,
            maxs = maxs,
            filter = function(ent) return MeleeFilter(ent, ply, hand) end,
            mask = MASK_SHOT
        }

        local tr = TraceBoxOrSphere(traceData)
        if cl_fistvisible:GetBool() then AddDebugShape(src, radius, mins, maxs, angles) end
        if tr.Hit then
            NextMeleeTime = CurTime() + cv_meleeDelay:GetFloat()
            local impactType = useWeapon and "blunt" or "fist"
            SendMeleeAttack(tr.HitPos, dir, relativeSpeed, radius, reach, mins, maxs, angles, impactType, hand)
        end
    end

    hook.Add("PostDrawOpaqueRenderables", "VRMeleeDebugShapes", function()
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

        for i = #collisionBoxes, 1, -1 do
            local b = collisionBoxes[i]
            if now > b.die then
                table.remove(collisionBoxes, i)
            else
                render.SetColorMaterial()
                render.DrawWireframeBox(b.pos, b.angles, b.mins, b.maxs, Color(0, 255, 0, 150))
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
    end)

    hook.Add("Think", "VRMod_MeleeWeaponMonitor", function()
        local ply = LocalPlayer()
        if not IsValid(ply) or not vrmod.IsPlayerInVR(ply) then return end
        if CurTime() < lastWeaponCheck + 0.5 then return end
        local wep = IsHoldingValidWeapon(ply)
        if wep ~= lastWeapon then
            if IsValid(wep) then
                local model = wep:GetModel() or wep:GetWeaponWorldModel()
                if model and model ~= "" then
                    if cv_meleeDebug:GetBool() then print("[VRMod_Melee][Client] Weapon changed to", wep:GetClass(), "model:", model) end
                    ComputePhysicsRadius(model, ply, wep)
                else
                    if cv_meleeDebug:GetBool() then print("[VRMod_Melee][Client] No valid model for weapon:", wep:GetClass()) end
                end
            end

            lastWeapon = wep
        end

        lastWeaponCheck = CurTime()
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
        local mins = net.ReadVector()
        local maxs = net.ReadVector()
        local angles = net.ReadAngle()
        local impactType = net.ReadString()
        local hand = net.ReadString()
        if hand == "" then hand = nil end
        local traceData = {
            start = src,
            endpos = src + dir * reach,
            radius = radius,
            mins = mins ~= Vector(0, 0, 0) and mins or nil,
            maxs = maxs ~= Vector(0, 0, 0) and maxs or nil,
            filter = function(ent)
                if ent == ply then return false end
                return MeleeFilter(ent, ply, hand)
            end,
            mask = MASK_SHOT
        }

        local tr = TraceBoxOrSphere(traceData)
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
            if soundPath then customSound = soundPath end
            if newDecal then customDecal = newDecal end
            if newDamage then customDamage = newDamage end
            if newDamageMultiplier then customDamageMultiplier = newDamageMultiplier end
            if newDamageType then customDamageType = newDamageType end
            if newReach then customReach = newReach end
            if newRadius then customRadius = newRadius end
            if newImpactType then customImpactType = newImpactType end
        end)

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

            customDamage = customDamage or base * speedFactor * customDamageMultiplier
        end

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
        if cv_meleeDebug:GetBool() then
            local targetVelDot = targetVel:Dot(dir)
            print(string.format("[VRMod_Melee][Server] %s smashed %s for %.1f damage (impact: %s, multiplier: %.2f, type: %d, reach: %.2f, radius: %.2f, mins: %s, maxs: %s, angles: %s, swingSpeed: %.1f, targetVelDot: %.1f, relativeSpeed: %.1f, speedFactor: %.2f, sound: %s)!", attackerName, targetName, customDamage, customImpactType, customDamageMultiplier, customDamageType, customReach, customRadius, tostring(mins or Vector(0, 0, 0)), tostring(maxs or Vector(0, 0, 0)), tostring(angles or Angle(0, 0, 0)), swingSpeed, targetVelDot, relativeSpeed, speedFactor, snd or "none"))
        else
            print(string.format("[VRMod_Melee][Server] %s smashed %s for %.1f damage", attackerName, targetName, customDamage))
        end
    end)

    hook.Add("PlayerSwitchWeapon", "VRHand_UpdateSweepRadius", function(ply, oldWep, newWep)
        if not vrmod.IsPlayerInVR(ply) then return end
        local wep = IsHoldingValidWeapon(ply)
        if wep then
            local model = wep:GetModel() or wep:GetWeaponWorldModel()
            if model and model ~= "" then
                if cv_meleeDebug:GetBool() then print("[VRMod_Melee][Server] Weapon changed to", wep:GetClass(), "model:", model) end
                ComputePhysicsRadius(model, ply, wep)
            else
                if cv_meleeDebug:GetBool() then print("[VRMod_Melee][Server] No valid model for weapon:", wep:GetClass()) end
            end
        end
    end)
end