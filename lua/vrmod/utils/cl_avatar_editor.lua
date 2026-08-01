-- =============================================================================
-- vrmod.avatar — Cube player customization twin
--
-- CLONE IS EASY when done right (0c6d4b9 SoT):
--   Player IK already solved → PublishPlayerPose (full bone VMatrices)
--   Twin = pure world translate of those matrices (same orientation)
--   NO charik.Update on twin, NO reparent, NO head scale, NO Euler
--
-- Placement moves stand XY only. Never VRUtilNetUpdateLocalPly from twin.
-- Credits: Pescorr · Catse — docs/CREDITS.md · Workshop 3695733221
-- =============================================================================
if SERVER then return end

vrmod = vrmod or {}
vrmod.avatar = vrmod.avatar or {}

local BONES = {
	head = "ValveBiped.Bip01_Head1",
	pelvis = "ValveBiped.Bip01_Pelvis",
	spine = "ValveBiped.Bip01_Spine",
	spine1 = "ValveBiped.Bip01_Spine1",
	spine2 = "ValveBiped.Bip01_Spine2",
	spine4 = "ValveBiped.Bip01_Spine4",
	lClav = "ValveBiped.Bip01_L_Clavicle",
	rClav = "ValveBiped.Bip01_R_Clavicle",
	lHand = "ValveBiped.Bip01_L_Hand",
	rHand = "ValveBiped.Bip01_R_Hand",
	lFore = "ValveBiped.Bip01_L_Forearm",
	rFore = "ValveBiped.Bip01_R_Forearm",
	lUpper = "ValveBiped.Bip01_L_UpperArm",
	rUpper = "ValveBiped.Bip01_R_UpperArm",
	lFoot = "ValveBiped.Bip01_L_Foot",
	rFoot = "ValveBiped.Bip01_R_Foot",
	lThigh = "ValveBiped.Bip01_L_Thigh",
	rThigh = "ValveBiped.Bip01_R_Thigh",
	lCalf = "ValveBiped.Bip01_L_Calf",
	rCalf = "ValveBiped.Bip01_R_Calf",
}

local sessions = {}
local DEFAULT_PELVIS_OFFSET = 30
local DEFAULT_SHOULDER_W = 8
local VEC_ZERO = Vector(0, 0, 0)
local VEC_ONE = Vector(1, 1, 1)
local VEC_TINY = Vector(0.001, 0.001, 0.001)
-- ValveBiped right-hand bone convention (matches cl_character / floating hands)
local RIGHT_HAND_OFFSET = Angle(0, 0, 180)

-- Persist customization
local cv_model = CreateClientConVar("vrmod_avatar_model", "", true, FCVAR_ARCHIVE)
local cv_skin = CreateClientConVar("vrmod_avatar_skin", "0", true, FCVAR_ARCHIVE)
local cv_body = CreateClientConVar("vrmod_avatar_bodygroups", "", true, FCVAR_ARCHIVE)
local cv_hide_head = CreateClientConVar("vrmod_avatar_hide_head", "0", true, FCVAR_ARCHIVE)
local cv_hide_hands = CreateClientConVar("vrmod_avatar_hide_hands", "0", true, FCVAR_ARCHIVE)
local cv_distance = CreateClientConVar("vrmod_avatar_distance", "40", true, FCVAR_ARCHIVE)
-- free = point RH + right stick rotate/distance (default)
-- facing/mirror, clone, world = legacy
local cv_mode = CreateClientConVar("vrmod_avatar_mode", "free", true, FCVAR_ARCHIVE)
local cv_yaw = CreateClientConVar("vrmod_avatar_yaw_off", "180", true, FCVAR_ARCHIVE,
	"Initial twin yaw offset vs player (180 = face you)")
local cv_steer_rate = CreateClientConVar("vrmod_avatar_steer_rate", "120", true, FCVAR_ARCHIVE,
	"Twin yaw deg/sec from right thumbstick", 30, 360)
local cv_dist_rate = CreateClientConVar("vrmod_avatar_dist_rate", "40", true, FCVAR_ARCHIVE,
	"Twin distance units/sec from right thumbstick Y", 10, 120)
-- Semicolon-separated bone names hidden via laser pick
local cv_hidden_bones = CreateClientConVar("vrmod_avatar_hidden_bones", "", true, FCVAR_ARCHIVE)



local function ParseHiddenBones(str)
	local t = {}
	if not str or str == "" then return t end
	for name in string.gmatch(str, "[^;]+") do
		name = string.Trim(name)
		if name ~= "" then t[name] = true end
	end
	return t
end

