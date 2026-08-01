-- =============================================================================
-- vrmod.charik — Character body IK SoT (Cube law: one energy path)
--
-- Source of truth for arm / finger / head bone drive — same math as
-- cl_character UpdateIK + BoneCallback. Used by:
--   • Real player (cl_character.lua) — world-space net frame
--   • Avatar twin (cl_avatar_editor.lua) — TransformFrame(facing) = flip + L↔R
--
-- Frame schema (sh_network buildClientFrame / lerpedFrame):
--   characterYaw, hmdPos/Ang, lefthandPos/Ang, righthandPos/Ang,
--   finger1..10, optional waist/feet
--
-- NEVER invent head translation. NEVER dual-truth pose. Twin never writes
-- g_VR.net / VRUtilNetUpdateLocalPly.
-- =============================================================================
if SERVER then return end

vrmod = vrmod or {}
vrmod.charik = vrmod.charik or {}
local C = vrmod.charik

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
	b_leftCalf = "ValveBiped.Bip01_L_Calf",
	b_leftThigh = "ValveBiped.Bip01_L_Thigh",
	b_leftFoot = "ValveBiped.Bip01_L_Foot",
	b_rightClavicle = "ValveBiped.Bip01_R_Clavicle",
	b_rightUpperarm = "ValveBiped.Bip01_R_UpperArm",
	b_rightForearm = "ValveBiped.Bip01_R_Forearm",
	b_rightHand = "ValveBiped.Bip01_R_Hand",
	b_rightWrist = "ValveBiped.Bip01_R_Wrist",
	b_rightUlna = "ValveBiped.Bip01_R_Ulna",
	b_rightCalf = "ValveBiped.Bip01_R_Calf",
	b_rightThigh = "ValveBiped.Bip01_R_Thigh",
	b_rightFoot = "ValveBiped.Bip01_R_Foot",
	b_head = "ValveBiped.Bip01_Head1",
	b_spine = "ValveBiped.Bip01_Spine",
}

local FINGER_TMP = {
	"0", "01", "02", "1", "11", "12", "2", "21", "22", "3", "31", "32", "4", "41", "42",
}

------------------------------------------------------------------------
-- Bone tree (clavicle → fingers) — same as cl_character RecursiveBoneTable2
------------------------------------------------------------------------
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

