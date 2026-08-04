if CLIENT then return end
vrmod = vrmod or {}
local vrProxies = {}
local proxyOwners = {}
local lastAppliedWeapon = {}
-- ==================== TEMP DEBUG VISIBILITY ====================
local DEBUG_VISIBLE_PROXIES = false -- set to false when done
local function Log(msg, ...)
    vrmod.logger.Debug("[VRProxy] " .. msg, ...)
end

-- ==================== CONVARS ====================
local cvEnableProxy = CreateConVar("vrmod_collison_proxy", "1", FCVAR_ARCHIVE + FCVAR_REPLICATED, "Enable VR collision proxies module (0 = completely disabled)")
-- ==================== ORIGINAL WEAPON LOGIC (unchanged) ====================
local function GetCachedWeaponParams(wep, ply, side)
    local radius, reach, mins, maxs, angles = vrmod.utils.GetWeaponMeleeParams(wep, ply, side)
    if radius == vrmod.DEFAULT_RADIUS and reach == vrmod.DEFAULT_REACH then return nil end
    return radius, reach, mins, maxs, angles
end

local function ApplySphere(proxyEnt, proxyData, radius)
    if not IsValid(proxyEnt) then return end
    Log("ApplySphere radius=%.2f", radius)
    -- Empty string = no specific surface material → much quieter collisions
    proxyEnt:PhysicsInitSphere(radius, "")
    proxyEnt:SetSolid(SOLID_VPHYSICS)
    proxyEnt:SetCollisionBounds(Vector(-radius, -radius, -radius), Vector(radius, radius, radius))
    proxyEnt:Activate()
    local phys = proxyEnt:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetMass(70)
        phys:EnableDrag(false)
        phys:SetDamping(0.05, 0.1)
        proxyData.phys = phys
        Log("ApplySphere SUCCESS")
    end
end

local function ApplyBox(proxyEnt, proxyData, mins, maxs, angles)
    if not IsValid(proxyEnt) then return end
    Log("ApplyBox mins=%s maxs=%s", tostring(mins), tostring(maxs))
    if angles then proxyEnt:SetAngles(angles) end
    proxyEnt:PhysicsInitBox(mins, maxs)
    proxyEnt:SetSolid(SOLID_VPHYSICS)
    proxyEnt:Activate()
    local phys = proxyEnt:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetMass(70)
        proxyData.phys = phys
        Log("ApplyBox SUCCESS")
    end
end

local function UpdateWeaponCollisionShape(ply, wep)
    if not IsValid(ply) or not vrmod.IsPlayerInVR(ply) then return end
    local wepClass = IsValid(wep) and wep:GetClass() or "none"
    local lastClass = lastAppliedWeapon[ply]
    if lastClass == wepClass then
        Log("Skipping re-apply for same weapon: %s", wepClass)
        return
    end

    Log("UpdateWeaponCollisionShape called for %s → %s", ply:Nick(), wepClass)
    timer.Simple(0.1, function()
        if not IsValid(ply) or not vrmod.IsPlayerInVR(ply) then return end
        local proxies = vrProxies[ply]
        if not proxies or not proxies.right or not IsValid(proxies.right.ent) then return end
        local right = proxies.right
        local proxyEnt = right.ent
        if not vrmod.utils.IsValidWep(wep) then
            lastAppliedWeapon[ply] = "none"
            timer.Simple(0, function() ApplySphere(proxyEnt, right, vrmod.DEFAULT_RADIUS) end)
            return
        end

        local radius, _, mins, maxs, angles = GetCachedWeaponParams(wep, ply, "right")
        if not radius or not mins or not maxs or not angles or radius == vrmod.DEFAULT_RADIUS then
            timer.Simple(0.5, function() UpdateWeaponCollisionShape(ply, wep) end)
            return
        end

        lastAppliedWeapon[ply] = wepClass
        timer.Simple(0, function() ApplyBox(proxyEnt, right, mins, maxs, angles) end)
    end)
end

