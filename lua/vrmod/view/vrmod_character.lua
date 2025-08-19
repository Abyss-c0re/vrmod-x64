if CLIENT then
	g_VR = g_VR or {}
	g_VR.characterYaw = 0
	local convars = vrmod.GetConvars()
	local lastModel = nil
	-- Constants
	local DEFAULT_EYE_HEIGHT = 66.8
	local DEFAULT_HEAD_TO_HMD_DIST = 6.3
	local NUM_FINGER_BONES = 30
	local ZERO_VEC = Vector()
	local ZERO_ANG = Angle()
	local RIGHT_HAND_OFFSET = Angle(0, 0, 180)
	local ANGLE_THRESHOLD = 0.01
	local POS_THRESHOLD = 0.01
	-- Generate hand angles
	g_VR.zeroHandAngles = {}
	for i = 1, NUM_FINGER_BONES do
		g_VR.zeroHandAngles[i] = Angle(0, 0, 0)
	end

	g_VR.defaultOpenHandAngles = {
		-- LEFT HAND
		-- Thumb
		Angle(5, 10, 0),
		Angle(0, -20, 5),
		Angle(0, -10, 0),
		-- Index
		Angle(0, -3, 1),
		Angle(0, -2, 0),
		Angle(0, -1, 0),
		-- Middle
		Angle(0, 0, 0),
		Angle(0, -2, 0),
		Angle(0, -1, 0),
		-- Ring
		Angle(0, 2, -1),
		Angle(0, -1, 0),
		Angle(0, 0, 0),
		-- Pinky
		Angle(0, 4, -1),
		Angle(0, 0, 0),
		Angle(0, 0, 0),
		-- RIGHT HAND
		-- Thumb
		Angle(5, -10, 0),
		Angle(0, -20, -5),
		Angle(0, -10, 0),
		-- Index
		Angle(0, 3, -1),
		Angle(0, -2, 0),
		Angle(0, -1, 0),
		-- Middle
		Angle(0, 0, 0),
		Angle(0, -2, 0),
		Angle(0, -1, 0),
		-- Ring
		Angle(0, -2, 1),
		Angle(0, -1, 0),
		Angle(0, 0, 0),
		-- Pinky
		Angle(0, -4, 1),
		Angle(0, 0, 0),
		Angle(0, 0, 0),
	}

	g_VR.defaultClosedHandAngles = {
		-- LEFT HAND
		-- Thumb
		Angle(30, 0, 0),
		Angle(0, 0, 0),
		Angle(0, 30, 0),
		-- Index
		Angle(0, -50, -10),
		Angle(0, -90, 0),
		Angle(0, -70, 0),
		-- Middle
		Angle(0, -35.8, 0),
		Angle(0, -80, 0),
		Angle(0, -70, 0),
		-- Ring
		Angle(0, -26.5, 4.8),
		Angle(0, -70, 0),
		Angle(0, -70, 0),
		-- Pinky
		Angle(0, -30, 12.7),
		Angle(0, -70, 0),
		Angle(0, -70, 0),
		-- RIGHT HAND
		-- Thumb
		Angle(-30, 0, 0),
		Angle(0, 0, 0),
		Angle(0, 30, 0),
		-- Index
		Angle(0, -50, 10),
		Angle(0, -90, 0),
		Angle(0, -70, 0),
		-- Middle
		Angle(0, -35.8, 0),
		Angle(0, -80, 0),
		Angle(0, -70, 0),
		-- Ring
		Angle(0, -26.5, -4.8),
		Angle(0, -70, 0),
		Angle(0, -70, 0),
		-- Pinky
		Angle(0, -30, -12.7),
		Angle(0, -70, 0),
		Angle(0, -70, 0),
	}

	g_VR.openHandAngles = g_VR.defaultOpenHandAngles
	g_VR.closedHandAngles = g_VR.defaultClosedHandAngles
	----------------------------------------------------------------------------------------------------------------------------------------------------
	local characterInfo = {}
	local activePlayers = {}
	local zeroVec, zeroAng = ZERO_VEC, ZERO_ANG
	local function RecursiveBoneTable2(ent, parentbone, infotab, ordertab, notfirst)
		local bones = notfirst and ent:GetChildBones(parentbone) or {parentbone}
		for k, v in pairs(bones) do
			local n = ent:GetBoneName(v)
			local boneparent = ent:GetBoneParent(v)
			local parentmat = ent:GetBoneMatrix(boneparent) --getboneposition doesnt work for all bones! but matrix seems to
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
				offsetAng = Angle(0, 0, 0)
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
		local inVehicle = ply:InVehicle() or IsValid(ply:GetNWEntity("GlideVehicle"))
		local plyAng = inVehicle and ply:GetVehicle():GetAngles() or Angle(0, frame.characterYaw, 0)
		if inVehicle then _, plyAng = LocalToWorld(zeroVec, Angle(0, 90, 0), zeroVec, plyAng) end
		-- Ensure cache is initialized
		g_VR.cache = g_VR.cache or {}
		g_VR.cache[steamid] = g_VR.cache[steamid] or {}
		local cache = g_VR.cache[steamid]
		-- Cache character yaw angle for non-vehicle case
		local characterYawAng = Angle(0, frame.characterYaw, 0)
		--alt head
		if net.characterAltHead then
			cache.headWTL = cache.headWTL or {}
			local pos, ang = WorldToLocal(zeroVec, frame.hmdAng, zeroVec, characterYawAng)
			cache.headWTL.pos, cache.headWTL.ang = pos, ang
			local _, tmp2 = cache.headWTL.pos, cache.headWTL.ang
			ply:ManipulateBoneAngles(bones.b_head, Angle(-tmp2.roll, -tmp2.pitch, tmp2.yaw))
		else
			cache.headWTL = nil
		end

		--****************** CROUCHING ******************
		if not inVehicle then
			local headHeight = frame.hmdPos.z + (frame.hmdAng:Forward() * -3).z
			local cutAmount = math.Clamp(charinfo.preRenderPos.z + charinfo.characterEyeHeight - headHeight, 0, 40)
			local spineTargetLen = charinfo.spineLen - cutAmount * 0.5
			local a1 = math.acos(spineTargetLen / charinfo.spineLen)
			charinfo.horizontalCrouchOffset = math.sin(a1) * charinfo.spineLen
			ply:ManipulateBoneAngles(bones.b_spine, Angle(0, math.deg(a1), 0))
			charinfo.verticalCrouchOffset = cutAmount * 0.5
			local legTargetLen = charinfo.upperLegLen + charinfo.lowerLegLen - charinfo.verticalCrouchOffset * 0.8
			local a1 = math.deg(math.acos((charinfo.upperLegLen * charinfo.upperLegLen + legTargetLen * legTargetLen - charinfo.lowerLegLen * charinfo.lowerLegLen) / (2 * charinfo.upperLegLen * legTargetLen)))
			local a23 = 180 - a1 - math.deg(math.acos((charinfo.lowerLegLen * charinfo.lowerLegLen + legTargetLen * legTargetLen - charinfo.upperArmLen * charinfo.upperArmLen) / (2 * charinfo.lowerLegLen * legTargetLen)))
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

		--****************** LEFT ARM ******************
		local L_TargetPos = frame.lefthandPos
		local L_TargetAng = frame.lefthandAng
		local mtx = ply:GetBoneMatrix(bones.b_leftClavicle)
		local L_ClaviclePos = mtx and mtx:GetTranslation() or ZERO_VEC
		charinfo.L_ClaviclePos = L_ClaviclePos
		local tmp1 = L_ClaviclePos + plyAng:Right() * -charinfo.clavicleLen
		local tmp2 = tmp1 + (L_TargetPos - tmp1) * 0.15
		local L_ClavicleTargetAng
		if not inVehicle then
			L_ClavicleTargetAng = (tmp2 - L_ClaviclePos):Angle()
		else
			cache.L_ClavicleWTL = cache.L_ClavicleWTL or {}
			local pos, ang = WorldToLocal(tmp2 - L_ClaviclePos, zeroAng, zeroVec, plyAng)
			cache.L_ClavicleWTL.pos, cache.L_ClavicleWTL.ang = pos, ang
			local _, ang = cache.L_ClavicleWTL.pos, cache.L_ClavicleWTL.ang
			_, L_ClavicleTargetAng = LocalToWorld(zeroVec, ang, zeroVec, plyAng)
		end

		L_ClavicleTargetAng:RotateAroundAxis(L_ClavicleTargetAng:Forward(), 90)
		local L_UpperarmPos = L_ClaviclePos + L_ClavicleTargetAng:Forward() * charinfo.clavicleLen
		local L_TargetVec = L_TargetPos - L_UpperarmPos
		local L_TargetVecLen = L_TargetVec:Length()
		local L_TargetVecAng, L_TargetVecAngLocal
		if not inVehicle then
			L_TargetVecAng = L_TargetVec:Angle()
		else
			cache.L_TargetVecWTL = cache.L_TargetVecWTL or {}
			local pos, ang = WorldToLocal(L_TargetVec, zeroAng, zeroVec, plyAng)
			cache.L_TargetVecWTL.pos, cache.L_TargetVecWTL.ang = pos, ang
			L_TargetVecAngLocal = cache.L_TargetVecWTL.ang
			_, L_TargetVecAng = LocalToWorld(zeroVec, L_TargetVecAngLocal, zeroVec, plyAng)
		end

		local L_UpperarmTargetAng = Angle(L_TargetVecAng.pitch, L_TargetVecAng.yaw, L_TargetVecAng.roll)
		local tmp
		if not inVehicle then
			tmp = Angle(L_TargetVecAng.pitch, frame.characterYaw, -90)
		else
			cache.L_UpperarmAng = cache.L_UpperarmAng or Angle(L_TargetVecAngLocal.pitch, 0, -90)
			_, tmp = LocalToWorld(zeroVec, cache.L_UpperarmAng, zeroVec, plyAng)
		end

		cache.L_UpperarmWTL = cache.L_UpperarmWTL or {}
		local pos, tang = WorldToLocal(zeroVec, tmp, zeroVec, L_TargetVecAng)
		cache.L_UpperarmWTL.pos, cache.L_UpperarmWTL.ang = pos, tang
		local _, tang = cache.L_UpperarmWTL.pos, cache.L_UpperarmWTL.ang
		L_UpperarmTargetAng:RotateAroundAxis(L_UpperarmTargetAng:Forward(), tang.roll)
		local a1 = math.deg(math.acos((charinfo.upperArmLen * charinfo.upperArmLen + L_TargetVecLen * L_TargetVecLen - charinfo.lowerArmLen * charinfo.lowerArmLen) / (2 * charinfo.upperArmLen * L_TargetVecLen)))
		if a1 == a1 then L_UpperarmTargetAng:RotateAroundAxis(L_UpperarmTargetAng:Up(), a1) end
		local test
		if not inVehicle then
			test = (L_TargetPos.z - L_UpperarmPos.z + 20) * 1.5
		else
			test = ((L_TargetPos - L_UpperarmPos):Dot(plyAng:Up()) + 20) * 1.5
		end

		if test < 0 then test = 0 end
		L_UpperarmTargetAng:RotateAroundAxis(L_TargetVec:GetNormalized(), 30 + test)
		local L_ForearmTargetAng = Angle(L_UpperarmTargetAng.pitch, L_UpperarmTargetAng.yaw, L_UpperarmTargetAng.roll)
		local a23 = 180 - a1 - math.deg(math.acos((charinfo.lowerArmLen * charinfo.lowerArmLen + L_TargetVecLen * L_TargetVecLen - charinfo.upperArmLen * charinfo.upperArmLen) / (2 * charinfo.lowerArmLen * L_TargetVecLen)))
		if a23 == a23 then L_ForearmTargetAng:RotateAroundAxis(L_ForearmTargetAng:Up(), 180 + a23) end
		local tmp = Angle(L_TargetAng.pitch, L_TargetAng.yaw, L_TargetAng.roll - 90)
		cache.L_WristWTL = cache.L_WristWTL or {}
		local pos, tang = WorldToLocal(zeroVec, tmp, zeroVec, L_ForearmTargetAng)
		cache.L_WristWTL.pos, cache.L_WristWTL.ang = pos, tang
		local _, tang = cache.L_WristWTL.pos, cache.L_WristWTL.ang
		local L_WristTargetAng = Angle(L_ForearmTargetAng.pitch, L_ForearmTargetAng.yaw, L_ForearmTargetAng.roll)
		L_WristTargetAng:RotateAroundAxis(L_WristTargetAng:Forward(), tang.roll)
		local L_UlnaTargetAng = LerpAngle(0.5, L_ForearmTargetAng, L_WristTargetAng)
		--****************** RIGHT ARM ******************
		local R_TargetPos = frame.righthandPos
		local R_TargetAng = frame.righthandAng
		local mtx = ply:GetBoneMatrix(bones.b_rightClavicle)
		local R_ClaviclePos = mtx and mtx:GetTranslation() or ZERO_VEC
		charinfo.R_ClaviclePos = R_ClaviclePos
		local tmp1 = R_ClaviclePos + plyAng:Right() * charinfo.clavicleLen
		local tmp2 = tmp1 + (R_TargetPos - tmp1) * 0.15
		local R_ClavicleTargetAng
		if not inVehicle then
			R_ClavicleTargetAng = (tmp2 - R_ClaviclePos):Angle()
		else
			cache.R_ClavicleWTL = cache.R_ClavicleWTL or {}
			local pos, ang = WorldToLocal(tmp2 - R_ClaviclePos, zeroAng, zeroVec, plyAng)
			cache.R_ClavicleWTL.pos, cache.R_ClavicleWTL.ang = pos, ang
			local _, ang = cache.R_ClavicleWTL.pos, cache.R_ClavicleWTL.ang
			_, R_ClavicleTargetAng = LocalToWorld(zeroVec, ang, zeroVec, plyAng)
		end

		R_ClavicleTargetAng:RotateAroundAxis(R_ClavicleTargetAng:Forward(), 90)
		local R_UpperarmPos = R_ClaviclePos + R_ClavicleTargetAng:Forward() * charinfo.clavicleLen
		local R_TargetVec = R_TargetPos - R_UpperarmPos
		local R_TargetVecLen = R_TargetVec:Length()
		local R_TargetVecAng, R_TargetVecAngLocal
		if not inVehicle then
			R_TargetVecAng = R_TargetVec:Angle()
		else
			cache.R_TargetVecWTL = cache.R_TargetVecWTL or {}
			local pos, ang = WorldToLocal(R_TargetVec, zeroAng, zeroVec, plyAng)
			cache.R_TargetVecWTL.pos, cache.R_TargetVecWTL.ang = pos, ang
			R_TargetVecAngLocal = cache.R_TargetVecWTL.ang
			_, R_TargetVecAng = LocalToWorld(zeroVec, R_TargetVecAngLocal, zeroVec, plyAng)
		end

		local R_UpperarmTargetAng = Angle(R_TargetVecAng.pitch, R_TargetVecAng.yaw, R_TargetVecAng.roll)
		R_UpperarmTargetAng:RotateAroundAxis(R_TargetVec, 180)
		local tmp
		if not inVehicle then
			tmp = Angle(R_TargetVecAng.pitch, frame.characterYaw, 90)
		else
			cache.R_UpperarmAng = cache.R_UpperarmAng or Angle(R_TargetVecAngLocal.pitch, 0, 90)
			_, tmp = LocalToWorld(zeroVec, cache.R_UpperarmAng, zeroVec, plyAng)
		end

		cache.R_UpperarmWTL = cache.R_UpperarmWTL or {}
		local pos, tang = WorldToLocal(zeroVec, tmp, zeroVec, R_TargetVecAng)
		cache.R_UpperarmWTL.pos, cache.R_UpperarmWTL.ang = pos, tang
		local _, tang = cache.R_UpperarmWTL.pos, cache.R_UpperarmWTL.ang
		R_UpperarmTargetAng:RotateAroundAxis(R_UpperarmTargetAng:Forward(), tang.roll)
		local a1 = math.deg(math.acos((charinfo.upperArmLen * charinfo.upperArmLen + R_TargetVecLen * R_TargetVecLen - charinfo.lowerArmLen * charinfo.lowerArmLen) / (2 * charinfo.upperArmLen * R_TargetVecLen)))
		if a1 == a1 then R_UpperarmTargetAng:RotateAroundAxis(R_UpperarmTargetAng:Up(), a1) end
		local test
		if not inVehicle then
			test = (R_TargetPos.z - R_UpperarmPos.z + 20) * 1.5
		else
			test = ((R_TargetPos - R_UpperarmPos):Dot(plyAng:Up()) + 20) * 1.5
		end

		if test < 0 then test = 0 end
		R_UpperarmTargetAng:RotateAroundAxis(R_TargetVec:GetNormalized(), -(30 + test))
		local R_ForearmTargetAng = Angle(R_UpperarmTargetAng.pitch, R_UpperarmTargetAng.yaw, R_UpperarmTargetAng.roll)
		local a23 = 180 - a1 - math.deg(math.acos((charinfo.lowerArmLen * charinfo.lowerArmLen + R_TargetVecLen * R_TargetVecLen - charinfo.upperArmLen * charinfo.upperArmLen) / (2 * charinfo.lowerArmLen * R_TargetVecLen)))
		if a23 == a23 then R_ForearmTargetAng:RotateAroundAxis(R_ForearmTargetAng:Up(), 180 + a23) end
		local tmp = Angle(R_TargetAng.pitch, R_TargetAng.yaw, R_TargetAng.roll - 90)
		cache.R_WristWTL = cache.R_WristWTL or {}
		local pos, tang = WorldToLocal(zeroVec, tmp, zeroVec, R_ForearmTargetAng)
		cache.R_WristWTL.pos, cache.R_WristWTL.ang = pos, tang
		local _, tang = cache.R_WristWTL.pos, cache.R_WristWTL.ang
		local R_WristTargetAng = Angle(R_ForearmTargetAng.pitch, R_ForearmTargetAng.yaw, R_ForearmTargetAng.roll)
		R_WristTargetAng:RotateAroundAxis(R_WristTargetAng:Forward(), tang.roll)
		local R_UlnaTargetAng = LerpAngle(0.5, R_ForearmTargetAng, R_WristTargetAng)
		--set absolute override angles for the relevant bones
		boneinfo[bones.b_leftClavicle].overrideAng = L_ClavicleTargetAng
		boneinfo[bones.b_leftUpperarm].overrideAng = L_UpperarmTargetAng
		boneinfo[bones.b_leftHand].overrideAng = L_TargetAng
		boneinfo[bones.b_rightClavicle].overrideAng = R_ClavicleTargetAng
		boneinfo[bones.b_rightUpperarm].overrideAng = R_UpperarmTargetAng
		boneinfo[bones.b_rightHand].overrideAng = R_TargetAng + RIGHT_HAND_OFFSET
		if bones.b_leftWrist and boneinfo[bones.b_leftWrist] and bones.b_leftUlna and boneinfo[bones.b_leftUlna] then
			boneinfo[bones.b_leftForearm].overrideAng = L_ForearmTargetAng
			boneinfo[bones.b_leftWrist].overrideAng = L_WristTargetAng
			boneinfo[bones.b_leftUlna].overrideAng = L_UlnaTargetAng
			boneinfo[bones.b_rightForearm].overrideAng = R_ForearmTargetAng
			boneinfo[bones.b_rightWrist].overrideAng = R_WristTargetAng
			boneinfo[bones.b_rightUlna].overrideAng = R_UlnaTargetAng
		else
			boneinfo[bones.b_leftForearm].overrideAng = L_UlnaTargetAng
			boneinfo[bones.b_rightForearm].overrideAng = R_UlnaTargetAng
		end

		--set finger offset angles
		for k, v in pairs(bones.fingers) do
			if not boneinfo[v] then continue end
			boneinfo[v].offsetAng = LerpAngle(frame["finger" .. math.floor((k - 1) / 3 + 1)], g_VR.openHandAngles[k], g_VR.closedHandAngles[k])
		end

		--calculate target matrices
		for i = 1, #charinfo.boneorder do
			local bone = charinfo.boneorder[i]
			local boneData = boneinfo[bone]
			local parent = boneData.parent
			local wpos, wang
			if boneData.name == "ValveBiped.Bip01_L_Clavicle" then
				wpos = charinfo.L_ClaviclePos
			elseif boneData.name == "ValveBiped.Bip01_R_Clavicle" then
				wpos = charinfo.R_ClaviclePos
			else
				local parentPos, parentAng = boneinfo[parent].pos, boneinfo[parent].ang
				wpos, wang = LocalToWorld(boneData.relativePos, boneData.relativeAng + boneData.offsetAng, parentPos, parentAng)
			end

			if boneData.overrideAng ~= nil then wang = boneData.overrideAng end
			local mat = boneData.targetMatrix
			if not boneData.pos or not boneData.ang or wpos:Distance(boneData.pos) > POS_THRESHOLD or math.abs(wang.pitch - boneData.ang.pitch) > ANGLE_THRESHOLD or math.abs(wang.yaw - boneData.ang.yaw) > ANGLE_THRESHOLD or math.abs(wang.roll - boneData.ang.roll) > ANGLE_THRESHOLD then
				mat:SetTranslation(wpos)
				mat:SetAngles(wang)
				boneData.pos = wpos
				boneData.ang = wang
			end
		end
	end

	local function CharacterInit(ply)
		local steamid = ply:SteamID()
		-- Initialize cache for this player
		g_VR.cache = g_VR.cache or {}
		g_VR.cache[steamid] = g_VR.cache[steamid] or {}
		local pmname = ply.vrmod_pm or ply:GetModel()
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
				print("VRMod: CharacterInit failed for " .. steamid)
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
		local headPos = cm:GetBonePosition(characterInfo[steamid].bones.b_head)
		local spinePos = cm:GetBonePosition(characterInfo[steamid].bones.b_spine)
		characterInfo[steamid].clavicleLen = claviclePos:Distance(upperPos)
		characterInfo[steamid].upperArmLen = upperPos:Distance(lowerPos)
		characterInfo[steamid].lowerArmLen = lowerPos:Distance(handPos)
		characterInfo[steamid].upperLegLen = thighPos:Distance(calfPos)
		characterInfo[steamid].lowerLegLen = calfPos:Distance(footPos)
		characterInfo[steamid].characterEyeHeight = DEFAULT_EYE_HEIGHT
		characterInfo[steamid].characterHeadToHmdDist = DEFAULT_HEAD_TO_HMD_DIST
		characterInfo[steamid].spineLen = (cm:GetPos().z + characterInfo[steamid].characterEyeHeight) - spinePos.z
		cm:Remove()
	end

	------------------------------------------------------------------------
	local function BoneCallbackFunc(ply, numbones)
		local steamid = ply:SteamID()
		if not activePlayers[steamid] or not g_VR.net[steamid].lerpedFrame or ply:InVehicle() and ply:GetVehicle():GetClass() ~= "prop_vehicle_prisoner_pod" then return end
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

	-------------------------------------------------------------
	local handYaw = 0
	local up = Vector(0, 0, 1)
	local function PreRenderFunc()
		if convars.vrmod_oldcharacteryaw:GetBool() then
			local unused, relativeAng = WorldToLocal(zeroVec, Angle(0, g_VR.tracking.hmd.ang.yaw, 0), zeroVec, Angle(0, g_VR.characterYaw, 0))
			if relativeAng.yaw > 45 then
				g_VR.characterYaw = g_VR.characterYaw + relativeAng.yaw - 45
			elseif relativeAng.yaw < -45 then
				g_VR.characterYaw = g_VR.characterYaw + relativeAng.yaw + 45
			end

			if g_VR.input.boolean_walk or g_VR.input.boolean_turnleft or g_VR.input.boolean_turnright then g_VR.characterYaw = g_VR.tracking.hmd.ang.yaw end
		else
			local leftPos, rightPos, hmdPos, hmdAng = g_VR.tracking.pose_lefthand.pos, g_VR.tracking.pose_righthand.pos, g_VR.tracking.hmd.pos, g_VR.tracking.hmd.ang
			if WorldToLocal(leftPos, zeroAng, hmdPos, hmdAng).y > WorldToLocal(rightPos, zeroAng, hmdPos, hmdAng).y then --update handYaw if hands are not crossed
				handYaw = Vector(rightPos.x - leftPos.x, rightPos.y - leftPos.y, 0):Angle().yaw + 90
			end

			local forwardAng = up:Cross(g_VR.tracking.hmd.ang:Right()):Angle()
			local _, tmp = WorldToLocal(zeroVec, Angle(0, handYaw, 0), zeroVec, forwardAng)
			local targetYaw = forwardAng.yaw + math.Clamp(tmp.yaw, -45, 45)
			local _, tmp = WorldToLocal(zeroVec, Angle(0, targetYaw, 0), zeroVec, Angle(0, g_VR.characterYaw, 0))
			local diff = tmp.yaw
			g_VR.characterYaw = math.NormalizeAngle(g_VR.characterYaw + diff * 8 * RealFrameTime())
		end
	end

	-------------------------------------------------------------
	local prevFrameNumber = 0
	local updatedPlayers = {}
	local function PrePlayerDrawFunc(ply)
		local steamid = ply:SteamID()
		if not activePlayers[steamid] or not g_VR.net[steamid].lerpedFrame then return end
		--hide head in first person
		if ply == LocalPlayer() then
			local ep = EyePos()
			local hide = (ep == g_VR.eyePosLeft or ep == g_VR.eyePosRight) and ply:GetViewEntity() == ply
			ply:ManipulateBoneScale(characterInfo[steamid].bones.b_head, hide and zeroVec or Vector(1, 1, 1))
		end

		characterInfo[steamid].preRenderPos = ply:GetPos()
		if not ply:InVehicle() then
			characterInfo[steamid].renderPos = g_VR.net[steamid].lerpedFrame.hmdPos + up:Cross(g_VR.net[steamid].lerpedFrame.hmdAng:Right()) * -characterInfo[steamid].characterHeadToHmdDist + Angle(0, g_VR.net[steamid].lerpedFrame.characterYaw, 0):Forward() * -characterInfo[steamid].horizontalCrouchOffset * 0.8
			characterInfo[steamid].renderPos.z = ply:GetPos().z - characterInfo[steamid].verticalCrouchOffset
			ply:SetPos(characterInfo[steamid].renderPos)
			ply:SetRenderAngles(Angle(0, g_VR.net[steamid].lerpedFrame.characterYaw, 0))
		end

		ply:SetupBones()
		--update ik once per frame per player
		if prevFrameNumber ~= FrameNumber() then
			prevFrameNumber = FrameNumber()
			updatedPlayers = {}
		end

		if not updatedPlayers[steamid] then
			UpdateIK(ply)
			updatedPlayers[steamid] = 1
		end

		--
		if ply:InVehicle() and ply:GetVehicle():GetClass() ~= "prop_vehicle_prisoner_pod" then return end
		--manipulate arms
		for i = 1, #characterInfo[steamid].boneorder do
			local bone = characterInfo[steamid].boneorder[i]
			if ply:GetBoneMatrix(bone) then --prevent unwritable bone errors (usually happens when someone opens pac editor while in vr and pac stuff in general)
				ply:SetBoneMatrix(bone, characterInfo[steamid].boneinfo[bone].targetMatrix)
			end
		end
	end

	-------------------------------------------------------------
	local function PostPlayerDrawFunc(ply)
		local steamid = ply:SteamID()
		if not activePlayers[steamid] or not g_VR.net[steamid].lerpedFrame or ply:InVehicle() then return end
		ply:SetPos(characterInfo[steamid].preRenderPos)
	end

	-------------------------------------------------------------
	local function CalcMainActivityFunc(ply, vel)
		if not activePlayers[ply:SteamID()] or ply:InVehicle() then return end
		local act = ACT_HL2MP_IDLE
		if ply.m_bJumping then
			act = ACT_HL2MP_JUMP_PASSIVE
			if CurTime() - ply.m_flJumpStartTime > 0.2 and ply:OnGround() then ply.m_bJumping = false end
		else
			local len2d = vel:Length2DSqr()
			if len2d > 22500 then
				act = ACT_HL2MP_RUN
			elseif len2d > 0.25 then
				act = ACT_HL2MP_WALK
			end
		end
		return act, -1
	end

	-------------------------------------------------------------
	local function DoAnimationEventFunc(ply, evt, data)
		if not activePlayers[ply:SteamID()] or ply:InVehicle() then return end
		if evt ~= PLAYERANIMEVENT_JUMP then return ACT_INVALID end
	end

	-------------------------------------------------------------
	function g_VR.StartCharacterSystem(ply)
		local steamid = ply:SteamID()
		lastModel = ply:GetModel()
		if not g_VR.net[steamid] or CharacterInit(ply) == false then return end
		characterInfo[steamid].boneCallback = ply:AddCallback("BuildBonePositions", BoneCallbackFunc)
		if ply == LocalPlayer() then hook.Add("VRMod_PreRender", "vrutil_hook_calcplyrenderpos", PreRenderFunc) end
		hook.Add("PrePlayerDraw", "vrutil_hook_preplayerdraw", PrePlayerDrawFunc)
		hook.Add("PostPlayerDraw", "vrutil_hook_postplayerdraw", PostPlayerDrawFunc)
		hook.Add("CalcMainActivity", "vrutil_hook_calcmainactivity", CalcMainActivityFunc)
		hook.Add("DoAnimationEvent", "vrutil_hook_doanimationevent", DoAnimationEventFunc)
		hook.Add("Think", "DetectLocalPlayerModelChange", function()
			local ply = LocalPlayer()
			if not IsValid(ply) or not vrmod.IsPlayerInVR(ply) then return end
			local mdl = ply:GetModel()
			if mdl ~= lastModel then
				lastModel = mdl
				g_VR.StopCharacterSystem(steamid)
				g_VR.StartCharacterSystem(ply)
			end
		end)

		activePlayers[steamid] = true
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
		g_VR.cache[steamid] = nil
		if table.Count(activePlayers) == 0 then
			hook.Remove("PrePlayerDraw", "vrutil_hook_preplayerdraw")
			hook.Remove("PostPlayerDraw", "vrutil_hook_postplayerdraw")
			hook.Remove("UpdateAnimation", "vrutil_hook_updateanimation")
			hook.Remove("CalcMainActivity", "vrutil_hook_calcmainactivity")
			hook.Remove("DoAnimationEvent", "vrutil_hook_doanimationevent")
			hook.Remove("Think", "DetectLocalPlayerModelChange")
		end

		print("VRMod: Stopped character system for " .. steamid)
	end

	hook.Add("VRMod_Start", "vrmod_characterstart", function(ply) g_VR.StartCharacterSystem(ply) end)
	hook.Add("VRMod_Exit", "vrmod_characterstop", function(ply, steamid) g_VR.StopCharacterSystem(steamid) end)
end