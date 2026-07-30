-- =============================================================================
-- vrmod.avatar — unified 3D avatar editor utility
-- Modes: mirror | clone | world
--
-- Body drive (copy player) uses Pescorr's VR Ragdoll Puppeteer algorithm:
--   https://steamcommunity.com/sharedfiles/filedetails/?id=3695733221
--   pelvis-from-HMD, spine lerp, 2-bone arm IK, full chain SetBoneMatrix
--   (not raw head-only SetBoneWorld — that stretches the mesh).
-- Credits: Pescorr · Catse — docs/CREDITS.md
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
	lClav = "ValveBiped.Bip01_L_Clavicle",
	rClav = "ValveBiped.Bip01_R_Clavicle",
	lFoot = "ValveBiped.Bip01_L_Foot",
	rFoot = "ValveBiped.Bip01_R_Foot",
	lThigh = "ValveBiped.Bip01_L_Thigh",
	rThigh = "ValveBiped.Bip01_R_Thigh",
	lCalf = "ValveBiped.Bip01_L_Calf",
	rCalf = "ValveBiped.Bip01_R_Calf",
}

local sessions = {}

-- Defaults from puppeteer convars
local DEFAULT_PELVIS_OFFSET = 30
local DEFAULT_SHOULDER_W = 8

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

local function SetBoneWorld(ent, bone, pos, ang)
	if not bone or not pos or not ang then return end
	local m = Matrix()
	m:SetTranslation(pos)
	m:SetAngles(ang)
	ent:SetBoneMatrix(bone, m)
end

--- Pescorr puppeteer: 2-bone IK elbow position
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
		if projHint:LengthSqr() < 0.001 then
			projHint = Vector(0, 1, 0)
		end
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
	if IsValid(self.ent) then self.ent:Remove() end
	self.ent = nil
	if self.hideLocalPlayer then
		local ply = LocalPlayer()
		if IsValid(ply) then ply.RenderOverride = nil end
	end
	sessions[self.id] = nil
	if self.onClose then pcall(self.onClose, self) end
end

function Session:RefreshModel()
	if not self:IsValid() then return end
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local want = ply.vrmod_pm or ply:GetModel()
	if want and want ~= "" and self.ent:GetModel() ~= want then
		self.ent:SetModel(want)
		CopyLooks(self.ent, ply)
		self.ent:SetupBones()
		self:_cacheBones()
		self:_measureArms()
	end
end

function Session:_cacheBones()
	local e = self.ent
	self.bones = {}
	for k, name in pairs(BONES) do
		self.bones[k] = Lookup(e, name)
	end
	-- Prefer Spine2 / Spine4 for chest
	self.bones.chest = self.bones.spine2 or self.bones.spine4 or self.bones.spine1 or self.bones.spine
end

--- Measure arm/leg chain lengths from bind pose (puppeteer CreatePuppet pattern)
function Session:_measureArms()
	local e = self.ent
	local b = self.bones
	self.upperArmLen = 12
	self.forearmLen = 12
	self.upperLegLen = 16
	self.lowerLegLen = 16
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

--- FBT live when waist + both feet exist on tracking (or g_VR.sixPoints / fbtActive)
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
	local dist = self.distance or 52
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

--- Puppeteer body solve in player world space, then map into avatar space
function Session:_applyPuppeteerCopy(hmd, playerFeet, playerYaw)
	local tr = g_VR.tracking
	local left = tr.pose_lefthand
	local right = tr.pose_righthand
	if not left or not left.pos or not right or not right.pos then return end

	-- Clone positions so L/R identity glue never feeds both targets
	local hmdPos = Vector(hmd.pos.x, hmd.pos.y, hmd.pos.z)
	local hmdAng = Angle(hmd.ang.p, hmd.ang.y, hmd.ang.r)
	local lhPos = Vector(left.pos.x, left.pos.y, left.pos.z)
	local lhAng = left.ang and Angle(left.ang.p, left.ang.y, left.ang.r) or Angle()
	local rhPos = Vector(right.pos.x, right.pos.y, right.pos.z)
	local rhAng = right.ang and Angle(right.ang.p, right.ang.y, right.ang.r) or Angle()

	local pelvisOff = self.pelvisOffset or DEFAULT_PELVIS_OFFSET
	local shoulderW = self.shoulderWidth or DEFAULT_SHOULDER_W
	local upperLen = self.upperArmLen or 12
	local foreLen = self.forearmLen or 12

	-- === Player-space body (Pescorr puppeteer) ===
	local headPos = hmdPos
	local headAng = Angle(hmdAng.p - 90, hmdAng.y, hmdAng.r + 90)
	local pelvisPos = hmdPos - Vector(0, 0, pelvisOff)
	local pelvisAng = Angle(0, hmdAng.y, 0)
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

	-- Mirror: swap visual L/R so twin faces you correctly
	local mirror = (self.mode == "mirror")
	local b = self.bones
	local ent = self.ent

	local function drive(boneId, pos, ang)
		if boneId then SetBoneWorld(ent, boneId, pos, ang) end
	end

	-- Core body
	local pPelvis, aPelvis = map(pelvisPos, pelvisAng)
	local pSpine, aSpine = map(spinePos, spineAng)
	local pHead, aHead = map(headPos, headAng)
	drive(b.pelvis, pPelvis, aPelvis)
	if b.chest then drive(b.chest, pSpine, aSpine) end
	if b.spine and b.spine ~= b.chest then drive(b.spine, pSpine, aSpine) end
	if self.follow.hmd then
		drive(b.head, pHead, aHead)
	end

	if not self.follow.hands then return end

	-- Arms: in mirror mode player-left drives avatar-right bones
	local function driveArm(shPos, elPos, handPos, handAng, upperId, foreId, handId, flipHand)
		local pS, _ = map(shPos, Angle())
		local pE, _ = map(elPos, Angle())
		local pH, aH = map(handPos, handAng)
		if flipHand then aH = aH + Angle(0, 0, 180) end
		drive(upperId, pS, AngleBetween(pS, pE))
		drive(foreId, pE, AngleBetween(pE, pH))
		drive(handId, pH, aH)
	end

	if mirror then
		-- Visual: avatar's right = player's left (mirrored)
		driveArm(shoulderL, elbowL, lhPos, lhAng, b.rUpper, b.rFore, b.rHand, true)
		driveArm(shoulderR, elbowR, rhPos, rhAng, b.lUpper, b.lFore, b.lHand, false)
	else
		driveArm(shoulderL, elbowL, lhPos, lhAng, b.lUpper, b.lFore, b.lHand, false)
		driveArm(shoulderR, elbowR, rhPos, rhAng, b.rUpper, b.rFore, b.rHand, true)
	end