local function EncodeHiddenBones(map)
	local parts = {}
	for name in pairs(map or {}) do
		parts[#parts + 1] = name
	end
	table.sort(parts)
	return table.concat(parts, ";")
end

local function CopyLooks(dst, src)
	if not IsValid(dst) or not IsValid(src) then return end
	dst:SetSkin(src:GetSkin() or 0)
	for i = 0, (src:GetNumBodyGroups() or 1) - 1 do
		dst:SetBodygroup(i, src:GetBodygroup(i))
	end
	if dst.SetPlayerColor and src.GetPlayerColor then
		pcall(function() dst:SetPlayerColor(src:GetPlayerColor()) end)
	end
end

local function Lookup(ent, name)
	local id = ent:LookupBone(name)
	return (id and id >= 0) and id or nil
end

local function SolveTwoBoneIK(shoulder, hand, lenUpper, lenLower, poleHint)
	local toHand = hand - shoulder
	local dist = toHand:Length()
	if dist < 0.01 then
		return shoulder + poleHint * lenUpper
	end
	local maxReach = lenUpper + lenLower - 0.1
	if dist >= maxReach then
		return shoulder + toHand:GetNormalized() * lenUpper
	end
	local cosA = (lenUpper * lenUpper + dist * dist - lenLower * lenLower) / (2 * lenUpper * dist)
	cosA = math.Clamp(cosA, -1, 1)
	local angleA = math.acos(cosA)
	local fwd = toHand / dist
	local projHint = poleHint - fwd * poleHint:Dot(fwd)
	if projHint:LengthSqr() < 0.001 then
		projHint = Vector(0, 0, -1) - fwd * fwd.z
		if projHint:LengthSqr() < 0.001 then projHint = Vector(0, 1, 0) end
	end
	projHint:Normalize()
	local elbowDir = fwd * math.cos(angleA) + projHint * math.sin(angleA)
	return shoulder + elbowDir * lenUpper
end

local function AngleBetween(fromPos, toPos)
	local dir = toPos - fromPos
	if dir:LengthSqr() < 0.01 then return Angle(0, 0, 0) end
	return dir:Angle()
end

-- Source local frame (playerYaw): X=Forward, Y=Right, Z=Up.

--- CLONE: rigid reparent of world bone into twin stand (no flip).
local function MapClone(worldPos, worldAng, srcFeet, srcYaw, dstFeet, dstYaw)
	local relPos, relAng = WorldToLocal(worldPos, worldAng or Angle(), srcFeet, srcYaw)
	return LocalToWorld(relPos, relAng, dstFeet, dstYaw)
end

--- MIRROR: same as clone, but flip Right (Y) in source local, then place at dst.
local function MapMirrorWorld(worldPos, worldAng, srcFeet, srcYaw, dstFeet, dstYaw)
	local relPos, relAng = WorldToLocal(worldPos, worldAng or Angle(), srcFeet, srcYaw)
	relPos.y = -relPos.y
	relAng = Angle(relAng.p, -relAng.y, -relAng.r)
	return LocalToWorld(relPos, relAng, dstFeet, dstYaw)
end

--- Deep-copy bone matrix (shallow Matrix(m) can share userdata → twin corkscrew).
-- Exact basis copy — do NOT Normalize axes (breaks orthonormality → cone-head shear).
local function DupMat(src)
	if not src then return nil end
	local m = Matrix()
	local tr = src:GetTranslation()
	m:SetTranslation(Vector(tr.x, tr.y, tr.z))
	local f, r, u = src:GetForward(), src:GetRight(), src:GetUp()
	m:SetForward(Vector(f.x, f.y, f.z))
	m:SetRight(Vector(r.x, r.y, r.z))
	m:SetUp(Vector(u.x, u.y, u.z))
	return m
end

--- Rotate a vector around world Z by dYaw degrees (no Euler bone decomp).
local function RotYaw(v, dYaw)
	if not v then return Vector() end
	local a = math.rad(dYaw)
	local c, s = math.cos(a), math.sin(a)
	return Vector(v.x * c - v.y * s, v.x * s + v.y * c, v.z)
end

--- Rigid reparent: move bone from player feet frame → twin feet frame (yaw only).
-- Position: WorldToLocal / LocalToWorld in feet frames.
-- Orientation: rotate bone basis by Δyaw around Z — NEVER Matrix:GetAngles / inv multiply.
local function ReparentMat(srcMat, srcFeet, srcYaw, dstFeet, dstYaw)
	if not srcMat then return nil end
	srcFeet = srcFeet or Vector()
	dstFeet = dstFeet or Vector()
	srcYaw = srcYaw or Angle()
	dstYaw = dstYaw or Angle()
	local dYaw = dstYaw.yaw - srcYaw.yaw

	local pos = srcMat:GetTranslation()
	local relPos = WorldToLocal(pos, Angle(), srcFeet, srcYaw)
	local newPos = LocalToWorld(relPos, Angle(), dstFeet, dstYaw)

	-- Rotate full basis as a rigid body around world Z (preserves orthonormality)
	local f = RotYaw(srcMat:GetForward(), dYaw)
	local r = RotYaw(srcMat:GetRight(), dYaw)
	local u = RotYaw(srcMat:GetUp(), dYaw)

	local m = Matrix()
	m:SetTranslation(newPos)
	m:SetForward(f)
	m:SetRight(r)
	m:SetUp(u)
	return m
end

--- Pure world translate (identical orientation to player). Proven SoT.
local function TranslateMat(srcMat, off)
	local m = DupMat(srcMat)
	if not m then return nil end
	local t = m:GetTranslation()
	m:SetTranslation(Vector(t.x + off.x, t.y + off.y, t.z + off.z))
	return m
end

-- Legacy name helpers (bone-map UI only — pose path does NOT rename bones)
local function MirrorBoneName(name)
	if not name or name == "" then return name end
	if string.find(name, "_L_", 1, true) then
		return (string.gsub(name, "_L_", "_R_", 1))
	end
	if string.find(name, "_R_", 1, true) then
		return (string.gsub(name, "_R_", "_L_", 1))
	end
	if string.find(name, "Left", 1, true) then
		return (string.gsub(name, "Left", "Right", 1))
	end
	if string.find(name, "Right", 1, true) then
		return (string.gsub(name, "Right", "Left", 1))
	end
	return name
end

local function ParseBodygroups(str)
	local t = {}
	if not str or str == "" then return t end
	for pair in string.gmatch(str, "[^;]+") do
		local a, b = string.match(pair, "(%d+):(%d+)")
		if a then t[tonumber(a)] = tonumber(b) end
	end
	return t
end

local function EncodeBodygroups(ent)
	if not IsValid(ent) then return "" end
	local parts = {}
	for i = 0, (ent:GetNumBodyGroups() or 1) - 1 do
		local v = ent:GetBodygroup(i)
		if v and v > 0 then
			parts[#parts + 1] = i .. ":" .. v
		end
	end
	return table.concat(parts, ";")
end

local function ApplyBodygroups(ent, map)
	if not IsValid(ent) or not map then return end
	for i, v in pairs(map) do
		if isnumber(i) and isnumber(v) then
			ent:SetBodygroup(i, v)
		end
	end
end

local Session = {}
Session.__index = Session

function Session:IsValid()
	return self.active and IsValid(self.ent)
end

function Session:GetEntity()
	return self.ent
end

function Session:GetStand()
	return self.standPos, self.standAng
end

function Session:Close()
	if not self.active then return end
	self.active = false
	hook.Remove("PostDrawTranslucentRenderables", self.hookId)
	hook.Remove("Think", self.thinkId)
	hook.Remove("VRMod_PreStereo", self.thinkId .. "_pose")
	if self.boneCb and IsValid(self.ent) then
		self.ent:RemoveCallback("BuildBonePositions", self.boneCb)
		self.boneCb = nil
	end
	if IsValid(self.ent) then self.ent:Remove() end
	self.ent = nil
	self.targets = nil
	if self.hideLocalPlayer then
		local ply = LocalPlayer()
		if IsValid(ply) then ply.RenderOverride = nil end
	end
	sessions[self.id] = nil
	-- Release right-stick steer if no free twin remains
	local anyFree = false
	for _, s in pairs(sessions) do
		if s and s.active and s.mode == "free" then anyFree = true break end
	end
	if not anyFree then g_VR.avatarSteerTwin = false end
	if self.onClose then pcall(self.onClose, self) end
end

function Session:_cacheBones()
	local e = self.ent
	self.bones = {}
	for k, name in pairs(BONES) do
		self.bones[k] = Lookup(e, name)
	end
	self.bones.chest = self.bones.spine2 or self.bones.spine4 or self.bones.spine1 or self.bones.spine
	self:_buildMirrorBoneMap()
end

local function IsValidBoneName(name)
	if not name or name == "" then return false end
	if name == "__INVALIDBONE__" then return false end
	if string.StartWith(name, "ValveBiped") or string.find(name, "Bip01", 1, true) then
		return true
	end
	-- allow non-Valve names that still L/R swap
	return true
end

--- Cache player bone id → twin bone id for mirror mode (L↔R). Avoids per-frame LookupBone.
function Session:_buildMirrorBoneMap()
	self.mirrorBoneMap = {} -- [playerBoneId] = twinBoneId (same skel path)
	local e = self.ent
	if not IsValid(e) then return end
	local n = e:GetBoneCount() or 0
	for i = 0, n - 1 do
		local bn = e:GetBoneName(i)
		if IsValidBoneName(bn) then
			local mn = MirrorBoneName(bn)
			if mn ~= bn then
				local tid = e:LookupBone(mn)
				if tid and tid >= 0 then
					self.mirrorBoneMap[i] = tid
				else
					self.mirrorBoneMap[i] = i -- no pair → keep (center-like)
				end
			else
				self.mirrorBoneMap[i] = i -- spine/head/pelvis
			end
		end
	end
end

function Session:_measureArms()
	local e = self.ent
	local b = self.bones
	self.upperArmLen, self.forearmLen = 12, 12
	self.upperLegLen, self.lowerLegLen = 16, 16
	e:SetupBones()
	if b.rUpper and b.rFore and b.rHand then
		local mu, mf, mh = e:GetBoneMatrix(b.rUpper), e:GetBoneMatrix(b.rFore), e:GetBoneMatrix(b.rHand)
		if mu and mf and mh then
			local u, f, h = mu:GetTranslation(), mf:GetTranslation(), mh:GetTranslation()
			self.upperArmLen = math.max(4, u:Distance(f))
			self.forearmLen = math.max(4, f:Distance(h))
		end
	end
	if b.lThigh and b.lCalf and b.lFoot then
		local mt, mc, mf = e:GetBoneMatrix(b.lThigh), e:GetBoneMatrix(b.lCalf), e:GetBoneMatrix(b.lFoot)
		if mt and mc and mf then
			local t, c, f = mt:GetTranslation(), mc:GetTranslation(), mf:GetTranslation()
			self.upperLegLen = math.max(4, t:Distance(c))
			self.lowerLegLen = math.max(4, c:Distance(f))
		end
	end
end

function Session:SetModel(path, opts)
	if not self:IsValid() or not path or path == "" then return false end
	opts = opts or {}
	util.PrecacheModel(path)
	self.ent:SetModel(path)
	self.model = path
	-- Preview only: do NOT archive to cv_model unless explicitly saved (ApplyToPlayer)
	if opts.persist then
		cv_model:SetString(path)
	end

	-- Preview: reset skin/body to model defaults unless keepLooks
	if opts.keepLooks then
		self.ent:SetSkin(cv_skin:GetInt())
		ApplyBodygroups(self.ent, ParseBodygroups(cv_body:GetString()))
	else
		self.ent:SetSkin(0)
	end

	self.ent:SetupBones()
	self:_cacheBones()
	self:_measureArms()
	-- Pure-paste path: drop any IK state; clear targets so next frame rebuilds
	self.ik = nil
	self.targets = {}
	self.hideHead = false
	self.hideHands = false
	self:_applyHideBones()

	-- Preview twin model change: refresh snap from live player IK (no full player reload)
	timer.Simple(0, function()
		if not self.active then return end
		if vrmod.character and vrmod.character.ForceLocalIKAndPublish then
			pcall(vrmod.character.ForceLocalIKAndPublish)
		end
	end)
	if vrmod.logger then
		vrmod.logger.Info("[Avatar] twin model → %s (preview, bone cache refresh)", path)
	end
	return true
end

--- Resolve playermodel name for a .mdl path
function Session:ModelName()
	local path = self.model or (IsValid(self.ent) and self.ent:GetModel()) or ""
	if path == "" then return nil end
	if player_manager and player_manager.TranslateToPlayerModelName then
		local n = player_manager.TranslateToPlayerModelName(path)
		if n and n ~= "" and n ~= "unknown" then return n end
	end
	if player_manager and player_manager.AllValidModels then
		for name, p in pairs(player_manager.AllValidModels()) do
			if p == path then return name end
		end
	end
	return nil
end

local function ApplyLooksToEnt(ent, path, skin, bodyMap)
	if not IsValid(ent) then return end
	if path and path ~= "" then
		util.PrecacheModel(path)
		ent:SetModel(path)
	end
	ent:SetSkin(skin or 0)
	if bodyMap then
		for i, v in pairs(bodyMap) do
			if isnumber(i) and isnumber(v) then ent:SetBodygroup(i, v) end
		end
	end
	ent:SetupBones()
end

--- Persist twin customization onto the REAL player + full VR character IK reload.
function Session:ApplyToPlayer()
	if not self:IsValid() then return false, "no twin" end
	local ply = LocalPlayer()
	if not IsValid(ply) then return false, "no player" end
	if not g_VR or not g_VR.active then return false, "VR inactive" end

	local path = self.ent:GetModel()
	local skin = self.ent:GetSkin() or 0
	local bodyStr = EncodeBodygroups(self.ent)
	local bodyMap = ParseBodygroups(bodyStr)
	local hidden = EncodeHiddenBones(self.customHidden)

	cv_model:SetString(path or "")
	cv_skin:SetInt(skin)
	cv_body:SetString(bodyStr)
	cv_hidden_bones:SetString(hidden)
	ply.vrmod_pm = path

	local name = self:ModelName()
	if name then
		RunConsoleCommand("cl_playermodel", name)
	end
	RunConsoleCommand("cl_playerskin", tostring(skin))

	local parts = {}
	for i = 0, (self.ent:GetNumBodyGroups() or 1) - 1 do
		parts[#parts + 1] = tostring(self.ent:GetBodygroup(i) or 0)
	end
	if #parts > 0 then
		RunConsoleCommand("cl_playerbodygroups", table.concat(parts, " "))
	end

	-- 1) Apply looks immediately on client player
	pcall(ApplyLooksToEnt, ply, path, skin, bodyMap)
	ply.vrmod_pm = path

	-- 2) Full character/FBT reload (safe for incomplete PMs — soft IK fail, no crash)
	if g_VR.ReloadCharacterSystem then
		pcall(g_VR.ReloadCharacterSystem, ply, "avatar_apply")
	elseif vrmod.character and vrmod.character.Reload then
		pcall(vrmod.character.Reload, ply, "avatar_apply")
	end

	-- 3) Twin follows after reload settles
	timer.Simple(0.15, function()
		if not IsValid(ply) or not g_VR or not g_VR.active then return end
		pcall(ApplyLooksToEnt, ply, path, skin, bodyMap)
		ply.vrmod_pm = path
		local twin = vrmod.avatar and vrmod.avatar.Get and vrmod.avatar.Get("avatar")
		if twin and twin:IsValid() then
			if path and twin.SetModel then
				twin:SetModel(path, { persist = true, keepLooks = true })
			end
			if twin.SetSkin then twin:SetSkin(skin) end
			if IsValid(twin.ent) and bodyMap then
				ApplyBodygroups(twin.ent, bodyMap)
			end
			twin.hideHead = false
			twin.hideHands = false
			if twin._applyHideBones then twin:_applyHideBones() end
			if twin._cacheBones then twin:_cacheBones() end
			if twin._measureArms then twin:_measureArms() end
		end
		if vrmod.character and vrmod.character.ForceLocalIKAndPublish then
			pcall(vrmod.character.ForceLocalIKAndPublish)
		end
		if vrmod.logger then
			vrmod.logger.Info("[Avatar] character IK reloaded after apply PM=%s", tostring(name or path))
		end
	end)

	if vrmod.logger then
		vrmod.logger.Info("[Avatar] apply→player PM=%s skin=%d body=%s (IK reload queued)",
			tostring(name or path), skin, bodyStr)
	end
	return true, name or path