--- Build IK state for player or ClientsideModel. Call after model set + SetupBones.
-- @return state or nil
function C.Init(ent, opts)
	if not IsValid(ent) then return nil end
	opts = opts or {}
	ent:SetupBones()

	local state = {
		boneinfo = {},
		boneorder = {},
		bones = { fingers = {} },
		clavicleLen = 8,
		upperArmLen = 12,
		lowerArmLen = 12,
		upperLegLen = 16,
		lowerLegLen = 16,
		spineZ = 40,
		spineLen = 26,
		L_ClaviclePos = Vector(),
		R_ClaviclePos = Vector(),
		L_armStretchScale = 1,
		R_armStretchScale = 1,
		horizontalCrouchOffset = 0,
		verticalCrouchOffset = 0,
		manip = {}, -- [boneId] = Angle for spine/legs
		targets = {}, -- [boneId] = Matrix (filled each Update)
		-- twin policy (Cube avatar)
		noStretch = opts.noStretch and true or false,
		headDampen = opts.headDampen and true or false,
		headMaxPitch = opts.headMaxPitch or 55,
		preRenderPos = Vector(),
		eyeHeight = opts.eyeHeight or 66.8,
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
	local function dist(a, c)
		if not a or a < 0 or not c or c < 0 then return nil end
		local pa, pc = ent:GetBonePosition(a), ent:GetBonePosition(c)
		if not pa or not pc then return nil end
		return pa:Distance(pc)
	end

	local d
	d = dist(b.b_leftClavicle, b.b_leftUpperarm)
	if d then state.clavicleLen = math.max(2, d) end
	d = dist(b.b_leftUpperarm, b.b_leftForearm)
	if d then state.upperArmLen = math.max(4, d) end
	d = dist(b.b_leftForearm, b.b_leftHand)
	if d then state.lowerArmLen = math.max(4, d) end
	d = dist(b.b_leftThigh, b.b_leftCalf)
	if d then state.upperLegLen = math.max(4, d) end
	d = dist(b.b_leftCalf, b.b_leftFoot)
	if d then state.lowerLegLen = math.max(4, d) end

	if b.b_spine and b.b_spine >= 0 then
		local sp = ent:GetBonePosition(b.b_spine)
		if sp then
			state.spineZ = sp.z - ent:GetPos().z
			state.spineLen = math.max(4, (ent:GetPos().z + state.eyeHeight) - sp.z)
		end
	end

	return state
end

------------------------------------------------------------------------
-- Mirror transform (facing twin) — sagittal flip + L↔R before IK
------------------------------------------------------------------------
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
		-- X=Forward, Y=Right, Z=Up — flip Y; Euler yaw/roll negate (no AngleFromBasis twist)
		relPos.y = -relPos.y
		relAng = Angle(relAng.p, -relAng.y, -relAng.r)
	end
	return LocalToWorld(relPos, relAng, dstFeet, dstYaw)
end

--- Rotate / mirror a net frame into target space.
-- mode "facing" | "mirror" = true mirror (flip + L/R swap)
-- mode "clone" | "world"  = rigid (no L/R swap); world leaves poses absolute if feet equal
function C.TransformFrame(src, mode, srcFeet, srcYaw, dstFeet, dstYaw)
	if not src then return nil end
	if mode == "mirror" then mode = "facing" end
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
		-- Anatomical L↔R AFTER spatial flip — never write mirrored R onto R bone
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

------------------------------------------------------------------------
-- Full UpdateIK — arms + fingers + crouch manip + head ang (same as player)
------------------------------------------------------------------------
function C.Update(ent, state, frame, opts)
	if not IsValid(ent) or not state or not frame then return false end
	if not frame.lefthandPos and not frame.righthandPos then return false end
	opts = opts or {}
	-- Stock foregrip: force left hand target to stereo-frozen attach (FBT/avatar body)
	local sf = (g_VR and g_VR.stereoFrame) or 0
	if g_VR and g_VR.foregripActive and g_VR._leftHandSnapFrame == sf
		and g_VR._leftHandSnapPos and g_VR._leftHandSnapAng then
		frame.lefthandPos = g_VR._leftHandSnapPos
		frame.lefthandAng = g_VR._leftHandSnapAng
	end

	local bones = state.bones
	local boneinfo = state.boneinfo
	if not bones or not boneinfo then return false end
	local inVehicle = opts.inVehicle and true or false
	local plyAng = opts.plyAng
	if not plyAng then
		plyAng = Angle(0, frame.characterYaw or 0, 0)
	end
	if inVehicle and opts.vehicleAng then
		local _, va = LocalToWorld(ZERO_VEC, Angle(0, 90, 0), ZERO_VEC, opts.vehicleAng)
		plyAng = va
	end

	local eyeHeight = opts.eyeHeight or state.eyeHeight or 66.8
	local convars = {}
	if vrmod.GetConvars then
		local ok, a, b = pcall(vrmod.GetConvars)
		if ok then convars = b or a or {} end
	end
	if not istable(convars) then convars = {} end
	local stretchAllowed = (not state.noStretch)
		and (convars.armStretcher == true or convars.armStretcher == 1)

	-- Clear arm overrides / finger offsets
	for _, bd in pairs(boneinfo) do
		if bd then
			bd.overrideAng = nil
			bd.offsetAng = Angle(0, 0, 0)
		end
	end
	state.manip = {}
	state.L_HandTargetPos = nil
	state.R_HandTargetPos = nil
	state.headTargetAng = nil
	state.horizontalCrouchOffset = state.horizontalCrouchOffset or 0
	state.verticalCrouchOffset = state.verticalCrouchOffset or 0
	state.spineZ = state.spineZ or 40
	state.upperLegLen = state.upperLegLen or 16
	state.lowerLegLen = state.lowerLegLen or 16
	state.upperArmLen = state.upperArmLen or 12
	state.lowerArmLen = state.lowerArmLen or 12
	state.clavicleLen = state.clavicleLen or 8

	-- Crouch / spine / legs (same formulas as cl_character)
	if not inVehicle and frame.hmdPos and frame.hmdAng and bones.b_spine and bones.b_spine >= 0 then
		local spineLen = eyeHeight - state.spineZ
		if spineLen < 1 then spineLen = 1 end
		state.spineLen = spineLen
		local headHeight = frame.hmdPos.z + (frame.hmdAng:Forward() * -3).z
		local baseZ = opts.baseZ or ent:GetPos().z
		local cutAmount = math.Clamp(baseZ + eyeHeight - headHeight, 0, 40)
		local spineTargetLen = spineLen - cutAmount * 0.5
		local aSpine = math.acos(math.Clamp(spineTargetLen / math.max(spineLen, 0.01), -1, 1))
		state.horizontalCrouchOffset = math.sin(aSpine) * spineLen
		state.verticalCrouchOffset = cutAmount * 0.5
		state.manip[bones.b_spine] = Angle(0, math.deg(aSpine), 0)

		local legTargetLen = state.upperLegLen + state.lowerLegLen - state.verticalCrouchOffset * 0.8
		local cosA1 = (state.upperLegLen * state.upperLegLen + legTargetLen * legTargetLen - state.lowerLegLen * state.lowerLegLen)
			/ (2 * state.upperLegLen * math.max(legTargetLen, 0.01))
		local cosA23 = (state.lowerLegLen * state.lowerLegLen + legTargetLen * legTargetLen - state.upperLegLen * state.upperLegLen)
			/ (2 * state.lowerLegLen * math.max(legTargetLen, 0.01))
		local a1 = math.deg(math.acos(math.Clamp(cosA1, -1, 1)))
		local a23 = 180 - a1 - math.deg(math.acos(math.Clamp(cosA23, -1, 1)))
		if a1 ~= a1 or a23 ~= a23 then
			a1, a23 = 0, 180
		end
		if bones.b_leftCalf >= 0 then state.manip[bones.b_leftCalf] = Angle(0, -(a23 - 180), 0) end
		if bones.b_leftThigh >= 0 then state.manip[bones.b_leftThigh] = Angle(0, -a1, 0) end
		if bones.b_rightCalf >= 0 then state.manip[bones.b_rightCalf] = Angle(0, -(a23 - 180), 0) end
		if bones.b_rightThigh >= 0 then state.manip[bones.b_rightThigh] = Angle(0, -a1, 0) end
		if bones.b_leftFoot >= 0 then state.manip[bones.b_leftFoot] = Angle(0, -a1, 0) end
		if bones.b_rightFoot >= 0 then state.manip[bones.b_rightFoot] = Angle(0, -a1, 0) end
	elseif bones.b_spine and bones.b_spine >= 0 then
		state.horizontalCrouchOffset = 0
		state.verticalCrouchOffset = 0
		state.manip[bones.b_spine] = Angle(0, 0, 0)
		if bones.b_leftCalf >= 0 then state.manip[bones.b_leftCalf] = Angle(0, 0, 0) end
		if bones.b_leftThigh >= 0 then state.manip[bones.b_leftThigh] = Angle(0, 0, 0) end
		if bones.b_rightCalf >= 0 then state.manip[bones.b_rightCalf] = Angle(0, 0, 0) end
		if bones.b_rightThigh >= 0 then state.manip[bones.b_rightThigh] = Angle(0, 0, 0) end
		if bones.b_leftFoot >= 0 then state.manip[bones.b_leftFoot] = Angle(0, 0, 0) end
		if bones.b_rightFoot >= 0 then state.manip[bones.b_rightFoot] = Angle(0, 0, 0) end
	end

	-- Apply manip early so clavicle GetBoneMatrix sees crouch (player path does this via ManipulateBoneAngles before SetupBones)
	if opts.applyManip ~= false then
		C.ApplyManip(ent, state)
	end

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
		local clavicleTargetAng
		if not inVehicle then
			clavicleTargetAng = (tmp2 - claviclePos):Angle()
		else
			_, clavicleTargetAng = LocalToWorld(Vector(), WorldToLocal(tmp2 - claviclePos, ZERO_ANG, ZERO_VEC, plyAng):Angle(), ZERO_VEC, plyAng)
		end
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

		local targetVecAng, targetVecAngLocal
		if not inVehicle then
			targetVecAng = targetVec:Angle()
		else
			targetVecAngLocal = WorldToLocal(targetVec, ZERO_ANG, ZERO_VEC, plyAng):Angle()
			_, targetVecAng = LocalToWorld(Vector(), targetVecAngLocal, ZERO_VEC, plyAng)
		end

		local upperarmTargetAng = Angle(targetVecAng.pitch, targetVecAng.yaw, targetVecAng.roll)
		if not isLeft then upperarmTargetAng:RotateAroundAxis(targetVec, 180) end

		local tmp
		if not inVehicle then
			tmp = Angle(targetVecAng.pitch, frame.characterYaw or 0, isLeft and -90 or 90)
		else
			_, tmp = LocalToWorld(Vector(), Angle((targetVecAngLocal or targetVecAng).pitch, 0, isLeft and -90 or 90), ZERO_VEC, plyAng)
		end
		local _, tang = WorldToLocal(ZERO_VEC, tmp, ZERO_VEC, targetVecAng)
		upperarmTargetAng:RotateAroundAxis(upperarmTargetAng:Forward(), tang.roll)

		local totalArmLen = state.upperArmLen + state.lowerArmLen
		local armStretchScale = 1
		local effUpper, effLower = state.upperArmLen, state.lowerArmLen
		if stretchAllowed and targetVecLen > totalArmLen * 0.98 then
			armStretchScale = targetVecLen / (totalArmLen * 0.98)
			effUpper = state.upperArmLen * armStretchScale
			effLower = state.lowerArmLen * armStretchScale
		elseif state.noStretch and targetVecLen > totalArmLen * 0.98 then
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

		local test
		if not inVehicle then
			test = (targetPos.z - upperarmPos.z + 20) * 1.5
		else
			test = ((targetPos - upperarmPos):Dot(plyAng:Up()) + 20) * 1.5
		end
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
		if bones.b_leftWrist >= 0 and boneinfo[bones.b_leftWrist]
			and bones.b_leftUlna >= 0 and boneinfo[bones.b_leftUlna] then
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
		if bones.b_rightWrist >= 0 and boneinfo[bones.b_rightWrist]
			and bones.b_rightUlna >= 0 and boneinfo[bones.b_rightUlna] then
			setOverride(bones.b_rightForearm, rightArm.forearm)
			setOverride(bones.b_rightWrist, rightArm.wrist)
			setOverride(bones.b_rightUlna, rightArm.ulna)
		else
			setOverride(bones.b_rightForearm, rightArm.ulna)
		end
		state.R_HandTargetPos = state.R_armStretchScale ~= 1 and rightArm.targetPos or nil
	end

	-- Fingers (same open/closed tables as cl_character)
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

	-- Head target angle — cl_character BoneCallback: LocalToWorld(Angle(-80,0,90), hmdAng)
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
	end

	-- Build arm-tree world matrices
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
			if not parent then continue end
			wpos, wang = LocalToWorld(bd.relativePos, bd.relativeAng + bd.offsetAng, parent.pos, parent.ang)
		end

		if bd.overrideAng ~= nil then wang = bd.overrideAng end
		if state.L_HandTargetPos and bd.name == "ValveBiped.Bip01_L_Hand" then
			wpos = state.L_HandTargetPos
		elseif state.R_HandTargetPos and bd.name == "ValveBiped.Bip01_R_Hand" then
			wpos = state.R_HandTargetPos
		end

		local mat = bd.targetMatrix
		local dirty = not bd.pos or not bd.ang
			or wpos:DistToSqr(bd.pos) > POS_THRESHOLD
			or math.abs(wang.pitch - bd.ang.pitch) > ANGLE_THRESHOLD
			or math.abs(wang.yaw - bd.ang.yaw) > ANGLE_THRESHOLD
			or math.abs(wang.roll - bd.ang.roll) > ANGLE_THRESHOLD
		if dirty then
			mat:Identity()
			mat:SetTranslation(wpos)
			mat:SetAngles(wang)
			if not state.noStretch then
				if state.L_armStretchScale ~= 1
					and (bd.name == "ValveBiped.Bip01_L_UpperArm" or bd.name == "ValveBiped.Bip01_L_Forearm") then
					mat:Scale(Vector(state.L_armStretchScale, 1, 1))
				end
				if state.R_armStretchScale ~= 1
					and (bd.name == "ValveBiped.Bip01_R_UpperArm" or bd.name == "ValveBiped.Bip01_R_Forearm") then
					mat:Scale(Vector(state.R_armStretchScale, 1, 1))
				end
			end
			bd.pos = wpos
			bd.ang = wang
		end
		targets[bone] = mat
	end

	-- Head: angle-only on live SetupBones translation (never invent pos)
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

--- Apply spine/leg ManipulateBoneAngles (player + ClientsideModel)
function C.ApplyManip(ent, state)
	if not IsValid(ent) or not state or not state.manip then return end
	for boneId, ang in pairs(state.manip) do
		if boneId and boneId >= 0 and ang then
			ent:ManipulateBoneAngles(boneId, ang)
		end
	end
end

--- Apply arm/finger/head SetBoneMatrix targets (BuildBonePositions / PrePlayerDraw)
function C.ApplyMatrices(ent, state)
	if not IsValid(ent) or not state then return end
	local targets = state.targets
	if not targets then return end
	for boneId, mat in pairs(targets) do
		if boneId and mat and ent:GetBoneMatrix(boneId) then
			ent:SetBoneMatrix(boneId, mat)
		end
	end
end

--- Head-only (BoneCallback path) — angle on existing matrix
function C.ApplyHead(ent, state, frame)
	if not IsValid(ent) or not state then return end
	local bid = state.bones and state.bones.b_head
	if not isnumber(bid) or bid < 0 then return end
	local hmdAng = frame and frame.hmdAng
	local targetAng = state.headTargetAng
	if hmdAng then
		local _
		_, targetAng = LocalToWorld(ZERO_VEC, Angle(-80, 0, 90), ZERO_VEC, hmdAng)
	end
	if not targetAng then return end
	local mtx = ent:GetBoneMatrix(bid)
	if not mtx then return end
	mtx:SetAngles(targetAng)
	ent:SetBoneMatrix(bid, mtx)
end

--- Clear manip angles (exit / model change)
function C.ClearManip(ent, state)
	if not IsValid(ent) or not state or not state.bones then return end
	for k, v in pairs(state.bones) do
		if isnumber(v) and v >= 0 then
			ent:ManipulateBoneAngles(v, Angle(0, 0, 0))
		end
	end
end

-- Compat alias used by older twin path
C.Apply = C.Update

return C
