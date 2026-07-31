-- =============================================================================
-- vrmod.avatar — Cube player customization twin
--
-- Cube law: the VR playermodel is already correct (cl_character / FBT).
-- Twin does NOT re-solve arm IK. Every frame:
--   snapshot LocalPlayer bone matrices (working VR body)
--   → MapMirror / MapClone into twin stand space
--   → L↔R bone name remap (facing) so limbs never stretch same-ID
--   → BuildBonePositions SetBoneMatrix only
--
-- Fallback: charik.TransformFrame + Update only if player skeleton unavailable.
-- Never VRUtilNetUpdateLocalPly from the twin.
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
-- facing = stand in front facing you (true mirror: sagittal flip + L↔R bone remap)
-- clone  = stand in front same yaw as player (no L/R flip — over-shoulder debug)
local cv_mode = CreateClientConVar("vrmod_avatar_mode", "facing", true, FCVAR_ARCHIVE)
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

-- Clone: same laterality (your right → twin's right in twin space)
local function MapClone(worldPos, worldAng, playerFeet, playerYaw, avatarFeet, avatarYaw)
	local relPos, relAng = WorldToLocal(worldPos, worldAng or Angle(), playerFeet, playerYaw)
	return LocalToWorld(relPos, relAng, avatarFeet, avatarYaw)
end

-- Reconstruct Angle from orthonormal right-handed basis (forward, up)
local function AngleFromBasis(forward, up)
	forward = forward:GetNormalized()
	-- Orthonormalize up against forward
	local right = forward:Cross(up)
	if right:LengthSqr() < 1e-6 then
		right = forward:Cross(Vector(0, 0, 1))
		if right:LengthSqr() < 1e-6 then right = forward:Cross(Vector(0, 1, 0)) end
	end
	right:Normalize()
	up = right:Cross(forward)
	up:Normalize()
	-- Source Angle from forward, then roll so local Up matches
	local ang = forward:Angle()
	local curUp = ang:Up()
	local curRight = ang:Right()
	local roll = math.deg(math.atan2(curRight:Dot(up), curUp:Dot(up)))
	ang.r = roll
	return ang
end

--- Swap ValveBiped (and common) left/right bone names.
-- A real mirror needs BOTH spatial reflection AND writing the mirrored matrix
-- onto the opposite limb bone — same-ID flip stretches R arm mesh to the left.
local function MirrorBoneName(name)
	if not name or name == "" then return name end
	if string.find(name, "_L_", 1, true) then
		return (string.gsub(name, "_L_", "_R_", 1))
	end
	if string.find(name, "_R_", 1, true) then
		return (string.gsub(name, "_R_", "_L_", 1))
	end
	-- rarer conventions
	if string.find(name, "Left", 1, true) then
		return (string.gsub(name, "Left", "Right", 1))
	end
	if string.find(name, "Right", 1, true) then
		return (string.gsub(name, "Right", "Left", 1))
	end
	return name
end

--- True mirror: left-right reflection in the player's sagittal plane, then into twin space.
-- WorldToLocal with playerYaw: X=Right, Y=Forward, Z=Up.
-- Flip X on position; reflect bone basis across YZ.
-- AngleFromBasis rebuilds a right-handed frame (Householder det=-1 is corrected via f×u).
-- Caller MUST also remap L↔R bone targets via MirrorBoneName (see _copyFromLocalPlayer).
local function MapMirror(worldPos, worldAng, playerFeet, playerYaw, avatarFeet, avatarYaw)
	local relPos, relAng = WorldToLocal(worldPos, worldAng or Angle(), playerFeet, playerYaw)

	-- Position: your right (+X) becomes left (−X) in player frame
	relPos.x = -relPos.x

	-- Orientation: reflect Forward/Up across the sagittal plane (YZ)
	local f = relAng:Forward()
	local u = relAng:Up()
	f = Vector(-f.x, f.y, f.z)
	u = Vector(-u.x, u.y, u.z)
	local nang = AngleFromBasis(f, u)

	return LocalToWorld(relPos, nang, avatarFeet, avatarYaw)
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

function Session:SetModel(path)
	if not self:IsValid() or not path or path == "" then return false end
	util.PrecacheModel(path)
	self.ent:SetModel(path)
	self.model = path
	cv_model:SetString(path)
	-- keep twin bodygroups/skin from convars (don't CopyLooks — that reverts to live PM)
	self.ent:SetSkin(cv_skin:GetInt())
	ApplyBodygroups(self.ent, ParseBodygroups(cv_body:GetString()))
	self.ent:SetupBones()
	self:_cacheBones()
	self:_measureArms()
	local charik = vrmod.charik or vrmod.frameik
	self.ik = charik and charik.Init(self.ent, {
		noStretch = true,
		headDampen = self.headDampen ~= false,
		headMaxPitch = self.headMaxPitch or 55,
	}) or nil
	self:_applyHideBones()
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

--- Persist twin customization onto the REAL player (convars + sandbox PM cmds)
function Session:ApplyToPlayer()
	if not self:IsValid() then return false, "no twin" end
	local ply = LocalPlayer()
	if not IsValid(ply) then return false, "no player" end

	local path = self.ent:GetModel()
	local skin = self.ent:GetSkin() or 0
	cv_model:SetString(path or "")
	cv_skin:SetInt(skin)
	cv_body:SetString(EncodeBodygroups(self.ent))
	ply.vrmod_pm = path

	local name = self:ModelName()
	if name then
		RunConsoleCommand("cl_playermodel", name)
	end
	RunConsoleCommand("cl_playerskin", tostring(skin))

	-- GMod bodygroup string: space-separated values per group index
	local parts = {}
	for i = 0, (self.ent:GetNumBodyGroups() or 1) - 1 do
		parts[#parts + 1] = tostring(self.ent:GetBodygroup(i) or 0)
	end
	if #parts > 0 then
		RunConsoleCommand("cl_playerbodygroups", table.concat(parts, " "))
	end

	-- Immediate client model (some gamemodes honor this)
	pcall(function()
		if path and path ~= "" then ply:SetModel(path) end
		ply:SetSkin(skin)
		for i = 0, (self.ent:GetNumBodyGroups() or 1) - 1 do
			ply:SetBodygroup(i, self.ent:GetBodygroup(i) or 0)
		end
	end)

	-- Keep custom hidden bones archived (already in cv_hidden_bones)
	cv_hidden_bones:SetString(EncodeHiddenBones(self.customHidden))

	if vrmod.logger then
		vrmod.logger.Info("[Avatar] saved PM=%s skin=%d body=%s hidden=%s",
			tostring(name or path), skin, cv_body:GetString(), cv_hidden_bones:GetString())
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

	-- Reset all bone scales first (custom hide may have changed many)
	local n = e:GetBoneCount() or 0
	for i = 0, n - 1 do
		e:ManipulateBoneScale(i, VEC_ONE)
	end

	if self.hideHead then scaleBone(b.head, VEC_TINY) end
	if self.hideHands then
		scaleBone(b.lHand, VEC_TINY)
		scaleBone(b.rHand, VEC_TINY)
		scaleBone(b.lFore, VEC_TINY)
		scaleBone(b.rFore, VEC_TINY)
	end

	-- Custom laser-picked bones (by name, re-lookup after model change)
	self.customHidden = self.customHidden or {}
	for name in pairs(self.customHidden) do
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
	-- accept legacy "mirror" as "facing"
	if mode == "mirror" then mode = "facing" end
	if mode ~= "facing" and mode ~= "clone" and mode ~= "world" then return end
	self.mode = mode
	self.idleOnly = false
	-- clear any leftover algocube policy flags that hijack pose
	self.algoDigit = nil
	self.algoPolicy = nil
	self.forceFBT = nil
	if mode == "clone" or mode == "world" then
		self.mirrorLR = false
	else
		self.mirrorLR = true
	end
	cv_mode:SetString(mode == "world" and "facing" or mode)
end

function Session:SetDistance(d)
	self.distance = math.Clamp(tonumber(d) or 40, 20, 80)
	cv_distance:SetFloat(self.distance)
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
	local mode = self.mode or "facing"
	if mode == "mirror" then mode = "facing" end
	if mode == "world" then
		return playerFeet, Angle(0, yaw, 0)
	elseif mode == "clone" then
		-- same facing as player (looks over twin's shoulder from behind-ish)
		return playerFeet + playerYaw:Forward() * dist, Angle(0, yaw, 0)
	end
	-- facing: twin in front looking at you (true mirror + L↔R remap)
	return playerFeet + playerYaw:Forward() * dist, Angle(0, yaw + 180, 0)
end

function Session:_isMirrorMode()
	local mode = self.mode or "facing"
	-- facing (and legacy "mirror") = real mirror; clone/world = no L/R flip
	return mode ~= "clone" and mode ~= "world"
end

function Session:_map(pos, ang, playerFeet, playerYaw)
	if self.mode == "world" then
		return pos, ang
	elseif self.mode == "clone" then
		-- Same laterality (debug / over-shoulder view)
		return MapClone(pos, ang, playerFeet, playerYaw, self.standPos, self.standAng)
	end
	-- facing / mirror: sagittal flip; L↔R bone IDs remapped in _copyFromLocalPlayer
	return MapMirror(pos, ang, playerFeet, playerYaw, self.standPos, self.standAng)
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

--- Mirror the *already-solved* VR playermodel — do NOT re-run arm IK.
-- The real player bones are the SoT (cl_character / FBT). We only:
--   1) snapshot world bone matrices from LocalPlayer
--   2) MapMirror / MapClone into twin stand space
--   3) L↔R bone name remap in facing mode (never same-ID flip → stretch)
-- That preserves limb lengths exactly — no rubber-band ProcessArm reach.
function Session:_mirrorWorkingPlayer(playerFeet, playerYaw)
	local ply = LocalPlayer()
	if not IsValid(ply) or not IsValid(self.ent) then return false end
	if not g_VR or not g_VR.active then return false end

	local headId = ply:LookupBone("ValveBiped.Bip01_Head1")
	-- Stereo path hides local head (scale 0 + nudge). Unhide for one snapshot so
	-- the twin gets a real head, then restore.
	local hideHead = false
	if isnumber(headId) and headId >= 0 then
		local ep = EyePos()
		hideHead = g_VR.eyePosLeft and g_VR.eyePosRight
			and (ep == g_VR.eyePosLeft or ep == g_VR.eyePosRight)
			and ply:GetViewEntity() == ply
		ply:ManipulateBoneScale(headId, Vector(1, 1, 1))
		ply:ManipulateBonePosition(headId, Vector(0, 0, 0))
	end

	-- Force a clean posed skeleton (player IK already ran in PrePlayerDraw this frame)
	ply:InvalidateBoneCache()
	ply:SetupBones()

	local mirror = self:_isMirrorMode()
	local standPos = self.standPos
	local standAng = self.standAng or playerYaw
	local targets = {}
	local n = ply:GetBoneCount() or 0
	local copied = 0

	for i = 0, n - 1 do
		local name = ply:GetBoneName(i)
		if not name or name == "" or name == "__INVALIDBONE__" then continue end
		local m = ply:GetBoneMatrix(i)
		if not m then continue end

		local pos = m:GetTranslation()
		local ang = m:GetAngles()
		local npos, nang
		if self.mode == "world" then
			npos, nang = pos, ang
		elseif mirror then
			npos, nang = MapMirror(pos, ang, playerFeet, playerYaw, standPos, standAng)
		else
			npos, nang = MapClone(pos, ang, playerFeet, playerYaw, standPos, standAng)
		end

		local twinName = mirror and MirrorBoneName(name) or name
		local tid = self.ent:LookupBone(twinName)
		if not tid or tid < 0 then
			-- same-name fallback (center bones / missing pair)
			tid = self.ent:LookupBone(name)
		end
		if not tid or tid < 0 then continue end

		-- World matrix only — never copy scale (would stretch mesh)
		local mat = Matrix()
		mat:Identity()
		mat:SetTranslation(npos)
		mat:SetAngles(nang)
		targets[tid] = mat
		copied = copied + 1
	end

	-- Restore local head hide for stereo comfort
	if hideHead and isnumber(headId) and headId >= 0 then
		ply:ManipulateBoneScale(headId, Vector(0.001, 0.001, 0.001))
		ply:ManipulateBonePosition(headId, Vector(0, 20, 0))
	end

	if copied < 4 then return false end
	self.targets = targets
	return true
end

--- Fallback only if player skeleton unavailable (no character system yet).
function Session:_applyFromNetFrame(playerFeet, playerYaw)
	local charik = vrmod.charik or vrmod.frameik
	if not charik then return false end
	if not self.ik then
		local ok, ik = pcall(charik.Init, self.ent, {
			noStretch = true,
			headDampen = self.headDampen ~= false,
			headMaxPitch = self.headMaxPitch or 55,
		})
		self.ik = ok and ik or nil
	end
	if not self.ik then return false end

	local src = ReadLocalVRFrame()
	if not src or (not src.lefthandPos and not src.righthandPos) then
		return false
	end

	local mode = self.mode or "facing"
	if mode == "mirror" then mode = "facing" end

	local okT, twinFrame = pcall(
		charik.TransformFrame,
		src, mode, playerFeet, playerYaw, self.standPos, self.standAng or playerYaw
	)
	if not okT or not twinFrame then return false end

	self.ent:SetPos(self.standPos)
	self.ent:SetAngles(self.standAng or Angle(0, twinFrame.characterYaw or 0, 0))
	self.ent:InvalidateBoneCache()
	self.ent:SetupBones()

	self.ik.noStretch = true
	self.ik.headDampen = true
	self.ik.headMaxPitch = self.headMaxPitch or 45

	local eyeH = 66.8
	if vrmod.GetConvars then
		local _, cv = vrmod.GetConvars()
		if cv and cv.characterEyeHeight then eyeH = cv.characterEyeHeight end
	end

	local okA = pcall(charik.Update, self.ent, self.ik, twinFrame, {
		baseZ = self.standPos.z,
		eyeHeight = eyeH,
		applyManip = true,
	})
	if not okA then return false end
	self.targets = self.ik.targets or {}
	return next(self.targets) ~= nil
end

function Session:_applyTracking()
	local hmd, playerFeet, playerYaw, yaw = self:_playerFrame()
	if not hmd then return end

	-- Same body yaw as real VR character (net / character system)
	local cyaw = g_VR.characterYaw
	if isnumber(cyaw) then
		yaw = cyaw
		playerYaw = Angle(0, yaw, 0)
	end
	local originZ = (g_VR.origin and g_VR.origin.z) or playerFeet.z
	-- Feet under character, not HMD pitch-wobble
	local frame = ReadLocalVRFrame()
	if frame and frame.hmdPos then
		playerFeet = Vector(frame.hmdPos.x, frame.hmdPos.y, originZ)
	else
		playerFeet = Vector(hmd.pos.x, hmd.pos.y, originZ)
	end

	self.standPos, self.standAng = self:_computeStand(hmd, playerFeet, playerYaw, yaw)

	self.ent:SetPos(self.standPos)
	self.ent:SetAngles(self.standAng or Angle(0, yaw, 0))

	if self.idleOnly then
		self.targets = {}
		return
	end

	-- Primary: mirror the working VR playermodel bones (no re-IK stretch)
	local ok = false
	local okP, res = pcall(function()
		return self:_mirrorWorkingPlayer(playerFeet, playerYaw)
	end)
	ok = okP and res
	-- Fallback: frame → charik only if player skeleton not ready
	if not ok then
		ok = self:_applyFromNetFrame(playerFeet, playerYaw)
	end
	if not ok then
		self.targets = {}
	end
end

function Session:_drawTrackers()
	if not g_VR.tracking then return end
	local fbt = self:_fbtLive()
	render.SetColorMaterial()
	local function box(pose, col)
		if not pose or not pose.pos then return end
		render.DrawBox(pose.pos, pose.ang or Angle(), Vector(-2, -2, -2), Vector(2, 2, 2), col or color_white)
	end
	if self.showTrackers or (fbt and self.showFBTTrackers) then
		local tr = g_VR.tracking
		box(tr.pose_waist, Color(80, 200, 80))
		box(tr.pose_leftfoot, Color(80, 160, 255))
		box(tr.pose_rightfoot, Color(255, 160, 80))
		if self.showHandTrackers then
			box(tr.pose_lefthand, Color(200, 200, 255))
			box(tr.pose_righthand, Color(255, 200, 200))
		end
	end

	-- Laser bone pick: small markers + highlight hover
	if self.laserPickBones then
		self.ent:SetupBones()
		local n = self.ent:GetBoneCount() or 0
		for i = 0, n - 1 do
			local m = self.ent:GetBoneMatrix(i)
			if not m then continue end
			local p = m:GetTranslation()
			local hidden = self:IsBoneCustomHidden(i)
			local hover = (self.hoverBoneId == i)
			local col = hover and Color(255, 70, 100, 255)
				or (hidden and Color(80, 80, 90, 120) or Color(255, 200, 80, 180))
			local s = hover and 2.2 or (hidden and 0.8 or 1.2)
			render.DrawWireframeSphere(p, s, 6, 6, col, true)
		end
		-- Beam to hover
		if self.hoverBonePos and g_VR.tracking.pose_righthand then
			local rh = g_VR.tracking.pose_righthand
			if rh.pos then
				render.DrawLine(rh.pos, self.hoverBonePos, Color(255, 70, 100), true)
			end
		end
	end
end

function vrmod.avatar.Open(opts)
	opts = opts or {}
	local id = opts.id or "default"
	if sessions[id] then sessions[id]:Close() end

	local ply = LocalPlayer()
	if not IsValid(ply) or not g_VR or not g_VR.active then return nil end

	local mdl = opts.model or cv_model:GetString()
	if mdl == "" then mdl = ply.vrmod_pm or ply:GetModel() end
	if not mdl or mdl == "" then mdl = "models/player/kleiner.mdl" end
	util.PrecacheModel(mdl)

	local ent = ClientsideModel(mdl, RENDERGROUP_BOTH)
	if not IsValid(ent) then return nil end
	ent:SetNoDraw(true)
	ent:DrawShadow(true)
	ent:SetIK(false)
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

	local mode0 = opts.mode or cv_mode:GetString() or "facing"
	if mode0 == "mirror" then mode0 = "facing" end

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
		laserPickBones = opts.laserPickBones ~= false, -- default on for Avatar menu
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
		mirrorLR = (mode0 ~= "clone" and mode0 ~= "world"),
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

	-- Apply twin targets only (mirrored player matrices or fallback IK)
	s.boneCb = ent:AddCallback("BuildBonePositions", function(e, _num)
		if not s.active or not s.targets then return end
		for boneId, mat in pairs(s.targets) do
			if boneId and mat and e:GetBoneMatrix(boneId) then
				e:SetBoneMatrix(boneId, mat)
			end
		end
	end)

	if s.hideLocalPlayer then
		ply.RenderOverride = function() end
	end

	hook.Add("Think", s.thinkId, function()
		if not s.active then return end
		s:_applyHideBones()
		if s.laserPickBones then
			s:UpdateLaserHover()
		end
	end)

	hook.Add("PostDrawTranslucentRenderables", s.hookId, function(depth, sky)
		if depth or sky or not s.active or not IsValid(s.ent) then return end
		if not g_VR.active or not g_VR.tracking then return end
		-- Prefer stereo eyes; still draw once for desktop/debug if no eye match
		local ep = EyePos()
		local stereo = (g_VR.eyePosLeft and ep == g_VR.eyePosLeft)
			or (g_VR.eyePosRight and ep == g_VR.eyePosRight)
		if not stereo and g_VR.eyePosLeft and g_VR.eyePosRight then
			return
		end

		-- Never let IK errors kill the twin draw
		pcall(function() s:_applyTracking() end)
		pcall(function()
			s.ent:SetupBones() -- BuildBonePositions → targets
			s:_applyHideBones()
		end)
		s.ent:DrawModel()
		pcall(function() s:_drawTrackers() end)
		if s.onDraw then pcall(s.onDraw, s) end
	end)

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
-- Clean open only — no algocube/daemon policy injection, no prophecy UI.
function vrmod.avatar.OpenHeightCal(menuUid)
	local fbt = g_VR and (g_VR.sixPoints or false)
	local mode = cv_mode:GetString()
	if mode == "mirror" or mode == "" then mode = "facing" end
	if mode ~= "clone" and mode ~= "facing" and mode ~= "world" then
		mode = "facing"
	end

	return vrmod.avatar.Open({
		id = "avatar",
		mode = mode,
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
		hideHead = cv_hide_head:GetBool(),
		hideHands = false, -- never open with hands scaled away
		laserPickBones = true,
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
