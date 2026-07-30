-- =============================================================================
-- vrmod.avatar — Cube player customization twin
-- Drives a ClientsideModel from g_VR.tracking (Pescorr 2-bone IK lineage).
-- Customization: model, skin, bodygroups, hide head/hands.
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

-- Persist customization
local cv_model = CreateClientConVar("vrmod_avatar_model", "", true, FCVAR_ARCHIVE)
local cv_skin = CreateClientConVar("vrmod_avatar_skin", "0", true, FCVAR_ARCHIVE)
local cv_body = CreateClientConVar("vrmod_avatar_bodygroups", "", true, FCVAR_ARCHIVE)
local cv_hide_head = CreateClientConVar("vrmod_avatar_hide_head", "0", true, FCVAR_ARCHIVE)
local cv_hide_hands = CreateClientConVar("vrmod_avatar_hide_hands", "0", true, FCVAR_ARCHIVE)
local cv_distance = CreateClientConVar("vrmod_avatar_distance", "40", true, FCVAR_ARCHIVE)
local cv_mode = CreateClientConVar("vrmod_avatar_mode", "mirror", true, FCVAR_ARCHIVE) -- mirror|clone

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

local function MapMirror(worldPos, worldAng, playerFeet, playerYaw, avatarFeet, avatarYaw)
	local relPos, relAng = WorldToLocal(worldPos, worldAng or Angle(), playerFeet, playerYaw)
	relPos.y = -relPos.y
	relAng.y = -relAng.y
	relAng.r = -relAng.r
	return LocalToWorld(relPos, relAng, avatarFeet, avatarYaw)
end

local function MapClone(worldPos, worldAng, playerFeet, playerYaw, avatarFeet, avatarYaw)
	local relPos, relAng = WorldToLocal(worldPos, worldAng or Angle(), playerFeet, playerYaw)
	return LocalToWorld(relPos, relAng, avatarFeet, avatarYaw)
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
	local ply = LocalPlayer()
	if IsValid(ply) then
		ply.vrmod_pm = path
		CopyLooks(self.ent, ply)
	end
	-- re-apply stored bodygroups/skin after model change
	self.ent:SetSkin(cv_skin:GetInt())
	ApplyBodygroups(self.ent, ParseBodygroups(cv_body:GetString()))
	self.ent:SetupBones()
	self:_cacheBones()
	self:_measureArms()
	self:_applyHideBones()
	return true
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
	scaleBone(b.head, self.hideHead and VEC_TINY or VEC_ONE)
	if self.hideHands then
		scaleBone(b.lHand, VEC_TINY)
		scaleBone(b.rHand, VEC_TINY)
		scaleBone(b.lFore, VEC_TINY)
		scaleBone(b.rFore, VEC_TINY)
	else
		scaleBone(b.lHand, VEC_ONE)
		scaleBone(b.rHand, VEC_ONE)
		scaleBone(b.lFore, VEC_ONE)
		scaleBone(b.rFore, VEC_ONE)
	end
end

function Session:SetMode(mode)
	if mode ~= "mirror" and mode ~= "clone" then return end
	self.mode = mode
	cv_mode:SetString(mode)
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
	local mode = self.mode or "mirror"
	if mode == "world" then
		return playerFeet, Angle(0, yaw, 0)
	elseif mode == "clone" then
		return playerFeet + playerYaw:Forward() * dist, Angle(0, yaw, 0)
	end
	return playerFeet + playerYaw:Forward() * dist, Angle(0, yaw + 180, 0)
end

function Session:_map(pos, ang, playerFeet, playerYaw)
	if self.mode == "world" then
		return pos, ang
	elseif self.mode == "mirror" then
		return MapMirror(pos, ang, playerFeet, playerYaw, self.standPos, self.standAng)
	end
	return MapClone(pos, ang, playerFeet, playerYaw, self.standPos, self.standAng)
end

local function MatFrom(pos, ang)
	local m = Matrix()
	m:SetTranslation(pos)
	m:SetAngles(ang)
	return m
end

