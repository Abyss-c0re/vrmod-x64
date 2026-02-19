local requiredModuleVersion = nil
if system.IsLinux() then
    requiredModuleVersion = 23
else
    requiredModuleVersion = 21
end

local latestModuleVersion = 23
g_VR = g_VR or {}
vrmod = vrmod or {}

local convars = vrmod.GetConvars()
if CLIENT then
    g_VR.net = g_VR.net or {}
    g_VR.viewModelInfo = g_VR.viewModelInfo or {}
    g_VR.locomotionOptions = g_VR.locomotionOptions or {}
    g_VR.menuItems = g_VR.menuItems or {}
    -- Helper to get player VR data
    local function getPlayerVRData(ply)
        local sid = ply and ply:SteamID() or LocalPlayer():SteamID()
        return g_VR.net[sid]
    end

    function vrmod.GetStartupError()
        local error = nil
        local moduleFile = nil
        if g_VR.moduleVersion == 0 then
            if system.IsLinux() then
                moduleFile = "lua/bin/gmcl_vrmod_linux64.dll"
            else
                moduleFile = "lua/bin/gmcl_vrmod_win64.dll"
            end

            if not file.Exists(moduleFile, "GAME") then
                error = "Module not installed. Read the workshop description for instructions.\n"
            else
                error = "Failed to load module\n"
            end
        elseif g_VR.moduleVersion < requiredModuleVersion then
            error = "Module update required.\nRun the module installer to update.\nIf you don't have the installer anymore you can re-download it from the workshop description.\n\nInstalled: v" .. g_VR.moduleVersion .. "\nRequired: v" .. requiredModuleVersion
        elseif g_VR.active then
            error = "Already running"
        elseif g_VR.moduleVersion > latestModuleVersion then
            error = "Unknown module version\n\nInstalled: v" .. g_VR.moduleVersion .. "\nRequired: v" .. requiredModuleVersion .. "\n\nMake sure the addon is up to date.\nAddon version: " .. vrmod.GetVersion()
        elseif VRMOD_IsHMDPresent and not VRMOD_IsHMDPresent() then
            error = "VR headset not detected\n"
        end
        return error
    end

    function vrmod.GetModuleVersion()
        return g_VR.moduleVersion, requiredModuleVersion, latestModuleVersion
    end

    function vrmod.IsPlayerInVR(ply)
        return getPlayerVRData(ply) ~= nil
    end

    function vrmod.UsingEmptyHands(ply)
        local wep = ply and ply:GetActiveWeapon() or LocalPlayer():GetActiveWeapon()
        return IsValid(wep) and wep:GetClass() == "weapon_vrmod_empty" or false
    end

    function vrmod.GetHeldEntity(ply, hand)
        if not IsValid(ply) then return nil end
        if hand ~= "left" and hand ~= "right" then return nil end
        if hand == "left" then
            return g_VR.heldEntityLeft
        else
            return g_VR.heldEntityRight
        end
        return nil
    end

    function vrmod.GetHMDPos(ply)
        local t = getPlayerVRData(ply)
        if not t or not g_VR.tracking or not g_VR.tracking.hmd then return Vector() end
        return g_VR.tracking.hmd.pos or Vector()
    end

    function vrmod.GetHMDAng(ply)
        local t = getPlayerVRData(ply)
        if not t or not g_VR.tracking or not g_VR.tracking.hmd then return Angle() end
        return g_VR.tracking.hmd.ang or Angle()
    end

    function vrmod.GetHMDPose(ply)
        local t = getPlayerVRData(ply)
        if not t or not g_VR.tracking or not g_VR.tracking.hmd then return Vector(), Angle() end
        return g_VR.tracking.hmd.pos or Vector(), g_VR.tracking.hmd.ang or Angle()
    end

    function vrmod.GetHMDVelocity()
        return g_VR.threePoints and g_VR.tracking.hmd.vel or Vector()
    end

    function vrmod.GetHMDAngularVelocity()
        return g_VR.threePoints and g_VR.tracking.hmd.angvel or Angle()
    end

    function vrmod.GetHMDVelocities()
        if g_VR.threePoints then return g_VR.tracking.hmd.vel or Vector(), g_VR.tracking.hmd.angvel or Angle() end
        return Vector(), Angle()
    end

    function vrmod.GetLeftHandPos(ply)
        local t = getPlayerVRData(ply)
        if not t or not g_VR.tracking or not g_VR.tracking.pose_lefthand then return Vector() end
        return g_VR.tracking.pose_lefthand.pos or Vector()
    end

    function vrmod.GetLeftHandAng(ply)
        local t = getPlayerVRData(ply)
        if not t or not g_VR.tracking or not g_VR.tracking.pose_lefthand then return Angle() end
        return g_VR.tracking.pose_lefthand.ang or Angle()
    end

    function vrmod.GetLeftHandPose(ply)
        local t = getPlayerVRData(ply)
        if not t or not g_VR.tracking or not g_VR.tracking.pose_lefthand then return Vector(), Angle() end
        return g_VR.tracking.pose_lefthand.pos or Vector(), g_VR.tracking.pose_lefthand.ang or Angle()
    end

    function vrmod.GetLeftHandVelocity()
        return g_VR.threePoints and g_VR.tracking.pose_lefthand.vel or Vector()
    end

    function vrmod.GetLeftHandAngularVelocity()
        return g_VR.threePoints and g_VR.tracking.pose_lefthand.angvel or Angle()
    end

    function vrmod.GetLeftHandVelocityRelative()
        if not g_VR.threePoints or not g_VR.tracking or not g_VR.tracking.pose_lefthand or not g_VR.tracking.hmd then return Vector() end
        return (g_VR.tracking.pose_lefthand.vel or Vector()) - (g_VR.tracking.hmd.vel or Vector())
    end

    function vrmod.GetLeftHandVelocities()
        if g_VR.threePoints and g_VR.tracking and g_VR.tracking.pose_lefthand then return g_VR.tracking.pose_lefthand.vel or Vector(), g_VR.tracking.pose_lefthand.angvel or Angle(), vrmod.GetLeftHandVelocityRelative() end
        return Vector(), Angle(), Vector()
    end

    function vrmod.GetRightHandPos(ply)
        local t = getPlayerVRData(ply)
        if not t or not g_VR.tracking or not g_VR.tracking.pose_righthand then return Vector() end
        return g_VR.tracking.pose_righthand.pos or Vector()
    end

    function vrmod.GetRightHandAng(ply)
        local t = getPlayerVRData(ply)
        if not t or not g_VR.tracking or not g_VR.tracking.pose_righthand then return Angle() end
        return g_VR.tracking.pose_righthand.ang or Angle()
    end

    function vrmod.GetRightHandPose(ply)
        local t = getPlayerVRData(ply)
        if not t or not g_VR.tracking or not g_VR.tracking.pose_righthand then return Vector(), Angle() end
        return g_VR.tracking.pose_righthand.pos or Vector(), g_VR.tracking.pose_righthand.ang or Angle()
    end

    function vrmod.GetRightHandVelocity()
        return g_VR.threePoints and g_VR.tracking.pose_righthand.vel or Vector()
    end

    function vrmod.GetRightHandAngularVelocity()
        return g_VR.threePoints and g_VR.tracking.pose_righthand.angvel or Angle()
    end

    function vrmod.GetRightHandVelocityRelative()
        if not g_VR.threePoints or not g_VR.tracking or not g_VR.tracking.pose_righthand or not g_VR.tracking.hmd then return Vector() end
        return (g_VR.tracking.pose_righthand.vel or Vector()) - (g_VR.tracking.hmd.vel or Vector())
    end

    function vrmod.GetRightHandVelocities()
        if g_VR.threePoints and g_VR.tracking and g_VR.tracking.pose_righthand then return g_VR.tracking.pose_righthand.vel or Vector(), g_VR.tracking.pose_righthand.angvel or Angle(), vrmod.GetRightHandVelocityRelative() end
        return Vector(), Angle(), Vector()
    end

    -- smoothing helper
    local function SmoothValue(oldVal, newVal, factor)
        if not oldVal then return newVal end
        if not factor or factor <= 0 then return newVal end
        if oldVal.Lerp then
            -- Vector or Angle
            return LerpVector(factor, oldVal, newVal)
        else
            -- Fallback for numbers
            return Lerp(factor, oldVal, newVal)
        end
    end

    function vrmod.SetLeftHandPose(pos, ang, smoothing)
        local ply = LocalPlayer()
        local netFrame = g_VR.net and g_VR.net[ply:SteamID()] and g_VR.net[ply:SteamID()].lerpedFrame
        if not netFrame then return end
        -- Apply smoothing
        netFrame.lefthandPos = SmoothValue(netFrame.lefthandPos, pos, smoothing or 0)
        netFrame.lefthandAng = SmoothValue(netFrame.lefthandAng, ang, smoothing or 0)
    end

    function vrmod.SetRightHandPose(pos, ang, smoothing)
        local ply = LocalPlayer()
        local netFrame = g_VR.net and g_VR.net[ply:SteamID()] and g_VR.net[ply:SteamID()].lerpedFrame
        if not netFrame then return end
        -- Apply smoothing
        netFrame.righthandPos = SmoothValue(netFrame.righthandPos, pos, smoothing or 0)
        netFrame.righthandAng = SmoothValue(netFrame.righthandAng, ang, smoothing or 0)
        -- Call utils update if available
        --if vrmod.utils then vrmod.utils.UpdateViewModelPos(netFrame.righthandPos, netFrame.righthandAng) end
    end

    local function HandleFingerAngles(mode, hand, state, tbl)
        local isGetter = mode == "get"
        local isDefault = mode == "get_default"
        local sourceTable = isDefault and (state == "open" and g_VR.defaultOpenHandAngles or g_VR.defaultClosedHandAngles) or state == "open" and g_VR.openHandAngles or g_VR.closedHandAngles
        local offset = hand == "right" and 15 or 0
        if isGetter or isDefault then
            local r = {}
            for i = 1, 15 do
                r[i] = sourceTable[i + offset]
            end
            return r
        else -- Setter
            local t = table.Copy(sourceTable)
            for i = 1, 15 do
                t[i + offset] = tbl[i]
            end

            if state == "open" then
                g_VR.openHandAngles = t
            else
                g_VR.closedHandAngles = t
            end
        end
    end

    -- Getter functions
    function vrmod.GetLeftHandOpenFingerAngles()
        return HandleFingerAngles("get", "left", "open")
    end

    function vrmod.GetLeftHandClosedFingerAngles()
        return HandleFingerAngles("get", "left", "closed")
    end

    function vrmod.GetRightHandOpenFingerAngles()
        return HandleFingerAngles("get", "right", "open")
    end

    function vrmod.GetRightHandClosedFingerAngles()
        return HandleFingerAngles("get", "right", "closed")
    end

    -- Setter functions
    function vrmod.SetLeftHandOpenFingerAngles(tbl)
        HandleFingerAngles("set", "left", "open", tbl)
    end

    function vrmod.SetLeftHandClosedFingerAngles(tbl)
        HandleFingerAngles("set", "left", "closed", tbl)
    end

    function vrmod.SetRightHandOpenFingerAngles(tbl)
        HandleFingerAngles("set", "right", "open", tbl)
    end

    function vrmod.SetRightHandClosedFingerAngles(tbl)
        HandleFingerAngles("set", "right", "closed", tbl)
    end

    -- Default getter functions
    function vrmod.GetDefaultLeftHandOpenFingerAngles()
        return HandleFingerAngles("get_default", "left", "open")
    end

    function vrmod.GetDefaultLeftHandClosedFingerAngles()
        return HandleFingerAngles("get_default", "left", "closed")
    end

    function vrmod.GetDefaultRightHandOpenFingerAngles()
        return HandleFingerAngles("get_default", "right", "open")
    end

    function vrmod.GetDefaultRightHandClosedFingerAngles()
        return HandleFingerAngles("get_default", "right", "closed")
    end

    local function GetFingerAnglesFromModel(modelName, sequenceNumber)
        sequenceNumber = sequenceNumber or 0
        local pm = convars.vrmod_floatinghands:GetBool() and "models/weapons/c_arms.mdl" or LocalPlayer():GetModel()
        local pmdl = ClientsideModel(pm)
        pmdl:SetupBones()
        local tmdl = ClientsideModel(modelName)
        tmdl:ResetSequence(sequenceNumber)
        tmdl:SetupBones()
        local tmp = {"0", "01", "02", "1", "11", "12", "2", "21", "22", "3", "31", "32", "4", "41", "42"}
        local r = {}
        for i = 1, 30 do
            r[i] = Angle()
            local fingerBoneName = "ValveBiped.Bip01_" .. (i < 16 and "L" or "R") .. "_Finger" .. tmp[i - (i < 16 and 0 or 15)]
            local pfinger = pmdl:LookupBone(fingerBoneName) or -1
            local tfinger = tmdl:LookupBone(fingerBoneName) or -1
            if pmdl:GetBoneMatrix(pfinger) then
                local _, pmoffset = WorldToLocal(Vector(0, 0, 0), pmdl:GetBoneMatrix(pfinger):GetAngles(), Vector(0, 0, 0), pmdl:GetBoneMatrix(pmdl:GetBoneParent(pfinger)):GetAngles())
                if tfinger ~= -1 then
                    local _, tmoffset = WorldToLocal(Vector(0, 0, 0), tmdl:GetBoneMatrix(tfinger):GetAngles(), Vector(0, 0, 0), tmdl:GetBoneMatrix(tmdl:GetBoneParent(tfinger)):GetAngles())
                    r[i] = tmoffset - pmoffset
                end
            end
        end

        pmdl:Remove()
        tmdl:Remove()
        return r
    end

    function vrmod.GetLeftHandFingerAnglesFromModel(modelName, sequenceNumber)
        local angles = GetFingerAnglesFromModel(modelName, sequenceNumber)
        local r = {}
        for i = 1, 15 do
            r[i] = angles[i]
        end
        return r
    end

    function vrmod.GetRightHandFingerAnglesFromModel(modelName, sequenceNumber)
        local angles = GetFingerAnglesFromModel(modelName, sequenceNumber)
        local r = {}
        for i = 1, 15 do
            r[i] = angles[15 + i]
        end
        return r
    end

    local function GetRelativeBonePoseFromModel(modelName, sequenceNumber, boneName, refBoneName)
        sequenceNumber = sequenceNumber or 0
        local ent = ClientsideModel(modelName)
        ent:ResetSequence(sequenceNumber)
        ent:SetupBones()
        local mtx, mtxRef = ent:GetBoneMatrix(ent:LookupBone(boneName)), ent:GetBoneMatrix(refBoneName and ent:LookupBone(refBoneName) or 0)
        local relativePos, relativeAng = WorldToLocal(mtx:GetTranslation(), mtx:GetAngles(), mtxRef:GetTranslation(), mtxRef:GetAngles())
        ent:Remove()
        return relativePos, relativeAng
    end

    function vrmod.GetLeftHandPoseFromModel(modelName, sequenceNumber, refBoneName)
        return GetRelativeBonePoseFromModel(modelName, sequenceNumber, "ValveBiped.Bip01_L_Hand", refBoneName)
    end

    function vrmod.GetRightHandPoseFromModel(modelName, sequenceNumber, refBoneName)
        return GetRelativeBonePoseFromModel(modelName, sequenceNumber, "ValveBiped.Bip01_R_Hand", refBoneName)
    end

    function vrmod.GetLerpedFingerAngles(fraction, from, to)
        local r = {}
        for i = 1, 15 do
            r[i] = LerpAngle(fraction, from[i], to[i])
        end
        return r
    end

    function vrmod.GetLerpedHandPose(fraction, fromPos, fromAng, toPos, toAng)
        return LerpVector(fraction, fromPos, toPos), LerpAngle(fraction, fromAng, toAng)
    end

    function vrmod.GetInput(name)
        return g_VR.input[name]
    end

    vrmod.MenuCreate = function() end
    vrmod.MenuClose = function() end
    vrmod.MenuExists = function() end
    vrmod.MenuRenderStart = function() end
    vrmod.MenuRenderEnd = function() end
    vrmod.MenuCursorPos = function() return g_VR.menuCursorX, g_VR.menuCursorY end
    vrmod.MenuFocused = function() return g_VR.menuFocus end
    timer.Simple(0, function()
        vrmod.MenuCreate = VRUtilMenuOpen
        vrmod.MenuClose = VRUtilMenuClose
        vrmod.MenuExists = VRUtilIsMenuOpen
        vrmod.MenuRenderStart = VRUtilMenuRenderStart
        vrmod.MenuRenderEnd = VRUtilMenuRenderEnd
    end)

    function vrmod.SetViewModelOffsetForWeaponClass(classname, pos, ang)
        g_VR.viewModelInfo[classname] = g_VR.viewModelInfo[classname] or {}
        g_VR.viewModelInfo[classname].offsetPos = pos
        g_VR.viewModelInfo[classname].offsetAng = ang
    end

    function vrmod.SetViewModelFixMuzzle(classname, bool)
        g_VR.viewModelInfo[classname] = g_VR.viewModelInfo[classname] or {}
        g_VR.viewModelInfo[classname].wrongMuzzleAng = bool
    end

    function vrmod.SetViewModelNoLaser(classname, bool)
        g_VR.viewModelInfo[classname] = g_VR.viewModelInfo[classname] or {}
        g_VR.viewModelInfo[classname].noLaser = bool
    end

    vrmod.AddCallbackedConvar("vrmod_locomotion", nil, "1")
    function vrmod.AddLocomotionOption(name, startfunc, stopfunc, buildcpanelfunc)
        g_VR.locomotionOptions[#g_VR.locomotionOptions + 1] = {
            name = name,
            startfunc = startfunc,
            stopfunc = stopfunc,
            buildcpanelfunc = buildcpanelfunc
        }
    end

    function vrmod.StartLocomotion()
        local selectedOption = g_VR.locomotionOptions[convars.vrmod_locomotion:GetInt()]
        if selectedOption then selectedOption.startfunc() end
    end

    function vrmod.StopLocomotion()
        local selectedOption = g_VR.locomotionOptions[convars.vrmod_locomotion:GetInt()]
        if selectedOption then selectedOption.stopfunc() end
    end

    function vrmod.GetOrigin()
        return g_VR.origin, g_VR.originAngle
    end

    function vrmod.GetOriginPos()
        return g_VR.origin
    end

    function vrmod.GetOriginAng()
        return g_VR.originAngle
    end

    function vrmod.SetOrigin(pos, ang)
        g_VR.origin = pos
        g_VR.originAngle = ang
    end

    function vrmod.SetOriginPos(pos)
        g_VR.origin = pos
    end

    function vrmod.SetOriginAng(ang)
        g_VR.originAngle = ang
    end

    function vrmod.AddInGameMenuItem(name, slot, slotpos, func)
        local index = #g_VR.menuItems + 1
        for i = 1, #g_VR.menuItems do
            if g_VR.menuItems[i].name == name then index = i end
        end

        g_VR.menuItems[index] = {
            name = name,
            slot = slot,
            slotPos = slotpos,
            func = func
        }
    end

    function vrmod.RemoveInGameMenuItem(name)
        for i = 1, #g_VR.menuItems do
            if g_VR.menuItems[i].name == name then
                table.remove(g_VR.menuItems, i)
                return
            end
        end
    end

    function vrmod.GetLeftEyePos()
        return g_VR.eyePosLeft or Vector()
    end

    function vrmod.GetRightEyePos()
        return g_VR.eyePosRight or Vector()
    end

    function vrmod.GetEyePos()
        return g_VR.view and g_VR.view.origin or Vector()
    end

    function vrmod.GetTrackedDeviceNames()
        return g_VR.active and VRMOD_GetTrackedDeviceNames and VRMOD_GetTrackedDeviceNames() or {}
    end
end