-- ==================== SPAWN ====================
local function SpawnVRProxies(ply)
    if not IsValid(ply) or not ply:Alive() or not vrmod.IsPlayerInVR(ply) or ply:InVehicle() or not cvEnableProxy:GetBool() or ply:GetMoveType() == MOVETYPE_NOCLIP then return end
    if vrProxies[ply] and vrProxies[ply].head and IsValid(vrProxies[ply].head.ent) and vrProxies[ply].left and IsValid(vrProxies[ply].left.ent) and vrProxies[ply].right and IsValid(vrProxies[ply].right.ent) then return end
    if not vrProxies[ply] then vrProxies[ply] = {} end
    local proxies = vrProxies[ply]
    Log("SpawnVRProxies started for %s", ply:Nick())
    for _, part in ipairs({"head", "left", "right"}) do
        timer.Simple(0, function()
            if proxies[part] and IsValid(proxies[part].ent) then return end
            local proxy = ents.Create("prop_physics")
            if not IsValid(proxy) then return end
            if part == "head" then
                proxy:SetModel("models/Gibs/HGIBS.mdl")
            else
                proxy:SetModel("models/hunter/plates/plate.mdl")
            end

            proxy:SetPos(ply:GetPos())
            proxy:Spawn()
            if DEBUG_VISIBLE_PROXIES then
                proxy:SetNoDraw(false)
                proxy:DrawShadow(true)
                proxy:SetRenderMode(RENDERMODE_NORMAL)
                if part == "head" then
                    proxy:SetModelScale(3.5)
                    proxy:SetColor(Color(255, 0, 0, 150))
                    proxy:SetMaterial("models/debug/debugwhite")
                end
            else
                proxy:SetNoDraw(true)
                proxy:DrawShadow(false)
                proxy:SetRenderMode(RENDERMODE_NONE)
            end

            proxy:SetNWBool("isVRProxy", true)
            proxy:SetCollisionGroup(COLLISION_GROUP_WEAPON)
            proxy:SetCustomCollisionCheck(true)
            proxies[part] = {
                ent = proxy,
                phys = nil,
                owner = ply,
                part = part
            }

            proxyOwners[proxy] = {
                ply = ply,
                part = part
            }

            local radius = part == "head" and 2.8 or 2.3
            ApplySphere(proxy, proxies[part], radius)
            proxy:AddCallback("PhysicsCollide", function(ent, data)
                local hit = data.HitEntity
                if not IsValid(hit) or hit:GetClass() ~= "prop_physics" then return end
                local speed = 80
                if part == "head" then
                    local vel = vrmod.GetHMDVelocity and vrmod.GetHMDVelocity(ply)
                    if vel then speed = vel:Length() end
                elseif part == "right" then
                    local vel = vrmod.GetRightHandVelocityRelative and vrmod.GetRightHandVelocity(ply)
                    if vel then speed = vel:Length() end
                else
                    local vel = vrmod.GetLeftHandVelocityRelative and vrmod.GetLeftHandVelocity(ply)
                    if vel then speed = vel:Length() end
                end

                if speed > 5 then
                    local physHit = hit:GetPhysicsObject()
                    if IsValid(physHit) then
                        local pushDir = data.HitNormal * -1
                        local pushAmount = speed * 5.0
                        -- Prevent pushing props inside walls/other props (extends anti-clip logic)
                        local trace = util.TraceHull({
                            start = hit:GetPos(),
                            endpos = hit:GetPos() + pushDir * 25,
                            mins = hit:OBBMins() * 0.7,
                            maxs = hit:OBBMaxs() * 0.7,
                            filter = {hit, ply},
                            mask = MASK_SOLID
                        })

                        if not trace.Hit then
                            physHit:ApplyForceCenter(pushDir * pushAmount)
                            Log("PHYSICS PUSH %s → prop | Speed: %.1f", part, speed)
                        end
                    end
                end
            end)

            Log("%s proxy created via ApplySphere (effects disabled)", part)
        end)
    end

    timer.Simple(0.2, function()
        if proxies.right and IsValid(proxies.right.ent) then
            local wep = ply:GetActiveWeapon()
            if vrmod.utils.IsValidWep(wep) then UpdateWeaponCollisionShape(ply, wep) end
        end
    end)

    -- NEW: Give proxies 1 second of no-collide right after spawn/enter VR
    timer.Simple(0.05, function()
        if IsValid(ply) and vrProxies[ply] then
            vrmod.SetVRProxiesNoCollide(ply, true)
            timer.Simple(1.0, function() if IsValid(ply) and vrProxies[ply] then vrmod.SetVRProxiesNoCollide(ply, false) end end)
        end
    end)
end

local function RemoveVRProxies(ply)
    if not IsValid(ply) then return end
    local proxies = vrProxies[ply]
    if not proxies then return end
    for _, data in pairs(proxies) do
        if IsValid(data.ent) then
            proxyOwners[data.ent] = nil
            data.ent:Remove()
        end
    end

    vrProxies[ply] = nil
end

