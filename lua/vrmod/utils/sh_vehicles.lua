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
    if not IsValid(ply) or not ply:InVehicle() then return nil, nil, nil, nil end
    local vehicle = ply:GetVehicle()
    if not IsValid(vehicle) then return nil, nil, nil, nil end
    local glideVeh = vrmod.utils.GetGlideVehicle(vehicle)
    local seatIndex = ply.GlideGetSeatIndex and ply:GlideGetSeatIndex() or 1
    local sitSeq = glideVeh and glideVeh.GetPlayerSitSequence and glideVeh:GetPlayerSitSequence(seatIndex)
    -- Define bone search priorities
    local bonePriority = {
        motorcycle = {
            names = {"handlebars", "handles", "Airboat.Steer", "handle", "steer", "steerw_bone"},
            type = "motorcycle"
        },
        car = {
            names = {"steering_wheel", "steering", "Rig_Buggy.Steer_Wheel", "car.steer_wheel", "steer", "steerw_bone"},
            type = "car"
        }
    }

    -- Decide search order based on Glide type
    local searchOrder
    if IsValid(glideVeh) then
        local vType = glideVeh.VehicleType
        if vType == Glide.VEHICLE_TYPE.MOTORCYCLE or sitSeq == "drive_airboat" then
            searchOrder = {bonePriority.motorcycle, bonePriority.car}
        elseif vType == Glide.VEHICLE_TYPE.CAR then
            searchOrder = {bonePriority.car, bonePriority.motorcycle}
        else
            -- For other Glide types, just try both
            searchOrder = {bonePriority.motorcycle, bonePriority.car}
        end
    else
        -- No Glide, default to car-first
        searchOrder = {bonePriority.car, bonePriority.motorcycle}
    end

    -- Search bones
    local candidates = {IsValid(glideVeh) and glideVeh or vehicle}
    local boneId, boneType, boneName
    for _, candidate in ipairs(candidates) do
        for _, entry in ipairs(searchOrder) do
            for _, name in ipairs(entry.names) do
                local id = candidate:LookupBone(name)
                if id then
                    boneId, boneType, boneName = id, entry.type, name
                    break
                end
            end

            if not boneId then
                local id, approxName = GetApproximateBoneId(candidate, entry.names)
                if id then boneId, boneType, boneName = id, entry.type, approxName end
            end

            if boneId then break end
        end

        if boneId then break end
    end

    -- Glide type still takes precedence in naming
    if IsValid(glideVeh) then
        local vType = glideVeh.VehicleType
        if vType == Glide.VEHICLE_TYPE.MOTORCYCLE or sitSeq == "drive_airboat" then
            return glideVeh, boneId, "motorcycle", true, boneName
        elseif vType == Glide.VEHICLE_TYPE.BOAT then
            return glideVeh, boneId, boneType or "boat", true, boneName
        elseif vType == Glide.VEHICLE_TYPE.CAR then
            return glideVeh, boneId, "car", true, boneName
        elseif vType == Glide.VEHICLE_TYPE.PLANE or vType == Glide.VEHICLE_TYPE.HELICOPTER then
            return glideVeh, boneId, "aircraft", true, boneName
        elseif vType == Glide.VEHICLE_TYPE.TANK then
            return glideVeh, boneId, "tank", true, boneName
        end
    end

    if boneId then return vehicle, boneId, boneType, false, boneName end
    return vehicle, nil, "unknown", false, nil
end

