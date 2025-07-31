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
	valueName, flags, conversionFunc = valueName or cvarName, flags or FCVAR_ARCHIVE, conversionFunc or function(val) return val end
	local cv = CreateConVar(cvarName, defaultValue, flags, helptext, min, max)
	convars[cvarName], convarValues[valueName] = cv, conversionFunc(cv:GetString())
	cvars.AddChangeCallback(cvarName, function(cv_name, val_old, val_new)
		convarValues[valueName] = conversionFunc(val_new)
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
		return g_VR.net[ply and ply:SteamID() or LocalPlayer():SteamID()] ~= nil
	end

	function vrmod.UsingEmptyHands(ply)
		local wep = ply and ply:GetActiveWeapon() or LocalPlayer():GetActiveWeapon()
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

	function vrmod.GetHMDPos(ply)
		local t = ply and g_VR.net[ply:SteamID()] or g_VR.net[LocalPlayer():SteamID()]
		return t and t.lerpedFrame and t.lerpedFrame.hmdPos or Vector()
	end

	function vrmod.GetHMDAng(ply)
		local t = ply and g_VR.net[ply:SteamID()] or g_VR.net[LocalPlayer():SteamID()]
		return t and t.lerpedFrame and t.lerpedFrame.hmdAng or Angle()
	end

	function vrmod.GetHMDPose(ply)
		local t = ply and g_VR.net[ply:SteamID()] or g_VR.net[LocalPlayer():SteamID()]
		if t and t.lerpedFrame then return t.lerpedFrame.hmdPos, t.lerpedFrame.hmdAng end
		return Vector(), Angle()
	end

	function vrmod.GetHMDVelocity()
		return g_VR.threePoints and g_VR.tracking.hmd.vel or Vector()
	end

	function vrmod.GetHMDAngularVelocity()
		return g_VR.threePoints and g_VR.tracking.hmd.angvel or Vector()
	end

	function vrmod.GetHMDVelocities()
		if g_VR.threePoints then return g_VR.tracking.hmd.vel, g_VR.tracking.hmd.angvel end
		return Vector(), Vector()
	end

	function vrmod.GetLeftHandPos(ply)
		local t = ply and g_VR.net[ply:SteamID()] or g_VR.net[LocalPlayer():SteamID()]
		return t and t.lerpedFrame and t.lerpedFrame.lefthandPos or Vector()
	end

	function vrmod.GetLeftHandAng(ply)
		local t = ply and g_VR.net[ply:SteamID()] or g_VR.net[LocalPlayer():SteamID()]
		return t and t.lerpedFrame and t.lerpedFrame.lefthandAng or Angle()
	end

	function vrmod.GetLeftHandPose(ply)
		local t = ply and g_VR.net[ply:SteamID()] or g_VR.net[LocalPlayer():SteamID()]
		if t and t.lerpedFrame then return t.lerpedFrame.lefthandPos, t.lerpedFrame.lefthandAng end
		return Vector(), Angle()
	end

	function vrmod.GetLeftHandVelocity()
		return g_VR.threePoints and g_VR.tracking.pose_lefthand.vel or Vector()
	end

	function vrmod.GetLeftHandAngularVelocity()
		return g_VR.threePoints and g_VR.tracking.pose_lefthand.angvel or Vector()
	end

	function vrmod.GetLeftHandVelocityRelative()
		return g_VR.tracking.pose_lefthand.vel - g_VR.tracking.hmd.vel
	end

	function vrmod.GetLeftHandVelocities()
		if g_VR.threePoints then return g_VR.tracking.pose_lefthand.vel, g_VR.tracking.pose_lefthand.angvel, GetLeftHandVelocityRelative() end
		return Vector(), Vector(), Vector()
	end

	function vrmod.GetRightHandPos(ply)
		local t = ply and g_VR.net[ply:SteamID()] or g_VR.net[LocalPlayer():SteamID()]
		return t and t.lerpedFrame and t.lerpedFrame.righthandPos or Vector()
	end

	function vrmod.GetRightHandAng(ply)
		local t = ply and g_VR.net[ply:SteamID()] or g_VR.net[LocalPlayer():SteamID()]
		return t and t.lerpedFrame and t.lerpedFrame.righthandAng or Angle()
	end

	function vrmod.GetRightHandPose(ply)
		local t = ply and g_VR.net[ply:SteamID()] or g_VR.net[LocalPlayer():SteamID()]
		if t and t.lerpedFrame then return t.lerpedFrame.righthandPos, t.lerpedFrame.righthandAng end
		return Vector(), Angle()
	end

	function vrmod.GetRightHandVelocity()
		return g_VR.threePoints and g_VR.tracking.pose_righthand.vel or Vector()
	end

	function vrmod.GetRightHandAngularVelocity()
		return g_VR.threePoints and g_VR.tracking.pose_righthand.angvel or Vector()
	end

	function vrmod.GetRightHandVelocityRelative()
		return g_VR.tracking.pose_righthand.vel - g_VR.tracking.hmd.vel
	end

	function vrmod.GetRightHandVelocities()
		if g_VR.threePoints then return g_VR.tracking.pose_righthand.vel, g_VR.tracking.pose_righthand.angvel, vrmod.GetRightHandVelocityRelative() end
		return Vector(), Vector(), Vector()
	end

	function vrmod.SetLeftHandPose(pos, ang)
		local t = g_VR.net[LocalPlayer():SteamID()]
		if t and t.lerpedFrame then t.lerpedFrame.lefthandPos, t.lerpedFrame.lefthandAng = pos, ang end
	end

	function vrmod.SetRightHandPose(pos, ang)
		local t = g_VR.net[LocalPlayer():SteamID()]
		if t and t.lerpedFrame then t.lerpedFrame.righthandPos, t.lerpedFrame.righthandAng = pos, ang end
	end

	function vrmod.GetLeftHandOpenFingerAngles()
		local r = {}
		for i = 1, 15 do
			r[i] = g_VR.openHandAngles[i]
		end
		return r
	end

	function vrmod.GetLeftHandClosedFingerAngles()
		local r = {}
		for i = 1, 15 do
			r[i] = g_VR.closedHandAngles[i]
		end
		return r
	end

	function vrmod.GetRightHandOpenFingerAngles()
		local r = {}
		for i = 1, 15 do
			r[i] = g_VR.openHandAngles[15 + i]
		end
		return r
	end

	function vrmod.GetRightHandClosedFingerAngles()
		local r = {}
		for i = 1, 15 do
			r[i] = g_VR.closedHandAngles[15 + i]
		end
		return r
	end

	function vrmod.SetLeftHandOpenFingerAngles(tbl)
		local t = table.Copy(g_VR.openHandAngles)
		for i = 1, 15 do
			t[i] = tbl[i]
		end

		g_VR.openHandAngles = t
	end

	function vrmod.SetLeftHandClosedFingerAngles(tbl)
		local t = table.Copy(g_VR.closedHandAngles)
		for i = 1, 15 do
			t[i] = tbl[i]
		end

		g_VR.closedHandAngles = t
	end

	function vrmod.SetRightHandOpenFingerAngles(tbl)
		local t = table.Copy(g_VR.openHandAngles)
		for i = 1, 15 do
			t[15 + i] = tbl[i]
		end

		g_VR.openHandAngles = t
	end

	function vrmod.SetRightHandClosedFingerAngles(tbl)
		local t = table.Copy(g_VR.closedHandAngles)
		for i = 1, 15 do
			t[15 + i] = tbl[i]
		end

		g_VR.closedHandAngles = t
	end

	function vrmod.GetDefaultLeftHandOpenFingerAngles()
		local r = {}
		for i = 1, 15 do
			r[i] = g_VR.defaultOpenHandAngles[i]
		end
		return r
	end

	function vrmod.GetDefaultLeftHandClosedFingerAngles()
		local r = {}
		for i = 1, 15 do
			r[i] = g_VR.defaultClosedHandAngles[i]
		end
		return r
	end

	function vrmod.GetDefaultRightHandOpenFingerAngles()
		local r = {}
		for i = 1, 15 do
			r[i] = g_VR.defaultOpenHandAngles[15 + i]
		end
		return r
	end

	function vrmod.GetDefaultRightHandClosedFingerAngles()
		local r = {}
		for i = 1, 15 do
			r[i] = g_VR.defaultClosedHandAngles[15 + i]
		end
		return r
	end

	local fingerAngleCache = {}
	local fingerAngleCachePM = ""
	local function GetFingerAnglesFromModel(modelName, sequenceNumber)
		sequenceNumber = sequenceNumber or 0
		local pm = convars.vrmod_floatinghands:GetBool() and "models/weapons/c_arms.mdl" or LocalPlayer():GetModel()
		if fingerAngleCachePM ~= pm then
			fingerAngleCachePM = pm
			fingerAngleCache = {}
		end

		local cache = fingerAngleCache[modelName .. sequenceNumber]
		if cache then return cache end
		--
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
		fingerAngleCache[modelName .. sequenceNumber] = r
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
		local ent = ClientsideModel(modelName)
		ent:ResetSequence(sequenceNumber or 0)
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
		return IsValid(ply) and g_VR[ply:SteamID()] ~= nil
	end

	function vrmod.UsingEmptyHands(ply)
		if not IsValid(ply) then return false end
		local wep = ply:GetActiveWeapon()
		return IsValid(wep) and wep:GetClass() == "weapon_vrmod_empty"
	end

	function vrmod.GetHeldEntity(ply, hand)
		if not IsValid(ply) or hand ~= "left" and hand ~= "right" then return nil end
		local sid, data = ply:SteamID(), g_VR[ply:SteamID()] and g_VR[ply:SteamID()].heldItems
		if not data then return nil end
		local info = data[hand == "left" and 1 or 2]
		return IsValid(info and info.ent) and info.ent or nil
	end

	local function AngleDifference(a1, a2)
		local diff = a1 - a2
		diff.p = math.NormalizeAngle(diff.p)
		diff.y = math.NormalizeAngle(diff.y)
		diff.r = math.NormalizeAngle(diff.r)
		return diff
	end

	local function UpdateWorldPoses(ply, playerTable)
		if not IsValid(ply) then return end
		local frame = playerTable.latestFrame
		if not frame then return end
		local frameID = engine.TickCount()
		local world = playerTable.latestFrameWorld or {}
		if world._cachedFrameID == frameID then return end
		world._cachedFrameID = frameID
		playerTable.latestFrameWorld = world
		local sid = ply:SteamID()
		local refPos = ply:GetPos()
		local refAng = ply:InVehicle() and ply:GetVehicle():GetAngles() or Angle()
		-- World pose conversion
		world.hmdPos, world.hmdAng = LocalToWorld(frame.hmdPos, frame.hmdAng, refPos, refAng)
		world.lefthandPos, world.lefthandAng = LocalToWorld(frame.lefthandPos, frame.lefthandAng, refPos, refAng)
		world.righthandPos, world.righthandAng = LocalToWorld(frame.righthandPos, frame.righthandAng, refPos, refAng)
		-- Velocity cache
		local cache = vrmod.HandVelocityCache[sid]
		if not cache then
			cache = {
				leftLastPos = world.lefthandPos,
				rightLastPos = world.righthandPos,
				hmdLastPos = world.hmdPos,
				leftLastAng = world.lefthandAng,
				rightLastAng = world.righthandAng,
				leftVel = Vector(),
				rightVel = Vector(),
				hmdVel = Vector(),
				leftAngVel = Angle(),
				rightAngVel = Angle(),
				lastTick = 0
			}

			vrmod.HandVelocityCache[sid] = cache
		end

		local dt = (frameID - cache.lastTick) * engine.TickInterval()
		if cache.lastTick ~= 0 and dt > 0 then
			cache.leftVel = (world.lefthandPos - cache.leftLastPos) / dt
			cache.rightVel = (world.righthandPos - cache.rightLastPos) / dt
			cache.hmdVel = (world.hmdPos - cache.hmdLastPos) / dt
			local deltaLeftAng = AngleDifference(world.lefthandAng, cache.leftLastAng)
			local deltaRightAng = AngleDifference(world.righthandAng, cache.rightLastAng)
			cache.leftAngVel = Angle(deltaLeftAng.p / dt, deltaLeftAng.y / dt, deltaLeftAng.r / dt)
			cache.rightAngVel = Angle(deltaRightAng.p / dt, deltaRightAng.y / dt, deltaRightAng.r / dt)
		end

		cache.leftLastPos = world.lefthandPos
		cache.rightLastPos = world.righthandPos
		cache.hmdLastPos = world.hmdPos
		cache.leftLastAng = world.lefthandAng
		cache.rightLastAng = world.righthandAng
		cache.lastTick = frameID
	end

	-- === Accessors === --
	local function GetCachedPlayerTable(ply)
		if not IsValid(ply) then return nil end
		return g_VR[ply:SteamID()]
	end

	local function GetCachedWorld(ply)
		local t = GetCachedPlayerTable(ply)
		if not t or not t.latestFrame then return nil end
		UpdateWorldPoses(ply, t)
		return t.latestFrameWorld
	end

	local function GetCachedVelocity(ply)
		local sid = ply:SteamID()
		local cache = vrmod.HandVelocityCache[sid]
		if not cache then
			UpdateWorldPoses(ply, GetCachedPlayerTable(ply))
			cache = vrmod.HandVelocityCache[sid]
		end
		return cache
	end

	function vrmod.GetHMDPose(ply)
		local w = GetCachedWorld(ply)
		return w and w.hmdPos or Vector(), w and w.hmdAng or Angle()
	end

	function vrmod.GetLeftHandPose(ply)
		local w = GetCachedWorld(ply)
		return w and w.lefthandPos or Vector(), w and w.lefthandAng or Angle()
	end

	function vrmod.GetRightHandPose(ply)
		local w = GetCachedWorld(ply)
		return w and w.righthandPos or Vector(), w and w.righthandAng or Angle()
	end

	function vrmod.GetHMDVelocity(ply)
		local c = GetCachedVelocity(ply)
		return c and c.hmdVel or Vector()
	end

	function vrmod.GetLeftHandVelocity(ply)
		local c = GetCachedVelocity(ply)
		return c and c.leftVel or Vector()
	end

	function vrmod.GetRightHandVelocity(ply)
		local c = GetCachedVelocity(ply)
		return c and c.rightVel or Vector()
	end

	function vrmod.GetLeftHandVelocityRelative(ply)
		return vrmod.GetLeftHandVelocity(ply) - vrmod.GetHMDVelocity(ply)
	end

	function vrmod.GetRightHandVelocityRelative(ply)
		return vrmod.GetRightHandVelocity(ply) - vrmod.GetHMDVelocity(ply)
	end

	function vrmod.GetLeftHandAngularVelocity(ply)
		local c = GetCachedVelocity(ply)
		return c and c.leftAngVel or Angle()
	end

	function vrmod.GetRightHandAngularVelocity(ply)
		local c = GetCachedVelocity(ply)
		return c and c.rightAngVel or Angle()
	end

	function vrmod.GetPullGestureStrength(ply, hand, targetPos)
		if not IsValid(ply) then return end
		local handPos = hand == "left" and vrmod.GetLeftHandPos(ply) or vrmod.GetRightHandPos(ply)
		local relVel = hand == "left" and vrmod.GetLeftHandVelocityRelative(ply) or vrmod.GetRightHandVelocityRelative(ply)
		local pullDir = (targetPos - handPos):GetNormalized()
		return relVel:Dot(pullDir)
	end
end

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