-- ==================== PREVENT PROXIES FROM COLLIDING WITH EACH OTHER + DISABLE WALL COLLISIONS ====================
-- We disable world collisions because we have separate handling (PhysicsCollide push + damage redirect)
-- This completely eliminates sparks, impact sounds, and effects when touching walls/floors
hook.Add("ShouldCollide", "VRProxy_PreventSelfCollision", function(ent1, ent2)
    if not IsValid(ent1) or not IsValid(ent2) then return end
    local o1 = proxyOwners[ent1]
    local o2 = proxyOwners[ent2]
    -- Prevent same-player proxy self-collision
    if o1 and o2 and o1.ply == o2.ply then return false end
    -- Disable collisions with world (walls, floor, ceiling) — no more sparks or wall noises
    local isWorld1 = ent1:IsWorld() or ent1:GetClass() == "worldspawn"
    local isWorld2 = ent2:IsWorld() or ent2:GetClass() == "worldspawn"
    local isProxy1 = o1 or ent1:GetNWBool("isVRProxy", false)
    local isProxy2 = o2 or ent2:GetNWBool("isVRProxy", false)
    if isProxy1 and isWorld2 or isProxy2 and isWorld1 then return false end
end)

-- ==================== BLOCK COLLISION SOUNDS ONLY WHEN HITTING A WALL ====================
hook.Add("EntityEmitSound", "VRProxy_BlockSounds", function(data)
    if not data or not data.Pos then return end
    local ent = data.Entity
    if IsValid(ent) and ent:GetNWBool("isVRProxy", false) then return false end
    if IsValid(ent) and (ent:IsWorld() or ent:GetClass() == "worldspawn") then
        for _, ply in ipairs(player.GetHumans()) do
            if vrmod.IsPlayerInVR(ply) then
                local proxies = vrProxies[ply]
                if proxies then
                    for _, part in ipairs({"head", "left", "right"}) do
                        local proxyEnt = proxies[part] and proxies[part].ent
                        if IsValid(proxyEnt) and proxyEnt:GetPos():DistToSqr(data.Pos) < 12000 then return false end
                    end
                end
            end
        end
    end
end)

-- ==================== BLOCK VISUAL EFFECTS (sparks, dust, impacts, etc.) ====================
hook.Add("PreEntityEmitEffect", "VRProxy_BlockEffects", function(ent, effect)
    if IsValid(ent) and ent:GetNWBool("isVRProxy", false) then
        return false -- Block sparks, impact effects, particles, etc.
    end
end)

-- ==================== SHADOW CONTROL IN THINK ====================
hook.Add("Tick", "VRProxy_PhysicsSync", function()
    if not cvEnableProxy:GetBool() then
        local plysToClean = {}
        for ply in pairs(vrProxies) do
            table.insert(plysToClean, ply)
        end

        for _, ply in ipairs(plysToClean) do
            if IsValid(ply) then RemoveVRProxies(ply) end
        end
        return
    end

    for _, ply in ipairs(player.GetHumans()) do
        if not vrmod.IsPlayerInVR(ply) then continue end
        if ply:GetMoveType() == MOVETYPE_NOCLIP then
            if vrProxies[ply] then RemoveVRProxies(ply) end
            continue
        end

        local proxies = vrProxies[ply]
        if not proxies or not proxies.head or not proxies.left or not proxies.right then
            if not ply:InVehicle() then
                RemoveVRProxies(ply)
                timer.Simple(1, function() if IsValid(ply) and vrmod.IsPlayerInVR(ply) and cvEnableProxy:GetBool() and ply:GetMoveType() ~= MOVETYPE_NOCLIP then SpawnVRProxies(ply) end end)
            end

            continue
        end

        if ply:InVehicle() then
            RemoveVRProxies(ply)
            continue
        end

        local function UpdateProxy(part)
            local proxyData = proxies[part]
            if not proxyData or not IsValid(proxyData.ent) or not IsValid(proxyData.phys) then return end
            local pos, ang
            if part == "head" then
                pos, ang = vrmod.GetHMDPose(ply)
            elseif part == "right" then
                pos, ang = vrmod.GetRightHandPose(ply)
            else
                pos, ang = vrmod.GetLeftHandPose(ply)
            end

            if not pos or not ang then return end
            local targetPos
            if part == "head" then
                targetPos = pos + ang:Up() * -5
            else
                targetPos = pos + ang:Forward() * (vrmod.DEFAULT_OFFSET or 0)
            end

            -- Anti-clip trace (keep this)
            local trace = util.TraceHull({
                start = pos,
                endpos = targetPos,
                mins = Vector(-4, -4, -4),
                maxs = Vector(4, 4, 4),
                filter = {ply, proxyData.ent},
                mask = MASK_SOLID
            })

            if trace.Hit then targetPos = trace.HitPos + trace.HitNormal * 3 end
            local phys = proxyData.phys
            phys:Wake()
            phys:ComputeShadowControl({
                secondstoarrive = 0.008, 
                pos = targetPos,
                angle = ang,
                maxangular = 6000,
                maxangulardamp = 6000,
                maxspeed = 85000, 
                maxspeeddamp = 4500,
                dampfactor = 0.75,
                teleportdistance = 400,
                deltatime = 0,
            })
        end

        UpdateProxy("head")
        UpdateProxy("right")
        UpdateProxy("left")
    end
end)

