g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}
local cachedBonePos, cachedBoneAng, cachedFrame = nil, nil, 0
--Vehicles/Glide
local function GetApproximateBoneId(vehicle, targetNames)
    if not IsValid(vehicle) then return nil end
    local boneCount = vehicle:GetBoneCount()
    if boneCount <= 0 then return nil end
    for i = 0, boneCount - 1 do
        local boneName = vehicle:GetBoneName(i)
        if boneName then
            for _, target in ipairs(targetNames) do
                if string.find(string.lower(boneName), string.lower(target), 1, true) then return i end
            end
        end
    end
    return nil
end

function vrmod.utils.GetGlideVehicle(vehicle)
    if not IsValid(vehicle) then return nil end
    local parent = vehicle:GetParent()
    if not IsValid(parent) or not parent.IsGlideVehicle then return nil end
    return parent
end

function vrmod.utils.GetVehicleBonePosition(vehicle, boneId)
    if not IsValid(vehicle) or not boneId then return nil, nil end
    if g_VR.vehicle.glide then return vehicle:GetBonePosition(boneId) end
    if cachedFrame == FrameNumber() then return cachedBonePos, cachedBoneAng end
    local m = vehicle:GetBoneMatrix(boneId)
    if not m then return nil, nil end
    cachedBonePos, cachedBoneAng = m:GetTranslation(), m:GetAngles()
    cachedFrame = FrameNumber()
    return cachedBonePos, cachedBoneAng
end

function vrmod.utils.GetSteeringInfo(ply)
    if not IsValid(ply) or not ply:InVehicle() then return nil, nil, nil end
    local vehicle = ply:GetVehicle()
    if not IsValid(vehicle) then return nil, nil, nil end
    local glideVeh = vrmod.utils.GetGlideVehicle(vehicle)
    local seatIndex = ply.GlideGetSeatIndex and ply:GlideGetSeatIndex() or 1
    local sitSeq = glideVeh and glideVeh.GetPlayerSitSequence and glideVeh:GetPlayerSitSequence(seatIndex)
    local bonePriority = {
        {
            names = {"handlebars", "handles", "Airboat.Steer", "handle"},
            type = "motorcycle"
        },
        {
            names = {"steering_wheel", "steering", "Rig_Buggy.Steer_Wheel", "car.steer_wheel", "steer"},
            type = "car"
        }
    }

    -- Find steering bone (always attempt, needed for pose alignment)
    local boneId, boneType
    local candidates = {}
    if IsValid(glideVeh) then
        table.insert(candidates, glideVeh)
    else
        table.insert(candidates, vehicle)
    end

    for _, candidate in ipairs(candidates) do
        for _, entry in ipairs(bonePriority) do
            for _, name in ipairs(entry.names) do
                local id = candidate:LookupBone(name)
                if id then
                    boneId, boneType = id, entry.type
                    break
                end
            end

            if not boneId then
                local id = GetApproximateBoneId(candidate, entry.names)
                if id then boneId, boneType = id, entry.type end
            end

            if boneId then break end
        end

        if boneId then break end
    end

    -- Glide type takes precedence over boneType
    if IsValid(glideVeh) then
        local vType = glideVeh.VehicleType
        if vType == Glide.VEHICLE_TYPE.MOTORCYCLE or sitSeq == "drive_airboat" then
            return glideVeh, boneId, "motorcycle", true
        elseif vType == Glide.VEHICLE_TYPE.BOAT then
            return glideVeh, boneId, "boat", true
        elseif vType == Glide.VEHICLE_TYPE.CAR then
            return glideVeh, boneId, "car", true
        elseif vType == Glide.VEHICLE_TYPE.PLANE or vType == Glide.VEHICLE_TYPE.HELICOPTER then
            return glideVeh, boneId, "aircraft", true
        elseif vType == Glide.VEHICLE_TYPE.TANK then
            return glideVeh, boneId, "tank", true
        end
    end

    -- If no Glide type, fall back to bone-derived type (if any)
    if boneId then return vehicle, boneId, boneType, false end
    -- Otherwise, nothing known
    return vehicle, nil, "unknown", false
