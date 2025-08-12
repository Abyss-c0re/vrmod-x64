local addonVersion = 200
local requiredModuleVersion = nil
if system.IsLinux() then
	requiredModuleVersion = 23
else
	requiredModuleVersion = 21
end

local latestModuleVersion = 23
g_VR = g_VR or {}
vrmod = vrmod or {}
local convars, convarValues = {}, {}
function vrmod.AddCallbackedConvar(cvarName, valueName, defaultValue, flags, helptext, min, max, conversionFunc, callbackFunc)
	valueName = valueName or cvarName
	flags = flags or FCVAR_ARCHIVE
	conversionFunc = conversionFunc or function(val) return val end
	-- Prevent re-creating existing convar
	local cv = GetConVar(cvarName)
	if not cv then cv = CreateConVar(cvarName, defaultValue, flags, helptext, min, max) end
	convars[cvarName] = cv
	convarValues[valueName] = conversionFunc(cv:GetString())
	-- Set up dynamic callback
	cvars.AddChangeCallback(cvarName, function(_, _, new)
		convarValues[valueName] = conversionFunc(new)
		if callbackFunc then callbackFunc(convarValues[valueName]) end
	end, "vrmod")
	return convars, convarValues
end

function vrmod.GetConvars()
	return convars, convarValues
end

function vrmod.GetVersion()
	return addonVersion
end

