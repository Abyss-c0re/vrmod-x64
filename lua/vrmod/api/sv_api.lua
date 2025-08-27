g_VR = g_VR or {}
vrmod = vrmod or {}
if SERVER then
    vrmod.HandVelocityCache = vrmod.HandVelocityCache or {}
    function vrmod.NetReceiveLimited(msgName, maxCountPerSec, maxLen, callback)
        local msgCounts = {}
        net.Receive(msgName, function(len, ply)
            local t = msgCounts[ply] or {
                count = 0,
                time = 0
            }

            msgCounts[ply], t.count = t, t.count + 1
            if SysTime() - t.time >= 1 then t.count, t.time = 1, SysTime() end
            if t.count > maxCountPerSec or len > maxLen then return end
            callback(len, ply)
        end)
    end

    function vrmod.IsPlayerInVR(ply)
        if not IsValid(ply) then return end
        return g_VR[ply:SteamID()] ~= nil
    end

    function vrmod.UsingEmptyHands(ply)
        if not IsValid(ply) then return end
        local wep = ply:GetActiveWeapon()
        return IsValid(wep) and wep:GetClass() == "weapon_vrmod_empty" or false
    end

    function vrmod.GetHeldEntity(ply, hand)
        if not IsValid(ply) or not (hand == "left" or hand == "right") then return nil end
        local sid = ply:SteamID()
        local data = g_VR[sid] and g_VR[sid].heldItems
        if not data then return nil end
        local slot = hand == "left" and 1 or 2
        local info = data[slot]
        if info and IsValid(info.ent) then return info.ent end
        return nil
    end

    local function UpdateWorldPoses(ply, playerTable)
        if not IsValid(ply) or not playerTable then return end
        if not playerTable.latestFrameWorld or playerTable.latestFrameWorld.ts ~= playerTable.latestFrame.ts then
            playerTable.latestFrameWorld = playerTable.latestFrameWorld or {}
            local lf = playerTable.latestFrame
            local lfw = playerTable.latestFrameWorld
            if not lf then return end
            -- Timestamp
            lfw.ts = lf.ts
            -- Base world reference
            local refPos, refAng = ply:GetPos(), ply:InVehicle() and ply:GetVehicle():GetAngles() or Angle()
            -- Base world conversions
            local rawHMDPos, rawHMDAng = LocalToWorld(lf.hmdPos or Vector(), lf.hmdAng or Angle(), refPos, refAng)
            local rawLeftPos, rawLeftAng = LocalToWorld(lf.lefthandPos or Vector(), lf.lefthandAng or Angle(), refPos, refAng)
            local rawRightPos, rawRightAng = LocalToWorld(lf.righthandPos or Vector(), lf.righthandAng or Angle(), refPos, refAng)
            -- Store updated positions
            lfw.hmdPos, lfw.hmdAng = rawHMDPos, rawHMDAng
            lfw.lefthandPos, lfw.lefthandAng = rawLeftPos, rawLeftAng
            lfw.righthandPos, lfw.righthandAng = rawRightPos, rawRightAng
            -- Velocity cache
            local sid = ply:SteamID()
            local cache = vrmod.HandVelocityCache[sid]
            if not cache then
                cache = {}
                vrmod.HandVelocityCache[sid] = cache
            end

            -- Ensure all required fields exist (patch old caches)
            cache.leftLastPos = cache.leftLastPos or lfw.lefthandPos
            cache.rightLastPos = cache.rightLastPos or lfw.righthandPos
            cache.hmdLastPos = cache.hmdLastPos or lfw.hmdPos
            cache.leftLastAng = cache.leftLastAng or lfw.lefthandAng
            cache.rightLastAng = cache.rightLastAng or lfw.righthandAng
            cache.hmdLastAng = cache.hmdLastAng or lfw.hmdAng
            cache.leftLastVelPos = cache.leftLastVelPos or lfw.lefthandPos
            cache.rightLastVelPos = cache.rightLastVelPos or lfw.righthandPos
            cache.hmdLastVelPos = cache.hmdLastVelPos or lfw.hmdPos
            cache.leftLastVelAng = cache.leftLastVelAng or lfw.lefthandAng
            cache.rightLastVelAng = cache.rightLastVelAng or lfw.righthandAng
            cache.hmdLastVelAng = cache.hmdLastVelAng or lfw.hmdAng
            cache.leftVel = cache.leftVel or Vector()
            cache.rightVel = cache.rightVel or Vector()
            cache.hmdVel = cache.hmdVel or Vector()
            cache.leftAngVel = cache.leftAngVel or Angle()
            cache.rightAngVel = cache.rightAngVel or Angle()
            cache.hmdAngVel = cache.hmdAngVel or Angle()
            cache.lastTs = cache.lastTs or lfw.ts
            cache.lastVelUpdateTs = cache.lastVelUpdateTs or lfw.ts
            cache.avgDt = cache.avgDt or 0.011 -- assume ~90Hz start
            -- Delta times
            local dt = lfw.ts - cache.lastTs
            local totalDt = lfw.ts - cache.lastVelUpdateTs
            -- Exponential moving average of frame time
            if dt > 0 then cache.avgDt = cache.avgDt * 0.9 + dt * 0.1 end
            -- Adaptive minimum dt: 2× avg frame time (at least 10ms)
            local minDt = math.max(0.01, cache.avgDt * 2)
            if dt > 0 and totalDt >= minDt then
                -- Angle difference helper
                local function AngDiff(a, b)
                    return Angle(math.AngleDifference(a.p, b.p), math.AngleDifference(a.y, b.y), math.AngleDifference(a.r, b.r))
                end

                -- Compute velocities over accumulated interval
                cache.leftVel = (lfw.lefthandPos - cache.leftLastVelPos) / totalDt
                cache.rightVel = (lfw.righthandPos - cache.rightLastVelPos) / totalDt
                cache.hmdVel = (lfw.hmdPos - cache.hmdLastVelPos) / totalDt
                cache.leftAngVel = AngDiff(lfw.lefthandAng, cache.leftLastVelAng) / totalDt
                cache.rightAngVel = AngDiff(lfw.righthandAng, cache.rightLastVelAng) / totalDt
                cache.hmdAngVel = AngDiff(lfw.hmdAng, cache.hmdLastVelAng) / totalDt
                -- Reset accumulation references
                cache.leftLastVelPos = lfw.lefthandPos
                cache.rightLastVelPos = lfw.righthandPos
                cache.hmdLastVelPos = lfw.hmdPos
                cache.leftLastVelAng = lfw.lefthandAng
                cache.rightLastVelAng = lfw.righthandAng
                cache.hmdLastVelAng = lfw.hmdAng
                cache.lastVelUpdateTs = lfw.ts
            end

            -- Always update frame-to-frame references
            cache.leftLastPos = lfw.lefthandPos
            cache.rightLastPos = lfw.righthandPos
            cache.hmdLastPos = lfw.hmdPos
            cache.leftLastAng = lfw.lefthandAng
            cache.rightLastAng = lfw.righthandAng
            cache.hmdLastAng = lfw.hmdAng
            cache.lastTs = lfw.ts
        end
    end

    function vrmod.GetHMDPos(ply)
        if not IsValid(ply) then return end
        local playerTable = g_VR[ply:SteamID()]
        if not (playerTable and playerTable.latestFrame) then return Vector() end
        UpdateWorldPoses(ply, playerTable)
        return playerTable.latestFrameWorld.hmdPos
    end

    function vrmod.GetHMDAng(ply)
        if not IsValid(ply) then return end
        local playerTable = g_VR[ply:SteamID()]
        if not (playerTable and playerTable.latestFrame) then return Angle() end
        UpdateWorldPoses(ply, playerTable)
        return playerTable.latestFrameWorld.hmdAng
    end

    function vrmod.GetHMDPose(ply)
        if not IsValid(ply) then return end
        local playerTable = g_VR[ply:SteamID()]
        if not (playerTable and playerTable.latestFrame) then return Vector(), Angle() end
        UpdateWorldPoses(ply, playerTable)
        return playerTable.latestFrameWorld.hmdPos, playerTable.latestFrameWorld.hmdAng
    end

    -- HMD
    function vrmod.GetHMDVelocity(ply)
        if not IsValid(ply) then return Vector() end
        local sid = ply:SteamID()
        local cache = vrmod.HandVelocityCache[sid]
        if not cache then
            UpdateWorldPoses(ply, g_VR[sid])
            cache = vrmod.HandVelocityCache[sid]
        end
        return cache and cache.hmdVel or Vector()
    end

    function vrmod.GetHMDAngularVelocity(ply)
        if not IsValid(ply) then return Angle() end
        local sid = ply:SteamID()
        local cache = vrmod.HandVelocityCache[sid]
        if not cache then
            UpdateWorldPoses(ply, g_VR[sid])
            cache = vrmod.HandVelocityCache[sid]
        end
        return cache and cache.hmdAngVel or Angle()
    end

    -- Left hand
    function vrmod.GetLeftHandPos(ply)
        if not IsValid(ply) then return Vector() end
        local t = g_VR[ply:SteamID()]
        if not (t and t.latestFrame) then return Vector() end
        UpdateWorldPoses(ply, t)
        return t.latestFrameWorld.lefthandPos
    end

    function vrmod.GetLeftHandAng(ply)
        if not IsValid(ply) then return Angle() end
        local t = g_VR[ply:SteamID()]
        if not (t and t.latestFrame) then return Angle() end
        UpdateWorldPoses(ply, t)
        return t.latestFrameWorld.lefthandAng
    end

    function vrmod.GetLeftHandPose(ply)
        if not IsValid(ply) then return Vector(), Angle() end
        local t = g_VR[ply:SteamID()]
        if not (t and t.latestFrame) then return Vector(), Angle() end
        UpdateWorldPoses(ply, t)
        return t.latestFrameWorld.lefthandPos, t.latestFrameWorld.lefthandAng
    end

    function vrmod.GetLeftHandVelocity(ply)
        if not IsValid(ply) then return Vector() end
        local sid = ply:SteamID()
        local cache = vrmod.HandVelocityCache[sid]
        if not cache then
            UpdateWorldPoses(ply, g_VR[sid])
            cache = vrmod.HandVelocityCache[sid]
        end
        return cache and cache.leftVel or Vector()
    end

    function vrmod.GetLeftHandAngularVelocity(ply)
        if not IsValid(ply) then return Angle() end
        local sid = ply:SteamID()
        local cache = vrmod.HandVelocityCache[sid]
        if not cache then
            UpdateWorldPoses(ply, g_VR[sid])
            cache = vrmod.HandVelocityCache[sid]
        end
        return cache and cache.leftAngVel or Angle()
    end

    function vrmod.GetLeftHandVelocityRelative(ply)
        if not IsValid(ply) then return Vector() end
        return vrmod.GetLeftHandVelocity(ply) - vrmod.GetHMDVelocity(ply)
    end

    function vrmod.GetLeftHandAngularVelocityRelative(ply)
        if not IsValid(ply) then return Angle() end
        return vrmod.GetLeftHandAngularVelocity(ply) - vrmod.GetHMDAngularVelocity(ply)
    end

    -- Right hand
    function vrmod.GetRightHandPos(ply)
        if not IsValid(ply) then return Vector() end
        local t = g_VR[ply:SteamID()]
        if not (t and t.latestFrame) then return Vector() end
        UpdateWorldPoses(ply, t)
        return t.latestFrameWorld.righthandPos
    end

    function vrmod.GetRightHandAng(ply)
        if not IsValid(ply) then return Angle() end
        local t = g_VR[ply:SteamID()]
        if not (t and t.latestFrame) then return Angle() end
        UpdateWorldPoses(ply, t)
        return t.latestFrameWorld.righthandAng
    end

    function vrmod.GetRightHandPose(ply)
        if not IsValid(ply) then return Vector(), Angle() end
        local t = g_VR[ply:SteamID()]
        if not (t and t.latestFrame) then return Vector(), Angle() end
        UpdateWorldPoses(ply, t)
        return t.latestFrameWorld.righthandPos, t.latestFrameWorld.righthandAng
    end

    function vrmod.GetRightHandVelocity(ply)
        if not IsValid(ply) then return Vector() end
        local sid = ply:SteamID()
        local cache = vrmod.HandVelocityCache[sid]
        if not cache then
            UpdateWorldPoses(ply, g_VR[sid])
            cache = vrmod.HandVelocityCache[sid]
        end
        return cache and cache.rightVel or Vector()
    end

    function vrmod.GetRightHandAngularVelocity(ply)
        if not IsValid(ply) then return Angle() end
        local sid = ply:SteamID()
        local cache = vrmod.HandVelocityCache[sid]
        if not cache then
            UpdateWorldPoses(ply, g_VR[sid])
            cache = vrmod.HandVelocityCache[sid]
        end
        return cache and cache.rightAngVel or Angle()
    end

    function vrmod.GetRightHandVelocityRelative(ply)
        if not IsValid(ply) then return Vector() end
        return vrmod.GetRightHandVelocity(ply) - vrmod.GetHMDVelocity(ply)
    end

    function vrmod.GetRightHandAngularVelocityRelative(ply)
        if not IsValid(ply) then return Angle() end
        return vrmod.GetRightHandAngularVelocity(ply) - vrmod.GetHMDAngularVelocity(ply)
    end

    -- Gesture
    function vrmod.GetPullGestureStrength(ply, hand, targetPos)
        if not IsValid(ply) then return 0 end
        local handPos = hand == "left" and vrmod.GetLeftHandPos(ply) or vrmod.GetRightHandPos(ply)
        local relVel = hand == "left" and vrmod.GetLeftHandVelocityRelative(ply) or vrmod.GetRightHandVelocityRelative(ply)
        local pullDir = (targetPos - handPos):GetNormalized()
        return relVel:Dot(pullDir)
    end
end