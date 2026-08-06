g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}
CreateClientConVar("vrmod_steeringbone", "", true, false, "Custom steering bones. Syntax: car:NAME, moto:NAME, -NAME (remove), or just NAME. " .. "Example: car:SteeringWheel,moto:handle_custom,-steering_wheel")
local cachedBonePos, cachedBoneAng, cachedFrame = nil, nil, 0
--Vehicles/Glide
-- ====================== HELPER FUNCTIONS  ======================
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

local function BuildBoneMap(ent)
    local map = {}
    if not IsValid(ent) then return map end
    for i = 0, ent:GetBoneCount() - 1 do
        local orig = ent:GetBoneName(i)
        if orig then
            map[orig:lower()] = {
                id = i,
                original = orig
            }
        end
    end
    return map
end

local function GetApproximateBoneId(ent, keywords)
    if not IsValid(ent) then return nil, nil end
    for i = 0, ent:GetBoneCount() - 1 do
        local boneName = ent:GetBoneName(i)
        if boneName then
            local l = boneName:lower()
            if not (l:find("shock") or l:find("_shock")) then
                local norm = l:gsub("[_%-%.%s]", "")
                for _, kw in ipairs(keywords) do
                    local normKw = kw:lower():gsub("[_%-%.%s]", "")
                    if #normKw > 2 and norm:find(normKw, 1, true) then return i, boneName end
                end
            end
        end
    end
    return nil, nil
end

local function ScoreBone(boneName)
    if not boneName then return 0 end
    local l = boneName:lower()
    local score = 0
    if l:find("steer") then score = score + 20 end
    if l:find("handle") then score = score + 15 end
    if l:find("wheel") then score = score + 10 end
    if l:find("bar") and l:find("handle") then score = score + 5 end
    if l:find("driv") then score = score + 5 end
    if l:find("column") then score = score + 8 end
    if l:find("%.steer$") or l == "steer" then score = score + 10 end
    if l:find("shock") or l:find("_shock") then -- DROP SHOCK BONES
        return -9999
    end

    if l:find("suspension") or l:find("spring") then score = score - 30 end
    if l:find("axle") or l:find("brake") or l:find("tire") then score = score - 12 end
    if l == "wheel" or l:find("^wheel") and not l:find("steer") then score = score - 18 end
    return score
end

local function FilterBoneList(list, toRemove)
    if #toRemove == 0 then return list end
    local newList = {}
    for _, name in ipairs(list) do
        local keep = true
        for _, bad in ipairs(toRemove) do
            if name:lower() == bad then
                keep = false
                break
            end
        end

        if keep then table.insert(newList, name) end
    end
    return newList
end