-- ==================== HOOKS ====================
hook.Add("PlayerSwitchWeapon", "VRProxy_UpdateCollisionOnWeaponSwitch", function(ply, oldWep, newWep) UpdateWeaponCollisionShape(ply, newWep) end)
hook.Add("VRMod_Pickup", "VRProxy_BlockPickup", function(ply, ent)
    local proxies = vrProxies[ply]
    if proxies and (proxies.right and ent == proxies.right.ent or proxies.left and ent == proxies.left.ent or proxies.head and ent == proxies.head.ent) then return false end
end)

hook.Add("VRMod_Start", "VRProxy_VRStart", SpawnVRProxies)
hook.Add("PlayerSpawn", "VRProxy_PlayerSpawn", function(ply) if vrmod.IsPlayerInVR(ply) then timer.Simple(0.1, function() SpawnVRProxies(ply) end) end end)
hook.Add("PlayerDeath", "VRProxy_PlayerDeath", RemoveVRProxies)
hook.Add("VRMod_Exit", "VRProxy_VREnd", RemoveVRProxies)
hook.Add("PlayerDisconnected", "VRProxy_Disconnect", function(ply) RemoveVRProxies(ply) end)
hook.Add("PreCleanupMap", "VRProxy_PreCleanup", function()
    local plys = {}
    for ply in pairs(vrProxies) do
        table.insert(plys, ply)
    end

    for _, ply in ipairs(plys) do
        RemoveVRProxies(ply)
    end
end)

hook.Add("PostCleanupMap", "VRProxy_PostCleanup", function()
    for _, ply in ipairs(player.GetHumans()) do
        if IsValid(ply) and vrmod.IsPlayerInVR(ply) then SpawnVRProxies(ply) end
    end
end)

-- AVR mag hooks
hook.Add("VRMod_Pickup", "VRProxy_AVRMagPickup", function(ply, ent)
    if not IsValid(ent) or not string.match(ent:GetClass(), "avrmag_") then return end
    local proxies = vrProxies[ply]
    if proxies and proxies.left and IsValid(proxies.left.ent) then proxies.left.ent:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE) end
end)

hook.Add("VRMod_Drop", "VRProxy_AVRMagDrop", function(ply, ent)
    if not IsValid(ent) or not string.match(ent:GetClass(), "avrmag_") then return end
    local proxies = vrProxies[ply]
    if proxies and proxies.left and IsValid(proxies.left.ent) then proxies.left.ent:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR) end
end)