end

function vrmod.utils.PatchGlideCamera()
    local Camera = Glide.Camera
    if not Camera then return end
    local Config = Glide.Config
    if not Config then print("[VRMod] Warning: Glide.Config not found, using fallback values") end
    -- Store original functions
    if not Camera._OrigCalcView then Camera._OrigCalcView = Camera.CalcView end
    if not Camera._OrigCreateMove then Camera._OrigCreateMove = Camera.CreateMove end
    -- Override CalcView
    function Camera:CalcView()
        local vehicle = self.vehicle
        if not IsValid(vehicle) then return end
        local user = self.user
        if vrmod and vrmod.IsPlayerInVR and vrmod.IsPlayerInVR(user) then
            -- VR mode: Use g_VR.view for camera position and orientation
            local hmdPos, hmdAng = g_VR.view.origin, g_VR.view.angles
            if self.isInFirstPerson then
                -- First-person: Align camera with HMD pose relative to vehicle
                local localEyePos = vehicle:WorldToLocal(hmdPos)
                local localPos = vehicle:GetFirstPersonOffset(self.seatIndex, localEyePos)
                self.origin = vehicle:LocalToWorld(localPos)
                self.angles = hmdAng
            else
                -- Third-person: Position camera behind vehicle, adjusted by HMD orientation
                local fraction = self.traceFraction
                -- Fallback values if Config is nil
                local cameraDistance = Config and Config.cameraDistance or 100
                local cameraHeight = Config and Config.cameraHeight or 50
                local offset = self.shakeOffset + vehicle.CameraOffset * Vector(cameraDistance, 1, cameraHeight) * fraction
                local startPos = vehicle:LocalToWorld(vehicle.CameraCenterOffset + vehicle.CameraTrailerOffset * self.trailerFraction)
                -- Use HMD angles instead of mouse-based angles
                self.angles = hmdAng + vehicle.CameraAngleOffset
                local endPos = startPos + self.angles:Forward() * offset[1] * (1 + self.trailerFraction * vehicle.CameraTrailerDistanceMultiplier) + self.angles:Right() * offset[2] + self.angles:Up() * offset[3]
                local dir = endPos - startPos
                dir:Normalize()
                -- Check for wall collisions
                local tr = util.TraceLine({
                    start = startPos,
                    endpos = endPos + dir * 10,
                    mask = 16395 -- MASK_SOLID_BRUSHONLY
                })

                if tr.Hit then
                    endPos = tr.HitPos - dir * 10
                    if tr.Fraction < fraction then self.traceFraction = tr.Fraction end
                end

                self.origin = endPos
            end

            -- Update aim position and entity using HMD angles
            local tr = util.TraceLine({
                start = user:GetShootPos(), -- Start from weapon shoot position
                endpos = user:GetShootPos() + hmdAng:Forward() * 50000,
                filter = {user, vehicle}
            })

            self.lastAimEntity = tr.Entity
            self.lastAimPos = tr.HitPos
            self.viewAngles = hmdAng
            -- Sync player's EyeAngles with HMD for weapon aiming
            user:SetEyeAngles(hmdAng)
            return {
                origin = self.origin,
                angles = self.angles + self.punchAngle,
                fov = self.fov,
                drawviewer = not self.isInFirstPerson
            }
        else
            -- Non-VR mode: Call original CalcView
            return self:_OrigCalcView()
        end
    end

    -- Override CreateMove
    function Camera:CreateMove(cmd)
        if vrmod and vrmod.IsPlayerInVR and vrmod.IsPlayerInVR(self.user) then
            -- VR mode: Set command angles to HMD angles for weapon firing
            cmd:SetViewAngles(g_VR.view.angles)
            return
        end

        -- Non-VR mode: Call original CreateMove
        self:_OrigCreateMove(cmd)
    end

    print("[VRMod] Patched Glide.Camera for VR support")
end