end

function Session:SetSkin(idx)
	if not self:IsValid() then return end
	idx = math.floor(tonumber(idx) or 0)
	self.ent:SetSkin(idx)
	cv_skin:SetInt(idx)
end

function Session:CycleBodygroup(bgId, delta)
	if not self:IsValid() then return end
	bgId = math.floor(tonumber(bgId) or 0)
	local n = self.ent:GetBodygroupCount(bgId) or 1
	if n <= 1 then return end
	local cur = self.ent:GetBodygroup(bgId) or 0
	local nxt = (cur + (delta or 1)) % n
	if nxt < 0 then nxt = n - 1 end
	self.ent:SetBodygroup(bgId, nxt)
	cv_body:SetString(EncodeBodygroups(self.ent))
end

function Session:SetHideHead(on)
	self.hideHead = on and true or false
	cv_hide_head:SetBool(self.hideHead)
	self:_applyHideBones()
end

function Session:SetHideHands(on)
	self.hideHands = on and true or false
	cv_hide_hands:SetBool(self.hideHands)
	self:_applyHideBones()
end

function Session:_applyHideBones()
	if not self:IsValid() then return end
	local e = self.ent
	local b = self.bones
	local function scaleBone(id, v)
		if id then e:ManipulateBoneScale(id, v) end
	end

	-- Always reset every bone scale first (prevents cone-head from leftover tiny head)
	local n = e:GetBoneCount() or 0
	for i = 0, n - 1 do
		e:ManipulateBoneScale(i, VEC_ONE)
		e:ManipulateBonePosition(i, VEC_ZERO)
	end

	-- Head hide on TWIN is always off (tiny head = cone spike). Only hands/custom optional.
	self.hideHead = false
	if self.hideHands then
		scaleBone(b.lHand, VEC_TINY)
		scaleBone(b.rHand, VEC_TINY)
		scaleBone(b.lFore, VEC_TINY)
		scaleBone(b.rFore, VEC_TINY)
	end

	self.customHidden = self.customHidden or {}
	for name in pairs(self.customHidden) do
		-- Never hide head bone via custom pick either
		if name and (string.find(name, "Head", 1, true) or name == "ValveBiped.Bip01_Head1") then
			continue
		end
		local id = e:LookupBone(name)
		if (not id or id < 0) and string.match(name, "^#(%d+)$") then
			id = tonumber(string.match(name, "^#(%d+)$"))
		end
		if id and id >= 0 then
			e:ManipulateBoneScale(id, VEC_TINY)
		end
	end