-- ==================== Damage redirect (ONLY bullet damage triggers VR logic) ====================
-- G37 / W9: pure HandBulletLaw — hands Real for grabs; bullets filtered/redirected
hook.Add("EntityTakeDamage", "VRProxy_DamageRedirect", function(ent, dmginfo)
    if not IsValid(ent) then return end
    local data = proxyOwners[ent]
    if not data or not IsValid(data.ply) then return end
    local ply = data.ply
    local part = data.part
    local dmgType = dmginfo:GetDamageType()
    local attacker = dmginfo:GetAttacker()
    local damage = dmginfo:GetDamage()
    if damage <= 0 then return end
    local isSelfDamage = IsValid(attacker) and attacker == ply
    local U = vrmod.utils
    local isBulletDamage = (U and U.HandBulletLaw_IsBulletDamageType and U.HandBulletLaw_IsBulletDamageType(dmgType))
        or (bit.band(dmgType, DMG_BULLET) ~= 0 or bit.band(dmgType, DMG_BUCKSHOT) ~= 0)
    local law = U and U.HandBulletLaw_Decide and U.HandBulletLaw_Decide({
        part = part,
        is_bullet = isBulletDamage,
        is_self = isSelfDamage,
        damage = damage,
        solid_to_world = false,
        blocks_bullets_as_world = false,
    }) or nil
    if law then
        ent._handBulletLaw = law
    end
    -- Self-punch / non-bullet absorb via pure law
    local absorb = law and law.absorb
    if absorb == nil then
        absorb = (isSelfDamage and not isBulletDamage and (part == "left" or part == "right"))
            or (not isBulletDamage)
    end
    if absorb and not isBulletDamage then
        dmginfo:SetDamage(0)
        dmginfo:ScaleDamage(0)
        if isSelfDamage and (part == "left" or part == "right") then
            Log("Self-punch prevented on %s proxy of %s", part, ply:Nick())
        end
        return true
    end

    -- ONLY bullet damage uses the special VR proxy logic (head multiplier / hand damage + drop)
    if not isBulletDamage then
        dmginfo:SetDamage(0)
        dmginfo:ScaleDamage(0)
        return true
    end

    local scale = (U and U.HandBulletLaw_RedirectScale and U.HandBulletLaw_RedirectScale(part))
        or ((part == "head") and 10 or 0.45)
    local finalDamage = damage * scale
    if ply:Alive() and finalDamage > 0 then
        local newDmg = DamageInfo()
        newDmg:SetDamage(finalDamage)
        newDmg:SetAttacker(attacker or game.GetWorld())
        newDmg:SetInflictor(dmginfo:GetInflictor() or ent)
        newDmg:SetDamageType(dmgType)
        newDmg:SetDamagePosition(dmginfo:GetDamagePosition())
        newDmg:SetDamageForce(dmginfo:GetDamageForce() * (part == "head" and 1 or scale))
        ply:TakeDamageInfo(newDmg)
        if part == "head" then
            Log("HEAD BULLET HIT - multiplied %.2f → %.2f (instakill)", damage, finalDamage)
            Log("VR head proxy damaged → applied %.2f to %s (head)", finalDamage, ply:Nick())
        else
            Log("VR hand proxy damaged → applied %.2f (%.0f%% of %.2f) to %s (%s)", finalDamage, scale * 100, damage, ply:Nick(), part)
        end
    end

    local drop = law and law.drop_weapon
    if drop == nil then
        drop = (part == "left" or part == "right")
    end
    if drop and vrmod and type(vrmod.Drop) == "function" then
        local steamid = ply:SteamID()
        vrmod.Drop(steamid, part == "left")
        Log("Called vrmod.Drop because %s proxy was hit", part)
    end

    dmginfo:SetDamage(0)
    dmginfo:ScaleDamage(0)
    return true
end)

hook.Add("EntityFireBullets", "VRProxy_HeadshotBackup", function(ent, data)
    if not IsValid(ent) or not ent:IsPlayer() or not vrmod.IsPlayerInVR(ent) then return end
    local proxies = vrProxies[ent]
    if not proxies or not proxies.head or not IsValid(proxies.head.ent) then return end
    local head = proxies.head.ent
    local muzzle = data.Src or ent:GetShootPos()
    local headPos = head:GetPos()
    local dist = muzzle:Distance(headPos)
    if dist < 45 then
        local dirToHead = (headPos - muzzle):GetNormalized()
        local aimDir = data.Dir or ent:GetAimVector()
        local dot = dirToHead:Dot(aimDir)
        if dot > 0.3 then
            local dmginfo = DamageInfo()
            dmginfo:SetDamage((data.Damage or 25) * 10) -- ← 10x damage
            dmginfo:SetAttacker(ent)
            dmginfo:SetInflictor(ent:GetActiveWeapon() or ent)
            dmginfo:SetDamageType(DMG_BULLET)
            dmginfo:SetDamagePosition(headPos)
            head:TakeDamageInfo(dmginfo)
        end
    end
end)

-- ==================== VEHICLE COLLISION HANDLING ====================
function vrmod.SetVRProxiesNoCollide(ply, noCollide)
    if not IsValid(ply) or not vrProxies[ply] then return end
    local group = noCollide and COLLISION_GROUP_IN_VEHICLE or COLLISION_GROUP_WEAPON
    for _, part in ipairs({"head", "left", "right"}) do
        local proxyData = vrProxies[ply][part]
        if proxyData and IsValid(proxyData.ent) then
            proxyData.ent:SetCollisionGroup(group)
            Log("SetVRProxiesNoCollide → %s = %s", part, noCollide and "NO COLLIDE" or "NORMAL")
        end
    end
end

vrmod.SetVRHandsNoCollide = vrmod.SetVRProxiesNoCollide