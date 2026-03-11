g_VR = g_VR or {}
vrmod = vrmod or {}
local EmptyHandsWeapons = {
    ["weapon_vrmod_empty"] = true,
    ["vr_spooderman"] = true,
    -- add more here if needed
}
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
        local wep = ply and ply:GetActiveWeapon() or LocalPlayer():GetActiveWeapon()
        if not IsValid(wep) then return false end
        return EmptyHandsWeapons[wep:GetClass()] or false
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
        -- Only update if timestamp changed (or first time)
        if not playerTable.latestFrameWorld or playerTable.latestFrameWorld.ts ~= playerTable.latestFrame.ts then
            playerTable.latestFrameWorld = playerTable.latestFrameWorld or {}
            local lf = playerTable.latestFrame
            local lfw = playerTable.latestFrameWorld
            if not lf then return end
            -- Timestamp
            lfw.ts = lf.ts
            -- Base world reference (player position + vehicle angles if applicable)
            local refPos, refAng = ply:GetPos(), ply:InVehicle() and ply:GetVehicle():GetAngles() or Angle()
            -- Convert local → world space for all tracked parts
            lfw.hmdPos, lfw.hmdAng = LocalToWorld(lf.hmdPos or Vector(), lf.hmdAng or Angle(), refPos, refAng)
            lfw.lefthandPos, lfw.lefthandAng = LocalToWorld(lf.lefthandPos or Vector(), lf.lefthandAng or Angle(), refPos, refAng)
            lfw.righthandPos, lfw.righthandAng = LocalToWorld(lf.righthandPos or Vector(), lf.righthandAng or Angle(), refPos, refAng)
            -- Waist / feet (only if present in the frame)
            if lf.waistPos then lfw.waistPos, lfw.waistAng = LocalToWorld(lf.waistPos, lf.waistAng or Angle(), refPos, refAng) end
            if lf.leftfootPos then lfw.leftfootPos, lfw.leftfootAng = LocalToWorld(lf.leftfootPos, lf.leftfootAng or Angle(), refPos, refAng) end
            if lf.rightfootPos then lfw.rightfootPos, lfw.rightfootAng = LocalToWorld(lf.rightfootPos, lf.rightfootAng or Angle(), refPos, refAng) end
            -- Velocity cache setup
            local sid = ply:SteamID()
            local cache = vrmod.HandVelocityCache[sid]
            if not cache then
                cache = {}
                vrmod.HandVelocityCache[sid] = cache
            end

            -- Initialize all tracking points (use current world values as starting point)
            cache.hmdLastPos = cache.hmdLastPos or lfw.hmdPos
            cache.hmdLastAng = cache.hmdLastAng or lfw.hmdAng
            cache.lefthandLastPos = cache.lefthandLastPos or lfw.lefthandPos
            cache.lefthandLastAng = cache.lefthandLastAng or lfw.lefthandAng
            cache.righthandLastPos = cache.righthandLastPos or lfw.righthandPos
            cache.righthandLastAng = cache.righthandLastAng or lfw.righthandAng
            cache.hmdLastVelPos = cache.hmdLastVelPos or lfw.hmdPos
            cache.lefthandLastVelPos = cache.lefthandLastVelPos or lfw.lefthandPos
            cache.righthandLastVelPos = cache.righthandLastVelPos or lfw.righthandPos
            cache.hmdLastVelAng = cache.hmdLastVelAng or lfw.hmdAng
            cache.lefthandLastVelAng = cache.lefthandLastVelAng or lfw.lefthandAng
            cache.righthandLastVelAng = cache.righthandLastVelAng or lfw.righthandAng
            cache.hmdVel = cache.hmdVel or Vector()
            cache.lefthandVel = cache.lefthandVel or Vector()
            cache.righthandVel = cache.righthandVel or Vector()
            cache.hmdAngVel = cache.hmdAngVel or Angle()
            cache.lefthandAngVel = cache.lefthandAngVel or Angle()
            cache.righthandAngVel = cache.righthandAngVel or Angle()
            -- Full-body additions
            cache.waistLastPos = cache.waistLastPos or lfw.waistPos or Vector()
            cache.waistLastAng = cache.waistLastAng or lfw.waistAng or Angle()
            cache.leftfootLastPos = cache.leftfootLastPos or lfw.leftfootPos or Vector()
            cache.leftfootLastAng = cache.leftfootLastAng or lfw.leftfootAng or Angle()
            cache.rightfootLastPos = cache.rightfootLastPos or lfw.rightfootPos or Vector()
            cache.rightfootLastAng = cache.rightfootLastAng or lfw.rightfootAng or Angle()
            cache.waistLastVelPos = cache.waistLastVelPos or lfw.waistPos or Vector()
            cache.leftfootLastVelPos = cache.leftfootLastVelPos or lfw.leftfootPos or Vector()
            cache.rightfootLastVelPos = cache.rightfootLastVelPos or lfw.rightfootPos or Vector()
            cache.waistLastVelAng = cache.waistLastVelAng or lfw.waistAng or Angle()
            cache.leftfootLastVelAng = cache.leftfootLastVelAng or lfw.leftfootAng or Angle()
            cache.rightfootLastVelAng = cache.rightfootLastVelAng or lfw.rightfootAng or Angle()
            cache.waistVel = cache.waistVel or Vector()
            cache.leftfootVel = cache.leftfootVel or Vector()
            cache.rightfootVel = cache.rightfootVel or Vector()
            cache.waistAngVel = cache.waistAngVel or Angle()
            cache.leftfootAngVel = cache.leftfootAngVel or Angle()
            cache.rightfootAngVel = cache.rightfootAngVel or Angle()
            cache.lastTs = cache.lastTs or lfw.ts
            cache.lastVelUpdateTs = cache.lastVelUpdateTs or lfw.ts
            cache.avgDt = cache.avgDt or 0.011 -- ~90 Hz default
            -- Delta times
            local dt = lfw.ts - cache.lastTs
            local totalDt = lfw.ts - cache.lastVelUpdateTs
            -- Exponential moving average of frame time
            if dt > 0 then cache.avgDt = cache.avgDt * 0.9 + dt * 0.1 end
            -- Adaptive minimum dt for velocity calculation (~2 frames)
            local minDt = math.max(0.01, cache.avgDt * 2)
            if dt > 0 and totalDt >= minDt then
                -- Helper to compute angular difference
                local function AngDiff(a, b)
                    return Angle(math.AngleDifference(a.p, b.p), math.AngleDifference(a.y, b.y), math.AngleDifference(a.r, b.r))
                end

                -- Linear and angular velocities (only compute when data exists)
                cache.hmdVel = (lfw.hmdPos - cache.hmdLastVelPos) / totalDt
                cache.lefthandVel = (lfw.lefthandPos - cache.lefthandLastVelPos) / totalDt
                cache.righthandVel = (lfw.righthandPos - cache.righthandLastVelPos) / totalDt
                cache.hmdAngVel = AngDiff(lfw.hmdAng, cache.hmdLastVelAng) / totalDt
                cache.lefthandAngVel = AngDiff(lfw.lefthandAng, cache.lefthandLastVelAng) / totalDt
                cache.righthandAngVel = AngDiff(lfw.righthandAng, cache.righthandLastVelAng) / totalDt
                if lfw.waistPos then
                    cache.waistVel = (lfw.waistPos - cache.waistLastVelPos) / totalDt
                    cache.waistAngVel = AngDiff(lfw.waistAng, cache.waistLastVelAng) / totalDt
                end

                if lfw.leftfootPos then
                    cache.leftfootVel = (lfw.leftfootPos - cache.leftfootLastVelPos) / totalDt
                    cache.leftfootAngVel = AngDiff(lfw.leftfootAng, cache.leftfootLastVelAng) / totalDt
                end

                if lfw.rightfootPos then
                    cache.rightfootVel = (lfw.rightfootPos - cache.rightfootLastVelPos) / totalDt
                    cache.rightfootAngVel = AngDiff(lfw.rightfootAng, cache.rightfootLastVelAng) / totalDt
                end

                -- Reset accumulation points
                cache.hmdLastVelPos = lfw.hmdPos
                cache.lefthandLastVelPos = lfw.lefthandPos
                cache.righthandLastVelPos = lfw.righthandPos
                cache.hmdLastVelAng = lfw.hmdAng
                cache.lefthandLastVelAng = lfw.lefthandAng
                cache.righthandLastVelAng = lfw.righthandAng
                if lfw.waistPos then
                    cache.waistLastVelPos = lfw.waistPos
                    cache.waistLastVelAng = lfw.waistAng
                end

                if lfw.leftfootPos then
                    cache.leftfootLastVelPos = lfw.leftfootPos
                    cache.leftfootLastVelAng = lfw.leftfootAng
                end

                if lfw.rightfootPos then
                    cache.rightfootLastVelPos = lfw.rightfootPos
                    cache.rightfootLastVelAng = lfw.rightfootAng
                end

                cache.lastVelUpdateTs = lfw.ts
            end

            -- Always update frame-to-frame last known positions/angles
            cache.hmdLastPos = lfw.hmdPos
            cache.lefthandLastPos = lfw.lefthandPos
            cache.righthandLastPos = lfw.righthandPos
            cache.hmdLastAng = lfw.hmdAng
            cache.lefthandLastAng = lfw.lefthandAng
            cache.righthandLastAng = lfw.righthandAng
            cache.waistLastPos = lfw.waistPos or cache.waistLastPos
            cache.leftfootLastPos = lfw.leftfootPos or cache.leftfootLastPos
            cache.rightfootLastPos = lfw.rightfootPos or cache.rightfootLastPos
            cache.waistLastAng = lfw.waistAng or cache.waistLastAng
            cache.leftfootLastAng = lfw.leftfootAng or cache.leftfootLastAng
            cache.rightfootLastAng = lfw.rightfootAng or cache.rightfootLastAng
            cache.lastTs = lfw.ts
            ------------------------------------------------------------------
            -- Optional: Apply simple extrapolation / prediction (~1 frame ahead)
            ------------------------------------------------------------------
            local predictionHorizon = cache.avgDt -- usually ~0.011 s
            local function PredictPose(pos, ang, vel, angVel, dt)
                if not pos or not ang or not vel or not angVel then return pos, ang end
                local predictedPos = pos + vel * dt
                local predictedAng = Angle(ang.p + angVel.p * dt, ang.y + angVel.y * dt, ang.r + angVel.r * dt)
                return predictedPos, predictedAng
            end

            lfw.hmdPos, lfw.hmdAng = PredictPose(lfw.hmdPos, lfw.hmdAng, cache.hmdVel, cache.hmdAngVel, predictionHorizon)
            lfw.lefthandPos, lfw.lefthandAng = PredictPose(lfw.lefthandPos, lfw.lefthandAng, cache.lefthandVel, cache.lefthandAngVel, predictionHorizon)
            lfw.righthandPos, lfw.righthandAng = PredictPose(lfw.righthandPos, lfw.righthandAng, cache.righthandVel, cache.righthandAngVel, predictionHorizon)
            if lfw.waistPos then lfw.waistPos, lfw.waistAng = PredictPose(lfw.waistPos, lfw.waistAng, cache.waistVel, cache.waistAngVel, predictionHorizon) end
            if lfw.leftfootPos then lfw.leftfootPos, lfw.leftfootAng = PredictPose(lfw.leftfootPos, lfw.leftfootAng, cache.leftfootVel, cache.leftfootAngVel, predictionHorizon) end
            if lfw.rightfootPos then lfw.rightfootPos, lfw.rightfootAng = PredictPose(lfw.rightfootPos, lfw.rightfootAng, cache.rightfootVel, cache.rightfootAngVel, predictionHorizon) end
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

    -- Waist
    function vrmod.GetWaistPos(ply)
        if not IsValid(ply) then return Vector() end
        local t = g_VR[ply:SteamID()]
        if not (t and t.latestFrame) then return Vector() end
        UpdateWorldPoses(ply, t)
        return t.latestFrameWorld.waistPos or Vector()
    end

    function vrmod.GetWaistAng(ply)
        if not IsValid(ply) then return Angle() end
        local t = g_VR[ply:SteamID()]
        if not (t and t.latestFrame) then return Angle() end
        UpdateWorldPoses(ply, t)
        return t.latestFrameWorld.waistAng or Angle()
    end

    function vrmod.GetWaistPose(ply)
        if not IsValid(ply) then return Vector(), Angle() end
        local t = g_VR[ply:SteamID()]
        if not (t and t.latestFrame) then return Vector(), Angle() end
        UpdateWorldPoses(ply, t)
        return t.latestFrameWorld.waistPos or Vector(), t.latestFrameWorld.waistAng or Angle()
    end

    function vrmod.GetWaistVelocity(ply)
        if not IsValid(ply) then return Vector() end
        local sid = ply:SteamID()
        local cache = vrmod.HandVelocityCache[sid]
        if not cache then
            UpdateWorldPoses(ply, g_VR[sid])
            cache = vrmod.HandVelocityCache[sid]
        end
        return cache and cache.waistVel or Vector()
    end

    function vrmod.GetWaistAngularVelocity(ply)
        if not IsValid(ply) then return Angle() end
        local sid = ply:SteamID()
        local cache = vrmod.HandVelocityCache[sid]
        if not cache then
            UpdateWorldPoses(ply, g_VR[sid])
            cache = vrmod.HandVelocityCache[sid]
        end
        return cache and cache.waistAngVel or Angle()
    end

    function vrmod.GetWaistVelocityRelative(ply)
        if not IsValid(ply) then return Vector() end
        return vrmod.GetWaistVelocity(ply) - vrmod.GetHMDVelocity(ply)
    end

    -- Left Foot
    function vrmod.GetLeftFootPos(ply)
        if not IsValid(ply) then return Vector() end
        local t = g_VR[ply:SteamID()]
        if not (t and t.latestFrame) then return Vector() end
        UpdateWorldPoses(ply, t)
        return t.latestFrameWorld.leftfootPos or Vector()
    end

    function vrmod.GetLeftFootAng(ply)
        if not IsValid(ply) then return Angle() end
        local t = g_VR[ply:SteamID()]
        if not (t and t.latestFrame) then return Angle() end
        UpdateWorldPoses(ply, t)
        return t.latestFrameWorld.leftfootAng or Angle()
    end

    function vrmod.GetLeftFootPose(ply)
        if not IsValid(ply) then return Vector(), Angle() end
        local t = g_VR[ply:SteamID()]
        if not (t and t.latestFrame) then return Vector(), Angle() end
        UpdateWorldPoses(ply, t)
        return t.latestFrameWorld.leftfootPos or Vector(), t.latestFrameWorld.leftfootAng or Angle()
    end

    function vrmod.GetLeftFootVelocity(ply)
        if not IsValid(ply) then return Vector() end
        local sid = ply:SteamID()
        local cache = vrmod.HandVelocityCache[sid]
        if not cache then
            UpdateWorldPoses(ply, g_VR[sid])
            cache = vrmod.HandVelocityCache[sid]
        end
        return cache and cache.leftfootVel or Vector()
    end

    function vrmod.GetLeftFootAngularVelocity(ply)
        if not IsValid(ply) then return Angle() end
        local sid = ply:SteamID()
        local cache = vrmod.HandVelocityCache[sid]
        if not cache then
            UpdateWorldPoses(ply, g_VR[sid])
            cache = vrmod.HandVelocityCache[sid]
        end
        return cache and cache.leftfootAngVel or Angle()
    end

    function vrmod.GetLeftFootVelocityRelative(ply)
        if not IsValid(ply) then return Vector() end
        return vrmod.GetLeftFootVelocity(ply) - vrmod.GetHMDVelocity(ply)
    end

    function vrmod.GetLeftFootVelocities(ply)
        if not IsValid(ply) then return Vector(), Angle(), Vector() end
        local sid = ply:SteamID()
        local cache = vrmod.HandVelocityCache[sid] or {}
        local vel = cache.leftfootVel or Vector()
        local angvel = cache.leftfootAngVel or Angle()
        return vel, angvel, vel - vrmod.GetHMDVelocity(ply)
    end

    -- Right Foot (symmetric)
    function vrmod.GetRightFootPos(ply)
        if not IsValid(ply) then return Vector() end
        local t = g_VR[ply:SteamID()]
        if not (t and t.latestFrame) then return Vector() end
        UpdateWorldPoses(ply, t)
        return t.latestFrameWorld.rightfootPos or Vector()
    end

    function vrmod.GetRightFootAng(ply)
        if not IsValid(ply) then return Angle() end
        local t = g_VR[ply:SteamID()]
        if not (t and t.latestFrame) then return Angle() end
        UpdateWorldPoses(ply, t)
        return t.latestFrameWorld.rightfootAng or Angle()
    end

    function vrmod.GetRightFootPose(ply)
        if not IsValid(ply) then return Vector(), Angle() end
        local t = g_VR[ply:SteamID()]
        if not (t and t.latestFrame) then return Vector(), Angle() end
        UpdateWorldPoses(ply, t)
        return t.latestFrameWorld.rightfootPos or Vector(), t.latestFrameWorld.rightfootAng or Angle()
    end

    function vrmod.GetRightFootVelocity(ply)
        if not IsValid(ply) then return Vector() end
        local sid = ply:SteamID()
        local cache = vrmod.HandVelocityCache[sid]
        if not cache then
            UpdateWorldPoses(ply, g_VR[sid])
            cache = vrmod.HandVelocityCache[sid]
        end
        return cache and cache.rightfootVel or Vector()
    end

    function vrmod.GetRightFootAngularVelocity(ply)
        if not IsValid(ply) then return Angle() end
        local sid = ply:SteamID()
        local cache = vrmod.HandVelocityCache[sid]
        if not cache then
            UpdateWorldPoses(ply, g_VR[sid])
            cache = vrmod.HandVelocityCache[sid]
        end
        return cache and cache.rightfootAngVel or Angle()
    end

    function vrmod.GetRightFootVelocityRelative(ply)
        if not IsValid(ply) then return Vector() end
        return vrmod.GetRightFootVelocity(ply) - vrmod.GetHMDVelocity(ply)
    end

    function vrmod.GetRightFootVelocities(ply)
        if not IsValid(ply) then return Vector(), Angle(), Vector() end
        local sid = ply:SteamID()
        local cache = vrmod.HandVelocityCache[sid] or {}
        local vel = cache.rightfootVel or Vector()
        local angvel = cache.rightfootAngVel or Angle()
        return vel, angvel, vel - vrmod.GetHMDVelocity(ply)
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