end

function Session:_saveCustomHidden()
	cv_hidden_bones:SetString(EncodeHiddenBones(self.customHidden))
end

--- Closest bone to a world ray (right-hand laser). Returns boneId, name, hitPos, distToBone
function Session:RayPickBone(origin, dir, maxDist, maxRadius)
	if not self:IsValid() or not origin or not dir then return nil end
	maxDist = maxDist or 250
	maxRadius = maxRadius or 6 -- units: how close ray must pass to bone
	dir = dir:GetNormalized()
	self.ent:SetupBones()

	local bestId, bestName, bestHit, bestD = nil, nil, nil, maxRadius
	local n = self.ent:GetBoneCount() or 0
	for i = 0, n - 1 do
		local m = self.ent:GetBoneMatrix(i)
		if not m then continue end
		local p = m:GetTranslation()
		local toP = p - origin
		local along = toP:Dot(dir)
		if along < 2 or along > maxDist then continue end
		local closest = origin + dir * along
		local d = closest:Distance(p)
		if d < bestD then
			bestD = d
			bestId = i
			bestHit = closest
			bestName = self.ent:GetBoneName(i)
			if not bestName or bestName == "" then bestName = "#" .. i end
		end
	end
	return bestId, bestName, bestHit, bestD
end

--- Toggle hide for a bone (by id). Persists name in vrmod_avatar_hidden_bones.
function Session:ToggleCustomBone(boneId)
	if not self:IsValid() or not boneId or boneId < 0 then return false, nil, false end
	local name = self.ent:GetBoneName(boneId)
	if not name or name == "" then name = "#" .. boneId end
	self.customHidden = self.customHidden or {}
	local nowHidden
	if self.customHidden[name] then
		self.customHidden[name] = nil
		nowHidden = false
	else
		self.customHidden[name] = true
		nowHidden = true
	end
	self:_saveCustomHidden()
	self:_applyHideBones()
	return true, name, nowHidden
end

function Session:ClearCustomHidden()
	self.customHidden = {}
	self:_saveCustomHidden()
	self:_applyHideBones()
end

function Session:IsBoneCustomHidden(boneId)
	if not self:IsValid() or not boneId then return false end
	local name = self.ent:GetBoneName(boneId)
	if not name or name == "" then name = "#" .. boneId end
	return self.customHidden and self.customHidden[name] and true or false
end

function Session:GetHoverBone()
	return self.hoverBoneId, self.hoverBoneName, self.hoverBonePos
end

--- Update hover from RH laser each frame (call while Avatar menu open)
function Session:UpdateLaserHover()
	self.hoverBoneId, self.hoverBoneName, self.hoverBonePos = nil, nil, nil
	if not self:IsValid() or not g_VR.tracking then return end
	local rh = g_VR.tracking.pose_righthand
	if not rh or not rh.pos or not rh.ang then return end
	local id, name, hit = self:RayPickBone(rh.pos, rh.ang:Forward(), 250, 7)
	self.hoverBoneId = id
	self.hoverBoneName = name
	self.hoverBonePos = hit
end

function Session:SetMode(mode)
	if mode == "mirror" then mode = "facing" end
	if mode ~= "free" and mode ~= "facing" and mode ~= "clone" and mode ~= "world" then return end
	self.mode = mode
	self.idleOnly = false
	self.algoDigit = nil
	self.algoPolicy = nil
	self.forceFBT = nil
	-- free + clone + world = no L↔R; facing = true mirror
	self.mirrorLR = (mode == "facing")
	cv_mode:SetString(mode)
	if mode == "free" then
		self.freeInited = false -- re-seed placement next frame
	end
end

function Session:SetDistance(d)
	self.distance = math.Clamp(tonumber(d) or 40, 20, 120)
	cv_distance:SetFloat(self.distance)
end

function Session:_isFreeMode()
	local mode = self.mode or "free"
	if mode == "mirror" then mode = "facing" end
	return mode == "free" or mode == ""
end

function Session:_isClonePose()
	-- free uses clone matrices (same laterality)
	local mode = self.mode or "free"
	if mode == "mirror" then mode = "facing" end
	return mode == "free" or mode == "clone" or mode == "world"
end