if CLIENT then
	g_VR.net = g_VR.net or {}
	g_VR.viewModelInfo = g_VR.viewModelInfo or {}
	g_VR.locomotionOptions = g_VR.locomotionOptions or {}
	g_VR.menuItems = g_VR.menuItems or {}
	-- Cache for per-frame results
	local frameCache = {}
	local lastFrame = -1
	local fingerAngleCache = {}
	local fingerAngleCachePM = ""
	-- Helper to get player VR data
	local function getPlayerVRData(ply)
		local sid = ply and ply:SteamID() or LocalPlayer():SteamID()
		return g_VR.net[sid]
	end

	-- Helper to update frame cache
	local function updateFrameCache()
		local frame = FrameNumber()
		if frame ~= lastFrame then
			frameCache = {}
			lastFrame = frame
		end
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
			error = "Unknown module version\n\nInstalled: v" .. g_VR.moduleVersion .. "\nRequired: v" .. requiredModuleVersion .. "\n\nMake sure the addon is up to date.\nAddon version: " .. addonVersion
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
		updateFrameCache()
		local cacheKey = (ply and ply:SteamID() or LocalPlayer():SteamID()) .. "_hmdPos"
		if frameCache[cacheKey] then return frameCache[cacheKey] end
		local t = getPlayerVRData(ply)
		if not t then return end
		local pos = t and t.lerpedFrame and t.lerpedFrame.hmdPos or Vector()
		frameCache[cacheKey] = pos
		return pos
	end

	function vrmod.GetHMDAng(ply)
		updateFrameCache()
		local cacheKey = (ply and ply:SteamID() or LocalPlayer():SteamID()) .. "_hmdAng"
		if frameCache[cacheKey] then return frameCache[cacheKey] end
		local t = getPlayerVRData(ply)
		if not t then return end
		local ang = t and t.lerpedFrame and t.lerpedFrame.hmdAng or Angle()
		frameCache[cacheKey] = ang
		return ang
	end

	function vrmod.GetHMDPose(ply)
		updateFrameCache()
		local sid = ply and ply:SteamID() or LocalPlayer():SteamID()
		local posKey = sid .. "_hmdPos"
		local angKey = sid .. "_hmdAng"
		if frameCache[posKey] and frameCache[angKey] then return frameCache[posKey], frameCache[angKey] end
		local t = getPlayerVRData(ply)
		if not t then return end
		local pos, ang = t and t.lerpedFrame and t.lerpedFrame.hmdPos or Vector(), t and t.lerpedFrame and t.lerpedFrame.hmdAng or Angle()
		frameCache[posKey], frameCache[angKey] = pos, ang
		return pos, ang
	end

	function vrmod.GetHMDVelocity()
		return g_VR.threePoints and g_VR.tracking.hmd.vel or Vector()
	end

	function vrmod.GetHMDAngularVelocity()
		return g_VR.threePoints and g_VR.tracking.hmd.angvel or Angle() -- Changed to return Angle() for consistency
	end

	function vrmod.GetHMDVelocities()
		if g_VR.threePoints then return g_VR.tracking.hmd.vel, g_VR.tracking.hmd.angvel end
		return Vector(), Angle() -- Changed to return Angle() for angvel
	end

	function vrmod.GetLeftHandPos(ply)
		updateFrameCache()
		local cacheKey = (ply and ply:SteamID() or LocalPlayer():SteamID()) .. "_leftPos"
		if frameCache[cacheKey] then return frameCache[cacheKey] end
		local t = getPlayerVRData(ply)
		if not t then return end
		if vrmod.utils and t.lerpedFrame then t.lerpedFrame = vrmod.utils.UpdateHandCollisionShapes(t.lerpedFrame) end
		local pos = t and t.lerpedFrame and t.lerpedFrame.lefthandPos or Vector()
		frameCache[cacheKey] = pos
		return pos
	end

	function vrmod.GetLeftHandAng(ply)
		updateFrameCache()
		local cacheKey = (ply and ply:SteamID() or LocalPlayer():SteamID()) .. "_leftAng"
		if frameCache[cacheKey] then return frameCache[cacheKey] end
		local t = getPlayerVRData(ply)
		if not t then return end
		local ang = t and t.lerpedFrame and t.lerpedFrame.lefthandAng or Angle()
		frameCache[cacheKey] = ang
		return ang
	end

	function vrmod.GetLeftHandPose(ply)
		updateFrameCache()
		local sid = ply and ply:SteamID() or LocalPlayer():SteamID()
		local posKey = sid .. "_leftPos"
		local angKey = sid .. "_leftAng"
		if frameCache[posKey] and frameCache[angKey] then return frameCache[posKey], frameCache[angKey] end
		local t = getPlayerVRData(ply)
		if not t then return end
		if vrmod.utils and t.lerpedFrame then t.lerpedFrame = vrmod.utils.UpdateHandCollisionShapes(t.lerpedFrame) end
		local pos, ang = t and t.lerpedFrame and t.lerpedFrame.lefthandPos or Vector(), t and t.lerpedFrame and t.lerpedFrame.lefthandAng or Angle()
		frameCache[posKey], frameCache[angKey] = pos, ang
		return pos, ang
	end

	function vrmod.GetLeftHandVelocity()
		return g_VR.threePoints and g_VR.tracking.pose_lefthand.vel or Vector()
	end

	function vrmod.GetLeftHandAngularVelocity()
		return g_VR.threePoints and g_VR.tracking.pose_lefthand.angvel or Angle() -- Changed to return Angle()
	end

	function vrmod.GetLeftHandVelocityRelative()
		if not g_VR.threePoints then return Vector() end
		return g_VR.tracking.pose_lefthand.vel - g_VR.tracking.hmd.vel
	end

	function vrmod.GetLeftHandVelocities()
		if g_VR.threePoints then return g_VR.tracking.pose_lefthand.vel, g_VR.tracking.pose_lefthand.angvel, vrmod.GetLeftHandVelocityRelative() end
		return Vector(), Angle(), Vector() -- Changed to return Angle() for angvel
	end

	function vrmod.GetRightHandPos(ply)
		updateFrameCache()
		local cacheKey = (ply and ply:SteamID() or LocalPlayer():SteamID()) .. "_rightPos"
		if frameCache[cacheKey] then return frameCache[cacheKey] end
		local t = getPlayerVRData(ply)
		if not t then return end
		if vrmod.utils and t.lerpedFrame then t.lerpedFrame = vrmod.utils.UpdateHandCollisionShapes(t.lerpedFrame) end
		local pos = t and t.lerpedFrame and t.lerpedFrame.righthandPos or Vector()
		frameCache[cacheKey] = pos
		return pos
	end

	function vrmod.GetRightHandAng(ply)
		updateFrameCache()
		local cacheKey = (ply and ply:SteamID() or LocalPlayer():SteamID()) .. "_rightAng"
		if frameCache[cacheKey] then return frameCache[cacheKey] end
		local t = getPlayerVRData(ply)
		if not t then return end
		local ang = t and t.lerpedFrame and t.lerpedFrame.righthandAng or Angle()
		frameCache[cacheKey] = ang
		return ang
	end

	function vrmod.GetRightHandPose(ply)
		updateFrameCache()
		local sid = ply and ply:SteamID() or LocalPlayer():SteamID()
		local posKey = sid .. "_rightPos"
		local angKey = sid .. "_rightAng"
		if frameCache[posKey] and frameCache[angKey] then return frameCache[posKey], frameCache[angKey] end
		local t = getPlayerVRData(ply)
		if not t then return end
		if vrmod.utils and t.lerpedFrame then t.lerpedFrame = vrmod.utils.UpdateHandCollisionShapes(t.lerpedFrame) end
		local pos, ang = t and t.lerpedFrame and t.lerpedFrame.righthandPos or Vector(), t and t.lerpedFrame and t.lerpedFrame.righthandAng or Angle()
		frameCache[posKey], frameCache[angKey] = pos, ang
		return pos, ang
	end

	function vrmod.GetRightHandVelocity()
		return g_VR.threePoints and g_VR.tracking.pose_righthand.vel or Vector()
	end

	function vrmod.GetRightHandAngularVelocity()
		return g_VR.threePoints and g_VR.tracking.pose_righthand.angvel or Angle() -- Changed to return Angle()
	end

	function vrmod.GetRightHandVelocityRelative()
		if not g_VR.threePoints then return Vector() end
		return g_VR.tracking.pose_righthand.vel - g_VR.tracking.hmd.vel
	end

	function vrmod.GetRightHandVelocities()
		if g_VR.threePoints then return g_VR.tracking.pose_righthand.vel, g_VR.tracking.pose_righthand.angvel, vrmod.GetRightHandVelocityRelative() end
		return Vector(), Angle(), Vector() -- Changed to return Angle() for angvel
	end

	function vrmod.SetLeftHandPose(pos, ang)
		local t = g_VR.net[LocalPlayer():SteamID()]
		if t and t.lerpedFrame then
			if vrmod.utils then t.lerpedFrame = vrmod.utils.UpdateHandCollisionShapes(t.lerpedFrame) end
			t.lerpedFrame.lefthandPos, t.lerpedFrame.lefthandAng = pos, ang
			-- Invalidate cache
			frameCache[LocalPlayer():SteamID() .. "_leftPos"] = nil
			frameCache[LocalPlayer():SteamID() .. "_leftAng"] = nil
		end
	end

	function vrmod.SetRightHandPose(pos, ang)
		local t = g_VR.net[LocalPlayer():SteamID()]
		if t and t.lerpedFrame then
			if vrmod.utils then t.lerpedFrame = vrmod.utils.UpdateHandCollisionShapes(t.lerpedFrame) end
			t.lerpedFrame.righthandPos, t.lerpedFrame.righthandAng = pos, ang
			-- Invalidate cache
			frameCache[LocalPlayer():SteamID() .. "_rightPos"] = nil
			frameCache[LocalPlayer():SteamID() .. "_rightAng"] = nil
		end
	end

	local function HandleFingerAngles(mode, hand, state, tbl)
		local isGetter = mode == "get"
		local isDefault = mode == "get_default"
		local sourceTable = isDefault and (state == "open" and g_VR.defaultOpenHandAngles or g_VR.defaultClosedHandAngles) or state == "open" and g_VR.openHandAngles or g_VR.closedHandAngles
		local offset = hand == "right" and 15 or 0
		local cacheKey = isGetter and hand .. "_" .. state or nil
		if isGetter or isDefault then
			-- Check cache for getters
			if isGetter and fingerAngleCache[cacheKey] then return fingerAngleCache[cacheKey] end
			local r = {}
			for i = 1, 15 do
				r[i] = sourceTable[i + offset]
			end

			if isGetter then fingerAngleCache[cacheKey] = r end
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

			-- Invalidate getter cache
			fingerAngleCache[hand .. "_" .. state] = nil
		end
	end

	-- Getter functions
	function vrmod.GetLeftHandOpenFingerAngles()
		updateFrameCache()
		return HandleFingerAngles("get", "left", "open")
	end

	function vrmod.GetLeftHandClosedFingerAngles()
		updateFrameCache()
		return HandleFingerAngles("get", "left", "closed")
	end

	function vrmod.GetRightHandOpenFingerAngles()
		updateFrameCache()
		return HandleFingerAngles("get", "right", "open")
	end

	function vrmod.GetRightHandClosedFingerAngles()
		updateFrameCache()
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
		if fingerAngleCachePM ~= pm then
			fingerAngleCachePM = pm
			fingerAngleCache = {}
		end

		local cacheKey = modelName .. sequenceNumber
		if fingerAngleCache[cacheKey] then return fingerAngleCache[cacheKey] end
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
		fingerAngleCache[cacheKey] = r
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

	local bonePoseCache = {}
	local function GetRelativeBonePoseFromModel(modelName, sequenceNumber, boneName, refBoneName)
		sequenceNumber = sequenceNumber or 0
		local cacheKey = modelName .. sequenceNumber .. boneName .. (refBoneName or "")
		if bonePoseCache[cacheKey] then return bonePoseCache[cacheKey][1], bonePoseCache[cacheKey][2] end
		local ent = ClientsideModel(modelName)
		ent:ResetSequence(sequenceNumber)
		ent:SetupBones()
		local mtx, mtxRef = ent:GetBoneMatrix(ent:LookupBone(boneName)), ent:GetBoneMatrix(refBoneName and ent:LookupBone(refBoneName) or 0)
		local relativePos, relativeAng = WorldToLocal(mtx:GetTranslation(), mtx:GetAngles(), mtxRef:GetTranslation(), mtxRef:GetAngles())
		ent:Remove()
		bonePoseCache[cacheKey] = {relativePos, relativeAng}
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
elseif SERVER then
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

	function vrmod.GetFrameDeltaTime(ply, shouldPrint)
		if not IsValid(ply) then return end
		local sid = ply:SteamID()
		local playerTable = g_VR[sid]
		if not playerTable or not playerTable.lastFrameDelta then
			if shouldPrint then print("VRMod: No frame delta time available for player " .. sid) end
			return
		end

		if shouldPrint then print(string.format("VRMod: Time since last frame for player %s: %.4f seconds", sid, playerTable.lastFrameDelta)) end
		return playerTable.lastFrameDelta
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
		if not playerTable.latestFrameWorld or playerTable.latestFrameWorld.tick ~= engine.TickCount() then
			playerTable.latestFrameWorld = playerTable.latestFrameWorld or {}
			local lf = playerTable.latestFrame
			local lfw = playerTable.latestFrameWorld
			lfw.tick = engine.TickCount()
			local refPos, refAng = ply:GetPos(), ply:InVehicle() and ply:GetVehicle():GetAngles() or Angle()
			-- Ensure latestFrame has valid data
			if not lf then return end
			-- Base world conversions
			local rawHMDPos, rawHMDAng = LocalToWorld(lf.hmdPos or Vector(), lf.hmdAng or Angle(), refPos, refAng)
			local rawLeftPos, rawLeftAng = LocalToWorld(lf.lefthandPos or Vector(), lf.lefthandAng or Angle(), refPos, refAng)
			local rawRightPos, rawRightAng = LocalToWorld(lf.righthandPos or Vector(), lf.righthandAng or Angle(), refPos, refAng)
			-- Store updated positions
			lfw.hmdPos, lfw.hmdAng = rawHMDPos, rawHMDAng
			lfw.lefthandPos, lfw.lefthandAng = rawLeftPos, rawLeftAng
			lfw.righthandPos, lfw.righthandAng = rawRightPos, rawRightAng
			-- Update velocity cache
			local sid = ply:SteamID()
			local cache = vrmod.HandVelocityCache[sid]
			if not cache then
				cache = {
					leftLastPos = lfw.lefthandPos,
					rightLastPos = lfw.righthandPos,
					hmdLastPos = lfw.hmdPos,
					leftLastAng = lfw.lefthandAng or Angle(),
					rightLastAng = lfw.righthandAng or Angle(),
					hmdLastAng = lfw.hmdAng or Angle(),
					leftVel = Vector(),
					rightVel = Vector(),
					hmdVel = Vector(),
					leftAngVel = Angle(),
					rightAngVel = Angle(),
					hmdAngVel = Angle(),
					lastTick = lfw.tick
				}

				vrmod.HandVelocityCache[sid] = cache
			end

			if cache.lastTick ~= 0 then
				local dt = (lfw.tick - cache.lastTick) * engine.TickInterval()
				if dt > 0 then
					cache.leftVel = (lfw.lefthandPos - cache.leftLastPos) / dt
					cache.rightVel = (lfw.righthandPos - cache.rightLastPos) / dt
					cache.hmdVel = (lfw.hmdPos - cache.hmdLastPos) / dt
					cache.leftAngVel = lfw.lefthandAng and cache.leftLastAng and (lfw.lefthandAng - cache.leftLastAng) / dt or Angle()
					cache.rightAngVel = lfw.righthandAng and cache.rightLastAng and (lfw.righthandAng - cache.rightLastAng) / dt or Angle()
					cache.hmdAngVel = lfw.hmdAng and cache.hmdLastAng and (lfw.hmdAng - cache.hmdLastAng) / dt or Angle()
				end
			end

			cache.leftLastPos = lfw.lefthandPos
			cache.rightLastPos = lfw.righthandPos
			cache.hmdLastPos = lfw.hmdPos
			cache.leftLastAng = lfw.lefthandAng or Angle()
			cache.rightLastAng = lfw.righthandAng or Angle()
			cache.hmdLastAng = lfw.hmdAng or Angle()
			cache.lastTick = lfw.tick
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

	function vrmod.GetHMDVelocity(ply)
		if not IsValid(ply) then return end
		local cache = vrmod.HandVelocityCache[ply:SteamID()]
		if not cache then
			UpdateWorldPoses(ply, g_VR[ply:SteamID()])
			cache = vrmod.HandVelocityCache[ply:SteamID()]
		end
		return cache and cache.hmdVel or Vector()
	end

	function vrmod.GetHMDAngularVelocity(ply)
		if not IsValid(ply) then return end
		local cache = vrmod.HandVelocityCache[ply:SteamID()]
		if not cache then
			UpdateWorldPoses(ply, g_VR[ply:SteamID()])
			cache = vrmod.HandVelocityCache[ply:SteamID()]
		end
		return cache and cache.hmdAngVel or Angle()
	end

	function vrmod.GetLeftHandPos(ply)
		if not IsValid(ply) then return end
		local playerTable = g_VR[ply:SteamID()]
		if not (playerTable and playerTable.latestFrame) then return Vector() end
		UpdateWorldPoses(ply, playerTable)
		return playerTable.latestFrameWorld.lefthandPos
	end

	function vrmod.GetLeftHandAng(ply)
		if not IsValid(ply) then return end
		local playerTable = g_VR[ply:SteamID()]
		if not (playerTable and playerTable.latestFrame) then return Angle() end
		UpdateWorldPoses(ply, playerTable)
		return playerTable.latestFrameWorld.lefthandAng
	end

	function vrmod.GetLeftHandPose(ply)
		if not IsValid(ply) then return end
		local playerTable = g_VR[ply:SteamID()]
		if not (playerTable and playerTable.latestFrame) then return Vector(), Angle() end
		UpdateWorldPoses(ply, playerTable)
		return playerTable.latestFrameWorld.lefthandPos, playerTable.latestFrameWorld.lefthandAng
	end

	function vrmod.GetLeftHandVelocity(ply)
		if not IsValid(ply) then return end
		local cache = vrmod.HandVelocityCache[ply:SteamID()]
		if not cache then
			UpdateWorldPoses(ply, g_VR[ply:SteamID()])
			cache = vrmod.HandVelocityCache[ply:SteamID()]
		end
		return cache and cache.leftVel or Vector()
	end

	function vrmod.GetLeftHandAngularVelocity(ply)
		if not IsValid(ply) then return end
		local cache = vrmod.HandVelocityCache[ply:SteamID()]
		if not cache then
			UpdateWorldPoses(ply, g_VR[ply:SteamID()])
			cache = vrmod.HandVelocityCache[ply:SteamID()]
		end
		return cache and cache.leftAngVel or Angle()
	end

	function vrmod.GetLeftHandVelocityRelative(ply)
		if not IsValid(ply) then return end
		local handVel = vrmod.GetLeftHandVelocity(ply)
		local hmdVel = vrmod.GetHMDVelocity(ply)
		return handVel - hmdVel
	end

	function vrmod.GetLeftHandAngularVelocityRelative(ply)
		if not IsValid(ply) then return end
		local handAngVel = vrmod.GetLeftHandAngularVelocity(ply)
		local hmdAngVel = vrmod.GetHMDAngularVelocity(ply)
		return handAngVel - hmdAngVel
	end

	function vrmod.GetRightHandPos(ply)
		if not IsValid(ply) then return end
		local playerTable = g_VR[ply:SteamID()]
		if not (playerTable and playerTable.latestFrame) then return Vector() end
		UpdateWorldPoses(ply, playerTable)
		return playerTable.latestFrameWorld.righthandPos
	end

	function vrmod.GetRightHandAng(ply)
		if not IsValid(ply) then return end
		local playerTable = g_VR[ply:SteamID()]
		if not (playerTable and playerTable.latestFrame) then return Angle() end
		UpdateWorldPoses(ply, playerTable)
		return playerTable.latestFrameWorld.righthandAng
	end

	function vrmod.GetRightHandPose(ply)
		if not IsValid(ply) then return end
		local playerTable = g_VR[ply:SteamID()]
		if not (playerTable and playerTable.latestFrame) then return Vector(), Angle() end
		UpdateWorldPoses(ply, playerTable)
		return playerTable.latestFrameWorld.righthandPos, playerTable.latestFrameWorld.righthandAng
	end

	function vrmod.GetRightHandVelocity(ply)
		if not IsValid(ply) then return end
		local cache = vrmod.HandVelocityCache[ply:SteamID()]
		if not cache then
			UpdateWorldPoses(ply, g_VR[ply:SteamID()])
			cache = vrmod.HandVelocityCache[ply:SteamID()]
		end
		return cache and cache.rightVel or Vector()
	end

	function vrmod.GetRightHandAngularVelocity(ply)
		if not IsValid(ply) then return end
		local cache = vrmod.HandVelocityCache[ply:SteamID()]
		if not cache then
			UpdateWorldPoses(ply, g_VR[ply:SteamID()])
			cache = vrmod.HandVelocityCache[ply:SteamID()]
		end
		return cache and cache.rightAngVel or Angle()
	end

	function vrmod.GetRightHandVelocityRelative(ply)
		if not IsValid(ply) then return end
		local handVel = vrmod.GetRightHandVelocity(ply)
		local hmdVel = vrmod.GetHMDVelocity(ply)
		return handVel - hmdVel
	end

	function vrmod.GetRightHandAngularVelocityRelative(ply)
		if not IsValid(ply) then return end
		local handAngVel = vrmod.GetRightHandAngularVelocity(ply)
		local hmdAngVel = vrmod.GetHMDAngularVelocity(ply)
		return handAngVel - hmdAngVel
	end

	function vrmod.GetPullGestureStrength(ply, hand, targetPos)
		if not IsValid(ply) then return end
		local handPos = hand == "left" and vrmod.GetLeftHandPos(ply) or vrmod.GetRightHandPos(ply)
		local relVel = hand == "left" and vrmod.GetLeftHandVelocityRelative(ply) or vrmod.GetRightHandVelocityRelative(ply)
		local pullDir = (targetPos - handPos):GetNormalized()
		return relVel:Dot(pullDir)
	end
