g_VR = g_VR or {}
local convars = vrmod.GetConvars()
if CLIENT then
	g_VR.scale = 0
	g_VR.origin = Vector(0, 0, 0)
	g_VR.rtWidth, g_VR.rtHeight = nil, nil
	g_VR.originAngle = Angle(0, 0, 0)
	g_VR.viewModel = nil
	g_VR.viewModelMuzzle = nil
	g_VR.viewModelPos = Vector(0, 0, 0)
	g_VR.viewModelAng = Angle(0, 0, 0)
	g_VR.active = false
	g_VR.threePoints = false --hmd + 2 controllers
	g_VR.sixPoints = false --hmd + 2 controllers + 3 trackers
	g_VR.tracking = {}
	g_VR.input = {}
	g_VR.changedInputs = {}
	g_VR.errorText = ""
	g_VR.moduleVersion = 0
	local hfovLeft, hfovRight
	local aspectLeft, aspectRight
	local leftCalc, rightCalc
	local ipd, eyez
	local cropVerticalMargin, cropHorizontalOffset
	local lastPosePos = {}
	local eyeOffset = nil
	local forwardOffset = nil
	local moduleFile
	local frameCounter = 0
	local prevRawHeadPos = Vector(0, 0, 0)
	local prevRawHeadTime = 0
	-- Desired values applied while VR is active.
	-- Do NOT include cvars on GMod's Blocked_ConCommands list (mat_reduceparticles,
	-- r_shadowrendertotexture, etc.) — Lua cannot change them without console spam.
	-- mat_queue_mode from vrmod_mat_queue_mode (0/1/2). Mode 2 is first-class:
	-- set once at VR start, never thrash workers mid-session; submit uses Lua RT size.
	local function WantedMatQueueMode()
		local cv = convars and convars.vrmod_mat_queue_mode
		if not cv and GetConVar then cv = GetConVar("vrmod_mat_queue_mode") end
		local n = cv and (cv.GetInt and cv:GetInt() or tonumber(cv:GetString())) or 2
		n = math.floor(tonumber(n) or 2)
		if n < 0 then n = 0 end
		if n > 2 then n = 2 end
		return n
	end

	local PERFORMANCE_CONVARS = {
		cl_threaded_bone_setup = "1",
		gmod_mcore_test = "1",
		-- Filled at VR start from WantedMatQueueMode()
		mat_queue_mode = "2",
		mat_disable_bloom = "1",
		mat_disable_fancy_blending = "1",
		mat_disable_lightwarp = "1",
		mat_disable_ps_patch = "1",
		mat_motion_blur_enabled = "0",
		mat_fastspecular = "0",
		r_3dsky = tostring(convars.vrmod_skybox:GetBool() and 1 or 0),
		r_threaded_particles = "1",
		r_queued_ropes = "1",
		-- Keep world + model decals on for both eye passes (stereo flicker if off/intermittent)
		r_drawdecals = "1",
		r_drawmodeldecals = "1",
		r_drawbatchdecals = "1",
		-- Glide WebAudio mutes entirely when the game window loses focus (ALVR/SteamVR).
		snd_mute_losefocus = "0",
	}
	-- mat_queue is set ONCE at start (re-SetInt every frame restarts workers → crash).
	-- Other pins can be re-asserted if needed.
	local SESSION_PIN_CONVARS = {
		-- mat_queue_mode deliberately NOT here
	}
	local matQueueAppliedForSession = false
	-- Stores original convar values so we can restore them on VR exit
	local convarOverrides = {}

	local wasPaused = false
	if system.IsLinux() then
		moduleFile = "lua/bin/gmcl_vrmod_linux64.dll"
	elseif system.IsWindows() then
		if file.Exists("lua/bin/gmcl_vrmod_win64.dll", "GAME") then
			moduleFile = "lua/bin/gmcl_vrmod_win64.dll"
		elseif file.Exists("lua/bin/gmcl_vrmod_win32.dll", "GAME") then
			moduleFile = "lua/bin/gmcl_vrmod_win32.dll"
		end
	else
		vrmod.logger.Err("Unsupported OS.")
	end

	if moduleFile then
		vrmod = vrmod or {}
		local success, err = pcall(function() require("vrmod") end)
		if success then
			for k, v in pairs(vrmod) do
				_G["VRMOD_" .. k] = v
			end

			g_VR.moduleVersion = VRMOD_GetVersion and VRMOD_GetVersion() or 0
		else
			vrmod.logger.Err("Failed to load module:", err)
		end
	else
		vrmod.logger.Err("No compatible module file found.")
	end

	-- 0) Helper functions
	-- Only ConVar setters — never RunConsoleCommand (GMod blacklists many engine cvars
	-- and prints "Command is blocked!" even when pcall'd).
	-- mat_queue_mode: 0 sync · 1 queued single-thread (safe) · 2 multithreaded (opt-in).
	local function setConvarValue(name, value)
		local cv = GetConVar(name)
		if not cv then return false end
		value = tostring(value)
		local ok = pcall(function()
			-- Prefer SetInt for numeric engine cvars (mat_queue_mode is an int)
			local n = tonumber(value)
			if n ~= nil and cv.SetInt then
				cv:SetInt(n)
			else
				cv:SetString(value)
			end
		end)
		if not ok then
			-- Fallback SetString only
			ok = pcall(function() cv:SetString(value) end)
		end
		if not ok then
			vrmod.logger.Debug("Could not set convar: " .. name)
			return false
		end
		return true
	end

	local function convarMatches(cv, want)
		if not cv then return false end
		want = tostring(want)
		if cv:GetString() == want then return true end
		local wn, gn = tonumber(want), tonumber(cv:GetString())
		if wn ~= nil and gn ~= nil and wn == gn then return true end
		if cv.GetInt and wn ~= nil and cv:GetInt() == wn then return true end
		return false
	end

	local function RefreshMatQueuePin()
		PERFORMANCE_CONVARS.mat_queue_mode = tostring(WantedMatQueueMode())
	end

	local function overrideConvar(name, value)
		local cv = GetConVar(name)
		if not cv then return end
		local previous = cv:GetString()
		if not setConvarValue(name, value) then return end
		-- Remember original so VR exit can restore (including mat_queue_mode).
		if convarOverrides[name] == nil then
			convarOverrides[name] = previous
		end
	end

	local function restoreConvarOverrides()
		-- Drain Source material workers before restoring mat_queue (avoids
		-- "Illegal termination of worker thread" on VR exit under mode 2).
		if convarOverrides["mat_queue_mode"] ~= nil then
			setConvarValue("mat_queue_mode", "0")
		end
		for k, v in pairs(convarOverrides) do
			setConvarValue(k, v)
		end
		convarOverrides = {}
	end

	-- Push authoritative SBS RT size to the module (mat_queue 2 cannot query GL size).
	local function PushKnownSubmitSize()
		if not isfunction(VRMOD_SetKnownSubmitSize) then return end
		local w = tonumber(g_VR.rtWidth)
		local h = tonumber(g_VR.rtHeight)
		if w and h and w >= 32 and h >= 32 then
			pcall(VRMOD_SetKnownSubmitSize, w, h)
		end
	end

	-- While VR is active: do NOT re-set mat_queue_mode every frame (worker thrash).
	local function EnsurePinnedConvars()
		if not g_VR.active then return end
		PushKnownSubmitSize()
		for name, _ in pairs(SESSION_PIN_CONVARS) do
			local want = PERFORMANCE_CONVARS[name]
			if want ~= nil then
				local cv = GetConVar(name)
				if cv and not convarMatches(cv, want) then
					setConvarValue(name, want)
				end
			end
		end
	end

	-- Module capability gates (Lua must never require new exports that ancient modules lack).
	-- v23+: ShareTextureBegin(eyeW, eyeH) optional args + raw HMD rec (crisp SS path).
	-- Older: ShareTextureBegin() only; RT size must match module-owned OUT.
	local MODULE_SS_EYE_ARGS = 23

	local function ModuleSupportsEyeSizeArgs()
		return (g_VR.moduleVersion or 0) >= MODULE_SS_EYE_ARGS
	end

	local function SafeShareTextureBegin(eyeW, eyeH)
		if not isfunction(VRMOD_ShareTextureBegin) then return false end
		if ModuleSupportsEyeSizeArgs() and eyeW and eyeH then
			-- New module: optional numbers; no new API name
			return pcall(VRMOD_ShareTextureBegin, eyeW, eyeH)
		end
		-- Ancient / mid: no args — module sizes from its own recommendation
		return pcall(VRMOD_ShareTextureBegin)
	end

	local function SafeShareTextureFinish()
		if not isfunction(VRMOD_ShareTextureFinish) then return false end
		return pcall(VRMOD_ShareTextureFinish)
	end

	local function ComputeDisplayParams()
		local viewscale = convars.vrmod_viewscale:GetFloat()
		local fovX, fovY = convars.vrmod_fovscale_x:GetFloat(), convars.vrmod_fovscale_y:GetFloat()
		if not isfunction(VRMOD_GetDisplayInfo) then
			return nil
		end
		local di = VRMOD_GetDisplayInfo(1, 10)
		if not di then return nil end
		-- Recommended per-eye from module (raw on v23+, pre-clamped on ancient)
		local eyeW = tonumber(di.RecommendedWidth) or 1024
		local eyeH = tonumber(di.RecommendedHeight) or 1024
		local ss = 1.0
		if convars.vrmod_supersample then
			ss = math.Clamp(convars.vrmod_supersample:GetFloat(), 0.5, 2.0)
		end
		local canSS = ModuleSupportsEyeSizeArgs()
		if canSS then
			-- Full crisp path: SS then one 4096 SBS clamp; pass size into ShareTextureBegin
			eyeW = math.floor(eyeW * ss + 0.5)
			eyeH = math.floor(eyeH * ss + 0.5)
			local maxDim = 4096
			local sbsW = eyeW * 2
			if sbsW > maxDim or eyeH > maxDim then
				local scale = math.min(maxDim / sbsW, maxDim / eyeH)
				eyeW = math.max(16, math.floor(eyeW * scale))
				eyeH = math.max(16, math.floor(eyeH * scale))
			end
		else
			-- Ancient module: OUT texture is sized inside the module. Oversizing the
			-- engine RT causes mismatch / stretch / potato — ignore SS size bumps.
			if ss ~= 1.0 and vrmod.logger then
				vrmod.logger.Info(
					"vrmod_supersample=%.2f ignored (module v%d; need v%d+ modules.zip for SS)",
					ss, g_VR.moduleVersion or 0, MODULE_SS_EYE_ARGS
				)
			end
			ss = 1.0
		end
		-- Even dimensions help some GPU / blit paths
		eyeW = math.max(16, math.floor(eyeW / 2) * 2)
		eyeH = math.max(16, math.floor(eyeH / 2) * 2)
		local sbsW = eyeW * 2
		local rawW, rawH = sbsW, eyeH

		local leftProj = vrmod.utils.AdjustFOV(di.ProjectionLeft, fovX, fovY)
		local rightProj = vrmod.utils.AdjustFOV(di.ProjectionRight, fovX, fovY)
		local leftCalc = vrmod.utils.CalculateProjectionParams(leftProj, viewscale)
		local rightCalc = vrmod.utils.CalculateProjectionParams(rightProj, viewscale)

		local ipd = di.TransformRight and di.TransformRight[1] and di.TransformRight[1][4] and (di.TransformRight[1][4] * 2) or 0.064
		local eyez = di.TransformRight and di.TransformRight[3] and di.TransformRight[3][4] or 0
		if vrmod.logger then
			vrmod.logger.Info(
				"Display RT SBS %dx%d (eye %dx%d, SS=%.2f, module v%d%s)",
				rawW, rawH, eyeW, eyeH, ss, g_VR.moduleVersion or 0,
				canSS and ", eyeArgs" or ", legacy"
			)
		end
		return {
			rtW = rawW,
			rtH = rawH,
			eyeW = eyeW,
			eyeH = eyeH,
			passEyeArgs = canSS,
			leftCalc = leftCalc,
			rightCalc = rightCalc,
			hfovL = leftCalc.HorizontalFOV,
			hfovR = rightCalc.HorizontalFOV,
			aspL = leftCalc.AspectRatio,
			aspR = rightCalc.AspectRatio,
			ipd = ipd,
			eyez = eyez
		}
	end

	-- ═══════════════════════════════════════════════════════════════════════
	-- Cube's Law — Truth Matrix (pose + stereo render)
	-- ─────────────────────────────────────────────────────────────────────
	-- Pose SoT (one truth, energy flows downward only):
	--   rawTracking  = device energy (unfiltered; modifiers never own this)
	--   tracking     = Source of Truth for all consumers (stable tables)
	--   VRMod_Tracking → early modifiers (seated, crouch, sim hands…)
	--   ApplyPoseModifiers → wall/weapon → write only into tracking hands
	--   viewmodel / net / character / melee → read tracking only
	--
	-- Stereo SoT (one public view, dual eye energy):
	--   g_VR.view     = cyclopean public SoT (origin/angles/znear for consumers)
	--   viewLeft/Right= private eye viewsetups (no realloc, no dual gun truth)
	--   PreRender(eye) → RealRenderView(eye) → ClearDepth → other eye → submit
	-- Integrity:
	--   • Never nil-out hmd / pose_lefthand / pose_righthand mid-session
	--   • Never invent a second parallel gun/hand or eye pose truth
	--   • angvel is Vector(p,y,r); never Angle:Set(Vector)
	--   • Stable Cube beats clever Cube — no thrash, no nested portal RTs
	-- ═══════════════════════════════════════════════════════════════════════

	--- In-place Vector write (no per-frame Vector() thrash on the hot path)
	local function WriteVec(dst, src)
		if not src then
			if not dst then return Vector() end
			dst.x, dst.y, dst.z = 0, 0, 0
			return dst
		end
		local x = src.x
		if x == nil then
			-- Angle-like (p/y/r) used as angvel carrier
			x = src.p or src.pitch or 0
			local y = src.y or src.yaw or 0
			local z = src.r or src.roll or 0
			if not dst then return Vector(x, y, z) end
			dst.x, dst.y, dst.z = x, y, z
			return dst
		end
		if not dst then return Vector(x, src.y or 0, src.z or 0) end
		dst.x, dst.y, dst.z = x, src.y or 0, src.z or 0
		return dst
	end

	local function WriteAng(dst, src)
		if not src then
			if not dst then return Angle() end
			dst.p, dst.y, dst.r = 0, 0, 0
			return dst
		end
		local p = src.p or src.pitch
		if p ~= nil then
			local y = src.y or src.yaw or 0
			local r = src.r or src.roll or 0
			if not dst then return Angle(p, y, r) end
			dst.p, dst.y, dst.r = p, y, r
			return dst
		end
		-- Vector mistaken for angle
		local px, py, pz = src.x or 0, src.y or 0, src.z or 0
		if not dst then return Angle(px, py, pz) end
		dst.p, dst.y, dst.r = px, py, pz
		return dst
	end

	local function CopyPoseFields(src, dst)
		dst = dst or {}
		dst.pos = WriteVec(dst.pos, src.pos)
		dst.ang = WriteAng(dst.ang, src.ang)
		dst.vel = WriteVec(dst.vel, src.vel)
		dst.angvel = WriteVec(dst.angvel, src.angvel)
		dst.simulatedPos = src.simulatedPos
		return dst
	end

	local function CopyRawIntoTracking()
		g_VR.rawTracking = g_VR.rawTracking or {}
		g_VR.tracking = g_VR.tracking or {}
		-- Only OVERWRITE keys present this frame. Never delete pose_lefthand /
		-- pose_righthand / hmd when a sample is briefly missing — consumers
		-- (melee, character, UI) assume those tables stay alive for the session.
		for k, rawPose in pairs(g_VR.rawTracking) do
			g_VR.tracking[k] = CopyPoseFields(rawPose, g_VR.tracking[k])
		end
	end

	-- ALWAYS clone Vectors — never store the same Vector in two poses.
	-- EmptyPose(origin) for both hands with shared `origin` glued L/R forever.
	local function EmptyPose(pos)
		local p
		if pos then
			p = Vector(pos.x or 0, pos.y or 0, pos.z or 0)
		else
			p = Vector()
		end
		return {
			pos = p,
			ang = Angle(),
			vel = Vector(),
			angvel = Vector()
		}
	end

	--- Ensure two pose tables never share Vector/Angle identity (runtime heal).
	-- Workshop: "hands stuck together" / "hands tied" — shared Vector identity or
	-- collision collapse to same world point. Heal identity always; if positions
	-- coincide but raw still has separation, restore from raw.
	local function EnsurePoseIndependence()
		local tr = g_VR.tracking
		if not tr then return end
		local L, R, H = tr.pose_lefthand, tr.pose_righthand, tr.hmd
		local raw = g_VR.rawTracking
		local rL = raw and raw.pose_lefthand
		local rR = raw and raw.pose_righthand

		local function cloneVec(v)
			return Vector(v.x, v.y, v.z)
		end
		local function cloneAng(a)
			return Angle(a.p, a.y, a.r)
		end

		-- 1) Identity glue (same userdata) — always split
		if L and R and L.pos and R.pos and L.pos == R.pos then
			R.pos = cloneVec(R.pos)
			if vrmod.logger then
				vrmod.logger.Warn("Healed glued hand pos identity (L==R Vector)")
			end
		end
		if L and R and L.ang and R.ang and L.ang == R.ang then
			R.ang = cloneAng(R.ang)
		end
		if H and L and H.pos and L.pos and H.pos == L.pos then
			L.pos = cloneVec(L.pos)
		end
		if H and R and H.pos and R.pos and H.pos == R.pos then
			R.pos = cloneVec(R.pos)
		end
		if rL and rR and rL.pos and rR.pos and rL.pos == rR.pos then
			rR.pos = cloneVec(rR.pos)
		end
		if rL and rR and rL.ang and rR.ang and rL.ang == rR.ang then
			rR.ang = cloneAng(rR.ang)
		end

		-- 2) Value collapse: L/R nearly same world pos but raw is separated → un-stick
		-- Skip while stock foregrip owns left hand (attach may sit near RH on short guns).
		if not g_VR.foregripActive and L and R and L.pos and R.pos and rL and rR and rL.pos and rR.pos then
			local trackDist = L.pos:DistToSqr(R.pos)
			local rawDist = rL.pos:DistToSqr(rR.pos)
			if trackDist < 4 and rawDist > 36 then -- <2u glued, raw >6u apart
				L.pos.x, L.pos.y, L.pos.z = rL.pos.x, rL.pos.y, rL.pos.z
				R.pos.x, R.pos.y, R.pos.z = rR.pos.x, rR.pos.y, rR.pos.z
				if rL.ang and L.ang then
					L.ang.p, L.ang.y, L.ang.r = rL.ang.p, rL.ang.y, rL.ang.r
				end
				if rR.ang and R.ang then
					R.ang.p, R.ang.y, R.ang.r = rR.ang.p, rR.ang.y, rR.ang.r
				end
				if vrmod.logger then
					vrmod.logger.Warn("Unstuck hands from rawTracking (track collapsed, raw separated)")
				end
			end
		end
	end

	local function UpdateTracking()
		local smoothingFactor = vrmod.SMOOTHING_FACTOR
		local maxPosDeltaSqr = 100
		-- Frame order (OpenVR): WaitGetPoses → render → Submit. Never invert.
		if isfunction(VRMOD_UpdatePosesAndActions) then
			pcall(VRMOD_UpdatePosesAndActions)
		end
		local rawPoses = (isfunction(VRMOD_GetPoses) and VRMOD_GetPoses()) or {}
		if not istable(rawPoses) then rawPoses = {} end
		g_VR.rawTracking = g_VR.rawTracking or {}

		for k, v in pairs(rawPoses) do
			if not v or not v.pos then continue end
			local lastPos = lastPosePos[k]
			local currentPos = v.pos
			-- Clamp teleport spikes (defensive: never let missing utils kill the frame)
			if lastPos and currentPos then
				local okClamp, newPos = pcall(function()
					local delta = vrmod.utils.SubVec(currentPos, lastPos)
					local deltaLenSqr = vrmod.utils.LengthSqr(delta)
					if deltaLenSqr > maxPosDeltaSqr then
						local deltaLen = math.sqrt(deltaLenSqr)
						local scale = maxPosDeltaSqr / math.max(deltaLen, 0.0001)
						local clampedDelta = (vrmod.utils.MulVec and vrmod.utils.MulVec(delta, scale))
							or Vector(delta.x * scale, delta.y * scale, delta.z * scale)
						local out = (vrmod.utils.AddVec and vrmod.utils.AddVec(lastPos, clampedDelta))
							or (lastPos + clampedDelta)
						if vrmod.logger then
							vrmod.logger.Warn("Pose %s exceeded max delta, clamped.", k)
						end
						return out
					end
					return currentPos
				end)
				if okClamp and newPos then currentPos = newPos end
			end

			lastPosePos[k] = currentPos
			g_VR.rawTracking[k] = g_VR.rawTracking[k] or {}
			local rawPose = g_VR.rawTracking[k]
			local pos, ang = LocalToWorld(currentPos * g_VR.scale, v.ang, g_VR.origin, g_VR.originAngle)
			if k == "pose_righthand" or k == "pose_lefthand" then
				-- Smooth only the raw stream (tracking is re-copied each frame)
				rawPose.pos = rawPose.pos and vrmod.utils.SmoothVector(rawPose.pos, pos, smoothingFactor) or pos
				rawPose.ang = rawPose.ang and vrmod.utils.SmoothAngle(rawPose.ang, ang, smoothingFactor) or ang
			else
				rawPose.pos = pos
				rawPose.ang = ang
			end

			-- Head velocity from RAW device sample (not post-modifier tracking)
			if k == "hmd" then
				local now = CurTime()
				if prevRawHeadTime > 0 then
					local dt = now - prevRawHeadTime
					if dt > 0 then
						local rawDelta = currentPos - prevRawHeadPos
						local rawVel = rawDelta / dt
						vrmod.cachedHeadPose.vel = LocalToWorld(rawVel, Angle(0, 0, 0), vector_origin, g_VR.originAngle) * g_VR.scale
						if v.angvel then
							local rawAngVel = Vector(v.angvel.pitch, v.angvel.yaw, v.angvel.roll)
							vrmod.cachedHeadPose.angvel = LocalToWorld(rawAngVel, Angle(0, 0, 0), vector_origin, g_VR.originAngle)
						end
					end
				end

				prevRawHeadPos = currentPos
				prevRawHeadTime = now
			end

			rawPose.vel = LocalToWorld(v.vel, Angle(0, 0, 0), vector_origin, g_VR.originAngle) * g_VR.scale
			rawPose.angvel = LocalToWorld(Vector(v.angvel.pitch, v.angvel.yaw, v.angvel.roll), Angle(0, 0, 0), vector_origin, g_VR.originAngle)
			local isRight = k == "pose_righthand"
			local isLeft = k == "pose_lefthand"
			if isRight or isLeft then
				local offsetPos = (isRight and g_VR.rightControllerOffsetPos or g_VR.leftControllerOffsetPos) * 0.01 * g_VR.scale
				local offsetAng = isRight and g_VR.rightControllerOffsetAng or g_VR.leftControllerOffsetAng
				local offsetWorldPos, offsetWorldAng = LocalToWorld(offsetPos, offsetAng, vector_origin, rawPose.ang)
				rawPose.pos = rawPose.pos + offsetWorldPos
				rawPose.ang = offsetWorldAng
			end
		end

		-- Reset public tracking from raw every frame, then run early modifiers
		CopyRawIntoTracking()
		EnsurePoseIndependence()
		g_VR.sixPoints = (g_VR.tracking.pose_waist and g_VR.tracking.pose_leftfoot and g_VR.tracking.pose_rightfoot) and true or false
		-- Early modifiers (seated offset, crouch, hand simulation…) may edit g_VR.tracking
		hook.Call("VRMod_Tracking")
	end

	--- Write pose into an existing tracking table field (preserve Vector/Angle identity for consumers)
	local function WritePose(dst, pos, ang)
		if not dst then return end
		if pos then
			if dst.pos and dst.pos.Set then
				dst.pos:Set(pos)
			else
				dst.pos = pos
			end
		end
		if ang then
			if dst.ang and dst.ang.Set then
				dst.ang:Set(ang)
			else
				dst.ang = ang
			end
		end
	end

	--- Late pose modifiers: OVERRIDE g_VR.tracking hands in place.
	--- rawTracking stays pure device energy (guns/addons that read tracking see the block;
	--- nobody needs the API — the tables themselves are the SoT).
	local function ApplyPoseModifiers()
		local left = g_VR.tracking and g_VR.tracking.pose_lefthand
		local right = g_VR.tracking and g_VR.tracking.pose_righthand
		if not (left and right and vrmod.utils and left.pos and right.pos and left.ang and right.ang) then return end
		frameCounter = frameCounter + 1
		if vrmod.utils.CollisionsPreCheck then
			vrmod.utils.CollisionsPreCheck(left.pos, right.pos)
		end

		-- Zero-arg: mutates g_VR.tracking.pose_*.pos in place (Cube SoT).
		-- Passing explicit Vector copies would break identity for gun readers.
		vrmod.utils.UpdateHandCollisions()
		-- Collisions can re-glue L/R if a path assigns one Vector to both — re-heal.
		EnsurePoseIndependence()

		hook.Call("VRMod_TrackingModified", nil, g_VR.tracking, g_VR.rawTracking)

		-- Viewmodel / gun mesh slaves tracking SoT only (never rawTracking).
		-- Weapon tip wall already ran in UpdateHandCollisions — no second muzzle TraceLine
		-- here (that doubled SetupBones + traces and spiked latency).
		if vrmod.utils.UpdateViewModelPos then
			vrmod.utils.UpdateViewModelPos(right.pos, right.ang)
		elseif vrmod.utils.UpdateViewModel then
			vrmod.utils.UpdateViewModel()
		end
	end

	-- OpenXR: optional Lua remaps (cl_openxr_bindings) over native GetActions.
	local function ApplyOpenXRBindings(input, changed)
		input = input or {}
		changed = type(changed) == "table" and changed or {}
		if not (vrmod.bindings and vrmod.bindings.Apply and vrmod.bindings.GetSources) then
			return input, changed
		end
		local sources = vrmod.bindings.GetSources()
		if not sources then return input, changed end
		local ok, a, b = pcall(vrmod.bindings.Apply, input, changed, sources)
		if ok and type(a) == "table" then
			return a, type(b) == "table" and b or changed
		end
		return input, changed
	end

	local function HandleInput()
		local input, changed = VRMOD_GetActions()
		input, changed = ApplyOpenXRBindings(input, changed)
		g_VR.input = input or {}
		g_VR.changedInputs = type(changed) == "table" and changed or {}
		for k, v in pairs(g_VR.changedInputs) do
			hook.Call("VRMod_Input", nil, k, v)
		end
	end

	local function DrawErrorOverlay()
		local isPaused = not system.HasFocus() or #g_VR.errorText > 0
		if isPaused then
			render.Clear(0, 0, 0, 255, true, true)
			cam.Start2D()
			local text = not system.HasFocus() and "Please focus the game window" or g_VR.errorText
			draw.DrawText(text, "DermaLarge", ScrW() / 2, ScrH() / 2, Color(255, 255, 255, 255), TEXT_ALIGN_CENTER)
			cam.End2D()
			g_VR.active = false
			-- Only log on state change
			if not wasPaused then vrmod.logger.Info("VR session paused") end
			wasPaused = true
			return true
		else
			g_VR.active = true
			-- Only log unpause on state change
			if wasPaused then vrmod.logger.Info("VR session resumed") end
			wasPaused = false
		end
	end

	local function UpdateViewFromEntity()
		local ply = LocalPlayer()
		if not IsValid(ply) then return end
		local viewEnt = ply:GetViewEntity()
		if not IsValid(viewEnt) then return end
		local hmd = g_VR.tracking.hmd
		if not hmd then return end
		-- Transform HMD to VR origin local space
		local rawPos, rawAng = WorldToLocal(hmd.pos, hmd.ang, g_VR.origin, g_VR.originAngle)
		-- Base position and angle
		local finalPos, finalAng = hmd.pos, hmd.ang
		-- If we are viewing through an entity (not player), apply offset
		if viewEnt ~= ply then
			local vePos = viewEnt:GetPos()
			local veAng = viewEnt:GetAngles()
			finalPos, finalAng = LocalToWorld(rawPos, rawAng, vePos, veAng)
		end

		-- Detect Glide vehicle and apply small lift/forward
		if g_VR.vehicle.glide then
			local forward = g_VR.view.angles:Forward() -- view/vehicle facing direction
			local up = g_VR.view.angles:Up()
			if g_VR.vehicle.type == "motorcycle" then
				-- Move 6 units forward instead of just down
				g_VR.view.origin = finalPos + forward * 8 + up * 3
			else
				-- Move slightly forward and up
				g_VR.view.origin = finalPos + forward * 6 + up * 6
			end

			g_VR.tracking.pose_lefthand.pos = g_VR.tracking.pose_lefthand.pos + forward * 5
			g_VR.tracking.pose_righthand.pos = g_VR.tracking.pose_righthand.pos + forward * 5
		else
			g_VR.view.origin = finalPos
		end

		g_VR.view.angles = finalAng
	end



	-- Persistent eye viewsetups (no table alloc per frame — Cube stability)
	-- drawmonitors MUST be false: monitors nest RenderView while we hold g_VR.rt → heap corruption
	-- Explicit zfar: nested RenderView (radar etc.) can leave a short far plane on the
	-- engine; eye views must always reassert a full distance or the world clips early.
	local VIEW_ZFAR = 32768
	local viewLeft = {
		x = 0, y = 0, w = 0, h = 0,
		origin = nil, angles = nil,
		fov = 90, aspectratio = 1,
		drawmonitors = false,
		drawviewmodel = false,
		drawhud = false,
		bloomtone = false,
		dopostprocess = false,
		znear = 1,
		zfar = VIEW_ZFAR,
	}
	local viewRight = {
		x = 0, y = 0, w = 0, h = 0,
		origin = nil, angles = nil,
		fov = 90, aspectratio = 1,
		drawmonitors = false,
		drawviewmodel = false,
		drawhud = false,
		bloomtone = false,
		dopostprocess = false,
		znear = 1,
		zfar = VIEW_ZFAR,
	}

	-- Freeze evidence (14:21): malloc unsorted double-linked list + empty .txt —
	-- same class as 12:52 WorldPortals RealRenderView nest. Nested RenderView while
	-- PushRenderTarget(g_VR.rt) corrupts the engine RT stack / heap.
	local renderingEyes = false
	local worldPortalsPatched = false
	local engineRenderView -- never the WorldPortals wrapper
	local wpRenderSceneFn -- saved to restore on VR exit
	local wpDrawingSaved

	local function CaptureEngineRenderView()
		-- Prefer RealRenderView (WorldPortals saves engine fn there before wrap)
		if isfunction(render.RealRenderView) then
			engineRenderView = render.RealRenderView
			return engineRenderView
		end
		if not engineRenderView and isfunction(render.RenderView) then
			-- Only safe before WorldPortals wraps; if already wrapped, still better than nil
			engineRenderView = render.RenderView
		end
		return engineRenderView
	end

	-- Capture ASAP (before Doors/WorldPortals InitPostEntity re-wrap if possible)
	CaptureEngineRenderView()
	hook.Add("InitPostEntity", "vrmod_capture_engine_renderview", function()
		-- After WP: RealRenderView should exist
		if isfunction(render.RealRenderView) then
			engineRenderView = render.RealRenderView
		end
	end)

	local function InstallWorldPortalsVRGuard()
		local wp = rawget(_G, "wp")
		if istable(wp) and isfunction(wp.renderportals) and not wp._vrmodRenderGuard then
			wp._vrmodRenderGuard = true
			local orig = wp.renderportals
			wp.renderportals = function(...)
				if g_VR.active or renderingEyes then return end
				return orig(...)
			end
			worldPortalsPatched = true
			if vrmod.logger then
				vrmod.logger.Info("World Portals: VR stereo guard installed")
			end
		end

		-- Kill WP's own RenderScene pass while VR owns the frame (nests full-screen RenderViews)
		local sceneHooks = hook.GetTable()["RenderScene"]
		if sceneHooks and isfunction(sceneHooks["WorldPortals_Render"]) and not wpRenderSceneFn then
			wpRenderSceneFn = sceneHooks["WorldPortals_Render"]
			hook.Remove("RenderScene", "WorldPortals_Render")
		end
	end

	local function BeginVRNestedRenderLock()
		InstallWorldPortalsVRGuard()
		CaptureEngineRenderView()
		local wp = rawget(_G, "wp")
		if istable(wp) then
			if wpDrawingSaved == nil then
				wpDrawingSaved = wp.drawing
			end
			-- drawing=true means "already drawing / skip portal work" in WorldPortals
			wp.drawing = true
		end
	end

	local function EndVRNestedRenderLock()
		local wp = rawget(_G, "wp")
		if istable(wp) and wpDrawingSaved ~= nil then
			wp.drawing = wpDrawingSaved
			wpDrawingSaved = nil
		end
		if wpRenderSceneFn then
			hook.Add("RenderScene", "WorldPortals_Render", wpRenderSceneFn)
			wpRenderSceneFn = nil
		end
	end

	local function GetEngineRenderView()
		if isfunction(render.RealRenderView) then
			return render.RealRenderView
		end
		if engineRenderView then
			return engineRenderView
		end
		-- Last resort — may be wrapped; still better than nil
		return render.RenderView
	end

	--- Reset GPU state that PostDrawEffects / halos / HUD can leave dirty between eyes.
	--- Dirty stencil, DepthRange, or blend is a common source of decal + prop flicker in SBS VR.
	local function ResetStereoEyeState()
		pcall(function()
			render.SetStencilEnable(false)
			render.SetStencilTestMask(0)
			render.SetStencilWriteMask(0)
			render.SetStencilReferenceValue(0)
			render.SuppressEngineLighting(false)
			render.SetBlend(1)
			if render.OverrideDepthEnable then render.OverrideDepthEnable(false, false) end
			if render.OverrideBlend then render.OverrideBlend(false) end
			if render.OverrideColorWriteEnable then render.OverrideColorWriteEnable(false) end
			if render.DepthRange then render.DepthRange(0, 1) end
			if render.SetColorModulation then render.SetColorModulation(1, 1, 1) end
			if cam.IgnoreZ then cam.IgnoreZ(false) end
		end)
	end

	--- Mode 2: light GPU-state barrier between eyes (NO glFinish — that races mat workers
	--- and caused "Illegal termination of worker thread" + zero-dimension submit spam).
	local function SyncMatQueueBetweenEyes()
		if WantedMatQueueMode() < 2 then return end
		ResetStereoEyeState()
		pcall(function()
			if render.SetColorMaterial then render.SetColorMaterial() end
			render.SetBlend(1)
		end)
	end

	local function EnsureDecalsEnabled()
		local d = GetConVar("r_drawdecals")
		local m = GetConVar("r_drawmodeldecals")
		if d and d:GetInt() ~= 1 then setConvarValue("r_drawdecals", "1") end
		if m and m:GetInt() ~= 1 then setConvarValue("r_drawmodeldecals", "1") end
	end

	--- Engine eye pass only — never WorldPortals_RenderView, never nested RTs.
	local function SafeRenderView(view)
		if not view or not view.origin or not view.angles then return end
		local o, a = view.origin, view.angles
		if o.x ~= o.x or o.y ~= o.y or o.z ~= o.z then return end
		if a.p ~= a.p or a.y ~= a.y or a.r ~= a.r then return end

		local wp = rawget(_G, "wp")
		if istable(wp) then
			wp.drawing = true
		end
		ResetStereoEyeState()
		local rv = GetEngineRenderView()
		rv(view)
		ResetStereoEyeState()
	end

	--- Fill a private eye viewsetup from public g_VR.view SoT + eye-specific fields.
	local function SyncEyeView(dst, origin, fov, aspect, x, y, w, h, angles, znear, dopost, zfar)
		dst.origin = origin
		dst.angles = angles
		dst.fov = fov
		dst.aspectratio = aspect
		dst.x, dst.y, dst.w, dst.h = x, y, w, h
		dst.znear = znear
		-- Always set zfar — never inherit a short far plane from radar/minimap RenderView
		local zf = tonumber(zfar) or VIEW_ZFAR
		if zf < 256 then zf = VIEW_ZFAR end
		dst.zfar = zf
		dst.dopostprocess = dopost and true or false
		dst.drawmonitors = false -- nested RenderView = freeze/heap corruption on Linux
		dst.drawviewmodel = false
		dst.drawhud = false
		dst.bloomtone = false
		dst.ortho = false -- radar uses ortho; must clear or eyes stay orthographic-clipped
	end

	local function PerformRenderViews()
		if renderingEyes then return end
		-- Ensure portal nest lock (idempotent); full Begin is on VR start
		InstallWorldPortalsVRGuard()
		local wpLock = rawget(_G, "wp")
		if istable(wpLock) then
			wpLock.drawing = true
		end

		local view = g_VR.view
		if not view or not view.origin or not view.angles then return end
		if not g_VR.rt then return end

		-- Recover RT size after lua_refresh / partial start (never arithmetic on nil)
		local rtW = tonumber(g_VR.rtWidth)
		local rtH = tonumber(g_VR.rtHeight)
		if not rtW or not rtH or rtW < 32 or rtH < 32 then
			local rtw, rth = 0, 0
			if g_VR.rt.Width and g_VR.rt.Height then
				rtw, rth = g_VR.rt:Width(), g_VR.rt:Height()
			end
			rtW = (rtw and rtw >= 32) and rtw or 2048
			rtH = (rth and rth >= 32) and rth or 1024
			g_VR.rtWidth, g_VR.rtHeight = rtW, rtH
			if vrmod.logger then
				vrmod.logger.Warn("PerformRenderViews recovered rt size %sx%s", rtW, rtH)
			end
		end
		local rtHalfW = math.floor(rtW / 2)
		if rtHalfW < 16 then return end

		local ang = view.angles
		local fwd = ang:Forward()
		local right = ang:Right()
		local up = ang:Up()
		local scale = g_VR.scale or 1
		local eyeScale = (convars.vrmod_eyescale and convars.vrmod_eyescale:GetFloat()) or 0.5
		local ipdUse = ipd or 0.064
		local eyezUse = eyez or 0
		eyeOffset = ipdUse * scale
		forwardOffset = fwd * -(eyezUse * scale)
		verticalOffset = up * -2.1

		-- Cyclopean SoT (public) — never leave g_VR.view stuck on last eye
		local cyclopeanOrigin = view.origin
		local baseAngles = ang
		local znear = view.znear or 1
		local zfar = view.zfar or VIEW_ZFAR
		if zfar < 256 then zfar = VIEW_ZFAR end
		local dopost = view.dopostprocess and true or false

		g_VR.eyePosLeft = cyclopeanOrigin + forwardOffset + right * (-eyeOffset * eyeScale) + verticalOffset
		g_VR.eyePosRight = cyclopeanOrigin + forwardOffset + right * (eyeOffset * eyeScale) + verticalOffset

		-- Optional eye swap (PSVR2 / inverted-stereo reports): content for logical L/R
		-- still uses correct IPD/FOV, but is written into the opposite SBS half.
		local swapEyes = convars.vrmod_swap_eyes and convars.vrmod_swap_eyes:GetBool()
		local leftX, rightX = 0, rtHalfW
		if swapEyes then
			leftX, rightX = rtHalfW, 0
		end

		SyncEyeView(viewLeft, g_VR.eyePosLeft, hfovLeft, aspectLeft, leftX, 0, rtHalfW, rtH, baseAngles, znear, dopost, zfar)
		SyncEyeView(viewRight, g_VR.eyePosRight, hfovRight, aspectRight, rightX, 0, rtHalfW, rtH, baseAngles, znear, dopost, zfar)

		renderingEyes = true
		local okEyes, errEyes = pcall(function()
			-- World RT captures (radar ortho, etc.) MUST run with no stereo RT pushed.
			-- Nested RenderView under g_VR.rt flickers the entire map.
			g_VR.stereoEye = nil
			g_VR.stereoFrame = (g_VR.stereoFrame or 0) + 1
			hook.Call("VRMod_PreStereoCapture", nil)

			render.PushRenderTarget(g_VR.rt)
			-- Menu / HUD panel RTs must NEVER nest while this is true (malloc crash ~2s after menu open).
			g_VR.stereoRtActive = true
			if DrawErrorOverlay() then
				g_VR.stereoRtActive = false
				render.PopRenderTarget()
				return
			end

			render.Clear(0, 0, 0, 255, true, true)

			-- ============================================================
			-- ONE pose/solve phase for the whole frame (not per-eye).
			-- Twin IK, HUD RT capture, menu pose snapshot — never on
			-- VRMod_PreRender(left) only. Both eyes then only DRAW.
			-- ============================================================
			-- Freeze hand samples for the whole stereo pair (grip/laser/UI).
			-- Live tracking must not be re-read between left and right eyes.
			do
				local L = g_VR.tracking and g_VR.tracking.pose_lefthand
				local R = g_VR.tracking and g_VR.tracking.pose_righthand
				g_VR.stereoPose = g_VR.stereoPose or {}
				local sp = g_VR.stereoPose
				sp.frame = g_VR.stereoFrame
				if L and L.pos and L.ang then
					sp.leftPos = sp.leftPos or Vector()
					sp.leftAng = sp.leftAng or Angle()
					sp.leftPos:Set(L.pos)
					sp.leftAng:Set(L.ang)
					sp.hasLeft = true
				else
					sp.hasLeft = false
				end
				if R and R.pos and R.ang then
					sp.rightPos = sp.rightPos or Vector()
					sp.rightAng = sp.rightAng or Angle()
					sp.rightPos:Set(R.pos)
					sp.rightAng:Set(R.ang)
					sp.hasRight = true
				else
					sp.hasRight = false
				end
			end
			hook.Call("VRMod_PreStereo", nil)
			EnsureDecalsEnabled()

			-- LEFT eye — draw only
			view.origin = g_VR.eyePosLeft
			view.angles = baseAngles
			view.fov = hfovLeft
			view.aspectratio = aspectLeft
			view.x, view.y, view.w, view.h = leftX, 0, rtHalfW, rtH
			g_VR.stereoEye = "left"
			render.SetScissorRect(leftX, 0, leftX + rtHalfW, rtH, true)
			hook.Call("VRMod_PreRender", nil, "left")
			SafeRenderView(viewLeft)

			-- Depth only — never Clear colour (would wipe left-eye world + decals).
			-- Reset stencil/depth-range so right eye does not inherit halo/HUD state.
			ResetStereoEyeState()
			render.ClearDepth(true)
			-- mat_queue_mode 2: serialize material workers before second eye
			SyncMatQueueBetweenEyes()

			-- RIGHT eye — draw only (same world pose as left)
			view.origin = g_VR.eyePosRight
			view.angles = baseAngles
			view.fov = hfovRight
			view.aspectratio = aspectRight
			view.x, view.y, view.w, view.h = rightX, 0, rtHalfW, rtH
			g_VR.stereoEye = "right"
			render.SetScissorRect(rightX, 0, rightX + rtHalfW, rtH, true)
			hook.Call("VRMod_PreRender", nil, "right")
			SafeRenderView(viewRight)

			render.SetScissorRect(0, 0, 0, 0, false)
			g_VR.stereoEye = nil
			ResetStereoEyeState()

			-- Restore cyclopean public SoT
			view.origin = cyclopeanOrigin
			view.angles = baseAngles
			view.fov = hfovLeft
			view.aspectratio = aspectLeft
			view.x, view.y, view.w, view.h = 0, 0, rtHalfW, rtH

			local ply = LocalPlayer()
			if IsValid(ply) and not ply:Alive() then
				vrmod.utils.DrawDeathAnimation(rtW, rtH)
			else
				g_VR.deathTime = nil
			end

			g_VR.stereoRtActive = false
			render.PopRenderTarget()
		end)
		renderingEyes = false
		g_VR.stereoEye = nil
		g_VR.stereoRtActive = false
		if view and cyclopeanOrigin then
			view.origin = cyclopeanOrigin
			view.angles = baseAngles
		end

		if not okEyes then
			if vrmod.logger then
				vrmod.logger.Warn("PerformRenderViews error: %s", tostring(errEyes))
			end
			pcall(function() render.SetScissorRect(0, 0, 0, 0, false) end)
			g_VR.stereoRtActive = false
			pcall(render.PopRenderTarget)
		end

		if g_VR.desktopView and g_VR.desktopView > 1 and g_VR.rtMaterial then
			render.CullMode(1)
			surface.SetDrawColor(255, 255, 255, 255)
			surface.SetMaterial(g_VR.rtMaterial)
			surface.DrawTexturedRectUV(-1, -1, 2, 2, cropHorizontalOffset, 1 - cropVerticalMargin, 0.5 + cropHorizontalOffset, cropVerticalMargin)
			render.CullMode(0)
		end
	end

	-- 1) Startup checks & init
	local function PerformStartup()
		local err = vrmod.GetStartupError()
		if err then
			vrmod.logger.Err("Failed to start: " .. err)
			if vrmod.Toast then
				vrmod.Toast("VR start blocked: " .. tostring(err), 8, "error")
			end
			return false
		end

		VRMOD_Shutdown() -- ensure clean state
		if VRMOD_Init() == false then
			vrmod.logger.Err("Init failed")
			if vrmod.Toast then
				vrmod.Toast("VR_Init failed — SteamVR/OpenXR running? Check module version.", 8, "error")
			end
			return false
		end
		return true
	end

	-- 2) Convar overrides for performance
	local function OverridePerformanceConvars()
		-- Keep skybox flag in sync with current settings at start time
		PERFORMANCE_CONVARS.r_3dsky = tostring(convars.vrmod_skybox:GetBool() and 1 or 0)
		RefreshMatQueuePin()
		for cvar, val in pairs(PERFORMANCE_CONVARS) do
			-- mat_queue only once per session
			if cvar == "mat_queue_mode" then
				if not matQueueAppliedForSession then
					overrideConvar(cvar, val)
					matQueueAppliedForSession = true
				end
			else
				overrideConvar(cvar, val)
			end
		end
		local mq = WantedMatQueueMode()
		if vrmod.logger then
			vrmod.logger.Info("mat_queue_mode=%s (vrmod_mat_queue_mode; 2=multithreaded, set once)", tostring(mq))
		end
	end

	-- Apply UV submit bounds from border convars (safe to call live while VR active)
	local function ApplySubmitBounds()
		if not g_VR.active and not leftCalc then return end
		if type(leftCalc) ~= "table" or type(rightCalc) ~= "table" then return end
		if not VRMOD_SetSubmitTextureBounds then return end
		local hOffset = convars.vrmod_horizontaloffset:GetFloat()
		local vOffset = convars.vrmod_verticaloffset:GetFloat()
		local scaleFactor = convars.vrmod_scalefactor:GetFloat()
		local renderOffset = convars.vrmod_renderoffset:GetBool()
		local bounds = {vrmod.utils.ComputeSubmitBounds(leftCalc, rightCalc, hOffset, vOffset, scaleFactor, renderOffset)}
		VRMOD_SetSubmitTextureBounds(unpack(bounds))
		-- OpenXR OpenGL: flip GL RT V into compositor (Linux). Windows D3D path usually false.
		if isfunction(VRMOD_SetRTTextureFlip) then
			VRMOD_SetRTTextureFlip(not system.IsWindows())
		end
	end

	-- Live update: UV bounds only (offsets/scale factor)
	local function BindBorderConvarCallbacks()
		local names = {
			"vrmod_horizontaloffset",
			"vrmod_verticaloffset",
			"vrmod_scalefactor",
			"vrmod_renderoffset",
		}
		for _, name in ipairs(names) do
			cvars.RemoveChangeCallback(name, "vrmod_submit_bounds")
			cvars.AddChangeCallback(name, function()
				if not g_VR.active then return end
				ApplySubmitBounds()
			end, "vrmod_submit_bounds")
		end
	end

	-- Soft-reload projection/FOV/viewscale without full VR restart (rendering profile)
	local function SoftRefreshDisplayParams()
		if not g_VR.active then return end
		local dp = ComputeDisplayParams()
		if not dp then return end
		leftCalc = dp.leftCalc or leftCalc
		rightCalc = dp.rightCalc or rightCalc
		hfovLeft = dp.hfovL or hfovLeft
		hfovRight = dp.hfovR or hfovRight
		aspectLeft = dp.aspL or aspectLeft
		aspectRight = dp.aspR or aspectRight
		ipd = dp.ipd or ipd
		eyez = dp.eyez or eyez
		g_VR.desktopView = convars.vrmod_desktopview:GetInt()
		if g_VR.rtWidth and g_VR.rtHeight then
			cropVerticalMargin, cropHorizontalOffset = vrmod.utils.ComputeDesktopCrop(g_VR.desktopView, g_VR.rtWidth, g_VR.rtHeight)
		end
		ApplySubmitBounds()
		if vrmod.logger then
			vrmod.logger.Info("Soft-refreshed display params (FOV/viewscale/desktop)")
		end
	end

	local function BindRenderProfileCallbacks()
		local names = {
			"vrmod_fovscale_x",
			"vrmod_fovscale_y",
			"vrmod_viewscale",
			"vrmod_desktopview",
		}
		for _, name in ipairs(names) do
			cvars.RemoveChangeCallback(name, "vrmod_render_profile")
			cvars.AddChangeCallback(name, function()
				if not g_VR.active then return end
				SoftRefreshDisplayParams()
			end, "vrmod_render_profile")
		end
	end

	-- 3) Display parameters & render target setup
	local function SetupRenderTargets()
		g_VR.desktopView = convars.vrmod_desktopview:GetInt()
		-- compute display params with fallback
		local dp = ComputeDisplayParams() or {}
		g_VR.rtWidth = dp.rtW or 1024
		g_VR.rtHeight = dp.rtH or 1024
		local eyeW = dp.eyeW or math.floor(g_VR.rtWidth / 2)
		local eyeH = dp.eyeH or g_VR.rtHeight
		leftCalc = dp.leftCalc or 0
		rightCalc = dp.rightCalc or 0
		hfovLeft = dp.hfovL or 90
		hfovRight = dp.hfovR or 90
		aspectLeft = dp.aspL or 1
		aspectRight = dp.aspR or 1
		ipd = dp.ipd or 0.064
		eyez = dp.eyez or 0
		cropVerticalMargin, cropHorizontalOffset = vrmod.utils.ComputeDesktopCrop(g_VR.desktopView, g_VR.rtWidth, g_VR.rtHeight)
		-- v23+: pass eye size so OUT matches supersampled RT. Ancient: no args (module owns size).
		local okBegin, errBegin = SafeShareTextureBegin(
			(dp.passEyeArgs and eyeW) or nil,
			(dp.passEyeArgs and eyeH) or nil
		)
		if not okBegin then
			if vrmod.logger then
				vrmod.logger.Err("ShareTextureBegin failed: %s (eye %sx%s rt %sx%s)",
					tostring(errBegin), tostring(eyeW), tostring(eyeH),
					tostring(g_VR.rtWidth), tostring(g_VR.rtHeight))
			end
			if vrmod.Toast then
				vrmod.Toast(string.format(
					"ShareTexture begin failed (%sx%s) — HMD may stay black. Lower supersample / check module.",
					tostring(g_VR.rtWidth), tostring(g_VR.rtHeight)
				), 8, "error")
			end
		end
		local rtName = "vrmod_rt_" .. tostring(SysTime())
		-- Filtered RT (no UNFILTERABLE). SS only applied when module can match OUT size.
		local depthMode = MATERIAL_RT_DEPTH_SEPARATE or 0
		local rtFlags = 0
		local imgFormat = IMAGE_FORMAT_RGBA8888
		g_VR.rt = GetRenderTargetEx(rtName, g_VR.rtWidth, g_VR.rtHeight, RT_SIZE_LITERAL or 0, depthMode, 0, rtFlags, imgFormat)
		local matName = "vrmod_rt_mat_" .. tostring(SysTime())
		g_VR.rtMaterial = CreateMaterial(matName, "UnlitGeneric", {
			["$basetexture"] = g_VR.rt:GetName()
		})

		local okFin, errFin = SafeShareTextureFinish()
		if not okFin then
			if vrmod.logger then
				vrmod.logger.Err("ShareTextureFinish failed: %s (rt %sx%s)",
					tostring(errFin), tostring(g_VR.rtWidth), tostring(g_VR.rtHeight))
			end
			if vrmod.Toast then
				vrmod.Toast(string.format(
					"ShareTexture finish failed (rt %sx%s) — desktop OK / HMD black often means this. Restart SteamVR + GMod.",
					tostring(g_VR.rtWidth), tostring(g_VR.rtHeight)
				), 8, "error")
			end
		end
		g_VR._shareTextureOk = okBegin and okFin and true or false
		-- Authoritative SBS size for OpenXR submit (mat_queue 2 cannot glGetTexLevel)
		PushKnownSubmitSize()
		ApplySubmitBounds()
		BindBorderConvarCallbacks()
		BindRenderProfileCallbacks()
	end

	-- 4) Action manifest & input initialization (never abort VR start)
	-- Module resolves: getcwd()/garrysmod/data/<arg> — files must live in DATA/vrmod/.
	local function RewriteActionManifestFiles()
		if not file.Exists("vrmod", "DATA") then file.CreateDir("vrmod") end
		-- Full binding set when available (self-heal corrupt/empty DATA)
		if g_VR.action_manifest then
			file.Write("vrmod/vrmod_action_manifest.txt", g_VR.action_manifest)
		end
		if g_VR.bindings_holographic then
			file.Write("vrmod/vrmod_bindings_holographic_controller.txt", g_VR.bindings_holographic)
		end
		if g_VR.bindings_touch then
			file.Write("vrmod/vrmod_bindings_oculus_touch.txt", g_VR.bindings_touch)
		end
		if g_VR.bindings_vive then
			file.Write("vrmod/vrmod_bindings_vive_controller.txt", g_VR.bindings_vive)
		end
		if g_VR.bindings_knuckles then
			file.Write("vrmod/vrmod_bindings_knuckles.txt", g_VR.bindings_knuckles)
		end
		if g_VR.bindings_cosmos then
			file.Write("vrmod/vrmod_bindings_vive_cosmos_controller.txt", g_VR.bindings_cosmos)
		end
		if g_VR.bindings_vive_tracker_left_foot then
			file.Write("vrmod/vrmod_bindings_vive_tracker_left_foot.txt", g_VR.bindings_vive_tracker_left_foot)
		end
		if g_VR.bindings_vive_tracker_right_foot then
			file.Write("vrmod/vrmod_bindings_vive_tracker_right_foot.txt", g_VR.bindings_vive_tracker_right_foot)
		end
		if g_VR.bindings_vive_tracker_waist then
			file.Write("vrmod/vrmod_bindings_vive_tracker_waist.txt", g_VR.bindings_vive_tracker_waist)
		end
	end

	local function SetupActions()
		RewriteActionManifestFiles()
		local manPath = "vrmod/vrmod_action_manifest.txt"
		local hasFile = file.Exists(manPath, "DATA")
		local okMan, errMan = pcall(VRMOD_SetActionManifest, manPath)
		if not okMan then
			-- Retry after force rewrite (corrupt DATA / first-run race)
			RewriteActionManifestFiles()
			okMan, errMan = pcall(VRMOD_SetActionManifest, manPath)
		end
		if not okMan then
			local detail = tostring(errMan or "unknown")
			if vrmod.logger then
				vrmod.logger.Err("SetActionManifest failed (VR continues without bindings): %s hasFile=%s", detail, tostring(hasFile))
			end
			-- Cube W6: honest toast — silent death left controllers dead with no clue
			if vrmod.Toast then
				vrmod.Toast(
					"Controller bindings failed — reinstall VRMod module; ensure data/vrmod/vrmod_action_manifest.txt exists. SteamVR may need restart.",
					8,
					"error"
				)
			end
			g_VR.errorText = "Bindings failed — check console / reinstall module"
			timer.Simple(12, function()
				if g_VR and g_VR.errorText and string.find(g_VR.errorText, "Bindings failed", 1, true) then
					g_VR.errorText = ""
				end
			end)
		else
			g_VR._actionManifestOk = true
		end

		local set = LocalPlayer():InVehicle() and "/actions/driving" or "/actions/main"
		pcall(VRMOD_SetActiveActionSets, "/actions/base", set)
		if isfunction(VRUtilLoadCustomActions) then pcall(VRUtilLoadCustomActions) end
		if isfunction(VRMOD_GetActions) then
			local okA, a, b = pcall(VRMOD_GetActions)
			if okA then
				a, b = ApplyOpenXRBindings(a, b)
				g_VR.input, g_VR.changedInputs = a, b
			else
				g_VR.input, g_VR.changedInputs = g_VR.input or {}, g_VR.changedInputs or {}
			end
		end
	end

	-- 5) Networking & origin
	local function SetupNetworkAndOrigin()
		VRUtilNetworkInit()
		g_VR.origin = LocalPlayer():GetPos()
	end

	-- 6) Controller offsets & scale
	local function SetupScaleAndOffsets()
		g_VR.scale = convars.vrmod_scale:GetFloat()
		g_VR.rightControllerOffsetPos = Vector(convars.vrmod_controlleroffset_x:GetFloat(), convars.vrmod_controlleroffset_y:GetFloat(), convars.vrmod_controlleroffset_z:GetFloat())
		g_VR.leftControllerOffsetPos = g_VR.rightControllerOffsetPos * Vector(1, -1, 1)
		g_VR.rightControllerOffsetAng = Angle(convars.vrmod_controlleroffset_pitch:GetFloat(), convars.vrmod_controlleroffset_yaw:GetFloat(), convars.vrmod_controlleroffset_roll:GetFloat())
		g_VR.leftControllerOffsetAng = g_VR.rightControllerOffsetAng
	end

	-- 7) Initial view setup
	local function SetupViewParams()
		g_VR.view = {
			x = 0,
			y = 0,
			w = g_VR.rtWidth / 2,
			h = g_VR.rtHeight,
			drawmonitors = false, -- nested RenderView → freeze/heap corruption in VR RT
			drawviewmodel = false,
			znear = convars.vrmod_znear:GetFloat(),
			zfar = VIEW_ZFAR,
			ortho = false,
			dopostprocess = convars.vrmod_postprocess:GetBool()
		}
	end

	-- 8) Initial tracking state — core pose tables always exist before first frame
	-- angvel is Vector(p,y,r) per Cube's Law (never Angle)
	-- EmptyPose / EnsurePoseIndependence defined above (before UpdateTracking).
	local function InitializeTracking()
		lastPosePos = {}
		local origin = LocalPlayer():GetPos()
		g_VR.tracking = {
			hmd = EmptyPose(origin + Vector(0, 0, 66.8)),
			pose_lefthand = EmptyPose(origin),
			pose_righthand = EmptyPose(origin),
		}
		-- Mirror seed into raw — each EmptyPose clones (never share tracking.pos)
		g_VR.rawTracking = {
			hmd = EmptyPose(g_VR.tracking.hmd.pos),
			pose_lefthand = EmptyPose(origin),
			pose_righthand = EmptyPose(origin),
		}

		g_VR.threePoints = true
	end

	-- 9) Simulated hand fallback
	local function SetupHandSimulation()
		local simulate = {
			{
				pose = g_VR.tracking.pose_lefthand,
				offset = Vector(0, 10, -30)
			},
			{
				pose = g_VR.tracking.pose_righthand,
				offset = Vector(0, -10, -30)
			},
		}

		for _, v in ipairs(simulate) do
			v.pose.simulatedPos = v.pose.pos
		end

		hook.Add("VRMod_Tracking", "simulatehands", function()
			for i = #simulate, 1, -1 do
				local v = simulate[i]
				if v.pose.pos == v.pose.simulatedPos then
					v.pose.pos, v.pose.ang = LocalToWorld(v.offset, Angle(90, 0, 0), g_VR.tracking.hmd.pos, Angle(0, g_VR.tracking.hmd.ang.yaw, 0))
					v.pose.simulatedPos = v.pose.pos
				else
					table.remove(simulate, i)
				end
			end

			if #simulate == 0 then hook.Remove("VRMod_Tracking", "simulatehands") end
		end)
	end

	local function BindRenderSceneHook()
		BeginVRNestedRenderLock()
		-- Cube frame energy (one direction):
		--   raw → tracking SoT → modifiers → input/net → cyclopean view
		--   → stereo eyes (engine RealRenderView only) → submit → PostRender
		hook.Add("RenderScene", "vrutil_hook_renderscene", function()
			if DrawErrorOverlay() then return true end

			-- Keep session mat_queue_mode (0/1/2) if another addon fights it
			EnsurePinnedConvars()

			-- Keep World Portals suppressed for the entire VR frame (do not restore mid-frame)
			local wp = rawget(_G, "wp")
			if istable(wp) then
				wp.drawing = true
			end

			UpdateTracking()
			ApplyPoseModifiers()
			HandleInput()
			VRUtilNetUpdateLocalPly()
			UpdateViewFromEntity()
			PerformRenderViews()
			if isfunction(VRMOD_SubmitSharedTexture) then
				VRMOD_SubmitSharedTexture()
			end
			hook.Call("VRMod_PostRender")
			return true
		end, HOOK_HIGH or 1)
	end

	local function SetupModelAndPlayerHooks()
		-- Do not touch viewmodel_fov — GMod x64 blocks it ("Command is blocked!")
		-- and VR never draws the HL2 viewmodel FOV path as desktop does.
		hook.Add("CalcViewModelView", "vrutil_hook_calcviewmodelview", function(_, vm, _, _, _, _) return g_VR.viewModelPos, g_VR.viewModelAng end)
		local blockViewModelDraw = true
		g_VR.allowPlayerDraw = false
		local hideplayer = convars.vrmod_floatinghands:GetBool()
		hook.Add("PostDrawTranslucentRenderables", "vrutil_hook_drawplayerandviewmodel", function(bSky, _)
			if bSky or not LocalPlayer():Alive() then return end
			if IsValid(g_VR.viewModel) then
				blockViewModelDraw = false
				-- Stamp frozen gun matrix both eyes (same pose — no live re-pose here)
				local sf = g_VR.stereoFrame or 0
				local vm = g_VR.viewModel
				if g_VR._weaponSnapFrame == sf and g_VR._weaponSnapPos and g_VR._weaponSnapAng then
					g_VR.viewModelPos = g_VR._weaponSnapPos
					g_VR.viewModelAng = g_VR._weaponSnapAng
					vm:SetPos(g_VR._weaponSnapPos)
					vm:SetAngles(g_VR._weaponSnapAng)
					if g_VR._weaponBonesFrame ~= sf then
						vm:SetupBones()
						g_VR._weaponBonesFrame = sf
					end
				elseif g_VR.viewModelPos and g_VR.viewModelAng then
					vm:SetPos(g_VR.viewModelPos)
					vm:SetAngles(g_VR.viewModelAng)
					if g_VR._weaponBonesFrame ~= sf then
						vm:SetupBones()
						g_VR._weaponBonesFrame = sf
					end
				end
				local okDraw, errDraw = pcall(function()
					vm:DrawModel()
				end)
				if not okDraw and vrmod.logger then
					vrmod.logger.Debug("viewModel DrawModel error: %s", tostring(errDraw))
				end
				local wep = LocalPlayer():GetActiveWeapon()
				if IsValid(wep) and isfunction(wep.PostDrawViewModel) then
					local ok, err = pcall(wep.PostDrawViewModel, wep, vm, LocalPlayer(), wep)
					if not ok and vrmod.logger then
						vrmod.logger.Debug("PostDrawViewModel error: %s", tostring(err))
					end
				end
				blockViewModelDraw = true
			end

			if not hideplayer then
				g_VR.allowPlayerDraw = true
				cam.Start3D()
				cam.End3D()
				local prev = render.GetBlend()
				render.SetBlend(1)
				LocalPlayer():DrawModel()
				render.SetBlend(prev)
				cam.Start3D()
				cam.End3D()
				g_VR.allowPlayerDraw = false
				-- Avatar twin SoT: pose snap right after the VR body is drawn this eye
				if vrmod.avatar and vrmod.avatar.PublishPlayerPose then
					local lp = LocalPlayer()
					local tab = g_VR.net and g_VR.net[lp:SteamID()]
					if tab and tab.lerpedFrame then
						pcall(vrmod.avatar.PublishPlayerPose, lp, tab.lerpedFrame)
					end
				end
			end

			VRUtilRenderMenuSystem()
		end)

		hook.Add("PreDrawPlayerHands", "vrutil_hook_predrawplayerhands", function() return true end)
		hook.Add("PreDrawViewModel", "vrutil_hook_predrawviewmodel", function() return blockViewModelDraw end)
		hook.Add("ShouldDrawLocalPlayer", "vrutil_hook_shoulddrawlocalplayer", function() return g_VR.allowPlayerDraw end)
	end

	local function SetupShutdownHooks()
		function VRUtilClientExit()
			if not g_VR.active then return end
			timer.Remove("vrmod_stereo_selftest")
			g_VR._stereoSelfTestDone = true
			matQueueAppliedForSession = false
			restoreConvarOverrides()
			VRUtilMenuClose()
			VRUtilNetworkCleanup()
			vrmod.StopLocomotion()
			if IsValid(g_VR.viewModel) and g_VR.viewModel:GetClass() == "class C_BaseFlex" then g_VR.viewModel:Remove() end
			g_VR.viewModel = nil
			g_VR.viewModelMuzzle = nil
			local ply = LocalPlayer()
			if IsValid(ply) then
				local vm = ply:GetViewModel()
				if IsValid(vm) then
					vm.RenderOverride = nil
					vm:RemoveEffects(EF_NODRAW)
				end
			end
			hook.Remove("RenderScene", "vrutil_hook_renderscene")
			hook.Remove("CalcViewModelView", "vrutil_hook_calcviewmodelview")
			hook.Remove("PostDrawTranslucentRenderables", "vrutil_hook_drawplayerandviewmodel")
			hook.Remove("PreDrawPlayerHands", "vrutil_hook_predrawplayerhands")
			hook.Remove("PreDrawViewModel", "vrutil_hook_predrawviewmodel")
			hook.Remove("ShouldDrawLocalPlayer", "vrutil_hook_shoulddrawlocalplayer")
			hook.Remove("CalcView", "vrutil_hook_calcview")
			g_VR.tracking = {}
			g_VR.rawTracking = {}
			g_VR.threePoints = false
			g_VR.sixPoints = false
			if g_VR.rt then
				render.PushRenderTarget(g_VR.rt)
				render.Clear(0, 0, 0, 255, true, true)
				render.PopRenderTarget()
				g_VR.rt = nil
			end
			g_VR.rtWidth, g_VR.rtHeight = nil, nil
			g_VR.stereoEye = nil
			g_VR.active = false
			EndVRNestedRenderLock()
			VRMOD_Shutdown()
			vrmod.logger.Info("Ended VR session")
		end

		hook.Add("ShutDown", "vrutil_hook_shutdown", function() if IsValid(LocalPlayer()) and g_VR.net[LocalPlayer():SteamID()] then VRUtilClientExit() end end)
	end

	-- Main ----------------------------------------------------------------------
	function VRUtilClientStart()
		if not PerformStartup() then return end
		OverridePerformanceConvars()
		-- RT setup is mandatory; if it fails, do not bind RenderScene
		local okRT, errRT = pcall(SetupRenderTargets)
		if not okRT or not g_VR.rt or not g_VR.rtWidth then
			if vrmod.logger then
				vrmod.logger.Err("SetupRenderTargets failed: %s", errRT)
			end
			if vrmod.Toast then
				vrmod.Toast("Render targets failed — cannot start VR eyes. Check console / module.", 8, "error")
			end
			return
		end
		-- Actions may fail (manifest path) — never block eyes/HUD
		pcall(SetupActions)
		pcall(SetupNetworkAndOrigin)
		pcall(SetupScaleAndOffsets)
		SetupViewParams()
		if g_VR.view then
			g_VR.view.drawmonitors = false
			g_VR.view.w = g_VR.view.w or (g_VR.rtWidth / 2)
			g_VR.view.h = g_VR.view.h or g_VR.rtHeight
		end
		InitializeTracking()
		pcall(SetupHandSimulation)
		g_VR.active = true
		BeginVRNestedRenderLock()
		BindRenderSceneHook()
		SetupModelAndPlayerHooks()
		SetupShutdownHooks()
		if vrmod.StartLocomotion then pcall(vrmod.StartLocomotion) end
		-- HUD bind after eyes are live
		if vrmod.RefreshHUD then
			timer.Simple(0, function()
				if g_VR.active and vrmod.RefreshHUD then vrmod.RefreshHUD() end
			end)
		end
		-- Cube W7: early stereo / tracking self-check (toast once if HMD silent)
		g_VR._stereoSelfTestDone = false
		timer.Create("vrmod_stereo_selftest", 2.5, 1, function()
			if not g_VR or not g_VR.active or g_VR._stereoSelfTestDone then return end
			g_VR._stereoSelfTestDone = true
			local hmd = g_VR.tracking and g_VR.tracking.hmd
			local hasHmd = hmd and hmd.pos and true or false
			if not hasHmd then
				if vrmod.Toast then
					vrmod.Toast(
						"No HMD pose after start — PC may show game while headset stays black/loading. Restart SteamVR; check cable/HMD.",
						8,
						"error"
					)
				end
				if vrmod.logger then
					vrmod.logger.Err("Stereo self-test: no HMD tracking rt=%sx%s shareOk=%s",
						tostring(g_VR.rtWidth), tostring(g_VR.rtHeight), tostring(g_VR._shareTextureOk))
				end
			elseif g_VR._shareTextureOk == false and vrmod.Toast then
				vrmod.Toast(
					"Stereo share was unhealthy at start — if HMD is black, restart SteamVR + lower supersample.",
					6,
					"hint"
				)
			end
		end)
		vrmod.logger.Info("Started VR session (nested RenderView lock active) rt=%sx%s", g_VR.rtWidth, g_VR.rtHeight)
	end
end