--- Build target matrices from g_VR.tracking (Pescorr algorithm, correct Valve head angles)
function Session:_solveTracking(hmd, playerFeet, playerYaw)
	local tr = g_VR.tracking
	local left, right = tr.pose_lefthand, tr.pose_righthand
	if not left or not left.pos or not right or not right.pos then return end

	local hmdPos = Vector(hmd.pos)
	local hmdAng = Angle(hmd.ang.p, hmd.ang.y, hmd.ang.r)
	local lhPos = Vector(left.pos)
	local lhAng = left.ang and Angle(left.ang.p, left.ang.y, left.ang.r) or Angle()
	local rhPos = Vector(right.pos)
	local rhAng = right.ang and Angle(right.ang.p, right.ang.y, right.ang.r) or Angle()

	local pelvisOff = self.pelvisOffset or DEFAULT_PELVIS_OFFSET
	local shoulderW = self.shoulderWidth or DEFAULT_SHOULDER_W
	local upperLen = self.upperArmLen or 12
	local foreLen = self.forearmLen or 12
	local upperLeg = self.upperLegLen or 16
	local lowerLeg = self.lowerLegLen or 16
	local fbt = self:_fbtLive()
	local follow = self.follow

	-- Pescorr: ValveBiped head orientation from HMD
	local headPos = hmdPos
	local headAng = Angle(hmdAng.p - 90, hmdAng.y, hmdAng.r + 90)

	local pelvisPos = hmdPos - Vector(0, 0, pelvisOff)
	local pelvisAng = Angle(0, hmdAng.y, 0)
	local waist = tr.pose_waist
	if fbt and follow.waist ~= false and waist and waist.pos then
		pelvisPos = Vector(waist.pos)
		pelvisAng = Angle(0, (waist.ang and waist.ang.y) or hmdAng.y, 0)
	end

	local spinePos = LerpVector(0.4, pelvisPos, headPos)
	local spineAng = Angle(hmdAng.p * 0.3, hmdAng.y, 0)
	local spineRight = spineAng:Right()
	local shoulderL = spinePos - spineRight * shoulderW
	local shoulderR = spinePos + spineRight * shoulderW
	local bodyFwd = spineAng:Forward()
	local hintBack = (-bodyFwd + Vector(0, 0, -0.3)):GetNormalized()
	local elbowL = SolveTwoBoneIK(shoulderL, lhPos, upperLen, foreLen, hintBack)
	local elbowR = SolveTwoBoneIK(shoulderR, rhPos, upperLen, foreLen, hintBack)

	local map = function(p, a)
		return self:_map(p, a, playerFeet, playerYaw)
	end
	local mirror = (self.mode == "mirror")
	local b = self.bones
	local targets = {}

	local function set(id, pos, ang)
		if id then targets[id] = MatFrom(pos, ang) end
	end

	local pPelvis, aPelvis = map(pelvisPos, pelvisAng)
	local pSpine, aSpine = map(spinePos, spineAng)
	local pHead, aHead = map(headPos, headAng)
	if follow.hmd ~= false then
		set(b.pelvis, pPelvis, aPelvis)
		if b.chest then set(b.chest, pSpine, aSpine) end
		if b.spine and b.spine ~= b.chest then set(b.spine, pSpine, aSpine) end
		set(b.head, pHead, aHead)
	end

	if follow.hands ~= false then
		local function arm(sh, el, handP, handA, uId, fId, hId, flip)
			local pS = map(sh, Angle())
			local pE = map(el, Angle())
			local pH, aH = map(handP, handA)
			if flip then aH = aH + Angle(0, 0, 180) end
			set(uId, pS, AngleBetween(pS, pE))
			set(fId, pE, AngleBetween(pE, pH))
			set(hId, pH, aH)
		end
		if mirror then
			-- visual swap so mirror reads as your reflection
			arm(shoulderL, elbowL, lhPos, lhAng, b.rUpper, b.rFore, b.rHand, true)
			arm(shoulderR, elbowR, rhPos, rhAng, b.lUpper, b.lFore, b.lHand, false)
		else
			arm(shoulderL, elbowL, lhPos, lhAng, b.lUpper, b.lFore, b.lHand, false)
			arm(shoulderR, elbowR, rhPos, rhAng, b.rUpper, b.rFore, b.rHand, true)
		end
	end

	if fbt and follow.feet ~= false then
		local lfoot, rfoot = tr.pose_leftfoot, tr.pose_rightfoot
		if lfoot and lfoot.pos and rfoot and rfoot.pos then
			local lfPos, rfPos = Vector(lfoot.pos), Vector(rfoot.pos)
			local lfAng = lfoot.ang and Angle(lfoot.ang.p, lfoot.ang.y, lfoot.ang.r) or Angle()
			local rfAng = rfoot.ang and Angle(rfoot.ang.p, rfoot.ang.y, rfoot.ang.r) or Angle()
			local hipRight = pelvisAng:Right()
			local kneeHint = -pelvisAng:Forward()
			local hipL = pelvisPos - hipRight * shoulderW - Vector(0, 0, 2)
			local hipR = pelvisPos + hipRight * shoulderW - Vector(0, 0, 2)
			local kneeL = SolveTwoBoneIK(hipL, lfPos, upperLeg, lowerLeg, kneeHint)
			local kneeR = SolveTwoBoneIK(hipR, rfPos, upperLeg, lowerLeg, kneeHint)
			local function leg(hip, knee, foot, footAng, tId, cId, fId)
				local pH = map(hip, Angle())
				local pK = map(knee, Angle())
				local pF, aF = map(foot, footAng)
				set(tId, pH, AngleBetween(pH, pK))
				set(cId, pK, AngleBetween(pK, pF))
				set(fId, pF, aF)
			end
			if mirror then
				leg(hipL, kneeL, lfPos, lfAng, b.rThigh, b.rCalf, b.rFoot)
				leg(hipR, kneeR, rfPos, rfAng, b.lThigh, b.lCalf, b.lFoot)
			else
				leg(hipL, kneeL, lfPos, lfAng, b.lThigh, b.lCalf, b.lFoot)
				leg(hipR, kneeR, rfPos, rfAng, b.rThigh, b.rCalf, b.rFoot)
			end
		end
	end

	self.targets = targets