--- RH aim place + grips spin/distance (no thumbstick).
-- Right grip + twist RH yaw → spin twin.
-- Left grip + move LH along aim → distance.
-- While gripping, consumes grips (no world pickup / no menu grab fight if not on menu).
function Session:_updateFreeControls(playerFeet, playerYaw)
	if not self:_isFreeMode() then
		g_VR.avatarSteerTwin = false
		return
	end

	local tr = g_VR.tracking
	local rh = tr and tr.pose_righthand
	local lh = tr and tr.pose_lefthand
	local aim = self.freeAimDir
	if rh and rh.ang then
		local f = rh.ang:Forward()
		f.z = 0
		if f:LengthSqr() > 0.01 then
			f:Normalize()
			aim = f
			self.freeAimDir = f
		end
	end
	if not aim then
		aim = playerYaw and playerYaw:Forward() or Vector(1, 0, 0)
		self.freeAimDir = aim
	end

	local inp = g_VR.input
	local rightGrip = inp and inp.boolean_right_pickup and true or false
	local leftGrip = inp and inp.boolean_left_pickup and true or false

	-- Only panel free-grab steals grips (menu laser focus alone does not)
	local menuOwnsGrips = g_VR.menuGrabActive and true or false

	if not self.freeInited then
		local dist = self.distance or cv_distance:GetFloat()
		local py = (playerYaw and playerYaw.yaw) or 0
		self.standPos = playerFeet + aim * dist
		self.freeYaw = py -- start facing same as player; R-grip twist to rotate
		self.standAng = Angle(0, self.freeYaw, 0)
		self.freeInited = true
	end

	local steering = false
	if not menuOwnsGrips then
		-- Right grip + twist RH: free-yaw spin (1:1 with controller)
		if rightGrip and rh and rh.ang then
			steering = true
			local rhYaw = rh.ang.yaw
			if not self.gripSpinActive then
				self.gripSpinActive = true
				self.gripSpinOffset = rhYaw - (self.freeYaw or 0)
			end
			self.freeYaw = rhYaw - (self.gripSpinOffset or 0)
		else
			self.gripSpinActive = false
		end

		-- Left grip: push/pull distance along aim
		if leftGrip and lh and lh.pos then
			steering = true
			local toHand = lh.pos - playerFeet
			local along = toHand.x * aim.x + toHand.y * aim.y
			if not self.gripDistActive then
				self.gripDistActive = true
				self.gripDistBase = self.distance or 40
				self.gripDistAlong0 = along
			end
			local delta = along - (self.gripDistAlong0 or along)
			self.distance = math.Clamp((self.gripDistBase or 40) + delta, 20, 120)
			cv_distance:SetFloat(self.distance)
		else
			self.gripDistActive = false
		end
	else
		self.gripSpinActive = false
		self.gripDistActive = false
	end

	g_VR.avatarSteerTwin = steering

	-- Freeze place while gripping / bone-pick / laser on avatar menu
	local freezePlace = steering
		or (self.laserPickBones and self.hoverBoneId)
		or (self.menuUid and g_VR.menuFocus == self.menuUid)

	local dist = self.distance or 40
	if not freezePlace then
		self.standPos = Vector(
			playerFeet.x + aim.x * dist,
			playerFeet.y + aim.y * dist,
			playerFeet.z
		)
	else
		local flat = (self.standPos or playerFeet) - playerFeet
		flat.z = 0
		if flat:LengthSqr() > 4 then
			flat:Normalize()
			self.standPos = Vector(
				playerFeet.x + flat.x * dist,
				playerFeet.y + flat.y * dist,
				playerFeet.z
			)
		else
			self.standPos = Vector(
				playerFeet.x + aim.x * dist,
				playerFeet.y + aim.y * dist,
				playerFeet.z
			)
		end
	end

	self.standAng = Angle(0, self.freeYaw or (playerYaw and playerYaw.yaw) or 0, 0)
	self.ent:SetPos(self.standPos)
	self.ent:SetAngles(self.standAng)
end

function Session:_fbtLive()
	if self.forceFBT == false then return false end
	if self.forceFBT == true then return true end
	if g_VR.sixPoints then return true end
	local sid = LocalPlayer():SteamID()
	if g_VR.fbtActive and g_VR.fbtActive[sid] then return true end
	local tr = g_VR.tracking
	if not tr then return false end
	local w, lf, rf = tr.pose_waist, tr.pose_leftfoot, tr.pose_rightfoot
	return w and w.pos and lf and lf.pos and rf and rf.pos
end

function Session:_playerFrame()
	local hmd = g_VR.tracking and g_VR.tracking.hmd
	if not hmd or not hmd.pos then return end
	local yaw = hmd.ang and hmd.ang.yaw or 0
	local playerYaw = Angle(0, yaw, 0)
	local originZ = (g_VR.origin and g_VR.origin.z) or (hmd.pos.z - 66.8)
	local playerFeet = Vector(hmd.pos.x, hmd.pos.y, originZ)
	return hmd, playerFeet, playerYaw, yaw
end

function Session:_computeStand(hmd, playerFeet, playerYaw, yaw)
	local dist = self.distance or cv_distance:GetFloat()
	local mode = self.mode or "free"
	if mode == "mirror" then mode = "facing" end
	if mode == "free" then
		-- Placement owned by _updateFreeControls
		if self.freeInited and self.standPos and self.standAng then
			return self.standPos, self.standAng
		end
		local yawOff = cv_yaw:GetFloat()
		if yawOff ~= yawOff then yawOff = 180 end
		return playerFeet + playerYaw:Forward() * dist, Angle(0, yaw + yawOff, 0)
	end
	if mode == "world" then
		return playerFeet, Angle(0, yaw, 0)
	elseif mode == "clone" then
		return playerFeet + playerYaw:Forward() * dist, Angle(0, yaw, 0)
	end
	return playerFeet + playerYaw:Forward() * dist, Angle(0, yaw + 180, 0)
end

function Session:_isMirrorMode()
	return not self:_isClonePose()
end

function Session:_map(pos, ang, playerFeet, playerYaw)
	if self.mode == "world" then
		return pos, ang
	elseif self:_isClonePose() then
		return MapClone(pos, ang, playerFeet, playerYaw, self.standPos, self.standAng)
	end
	return MapMirrorWorld(pos, ang, playerFeet, playerYaw, self.standPos, self.standAng)
end

local function MatFrom(pos, ang)
	local m = Matrix()
	m:SetTranslation(pos)
	m:SetAngles(ang)
	return m
end

--- Resolve twin bone id for a player bone (L↔R swap in mirror mode).
-- Prefer cached mirrorBoneMap (same skeleton); fall back to name swap.
function Session:_twinBoneFor(playerBoneId, playerBoneName, fallbackId)
	if not self:_isMirrorMode() then
		return fallbackId
	end
	if self.mirrorBoneMap and playerBoneId ~= nil and self.mirrorBoneMap[playerBoneId] ~= nil then
		return self.mirrorBoneMap[playerBoneId]
	end
	if not playerBoneName or not IsValidBoneName(playerBoneName) then
		return fallbackId
	end
	local mirrorName = MirrorBoneName(playerBoneName)
	if mirrorName == playerBoneName then
		return fallbackId -- center bone (spine/head/pelvis)
	end
	local tid = self.ent:LookupBone(mirrorName)
	if tid and tid >= 0 then return tid end
	return fallbackId
end

