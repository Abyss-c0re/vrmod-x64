-- =============================================================================
-- vrmod.frameik — Same character arm IK as cl_character, driven by a net frame.
--
-- Input:  VR frame (hmd/hands/fingers/characterYaw) from buildClientFrame / lerpedFrame
-- Output: bone world matrices for BuildBonePositions
--
-- Twin path: CopyFrame → TransformFrame (clone / mirror rotate) → Apply
-- Do NOT reinvent arm math. ProcessArm matches cl_character UpdateIK.
-- =============================================================================
if SERVER then return end

vrmod = vrmod or {}
vrmod.frameik = vrmod.frameik or {}
local F = vrmod.frameik

local ZERO_VEC = Vector()
local ZERO_ANG = Angle()
local RIGHT_HAND_OFFSET = Angle(0, 0, 180)
local POS_THRESHOLD = 0.01
local ANGLE_THRESHOLD = 0.01

local BONE_NAMES = {
	b_leftClavicle = "ValveBiped.Bip01_L_Clavicle",
	b_leftUpperarm = "ValveBiped.Bip01_L_UpperArm",
	b_leftForearm = "ValveBiped.Bip01_L_Forearm",
	b_leftHand = "ValveBiped.Bip01_L_Hand",
	b_leftWrist = "ValveBiped.Bip01_L_Wrist",
	b_leftUlna = "ValveBiped.Bip01_L_Ulna",
	b_rightClavicle = "ValveBiped.Bip01_R_Clavicle",
	b_rightUpperarm = "ValveBiped.Bip01_R_UpperArm",
	b_rightForearm = "ValveBiped.Bip01_R_Forearm",
	b_rightHand = "ValveBiped.Bip01_R_Hand",
	b_rightWrist = "ValveBiped.Bip01_R_Wrist",
	b_rightUlna = "ValveBiped.Bip01_R_Ulna",
	b_head = "ValveBiped.Bip01_Head1",
	b_spine = "ValveBiped.Bip01_Spine",
}

local FINGER_TMP = { "0", "01", "02", "1", "11", "12", "2", "21", "22", "3", "31", "32", "4", "41", "42" }