end

function Session:_applyTracking()
	local hmd, playerFeet, playerYaw, yaw = self:_playerFrame()
	if not hmd then return end

	local fbt = self:_fbtLive()
	if fbt and not self.idleOnly then
		self.follow.waist = true
		self.follow.feet = true
		self.showTrackers = self.showTrackers or self.showFBTTrackers
	end

	self.standPos, self.standAng = self:_computeStand(hmd, playerFeet, playerYaw, yaw)
	self.ent:SetPos(self.standPos)
	self.ent:SetAngles(self.standAng or Angle(0, yaw, 0))
	self.ent:InvalidateBoneCache()
	self.ent:SetupBones()

	if not self.idleOnly then
		local follow = self.follow
		if follow.hmd or follow.hands or follow.waist or follow.feet then
			self:_solveTracking(hmd, playerFeet, playerYaw)
		end
	end
end

function Session:_drawTrackers()
	if not g_VR.tracking then return end
	local fbt = self:_fbtLive()
	if not self.showTrackers and not (fbt and self.showFBTTrackers) then return end
	render.SetColorMaterial()
	local function box(pose, col)
		if not pose or not pose.pos then return end
		render.DrawBox(pose.pos, pose.ang or Angle(), Vector(-2, -2, -2), Vector(2, 2, 2), col or color_white)
	end
	local tr = g_VR.tracking
	box(tr.pose_waist, Color(80, 200, 80))
	box(tr.pose_leftfoot, Color(80, 160, 255))
	box(tr.pose_rightfoot, Color(255, 160, 80))
	if self.showHandTrackers then
		box(tr.pose_lefthand, Color(200, 200, 255))
		box(tr.pose_righthand, Color(255, 200, 200))
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

	local s = setmetatable({
		id = id,
		active = true,
		ent = ent,
		model = mdl,
		mode = opts.mode or cv_mode:GetString() or "mirror",
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
		menuUid = opts.menuUid,
		menuAnchor = opts.menuAnchor,
		onClose = opts.onClose,
		hideLocalPlayer = opts.hideLocalPlayer or false,
		hookId = "vrmod_avatar_" .. id,
		thinkId = "vrmod_avatar_think_" .. id,
		standPos = Vector(),
		standAng = Angle(),
		bones = {},
		targets = {},
		upperArmLen = 12,
		forearmLen = 12,
		upperLegLen = 16,
		lowerLegLen = 16,
	}, Session)

	s:_cacheBones()
	s:_measureArms()
	s:_applyHideBones()
	sessions[id] = s

	-- Apply solved matrices in BuildBonePositions (stable vs free SetBoneMatrix thrash)
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
		-- keep hide scales sticky
		s:_applyHideBones()
	end)

	hook.Add("PostDrawTranslucentRenderables", s.hookId, function(depth, sky)
		if depth or sky or not s.active or not IsValid(s.ent) then return end
		if not g_VR.active or not g_VR.tracking then return end
		if EyePos() ~= g_VR.eyePosLeft and EyePos() ~= g_VR.eyePosRight then return end

		s:_applyTracking()
		s.ent:SetupBones() -- triggers BuildBonePositions → apply targets
		s.ent:DrawModel()
		s:_drawTrackers()
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

--- Cube Avatar twin: tracking-matched customization preview
function vrmod.avatar.OpenHeightCal(menuUid)
	local fbt = g_VR and (g_VR.sixPoints or false)
	return vrmod.avatar.Open({
		id = "avatar",
		mode = cv_mode:GetString() == "clone" and "clone" or "mirror",
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
