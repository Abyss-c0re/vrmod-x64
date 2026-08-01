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
		-- Incomplete PMs often lack clavicles — never crash on nil/-1 roots
		if not isnumber(parentbone) or parentbone < 0 then return end
		if not IsValid(ent) then return end
		local bones = notfirst and ent:GetChildBones(parentbone) or { parentbone }
		if not istable(bones) then return end
		for _, v in pairs(bones) do
			if not isnumber(v) or v < 0 then continue end
			local n = ent:GetBoneName(v)
			local boneparent = ent:GetBoneParent(v)
			local parentmat = isnumber(boneparent) and boneparent >= 0 and ent:GetBoneMatrix(boneparent) or nil
			local childmat = ent:GetBoneMatrix(v)
			if not parentmat or not childmat then continue end
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
		for _, v in pairs(bones) do
			if isnumber(v) and v >= 0 then
				RecursiveBoneTable2(ent, v, infotab, ordertab, true)
			end
		end
	end

	local function BoneDist(ent, a, b, fallback)
		if not isnumber(a) or a < 0 or not isnumber(b) or b < 0 then return fallback end
		local ok, pa, pb = pcall(function()
			local p1 = ent:GetBonePosition(a)
			local p2 = ent:GetBonePosition(b)
			return p1, p2
		end)
		if not ok or not pa or not pb then return fallback end
		local d = pa:Distance(pb)
		if not d or d < 0.5 or d ~= d then return fallback end
		return d
	end

	-- Bones required for VR body IK (wrists/ulnas optional)
	local REQUIRED_BONES = {
		"b_leftClavicle", "b_leftUpperarm", "b_leftForearm", "b_leftHand",
		"b_rightClavicle", "b_rightUpperarm", "b_rightForearm", "b_rightHand",
		"b_leftCalf", "b_leftThigh", "b_leftFoot",
		"b_rightCalf", "b_rightThigh", "b_rightFoot",
		"b_head", "b_spine",
	}

	-- Body IK SoT: vrmod.charik (shared with avatar twin + flip). No dual math.
	local function UpdateIK(ply)
		local steamid = ply:SteamID()
		local net = g_VR.net[steamid]
		local charinfo = characterInfo[steamid]
		if not net or not charinfo or not net.lerpedFrame then return end
		-- Incomplete skeleton: never run full arm IK (prevents nil bone math)
		if charinfo.incompatible or charinfo.ikReady == false then return end
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

	local function CharacterInit(ply, force)
		if not IsValid(ply) then return false end
		local steamid = ply:SteamID()
		if not steamid then return false end
		g_VR.cache = g_VR.cache or {}
		g_VR.cache[steamid] = g_VR.cache[steamid] or {}
		local pmname = ply.vrmod_pm or ply:GetModel() or ""
		if pmname == "" then return false end
		if not force and characterInfo[steamid] and characterInfo[steamid].modelName == pmname then
			return true
		end
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

		-- Drop previous callback before rebuild
		if characterInfo[steamid] and characterInfo[steamid].boneCallback and IsValid(ply) then
			pcall(function()
				ply:RemoveCallback("BuildBonePositions", characterInfo[steamid].boneCallback)
			end)
		end

		characterInfo[steamid] = {
			preRenderPos = Vector(0, 0, 0),
			renderPos = Vector(0, 0, 0),
			characterHeadToHmdDist = DEFAULT_HEAD_TO_HMD_DIST,
			characterEyeHeight = DEFAULT_EYE_HEIGHT,
			bones = { fingers = {} },
			boneinfo = {},
			boneorder = {},
			player = ply,
			boneCallback = 0,
			verticalCrouchOffset = 0,
			horizontalCrouchOffset = 0,
			ikReady = false,
			incompatible = false,
			missingBones = {},
			-- Safe limb defaults if PM is incomplete
			clavicleLen = 8,
			upperArmLen = 12,
			lowerArmLen = 12,
			upperLegLen = 16,
			lowerLegLen = 16,
			spineZ = 40,
			spineLen = 26,
		}

		local ci = characterInfo[steamid]
		pcall(function() ply:SetLOD(0) end)

		local cm
		local okCm, cmOrErr = pcall(ClientsideModel, pmname)
		if okCm and IsValid(cmOrErr) then
			cm = cmOrErr
		else
			if ply == LocalPlayer() then
				g_VR.errorText = "Could not load player model for VR body IK"
			end
			vrmod.logger.Warn("CharacterInit: ClientsideModel failed for %s (%s)", steamid, tostring(pmname))
			ci.incompatible = true
			ci.modelName = pmname
			return true -- no crash; system runs without IK
		end

		pcall(function()
			cm:SetPos(IsValid(LocalPlayer()) and LocalPlayer():GetPos() or Vector())
			cm:SetAngles(Angle(0, 0, 0))
			cm:SetupBones()
		end)

		local lClav = cm:LookupBone("ValveBiped.Bip01_L_Clavicle")
		local rClav = cm:LookupBone("ValveBiped.Bip01_R_Clavicle")
		pcall(RecursiveBoneTable2, cm, lClav, ci.boneinfo, ci.boneorder)
		pcall(RecursiveBoneTable2, cm, rClav, ci.boneinfo, ci.boneorder)
		for _, data in pairs(ci.boneinfo) do
			data.targetMatrix = data.targetMatrix or Matrix()
			data.pos = data.pos or Vector()
			data.ang = data.ang or Angle()
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

		local fingerNames = {
			"ValveBiped.Bip01_L_Finger0", "ValveBiped.Bip01_L_Finger01", "ValveBiped.Bip01_L_Finger02",
			"ValveBiped.Bip01_L_Finger1", "ValveBiped.Bip01_L_Finger11", "ValveBiped.Bip01_L_Finger12",
			"ValveBiped.Bip01_L_Finger2", "ValveBiped.Bip01_L_Finger21", "ValveBiped.Bip01_L_Finger22",
			"ValveBiped.Bip01_L_Finger3", "ValveBiped.Bip01_L_Finger31", "ValveBiped.Bip01_L_Finger32",
			"ValveBiped.Bip01_L_Finger4", "ValveBiped.Bip01_L_Finger41", "ValveBiped.Bip01_L_Finger42",
			"ValveBiped.Bip01_R_Finger0", "ValveBiped.Bip01_R_Finger01", "ValveBiped.Bip01_R_Finger02",
			"ValveBiped.Bip01_R_Finger1", "ValveBiped.Bip01_R_Finger11", "ValveBiped.Bip01_R_Finger12",
			"ValveBiped.Bip01_R_Finger2", "ValveBiped.Bip01_R_Finger21", "ValveBiped.Bip01_R_Finger22",
			"ValveBiped.Bip01_R_Finger3", "ValveBiped.Bip01_R_Finger31", "ValveBiped.Bip01_R_Finger32",
			"ValveBiped.Bip01_R_Finger4", "ValveBiped.Bip01_R_Finger41", "ValveBiped.Bip01_R_Finger42",
		}
		ci.bones.fingers = {}
		for i = 1, #fingerNames do
			ci.bones.fingers[i] = cm:LookupBone(fingerNames[i]) or -1
		end

		local missing = {}
		if ply == LocalPlayer() then g_VR.errorText = "" end
		for k, v in pairs(boneNames) do
			local bone = cm:LookupBone(v)
			if not isnumber(bone) then bone = -1 end
			ci.bones[k] = bone
			if bone < 0 and not string.find(k, "Wrist", 1, true) and not string.find(k, "Ulna", 1, true) then
				missing[#missing + 1] = v
			end
		end

		ci.missingBones = missing
		ci.incompatible = #missing > 0
		ci.ikReady = #missing == 0
		if #missing > 0 then
			local msg = "Incompatible player model (missing " .. #missing .. " bones, e.g. " .. missing[1] .. "). VR body IK limited."
			if ply == LocalPlayer() then g_VR.errorText = msg end
			vrmod.logger.Warn("CharacterInit soft-fail %s model=%s missing=%s", steamid, pmname, table.concat(missing, ", "))
			-- Do NOT StopCharacterSystem / return false — no crash, degraded IK only
		end

		ci.modelName = pmname
		local b = ci.bones
		ci.clavicleLen = BoneDist(cm, b.b_leftClavicle, b.b_leftUpperarm, 8)
		ci.upperArmLen = BoneDist(cm, b.b_leftUpperarm, b.b_leftForearm, 12)
		ci.lowerArmLen = BoneDist(cm, b.b_leftForearm, b.b_leftHand, 12)
		ci.upperLegLen = BoneDist(cm, b.b_leftThigh, b.b_leftCalf, 16)
		ci.lowerLegLen = BoneDist(cm, b.b_leftCalf, b.b_leftFoot, 16)
		ci.characterEyeHeight = DEFAULT_EYE_HEIGHT
		ci.characterHeadToHmdDist = DEFAULT_HEAD_TO_HMD_DIST
		if isnumber(b.b_spine) and b.b_spine >= 0 then
			local okSp, spinePos = pcall(function() return cm:GetBonePosition(b.b_spine) end)
			if okSp and spinePos then
				local baseZ = cm:GetPos().z
				ci.spineZ = spinePos.z - baseZ
				ci.spineLen = math.max(4, (baseZ + ci.characterEyeHeight) - spinePos.z)
			end
		end

		if IsValid(cm) then cm:Remove() end
		return true
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
	local charYawStereoFrame = -1
	local function PreRenderFunc()
		-- Per-eye hook: only update character yaw once per stereo pair
		local sf = g_VR.stereoFrame or 0
		if charYawStereoFrame == sf then return end
		charYawStereoFrame = sf

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

		-- Foregrip parks LH on the gun next to RH → L–R atan2 is near-singular and
		-- shakes full-body yaw (reads as left-hand flicker on FBT / avatar).
		if g_VR.foregripActive then
			if g_VR.input and (g_VR.input.boolean_walk or g_VR.input.boolean_turnleft or g_VR.input.boolean_turnright) then
				g_VR.characterYaw = g_VR.tracking.hmd.ang.yaw
			end
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
	-- Must run AFTER 0_vrmod_foregrip so lefthand is attach snap for stock two-hand.
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
		local sf = g_VR.stereoFrame or 0
		local canIK = not ci.incompatible and ci.ikReady ~= false

		-- Stock foregrip: force frame LH to frozen attach before any IK
		if canIK and g_VR.foregripActive and g_VR._leftHandSnapFrame == sf
			and g_VR._leftHandSnapPos and g_VR._leftHandSnapAng then
			frame.lefthandPos = Vector(g_VR._leftHandSnapPos.x, g_VR._leftHandSnapPos.y, g_VR._leftHandSnapPos.z)
			frame.lefthandAng = Angle(g_VR._leftHandSnapAng.p, g_VR._leftHandSnapAng.y, g_VR._leftHandSnapAng.r)
			lastFrames[steamid] = nil -- don't skip UpdateIK via FramesAreEqual
		end

		-- Head fully visible for a clean snap
		local headBone = ci.bones and ci.bones.b_head
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

		-- Incomplete PMs: skip body IK solve (still publish idle pose for twin)
		if canIK then
			-- FBT body: use FBT arm IK (not charik) so twin matches real body + foregrip
			local useFbt = g_VR.fbtActive and g_VR.fbtActive[steamid] and vrmod_fbt
				and vrmod_fbt.characterInfo and vrmod_fbt.characterInfo[steamid]
				and vrmod_fbt.CalculateBonePositions
			if useFbt then
				local info = vrmod_fbt.characterInfo[steamid]
				info.frameNumber = -1
				pcall(vrmod_fbt.CalculateBonePositions, ply)
				if info.boneinfo and info.boneCount then
					for i = 0, info.boneCount - 1 do
						local bi = info.boneinfo[i]
						if bi and bi.targetMatrix and ply:GetBoneMatrix(i) then
							ply:SetBoneMatrix(i, bi.targetMatrix)
						end
					end
				end
			else
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
			end
		end

		if vrmod.avatar and vrmod.avatar.PublishPlayerPose then
			-- Allow a fresh twin snap this stereo frame (foregrip may have just moved LH)
			if g_VR.avatarPoseSnap and g_VR.avatarPoseSnap.stereoFrame == sf then
				g_VR.avatarPoseSnap.stereoFrame = -1
			end
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

	-- Twin open: ONE player IK + pose publish per stereo frame (after 0_vrmod_foregrip)
	hook.Remove("VRMod_PreStereo", "vrmod_twin_force_ik") -- old name
	hook.Add("VRMod_PreStereo", "1_vrmod_twin_force_ik", function()
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
	function g_VR.StartCharacterSystem(ply, force)
		if not IsValid(ply) then return false end
		local steamid = ply:SteamID()
		local ok = CharacterInit(ply, force)
		if ok == false then return false end
		if not g_VR.net or not g_VR.net[steamid] then return false end
		if characterInfo and characterInfo[steamid] then
			if characterInfo[steamid].boneCallback then
				pcall(function()
					ply:RemoveCallback("BuildBonePositions", characterInfo[steamid].boneCallback)
				end)
			end
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
			return true
		end
		return false
	end

	--- Full character + FBT + twin snap reload after PM apply (player or twin→player).
	function g_VR.ReloadCharacterSystem(ply, reason)
		if not IsValid(ply) then return false end
		if not g_VR or not g_VR.active then return false end
		local sid = ply:SteamID()
		if not sid then return false end
		if vrmod.logger then
			vrmod.logger.Info("ReloadCharacterSystem %s (%s)", sid, tostring(reason or "pm"))
		end
		-- Invalidate caches so Init always rebuilds
		if characterInfo[sid] then characterInfo[sid].modelName = nil end
		if vrmod_fbt and vrmod_fbt.characterInfo and vrmod_fbt.characterInfo[sid] then
			vrmod_fbt.characterInfo[sid].modelName = nil
		end
		if g_VR.fbtActive then g_VR.fbtActive[sid] = nil end

		pcall(g_VR.StopCharacterSystem, sid)

		timer.Simple(0, function()
			if not IsValid(ply) or not g_VR or not g_VR.active then return end
			pcall(g_VR.StartCharacterSystem, ply, true)
			if vrmod_fbt and vrmod_fbt.Init then
				pcall(vrmod_fbt.Init, ply)
			end
			timer.Simple(0.05, function()
				if not IsValid(ply) or not g_VR or not g_VR.active then return end
				if vrmod.character and vrmod.character.ForceLocalIKAndPublish then
					pcall(vrmod.character.ForceLocalIKAndPublish)
				end
			end)
		end)
		return true
	end

	vrmod.character = vrmod.character or {}
	vrmod.character.Reload = function(ply, reason)
		return g_VR.ReloadCharacterSystem(ply or LocalPlayer(), reason)
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
