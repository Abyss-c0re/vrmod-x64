-- =============================================================================
-- vrmod.avatar — unified 3D avatar editor utility
-- Shared by height calibration and FBT tracking (same PM, same bone vocabulary).
-- Modes:
--   "mirror" — stand in front of player, face them, L/R flipped (height twin)
--   "clone"  — stand offset with same facing (third-person twin)
--   "world"  — body at feet under HMD, same yaw as player (FBT T-pose cal)
-- Follow flags map g_VR.tracking → ValveBiped bones (HMD/hands/waist/feet).
-- =============================================================================
if SERVER then return end

vrmod = vrmod or {}
vrmod.avatar = vrmod.avatar or {}

local BONES = {
	head = "ValveBiped.Bip01_Head1",
	pelvis = "ValveBiped.Bip01_Pelvis",
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

local sessions = {} -- id → session

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

local function MapMirror(worldPos, worldAng, playerFeet, playerYaw, avatarFeet, avatarYaw)
	local relPos, relAng = WorldToLocal(worldPos, worldAng, playerFeet, playerYaw)
	relPos.y = -relPos.y
	relAng.y = -relAng.y
	relAng.r = -relAng.r
	return LocalToWorld(relPos, relAng, avatarFeet, avatarYaw)
end

local function MapClone(worldPos, worldAng, playerFeet, playerYaw, avatarFeet, avatarYaw)
	local relPos, relAng = WorldToLocal(worldPos, worldAng, playerFeet, playerYaw)
	return LocalToWorld(relPos, relAng, avatarFeet, avatarYaw)
end

local function AimLimb(ent, upperId, foreId, handPos)
	if not handPos then return end
	for _, boneId in ipairs({ upperId, foreId }) do
		if boneId then
			local m = ent:GetBoneMatrix(boneId)
			if m then
				local o = m:GetTranslation()
				local dir = handPos - o
				if dir:LengthSqr() > 1 then
					local ang = dir:GetNormalized():Angle()
					ang:RotateAroundAxis(ang:Right(), 90)
					SetBoneWorld(ent, boneId, o, ang)
				end
			end
		end
	end
end

local function AimLeg(ent, thighId, calfId, footPos)
	AimLimb(ent, thighId, calfId, footPos)
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
	end
end

function Session:_cacheBones()
	local e = self.ent
	self.bones = {}
	for k, name in pairs(BONES) do
		self.bones[k] = Lookup(e, name)
	end
end

function Session:_playerFrame()
	local hmd = g_VR.tracking and g_VR.tracking.hmd
	if not hmd then return end
	local yaw = hmd.ang.yaw
	local playerYaw = Angle(0, yaw, 0)
	local playerFeet = Vector(hmd.pos.x, hmd.pos.y, g_VR.origin and g_VR.origin.z or hmd.pos.z - 66.8)
	return hmd, playerFeet, playerYaw, yaw
end

function Session:_computeStand(hmd, playerFeet, playerYaw, yaw)
	local dist = self.distance or 48
	local mode = self.mode or "mirror"
	if mode == "world" then
		-- FBT-style: avatar under player, same facing as HMD
		return playerFeet, Angle(0, yaw, 0)
	elseif mode == "clone" then
		return playerFeet + playerYaw:Forward() * dist, Angle(0, yaw, 0)
	else -- mirror
		return playerFeet + playerYaw:Forward() * dist, Angle(0, yaw + 180, 0)
	end
end

function Session:_map(worldPos, worldAng, playerFeet, playerYaw)
	if self.mode == "mirror" then
		return MapMirror(worldPos, worldAng, playerFeet, playerYaw, self.standPos, self.standAng)
	end
	return MapClone(worldPos, worldAng, playerFeet, playerYaw, self.standPos, self.standAng)
end

function Session:_applyTracking()
	local hmd, playerFeet, playerYaw, yaw = self:_playerFrame()
	if not hmd then return end
	local follow = self.follow
	local tr = g_VR.tracking
	local b = self.bones

	self.standPos, self.standAng = self:_computeStand(hmd, playerFeet, playerYaw, yaw)
	self.ent:SetPos(self.standPos)
	self.standAng = self.standAng or Angle()
	self.ent:SetAngles(self.standAng)
	-- Keep idle sequence alive (height twin = human-looking PM, not bone soup)
	if self.ent.FrameAdvance then
		self.ent:FrameAdvance(FrameTime())
	end
	self.ent:InvalidateBoneCache()
	self.ent:SetupBones()

	-- Idle-only (height cal default): no SetBoneWorld — world matrix hacks
	-- stretch head/arms off the neck (giraffe / cursed twin).
	local anyBone = follow.hmd or follow.hands or follow.waist or follow.feet
	if not anyBone then
		if self.menuAnchor and g_VR.menus and g_VR.menus[self.menuUid] then
			local mp, ma = self.menuAnchor(self.standPos, self.standAng, self)
			if mp then g_VR.menus[self.menuUid].pos = mp end
			if ma then g_VR.menus[self.menuUid].ang = ma end
		end
		return
	end

	local map = function(pos, ang)
		if self.mode == "world" then
			return pos, ang
		end
		return self:_map(pos, ang, playerFeet, playerYaw)
	end

	-- Safe mode: only FBT world mode may write full bone chains.
	-- Partial head/hand world overrides without a full IK solve = cursed mesh.
	if self.mode ~= "world" or self.safeBoneDrive then
		-- Optional: soft head look (angles only) — never teleport head bone in world space
		if follow.hmd and b.head and self.ent.ManipulateBoneAngles then
			local targetYaw = math.NormalizeAngle((hmd.ang and hmd.ang.yaw or yaw) - yaw)
			local pitch = math.Clamp(hmd.ang and hmd.ang.pitch or 0, -35, 35)
			self.ent:ManipulateBoneAngles(b.head, Angle(0, math.Clamp(targetYaw * 0.35, -40, 40), math.Clamp(-pitch * 0.25, -20, 20)))
		end
		if self.menuAnchor and g_VR.menus and g_VR.menus[self.menuUid] then
			local mp, ma = self.menuAnchor(self.standPos, self.standAng, self)
			if mp then g_VR.menus[self.menuUid].pos = mp end
			if ma then g_VR.menus[self.menuUid].ang = ma end
		end
		return
	end

	-- World / FBT advanced: full bone drive (only when explicitly requested)
	if follow.hmd and b.head then
		local hp, ha = map(hmd.pos + hmd.ang:Forward() * -2, hmd.ang)
		SetBoneWorld(self.ent, b.head, hp, ha)
	end

	local left = tr.pose_lefthand
	local right = tr.pose_righthand
	if follow.hands then
		if left and left.pos and b.lHand then
			local p, a = map(left.pos, left.ang or Angle())
			SetBoneWorld(self.ent, b.lHand, p, a)
			AimLimb(self.ent, b.lUpper, b.lFore, p)
		end
		if right and right.pos and b.rHand then
			local p, a = map(right.pos, right.ang or Angle())
			SetBoneWorld(self.ent, b.rHand, p, a)
			AimLimb(self.ent, b.rUpper, b.rFore, p)
		end
	end

	local waist = tr.pose_waist
	if follow.waist and waist and waist.pos and b.pelvis then
		local p, a = map(waist.pos, waist.ang or Angle())
		SetBoneWorld(self.ent, b.pelvis, p, a)
	end

	local lfoot = tr.pose_leftfoot
	local rfoot = tr.pose_rightfoot
	if follow.feet then
		if lfoot and lfoot.pos and b.lFoot then
			local p, a = map(lfoot.pos, lfoot.ang or Angle())
			SetBoneWorld(self.ent, b.lFoot, p, a)
			AimLeg(self.ent, b.lThigh, b.lCalf, p)
		end
		if rfoot and rfoot.pos and b.rFoot then
			local p, a = map(rfoot.pos, rfoot.ang or Angle())
			SetBoneWorld(self.ent, b.rFoot, p, a)
			AimLeg(self.ent, b.rThigh, b.rCalf, p)
		end
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

--- Open an avatar editor session.
-- @param opts table
--   id (string, required), mode ("mirror"|"clone"|"world"), distance (number),
--   follow { hmd, hands, waist, feet }, showTrackers, showHandTrackers,
--   menuUid, menuAnchor(standPos, standAng, session), onClose, hideLocalPlayer
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
	-- World/FBT cal: idle body, trackers only (bone measure against T-pose)
	if opts.idleOnly then
		follow = { hmd = false, hands = false, waist = false, feet = false }
	end

	local s = setmetatable({
		id = id,
		active = true,
		ent = ent,
		mode = opts.mode or "mirror",
		distance = opts.distance or 48,
		follow = follow,
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
	}, Session)

	s:_cacheBones()
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

--- Height-cal preset: idle PM twin (looks human). No bone-world stretch.
function vrmod.avatar.OpenHeightCal(menuUid)
	return vrmod.avatar.Open({
		id = "height",
		mode = "mirror",
		distance = 48,
		idleOnly = true, -- critical: SetBoneWorld head = giraffe
		follow = { hmd = false, hands = false, waist = false, feet = false },
		menuUid = menuUid or "heightmenu",
		menuAnchor = function(standPos, standAng)
			return standPos + Vector(0, 0, 52) + standAng:Right() * -18,
				Angle(0, standAng.y + 90, 90)
		end,
	})
end

--- FBT calibration preset: world-aligned idle PM + tracker boxes (same concept as height avatar)
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