--- Clamp child bone distance from parent in target map (stops stretch without re-IK).
local function ClampBoneDist(targets, parentId, childId, maxLen)
	if not parentId or not childId or not targets[parentId] or not targets[childId] then return end
	if maxLen < 1 then return end
	local pm = targets[parentId]
	local cm = targets[childId]
	local pp = pm:GetTranslation()
	local cp = cm:GetTranslation()
	local ca = cm:GetAngles()
	local d = cp - pp
	local len = d:Length()
	if len > maxLen * 1.15 and len > 0.01 then -- 15% slack before clamp
		targets[childId] = MatFrom(pp + d:GetNormalized() * maxLen, ca)
	end
end

--- READ-ONLY snapshot of the same frame the game already built this tick.
-- NEVER call VRUtilNetUpdateLocalPly here — that overwrites g_VR.net.lerpedFrame
-- mid-frame and makes real player hands feel "blocked" / desynced.
local function ReadLocalVRFrame()
	local ply = LocalPlayer()
	if not IsValid(ply) then return nil end
	local sid = ply:SteamID()
	local tab = g_VR.net and g_VR.net[sid]
	local src = tab and tab.lerpedFrame
	if src and (src.lefthandPos or src.righthandPos or src.hmdPos) then
		return vrmod.utils and vrmod.utils.CopyFrame and vrmod.utils.CopyFrame(src) or src
	end
	-- Ephemeral fallback from tracking (do not write into g_VR.net)
	local tr = g_VR.tracking
	if not tr or not tr.hmd or not tr.hmd.pos then return nil end
	local frame = {
		characterYaw = g_VR.characterYaw or (tr.hmd.ang and tr.hmd.ang.yaw) or 0,
		hmdPos = Vector(tr.hmd.pos.x, tr.hmd.pos.y, tr.hmd.pos.z),
		hmdAng = tr.hmd.ang and Angle(tr.hmd.ang.p, tr.hmd.ang.y, tr.hmd.ang.r) or Angle(),
	}
	if tr.pose_lefthand and tr.pose_lefthand.pos then
		local p, a = tr.pose_lefthand.pos, tr.pose_lefthand.ang or Angle()
		frame.lefthandPos = Vector(p.x, p.y, p.z)
		frame.lefthandAng = Angle(a.p, a.y, a.r)
	end
	if tr.pose_righthand and tr.pose_righthand.pos then
		local p, a = tr.pose_righthand.pos, tr.pose_righthand.ang or Angle()
		frame.righthandPos = Vector(p.x, p.y, p.z)
		frame.righthandAng = Angle(a.p, a.y, a.r)
	end
	if g_VR.input then
		local lf = g_VR.input.skeleton_lefthand and g_VR.input.skeleton_lefthand.fingerCurls
		local rf = g_VR.input.skeleton_righthand and g_VR.input.skeleton_righthand.fingerCurls
		for i = 1, 5 do
			frame["finger" .. i] = lf and lf[i] or 0
			frame["finger" .. (i + 5)] = rf and rf[i] or 0
		end
	end
	return frame
end

--- Full bone VMatrices from the working VR playermodel (after player IK).
-- { frame, characterYaw, feet, bones = { {name, mat}, ... } }
g_VR.avatarPoseSnap = g_VR.avatarPoseSnap or nil

