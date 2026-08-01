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

	-- Safe convar table (GetConvars can lag or return nil on first frames)
	local function CV()
		if istable(convarValues) then return convarValues end
		if vrmod.GetConvars then
			local c, v = vrmod.GetConvars()
			convars = c or convars
			convarValues = v
		end
		return istable(convarValues) and convarValues or {}
	end
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

	-- Body IK SoT: vrmod.charik (shared with avatar twin + flip). No dual math.
	local function UpdateIK(ply)
		local steamid = ply:SteamID()
		local net = g_VR.net[steamid]
		local charinfo = characterInfo[steamid]
		if not net or not charinfo or not net.lerpedFrame then return end
		local frame = net.lerpedFrame
		if lastFrames[steamid] and vrmod.utils.FramesAreEqual(frame, lastFrames[steamid]) then return end

		local charik = vrmod.charik
		if not charik or not charik.Update then return end

		local bones = charinfo.bones
		local inVehicle = ply:InVehicle()
		local veh = inVehicle and ply:GetVehicle() or nil
		local vehicleAng = IsValid(veh) and veh:GetAngles() or nil

		-- Alt head (ManipulateBoneAngles path — not SetBoneMatrix head)
		if net.characterAltHead and bones and bones.b_head and bones.b_head >= 0 and frame.hmdAng then
			local _, tmp2 = WorldToLocal(zeroVec, frame.hmdAng, zeroVec, Angle(0, frame.characterYaw or 0, 0))
			ply:ManipulateBoneAngles(bones.b_head, Angle(-tmp2.roll, -tmp2.pitch, tmp2.yaw))
		end

		charinfo.noStretch = false
		charinfo.headDampen = false
		-- Defaults so PrePlayerDraw never multiplies nil crouch offsets
		charinfo.horizontalCrouchOffset = charinfo.horizontalCrouchOffset or 0
		charinfo.verticalCrouchOffset = charinfo.verticalCrouchOffset or 0
		charik.Update(ply, charinfo, frame, {
			inVehicle = inVehicle,
			vehicleAng = vehicleAng,
			baseZ = (charinfo.preRenderPos and charinfo.preRenderPos.z) or ply:GetPos().z,
			eyeHeight = CV().characterEyeHeight or DEFAULT_EYE_HEIGHT,
			applyManip = true,
		})

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
		if not IsValid(ply) then return end
		local steamid = ply:SteamID()
		if not steamid or not activePlayers[steamid] then return end
		-- Guard each table: activePlayers can outlive net/characterInfo on exit/respawn
		local netTab = g_VR.net and g_VR.net[steamid]
		if not netTab or not netTab.lerpedFrame then return end
		local frame = netTab.lerpedFrame
		local ci = characterInfo[steamid]
		if not ci or not ci.bones then return end
		if ply:InVehicle() then
			local veh = ply:GetVehicle()
			if IsValid(veh) and veh:GetClass() ~= "prop_vehicle_prisoner_pod" then return end
		end
		if g_VR.fbtActive and g_VR.fbtActive[steamid] then return end

		local bones = ci.bones
		local rh = bones.b_rightHand
		if isnumber(rh) and rh >= 0 and frame.righthandPos and frame.righthandAng then
			if ply:GetBoneMatrix(rh) then
				ply:SetBonePosition(rh, frame.righthandPos, frame.righthandAng + RIGHT_HAND_OFFSET)
			end
		end
		if netTab.characterAltHead then return end
		if not frame.hmdAng then return end
		local head = bones.b_head
		if not isnumber(head) or head < 0 then return end
		local charik = vrmod.charik
		if charik and charik.ApplyHead then
			charik.ApplyHead(ply, ci, frame)
		else
			local _, targetAng = LocalToWorld(zeroVec, Angle(-80, 0, 90), zeroVec, frame.hmdAng)
			local mtx = ply:GetBoneMatrix(head)
			if mtx then
				mtx:SetAngles(targetAng)
				ply:SetBoneMatrix(head, mtx)
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

	local function TwinOpenLocal()
		return vrmod.avatar
			and (vrmod.avatar.IsOpen("avatar") or vrmod.avatar.IsOpen("default") or vrmod.avatar.IsOpen("fbt_cal"))
	end

	--- Always solve local player IK + publish snap when twin is open.
	-- PrePlayerDraw often does NOT run in VR first-person → twin got idle/T-pose bones.
	local function ForceLocalIKAndPublish()
		local ply = LocalPlayer()
		if not IsValid(ply) or not g_VR or not g_VR.active then return false end
		local steamid = ply:SteamID()
		if not steamid or not activePlayers[steamid] then return false end
		local netTab = g_VR.net and g_VR.net[steamid]
		if not netTab or not netTab.lerpedFrame then return false end
		local ci = characterInfo and characterInfo[steamid]
		if not ci or not ci.bones then
			if CharacterInit(ply) == false then return false end
			ci = characterInfo[steamid]
			if not ci then return false end
		end
		local frame = netTab.lerpedFrame

		-- Head fully visible for a clean snap
		local headBone = ci.bones.b_head
		if isnumber(headBone) and headBone >= 0 then
			ply:ManipulateBoneScale(headBone, Vector(1, 1, 1))
			ply:ManipulateBonePosition(headBone, zeroVec)
		end

		local cv = CV()
		local headToHmdDist = cv.characterHeadToHmdDist or DEFAULT_HEAD_TO_HMD_DIST
		ci.preRenderPos = ply:GetPos()
		local hCrouch = ci.horizontalCrouchOffset or 0
		local vCrouch = ci.verticalCrouchOffset or 0
		if not ply:InVehicle() and frame.hmdPos and frame.hmdAng then
			local yaw = frame.characterYaw or 0
			ci.renderPos = frame.hmdPos
				+ up:Cross(frame.hmdAng:Right()) * -headToHmdDist
				+ Angle(0, yaw, 0):Forward() * -hCrouch * 0.8
			ci.renderPos.z = ply:GetPos().z - vCrouch
			ply:SetPos(ci.renderPos)
			ply:SetRenderAngles(Angle(0, yaw, 0))
		end

		ply:SetupBones()
		pcall(UpdateIK, ply)
		if ci.boneorder and ci.boneinfo then
			for i = 1, #ci.boneorder do
				local bone = ci.boneorder[i]
				local bd = ci.boneinfo[bone]
				if bone and bd and bd.targetMatrix and ply:GetBoneMatrix(bone) then
					ply:SetBoneMatrix(bone, bd.targetMatrix)
				end
			end
		end
		-- Refresh full skeleton after arm matrix write
		ply:InvalidateBoneCache()
		ply:SetupBones()
		if ci.boneorder and ci.boneinfo then
			for i = 1, #ci.boneorder do
				local bone = ci.boneorder[i]
				local bd = ci.boneinfo[bone]
				if bone and bd and bd.targetMatrix and ply:GetBoneMatrix(bone) then
					ply:SetBoneMatrix(bone, bd.targetMatrix)
				end
			end
		end

		if vrmod.avatar and vrmod.avatar.PublishPlayerPose then
			pcall(vrmod.avatar.PublishPlayerPose, ply, frame)
		end
		-- Restore gameplay pos (same as PostPlayerDraw)
		if not (g_VR.vehicle and g_VR.vehicle.current) and ci.preRenderPos then
			ply:SetPos(ci.preRenderPos)
		end
		return true
	end

	vrmod.character = vrmod.character or {}
	vrmod.character.ForceLocalIKAndPublish = ForceLocalIKAndPublish

	-- Twin open: ONE player IK + pose publish per stereo frame (before either eye)
	hook.Add("VRMod_PreStereo", "vrmod_twin_force_ik", function()
		if not TwinOpenLocal() then return end
		pcall(ForceLocalIKAndPublish)
	end)

	------------------------------------------------------------------------
	local function PrePlayerDrawFunc(ply)
		if not IsValid(ply) then return end
		local steamid = ply:SteamID()
		if not steamid or not activePlayers[steamid] then return end
		local netTab = g_VR.net and g_VR.net[steamid]
		if not netTab or not netTab.lerpedFrame then return end
		local ci = characterInfo and characterInfo[steamid]
		if not ci or not ci.bones then return end
		local frame = netTab.lerpedFrame
		local cv = CV()
		local headToHmdDist = cv.characterHeadToHmdDist or DEFAULT_HEAD_TO_HMD_DIST
		-- Twin needs a real head matrix: never hide head while avatar twin is open.
		local twinOpen = ply == LocalPlayer() and TwinOpenLocal()
		if ply == LocalPlayer() then
			local headBone = ci.bones.b_head
			if isnumber(headBone) and headBone >= 0 then
				local ep = EyePos()
				local hide = (not twinOpen)
					and g_VR.eyePosLeft and g_VR.eyePosRight
					and (ep == g_VR.eyePosLeft or ep == g_VR.eyePosRight)
					and ply:GetViewEntity() == ply
				ply:ManipulateBoneScale(headBone, hide and zeroVec or Vector(1, 1, 1))
				ply:ManipulateBonePosition(headBone, hide and Vector(0, 20, 0) or zeroVec)
			end
		end

		ci.preRenderPos = ply:GetPos()
		local hCrouch = ci.horizontalCrouchOffset or 0
		local vCrouch = ci.verticalCrouchOffset or 0
		if not ply:InVehicle() and frame.hmdPos and frame.hmdAng then
			local yaw = frame.characterYaw or 0
			ci.renderPos = frame.hmdPos
				+ up:Cross(frame.hmdAng:Right()) * -headToHmdDist
				+ Angle(0, yaw, 0):Forward() * -hCrouch * 0.8
			ci.renderPos.z = ply:GetPos().z - vCrouch
			ply:SetPos(ci.renderPos)
			ply:SetRenderAngles(Angle(0, yaw, 0))
		end

		ply:SetupBones()
		if g_VR.fbtActive and g_VR.fbtActive[steamid] then
			return -- snap still taken in PostPlayerDraw after FBT bone apply
		end

		-- Once per stereoFrame (not FrameNumber): left/right eyes share one IK.
		-- Foregrip updates lefthand after NetUpdate; first eye must use attach pose.
		local sf = g_VR.stereoFrame or FrameNumber() or 0
		if prevFrameNumber ~= sf then
			prevFrameNumber = sf
			updatedPlayers = {}
		end

		if not updatedPlayers[steamid] then
			local ok, err = pcall(UpdateIK, ply)
			if not ok and vrmod.logger then
				vrmod.logger.Debug("UpdateIK: %s", tostring(err))
			end
			updatedPlayers[steamid] = 1
		end

		if ci.boneorder and ci.boneinfo then
			for i = 1, #ci.boneorder do
				local bone = ci.boneorder[i]
				local bd = ci.boneinfo[bone]
				if bone and bd and bd.targetMatrix and ply:GetBoneMatrix(bone) then
					ply:SetBoneMatrix(bone, bd.targetMatrix)
				end
			end
		end

		-- Publish as soon as IK matrices are on the player (twin may draw same frame)
		if twinOpen and vrmod.avatar and vrmod.avatar.PublishPlayerPose then
			pcall(vrmod.avatar.PublishPlayerPose, ply, frame)
		end
	end

	local function PostPlayerDrawFunc(ply)
		if not IsValid(ply) then return end
		local steamid = ply:SteamID()
		if activePlayers[steamid] == nil then return end
		local netTab = g_VR.net and g_VR.net[steamid]
		if not netTab or not netTab.lerpedFrame then return end
		if not characterInfo or not characterInfo[steamid] then return end

		-- After DrawModel/BoneCallback: refresh snap (head angles included)
		if ply == LocalPlayer() and vrmod.avatar and vrmod.avatar.PublishPlayerPose then
			if vrmod.avatar.IsOpen("avatar") or vrmod.avatar.IsOpen("default") or vrmod.avatar.IsOpen("fbt_cal") then
				pcall(vrmod.avatar.PublishPlayerPose, ply, netTab.lerpedFrame)
			end
		end

		if g_VR.vehicle and g_VR.vehicle.current then return end
		ply:SetPos(characterInfo[steamid].preRenderPos)
	end

	------------------------------------------------------------------------
	local function CalcMainActivityFunc(ply, vel)
		if not IsValid(ply) then return end
		local sid = ply:SteamID()
		if not sid or not activePlayers[sid] or ply:InVehicle() then return end
		-- When animations are disabled, force idle standing pose
		if not CV().characterIK then
			ply:SetPlaybackRate(0)
			ply:SetPoseParameter("move_yaw", 0)
			ply:SetPoseParameter("move_x", 0)
			ply:SetPoseParameter("move_y", 0)
			return ACT_HL2MP_IDLE, -1
		end

		local act = ACT_HL2MP_IDLE
		if ply.m_bJumping then
			act = ACT_HL2MP_JUMP_PASSIVE
			if CurTime() - (ply.m_flJumpStartTime or 0) > 0.2 and ply:OnGround() then ply.m_bJumping = false end
		else
			local l = vel and vel:Length2DSqr() or 0
			if l > 22500 then
				act = ACT_HL2MP_RUN
			elseif l > 0.25 then
				act = ACT_HL2MP_WALK
			end
		end
		return act, -1
	end

	local function DoAnimationEventFunc(ply, evt, data)
		if not IsValid(ply) then return end
		local sid = ply:SteamID()
		if not sid or not activePlayers[sid] or ply:InVehicle() then return end
		-- Block all animation events when animations are disabled
		if not CV().characterIK then return ACT_INVALID end
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
				local headBone = characterInfo[steamid].bones.b_head
				if isnumber(headBone) then
					ply:ManipulateBoneScale(headBone, Vector(1, 1, 1))
					ply:ManipulateBonePosition(headBone, zeroVec)
				end
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