-- ====================== MAIN FUNCTION ======================
function vrmod.utils.GetSteeringInfo(ply)
    if not IsValid(ply) or not ply:InVehicle() then return nil, nil, nil, nil end
    local glideVeh, vehicle
    if ply.GlideGetVehicle then
        glideVeh = ply:GlideGetVehicle()
        if IsValid(glideVeh) then
            vehicle = glideVeh
        else
            vehicle = ply:GetVehicle()
        end
    else
        vehicle = ply:GetVehicle()
    end

    if not IsValid(vehicle) then return nil, nil, nil, nil end
    local seatIndex = ply.GlideGetSeatIndex and ply:GlideGetSeatIndex() or 1
    local sitSeq = glideVeh and glideVeh.GetPlayerSitSequence and glideVeh:GetPlayerSitSequence(seatIndex)
    -- ====================== CUSTOM BONE CONVAR ======================
    local steeringConVar = GetConVar("vrmod_steeringbone")
    local customCar, customMoto, toRemove = {}, {}, {}
    if steeringConVar then
        local raw = steeringConVar:GetString() or ""
        for _, entry in ipairs(string.Split(raw, ",")) do
            entry = string.Trim(entry)
            if #entry == 0 then continue end
            local lower = entry:lower()
            if lower:StartWith("car:") then
                local name = string.Trim(entry:sub(5))
                if #name > 0 then table.insert(customCar, name) end
            elseif lower:StartWith("moto:") or lower:StartWith("motorcycle:") then
                local prefixLen = lower:StartWith("moto:") and 6 or 12
                local name = string.Trim(entry:sub(prefixLen))
                if #name > 0 then table.insert(customMoto, name) end
            elseif lower:StartWith("remove:") or lower:StartWith("-") then
                local prefixLen = lower:StartWith("remove:") and 8 or 2
                local name = string.Trim(entry:sub(prefixLen))
                if #name > 0 then table.insert(toRemove, name:lower()) end
            else
                table.insert(customCar, entry)
                table.insert(customMoto, entry)
            end
        end
    end

    -- ====================== BONE PRIORITY LISTS ======================
    local bonePriority = {
        motorcycle = {
            names = {"handlebars", "Handlebars", "handlebar", "Handlebar", "HandleBars", "handles", "Handles", "handle", "Handle", "Airboat.Steer", "airboat.steer", "AirboatSteer", "steering_handle", "SteeringHandle", "steer", "Steer", "steerw_bone", "SteerW_Bone"},
            type = "motorcycle"
        },
        car = {
            names = {"steering_wheel", "Steering_Wheel", "SteeringWheel", "steeringwheel", "steer_wheel", "Steer_Wheel", "SteerWheel", "steerwheel", "Rig_Buggy.Steer_Wheel", "car.steer_wheel", "steer", "Steer", "steerw_bone", "SteerW_Bone", "driving", "Driving", "driving_wheel", "DrivingWheel", "Steering", "steering"},
            type = "car"
        }
    }

    for _, name in ipairs(customCar) do
        table.insert(bonePriority.car.names, 1, name)
    end

    for _, name in ipairs(customMoto) do
        table.insert(bonePriority.motorcycle.names, 1, name)
    end

    bonePriority.car.names = FilterBoneList(bonePriority.car.names, toRemove)
    bonePriority.motorcycle.names = FilterBoneList(bonePriority.motorcycle.names, toRemove)
    -- ====================== SEARCH ORDER ======================
    local searchOrder
    if IsValid(glideVeh) then
        local vType = glideVeh.VehicleType
        if vType == Glide.VEHICLE_TYPE.MOTORCYCLE or sitSeq == "drive_airboat" then
            searchOrder = {bonePriority.motorcycle, bonePriority.car}
        elseif vType == Glide.VEHICLE_TYPE.CAR then
            searchOrder = {bonePriority.car, bonePriority.motorcycle}
        else
            searchOrder = {bonePriority.motorcycle, bonePriority.car}
        end
    else
        searchOrder = {bonePriority.car, bonePriority.motorcycle}
    end

    -- ====================== MAIN SEARCH ======================
    local candidates = {}
    if IsValid(glideVeh) then table.insert(candidates, glideVeh) end
    table.insert(candidates, vehicle)
    local boneId, boneType, boneName
    for _, candidate in ipairs(candidates) do
        local boneMap = BuildBoneMap(candidate)
        for _, searchEntry in ipairs(searchOrder) do
            for _, name in ipairs(searchEntry.names) do
                local match = boneMap[name:lower()]
                if match then
                    boneId, boneType, boneName = match.id, searchEntry.type, match.original
                    break
                end
            end

            if not boneId then
                local id, origName = GetApproximateBoneId(candidate, searchEntry.names)
                if id then boneId, boneType, boneName = id, searchEntry.type, origName end
            end

            if boneId then break end
        end

        if boneId then break end
    end

    -- ====================== FALLBACK SCANNER (with shock drop) ======================
    if not boneId then
        for _, candidate in ipairs(candidates) do
            if IsValid(candidate) then
                local num = candidate:GetBoneCount()
                local bestScore, bestId, bestName = 0, nil, nil
                for i = 0, num - 1 do
                    local nm = candidate:GetBoneName(i)
                    local l = nm:lower()
                    if l:find("shock") or l:find("_shock") then
                        continue -- DROP SHOCK BONES COMPLETELY
                    end

                    local sc = ScoreBone(nm)
                    if sc > bestScore then
                        bestScore = sc
                        bestId = i
                        bestName = nm
                    end
                end

                if bestId and bestScore >= 10 then
                    boneId = bestId
                    boneName = bestName
                    boneType = IsValid(glideVeh) and (glideVeh.VehicleType == Glide.VEHICLE_TYPE.MOTORCYCLE and "motorcycle" or "car") or "car"
                    break
                end
            end
        end
    end

    if boneId ~= nil and type(boneId) ~= "number" then boneId = nil end
    -- ====================== RETURN ======================
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

function vrmod.utils.GetVehicleBonePosition(vehicle, boneId)
    if not IsValid(vehicle) or not boneId then return nil, nil end
    -- Cache once per render frame — Glide GetBonePosition was uncached and
    -- SteeringGripTransform ran twice (left+right PreRender) → VR frame lag.
    local frameKey = (g_VR and g_VR.stereoFrame) or FrameNumber()
    if cachedFrame == frameKey and cachedBonePos then
        return cachedBonePos, cachedBoneAng
    end
    local pos, ang
    if g_VR.vehicle and g_VR.vehicle.glide then
        pos, ang = vehicle:GetBonePosition(boneId)
    else
        local m = vehicle:GetBoneMatrix(boneId)
        if m then
            pos, ang = m:GetTranslation(), m:GetAngles()
        end
    end
    if not pos then return nil, nil end
    cachedBonePos, cachedBoneAng = pos, ang
    cachedFrame = frameKey
    return cachedBonePos, cachedBoneAng
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
        -- VR: cheap path — no 50k-unit aim traces (those stalled VR frames via CalcView)
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
                -- Soft distance only — skip brush TraceLine every CalcView in VR
                local fraction = self.distanceFraction or 1
                offset = (self.shakeOffset or Vector()) + baseOffset * fraction
            end

            self.position = pivot + angles:Forward() * offset[1] + angles:Right() * offset[2] + angles:Up() * offset[3]
            -- Aim: HMD forward only (no world TraceLine) — weapons still use VR tracking
            self.lastAimPos = hmdPos + hmdAng:Forward() * 4096
            self.lastAimEntity = NULL
            self.lastAimPosDistanceFromEyes = 4096
            self.lastAimPosAnglesFromEyes = hmdAng
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
            local setAng = self.lastAimPosAnglesFromEyes or g_VR and g_VR.view and g_VR.view.angles or self.angles or Angle(0, 0, 0)
            cmd:SetViewAngles(setAng)
            cmd:SetUpMove(math.Clamp(self.lastAimPosDistanceFromEyes or 0, 0, 10000))
            return
        end

        -- Non-VR
        self:_OrigCreateMove(cmd)
    end
end

function vrmod.utils.IsInChair(ply)
    if not IsValid(ply) then return false end
    local veh = ply:GetVehicle()
    if not IsValid(veh) then return false end
    return veh:GetClass() == "prop_vehicle_prisoner_pod"
end

function vrmod.utils.inRealVehicle(ply)
    if not IsValid(ply) or not ply:InVehicle() then return false end
    return not vrmod.utils.IsInChair(ply)
end