--- Call from cl_character / VR draw AFTER player IK — NEVER invent pose here.
--- Once per stereoFrame only: re-publishing after the right eye (or mid-draw)
--- made FBT left-hand foregrip flicker between eyes on the avatar twin.
function vrmod.avatar.PublishPlayerPose(ply, frame)
	if not IsValid(ply) then return end
	local sf = (g_VR and g_VR.stereoFrame) or 0
	if g_VR.avatarPoseSnap and g_VR.avatarPoseSnap.stereoFrame == sf and sf > 0 then
		return
	end
	local n = ply:GetBoneCount() or 0
	if n < 4 then return end

	local yaw = (frame and frame.characterYaw) or g_VR.characterYaw or 0
	local ra = ply:GetRenderAngles()
	if ra and math.abs(math.AngleDifference(ra.yaw, yaw)) < 90 then
		yaw = ra.yaw
	end

	local originZ = (g_VR.origin and g_VR.origin.z) or ply:GetPos().z
	local fx, fy = ply:GetPos().x, ply:GetPos().y
	local pelvis = ply:LookupBone("ValveBiped.Bip01_Pelvis")
	if isnumber(pelvis) and pelvis >= 0 then
		local pm = ply:GetBoneMatrix(pelvis)
		if pm then
			local pp = pm:GetTranslation()
			fx, fy = pp.x, pp.y
		end
	end

	local bones = {}
	for i = 0, n - 1 do
		local name = ply:GetBoneName(i)
		if not name or name == "" or name == "__INVALIDBONE__" then continue end
		local m = ply:GetBoneMatrix(i)
		if not m then continue end
		-- Full matrix copy — NEVER decompose to Angle (that corkscrewed CLONE)
		bones[#bones + 1] = { name = name, mat = DupMat(m) }
	end
	if #bones < 4 then return end
	g_VR.avatarPoseSnap = {
		frame = FrameNumber(),
		stereoFrame = sf,
		characterYaw = yaw,
		feet = Vector(fx, fy, originZ),
		bones = bones,
	}
end

--- GOLD PATH: paste player post-IK matrices.
-- dYaw ≈ 0 → pure XY translate (fast).
-- dYaw ≠ 0 → rigid Z-yaw reparent (RotYaw basis + feet-frame pos). No Euler decomp.
function Session:_applyCloneFromSnap(playerFeet, playerYaw)
	if not IsValid(self.ent) then return false end
	local snap = g_VR.avatarPoseSnap
	if not snap or not snap.bones or #snap.bones < 4 then return false end
	if snap.frame and FrameNumber() - snap.frame > 8 then return false end

	local srcFeet = snap.feet or playerFeet or Vector()
	local srcYaw = Angle(0, snap.characterYaw or (playerYaw and playerYaw.yaw) or 0, 0)
	local dist = self.distance or cv_distance:GetFloat() or 40

	local standPos, standAng
	if self:_isFreeMode() and self.standPos then
		standPos = Vector(self.standPos.x, self.standPos.y, srcFeet.z)
		local fy = self.freeYaw
		if fy == nil and self.standAng then fy = self.standAng.yaw end
		if fy == nil then fy = srcYaw.yaw end
		standAng = Angle(0, fy, 0)
	else
		standPos = srcFeet + srcYaw:Forward() * dist
		standAng = Angle(0, srcYaw.yaw, 0)
	end
	self.standPos, self.standAng = standPos, standAng
	self.ent:SetPos(standPos)
	self.ent:SetAngles(standAng)

	-- Wipe manip every frame (no leftover hideHead spike)
	local nb = self.ent:GetBoneCount() or 0
	for i = 0, nb - 1 do
		self.ent:ManipulateBoneScale(i, VEC_ONE)
		self.ent:ManipulateBonePosition(i, VEC_ZERO)
		self.ent:ManipulateBoneAngles(i, Angle(0, 0, 0))
	end
	self.hideHead = false
	self.hideHands = false

	local dYaw = math.AngleDifference(standAng.yaw, srcYaw.yaw)
	local needRotate = math.abs(dYaw) > 0.25
	local off = Vector(standPos.x - srcFeet.x, standPos.y - srcFeet.y, 0)

	local targets = {}
	local copied = 0
	for _, b in ipairs(snap.bones) do
		if not b.name or not b.mat then continue end
		local tid = self.ent:LookupBone(b.name)
		if not tid or tid < 0 then continue end
		local m
		if needRotate then
			m = ReparentMat(b.mat, srcFeet, srcYaw, standPos, standAng)
		else
			m = TranslateMat(b.mat, off)
		end
		if not m then continue end
		targets[tid] = m
		copied = copied + 1
	end
	if copied < 4 then return false end
	self.targets = targets
	self._targetsFrame = FrameNumber()
	self.lastFrame = nil
	self.ik = nil
	return true
end

function Session:_applyFromNetFrame(playerFeet, playerYaw)
	return self:_applyCloneFromSnap(playerFeet, playerYaw)
end

function Session:_applyIKnetClone(playerFeet, playerYaw)
	return self:_applyCloneFromSnap(playerFeet, playerYaw)
end

--- Stamp targets onto twin skeleton (call EVERY stereo eye before DrawModel).
function Session:_applyTargets()
	if not IsValid(self.ent) or not self.targets or not next(self.targets) then return false end
	local e = self.ent
	e:InvalidateBoneCache()
	e:SetupBones()
	-- Direct SetBoneMatrix (don't rely only on BuildBonePositions — stereo-safe)
	local ids = {}
	for boneId in pairs(self.targets) do ids[#ids + 1] = boneId end
	table.sort(ids)
	for _, boneId in ipairs(ids) do
		local mat = self.targets[boneId]
		if boneId and mat then
			e:SetBoneMatrix(boneId, mat)
		end
	end
	return true
end

function Session:_drawModel()
	if not IsValid(self.ent) then return end
	self:_applyTargets()
	self.ent:DrawModel()
end

function Session:_applyTracking()
	local hmd, playerFeet, playerYaw, yaw = self:_playerFrame()
	if not hmd then return end

	local cyaw = g_VR.characterYaw
	if isnumber(cyaw) then
		yaw = cyaw
		playerYaw = Angle(0, yaw, 0)
	end

	local snap = g_VR.avatarPoseSnap
	if snap and snap.feet and snap.frame and FrameNumber() - snap.frame <= 8 then
		playerFeet = Vector(snap.feet.x, snap.feet.y, snap.feet.z)
		if snap.characterYaw then
			yaw = snap.characterYaw
			playerYaw = Angle(0, yaw, 0)
		end
	else
		local originZ = (g_VR.origin and g_VR.origin.z) or playerFeet.z
		playerFeet = Vector(hmd.pos.x, hmd.pos.y, originZ)
	end

	if self:_isFreeMode() then
		self:_updateFreeControls(playerFeet, playerYaw)
	else
		g_VR.avatarSteerTwin = false
		self.standPos, self.standAng = self:_computeStand(hmd, playerFeet, playerYaw, yaw)
		self.ent:SetPos(self.standPos)
		self.ent:SetAngles(self.standAng or Angle(0, yaw, 0))
	end

	if self.idleOnly then
		self.targets = {}
		return
	end

	-- Snap filled by VRMod_PreStereo → ForceLocalIKAndPublish (once / frame).
	local ok = self:_applyCloneFromSnap(playerFeet, playerYaw)
	if not ok then
		self.targets = {}
	end
end

function Session:_drawTrackers()
	-- Trackers / bone orbs OFF by default — they looked like cursed yellow hands.
	if not self.showTrackers and not self.laserPickBones then return end
	if not g_VR.tracking then return end
	render.SetColorMaterial()
	if self.showTrackers then
		local tr = g_VR.tracking
		local function box(pose, col)
			if not pose or not pose.pos then return end
			render.DrawBox(pose.pos, pose.ang or Angle(), Vector(-2, -2, -2), Vector(2, 2, 2), col or color_white)
		end
		box(tr.pose_waist, Color(80, 200, 80))
		box(tr.pose_leftfoot, Color(80, 160, 255))
		box(tr.pose_rightfoot, Color(255, 160, 80))
	end
	if self.laserPickBones and self.hoverBonePos and g_VR.tracking.pose_righthand then
		local rh = g_VR.tracking.pose_righthand
		if rh and rh.pos then
			render.DrawLine(rh.pos, self.hoverBonePos, Color(255, 70, 100), true)
			render.DrawWireframeSphere(self.hoverBonePos, 2, 8, 8, Color(255, 70, 100), true)
		end
	end
end

function vrmod.avatar.Open(opts)
	opts = opts or {}
	local id = opts.id or "default"
	if sessions[id] then sessions[id]:Close() end

	local ply = LocalPlayer()
	if not IsValid(ply) or not g_VR or not g_VR.active then return nil end

	-- Always prefer LIVE player model on open (cv_model is only after Apply/save —
	-- otherwise twin "remembers" preview picks that were never saved).
	local live = ply.vrmod_pm or ply:GetModel() or ""
	local mdl = opts.model
	if not mdl or mdl == "" then
		mdl = live
	end
	if not mdl or mdl == "" then
		mdl = "models/player/kleiner.mdl"
	end
	util.PrecacheModel(mdl)

	local ent = ClientsideModel(mdl, RENDERGROUP_BOTH)
	if not IsValid(ent) then return nil end
	ent:SetNoDraw(true)
	ent:DrawShadow(true)
	ent:SetIK(false)
	-- Match live player looks (skin/bodygroups) for the opened model
	CopyLooks(ent, ply)
	ent:SetSkin(cv_skin:GetInt())
	ApplyBodygroups(ent, ParseBodygroups(cv_body:GetString()))
	local idle = ply:LookupSequence("idle_all_01")
	if idle < 0 then idle = ply:LookupSequence("idle_subtle") end
	ent:ResetSequence(idle >= 0 and idle or 0)
	ent:SetCycle(0)
	ent:SetPlaybackRate(0)
	ent:SetupBones()

	local follow = { hmd = true, hands = true, waist = false, feet = false }
	if opts.follow then
		follow.hmd = opts.follow.hmd ~= false
		follow.hands = opts.follow.hands ~= false
		follow.waist = opts.follow.waist and true or false
		follow.feet = opts.follow.feet and true or false
	end
	local idleOnly = opts.idleOnly and true or false
	if idleOnly then
		follow = { hmd = false, hands = false, waist = false, feet = false }
	end

	local mode0 = opts.mode or cv_mode:GetString() or "free"
	if mode0 == "mirror" then mode0 = "facing" end
	if mode0 == "" then mode0 = "free" end

	local s = setmetatable({
		id = id,
		active = true,
		ent = ent,
		model = mdl,
		mode = mode0,
		distance = opts.distance or cv_distance:GetFloat(),
		follow = follow,
		idleOnly = idleOnly,
		forceFBT = opts.forceFBT,
		pelvisOffset = opts.pelvisOffset or DEFAULT_PELVIS_OFFSET,
		shoulderWidth = opts.shoulderWidth or DEFAULT_SHOULDER_W,
		showTrackers = opts.showTrackers or false,
		showFBTTrackers = opts.showFBTTrackers ~= false,
		showHandTrackers = opts.showHandTrackers or false,
		hideHead = opts.hideHead ~= nil and opts.hideHead or cv_hide_head:GetBool(),
		hideHands = opts.hideHands ~= nil and opts.hideHands or cv_hide_hands:GetBool(),
		customHidden = ParseHiddenBones(cv_hidden_bones:GetString()),
		laserPickBones = opts.laserPickBones == true, -- off by default (yellow orbs = bone pick)
		hoverBoneId = nil,
		hoverBoneName = nil,
		hoverBonePos = nil,
		menuUid = opts.menuUid,
		menuAnchor = opts.menuAnchor,
		onClose = opts.onClose,
		hideLocalPlayer = opts.hideLocalPlayer or false,
		hookId = "vrmod_avatar_" .. id,
		thinkId = "vrmod_avatar_think_" .. id,
		standPos = Vector(),
		standAng = Angle(),
		bones = {},
		mirrorBoneMap = {},
		targets = {},
		headDampen = true, -- soft neck clamp only (not UI)
		headMaxLen = 14,
		mirrorLR = (mode0 == "facing"),
		freeInited = false,
		freeYaw = nil,
		freeAimDir = nil,
		upperArmLen = 12,
		forearmLen = 12,
		upperLegLen = 16,
		lowerLegLen = 16,
	}, Session)

	s:_cacheBones()
	s:_measureArms()
	local charik0 = vrmod.charik or vrmod.frameik
	s.ik = charik0 and charik0.Init(ent, {
		noStretch = true,
		headDampen = s.headDampen ~= false,
		headMaxPitch = s.headMaxPitch or 55,
	}) or nil
	s:_applyHideBones()
	sessions[id] = s

	-- Prefer self.targets (clone full-skeleton snap, or charik arm targets)
	s.boneCb = ent:AddCallback("BuildBonePositions", function(e, _num)
		if not s.active then return end
		if not s.targets or not next(s.targets) then return end
		-- Paste only — never charik.ApplyHead (spike head) on twin
		local ids = {}
		for boneId in pairs(s.targets) do ids[#ids + 1] = boneId end
		table.sort(ids)
		for _, boneId in ipairs(ids) do
			local mat = s.targets[boneId]
			if boneId and mat and e:GetBoneMatrix(boneId) then
				e:SetBoneMatrix(boneId, mat)
			end
		end
	end)

	-- Hot-reload helper for vision loop
	concommand.Add("vrmod_twin_restart", function()
		if vrmod.avatar and vrmod.avatar.Close then
			vrmod.avatar.Close("avatar")
		end
		timer.Simple(0.05, function()
			if vrmod.avatar and vrmod.avatar.OpenHeightCal then
				vrmod.avatar.OpenHeightCal("avatar_menu")
			end
		end)
	end)

	if s.hideLocalPlayer then
		ply.RenderOverride = function() end
	end

	hook.Add("Think", s.thinkId, function()
		if not s.active then return end
		if s.laserPickBones then
			s:UpdateLaserHover()
		end
	end)

	-- Pose once per stereo frame (shared by both eyes)
	hook.Add("VRMod_PreStereo", s.thinkId .. "_pose", function()
		if not s.active then return end
		pcall(function() s:_applyTracking() end)
	end)

	-- Draw path: stamp immutable targets + DrawModel (no solve)
	hook.Add("PostDrawTranslucentRenderables", s.hookId, function(depth, sky)
		if depth or sky or not s.active or not IsValid(s.ent) then return end
		if not g_VR.active or not g_VR.tracking then return end
		if not g_VR.stereoEye then return end
		if not s.targets or not next(s.targets) then return end
		pcall(function() s:_drawModel() end)
		pcall(function() s:_drawTrackers() end)
		if s.onDraw then pcall(s.onDraw, s) end
	end, -10)

	return s
end

function vrmod.avatar.Close(id)
	if sessions[id] then sessions[id]:Close() end
end

function vrmod.avatar.CloseAll()
	for id in pairs(sessions) do
		vrmod.avatar.Close(id)
	end
end

function vrmod.avatar.Get(id)
	return sessions[id]
end

function vrmod.avatar.IsOpen(id)
	local s = sessions[id]
	return s and s:IsValid()
end

function vrmod.avatar.ListPlayerModels()
	local list = {}
	if player_manager and player_manager.AllValidModels then
		for name, path in pairs(player_manager.AllValidModels()) do
			list[#list + 1] = { name = name, path = path }
		end
		table.sort(list, function(a, b) return a.name < b.name end)
	end
	if #list == 0 then
		list = {
			{ name = "kleiner", path = "models/player/kleiner.mdl" },
			{ name = "gman", path = "models/player/gman_high.mdl" },
			{ name = "alyx", path = "models/player/alyx.mdl" },
			{ name = "barney", path = "models/player/barney.mdl" },
			{ name = "eli", path = "models/player/eli.mdl" },
			{ name = "monk", path = "models/player/monk.mdl" },
			{ name = "odessa", path = "models/player/odessa.mdl" },
			{ name = "breen", path = "models/player/breen.mdl" },
		}
	end
	return list
end

--- Cube Avatar twin: tracking-matched customization preview.
-- Always opens on the LIVE player model (not last preview selection).
function vrmod.avatar.OpenHeightCal(menuUid)
	local fbt = g_VR and (g_VR.sixPoints or false)
	local mode = cv_mode:GetString()
	if mode == "mirror" then mode = "facing" end
	if mode == "" or (mode ~= "free" and mode ~= "clone" and mode ~= "facing" and mode ~= "world") then
		mode = "free"
	end

	local ply = LocalPlayer()
	local liveMdl = IsValid(ply) and (ply.vrmod_pm or ply:GetModel()) or nil

	return vrmod.avatar.Open({
		id = "avatar",
		mode = mode,
		model = liveMdl, -- force current player model (ignore unsaved cv_model preview)
		distance = cv_distance:GetFloat(),
		idleOnly = false,
		forceFBT = nil,
		follow = {
			hmd = true,
			hands = true,
			waist = fbt,
			feet = fbt,
		},
		showFBTTrackers = true,
		hideHead = false,
		hideHands = false,
		laserPickBones = false,
		pelvisOffset = DEFAULT_PELVIS_OFFSET,
		shoulderWidth = DEFAULT_SHOULDER_W,
		menuUid = menuUid or "avatar_menu",
		menuAnchor = nil,
	})
end


-- Alias for old callers
vrmod.avatar.OpenAvatar = vrmod.avatar.OpenHeightCal

function vrmod.avatar.OpenFBTCal()
	return vrmod.avatar.Open({
		id = "fbt_cal",
		mode = "world",
		distance = 0,
		idleOnly = false,
		forceFBT = true,
		follow = { hmd = true, hands = true, waist = true, feet = true },
		showTrackers = true,
		showFBTTrackers = true,
		showHandTrackers = false,
		hideLocalPlayer = true,
	})
end

hook.Add("VRMod_Exit", "vrmod_avatar_editor_cleanup", function(ply)
	if ply == LocalPlayer() then
		vrmod.avatar.CloseAll()
	end
end)