local function RecursiveBoneTable(ent, parentbone, infotab, ordertab, notfirst)
	if not parentbone or parentbone < 0 then return end
	local bones = notfirst and ent:GetChildBones(parentbone) or { parentbone }
	for _, v in pairs(bones) do
		local n = ent:GetBoneName(v)
		local boneparent = ent:GetBoneParent(v)
		local parentmat = ent:GetBoneMatrix(boneparent)
		local childmat = ent:GetBoneMatrix(v)
		if parentmat and childmat then
			local parentpos, parentang = parentmat:GetTranslation(), parentmat:GetAngles()
			local childpos, childang = childmat:GetTranslation(), childmat:GetAngles()
			local relpos, relang = WorldToLocal(childpos, childang, parentpos, parentang)
			infotab[v] = {
				name = n,
				pos = Vector(0, 0, 0),
				ang = Angle(0, 0, 0),
				parent = boneparent,
				relativePos = relpos,
				relativeAng = relang,
				offsetAng = Angle(0, 0, 0),
				targetMatrix = Matrix(),
				overrideAng = nil,
			}
			ordertab[#ordertab + 1] = v
		end
	end
	for _, v in pairs(bones) do
		RecursiveBoneTable(ent, v, infotab, ordertab, true)
	end
end

--- Build IK state for a model (ClientsideModel or player). Call once after model set.
function F.Init(ent)
	if not IsValid(ent) then return nil end
	ent:SetupBones()
	local state = {
		boneinfo = {},
		boneorder = {},
		bones = { fingers = {} },
		clavicleLen = 8,
		upperArmLen = 12,
		lowerArmLen = 12,
		L_ClaviclePos = Vector(),
		R_ClaviclePos = Vector(),
		L_armStretchScale = 1,
		R_armStretchScale = 1,
		targets = {},
	}

	local lClav = ent:LookupBone("ValveBiped.Bip01_L_Clavicle")
	local rClav = ent:LookupBone("ValveBiped.Bip01_R_Clavicle")
	if lClav and lClav >= 0 then RecursiveBoneTable(ent, lClav, state.boneinfo, state.boneorder) end
	if rClav and rClav >= 0 then RecursiveBoneTable(ent, rClav, state.boneinfo, state.boneorder) end

	for k, name in pairs(BONE_NAMES) do
		local id = ent:LookupBone(name)
		state.bones[k] = (id and id >= 0) and id or -1
	end

	for i = 1, 15 do
		state.bones.fingers[i] = ent:LookupBone("ValveBiped.Bip01_L_Finger" .. FINGER_TMP[i]) or -1
		state.bones.fingers[i + 15] = ent:LookupBone("ValveBiped.Bip01_R_Finger" .. FINGER_TMP[i]) or -1
	end

	local b = state.bones
	if b.b_leftClavicle >= 0 and b.b_leftUpperarm >= 0 then
		local a, c = ent:GetBonePosition(b.b_leftClavicle), ent:GetBonePosition(b.b_leftUpperarm)
		if a and c then state.clavicleLen = math.max(2, a:Distance(c)) end
	end
	if b.b_leftUpperarm >= 0 and b.b_leftForearm >= 0 and b.b_leftHand >= 0 then
		local u, f, h = ent:GetBonePosition(b.b_leftUpperarm), ent:GetBonePosition(b.b_leftForearm), ent:GetBonePosition(b.b_leftHand)
		if u and f then state.upperArmLen = math.max(4, u:Distance(f)) end
		if f and h then state.lowerArmLen = math.max(4, f:Distance(h)) end
	end

	return state
end

--- Reconstruct Angle from reflected basis (mirror orientation).
local function AngleFromBasis(forward, up)
	forward = forward:GetNormalized()
	local right = forward:Cross(up)
	if right:LengthSqr() < 1e-6 then
		right = forward:Cross(Vector(0, 0, 1))
		if right:LengthSqr() < 1e-6 then right = forward:Cross(Vector(0, 1, 0)) end
	end
	right:Normalize()
	up = right:Cross(forward)
	up:Normalize()
	local ang = forward:Angle()
	local roll = math.deg(math.atan2(ang:Right():Dot(up), ang:Up():Dot(up)))
	ang.r = roll
	return ang
end

local function MapPose(worldPos, worldAng, srcFeet, srcYaw, dstFeet, dstYaw, mirror)
	local relPos, relAng = WorldToLocal(worldPos, worldAng or Angle(), srcFeet, srcYaw)
	if mirror then
		relPos.x = -relPos.x
		local f = relAng:Forward()
		local u = relAng:Up()
		f = Vector(-f.x, f.y, f.z)
		u = Vector(-u.x, u.y, u.z)
		relAng = AngleFromBasis(f, u)
	end
	return LocalToWorld(relPos, relAng, dstFeet, dstYaw)
end

--- Rotate / mirror a net frame into twin space. Same fields as buildClientFrame.
-- mode: "facing" = true mirror (flip + swap L/R), "clone"/"world" = rigid copy
function F.TransformFrame(src, mode, srcFeet, srcYaw, dstFeet, dstYaw)
	if not src then return nil end
	local mirror = (mode ~= "clone" and mode ~= "world")
	local out = {
		characterYaw = (dstYaw and dstYaw.yaw) or (src.characterYaw or 0),
	}
	for i = 1, 10 do
		out["finger" .. i] = src["finger" .. i] or 0
	end

	local parts = { "hmd", "lefthand", "righthand", "waist", "leftfoot", "rightfoot" }
	local mapped = {}
	for _, part in ipairs(parts) do
		local pos, ang = src[part .. "Pos"], src[part .. "Ang"]
		if pos and ang then
			local np, na = MapPose(pos, ang, srcFeet, srcYaw, dstFeet, dstYaw, mirror)
			mapped[part] = { pos = np, ang = na }
		end
	end

	if mirror then
		-- Laterality: after sagittal flip, anatomical L/R swap for IK limbs
		if mapped.righthand then
			out.lefthandPos, out.lefthandAng = mapped.righthand.pos, mapped.righthand.ang
		end
		if mapped.lefthand then
			out.righthandPos, out.righthandAng = mapped.lefthand.pos, mapped.lefthand.ang
		end
		if mapped.rightfoot then
			out.leftfootPos, out.leftfootAng = mapped.rightfoot.pos, mapped.rightfoot.ang
		end
		if mapped.leftfoot then
			out.rightfootPos, out.rightfootAng = mapped.leftfoot.pos, mapped.leftfoot.ang
		end
		if mapped.hmd then
			out.hmdPos, out.hmdAng = mapped.hmd.pos, mapped.hmd.ang
		end
		if mapped.waist then
			out.waistPos, out.waistAng = mapped.waist.pos, mapped.waist.ang
		end
		for i = 1, 5 do
			out["finger" .. i] = src["finger" .. (i + 5)] or 0
			out["finger" .. (i + 5)] = src["finger" .. i] or 0
		end
	else
		for _, part in ipairs(parts) do
			if mapped[part] then
				out[part .. "Pos"] = mapped[part].pos
				out[part .. "Ang"] = mapped[part].ang
			end
		end
	end

	return out
end

--- Run character ProcessArm IK on frame → fill state.targets { [boneId] = Matrix }
function F.Apply(ent, state, frame)
	if not IsValid(ent) or not state or not frame then return false end
	if not frame.lefthandPos and not frame.righthandPos then return false end

	local bones = state.bones
	local boneinfo = state.boneinfo
	local plyAng = Angle(0, frame.characterYaw or 0, 0)
	local convars = vrmod.GetConvars and select(2, vrmod.GetConvars()) or {}

	local function ProcessArm(side)
		local isLeft = side == "left"
		local prefix = isLeft and "L_" or "R_"
		local targetPos = isLeft and frame.lefthandPos or frame.righthandPos
		local targetAng = isLeft and frame.lefthandAng or frame.righthandAng
		if not targetPos or not targetAng then return nil end

		local clavicleBone = isLeft and bones.b_leftClavicle or bones.b_rightClavicle
		local upperarmBone = isLeft and bones.b_leftUpperarm or bones.b_rightUpperarm
		if not clavicleBone or clavicleBone < 0 or not upperarmBone or upperarmBone < 0 then return nil end
		if not boneinfo[upperarmBone] then return nil end

		local mtx = ent:GetBoneMatrix(clavicleBone)
		local claviclePos = mtx and mtx:GetTranslation() or (ent:GetPos() + Vector(0, 0, 50))
		state[prefix .. "ClaviclePos"] = claviclePos

		local tmp1 = claviclePos + plyAng:Right() * (isLeft and -state.clavicleLen or state.clavicleLen)
		local tmp2 = tmp1 + (targetPos - tmp1) * 0.15
		local clavicleTargetAng = (tmp2 - claviclePos):Angle()
		clavicleTargetAng:RotateAroundAxis(clavicleTargetAng:Forward(), 90)

		local upperarmPos = LocalToWorld(
			boneinfo[upperarmBone].relativePos,
			boneinfo[upperarmBone].relativeAng,
			claviclePos,
			clavicleTargetAng
		)
		local targetVec = targetPos - upperarmPos
		local targetVecLen = targetVec:Length()
		if targetVecLen < 0.01 then
			targetVec = plyAng:Forward() * 0.01
			targetVecLen = 0.01
		end
		local targetVecAng = targetVec:Angle()
		local upperarmTargetAng = Angle(targetVecAng.pitch, targetVecAng.yaw, targetVecAng.roll)
		if not isLeft then upperarmTargetAng:RotateAroundAxis(targetVec, 180) end

		local tmp = Angle(targetVecAng.pitch, frame.characterYaw or 0, isLeft and -90 or 90)
		local _, tang = WorldToLocal(ZERO_VEC, tmp, ZERO_VEC, targetVecAng)
		upperarmTargetAng:RotateAroundAxis(upperarmTargetAng:Forward(), tang.roll)

		local totalArmLen = state.upperArmLen + state.lowerArmLen
		local armStretchScale = 1
		local effUpper, effLower = state.upperArmLen, state.lowerArmLen
		-- noStretch: twin / mirror path must never rubber-band arm bones
		local stretchOn = (not state.noStretch)
			and convars
			and (convars.armStretcher == true or convars.armStretcher == 1)
		if stretchOn and targetVecLen > totalArmLen * 0.98 then
			armStretchScale = targetVecLen / (totalArmLen * 0.98)
			effUpper = state.upperArmLen * armStretchScale
			effLower = state.lowerArmLen * armStretchScale
		end
		-- Cap reach instead of stretching when twin: keep elbow solvable
		if state.noStretch and targetVecLen > totalArmLen * 0.98 then
			targetVecLen = totalArmLen * 0.98
			targetVec = targetVec:GetNormalized() * targetVecLen
			targetPos = upperarmPos + targetVec
		end
		state[prefix .. "armStretchScale"] = armStretchScale

		local a1 = math.deg(math.acos(math.Clamp(
			(effUpper * effUpper + targetVecLen * targetVecLen - effLower * effLower) / (2 * effUpper * targetVecLen),
			-1, 1
		)))
		if a1 == a1 then upperarmTargetAng:RotateAroundAxis(upperarmTargetAng:Up(), a1) end

		local test = (targetPos.z - upperarmPos.z + 20) * 1.5
		if test < 0 then test = 0 end
		local tvn = targetVec / targetVecLen
		upperarmTargetAng:RotateAroundAxis(tvn, (isLeft and 1 or -1) * (30 + test))

		local forearmTargetAng = Angle(upperarmTargetAng.pitch, upperarmTargetAng.yaw, upperarmTargetAng.roll)
		local a23 = 180 - a1 - math.deg(math.acos(math.Clamp(
			(effLower * effLower + targetVecLen * targetVecLen - effUpper * effUpper) / (2 * effLower * targetVecLen),
			-1, 1
		)))
		if a23 == a23 then forearmTargetAng:RotateAroundAxis(forearmTargetAng:Up(), 180 + a23) end

		local tmpH = Angle(targetAng.pitch, targetAng.yaw, targetAng.roll - 90)
		local _, tangH = WorldToLocal(ZERO_VEC, tmpH, ZERO_VEC, forearmTargetAng)
		local wristTargetAng = Angle(forearmTargetAng.pitch, forearmTargetAng.yaw, forearmTargetAng.roll)
		wristTargetAng:RotateAroundAxis(wristTargetAng:Forward(), tangH.roll)
		local ulnaTargetAng = LerpAngle(0.5, forearmTargetAng, wristTargetAng)

		return {
			clavicle = clavicleTargetAng,
			upperarm = upperarmTargetAng,
			forearm = forearmTargetAng,
			wrist = wristTargetAng,
			ulna = ulnaTargetAng,
			hand = isLeft and targetAng or (targetAng + RIGHT_HAND_OFFSET),
			targetPos = targetPos,
		}
	end

	-- Clear overrides
	for _, bd in pairs(boneinfo) do
		bd.overrideAng = nil
		bd.offsetAng = Angle(0, 0, 0)
	end

	local leftArm = ProcessArm("left")
	local rightArm = ProcessArm("right")

	local function setOverride(boneId, ang)
		if boneId and boneId >= 0 and boneinfo[boneId] and ang then
			boneinfo[boneId].overrideAng = ang
		end
	end

	if leftArm then
		setOverride(bones.b_leftClavicle, leftArm.clavicle)
		setOverride(bones.b_leftUpperarm, leftArm.upperarm)
		setOverride(bones.b_leftHand, leftArm.hand)
		if bones.b_leftWrist and bones.b_leftWrist >= 0 and boneinfo[bones.b_leftWrist]
			and bones.b_leftUlna and bones.b_leftUlna >= 0 and boneinfo[bones.b_leftUlna] then
			setOverride(bones.b_leftForearm, leftArm.forearm)
			setOverride(bones.b_leftWrist, leftArm.wrist)
			setOverride(bones.b_leftUlna, leftArm.ulna)
		else
			setOverride(bones.b_leftForearm, leftArm.ulna)
		end
		state.L_HandTargetPos = state.L_armStretchScale ~= 1 and leftArm.targetPos or nil
	end
	if rightArm then
		setOverride(bones.b_rightClavicle, rightArm.clavicle)
		setOverride(bones.b_rightUpperarm, rightArm.upperarm)
		setOverride(bones.b_rightHand, rightArm.hand)
		if bones.b_rightWrist and bones.b_rightWrist >= 0 and boneinfo[bones.b_rightWrist]
			and bones.b_rightUlna and bones.b_rightUlna >= 0 and boneinfo[bones.b_rightUlna] then
			setOverride(bones.b_rightForearm, rightArm.forearm)
			setOverride(bones.b_rightWrist, rightArm.wrist)
			setOverride(bones.b_rightUlna, rightArm.ulna)
		else
			setOverride(bones.b_rightForearm, rightArm.ulna)
		end
		state.R_HandTargetPos = state.R_armStretchScale ~= 1 and rightArm.targetPos or nil
	end

	-- Fingers (same as cl_character)
	local openA = g_VR.openHandAngles or g_VR.defaultOpenHandAngles
	local closedA = g_VR.closedHandAngles or g_VR.defaultClosedHandAngles
	if openA and closedA then
		for k, v in pairs(bones.fingers) do
			if v and v >= 0 and boneinfo[v] then
				local curl = frame["finger" .. math.floor((k - 1) / 3 + 1)] or 0
				boneinfo[v].offsetAng = LerpAngle(curl, openA[k] or Angle(), closedA[k] or Angle())
			end
		end
	end

	-- Head orientation only — match cl_character BoneCallback:
	-- SetAngles on the *existing* head matrix after SetupBones.
	-- Never invent translation (parent.up*6 / ent+Z64 = giraffe neck).
	-- Note: head is NOT in boneinfo (only clavicle arm trees are); use state.headTargetAng.
	if frame.hmdAng and bones.b_head and bones.b_head >= 0 then
		local _, targetAng = LocalToWorld(ZERO_VEC, Angle(-80, 0, 90), ZERO_VEC, frame.hmdAng)
		if state.headDampen then
			local maxP = state.headMaxPitch or 55
			local p = targetAng.p
			if p > maxP then
				targetAng = Angle(maxP, targetAng.y, targetAng.r)
			elseif p < -maxP then
				targetAng = Angle(-maxP, targetAng.y, targetAng.r)
			end
		end
		state.headTargetAng = targetAng
	else
		state.headTargetAng = nil
	end

	-- Build world matrices along arm trees
	local targets = {}
	for i = 1, #state.boneorder do
		local bone = state.boneorder[i]
		local bd = boneinfo[bone]
		if not bd then continue end

		local wpos, wang
		if bd.name == "ValveBiped.Bip01_L_Clavicle" then
			wpos = state.L_ClaviclePos or ZERO_VEC
			wang = bd.overrideAng or Angle()
		elseif bd.name == "ValveBiped.Bip01_R_Clavicle" then
			wpos = state.R_ClaviclePos or ZERO_VEC
			wang = bd.overrideAng or Angle()
		else
			local parent = boneinfo[bd.parent]
			if parent then
				wpos, wang = LocalToWorld(bd.relativePos, bd.relativeAng + bd.offsetAng, parent.pos, parent.ang)
			else
				continue
			end
		end

		if bd.overrideAng ~= nil then wang = bd.overrideAng end
		if state.L_HandTargetPos and bd.name == "ValveBiped.Bip01_L_Hand" then
			wpos = state.L_HandTargetPos
		elseif state.R_HandTargetPos and bd.name == "ValveBiped.Bip01_R_Hand" then
			wpos = state.R_HandTargetPos
		end

		local mat = bd.targetMatrix
		mat:Identity()
		mat:SetTranslation(wpos)
		mat:SetAngles(wang)
		-- Twin / noStretch: never scale arm bones (rubber-band stretch)
		if not state.noStretch then
			if state.L_armStretchScale ~= 1 and (bd.name == "ValveBiped.Bip01_L_UpperArm" or bd.name == "ValveBiped.Bip01_L_Forearm") then
				mat:Scale(Vector(state.L_armStretchScale, 1, 1))
			end
			if state.R_armStretchScale ~= 1 and (bd.name == "ValveBiped.Bip01_R_UpperArm" or bd.name == "ValveBiped.Bip01_R_Forearm") then
				mat:Scale(Vector(state.R_armStretchScale, 1, 1))
			end
		end
		bd.pos = wpos
		bd.ang = wang
		targets[bone] = mat
	end

	-- Head: angle-only on live SetupBones translation (cl_character path)
	if bones.b_head and bones.b_head >= 0 and state.headTargetAng then
		local hm = ent:GetBoneMatrix(bones.b_head)
		if hm then
			local mat = Matrix()
			mat:SetTranslation(hm:GetTranslation())
			mat:SetAngles(state.headTargetAng)
			targets[bones.b_head] = mat
		end
	end

	state.targets = targets
	return true
end

return F
