if CLIENT then
	g_VR = g_VR or {}
	g_VR.characterYaw = 0
	local convars, convarValues = vrmod.GetConvars()
	-- Constants
	local DEFAULT_EYE_HEIGHT = 66.8
	local DEFAULT_HEAD_TO_HMD_DIST = 6.3
	local NUM_FINGER_BONES = 30
	local ZERO_VEC = Vector()
	local ZERO_ANG = Angle()
	local RIGHT_HAND_OFFSET = Angle(0, 0, 180)
	local ANGLE_THRESHOLD = 0.01
	local POS_THRESHOLD = 0.01
	local zeroVec, zeroAng = ZERO_VEC, ZERO_ANG
	------------------------------------------------------------------------
	-- CONVARS
	------------------------------------------------------------------------
	------------------------------------------------------------------------
	-- HAND ANGLES
	------------------------------------------------------------------------
	g_VR.zeroHandAngles = {}
	for i = 1, NUM_FINGER_BONES do
		g_VR.zeroHandAngles[i] = Angle(0, 0, 0)
	end

	g_VR.defaultOpenHandAngles = {Angle(5, 10, 0), Angle(0, -20, 5), Angle(0, -10, 0), Angle(0, -3, 1), Angle(0, -2, 0), Angle(0, -1, 0), Angle(0, 0, 0), Angle(0, -2, 0), Angle(0, -1, 0), Angle(0, 2, -1), Angle(0, -1, 0), Angle(0, 0, 0), Angle(0, 4, -1), Angle(0, 0, 0), Angle(0, 0, 0), Angle(5, -10, 0), Angle(0, -20, -5), Angle(0, -10, 0), Angle(0, 3, -1), Angle(0, -2, 0), Angle(0, -1, 0), Angle(0, 0, 0), Angle(0, -2, 0), Angle(0, -1, 0), Angle(0, -2, 1), Angle(0, -1, 0), Angle(0, 0, 0), Angle(0, -4, 1), Angle(0, 0, 0), Angle(0, 0, 0),}
	g_VR.defaultClosedHandAngles = {Angle(30, 0, 0), Angle(0, 0, 0), Angle(0, 30, 0), Angle(0, -50, -10), Angle(0, -90, 0), Angle(0, -70, 0), Angle(0, -35.8, 0), Angle(0, -80, 0), Angle(0, -70, 0), Angle(0, -26.5, 4.8), Angle(0, -70, 0), Angle(0, -70, 0), Angle(0, -30, 12.7), Angle(0, -70, 0), Angle(0, -70, 0), Angle(-30, 0, 0), Angle(0, 0, 0), Angle(0, 30, 0), Angle(0, -50, 10), Angle(0, -90, 0), Angle(0, -70, 0), Angle(0, -35.8, 0), Angle(0, -80, 0), Angle(0, -70, 0), Angle(0, -26.5, -4.8), Angle(0, -70, 0), Angle(0, -70, 0), Angle(0, -30, -12.7), Angle(0, -70, 0), Angle(0, -70, 0),}
	g_VR.openHandAngles = g_VR.defaultOpenHandAngles
	g_VR.closedHandAngles = g_VR.defaultClosedHandAngles
	----------------------------------------------------------------------------------------------------------------------------------------------------
	-- CHARACTER SYSTEM
	----------------------------------------------------------------------------------------------------------------------------------------------------
	local prevFrameNumber = 0
	local lastFrames = {}
	local characterInfo = {}
	local activePlayers = {}
	local updatedPlayers = {}
	g_VR.fbtActive = g_VR.fbtActive or {} -- Per-player FBT active flag, set by sh_character_fbt.lua
	local function RecursiveBoneTable2(ent, parentbone, infotab, ordertab, notfirst)
		local bones = notfirst and ent:GetChildBones(parentbone) or {parentbone}
		for k, v in pairs(bones) do
			local n = ent:GetBoneName(v)
			local boneparent = ent:GetBoneParent(v)
			local parentmat = ent:GetBoneMatrix(boneparent)
			local childmat = ent:GetBoneMatrix(v)
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
				overrideAng = nil
			}

			ordertab[#ordertab + 1] = v
		end

		for k, v in pairs(bones) do
			RecursiveBoneTable2(ent, v, infotab, ordertab, true)
		end
	end

	local function UpdateIK(ply)
		local steamid = ply:SteamID()
		local net = g_VR.net[steamid]
		local charinfo = characterInfo[steamid]
		local boneinfo = charinfo.boneinfo
		local bones = charinfo.bones
		local frame = net.lerpedFrame
		-- Skip if frame hasn't changed
		if lastFrames[steamid] and vrmod.utils.FramesAreEqual(frame, lastFrames[steamid]) then return end
		local inVehicle = ply:InVehicle()
		local plyAng = inVehicle and ply:GetVehicle():GetAngles() or Angle(0, frame.characterYaw, 0)
		if inVehicle then _, plyAng = LocalToWorld(zeroVec, Angle(0, 90, 0), zeroVec, plyAng) end
		-- Read from convars every frame (reactive to slider changes)
		local eyeHeight = convarValues.characterEyeHeight or 66.8
		-- Alt head
		if net.characterAltHead then
			local _, tmp2 = WorldToLocal(zeroVec, frame.hmdAng, zeroVec, Angle(0, frame.characterYaw, 0))
			ply:ManipulateBoneAngles(bones.b_head, Angle(-tmp2.roll, -tmp2.pitch, tmp2.yaw))
		end

		-- Crouching
		if not inVehicle then
			-- Update spineLen if eyeHeight changed
			local spineLen = eyeHeight - charinfo.spineZ
			charinfo.spineLen = spineLen
			local headHeight = frame.hmdPos.z + (frame.hmdAng:Forward() * -3).z
			local cutAmount = math.Clamp(charinfo.preRenderPos.z + eyeHeight - headHeight, 0, 40)
			local spineTargetLen = spineLen - cutAmount * 0.5
			local a1 = math.acos(math.Clamp(spineTargetLen / spineLen, -1, 1))
			charinfo.horizontalCrouchOffset = math.sin(a1) * spineLen
			ply:ManipulateBoneAngles(bones.b_spine, Angle(0, math.deg(a1), 0))
			charinfo.verticalCrouchOffset = cutAmount * 0.5
			local legTargetLen = charinfo.upperLegLen + charinfo.lowerLegLen - charinfo.verticalCrouchOffset * 0.8
			local cosA1 = (charinfo.upperLegLen * charinfo.upperLegLen + legTargetLen * legTargetLen - charinfo.lowerLegLen * charinfo.lowerLegLen) / (2 * charinfo.upperLegLen * legTargetLen)
			local cosA23 = (charinfo.lowerLegLen * charinfo.lowerLegLen + legTargetLen * legTargetLen - charinfo.upperLegLen * charinfo.upperLegLen) / (2 * charinfo.lowerLegLen * legTargetLen)
			local a1 = math.deg(math.acos(math.Clamp(cosA1, -1, 1)))
			local a23 = 180 - a1 - math.deg(math.acos(math.Clamp(cosA23, -1, 1)))
			if a1 ~= a1 or a23 ~= a23 then
				a1 = 0
				a23 = 180
			end

			ply:ManipulateBoneAngles(bones.b_leftCalf, Angle(0, -(a23 - 180), 0))
			ply:ManipulateBoneAngles(bones.b_leftThigh, Angle(0, -a1, 0))
			ply:ManipulateBoneAngles(bones.b_rightCalf, Angle(0, -(a23 - 180), 0))
			ply:ManipulateBoneAngles(bones.b_rightThigh, Angle(0, -a1, 0))
			ply:ManipulateBoneAngles(bones.b_leftFoot, Angle(0, -a1, 0))
			ply:ManipulateBoneAngles(bones.b_rightFoot, Angle(0, -a1, 0))
		else
			ply:ManipulateBoneAngles(bones.b_spine, Angle(0, 0, 0))
			ply:ManipulateBoneAngles(bones.b_leftCalf, Angle(0, 0, 0))
			ply:ManipulateBoneAngles(bones.b_leftThigh, Angle(0, 0, 0))
			ply:ManipulateBoneAngles(bones.b_rightCalf, Angle(0, 0, 0))
			ply:ManipulateBoneAngles(bones.b_rightThigh, Angle(0, 0, 0))
			ply:ManipulateBoneAngles(bones.b_leftFoot, Angle(0, 0, 0))
			ply:ManipulateBoneAngles(bones.b_rightFoot, Angle(0, 0, 0))
		end

		--****************** ARM PROCESSING ******************
		local function ProcessArm(side)
			local isLeft = side == "left"
			local prefix = isLeft and "L_" or "R_"
			local targetPos = isLeft and frame.lefthandPos or frame.righthandPos
			local targetAng = isLeft and frame.lefthandAng or frame.righthandAng
			local clavicleBone = isLeft and bones.b_leftClavicle or bones.b_rightClavicle
			local upperarmBone = isLeft and bones.b_leftUpperarm or bones.b_rightUpperarm
			local mtx = ply:GetBoneMatrix(clavicleBone)
			local claviclePos = mtx and mtx:GetTranslation() or Vector()
			charinfo[prefix .. "ClaviclePos"] = claviclePos
			local tmp1 = claviclePos + plyAng:Right() * (isLeft and -charinfo.clavicleLen or charinfo.clavicleLen)
			local tmp2 = tmp1 + (targetPos - tmp1) * 0.15
			local clavicleTargetAng
			if not inVehicle then
				clavicleTargetAng = (tmp2 - claviclePos):Angle()
			else
				_, clavicleTargetAng = LocalToWorld(Vector(), WorldToLocal(tmp2 - claviclePos, zeroAng, zeroVec, plyAng):Angle(), zeroVec, plyAng)
			end

			clavicleTargetAng:RotateAroundAxis(clavicleTargetAng:Forward(), 90)
			local upperarmPos = LocalToWorld(boneinfo[upperarmBone].relativePos, boneinfo[upperarmBone].relativeAng, claviclePos, clavicleTargetAng)
			local targetVec = targetPos - upperarmPos
			local targetVecLen = targetVec:Length()
			local targetVecAng, targetVecAngLocal
			if not inVehicle then
				targetVecAng = targetVec:Angle()
			else
				targetVecAngLocal = WorldToLocal(targetVec, zeroAng, zeroVec, plyAng):Angle()
				_, targetVecAng = LocalToWorld(Vector(), targetVecAngLocal, zeroVec, plyAng)
			end

			local upperarmTargetAng = Angle(targetVecAng.pitch, targetVecAng.yaw, targetVecAng.roll)
			if not isLeft then upperarmTargetAng:RotateAroundAxis(targetVec, 180) end
			local tmp
			if not inVehicle then
				tmp = Angle(targetVecAng.pitch, frame.characterYaw, isLeft and -90 or 90)
			else
				_, tmp = LocalToWorld(Vector(), Angle((targetVecAngLocal or targetVecAng).pitch, 0, isLeft and -90 or 90), zeroVec, plyAng)
			end

			local _, tang = WorldToLocal(zeroVec, tmp, zeroVec, targetVecAng)
			upperarmTargetAng:RotateAroundAxis(upperarmTargetAng:Forward(), tang.roll)
			local totalArmLen = charinfo.upperArmLen + charinfo.lowerArmLen
			local armStretchScale = 1
			local effUpper, effLower = charinfo.upperArmLen, charinfo.lowerArmLen
			if convarValues.armStretcher and targetVecLen > totalArmLen * 0.98 then
				armStretchScale = targetVecLen / (totalArmLen * 0.98)
				effUpper = charinfo.upperArmLen * armStretchScale
				effLower = charinfo.lowerArmLen * armStretchScale
			end

			charinfo[prefix .. "armStretchScale"] = armStretchScale
			local a1 = math.deg(math.acos(math.Clamp((effUpper * effUpper + targetVecLen * targetVecLen - effLower * effLower) / (2 * effUpper * targetVecLen), -1, 1)))
			if a1 == a1 then upperarmTargetAng:RotateAroundAxis(upperarmTargetAng:Up(), a1) end
			local test
			if not inVehicle then
				test = (targetPos.z - upperarmPos.z + 20) * 1.5
			else
				test = ((targetPos - upperarmPos):Dot(plyAng:Up()) + 20) * 1.5
			end

			if test < 0 then test = 0 end
			upperarmTargetAng:RotateAroundAxis(targetVec:GetNormalized(), (isLeft and 1 or -1) * (30 + test))
			local forearmTargetAng = Angle(upperarmTargetAng.pitch, upperarmTargetAng.yaw, upperarmTargetAng.roll)
			local a23 = 180 - a1 - math.deg(math.acos(math.Clamp((effLower * effLower + targetVecLen * targetVecLen - effUpper * effUpper) / (2 * effLower * targetVecLen), -1, 1)))
			if a23 == a23 then forearmTargetAng:RotateAroundAxis(forearmTargetAng:Up(), 180 + a23) end
			local tmp = Angle(targetAng.pitch, targetAng.yaw, targetAng.roll - 90)
			local _, tang = WorldToLocal(zeroVec, tmp, zeroVec, forearmTargetAng)
			local wristTargetAng = Angle(forearmTargetAng.pitch, forearmTargetAng.yaw, forearmTargetAng.roll)
			wristTargetAng:RotateAroundAxis(wristTargetAng:Forward(), tang.roll)
			local ulnaTargetAng = LerpAngle(0.5, forearmTargetAng, wristTargetAng)
			return {
				clavicle = clavicleTargetAng,
				upperarm = upperarmTargetAng,
				forearm = forearmTargetAng,
				wrist = wristTargetAng,
				ulna = ulnaTargetAng,
				hand = isLeft and targetAng or targetAng + RIGHT_HAND_OFFSET,
				targetPos = targetPos,
			}
		end

		local leftArm = ProcessArm("left")
		local rightArm = ProcessArm("right")
		-- Override angles
		boneinfo[bones.b_leftClavicle].overrideAng = leftArm.clavicle
		boneinfo[bones.b_leftUpperarm].overrideAng = leftArm.upperarm
		boneinfo[bones.b_leftHand].overrideAng = leftArm.hand
		boneinfo[bones.b_rightClavicle].overrideAng = rightArm.clavicle
		boneinfo[bones.b_rightUpperarm].overrideAng = rightArm.upperarm
		boneinfo[bones.b_rightHand].overrideAng = rightArm.hand
		-- Hand position override for stretching
		charinfo.L_HandTargetPos = charinfo.L_armStretchScale ~= 1 and leftArm.targetPos or nil
		charinfo.R_HandTargetPos = charinfo.R_armStretchScale ~= 1 and rightArm.targetPos or nil
		if bones.b_leftWrist and boneinfo[bones.b_leftWrist] and bones.b_leftUlna and boneinfo[bones.b_leftUlna] then
			boneinfo[bones.b_leftForearm].overrideAng = leftArm.forearm
			boneinfo[bones.b_leftWrist].overrideAng = leftArm.wrist
			boneinfo[bones.b_leftUlna].overrideAng = leftArm.ulna
			boneinfo[bones.b_rightForearm].overrideAng = rightArm.forearm
			boneinfo[bones.b_rightWrist].overrideAng = rightArm.wrist
			boneinfo[bones.b_rightUlna].overrideAng = rightArm.ulna
		else
			boneinfo[bones.b_leftForearm].overrideAng = leftArm.ulna
			boneinfo[bones.b_rightForearm].overrideAng = rightArm.ulna
		end

		-- Fingers
		for k, v in pairs(bones.fingers) do
			if not boneinfo[v] then continue end
			boneinfo[v].offsetAng = LerpAngle(frame["finger" .. math.floor((k - 1) / 3 + 1)], g_VR.openHandAngles[k], g_VR.closedHandAngles[k])
		end

		-- Target matrices (reuse existing Matrix, only update if changed)
		for i = 1, #charinfo.boneorder do
			local bone = charinfo.boneorder[i]
			local bd = boneinfo[bone]
			local wpos, wang
			if bd.name == "ValveBiped.Bip01_L_Clavicle" then
				wpos = charinfo.L_ClaviclePos
			elseif bd.name == "ValveBiped.Bip01_R_Clavicle" then
				wpos = charinfo.R_ClaviclePos
			else
				wpos, wang = LocalToWorld(bd.relativePos, bd.relativeAng + bd.offsetAng, boneinfo[bd.parent].pos, boneinfo[bd.parent].ang)
			end

			if bd.overrideAng ~= nil then wang = bd.overrideAng end
			if charinfo.L_HandTargetPos and bd.name == "ValveBiped.Bip01_L_Hand" then
				wpos = charinfo.L_HandTargetPos
			elseif charinfo.R_HandTargetPos and bd.name == "ValveBiped.Bip01_R_Hand" then
				wpos = charinfo.R_HandTargetPos
			end

			local mat = bd.targetMatrix
			if not bd.pos or not bd.ang or wpos:DistToSqr(bd.pos) > POS_THRESHOLD or math.abs(wang.pitch - bd.ang.pitch) > ANGLE_THRESHOLD or math.abs(wang.yaw - bd.ang.yaw) > ANGLE_THRESHOLD or math.abs(wang.roll - bd.ang.roll) > ANGLE_THRESHOLD then
				mat:Identity()
				mat:SetTranslation(wpos)
				mat:SetAngles(wang)
				if charinfo.L_armStretchScale ~= 1 and (bd.name == "ValveBiped.Bip01_L_UpperArm" or bd.name == "ValveBiped.Bip01_L_Forearm") then mat:Scale(Vector(charinfo.L_armStretchScale, 1, 1)) end
				if charinfo.R_armStretchScale ~= 1 and (bd.name == "ValveBiped.Bip01_R_UpperArm" or bd.name == "ValveBiped.Bip01_R_Forearm") then mat:Scale(Vector(charinfo.R_armStretchScale, 1, 1)) end
				bd.pos = wpos
				bd.ang = wang
			end
		end

		lastFrames[steamid] = vrmod.utils.CopyFrame(frame)
	end

	local function CharacterInit(ply)
		local steamid = ply:SteamID()
		g_VR.cache = g_VR.cache or {}
		g_VR.cache[steamid] = g_VR.cache[steamid] or {}
		local pmname = ply:GetModel()
		if characterInfo[steamid] and characterInfo[steamid].modelName == pmname then return end
		if ply == LocalPlayer() then
			timer.Create("vrutil_timer_validatefingertracking", 0.1, 0, function()
				if g_VR.tracking.pose_lefthand and g_VR.tracking.pose_righthand and g_VR.tracking.pose_lefthand.simulatedPos == nil and g_VR.tracking.pose_righthand.simulatedPos == nil then
					timer.Remove("vrutil_timer_validatefingertracking")
					for i = 1, 2 do
						for k, v in pairs(i == 1 and g_VR.input.skeleton_lefthand.fingerCurls or g_VR.input.skeleton_righthand.fingerCurls) do
							if v < 0 or v > 1 or k == 3 and v == 0.75 then
								g_VR.defaultOpenHandAngles = g_VR.defaultOpenHandAngles
								g_VR.defaultClosedHandAngles = g_VR.defaultClosedHandAngles
								g_VR.openHandAngles = g_VR.defaultOpenHandAngles
								g_VR.closedHandAngles = g_VR.defaultClosedHandAngles
								break
							end
						end
					end
				end
			end)
		end

		characterInfo[steamid] = {
			preRenderPos = Vector(0, 0, 0),
			renderPos = Vector(0, 0, 0),
			characterHeadToHmdDist = 0,
			characterEyeHeight = 0,
			bones = {},
			boneinfo = {},
			boneorder = {},
			player = ply,
			boneCallback = 0,
			verticalCrouchOffset = 0,
			horizontalCrouchOffset = 0,
		}

		ply:SetLOD(0)
		local cm = ClientsideModel(pmname)
		cm:SetPos(LocalPlayer():GetPos())
		cm:SetAngles(Angle(0, 0, 0))
		cm:SetupBones()
		RecursiveBoneTable2(cm, cm:LookupBone("ValveBiped.Bip01_L_Clavicle"), characterInfo[steamid].boneinfo, characterInfo[steamid].boneorder)
		RecursiveBoneTable2(cm, cm:LookupBone("ValveBiped.Bip01_R_Clavicle"), characterInfo[steamid].boneinfo, characterInfo[steamid].boneorder)
		for bone, data in pairs(characterInfo[steamid].boneinfo) do
			data.targetMatrix = Matrix()
			data.pos = Vector()
			data.ang = Angle()
			data.lastPos = nil
			data.lastAng = nil
			data.overrideAng = nil
		end

		local boneNames = {
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

		characterInfo[steamid].bones = {
			fingers = {cm:LookupBone("ValveBiped.Bip01_L_Finger0") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger01") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger02") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger1") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger11") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger12") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger2") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger21") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger22") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger3") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger31") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger32") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger4") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger41") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger42") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger0") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger01") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger02") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger1") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger11") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger12") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger2") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger21") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger22") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger3") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger31") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger32") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger4") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger41") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger42") or -1,}
		}

		if ply == LocalPlayer() then g_VR.errorText = "" end
		for k, v in pairs(boneNames) do
			local bone = cm:LookupBone(v) or -1
			characterInfo[steamid].bones[k] = bone
			if bone == -1 and not string.find(k, "Wrist") and not string.find(k, "Ulna") then
				if ply == LocalPlayer() then g_VR.errorText = "Incompatible player model. Missing bone " .. v end
				cm:Remove()
				g_VR.StopCharacterSystem(steamid)
				vrmod.logger.Err("CharacterInit failed for " .. steamid)
				return false
			end
		end

		characterInfo[steamid].modelName = pmname
		local claviclePos = cm:GetBonePosition(characterInfo[steamid].bones.b_leftClavicle)
		local upperPos = cm:GetBonePosition(characterInfo[steamid].bones.b_leftUpperarm)
		local lowerPos = cm:GetBonePosition(characterInfo[steamid].bones.b_leftForearm)
		local handPos = cm:GetBonePosition(characterInfo[steamid].bones.b_leftHand)
		local thighPos = cm:GetBonePosition(characterInfo[steamid].bones.b_leftThigh)
		local calfPos = cm:GetBonePosition(characterInfo[steamid].bones.b_leftCalf)
		local footPos = cm:GetBonePosition(characterInfo[steamid].bones.b_leftFoot)
		local spinePos = cm:GetBonePosition(characterInfo[steamid].bones.b_spine)
		characterInfo[steamid].clavicleLen = claviclePos:Distance(upperPos)
		characterInfo[steamid].upperArmLen = upperPos:Distance(lowerPos)
		characterInfo[steamid].lowerArmLen = lowerPos:Distance(handPos)
		characterInfo[steamid].upperLegLen = thighPos:Distance(calfPos)
		characterInfo[steamid].lowerLegLen = calfPos:Distance(footPos)
		characterInfo[steamid].characterEyeHeight = DEFAULT_EYE_HEIGHT
		characterInfo[steamid].characterHeadToHmdDist = DEFAULT_HEAD_TO_HMD_DIST
		characterInfo[steamid].spineZ = spinePos.z - cm:GetPos().z
		characterInfo[steamid].spineLen = (cm:GetPos().z + characterInfo[steamid].characterEyeHeight) - spinePos.z
		cm:Remove()
	end

	------------------------------------------------------------------------
	local function BoneCallbackFunc(ply, numbones)
		local steamid = ply:SteamID()
		if not activePlayers[steamid] or not g_VR.net[steamid].lerpedFrame or ply:InVehicle() and ply:GetVehicle():GetClass() ~= "prop_vehicle_prisoner_pod" then return end
		if g_VR.fbtActive[steamid] then -- FBT handles all bones
			return
		end

		if ply:GetBoneMatrix(characterInfo[steamid].bones.b_rightHand) then ply:SetBonePosition(characterInfo[steamid].bones.b_rightHand, g_VR.net[steamid].lerpedFrame.righthandPos, g_VR.net[steamid].lerpedFrame.righthandAng + RIGHT_HAND_OFFSET) end
		if not g_VR.net[steamid].characterAltHead then
			local _, targetAng = LocalToWorld(zeroVec, Angle(-80, 0, 90), zeroVec, g_VR.net[steamid].lerpedFrame.hmdAng)
			local mtx = ply:GetBoneMatrix(characterInfo[steamid].bones.b_head)
			if mtx then
				mtx:SetAngles(targetAng)
				ply:SetBoneMatrix(characterInfo[steamid].bones.b_head, mtx)
			end
		end
	end

	------------------------------------------------------------------------
	local up = Vector(0, 0, 1)
	local function PreRenderFunc()
		if convars.vrmod_oldcharacteryaw:GetBool() then
			-- old behavior (unchanged)
			local _, relativeAng = WorldToLocal(zeroVec, Angle(0, g_VR.tracking.hmd.ang.yaw, 0), zeroVec, Angle(0, g_VR.characterYaw, 0))
			if relativeAng.yaw > 45 then
				g_VR.characterYaw = g_VR.characterYaw + relativeAng.yaw - 45
			elseif relativeAng.yaw < -45 then
				g_VR.characterYaw = g_VR.characterYaw + relativeAng.yaw + 45
			end

			if g_VR.input.boolean_walk or g_VR.input.boolean_turnleft or g_VR.input.boolean_turnright then g_VR.characterYaw = g_VR.tracking.hmd.ang.yaw end
			return
		end

		-- ---- optimized method ----
		local leftPos = g_VR.tracking.pose_lefthand.pos
		local rightPos = g_VR.tracking.pose_righthand.pos
		local hmdPos = g_VR.tracking.hmd.pos
		local hmdAng = g_VR.tracking.hmd.ang
		-- local helpers to avoid repeated global lookups
		local NormalizeAngle = math.NormalizeAngle
		local Clamp = math.Clamp
		local RealFT = RealFrameTime()
		-- compute hand positions relative to HMD once (WorldToLocal returns pos, ang)
		-- Use the returned pos.y for the left/right crossing check
		local lpos_local = WorldToLocal(leftPos, zeroAng, hmdPos, hmdAng) -- (pos, ang) unused ang
		local rpos_local = WorldToLocal(rightPos, zeroAng, hmdPos, hmdAng)
		-- update handYaw only if hands are not crossed (same logic)
		if lpos_local.y > rpos_local.y then
			-- compute yaw from delta x,y via atan2 to avoid Vector():Angle() allocations
			local dx = rightPos.x - leftPos.x
			local dy = rightPos.y - leftPos.y
			local handYaw = math.deg(math.atan2(dy, dx)) + 90
			-- normalize to -180..180
			handYaw = NormalizeAngle(handYaw)
			-- compute forward angle projected to horizontal plane (zero pitch)
			local fwd = hmdAng:Forward()
			fwd.z = 0
			if fwd:LengthSqr() < 1e-6 then
				-- fallback to HMD yaw if forward degenerate
				fwd = Angle(0, hmdAng.yaw, 0):Forward()
			end

			local forwardYaw = fwd:Angle().yaw
			-- compute relative yaw from forward to handYaw in degrees, clamp at ±45
			local relativeToForward = NormalizeAngle(handYaw - forwardYaw)
			local clamped = Clamp(relativeToForward, -45, 45)
			local targetYaw = forwardYaw + clamped
			-- compute yaw difference between targetYaw and current characterYaw, normalized
			local yawDiff = NormalizeAngle(targetYaw - g_VR.characterYaw)
			-- smooth toward target; keep your existing responsiveness (8 * RealFrameTime)
			g_VR.characterYaw = NormalizeAngle(g_VR.characterYaw + yawDiff * 8 * RealFT)
		end

		-- If movement inputs require snapping the char yaw to HMD yaw, keep that behavior
		if g_VR.input.boolean_walk or g_VR.input.boolean_turnleft or g_VR.input.boolean_turnright then g_VR.characterYaw = g_VR.tracking.hmd.ang.yaw end
	end

	------------------------------------------------------------------------
	local function PrePlayerDrawFunc(ply)
		if not IsValid(ply) then return end
		local steamid = ply:SteamID()
		if not activePlayers[steamid] or not g_VR.net[steamid] or not g_VR.net[steamid].lerpedFrame then return end
		if not characterInfo or not characterInfo[steamid] or not characterInfo[steamid].bones then return end
		local headToHmdDist = convarValues.characterHeadToHmdDist or 6.3
		if ply == LocalPlayer() then
			local ep = EyePos()
			local hide = (ep == g_VR.eyePosLeft or ep == g_VR.eyePosRight) and ply:GetViewEntity() == ply
			ply:ManipulateBoneScale(characterInfo[steamid].bones.b_head, hide and zeroVec or Vector(1, 1, 1))
		end

		characterInfo[steamid].preRenderPos = ply:GetPos()
		if not ply:InVehicle() then
			characterInfo[steamid].renderPos = g_VR.net[steamid].lerpedFrame.hmdPos + up:Cross(g_VR.net[steamid].lerpedFrame.hmdAng:Right()) * -headToHmdDist + Angle(0, g_VR.net[steamid].lerpedFrame.characterYaw, 0):Forward() * -characterInfo[steamid].horizontalCrouchOffset * 0.8
			characterInfo[steamid].renderPos.z = ply:GetPos().z - characterInfo[steamid].verticalCrouchOffset
			ply:SetPos(characterInfo[steamid].renderPos)
			ply:SetRenderAngles(Angle(0, g_VR.net[steamid].lerpedFrame.characterYaw, 0))
		end

		ply:SetupBones()
		if g_VR.fbtActive[steamid] then -- FBT handles all bone positioning
			return
		end

		if prevFrameNumber ~= FrameNumber() then
			prevFrameNumber = FrameNumber()
			updatedPlayers = {}
		end

		if not updatedPlayers[steamid] then
			UpdateIK(ply)
			updatedPlayers[steamid] = 1
		end

		if characterInfo[steamid].boneorder and characterInfo[steamid].boneinfo then
			for i = 1, #characterInfo[steamid].boneorder do
				local bone = characterInfo[steamid].boneorder[i]
				if ply:GetBoneMatrix(bone) and characterInfo[steamid].boneinfo[bone] and characterInfo[steamid].boneinfo[bone].targetMatrix then ply:SetBoneMatrix(bone, characterInfo[steamid].boneinfo[bone].targetMatrix) end
			end
		end
	end

	local function PostPlayerDrawFunc(ply)
		if not IsValid(ply) then return end
		local steamid = ply:SteamID()
		if activePlayers[steamid] == nil then return end
		if not g_VR.net or not g_VR.net[steamid] or not g_VR.net[steamid].lerpedFrame then return end
		if not characterInfo or not characterInfo[steamid] then return end
		if g_VR.vehicle.current then return end
		ply:SetPos(characterInfo[steamid].preRenderPos)
	end

	------------------------------------------------------------------------
	local function CalcMainActivityFunc(ply, vel)
		if not activePlayers[ply:SteamID()] or ply:InVehicle() then return end
		-- When animations are disabled, force idle standing pose
		if not convarValues.characterIK then
			ply:SetPlaybackRate(0)
			ply:SetPoseParameter("move_yaw", 0)
			ply:SetPoseParameter("move_x", 0)
			ply:SetPoseParameter("move_y", 0)
			return ACT_HL2MP_IDLE, -1
		end

		local act = ACT_HL2MP_IDLE
		if ply.m_bJumping then
			act = ACT_HL2MP_JUMP_PASSIVE
			if CurTime() - ply.m_flJumpStartTime > 0.2 and ply:OnGround() then ply.m_bJumping = false end
		else
			local l = vel:Length2DSqr()
			if l > 22500 then
				act = ACT_HL2MP_RUN
			elseif l > 0.25 then
				act = ACT_HL2MP_WALK
			end
		end
		return act, -1
	end

	local function DoAnimationEventFunc(ply, evt, data)
		if not activePlayers[ply:SteamID()] or ply:InVehicle() then return end
		-- Block all animation events when animations are disabled
		if not convarValues.characterIK then return ACT_INVALID end
		if evt ~= PLAYERANIMEVENT_JUMP then return ACT_INVALID end
	end

	------------------------------------------------------------------------
	function g_VR.StartCharacterSystem(ply)
		if not IsValid(ply) then return end
		local steamid = ply:SteamID()
		if CharacterInit(ply) == false then return end
		if not g_VR.net or not g_VR.net[steamid] then return end
		if characterInfo and characterInfo[steamid] then
			if characterInfo[steamid].boneCallback then ply:RemoveCallback("BuildBonePositions", characterInfo[steamid].boneCallback) end
			characterInfo[steamid].boneCallback = ply:AddCallback("BuildBonePositions", BoneCallbackFunc)
			if ply == LocalPlayer() then
				hook.Remove("VRMod_PreRender", "vrutil_hook_calcplyrenderpos")
				hook.Add("VRMod_PreRender", "vrutil_hook_calcplyrenderpos", PreRenderFunc)
			end

			hook.Remove("PrePlayerDraw", "vrutil_hook_preplayerdraw")
			hook.Add("PrePlayerDraw", "vrutil_hook_preplayerdraw", PrePlayerDrawFunc)
			hook.Remove("PostPlayerDraw", "vrutil_hook_postplayerdraw")
			hook.Add("PostPlayerDraw", "vrutil_hook_postplayerdraw", PostPlayerDrawFunc)
			hook.Remove("CalcMainActivity", "vrutil_hook_calcmainactivity")
			hook.Add("CalcMainActivity", "vrutil_hook_calcmainactivity", CalcMainActivityFunc)
			hook.Remove("DoAnimationEvent", "vrutil_hook_doanimationevent")
			hook.Add("DoAnimationEvent", "vrutil_hook_doanimationevent", DoAnimationEventFunc)
			activePlayers[steamid] = true
		end
	end

	function g_VR.StopCharacterSystem(steamid)
		if not activePlayers[steamid] then return end
		local ply = player.GetBySteamID(steamid)
		if characterInfo[steamid] and IsValid(ply) then
			for k, v in pairs(characterInfo[steamid].bones) do
				if not isnumber(v) then continue end
				ply:ManipulateBoneAngles(v, Angle(0, 0, 0))
			end

			ply:RemoveCallback("BuildBonePositions", characterInfo[steamid].boneCallback)
			if ply == LocalPlayer() then
				hook.Remove("VRMod_PreRender", "vrutil_hook_calcplyrenderpos")
				ply:ManipulateBoneScale(characterInfo[steamid].bones.b_head, Vector(1, 1, 1))
			end
		end

		activePlayers[steamid] = nil
		characterInfo[steamid] = nil
		lastFrames[steamid] = nil
		if table.Count(activePlayers) == 0 then
			hook.Remove("PrePlayerDraw", "vrutil_hook_preplayerdraw")
			hook.Remove("PostPlayerDraw", "vrutil_hook_postplayerdraw")
			hook.Remove("UpdateAnimation", "vrutil_hook_updateanimation")
			hook.Remove("CalcMainActivity", "vrutil_hook_calcmainactivity")
			hook.Remove("DoAnimationEvent", "vrutil_hook_doanimationevent")
		end

		vrmod.logger.Info("Stopped character system for " .. steamid)
	end

	hook.Add("VRMod_Start", "vrmod_characterstart", function(ply) g_VR.StartCharacterSystem(ply) end)
	hook.Add("VRMod_Exit", "vrmod_characterstop", function(ply, steamid) g_VR.StopCharacterSystem(steamid) end)
end