end

hook.Add("PlayerDisconnected", "VRMod_CleanCache", function(ply) vrmod.HandVelocityCache[ply:SteamID()] = nil end)
local hookTranslations = {
	VRUtilEventTracking = "VRMod_Tracking",
	VRUtilEventInput = "VRMod_Input",
	VRUtilEventPreRender = "VRMod_PreRender",
	VRUtilEventPreRenderRight = "VRMod_PreRenderRight",
	VRUtilEventPostRender = "VRMod_PostRender",
	VRUtilStart = "VRMod_Start",
	VRUtilExit = "VRMod_Exit",
	VRUtilEventPickup = "VRMod_Pickup",
	VRUtilEventDrop = "VRMod_Drop",
	VRUtilAllowDefaultAction = "VRMod_AllowDefaultAction"
}

local hooks = hook.GetTable()
for k, v in pairs(hooks) do
	local translation = hookTranslations[k]
	if translation then
		hooks[translation] = hooks[translation] or {}
		for k2, v2 in pairs(v) do
			hooks[translation][k2] = v2
		end

		hooks[k] = nil
	end
end

local orig = hook.Add
hook.Add = function(...)
	local args = {...}
	args[1] = hookTranslations[args[1]] or args[1]
	orig(unpack(args))
end

local orig = hook.Remove
hook.Remove = function(...)
	local args = {...}
	args[1] = hookTranslations[args[1]] or args[1]
	orig(unpack(args))
end