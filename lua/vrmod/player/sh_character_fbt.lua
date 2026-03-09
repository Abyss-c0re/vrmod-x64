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

-------------------------------------------------------------------------------------
-- CLIENT
-------------------------------------------------------------------------------------
local characterInfo = {}
local _, convarValues = vrmod.GetConvars()
local zeroVec, zeroAng = Vector(), Angle()
-------------------------------------------------------------------------------------
-- INIT: build full skeleton info for a player model
-------------------------------------------------------------------------------------
local function Init(ply)
	local steamid = ply:SteamID()
	local info = characterInfo[steamid] or {}
	characterInfo[steamid] = info
	local pmname = ply.vrmod_pm or ply:GetModel()
	if info.modelName == pmname then return end
	local tmpPlayerModel = ClientsideModel(pmname)
	tmpPlayerModel:SetupBones()
	local boneids = {
		leftClavicle = tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Clavicle") or -1,
		leftUpperArm = tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_UpperArm") or -1,
		leftForearm = tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Forearm") or -1,
		leftHand = tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Hand") or -1,
		leftWrist = tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Wrist") or -1,
		leftUlna = tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Ulna") or -1,
		leftCalf = tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Calf") or -1,
		leftThigh = tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Thigh") or -1,
		leftFoot = tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Foot") or -1,
		rightClavicle = tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Clavicle") or -1,
		rightUpperArm = tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_UpperArm") or -1,
		rightForearm = tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Forearm") or -1,
		rightHand = tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Hand") or -1,
		rightWrist = tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Wrist") or -1,
		rightUlna = tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Ulna") or -1,
		rightCalf = tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Calf") or -1,
		rightThigh = tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Thigh") or -1,
		rightFoot = tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Foot") or -1,
		head = tmpPlayerModel:LookupBone("ValveBiped.Bip01_Head1") or -1,
		spine = tmpPlayerModel:LookupBone("ValveBiped.Bip01_Spine") or -1,
		spine1 = tmpPlayerModel:LookupBone("ValveBiped.Bip01_Spine1") or -1,
		spine2 = tmpPlayerModel:LookupBone("ValveBiped.Bip01_Spine2") or -1,
		spine4 = tmpPlayerModel:LookupBone("ValveBiped.Bip01_Spine4") or -1,
		neck = tmpPlayerModel:LookupBone("ValveBiped.Bip01_Neck1") or -1,
		pelvis = tmpPlayerModel:LookupBone("ValveBiped.Bip01_Pelvis") or -1,
	}

	info.boneids = boneids
	local fingerboneids = {tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Finger0") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Finger01") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Finger02") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Finger1") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Finger11") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Finger12") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Finger2") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Finger21") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Finger22") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Finger3") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Finger31") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Finger32") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Finger4") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Finger41") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_L_Finger42") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Finger0") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Finger01") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Finger02") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Finger1") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Finger11") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Finger12") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Finger2") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Finger21") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Finger22") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Finger3") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Finger31") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Finger32") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Finger4") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Finger41") or -1, tmpPlayerModel:LookupBone("ValveBiped.Bip01_R_Finger42") or -1,}
	info.fingerboneids = fingerboneids
	-- Validate required bones
	g_VR.errorText = ply == LocalPlayer() and "" or g_VR.errorText
	for k, v in pairs(boneids) do
		if v == -1 and k ~= "leftWrist" and k ~= "rightWrist" and k ~= "leftUlna" and k ~= "rightUlna" then
			g_VR.errorText = ply == LocalPlayer() and "Missing bone: " .. k or g_VR.errorText
			tmpPlayerModel:Remove()
			characterInfo[steamid] = nil
			vrmod.logger.Err("FBT Init failed for %s - missing bone: %s", steamid, k)
			return false
		end
	end

	info.modelName = pmname
	-- Build full bone info table (all bones, indexed by bone ID)
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
			offsetAng = zeroAng,
			pos = zeroVec,
			ang = zeroAng,
			targetMatrix = mtx
		}
	end

	-- Measure limb lengths
	info.upperLegLen = (tmpPlayerModel:GetBoneMatrix(boneids.leftCalf):GetTranslation() - tmpPlayerModel:GetBoneMatrix(boneids.leftThigh):GetTranslation()):Length()
	info.lowerLegLen = (tmpPlayerModel:GetBoneMatrix(boneids.leftFoot):GetTranslation() - tmpPlayerModel:GetBoneMatrix(boneids.leftCalf):GetTranslation()):Length()
	info.clavicleLen = (tmpPlayerModel:GetBoneMatrix(boneids.leftUpperArm):GetTranslation() - tmpPlayerModel:GetBoneMatrix(boneids.leftClavicle):GetTranslation()):Length()
	info.upperArmLen = (tmpPlayerModel:GetBoneMatrix(boneids.leftForearm):GetTranslation() - tmpPlayerModel:GetBoneMatrix(boneids.leftUpperArm):GetTranslation()):Length()
	info.lowerArmLen = (tmpPlayerModel:GetBoneMatrix(boneids.leftHand):GetTranslation() - tmpPlayerModel:GetBoneMatrix(boneids.leftForearm):GetTranslation()):Length()
	_, info.defaultToNeutralClavicleAng = WorldToLocal(zeroVec, Angle(0, 90, 90), zeroVec, tmpPlayerModel:GetBoneMatrix(boneids.leftClavicle):GetAngles())
	info.defaultLeftFootAngles = tmpPlayerModel:GetBoneMatrix(boneids.leftFoot):GetAngles()
	info.defaultRightFootAngles = tmpPlayerModel:GetBoneMatrix(boneids.rightFoot):GetAngles()
	-- Build spine bend lookup tables
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
			for j = 1, #input do
				if i >= input[j][2] and i <= input[j + 1][2] then
					local prevAmt, prevDeg, nextAmt, nextDeg = input[j][1], input[j][2], input[j + 1][1], input[j + 1][2]
					output[#output + 1] = prevAmt + (nextAmt - prevAmt) * (i - prevDeg) / (nextDeg - prevDeg)
					break
				end
			end
		end
	end

	tmpPlayerModel:Remove()
	vrmod.logger.Info("FBT Init succeeded for %s (model: %s)", steamid, pmname)
end

-------------------------------------------------------------------------------------
-- SPINE BEND HELPER
-------------------------------------------------------------------------------------
local function GetSpineBend(tab, val)
	local prev = tab[math.floor(val + 91)]
	return prev + (tab[math.ceil(val + 91)] - prev) * val % 1
end

-------------------------------------------------------------------------------------
-- CALCULATE ALL BONE POSITIONS (full-body IK)
-------------------------------------------------------------------------------------
local function CalculateBonePositions(ply)
	local steamid = ply:SteamID()
	local info = characterInfo[steamid]
	local frame = g_VR.net[steamid].lerpedFrame
	if info.frameNumber == FrameNumber() or not frame then return end
	info.frameNumber = FrameNumber()
	-- Get target poses from calibration + tracked frame data
	local pelvisTargetPos, pelvisTargetAng = LocalToWorld(info.waistCalibrationPos, info.waistCalibrationAng, frame.waistPos, frame.waistAng)
	local headTargetPos, headTargetAng = LocalToWorld(info.headCalibrationPos, info.headCalibrationAng, frame.hmdPos, frame.hmdAng)
	local leftHandTargetPos, leftHandTargetAng = frame.lefthandPos, frame.lefthandAng
	local rightHandTargetPos, rightHandTargetAng = frame.righthandPos, frame.righthandAng
	local leftFootTargetPos, leftFootTargetAng = LocalToWorld(info.leftFootCalibrationPos, info.leftFootCalibrationAng, frame.leftfootPos, frame.leftfootAng)
	local rightFootTargetPos, rightFootTargetAng = LocalToWorld(info.rightFootCalibrationPos, info.rightFootCalibrationAng, frame.rightfootPos, frame.rightfootAng)
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
	local boneinfo = info.boneinfo
	local boneCount = info.boneCount
	local boneids = info.boneids
	local fingerboneids = info.fingerboneids
	-- Override pelvis pose
	boneinfo[boneids.pelvis].overridePos, boneinfo[boneids.pelvis].overrideAng = LocalToWorld(zeroVec, Angle(0, 90, 90), pelvisTargetPos, pelvisTargetAng)
	-- Spine rotation
	local headVecRelative = WorldToLocal(headTargetPos, headTargetAng, pelvisTargetPos, pelvisTargetAng):GetNormalized()
	local bendForwardAmount = GetSpineBend(degToBendForwardAmount, 90 - math.deg(math.acos(headVecRelative:Dot(Vector(1, 0, 0)))))
	local bendRightAmount = GetSpineBend(degToBendRightAmount, 90 - math.deg(math.acos(headVecRelative:Dot(Vector(0, -1, 0)))))
	boneinfo[boneids.spine].offsetAng = Angle(-bendForwardAmount, bendRightAmount, 0)
	boneinfo[boneids.spine1].offsetAng = Angle(bendRightAmount, bendForwardAmount, 0)
	boneinfo[boneids.spine2].offsetAng = Angle(bendRightAmount, bendForwardAmount, 0)
	boneinfo[boneids.spine4].offsetAng = Angle(bendRightAmount, bendForwardAmount, 0)
	boneinfo[boneids.neck].offsetAng = Angle(bendRightAmount, bendForwardAmount, 0)
	-- Override foot angles
	_, boneinfo[boneids.leftFoot].overrideAng = LocalToWorld(zeroVec, defaultLeftFootAngles, zeroVec, leftFootTargetAng)
	_, boneinfo[boneids.rightFoot].overrideAng = LocalToWorld(zeroVec, defaultRightFootAngles, zeroVec, rightFootTargetAng)
	-- Override hand angles
	boneinfo[boneids.leftHand].overrideAng = leftHandTargetAng
	boneinfo[boneids.rightHand].overrideAng = rightHandTargetAng + Angle(0, 0, 180)
	-- Override head angles
	_, boneinfo[boneids.head].overrideAng = LocalToWorld(zeroVec, Angle(-80, 0, 90), zeroVec, headTargetAng)
	-- Finger offset angles
	for k, v in pairs(fingerboneids) do
		if not boneinfo[v] then continue end
		boneinfo[v].offsetAng = LerpAngle(frame["finger" .. math.floor((k - 1) / 3 + 1)], g_VR.openHandAngles[k], g_VR.closedHandAngles[k])
	end

	-- Calculate target matrices for all bones
	local upperBodyAng
	for i = 0, boneCount - 1 do
		local bi = boneinfo[i]
		local parentInfo = boneinfo[bi.parent] or bi
		local wpos, wang = LocalToWorld(bi.relativePos, bi.relativeAng + bi.offsetAng, parentInfo.pos, parentInfo.ang)
		---------- LEFT LEG IK ----------
		if i == boneids.leftThigh then
			local targetVec = (leftFootTargetPos - wpos):GetNormalized()
			local targetVecLen = (leftFootTargetPos - wpos):Length()
			local newAng = targetVec:Angle()
			-- Rotation
			local mtx = Matrix()
			mtx:SetForward(targetVec)
			mtx:SetUp(targetVec:Cross(leftFootTargetAng:Right()))
			mtx:SetRight(targetVec:Cross(mtx:GetUp()))
			local _, targetAngRelative = WorldToLocal(zeroVec, mtx:GetAngles(), zeroVec, newAng)
			newAng:RotateAroundAxis(targetVec, targetAngRelative.roll + 90)
			-- Contraction
			local a1 = math.deg(math.acos((upperLegLen * upperLegLen + targetVecLen * targetVecLen - lowerLegLen * lowerLegLen) / (2 * upperLegLen * targetVecLen)))
			if a1 == a1 then newAng:RotateAroundAxis(newAng:Up(), -a1) end
			bi.overrideAng = newAng
			-- Calf
			local calfAng = Angle(newAng.pitch, newAng.yaw, newAng.roll)
			local a23 = 180 - a1 - math.deg(math.acos((lowerLegLen * lowerLegLen + targetVecLen * targetVecLen - upperLegLen * upperLegLen) / (2 * lowerLegLen * targetVecLen)))
			if a23 == a23 then calfAng:RotateAroundAxis(calfAng:Up(), 180 - a23) end
			boneinfo[boneids.leftCalf].overrideAng = calfAng
		end

		---------- RIGHT LEG IK ----------
		if i == boneids.rightThigh then
			local targetVec = (rightFootTargetPos - wpos):GetNormalized()
			local targetVecLen = (rightFootTargetPos - wpos):Length()
			local newAng = targetVec:Angle()
			-- Rotation
			local mtx = Matrix()
			mtx:SetForward(targetVec)
			mtx:SetUp(targetVec:Cross(rightFootTargetAng:Right()))
			mtx:SetRight(targetVec:Cross(mtx:GetUp()))
			local _, targetAngRelative = WorldToLocal(zeroVec, mtx:GetAngles(), zeroVec, newAng)
			newAng:RotateAroundAxis(targetVec, targetAngRelative.roll + 90)
			-- Contraction
			local a1 = math.deg(math.acos((upperLegLen * upperLegLen + targetVecLen * targetVecLen - lowerLegLen * lowerLegLen) / (2 * upperLegLen * targetVecLen)))
			if a1 == a1 then newAng:RotateAroundAxis(newAng:Up(), -a1) end
			bi.overrideAng = newAng
			-- Calf
			local calfAng = Angle(newAng.pitch, newAng.yaw, newAng.roll)
			local a23 = 180 - a1 - math.deg(math.acos((lowerLegLen * lowerLegLen + targetVecLen * targetVecLen - upperLegLen * upperLegLen) / (2 * lowerLegLen * targetVecLen)))
			if a23 == a23 then calfAng:RotateAroundAxis(calfAng:Up(), 180 - a23) end
			boneinfo[boneids.rightCalf].overrideAng = calfAng
		end

		---------- LEFT CLAVICLE ----------
		if i == boneids.leftClavicle then
			local _, neutralClavicleAng = LocalToWorld(zeroVec, defaultToNeutralClavicleAng, wpos, wang)
			local neutralShoulderPos = wpos + neutralClavicleAng:Forward() * clavicleLen
			local targetShoulderPos = neutralShoulderPos + (leftHandTargetPos - neutralShoulderPos) * 0.15
			local targetShoulderPosRelative = WorldToLocal(targetShoulderPos, zeroAng, wpos, neutralClavicleAng)
			local _, newClavicleAng = LocalToWorld(zeroVec, targetShoulderPosRelative:Angle(), zeroVec, neutralClavicleAng)
			bi.overrideAng = newClavicleAng
			if boneids.leftClavicle < boneids.rightClavicle then _, upperBodyAng = LocalToWorld(zeroVec, Angle(-90, 0, -90), zeroVec, neutralClavicleAng) end
		end

		---------- RIGHT CLAVICLE ----------
		if i == boneids.rightClavicle then
			local _, neutralClavicleAng = LocalToWorld(zeroVec, defaultToNeutralClavicleAng, wpos, wang)
			local neutralShoulderPos = wpos + neutralClavicleAng:Forward() * clavicleLen
			local targetShoulderPos = neutralShoulderPos + (rightHandTargetPos - neutralShoulderPos) * 0.15
			local targetShoulderPosRelative = WorldToLocal(targetShoulderPos, zeroAng, wpos, neutralClavicleAng)
			local _, newClavicleAng = LocalToWorld(zeroVec, targetShoulderPosRelative:Angle(), zeroVec, neutralClavicleAng)
			bi.overrideAng = newClavicleAng
			if boneids.rightClavicle < boneids.leftClavicle then _, upperBodyAng = LocalToWorld(zeroVec, Angle(90, 0, -90), zeroVec, neutralClavicleAng) end
		end

		---------- LEFT ARM IK ----------
		if i == boneids.leftUpperArm then
			-- Upper arm direction
			local targetPosRelative = WorldToLocal(leftHandTargetPos, zeroAng, wpos, upperBodyAng)
			local targetPosRelativeAng = targetPosRelative:Angle()
			local _, newUpperArmAng = LocalToWorld(zeroVec, targetPosRelativeAng, zeroVec, upperBodyAng)
			-- Arm roll
			local _, tmp1 = LocalToWorld(zeroVec, Angle(targetPosRelativeAng.pitch, 0, -90 + 30 + math.max((targetPosRelative.z + 20) * 1.5, 0)), zeroVec, upperBodyAng)
			local _, tmp2 = WorldToLocal(zeroVec, tmp1, zeroVec, newUpperArmAng)
			newUpperArmAng:RotateAroundAxis(newUpperArmAng:Forward(), tmp2.roll)
			-- Contraction (with arm stretching support)
			local targetVecLen = (leftHandTargetPos - wpos):Length()
			local totalArmLen = upperArmLen + lowerArmLen
			local armStretchScale = 1
			local effectiveUpperArmLen = upperArmLen
			local effectiveLowerArmLen = lowerArmLen
			if convarValues.armStretcher and targetVecLen > totalArmLen * 0.98 then
				armStretchScale = targetVecLen / (totalArmLen * 0.98)
				effectiveUpperArmLen = upperArmLen * armStretchScale
				effectiveLowerArmLen = lowerArmLen * armStretchScale
				boneinfo[boneids.leftHand].overridePos = leftHandTargetPos
			else
				boneinfo[boneids.leftHand].overridePos = nil
			end

			local a1 = math.deg(math.acos((effectiveUpperArmLen * effectiveUpperArmLen + targetVecLen * targetVecLen - effectiveLowerArmLen * effectiveLowerArmLen) / (2 * effectiveUpperArmLen * targetVecLen)))
			if a1 == a1 then newUpperArmAng:RotateAroundAxis(newUpperArmAng:Up(), a1) end
			bi.overrideAng = newUpperArmAng
			bi.overrideScale = armStretchScale ~= 1 and Vector(armStretchScale, 1, 1) or nil
			-- Forearm
			local newForearmAng = Angle(newUpperArmAng.pitch, newUpperArmAng.yaw, newUpperArmAng.roll)
			local a23 = 180 - a1 - math.deg(math.acos((effectiveLowerArmLen * effectiveLowerArmLen + targetVecLen * targetVecLen - effectiveUpperArmLen * effectiveUpperArmLen) / (2 * effectiveLowerArmLen * targetVecLen)))
			if a23 == a23 then newForearmAng:RotateAroundAxis(newForearmAng:Up(), 180 + a23) end
			boneinfo[boneids.leftForearm].overrideAng = newForearmAng
			boneinfo[boneids.leftForearm].overrideScale = armStretchScale ~= 1 and Vector(armStretchScale, 1, 1) or nil
			-- Wrist
			local _, handAngRelativeToForearm = WorldToLocal(zeroVec, Angle(leftHandTargetAng.pitch, leftHandTargetAng.yaw, leftHandTargetAng.roll - 90), zeroVec, newForearmAng)
			local newWristAng = Angle(newForearmAng.pitch, newForearmAng.yaw, newForearmAng.roll)
			newWristAng:RotateAroundAxis(newWristAng:Forward(), handAngRelativeToForearm.roll)
			if boneids.leftWrist ~= -1 then boneinfo[boneids.leftWrist].overrideAng = newWristAng end
			-- Ulna
			if boneids.leftUlna ~= -1 then boneinfo[boneids.leftUlna].overrideAng = LerpAngle(0.5, newForearmAng, newWristAng) end
		end

		---------- RIGHT ARM IK ----------
		if i == boneids.rightUpperArm then
			-- Upper arm direction
			local targetPosRelative = WorldToLocal(rightHandTargetPos, zeroAng, wpos, upperBodyAng)
			local targetPosRelativeAng = targetPosRelative:Angle()
			local _, newUpperArmAng = LocalToWorld(zeroVec, targetPosRelativeAng, zeroVec, upperBodyAng)
			-- Arm roll
			local _, tmp1 = LocalToWorld(zeroVec, Angle(targetPosRelativeAng.pitch, 0, 90 - 30 - math.max((targetPosRelative.z + 20) * 1.5, 0)), zeroVec, upperBodyAng)
			local _, tmp2 = WorldToLocal(zeroVec, tmp1, zeroVec, newUpperArmAng)
			newUpperArmAng:RotateAroundAxis(newUpperArmAng:Forward(), 180 + tmp2.roll)
			-- Contraction (with arm stretching support)
			local targetVecLen = (rightHandTargetPos - wpos):Length()
			local totalArmLen = upperArmLen + lowerArmLen
			local armStretchScale = 1
			local effectiveUpperArmLen = upperArmLen
			local effectiveLowerArmLen = lowerArmLen
			if convarValues.armStretcher and targetVecLen > totalArmLen * 0.98 then
				armStretchScale = targetVecLen / (totalArmLen * 0.98)
				effectiveUpperArmLen = upperArmLen * armStretchScale
				effectiveLowerArmLen = lowerArmLen * armStretchScale
				boneinfo[boneids.rightHand].overridePos = rightHandTargetPos
			else
				boneinfo[boneids.rightHand].overridePos = nil
			end

			local a1 = math.deg(math.acos((effectiveUpperArmLen * effectiveUpperArmLen + targetVecLen * targetVecLen - effectiveLowerArmLen * effectiveLowerArmLen) / (2 * effectiveUpperArmLen * targetVecLen)))
			if a1 == a1 then newUpperArmAng:RotateAroundAxis(newUpperArmAng:Up(), a1) end
			bi.overrideAng = newUpperArmAng
			bi.overrideScale = armStretchScale ~= 1 and Vector(armStretchScale, 1, 1) or nil
			-- Forearm
			local newForearmAng = Angle(newUpperArmAng.pitch, newUpperArmAng.yaw, newUpperArmAng.roll)
			local a23 = 180 - a1 - math.deg(math.acos((effectiveLowerArmLen * effectiveLowerArmLen + targetVecLen * targetVecLen - effectiveUpperArmLen * effectiveUpperArmLen) / (2 * effectiveLowerArmLen * targetVecLen)))
			if a23 == a23 then newForearmAng:RotateAroundAxis(newForearmAng:Up(), 180 + a23) end
			boneinfo[boneids.rightForearm].overrideAng = newForearmAng
			boneinfo[boneids.rightForearm].overrideScale = armStretchScale ~= 1 and Vector(armStretchScale, 1, 1) or nil
			-- Wrist
			local _, handAngRelativeToForearm = WorldToLocal(zeroVec, Angle(rightHandTargetAng.pitch, rightHandTargetAng.yaw, rightHandTargetAng.roll - 90), zeroVec, newForearmAng)
			local newWristAng = Angle(newForearmAng.pitch, newForearmAng.yaw, newForearmAng.roll)
			newWristAng:RotateAroundAxis(newWristAng:Forward(), handAngRelativeToForearm.roll)
			if boneids.rightWrist ~= -1 then boneinfo[boneids.rightWrist].overrideAng = newWristAng end
			-- Ulna
			if boneids.rightUlna ~= -1 then boneinfo[boneids.rightUlna].overrideAng = LerpAngle(0.5, newForearmAng, newWristAng) end
		end

		---------- APPLY OVERRIDES & BUILD MATRIX ----------
		wpos = bi.overridePos or wpos
		wang = bi.overrideAng or wang
		local mat = Matrix()
		mat:Translate(wpos)
		mat:Rotate(wang)
		-- Apply arm stretch scale if set
		if bi.overrideScale then
			mat:Scale(bi.overrideScale)
			bi.overrideScale = nil
		end

		bi.targetMatrix = mat
		bi.pos = wpos
		bi.ang = wang
	end
end

-------------------------------------------------------------------------------------
-- CALIBRATION
-------------------------------------------------------------------------------------
local function Calibrate()
	local ply = LocalPlayer()
	ply.RenderOverride = function() end
	local calibrationModel = ClientsideModel(ply.vrmod_pm or ply:GetModel())
	calibrationModel:SetPos(Vector(g_VR.tracking.hmd.pos.x, g_VR.tracking.hmd.pos.y, ply:GetPos().z))
	calibrationModel:SetAngles(Angle(0, g_VR.tracking.hmd.ang.yaw, 0))
	hook.Add("PostDrawTranslucentRenderables", "fbt_test_showtrackers", function(depth, sky)
		if depth or sky then return end
		if not g_VR.tracking.pose_waist or not g_VR.tracking.pose_leftfoot or not g_VR.tracking.pose_rightfoot then return end
		render.SetColorMaterial()
		render.DrawBox(g_VR.tracking.pose_waist.pos, g_VR.tracking.pose_waist.ang, Vector(-1, -1, -1), Vector(1, 1, 1))
		render.DrawBox(g_VR.tracking.pose_leftfoot.pos, g_VR.tracking.pose_leftfoot.ang, Vector(-1, -1, -1), Vector(1, 1, 1))
		render.DrawBox(g_VR.tracking.pose_rightfoot.pos, g_VR.tracking.pose_rightfoot.ang, Vector(-1, -1, -1), Vector(1, 1, 1))
	end)

	hook.Add("VRMod_Input", "fbt_test_input", function(action, pressed)
		if action == "boolean_reload" and pressed then
			if Init(ply) == false then return end
			local boneids = characterInfo[ply:SteamID()].boneids
			calibrationModel:SetupBones()
			net.Start("vrmod_fbt_cal")
			net.WriteBool(false)
			local pos, ang = WorldToLocal(calibrationModel:GetBoneMatrix(boneids.head):GetTranslation(), calibrationModel:GetAngles(), g_VR.tracking.hmd.pos, g_VR.tracking.hmd.ang)
			net.WriteVector(pos)
			net.WriteAngle(ang)
			local pos, ang = WorldToLocal(calibrationModel:GetBoneMatrix(boneids.pelvis):GetTranslation(), calibrationModel:GetAngles(), g_VR.tracking.pose_waist.pos, g_VR.tracking.pose_waist.ang)
			net.WriteVector(pos)
			net.WriteAngle(ang)
			local pos, ang = WorldToLocal(calibrationModel:GetBoneMatrix(boneids.leftFoot):GetTranslation(), calibrationModel:GetAngles(), g_VR.tracking.pose_leftfoot.pos, g_VR.tracking.pose_leftfoot.ang)
			net.WriteVector(pos)
			net.WriteAngle(ang)
			local pos, ang = WorldToLocal(calibrationModel:GetBoneMatrix(boneids.rightFoot):GetTranslation(), calibrationModel:GetAngles(), g_VR.tracking.pose_rightfoot.pos, g_VR.tracking.pose_rightfoot.ang)
			net.WriteVector(pos)
			net.WriteAngle(ang)
			net.SendToServer()
			calibrationModel:Remove()
			ply.RenderOverride = nil
			hook.Remove("PostDrawTranslucentRenderables", "fbt_test_showtrackers")
			hook.Remove("VRMod_Input", "fbt_test_input")
			hook.Add("VRMod_Input", "fbt_walk", function(action, pressed)
				if action == "boolean_walk" and not ply:InVehicle() then
					-- When animations are disabled (characterIK == false), stay in FBT mode
					if not convarValues.characterIK then return end
					net.Start("vrmod_fbt_toggle")
					net.WriteBool(not pressed)
					net.SendToServer()
				end
			end)

			hook.Add("VRMod_EnterVehicle", "fbt_entervehicle", function()
				net.Start("vrmod_fbt_toggle")
				net.WriteBool(false)
				net.SendToServer()
			end)

			hook.Add("VRMod_ExitVehicle", "fbt_exitvehicle", function()
				net.Start("vrmod_fbt_toggle")
				net.WriteBool(true)
				net.SendToServer()
			end)

			vrmod.logger.Info("FBT calibration completed")
		end
	end)
end

-------------------------------------------------------------------------------------
-- START / STOP FBT for a player
-- Sets g_VR.fbtActive[steamid] so cl_character.lua skips its bone overrides
-- while keeping its animation hooks (CalcMainActivity, render pos, etc.) alive.
-- Reads convarValues.characterIK to respect the "Disable Animations" toggle.
-------------------------------------------------------------------------------------
local function Start(ply)
	if not g_VR.net[ply:SteamID()] or Init(ply) == false then return end
	local steamid = ply:SteamID()
	local info = characterInfo[steamid]
	if not info.headCalibrationPos then
		vrmod.logger.Info("FBT Start: no calibration data, requesting from server...")
		net.Start("vrmod_fbt_cal")
		net.WriteBool(true)
		net.WriteEntity(ply)
		net.SendToServer()
		return
	end

	-- Tell the standard character system to skip its bone overrides
	g_VR.fbtActive = g_VR.fbtActive or {}
	g_VR.fbtActive[steamid] = true
	-- Add FBT bone callback (runs alongside the standard system's callback,
	-- but the standard one early-returns when fbtActive is set)
	if info.fbtBoneCallback then ply:RemoveCallback("BuildBonePositions", info.fbtBoneCallback) end
	local boneinfo, boneCount = info.boneinfo, info.boneCount
	info.fbtBoneCallback = ply:AddCallback("BuildBonePositions", function(ent, numbones)
		CalculateBonePositions(ply)
		for i = 0, boneCount - 1 do
			if ply:GetBoneMatrix(i) then ply:SetBoneMatrix(i, boneinfo[i].targetMatrix) end
		end
	end)

	-- Hide head in first person
	if ply == LocalPlayer() then
		hook.Add("PrePlayerDraw", "fbt_preplayerdraw", function(player)
			if player ~= ply then return end
			local eyePos = EyePos()
			ply:ManipulateBoneScale(info.boneids.head, (eyePos == g_VR.eyePosLeft or eyePos == g_VR.eyePosRight) and ply:GetViewEntity() == ply and zeroVec or Vector(1, 1, 1))
		end)
	end

	vrmod.logger.Info("FBT started for %s", steamid)
end

local function Stop(ply)
	if not ply then return end
	local steamid = ply:SteamID()
	if not g_VR.fbtActive or not g_VR.fbtActive[steamid] then return end
	local info = characterInfo[steamid]
	if info and info.fbtBoneCallback then
		ply:RemoveCallback("BuildBonePositions", info.fbtBoneCallback)
		info.fbtBoneCallback = nil
	end

	if ply == LocalPlayer() then
		hook.Remove("PrePlayerDraw", "fbt_preplayerdraw")
		if info then ply:ManipulateBoneScale(info.boneids.head, Vector(1, 1, 1)) end
	end

	-- Let the standard character system resume its bone overrides
	g_VR.fbtActive[steamid] = nil
	vrmod.logger.Info("FBT stopped for %s", steamid)
end

-------------------------------------------------------------------------------------
-- QUICK MENU INTEGRATION
-------------------------------------------------------------------------------------
hook.Add("VRMod_OpenQuickMenu", "fbtcal", function()
	vrmod.RemoveInGameMenuItem("Calibrate Full-body Tracking")
	if g_VR.sixPoints then vrmod.AddInGameMenuItem("Calibrate Full-body Tracking", 5, 0, function() Calibrate() end) end
end)

-------------------------------------------------------------------------------------
-- NET RECEIVERS
-------------------------------------------------------------------------------------
net.Receive("vrmod_fbt_cal", function()
	local ply = net.ReadEntity()
	local steamid = ply:SteamID()
	local info = characterInfo[steamid] or {}
	characterInfo[steamid] = info
	info.headCalibrationPos, info.headCalibrationAng = net.ReadVector(), net.ReadAngle()
	info.waistCalibrationPos, info.waistCalibrationAng = net.ReadVector(), net.ReadAngle()
	info.leftFootCalibrationPos, info.leftFootCalibrationAng = net.ReadVector(), net.ReadAngle()
	info.rightFootCalibrationPos, info.rightFootCalibrationAng = net.ReadVector(), net.ReadAngle()
	Start(ply)
end)

net.Receive("vrmod_fbt_toggle", function()
	local ply = net.ReadEntity()
	if not IsValid(ply) then return end
	if net.ReadBool() then
		-- Switch to FBT (standing still)
		Start(ply)
	else
		-- Switch to standard animations (walking)
		Stop(ply)
	end
end)

-------------------------------------------------------------------------------------
-- VR EXIT CLEANUP
-------------------------------------------------------------------------------------
hook.Add("VRMod_Exit", "vrmod_fbtstop", function(ply, steamid)
	Stop(ply)
	if ply == LocalPlayer() then
		hook.Remove("VRMod_Input", "fbt_walk")
		hook.Remove("VRMod_EnterVehicle", "fbt_entervehicle")
		hook.Remove("VRMod_ExitVehicle", "fbt_exitvehicle")
	end
end)

vrmod.logger.Info("Full-body tracking module loaded")