function vrmod.utils.PatchGlideCamera()
    local Camera = Glide.Camera
    if not Camera then return end
    local Config = Glide.Config
    if not Config then vrmod.logger.Warn("[Glide] Warning: Glide.Config not found, using fallback values") end
    -- Store original functions
    if not Camera._OrigCalcView then Camera._OrigCalcView = Camera.CalcView end
    if not Camera._OrigCreateMove then Camera._OrigCreateMove = Camera.CreateMove end
    -- Override CalcView
    function Camera:CalcView()
        if not self.isActive then return end
        local vehicle = self.vehicle
        if not IsValid(vehicle) then return end
        local user = self.user
        -- VR guard: ensure vrmod and g_VR.view exist
        if vrmod and vrmod.IsPlayerInVR and vrmod.IsPlayerInVR(user) and g_VR and g_VR.view then
            local hmdPos = g_VR.view.origin or user:EyePos()
            local hmdAng = g_VR.view.angles or user:EyeAngles()
            local pivot, offset
            local angles = hmdAng
            if self.isInFirstPerson then
                local localEyePos = vehicle:WorldToLocal(hmdPos)
                local localPos = vehicle:GetFirstPersonOffset(self.seatIndex, localEyePos)
                pivot = vehicle:LocalToWorld(localPos)
                offset = Vector()
            else
                angles = hmdAng + (vehicle.CameraAngleOffset or Angle(0, 0, 0))
                pivot = vehicle:LocalToWorld((vehicle.CameraCenterOffset or Vector()) + (vehicle.CameraTrailerOffset or Vector()) * (self.trailerDistanceFraction or 0))
                local cfgCamDist = Config and Config.cameraDistance or 100
                local cfgCamHeight = Config and Config.cameraHeight or 50
                local baseOffset = (vehicle.CameraOffset or Vector(-100, 0, 50)) * Vector(cfgCamDist * (1 + (self.trailerDistanceFraction or 0) * (vehicle.CameraTrailerDistanceMultiplier or 0)), 1, cfgCamHeight)
                local endPos = pivot + angles:Forward() * baseOffset[1] + angles:Right() * baseOffset[2] + angles:Up() * baseOffset[3]
                local offsetDir = endPos - pivot
                local offsetLen = offsetDir:Length()
                if offsetLen > 0 then
                    offsetDir:Normalize()
                else
                    offsetDir = angles:Forward() -- arbitrary fallback
                    offsetLen = 1
                end

                -- Local trace table; do NOT rely on global traceData/traceResult
                local tr = util.TraceLine({
                    start = pivot,
                    endpos = endPos + offsetDir * 10,
                    mask = 16395, -- MASK_SOLID_BRUSHONLY
                    filter = {vehicle}
                })

                local fraction = self.distanceFraction or 1
                if tr.Hit then
                    fraction = tr.Fraction or fraction
                    if fraction < (self.distanceFraction or 1) then self.distanceFraction = fraction end
                end

                offset = (self.shakeOffset or Vector()) + baseOffset * fraction
            end

            self.position = pivot + angles:Forward() * offset[1] + angles:Right() * offset[2] + angles:Up() * offset[3]
            -- Aim trace from player's eyes using HMD forward
            local trAim = util.TraceLine({
                start = user:EyePos(),
                endpos = user:EyePos() + hmdAng:Forward() * 50000,
                filter = {user, vehicle}
            })

            self.lastAimPos = trAim.HitPos
            self.lastAimEntity = trAim.Entity
            local aimDir = trAim.HitPos - user:EyePos()
            self.lastAimPosDistanceFromEyes = aimDir:Length()
            if self.lastAimPosDistanceFromEyes > 0 then
                aimDir:Normalize()
                self.lastAimPosAnglesFromEyes = aimDir:Angle()
            else
                self.lastAimPosAnglesFromEyes = hmdAng
            end

            -- Keep player's eye angles synced to HMD for weapon aim
            if user.SetEyeAngles then user:SetEyeAngles(hmdAng) end
            return {
                origin = self.position,
                angles = angles + (self.punchAngle or Angle(0, 0, 0)),
                fov = self.fov,
                drawviewer = not self.isInFirstPerson
            }
        end
        -- Non-VR or fallback: call original
        return self:_OrigCalcView()
    end

    function Camera:CreateMove(cmd)
        if self.isActive and vrmod and vrmod.IsPlayerInVR and vrmod.IsPlayerInVR(self.user) then
            -- Prefer the cached eye-relative aim angles; fall back to HMD or stored angles if missing.
            local setAng = self.lastAimPosAnglesFromEyes or g_VR and g_VR.view and g_VR.view.angles or self.angles or Angle(0, 0, 0)
            cmd:SetViewAngles(setAng)
            cmd:SetUpMove(math.Clamp(self.lastAimPosDistanceFromEyes or 0, 0, 10000))
            return
        end

        -- Non-VR
        self:_OrigCreateMove(cmd)
    end
end