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
local EmptyHandsWeapons = {
    ["weapon_vrmod_empty"] = true,
    ["vr_spooderman"] = true,
}

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

    -- smoothing helper (Angles must use LerpAngle — both Angle and Vector expose :Lerp)
    local function SmoothValue(oldVal, newVal, factor)
        if not oldVal then return newVal end
        if not factor or factor <= 0 then return newVal end
        if isangle and isangle(oldVal) then
            return LerpAngle(factor, oldVal, newVal)
        end
        if isvector and isvector(oldVal) then
            return LerpVector(factor, oldVal, newVal)
        end
        -- Fallback without isangle/isvector: Angle uses p/y/r, Vector uses x/y/z
        if oldVal.p ~= nil and oldVal.r ~= nil and oldVal.x == nil then
            return LerpAngle(factor, oldVal, newVal)
        end
        if oldVal.x ~= nil and oldVal.z ~= nil and oldVal.p == nil then
            return LerpVector(factor, oldVal, newVal)
        end
        if type(oldVal) == "number" and type(newVal) == "number" then
            return Lerp(factor, oldVal, newVal)
        end
        return newVal
    end

    vrmod.cachedHeadPose = {
        pos = Vector(0, 0, 0),
        ang = Angle(0, 0, 0),
        vel = Vector(0, 0, 0),
        angvel = Vector(0, 0, 0), -- Cube's Law: angvel is Vector(p,y,r)
        lastUpdate = 0
    }

    local function UpdateHeadVelocitiesFromPose()
        if not g_VR.tracking or not g_VR.tracking.hmd then return end
        local hmd = g_VR.tracking.hmd
        vrmod.cachedHeadPose.pos = hmd.pos or Vector(0, 0, 0)
        vrmod.cachedHeadPose.ang = hmd.ang or Angle(0, 0, 0)
        vrmod.cachedHeadPose.lastUpdate = CurTime()
        -- vel / angvel are set in UpdateTracking() from raw pose delta
    end

    hook.Add("Think", "VRMod_HeadPoseVelocityCache", function() UpdateHeadVelocitiesFromPose() end)
    function vrmod.GetStartupError()
        local error = nil
        local moduleFile = nil
        -- requiredVersion = hard floor (must boot). latestVersion = full feature set (SS eye args, etc).
        -- Lua degrades gracefully on older modules; only refuse if too ancient / missing.
        local requiredVersion, latestVersion
        if system.IsLinux() then
            requiredVersion = 20
            latestVersion = 27
            moduleFile = "lua/bin/gmcl_vrmod_linux64.dll"
        else
            requiredVersion = 20
            latestVersion = 27
            moduleFile = "lua/bin/gmcl_vrmod_win64.dll"
            if not file.Exists(moduleFile, "GAME") then
                moduleFile = "lua/bin/gmcl_vrmod_win32.dll"
            end
        end

        g_VR.moduleVersion = g_VR.moduleVersion or 0
        if g_VR.moduleVersion == 0 then
            if not file.Exists(moduleFile, "GAME") then
                error = "Module not installed.\nPlease follow the workshop instructions to install the module."
            else
                error = "Failed to load module.\nModule file exists but could not be loaded. Check antivirus or permissions."
            end
        elseif g_VR.moduleVersion < requiredVersion then
            error = "Module update required.\nRun the installer or re-download from the workshop.\n\nInstalled: v" .. g_VR.moduleVersion .. "\nRequired: v" .. requiredVersion
        else
            if g_VR.moduleVersion < latestVersion then
                print(string.format(
                    "[VRMOD] Module v%d is older than recommended v%d. VR still runs; supersample eye sizing and some crisp-path fixes need the latest modules.zip.",
                    g_VR.moduleVersion, latestVersion
                ))
            elseif g_VR.moduleVersion > latestVersion then
                print("[VRMOD] Warning: Module version is newer than tested. Installed: v" .. g_VR.moduleVersion .. " | Recommended: v" .. latestVersion .. " | Addon: " .. vrmod.GetVersion() .. " | Most features should work.")
            end
            if VRMOD_IsHMDPresent and not VRMOD_IsHMDPresent() then
                error = "VR headset not detected."
            end
        end
        return error
    end

    --- Feature flags for optional module APIs (never hard-crash on missing exports).
    function vrmod.ModuleSupportsEyeSizeArgs()
        return (g_VR.moduleVersion or 0) >= 23
    end

    function vrmod.GetModuleVersion()
        return g_VR.moduleVersion, 20, 27
    end

    function vrmod.IsPlayerInVR(ply)
        return getPlayerVRData(ply) ~= nil
    end

    function vrmod.UsingEmptyHands(ply)
        local wep = ply and ply:GetActiveWeapon() or LocalPlayer():GetActiveWeapon()
        if not IsValid(wep) then return false end
        return EmptyHandsWeapons[wep:GetClass()] or false
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

    -- Safe pose table lookup: g_VR.tracking.* must never nil-index for callers.
    local function trackPose(name)
        local t = g_VR and g_VR.tracking
        return t and t[name] or nil
    end

    function vrmod.GetHMDPos(ply)
        local p = trackPose("hmd")
        return (p and p.pos) or Vector()
    end

    function vrmod.GetHMDAng(ply)
        local p = trackPose("hmd")
        return (p and p.ang) or Angle()
    end

    function vrmod.GetHMDPose(ply)
        local p = trackPose("hmd")
        if not p then return Vector(), Angle() end
        return p.pos or Vector(), p.ang or Angle()
    end

    function vrmod.GetHMDVelocity()
        return vrmod.cachedHeadPose.vel or Vector()
    end

    function vrmod.GetHMDAngularVelocity()
        return vrmod.cachedHeadPose.angvel or Vector()
    end

    function vrmod.GetHMDVelocityRelative()
        if not g_VR.threePoints then return Vector() end
        local vel = vrmod.cachedHeadPose.vel or Vector()
        local ply = LocalPlayer()
        if IsValid(ply) then vel = vel - ply:GetVelocity() end
        return vel
    end

    function vrmod.GetHMDVelocities()
        if g_VR.threePoints then return vrmod.cachedHeadPose.vel or Vector(), vrmod.cachedHeadPose.angvel or Vector() end
        return Vector(), Vector()
    end

    function vrmod.GetLeftHandPos(ply)
        local p = trackPose("pose_lefthand")
        return (p and p.pos) or Vector()
    end

    function vrmod.GetLeftHandAng(ply)
        local p = trackPose("pose_lefthand")
        return (p and p.ang) or Angle()
    end

    function vrmod.GetLeftHandPose(ply)
        local p = trackPose("pose_lefthand")
        if not p then return Vector(), Angle() end
        return p.pos or Vector(), p.ang or Angle()
    end

    function vrmod.GetLeftHandVelocity()
        local p = trackPose("pose_lefthand")
        return (p and p.vel) or Vector()
    end

    function vrmod.GetLeftHandAngularVelocity()
        local p = trackPose("pose_lefthand")
        return (p and p.angvel) or Vector()
    end

    function vrmod.GetLeftHandVelocityRelative()
        local hand = trackPose("pose_lefthand")
        local hmd = trackPose("hmd")
        if not g_VR.threePoints or not hand or not hmd then return Vector() end
        return (hand.vel or Vector()) - (hmd.vel or Vector())
    end

    function vrmod.GetLeftHandVelocities()
        local p = trackPose("pose_lefthand")
        if g_VR.threePoints and p then
            return p.vel or Vector(), p.angvel or Vector(), vrmod.GetLeftHandVelocityRelative()
        end
        return Vector(), Vector(), Vector()
    end

    function vrmod.GetRightHandPos(ply)
        local p = trackPose("pose_righthand")
        return (p and p.pos) or Vector()
    end

    function vrmod.GetRightHandAng(ply)
        local p = trackPose("pose_righthand")
        return (p and p.ang) or Angle()
    end

    function vrmod.GetRightHandPose(ply)
        local p = trackPose("pose_righthand")
        if not p then return Vector(), Angle() end
        return p.pos or Vector(), p.ang or Angle()
    end

    function vrmod.GetRightHandVelocity()
        local p = trackPose("pose_righthand")
        return (p and p.vel) or Vector()
    end

    function vrmod.GetRightHandAngularVelocity()
        local p = trackPose("pose_righthand")
        return (p and p.angvel) or Vector()
    end

    function vrmod.GetRightHandVelocityRelative()
        local hand = trackPose("pose_righthand")
        local hmd = trackPose("hmd")
        if not g_VR.threePoints or not hand or not hmd then return Vector() end
        return (hand.vel or Vector()) - (hmd.vel or Vector())
    end

    function vrmod.GetRightHandVelocities()
        local p = trackPose("pose_righthand")
        if g_VR.threePoints and p then
            return p.vel or Vector(), p.angvel or Vector(), vrmod.GetRightHandVelocityRelative()
        end
        return Vector(), Vector(), Vector()
    end

    -- Waist (often called "hip" in other VR contexts)
    function vrmod.GetWaistPos(ply)
        local t = getPlayerVRData(ply)
        if not t or not g_VR.fbtActive or not g_VR.tracking or not g_VR.tracking.pose_waist then return Vector() end
        return g_VR.tracking.pose_waist.pos or Vector()
    end

    function vrmod.GetWaistAng(ply)
        local t = getPlayerVRData(ply)
        if not t or not g_VR.fbtActive or not g_VR.tracking or not g_VR.tracking.pose_waist then return Angle() end
        return g_VR.tracking.pose_waist.ang or Angle()
    end

    function vrmod.GetWaistPose(ply)
        local t = getPlayerVRData(ply)
        if not t or not g_VR.fbtActive or not g_VR.tracking or not g_VR.tracking.pose_waist then return Vector(), Angle() end
        return g_VR.tracking.pose_waist.pos or Vector(), g_VR.tracking.pose_waist.ang or Angle()
    end

    -- If velocities are provided on the waist pose (many FBT setups include them)
    function vrmod.GetWaistVelocity()
        return g_VR.fbtActive and g_VR.tracking and g_VR.tracking.pose_waist and g_VR.tracking.pose_waist.vel or Vector()
    end

    function vrmod.GetWaistAngularVelocity()
        return g_VR.fbtActive and g_VR.tracking and g_VR.tracking.pose_waist and g_VR.tracking.pose_waist.angvel or Vector()
    end

    -- Optional relative (to HMD)
    function vrmod.GetWaistVelocityRelative()
        if not g_VR.fbtActive or not g_VR.tracking or not g_VR.tracking.pose_waist or not g_VR.tracking.hmd then return Vector() end
        return (g_VR.tracking.pose_waist.vel or Vector()) - (g_VR.tracking.hmd.vel or Vector())
    end

    -- Left Foot
    function vrmod.GetLeftFootPos(ply)
        local t = getPlayerVRData(ply)
        if not t or not g_VR.fbtActive or not g_VR.tracking or not g_VR.tracking.pose_leftfoot then return Vector() end
        return g_VR.tracking.pose_leftfoot.pos or Vector()
    end

    function vrmod.GetLeftFootAng(ply)
        local t = getPlayerVRData(ply)
        if not t or not g_VR.fbtActive or not g_VR.tracking or not g_VR.tracking.pose_leftfoot then return Angle() end
        return g_VR.tracking.pose_leftfoot.ang or Angle()
    end

    function vrmod.GetLeftFootPose(ply)
        local t = getPlayerVRData(ply)
        if not t or not g_VR.fbtActive or not g_VR.tracking or not g_VR.tracking.pose_leftfoot then return Vector(), Angle() end
        return g_VR.tracking.pose_leftfoot.pos or Vector(), g_VR.tracking.pose_leftfoot.ang or Angle()
    end

    function vrmod.GetLeftFootVelocity()
        return g_VR.fbtActive and g_VR.tracking and g_VR.tracking.pose_leftfoot and g_VR.tracking.pose_leftfoot.vel or Vector()
    end

    function vrmod.GetLeftFootAngularVelocity()
        return g_VR.fbtActive and g_VR.tracking and g_VR.tracking.pose_leftfoot and g_VR.tracking.pose_leftfoot.angvel or Vector()
    end

    function vrmod.GetLeftFootVelocityRelative()
        if not g_VR.fbtActive or not g_VR.tracking or not g_VR.tracking.pose_leftfoot or not g_VR.tracking.hmd then return Vector() end
        return (g_VR.tracking.pose_leftfoot.vel or Vector()) - (g_VR.tracking.hmd.vel or Vector())
    end

    function vrmod.GetLeftFootVelocities()
        if g_VR.fbtActive and g_VR.tracking and g_VR.tracking.pose_leftfoot then return g_VR.tracking.pose_leftfoot.vel or Vector(), g_VR.tracking.pose_leftfoot.angvel or Vector(), vrmod.GetLeftFootVelocityRelative() end
        return Vector(), Vector(), Vector()
    end

    -- Right Foot (symmetric to left)
    function vrmod.GetRightFootPos(ply)
        local t = getPlayerVRData(ply)
        if not t or not g_VR.fbtActive or not g_VR.tracking or not g_VR.tracking.pose_rightfoot then return Vector() end
        return g_VR.tracking.pose_rightfoot.pos or Vector()
    end

    function vrmod.GetRightFootAng(ply)
        local t = getPlayerVRData(ply)
        if not t or not g_VR.fbtActive or not g_VR.tracking or not g_VR.tracking.pose_rightfoot then return Angle() end
        return g_VR.tracking.pose_rightfoot.ang or Angle()
    end

    function vrmod.GetRightFootPose(ply)
        local t = getPlayerVRData(ply)
        if not t or not g_VR.fbtActive or not g_VR.tracking or not g_VR.tracking.pose_rightfoot then return Vector(), Angle() end
        return g_VR.tracking.pose_rightfoot.pos or Vector(), g_VR.tracking.pose_rightfoot.ang or Angle()
    end

    function vrmod.GetRightFootVelocity()
        return g_VR.fbtActive and g_VR.tracking and g_VR.tracking.pose_rightfoot and g_VR.tracking.pose_rightfoot.vel or Vector()
    end

    function vrmod.GetRightFootAngularVelocity()
        return g_VR.fbtActive and g_VR.tracking and g_VR.tracking.pose_rightfoot and g_VR.tracking.pose_rightfoot.angvel or Vector()
    end

    function vrmod.GetRightFootVelocityRelative()
        if not g_VR.fbtActive or not g_VR.tracking or not g_VR.tracking.pose_rightfoot or not g_VR.tracking.hmd then return Vector() end
        return (g_VR.tracking.pose_rightfoot.vel or Vector()) - (g_VR.tracking.hmd.vel or Vector())
    end

    function vrmod.GetRightFootVelocities()
        if g_VR.fbtActive and g_VR.tracking and g_VR.tracking.pose_rightfoot then return g_VR.tracking.pose_rightfoot.vel or Vector(), g_VR.tracking.pose_rightfoot.angvel or Vector(), vrmod.GetRightFootVelocityRelative() end
        return Vector(), Vector(), Vector()
    end

    function vrmod.SetLeftHandPose(pos, ang, smoothing)
        local ply = LocalPlayer()
        if not pos or not ang then return end
        -- Always write COPIES — never alias caller vectors into tracking/net
        -- (foregrip + FBT flicker when state.leftPos became tracking.pos).
        local factor = smoothing or 0
        local L = g_VR.tracking and g_VR.tracking.pose_lefthand
        if L and L.pos and L.ang then
            local np = SmoothValue(L.pos, pos, factor)
            local na = SmoothValue(L.ang, ang, factor)
            if L.pos.Set and isvector(np) then
                L.pos:Set(np)
            else
                L.pos = Vector(np.x, np.y, np.z)
            end
            if L.ang.Set and isangle and isangle(na) then
                L.ang:Set(na)
            elseif L.ang.Set and na.p then
                L.ang:Set(na)
            else
                L.ang = Angle(na.p or 0, na.y or 0, na.r or 0)
            end
            pos, ang = L.pos, L.ang
        end
        local netFrame = g_VR.net and g_VR.net[ply:SteamID()] and g_VR.net[ply:SteamID()].lerpedFrame
        if not netFrame then return end
        local npos = SmoothValue(netFrame.lefthandPos, pos, factor)
        local nang = SmoothValue(netFrame.lefthandAng, ang, factor)
        netFrame.lefthandPos = Vector(npos.x or npos[1] or 0, npos.y or npos[2] or 0, npos.z or npos[3] or 0)
        if nang and nang.p then
            netFrame.lefthandAng = Angle(nang.p, nang.y, nang.r)
        else
            netFrame.lefthandAng = Angle(ang.p, ang.y, ang.r)
        end
    end

    function vrmod.SetRightHandPose(pos, ang, smoothing)
        local ply = LocalPlayer()
        if g_VR.tracking and g_VR.tracking.pose_righthand and pos and ang then
            g_VR.tracking.pose_righthand.pos = SmoothValue(g_VR.tracking.pose_righthand.pos, pos, smoothing or 0)
            g_VR.tracking.pose_righthand.ang = SmoothValue(g_VR.tracking.pose_righthand.ang, ang, smoothing or 0)
            pos = g_VR.tracking.pose_righthand.pos
            ang = g_VR.tracking.pose_righthand.ang
        end
        local netFrame = g_VR.net and g_VR.net[ply:SteamID()] and g_VR.net[ply:SteamID()].lerpedFrame
        if not netFrame then return end
        netFrame.righthandPos = SmoothValue(netFrame.righthandPos, pos, smoothing or 0)
        netFrame.righthandAng = SmoothValue(netFrame.righthandAng, ang, smoothing or 0)
        if vrmod.utils and vrmod.utils.UpdateViewModelPos then
            vrmod.utils.UpdateViewModelPos(pos, ang, true)
        end
    end

    --- Unmodified device poses (pre-collision / pre-UI). Safe for velocity & gestures.
    function vrmod.GetRawLeftHandPose()
        local p = g_VR.rawTracking and g_VR.rawTracking.pose_lefthand
        if not p then return Vector(), Angle() end
        return p.pos or Vector(), p.ang or Angle()
    end

    function vrmod.GetRawRightHandPose()
        local p = g_VR.rawTracking and g_VR.rawTracking.pose_righthand
        if not p then return Vector(), Angle() end
        return p.pos or Vector(), p.ang or Angle()
    end

    function vrmod.GetRawHMDPose()
        local p = g_VR.rawTracking and g_VR.rawTracking.hmd
        if not p then return Vector(), Angle() end
        return p.pos or Vector(), p.ang or Angle()
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

    function vrmod.SetViewModelUseWorldModel(classname, bool)
        g_VR.viewModelInfo[classname] = g_VR.viewModelInfo[classname] or {}
        g_VR.viewModelInfo[classname].useWorldModel = bool
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

    local function GetMenuItemID(name, func)
        return name .. "_" .. tostring(func)
    end

    -- Add or restore a menu item
    -- id (optional): stable layout key for Quick Menu pages (Settings → Quick Menu)
    function vrmod.AddInGameMenuItem(name, slot, slotpos, func, forceSlot, hint, id)
        g_VR.menuItems = g_VR.menuItems or {}
        g_VR.menuBackup = g_VR.menuBackup or {}
        -- Stable layout id (for multi-page quick menu)
        if not id and vrmod.QuickMenu and vrmod.QuickMenu.IdFromName then
            id = vrmod.QuickMenu.IdFromName(name)
        end
        -- Determine slot if not forced
        if not forceSlot then
            local occupied = {}
            for _, item in ipairs(g_VR.menuItems) do
                occupied[item.slot] = occupied[item.slot] or {}
                occupied[item.slot][item.slotPos] = true
            end

            local found = false
            for s = 0, 10 do
                occupied[s] = occupied[s] or {}
                for p = 0, 10 do
                    if not occupied[s][p] then
                        slot = s
                        slotpos = p
                        found = true
                        break
                    end
                end

                if found then break end
            end
        end

        -- Avoid exact duplicates
        for _, item in ipairs(g_VR.menuItems) do
            if item.name == name and item.func == func then
                -- Upgrade id if newer call provides one
                if id and not item.id then item.id = id end
                return
            end
        end

        table.insert(g_VR.menuItems, {
            name = name,
            slot = slot,
            slotPos = slotpos,
            func = func,
            hint = hint,
            id = id,
        })

        -- Store in backup with unique ID (name+func; not layout id)
        local bakId = GetMenuItemID(name, func)
        g_VR.menuBackup[bakId] = {
            name = name,
            slot = slot,
            slotPos = slotpos,
            func = func,
            internal = forceSlot == true,
            hint = hint,
            id = id,
        }
    end

    -- Remove menu item, optionally permanently
    function vrmod.RemoveInGameMenuItem(name, func, permanent)
        for i = #g_VR.menuItems, 1, -1 do
            if g_VR.menuItems[i].name == name and (not func or g_VR.menuItems[i].func == func) then table.remove(g_VR.menuItems, i) end
        end

        if permanent then
            local id = GetMenuItemID(name, func)
            g_VR.menuBackup[id] = nil
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