end

function Session:_applyTracking()
	local hmd, playerFeet, playerYaw, yaw = self:_playerFrame()
	if not hmd then return end

	self.standPos, self.standAng = self:_computeStand(hmd, playerFeet, playerYaw, yaw)
	self.ent:SetPos(self.standPos)
	self.ent:SetAngles(self.standAng or Angle())
	self.ent:InvalidateBoneCache()
	self.ent:SetupBones()

	local follow = self.follow
	local anyDrive = follow.hmd or follow.hands or follow.waist or follow.feet

	if anyDrive and not self.idleOnly then
		-- Full puppeteer-style copy (head + arms + torso)
		self:_applyPuppeteerCopy(hmd, playerFeet, playerYaw)
	end

	if self.menuAnchor and g_VR.menus and g_VR.menus[self.menuUid] then
		local mp, ma = self.menuAnchor(self.standPos, self.standAng, self)
		if mp then g_VR.menus[self.menuUid].pos = mp end
		if ma then g_VR.menus[self.menuUid].ang = ma end
	end
end

function Session:_drawTrackers()
	if not self.showTrackers or not g_VR.tracking then return end
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
	if not IsValid(ply) then return nil end
	if not g_VR or not g_VR.active then return nil end

	local mdl = ply.vrmod_pm or ply:GetModel()
	if not mdl or mdl == "" then mdl = "models/player/kleiner.mdl" end

	local ent = ClientsideModel(mdl, RENDERGROUP_BOTH)
	if not IsValid(ent) then return nil end
	ent:SetNoDraw(true)
	ent:DrawShadow(true)
	ent:SetIK(false)
	CopyLooks(ent, ply)
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
		mode = opts.mode or "mirror",
		distance = opts.distance or 52,
		follow = follow,
		idleOnly = idleOnly,
		pelvisOffset = opts.pelvisOffset or DEFAULT_PELVIS_OFFSET,
		shoulderWidth = opts.shoulderWidth or DEFAULT_SHOULDER_W,
		showTrackers = opts.showTrackers or false,
		showHandTrackers = opts.showHandTrackers or false,
		menuUid = opts.menuUid,
		menuAnchor = opts.menuAnchor,
		onClose = opts.onClose,
		hideLocalPlayer = opts.hideLocalPlayer or false,
		hookId = "vrmod_avatar_" .. id,
		thinkId = "vrmod_avatar_think_" .. id,
		standPos = Vector(),
		standAng = Angle(),
		bones = {},
		upperArmLen = 12,
		forearmLen = 12,
	}, Session)

	s:_cacheBones()
	s:_measureArms()
	sessions[id] = s

	if s.hideLocalPlayer then
		ply.RenderOverride = function() end
	end

	hook.Add("Think", s.thinkId, function()
		if not s.active then return end
		s:RefreshModel()
	end)

	hook.Add("PostDrawTranslucentRenderables", s.hookId, function(depth, sky)
		if depth or sky or not s.active or not IsValid(s.ent) then return end
		if not g_VR.active or not g_VR.tracking then return end
		if EyePos() ~= g_VR.eyePosLeft and EyePos() ~= g_VR.eyePosRight then return end

		s:_applyTracking()
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

--- Height-cal: mirror twin that COPIES player via puppeteer 2-bone IK
function vrmod.avatar.OpenHeightCal(menuUid)
	return vrmod.avatar.Open({
		id = "height",
		mode = "mirror",
		distance = 52,
		idleOnly = false,
		follow = { hmd = true, hands = true, waist = false, feet = false },
		pelvisOffset = 30,
		shoulderWidth = 8,
		menuUid = menuUid or "heightmenu",
		menuAnchor = function(standPos, standAng)
			-- Large panel to the twin's left, chest height
			return standPos + Vector(0, 0, 48) + standAng:Right() * -28,
				Angle(0, standAng.y + 90, 90)
		end,
	})
end

function vrmod.avatar.OpenFBTCal()
	return vrmod.avatar.Open({
		id = "fbt_cal",
		mode = "world",
		distance = 0,
		idleOnly = true,
		showTrackers = true,
		showHandTrackers = false,
		hideLocalPlayer = true,
	})
end

hook.Add("VRMod_Exit", "vrmod_avatar_editor_cleanup", function(ply)
	if ply == LocalPlayer() then
		vrmod.avatar.CloseAll()
	end
end)
