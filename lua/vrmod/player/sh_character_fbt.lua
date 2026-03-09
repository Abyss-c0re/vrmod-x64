-- Full-Body Tracking (FBT) Module for VRMod
if SERVER then
	util.AddNetworkString("vrmod_fbt_cal")
	util.AddNetworkString("vrmod_fbt_toggle")
	local caldata = {}
	net.Receive("vrmod_fbt_cal", function(len, ply)
		local requestedPly = net.ReadBool() and net.ReadEntity() or nil
		local steamid = requestedPly and requestedPly:SteamID() or ply:SteamID()
		local cd = caldata[steamid] or {}
		caldata[steamid] = cd
		if not requestedPly then
			for i = 0, 3 do
				cd[i * 2 + 1] = net.ReadVector()
				cd[i * 2 + 2] = net.ReadAngle()
			end
		end

		net.Start("vrmod_fbt_cal")
		net.WriteEntity(requestedPly or ply)
		for i = 0, 3 do
			net.WriteVector(cd[i * 2 + 1])
			net.WriteAngle(cd[i * 2 + 2])
		end

		if requestedPly then
			if ply.hasRequestedVRPlayers then net.Send(ply) end
		else
			local omittedPlayers = {}
			for k, v in ipairs(player.GetAll()) do
				if not v.hasRequestedVRPlayers then omittedPlayers[#omittedPlayers + 1] = v end
			end

			net.SendOmit(omittedPlayers)
		end
	end)

	vrmod.NetReceiveLimited("vrmod_fbt_toggle", 10, 1, function(len, ply)
		net.Start("vrmod_fbt_toggle")
		net.WriteEntity(ply)
		net.WriteBool(net.ReadBool())
		net.Broadcast()
	end)
	return
end

-- CLIENT-SIDE CODE BELOW
local vrmod_fbt = {} -- Module table for organization
vrmod_fbt.characterInfo = {}
vrmod_fbt.convarValues = select(2, vrmod.GetConvars()) -- Cache convars
vrmod_fbt.zeroVec = Vector()
vrmod_fbt.zeroAng = Angle()
-- Bone name constants for clarity
local BONE_NAMES = {
	leftClavicle = "ValveBiped.Bip01_L_Clavicle",
	leftUpperArm = "ValveBiped.Bip01_L_UpperArm",
	leftForearm = "ValveBiped.Bip01_L_Forearm",
	leftHand = "ValveBiped.Bip01_L_Hand",
	leftWrist = "ValveBiped.Bip01_L_Wrist",
	leftUlna = "ValveBiped.Bip01_L_Ulna",
	leftCalf = "ValveBiped.Bip01_L_Calf",
	leftThigh = "ValveBiped.Bip01_L_Thigh",
	leftFoot = "ValveBiped.Bip01_L_Foot",
	rightClavicle = "ValveBiped.Bip01_R_Clavicle",
	rightUpperArm = "ValveBiped.Bip01_R_UpperArm",
	rightForearm = "ValveBiped.Bip01_R_Forearm",
	rightHand = "ValveBiped.Bip01_R_Hand",
	rightWrist = "ValveBiped.Bip01_R_Wrist",
	rightUlna = "ValveBiped.Bip01_R_Ulna",
	rightCalf = "ValveBiped.Bip01_R_Calf",
	rightThigh = "ValveBiped.Bip01_R_Thigh",
	rightFoot = "ValveBiped.Bip01_R_Foot",
	head = "ValveBiped.Bip01_Head1",
	spine = "ValveBiped.Bip01_Spine",
	spine1 = "ValveBiped.Bip01_Spine1",
	spine2 = "ValveBiped.Bip01_Spine2",
	spine4 = "ValveBiped.Bip01_Spine4",
	neck = "ValveBiped.Bip01_Neck1",
	pelvis = "ValveBiped.Bip01_Pelvis",
}

local FINGER_BONE_NAMES = {"ValveBiped.Bip01_L_Finger0", "ValveBiped.Bip01_L_Finger01", "ValveBiped.Bip01_L_Finger02", "ValveBiped.Bip01_L_Finger1", "ValveBiped.Bip01_L_Finger11", "ValveBiped.Bip01_L_Finger12", "ValveBiped.Bip01_L_Finger2", "ValveBiped.Bip01_L_Finger21", "ValveBiped.Bip01_L_Finger22", "ValveBiped.Bip01_L_Finger3", "ValveBiped.Bip01_L_Finger31", "ValveBiped.Bip01_L_Finger32", "ValveBiped.Bip01_L_Finger4", "ValveBiped.Bip01_L_Finger41", "ValveBiped.Bip01_L_Finger42", "ValveBiped.Bip01_R_Finger0", "ValveBiped.Bip01_R_Finger01", "ValveBiped.Bip01_R_Finger02", "ValveBiped.Bip01_R_Finger1", "ValveBiped.Bip01_R_Finger11", "ValveBiped.Bip01_R_Finger12", "ValveBiped.Bip01_R_Finger2", "ValveBiped.Bip01_R_Finger21", "ValveBiped.Bip01_R_Finger22", "ValveBiped.Bip01_R_Finger3", "ValveBiped.Bip01_R_Finger31", "ValveBiped.Bip01_R_Finger32", "ValveBiped.Bip01_R_Finger4", "ValveBiped.Bip01_R_Finger41", "ValveBiped.Bip01_R_Finger42",}
-- Initializes character info for a player model
function vrmod_fbt.Init(ply)
	local steamid = ply:SteamID()
	local info = vrmod_fbt.characterInfo[steamid] or {}
	vrmod_fbt.characterInfo[steamid] = info
	local pmname = ply.vrmod_pm or ply:GetModel()
	if info.modelName == pmname then return true end
	local tmpPlayerModel = ClientsideModel(pmname)
	if not IsValid(tmpPlayerModel) then return false end
	tmpPlayerModel:SetupBones()
	-- Lookup bone IDs
	local boneids = {}
	for k, v in pairs(BONE_NAMES) do
		boneids[k] = tmpPlayerModel:LookupBone(v) or -1
	end

	info.boneids = boneids
	-- Lookup finger bone IDs
	local fingerboneids = {}
	for i, name in ipairs(FINGER_BONE_NAMES) do
		fingerboneids[i] = tmpPlayerModel:LookupBone(name) or -1
	end

	info.fingerboneids = fingerboneids
	-- Validate required bones
	g_VR.errorText = ply == LocalPlayer() and "" or g_VR.errorText
	for k, v in pairs(boneids) do
		if v == -1 and not table.HasValue({"leftWrist", "rightWrist", "leftUlna", "rightUlna"}, k) then
			g_VR.errorText = ply == LocalPlayer() and "Missing bone: " .. k or g_VR.errorText
			tmpPlayerModel:Remove()
			vrmod_fbt.characterInfo[steamid] = nil
			vrmod.logger.Err("FBT Init failed for %s - missing bone: %s", steamid, k)
			return false
		end
	end

	info.modelName = pmname
	-- Build full bone info table
	local boneinfo = {}
	info.boneinfo = boneinfo
	local boneCount = tmpPlayerModel:GetBoneCount()
	info.boneCount = boneCount
	for i = 0, boneCount - 1 do
		local parent = tmpPlayerModel:GetBoneParent(i)
		local mtx = tmpPlayerModel:GetBoneMatrix(i) or Matrix()
		local mtxParent = tmpPlayerModel:GetBoneMatrix(parent) or mtx
		local relativePos, relativeAng = WorldToLocal(mtx:GetTranslation(), mtx:GetAngles(), mtxParent:GetTranslation(), mtxParent:GetAngles())
		boneinfo[i] = {
			name = tmpPlayerModel:GetBoneName(i),
			parent = parent,
			relativePos = relativePos,
			relativeAng = relativeAng,
			offsetAng = vrmod_fbt.zeroAng,
			pos = vrmod_fbt.zeroVec,
			ang = vrmod_fbt.zeroAng,
			targetMatrix = mtx
		}
	end

	-- Measure limb lengths (using left side, assuming symmetry)
	info.upperLegLen = (tmpPlayerModel:GetBoneMatrix(boneids.leftCalf):GetTranslation() - tmpPlayerModel:GetBoneMatrix(boneids.leftThigh):GetTranslation()):Length()
	info.lowerLegLen = (tmpPlayerModel:GetBoneMatrix(boneids.leftFoot):GetTranslation() - tmpPlayerModel:GetBoneMatrix(boneids.leftCalf):GetTranslation()):Length()
	info.clavicleLen = (tmpPlayerModel:GetBoneMatrix(boneids.leftUpperArm):GetTranslation() - tmpPlayerModel:GetBoneMatrix(boneids.leftClavicle):GetTranslation()):Length()
	info.upperArmLen = (tmpPlayerModel:GetBoneMatrix(boneids.leftForearm):GetTranslation() - tmpPlayerModel:GetBoneMatrix(boneids.leftUpperArm):GetTranslation()):Length()
	info.lowerArmLen = (tmpPlayerModel:GetBoneMatrix(boneids.leftHand):GetTranslation() - tmpPlayerModel:GetBoneMatrix(boneids.leftForearm):GetTranslation()):Length()
	-- Default angles
	_, info.defaultToNeutralClavicleAng = WorldToLocal(vrmod_fbt.zeroVec, Angle(0, 90, 90), vrmod_fbt.zeroVec, tmpPlayerModel:GetBoneMatrix(boneids.leftClavicle):GetAngles())
	info.defaultLeftFootAngles = tmpPlayerModel:GetBoneMatrix(boneids.leftFoot):GetAngles()
	info.defaultRightFootAngles = tmpPlayerModel:GetBoneMatrix(boneids.rightFoot):GetAngles()
	-- Build spine bend lookup tables
	vrmod_fbt.BuildSpineBendTables(info, boneids, boneinfo, tmpPlayerModel)
	tmpPlayerModel:Remove()
	vrmod.logger.Info("FBT Init succeeded for %s (model: %s)", steamid, pmname)
	return true
end

-- Helper to build spine bend lookup tables
function vrmod_fbt.BuildSpineBendTables(info, boneids, boneinfo)
	local degToBendRightAmount = {}
	info.degToBendRightAmount = degToBendRightAmount
	local degToBendForwardAmount = {}
	info.degToBendForwardAmount = degToBendForwardAmount
	local tmp = {
		forward = {},
		right = {}
	}

	local tmpboneids = {boneids.pelvis, boneids.spine, boneids.spine1, boneids.spine2, boneids.spine4, boneids.neck, boneids.head}
	for i = 1, 402 do
		local bendForwardAmount = i > 201 and (i - 302) * 0.4 or 0
		local bendRightAmount = i <= 201 and (i - 101) * 0.4 or 0
		boneinfo[boneids.spine].offsetAng = Angle(-bendForwardAmount, bendRightAmount, 0)
		boneinfo[boneids.spine1].offsetAng = Angle(bendRightAmount, bendForwardAmount, 0)
		boneinfo[boneids.spine2].offsetAng = Angle(bendRightAmount, bendForwardAmount, 0)
		boneinfo[boneids.spine4].offsetAng = Angle(bendRightAmount, bendForwardAmount, 0)
		boneinfo[boneids.neck].offsetAng = Angle(bendRightAmount, bendForwardAmount, 0)
		for j = 1, 7 do
			local bi = boneinfo[tmpboneids[j]]
			local parentInfo = boneinfo[bi.parent] or bi
			local wpos, wang = LocalToWorld(bi.relativePos, bi.relativeAng + bi.offsetAng, parentInfo.pos, parentInfo.ang)
			bi.pos, bi.ang = wpos, wang
			if j == 7 then
				if i > 201 then
					tmp.forward[#tmp.forward + 1] = {bendForwardAmount, math.deg(math.atan2(wpos.z, wpos.y))}
				else
					tmp.right[#tmp.right + 1] = {bendRightAmount, math.deg(math.atan2(-wpos.x, wpos.y))}
				end
			end
		end
	end

	for asd = 1, 2 do
		local input = asd == 1 and tmp.right or tmp.forward
		local output = asd == 1 and degToBendRightAmount or degToBendForwardAmount
		for i = -90, 90 do
			for j = 1, #input - 1 do -- Avoid out-of-bounds
				if i >= input[j][2] and i <= input[j + 1][2] then
					local prevAmt, prevDeg, nextAmt, nextDeg = input[j][1], input[j][2], input[j + 1][1], input[j + 1][2]
					output[#output + 1] = prevAmt + (nextAmt - prevAmt) * (i - prevDeg) / (nextDeg - prevDeg)
					break
				end
			end
		end
	end
end

-- Helper to get spine bend amount from lookup table
function vrmod_fbt.GetSpineBend(tab, val)
	local index = math.floor(val + 91)
	local prev = tab[index] or 0
	local next = tab[index + 1] or prev
	return prev + (next - prev) * val % 1
end

-- Calculates IK for a leg
function vrmod_fbt.CalculateLegIK(boneinfo, boneids, upperLegLen, lowerLegLen, thighId, calfId, footId, targetPos, targetAng, defaultFootAngles, wpos, wang)
	local targetVec = (targetPos - wpos):GetNormalized()
	local targetVecLen = (targetPos - wpos):Length()
	local newAng = targetVec:Angle()
	-- Rotation
	local mtx = Matrix()
	mtx:SetForward(targetVec)
	mtx:SetUp(targetVec:Cross(targetAng:Right()))
	mtx:SetRight(targetVec:Cross(mtx:GetUp()))
	local _, targetAngRelative = WorldToLocal(vrmod_fbt.zeroVec, mtx:GetAngles(), vrmod_fbt.zeroVec, newAng)
	newAng:RotateAroundAxis(targetVec, targetAngRelative.roll + 90)
	-- Contraction
	local a1 = math.deg(math.acos((upperLegLen * upperLegLen + targetVecLen * targetVecLen - lowerLegLen * lowerLegLen) / (2 * upperLegLen * targetVecLen)))
	if a1 == a1 then newAng:RotateAroundAxis(newAng:Up(), -a1) end
	boneinfo[thighId].overrideAng = newAng
	-- Calf
	local calfAng = Angle(newAng.pitch, newAng.yaw, newAng.roll)
	local a23 = 180 - a1 - math.deg(math.acos((lowerLegLen * lowerLegLen + targetVecLen * targetVecLen - upperLegLen * upperLegLen) / (2 * lowerLegLen * targetVecLen)))
	if a23 == a23 then calfAng:RotateAroundAxis(calfAng:Up(), 180 - a23) end
	boneinfo[calfId].overrideAng = calfAng
	-- Foot
	_, boneinfo[footId].overrideAng = LocalToWorld(vrmod_fbt.zeroVec, defaultFootAngles, vrmod_fbt.zeroVec, targetAng)
end

-- Calculates IK for an arm
function vrmod_fbt.CalculateArmIK(boneinfo, boneids, upperArmLen, lowerArmLen, upperArmId, forearmId, handId, wristId, ulnaId, targetPos, targetAng, upperBodyAng, convarValues, isLeft)
	local wpos = boneinfo[upperArmId].pos
	local targetPosRelative = WorldToLocal(targetPos, vrmod_fbt.zeroAng, wpos, upperBodyAng)
	local targetPosRelativeAng = targetPosRelative:Angle()
	local _, newUpperArmAng = LocalToWorld(vrmod_fbt.zeroVec, targetPosRelativeAng, vrmod_fbt.zeroVec, upperBodyAng)
	-- Arm roll
	local rollSign = isLeft and 1 or -1
	local rollOffset = isLeft and -90 + 30 + math.max((targetPosRelative.z + 20) * 1.5, 0) or 90 - 30 - math.max((targetPosRelative.z + 20) * 1.5, 0)
	local _, tmp1 = LocalToWorld(vrmod_fbt.zeroVec, Angle(targetPosRelativeAng.pitch, 0, rollOffset), vrmod_fbt.zeroVec, upperBodyAng)
	local _, tmp2 = WorldToLocal(vrmod_fbt.zeroVec, tmp1, vrmod_fbt.zeroVec, newUpperArmAng)
	newUpperArmAng:RotateAroundAxis(newUpperArmAng:Forward(), rollSign < 0 and 180 + tmp2.roll or tmp2.roll)
	-- Contraction with stretching
	local targetVecLen = (targetPos - wpos):Length()
	local totalArmLen = upperArmLen + lowerArmLen
	local armStretchScale = 1
	local effectiveUpperArmLen = upperArmLen
	local effectiveLowerArmLen = lowerArmLen
	if convarValues.armStretcher and targetVecLen > totalArmLen * 0.98 then
		armStretchScale = targetVecLen / (totalArmLen * 0.98)
		effectiveUpperArmLen = upperArmLen * armStretchScale
		effectiveLowerArmLen = lowerArmLen * armStretchScale
		boneinfo[handId].overridePos = targetPos
	else
		boneinfo[handId].overridePos = nil
	end

	local a1 = math.deg(math.acos((effectiveUpperArmLen * effectiveUpperArmLen + targetVecLen * targetVecLen - effectiveLowerArmLen * effectiveLowerArmLen) / (2 * effectiveUpperArmLen * targetVecLen)))
	if a1 == a1 then newUpperArmAng:RotateAroundAxis(newUpperArmAng:Up(), a1) end
	boneinfo[upperArmId].overrideAng = newUpperArmAng
	boneinfo[upperArmId].overrideScale = armStretchScale ~= 1 and Vector(armStretchScale, 1, 1) or nil
	-- Forearm
	local newForearmAng = Angle(newUpperArmAng.pitch, newUpperArmAng.yaw, newUpperArmAng.roll)
	local a23 = 180 - a1 - math.deg(math.acos((effectiveLowerArmLen * effectiveLowerArmLen + targetVecLen * targetVecLen - effectiveUpperArmLen * effectiveUpperArmLen) / (2 * effectiveLowerArmLen * targetVecLen)))
	if a23 == a23 then newForearmAng:RotateAroundAxis(newForearmAng:Up(), 180 + a23) end
	boneinfo[forearmId].overrideAng = newForearmAng
	boneinfo[forearmId].overrideScale = armStretchScale ~= 1 and Vector(armStretchScale, 1, 1) or nil
	-- Wrist
	local handAngAdj = Angle(targetAng.pitch, targetAng.yaw, targetAng.roll - 90)
	local _, handAngRelativeToForearm = WorldToLocal(vrmod_fbt.zeroVec, handAngAdj, vrmod_fbt.zeroVec, newForearmAng)
	local newWristAng = Angle(newForearmAng.pitch, newForearmAng.yaw, newForearmAng.roll)
	newWristAng:RotateAroundAxis(newWristAng:Forward(), handAngRelativeToForearm.roll)
	if wristId ~= -1 then boneinfo[wristId].overrideAng = newWristAng end
	-- Ulna
	if ulnaId ~= -1 then boneinfo[ulnaId].overrideAng = LerpAngle(0.5, newForearmAng, newWristAng) end
end

-- Calculates clavicle adjustment
function vrmod_fbt.CalculateClavicle(boneinfo, boneId, defaultToNeutralClavicleAng, clavicleLen, targetPos, wpos, wang, isLeft)
	local _, neutralClavicleAng = LocalToWorld(vrmod_fbt.zeroVec, defaultToNeutralClavicleAng, wpos, wang)
	local neutralShoulderPos = wpos + neutralClavicleAng:Forward() * clavicleLen
	local targetShoulderPos = neutralShoulderPos + (targetPos - neutralShoulderPos) * 0.15
	local targetShoulderPosRelative = WorldToLocal(targetShoulderPos, vrmod_fbt.zeroAng, wpos, neutralClavicleAng)
	local _, newClavicleAng = LocalToWorld(vrmod_fbt.zeroVec, targetShoulderPosRelative:Angle(), vrmod_fbt.zeroVec, neutralClavicleAng)
	boneinfo[boneId].overrideAng = newClavicleAng
	return neutralClavicleAng
end

-- Main bone position calculation function
function vrmod_fbt.CalculateBonePositions(ply)
	local steamid = ply:SteamID()
	local info = vrmod_fbt.characterInfo[steamid]
	local frame = g_VR.net[steamid].lerpedFrame
	if info.frameNumber == FrameNumber() or not frame then return end
	info.frameNumber = FrameNumber()
	local boneids = info.boneids
	local boneinfo = info.boneinfo
	local boneCount = info.boneCount
	local fingerboneids = info.fingerboneids
	local upperLegLen = info.upperLegLen
	local lowerLegLen = info.lowerLegLen
	local clavicleLen = info.clavicleLen
	local upperArmLen = info.upperArmLen
	local lowerArmLen = info.lowerArmLen
	local defaultToNeutralClavicleAng = info.defaultToNeutralClavicleAng
	local defaultLeftFootAngles = info.defaultLeftFootAngles
	local defaultRightFootAngles = info.defaultRightFootAngles
	local degToBendRightAmount = info.degToBendRightAmount
	local degToBendForwardAmount = info.degToBendForwardAmount
	-- Target poses
	local pelvisTargetPos, pelvisTargetAng = LocalToWorld(info.waistCalibrationPos, info.waistCalibrationAng, frame.waistPos, frame.waistAng)
	local headTargetPos, headTargetAng = LocalToWorld(info.headCalibrationPos, info.headCalibrationAng, frame.hmdPos, frame.hmdAng)
	local leftHandTargetPos, leftHandTargetAng = frame.lefthandPos, frame.lefthandAng
	local rightHandTargetPos, rightHandTargetAng = frame.righthandPos, frame.righthandAng
	local leftFootTargetPos, leftFootTargetAng = LocalToWorld(info.leftFootCalibrationPos, info.leftFootCalibrationAng, frame.leftfootPos, frame.leftfootAng)
	local rightFootTargetPos, rightFootTargetAng = LocalToWorld(info.rightFootCalibrationPos, info.rightFootCalibrationAng, frame.rightfootPos, frame.rightfootAng)
	-- Override pelvis
	boneinfo[boneids.pelvis].overridePos, boneinfo[boneids.pelvis].overrideAng = LocalToWorld(vrmod_fbt.zeroVec, Angle(0, 90, 90), pelvisTargetPos, pelvisTargetAng)
	-- Spine rotation
	local headVecRelative = WorldToLocal(headTargetPos, headTargetAng, pelvisTargetPos, pelvisTargetAng):GetNormalized()
	local bendForwardAmount = vrmod_fbt.GetSpineBend(degToBendForwardAmount, 90 - math.deg(math.acos(headVecRelative:Dot(Vector(1, 0, 0)))))
	local bendRightAmount = vrmod_fbt.GetSpineBend(degToBendRightAmount, 90 - math.deg(math.acos(headVecRelative:Dot(Vector(0, -1, 0)))))
	boneinfo[boneids.spine].offsetAng = Angle(-bendForwardAmount, bendRightAmount, 0)
	boneinfo[boneids.spine1].offsetAng = Angle(bendRightAmount, bendForwardAmount, 0)
	boneinfo[boneids.spine2].offsetAng = Angle(bendRightAmount, bendForwardAmount, 0)
	boneinfo[boneids.spine4].offsetAng = Angle(bendRightAmount, bendForwardAmount, 0)
	boneinfo[boneids.neck].offsetAng = Angle(bendRightAmount, bendForwardAmount, 0)
	-- Override hand angles
	boneinfo[boneids.leftHand].overrideAng = leftHandTargetAng
	boneinfo[boneids.rightHand].overrideAng = rightHandTargetAng + Angle(0, 0, 180)
	-- Override head angles
	_, boneinfo[boneids.head].overrideAng = LocalToWorld(vrmod_fbt.zeroVec, Angle(-80, 0, 90), vrmod_fbt.zeroVec, headTargetAng)
	-- Finger offsets
	for k, v in ipairs(fingerboneids) do
		if boneinfo[v] then boneinfo[v].offsetAng = LerpAngle(frame["finger" .. math.floor((k - 1) / 3 + 1)], g_VR.openHandAngles[k], g_VR.closedHandAngles[k]) end
	end

	local upperBodyAng
	for i = 0, boneCount - 1 do
		local bi = boneinfo[i]
		local parentInfo = boneinfo[bi.parent] or bi
		local wpos, wang = LocalToWorld(bi.relativePos, bi.relativeAng + bi.offsetAng, parentInfo.pos, parentInfo.ang)
		-- Left leg IK
		if i == boneids.leftThigh then vrmod_fbt.CalculateLegIK(boneinfo, boneids, upperLegLen, lowerLegLen, boneids.leftThigh, boneids.leftCalf, boneids.leftFoot, leftFootTargetPos, leftFootTargetAng, defaultLeftFootAngles, wpos, wang) end
		-- Right leg IK
		if i == boneids.rightThigh then vrmod_fbt.CalculateLegIK(boneinfo, boneids, upperLegLen, lowerLegLen, boneids.rightThigh, boneids.rightCalf, boneids.rightFoot, rightFootTargetPos, rightFootTargetAng, defaultRightFootAngles, wpos, wang) end
		-- Left clavicle
		if i == boneids.leftClavicle then
			local neutralClavicleAng = vrmod_fbt.CalculateClavicle(boneinfo, boneids.leftClavicle, defaultToNeutralClavicleAng, clavicleLen, leftHandTargetPos, wpos, wang, true)
			if boneids.leftClavicle < boneids.rightClavicle then _, upperBodyAng = LocalToWorld(vrmod_fbt.zeroVec, Angle(-90, 0, -90), vrmod_fbt.zeroVec, neutralClavicleAng) end
		end

		-- Right clavicle
		if i == boneids.rightClavicle then
			local neutralClavicleAng = vrmod_fbt.CalculateClavicle(boneinfo, boneids.rightClavicle, defaultToNeutralClavicleAng, clavicleLen, rightHandTargetPos, wpos, wang, false)
			if boneids.rightClavicle < boneids.leftClavicle then _, upperBodyAng = LocalToWorld(vrmod_fbt.zeroVec, Angle(90, 0, -90), vrmod_fbt.zeroVec, neutralClavicleAng) end
		end

		-- Left arm IK
		if i == boneids.leftUpperArm then vrmod_fbt.CalculateArmIK(boneinfo, boneids, upperArmLen, lowerArmLen, boneids.leftUpperArm, boneids.leftForearm, boneids.leftHand, boneids.leftWrist, boneids.leftUlna, leftHandTargetPos, leftHandTargetAng, upperBodyAng, vrmod_fbt.convarValues, true) end
		-- Right arm IK
		if i == boneids.rightUpperArm then vrmod_fbt.CalculateArmIK(boneinfo, boneids, upperArmLen, lowerArmLen, boneids.rightUpperArm, boneids.rightForearm, boneids.rightHand, boneids.rightWrist, boneids.rightUlna, rightHandTargetPos, rightHandTargetAng + Angle(0, 0, 180), upperBodyAng, vrmod_fbt.convarValues, false) end
		-- Apply overrides and build matrix
		wpos = bi.overridePos or wpos
		wang = bi.overrideAng or wang
		local mat = Matrix()
		mat:Translate(wpos)
		mat:Rotate(wang)
		if bi.overrideScale then
			mat:Scale(bi.overrideScale)
			bi.overrideScale = nil
		end

		bi.targetMatrix = mat
		bi.pos = wpos
		bi.ang = wang
	end
end

-- Track active calibration session
vrmod_fbt.activeCalibration = vrmod_fbt.activeCalibration or {}
function vrmod_fbt.Calibrate()
	local ply = LocalPlayer()
	-- Cleanup previous calibration if it exists
	if vrmod_fbt.activeCalibration.model then
		vrmod.logger.Info("Resetting previous FBT calibration...")
		vrmod_fbt.activeCalibration.model:Remove()
		ply.RenderOverride = nil
		hook.Remove("PostDrawTranslucentRenderables", "fbt_showtrackers")
		hook.Remove("VRMod_Input", "fbt_cal_input")
		vrmod_fbt.activeCalibration = {}
	end

	-- Create new calibration session
	local calibrationModel = ClientsideModel(ply.vrmod_pm or ply:GetModel())
	vrmod_fbt.activeCalibration.model = calibrationModel
	ply.RenderOverride = function() end
	calibrationModel:SetPos(Vector(g_VR.tracking.hmd.pos.x, g_VR.tracking.hmd.pos.y, ply:GetPos().z))
	calibrationModel:SetAngles(Angle(0, g_VR.tracking.hmd.ang.yaw, 0))
	-- Show tracker boxes
	hook.Add("PostDrawTranslucentRenderables", "fbt_showtrackers", function(depth, sky)
		if depth or sky or not g_VR.tracking.pose_waist or not g_VR.tracking.pose_leftfoot or not g_VR.tracking.pose_rightfoot then return end
		render.SetColorMaterial()
		render.DrawBox(g_VR.tracking.pose_waist.pos, g_VR.tracking.pose_waist.ang, Vector(-1, -1, -1), Vector(1, 1, 1))
		render.DrawBox(g_VR.tracking.pose_leftfoot.pos, g_VR.tracking.pose_leftfoot.ang, Vector(-1, -1, -1), Vector(1, 1, 1))
		render.DrawBox(g_VR.tracking.pose_rightfoot.pos, g_VR.tracking.pose_rightfoot.ang, Vector(-1, -1, -1), Vector(1, 1, 1))
	end)

	-- Input hook for finalizing calibration
	hook.Add("VRMod_Input", "fbt_cal_input", function(action, pressed)
		if action ~= "boolean_reload" or not pressed then return end
		if vrmod_fbt.Init(ply) == false then return end
		local boneids = vrmod_fbt.characterInfo[ply:SteamID()].boneids
		calibrationModel:SetupBones()
		net.Start("vrmod_fbt_cal")
		net.WriteBool(false)
		local function sendBone(bone, tracker)
			local pos, ang = WorldToLocal(calibrationModel:GetBoneMatrix(bone):GetTranslation(), calibrationModel:GetAngles(), tracker.pos, tracker.ang)
			net.WriteVector(pos)
			net.WriteAngle(ang)
		end

		sendBone(boneids.head, g_VR.tracking.hmd)
		sendBone(boneids.pelvis, g_VR.tracking.pose_waist)
		sendBone(boneids.leftFoot, g_VR.tracking.pose_leftfoot)
		sendBone(boneids.rightFoot, g_VR.tracking.pose_rightfoot)
		net.SendToServer()
		-- Cleanup calibration session
		calibrationModel:Remove()
		ply.RenderOverride = nil
		hook.Remove("PostDrawTranslucentRenderables", "fbt_showtrackers")
		hook.Remove("VRMod_Input", "fbt_cal_input")
		vrmod_fbt.activeCalibration = {}
		vrmod.logger.Info("FBT calibration completed")
	end)
end

-- Starts FBT for a player
function vrmod_fbt.Start(ply)
	local steamid = ply:SteamID()
	if not g_VR.net[steamid] or vrmod_fbt.Init(ply) == false then return end
	local info = vrmod_fbt.characterInfo[steamid]
	if not info.headCalibrationPos then
		vrmod.logger.Info("FBT Start: no calibration data, requesting from server...")
		net.Start("vrmod_fbt_cal")
		net.WriteBool(true)
		net.WriteEntity(ply)
		net.SendToServer()
		return
	end

	g_VR.fbtActive = g_VR.fbtActive or {}
	g_VR.fbtActive[steamid] = true
	if info.fbtBoneCallback then ply:RemoveCallback("BuildBonePositions", info.fbtBoneCallback) end
	info.fbtBoneCallback = ply:AddCallback("BuildBonePositions", function(ent, numbones)
		vrmod_fbt.CalculateBonePositions(ply)
		local boneinfo = info.boneinfo
		for i = 0, info.boneCount - 1 do
			if ply:GetBoneMatrix(i) then ply:SetBoneMatrix(i, boneinfo[i].targetMatrix) end
		end
	end)

	if ply == LocalPlayer() then
		hook.Add("PrePlayerDraw", "fbt_hide_head", function(player)
			if player ~= ply then return end
			local eyePos = EyePos()
			ply:ManipulateBoneScale(info.boneids.head, (eyePos == g_VR.eyePosLeft or eyePos == g_VR.eyePosRight) and ply:GetViewEntity() == ply and vrmod_fbt.zeroVec or Vector(1, 1, 1))
		end)
	end

	vrmod.logger.Info("FBT started for %s", steamid)
end

-- Stops FBT for a player
function vrmod_fbt.Stop(ply)
	local steamid = ply:SteamID()
	if not g_VR.fbtActive or not g_VR.fbtActive[steamid] then return end
	local info = vrmod_fbt.characterInfo[steamid]
	if info and info.fbtBoneCallback then
		ply:RemoveCallback("BuildBonePositions", info.fbtBoneCallback)
		info.fbtBoneCallback = nil
	end

	if ply == LocalPlayer() then
		hook.Remove("PrePlayerDraw", "fbt_hide_head")
		if info then ply:ManipulateBoneScale(info.boneids.head, Vector(1, 1, 1)) end
	end

	g_VR.fbtActive[steamid] = nil
	vrmod.logger.Info("FBT stopped for %s", steamid)
end

hook.Add("VRMod_OpenQuickMenu", "fbt_quickmenu", function()
	vrmod.RemoveInGameMenuItem("Calibrate Full-body Tracking")
	vrmod.RemoveInGameMenuItem("Disable Full-body Tracking")
	if not g_VR.sixPoints then return end
	local steamid = LocalPlayer():SteamID()
	local active = g_VR.fbtActive and g_VR.fbtActive[steamid] or false
	if active then
		vrmod.AddInGameMenuItem("Disable Full-body Tracking", 5, 0, function() vrmod_fbt.Stop(LocalPlayer()) end)
	else
		vrmod.AddInGameMenuItem("Calibrate Full-body Tracking", 5, 0, vrmod_fbt.Calibrate, false, "press reload when done")
	end
end)

-- Net receivers
net.Receive("vrmod_fbt_cal", function()
	local ply = net.ReadEntity()
	local steamid = ply:SteamID()
	local info = vrmod_fbt.characterInfo[steamid] or {}
	vrmod_fbt.characterInfo[steamid] = info
	info.headCalibrationPos, info.headCalibrationAng = net.ReadVector(), net.ReadAngle()
	info.waistCalibrationPos, info.waistCalibrationAng = net.ReadVector(), net.ReadAngle()
	info.leftFootCalibrationPos, info.leftFootCalibrationAng = net.ReadVector(), net.ReadAngle()
	info.rightFootCalibrationPos, info.rightFootCalibrationAng = net.ReadVector(), net.ReadAngle()
	vrmod_fbt.Start(ply)
end)

net.Receive("vrmod_fbt_toggle", function()
	local ply = net.ReadEntity()
	if not IsValid(ply) then return end
	if net.ReadBool() then
		vrmod_fbt.Start(ply)
	else
		vrmod_fbt.Stop(ply)
	end
end)

-- VR exit cleanup
hook.Add("VRMod_Exit", "fbt_cleanup", function(ply, steamid)
	vrmod_fbt.Stop(ply)
	if ply == LocalPlayer() then
		hook.Remove("VRMod_Input", "fbt_walk_toggle")
		hook.Remove("VRMod_EnterVehicle", "fbt_enter_vehicle")
		hook.Remove("VRMod_ExitVehicle", "fbt_exit_vehicle")
	end
end)

vrmod.logger.Info("Full-body tracking module loaded")