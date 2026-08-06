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
	-- Engine mat_queue_mode is process-global. We never write it (no force 0/1/2).
	-- Mode 2 is supported when the user already set it; thrash = ~CThread crash.
	local function WantedMatQueueMode()
		local cv = GetConVar and GetConVar("mat_queue_mode")
		local n = cv and (cv.GetInt and cv:GetInt() or tonumber(cv:GetString())) or 1
		-- G17 pure clamp (observation only — never write mat_queue_mode)
		if vrmod.utils and vrmod.utils.MatQueueLaw_ClampRead then
			n = vrmod.utils.MatQueueLaw_ClampRead(n)
		else
			n = math.floor(tonumber(n) or 1)
			if n < 0 then n = 0 end
			if n > 2 then n = 2 end
		end
		if vrmod.utils and vrmod.utils.MatQueueLaw_Decide then
			local prefer = 1
			pcall(function()
				local p = GetConVar and GetConVar("vrmod_prefer_mat_queue")
				if p then prefer = p:GetInt() end
			end)
			local dec = vrmod.utils.MatQueueLaw_Decide({
				live_mode = n,
				prefer = prefer,
				context = "vr_session",
			})
			g_VR._matQueueLaw = dec
			g_VR._matQueueLabel = vrmod.utils.MatQueueLaw_StatusLabel
				and vrmod.utils.MatQueueLaw_StatusLabel(dec) or nil
		end
		return n
	end

	-- Cvars we must never SetInt during VR (worker / thread lifecycle).
	local NEVER_WRITE_CONVARS = {
		mat_queue_mode = true,
		gmod_mcore_test = true, -- toggling mcore mid-session = same CThread assert
	}

	local PERFORMANCE_CONVARS = {
		-- NEVER list mat_queue_mode / gmod_mcore_test — thrash kills CThread workers.
		mat_disable_bloom = "1",
		mat_disable_fancy_blending = "1",
		mat_disable_lightwarp = "1",
		mat_disable_ps_patch = "1",
		mat_motion_blur_enabled = "0",
		mat_fastspecular = "0",
		r_3dsky = tostring(convars.vrmod_skybox:GetBool() and 1 or 0),
		r_queued_ropes = "1",
		r_drawdecals = "1",
		r_drawmodeldecals = "1",
		r_drawbatchdecals = "1",
		snd_mute_losefocus = "0",
		-- Keep engine frame loop alive when desktop window is not focused (VR HMD play).
		engine_no_focus_sleep = "0",
	}
	-- Empty: never re-pin engine queue/mcore every frame.
	local SESSION_PIN_CONVARS = {}
	local matQueueAppliedForSession = false
	local convarOverrides = {}

	local wasPaused = false
	if vrmod.LoadNativeModule then
		if vrmod.LoadNativeModule() then
			moduleFile = g_VR.moduleFile
			local pol = vrmod.DetectBackend and vrmod.DetectBackend() or nil
			if vrmod.logger then
				vrmod.logger.Info("Runtime: %s", vrmod.DescribeBackend and vrmod.DescribeBackend() or tostring(pol and pol.backend))
			end
			-- Refuse every-frame mat_queue pin always (OpenXR + mode 2 fatal).
		else
			vrmod.logger.Err("Failed to load module: %s", tostring(vrmod.GetModuleLoadError and vrmod.GetModuleLoadError()))
		end
	else
		local success, err = pcall(function() require("vrmod_xr") end)
		if not success then
			success, err = pcall(function() require("vrmod") end)
		end
		if success then
			for k, v in pairs(vrmod) do
				if isfunction(v) then _G["VRMOD_" .. k] = v end
			end
			g_VR.moduleVersion = VRMOD_GetVersion and VRMOD_GetVersion() or 0
		else
			vrmod.logger.Err("Failed to load module:", err)
		end
	end

	-- 0) Helper functions
	-- Only ConVar setters — never RunConsoleCommand (GMod blacklists many engine cvars
	-- and prints "Command is blocked!" even when pcall'd).
	-- mat_queue_mode: 0 sync · 1 queued single-thread · 2 multithreaded.
	-- HARD BAN: any write restarts CThread workers → Illegal termination / ExitProcess.
	local function convarMatches(cv, want)
		if not cv then return false end
		want = tostring(want)
		if cv:GetString() == want then return true end
		local wn, gn = tonumber(want), tonumber(cv:GetString())
		if wn ~= nil and gn ~= nil and wn == gn then return true end
		if cv.GetInt and wn ~= nil and cv:GetInt() == wn then return true end
		return false
	end

	local function setConvarValue(name, value)
		-- G27: never write engine-blocked or lifecycle convars (W2 / pain #3).
		if vrmod.utils and vrmod.utils.EngineBlacklist_AllowWrite then
			if not vrmod.utils.EngineBlacklist_AllowWrite(name) then
				if vrmod.logger then
					vrmod.logger.Debug("refused write %s (engine blacklist / lifecycle)", tostring(name))
				end
				return false
			end
		elseif NEVER_WRITE_CONVARS[name] then
			if vrmod.logger then
				vrmod.logger.Debug("refused write %s (thread-lifecycle cvar)", tostring(name))
			end
			return false
		end
		local cv = GetConVar(name)
		if not cv then return false end
		value = tostring(value)
		-- Skip no-ops so we do not fire engine change callbacks needlessly.
		if convarMatches(cv, value) then return true end
		local ok = pcall(function()
			local n = tonumber(value)
			if n ~= nil and cv.SetInt and math.floor(n) == n then
				cv:SetInt(n)
			elseif n ~= nil and cv.SetFloat then
				cv:SetFloat(n)
			else
				cv:SetString(value)
			end
		end)
		if not ok then
			ok = pcall(function() cv:SetString(value) end)
		end
		if not ok then
			vrmod.logger.Debug("Could not set convar: " .. name)
			return false
		end
		return true
	end

	local function overrideConvar(name, value)
		if vrmod.utils and vrmod.utils.EngineBlacklist_AllowWrite then
			if not vrmod.utils.EngineBlacklist_AllowWrite(name) then return end
		elseif NEVER_WRITE_CONVARS[name] then
			return
		end
		local cv = GetConVar(name)
		if not cv then return end
		local previous = cv:GetString()
		if not setConvarValue(name, value) then return end
		if convarOverrides[name] == nil then
			convarOverrides[name] = previous
		end
	end

	local function restoreConvarOverrides()
		-- Never restore mat_queue_mode / gmod_mcore_test (lifecycle thrash).
		for k, v in pairs(convarOverrides) do
			if not NEVER_WRITE_CONVARS[k] then
				setConvarValue(k, v)
			end
		end
		convarOverrides = {}
	end

	-- Soft restore of non-mat_queue pins only (mat_queue stays put).
	local function ScheduleConvarRestore(delay)
		delay = tonumber(delay) or 0.15
		timer.Remove("vrmod_mat_queue_restore")
		timer.Create("vrmod_mat_queue_restore", delay, 1, function()
			if g_VR and g_VR.active then return end
			restoreConvarOverrides()
			if vrmod.logger then
				vrmod.logger.Info("Restored pre-VR convars (mat_queue left unchanged)")
			end
		end)
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
		-- G27: snapshot performance map cleanliness (never claim HMD from this alone).
		if vrmod.utils and vrmod.utils.EngineBlacklist_Decide then
			local d = vrmod.utils.EngineBlacklist_Decide({
				vr_active = true,
				performance_map = PERFORMANCE_CONVARS,
				attempted = {},
			})
			g_VR._engineBlacklistLaw = d
			g_VR._engineBlacklistLabel = vrmod.utils.EngineBlacklist_StatusLabel
				and vrmod.utils.EngineBlacklist_StatusLabel(d) or nil
			g_VR._engineBlacklistHmdExpect = vrmod.utils.EngineBlacklist_HmdExpect
				and vrmod.utils.EngineBlacklist_HmdExpect(d) or nil
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
		-- G35 / W8: clamp viewscale (fisheye band); prefer HMD projection
		local rawVs = convars.vrmod_viewscale:GetFloat()
		local viewscale = (vrmod.utils and vrmod.utils.ViewScaleLaw_Clamp
			and vrmod.utils.ViewScaleLaw_Clamp(rawVs)) or rawVs
		-- G36 / W5: clamp FOV scales (extreme FOV → one-eye wrap)
		local rawFx, rawFy = convars.vrmod_fovscale_x:GetFloat(), convars.vrmod_fovscale_y:GetFloat()
		local fovX = (vrmod.utils and vrmod.utils.FovZLaw_ClampFovScale
			and vrmod.utils.FovZLaw_ClampFovScale(rawFx)) or rawFx
		local fovY = (vrmod.utils and vrmod.utils.FovZLaw_ClampFovScale
			and vrmod.utils.FovZLaw_ClampFovScale(rawFy)) or rawFy
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

		-- Raw module projection (before FOV scale). Identity = session not RUNNING yet
		-- (deferred GL session after cold Init/teardown). Callers must re-query.
		local rawLeft = di.ProjectionLeft
		local rawRight = di.ProjectionRight
		local projLive = false
		if type(rawLeft) == "table" and type(rawLeft[1]) == "table" then
			local a11 = tonumber(rawLeft[1][1]) or 1
			local a22 = tonumber(rawLeft[2] and rawLeft[2][2]) or 1
			projLive = math.abs(a11 - 1.0) > 0.02 or math.abs(a22 - 1.0) > 0.02
		end
		-- IPD from eye transform: identity has translation 0; real HMD has non-zero X offset.
		local ipd = di.TransformRight and di.TransformRight[1] and di.TransformRight[1][4] and (di.TransformRight[1][4] * 2) or 0.064
		local eyez = di.TransformRight and di.TransformRight[3] and di.TransformRight[3][4] or 0
		if not projLive and math.abs(ipd) > 0.001 and math.abs(ipd - 0.064) > 0.0001 then
			projLive = true
		end

		local leftProj = vrmod.utils.AdjustFOV(rawLeft, fovX, fovY)
		local rightProj = vrmod.utils.AdjustFOV(rawRight, fovX, fovY)
		local leftCalc = vrmod.utils.CalculateProjectionParams(leftProj, viewscale)
		local rightCalc = vrmod.utils.CalculateProjectionParams(rightProj, viewscale)

		if vrmod.utils and vrmod.utils.ViewScaleLaw_Decide then
			local vd = vrmod.utils.ViewScaleLaw_Decide({
				viewscale = rawVs,
				proj_live = projLive,
				fovscale_x = fovX,
				fovscale_y = fovY,
				require_proj_live = false, -- soft until session RUNNING
			})
			g_VR._viewScaleLaw = vd
			g_VR._viewScaleLawLabel = vrmod.utils.ViewScaleLaw_StatusLabel
				and vrmod.utils.ViewScaleLaw_StatusLabel(vd) or nil
			g_VR._viewScaleLawHmdExpect = vrmod.utils.ViewScaleLaw_HmdExpect
				and vrmod.utils.ViewScaleLaw_HmdExpect(vd) or nil
		end

		if vrmod.logger then
			vrmod.logger.Info(
				"Display RT SBS %dx%d (eye %dx%d, SS=%.2f, module v%d%s, projLive=%s)",
				rawW, rawH, eyeW, eyeH, ss, g_VR.moduleVersion or 0,
				canSS and ", eyeArgs" or ", legacy", tostring(projLive)
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
			eyez = eyez,
			projLive = projLive,
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
	-- G42 / ship bar: "hands stuck together" — pure HandStuckLaw_* owns thresholds.
	-- Heal identity always; if track collapsed but raw separated, restore from raw.
	-- Skip unstick while stock foregrip owns left (no climb/wall thrash).
	local function EnsurePoseIndependence()
		local tr = g_VR.tracking
		if not tr then return end
		local L, R, H = tr.pose_lefthand, tr.pose_righthand, tr.hmd
		local raw = g_VR.rawTracking
		local rL = raw and raw.pose_lefthand
		local rR = raw and raw.pose_righthand
		local U = vrmod.utils
		local identityHealed, unstuckApplied = false, false

		local function cloneVec(v)
			return Vector(v.x, v.y, v.z)
		end
		local function cloneAng(a)
			return Angle(a.p, a.y, a.r)
		end

		-- 1) Identity glue (same userdata) — always split (pure: ShouldSplitIdentity)
		local posIdLR = L and R and L.pos and R.pos and L.pos == R.pos
		local angIdLR = L and R and L.ang and R.ang and L.ang == R.ang
		local posIdHL = H and L and H.pos and L.pos and H.pos == L.pos
		local posIdHR = H and R and H.pos and R.pos and H.pos == R.pos
		local posIdRaw = rL and rR and rL.pos and rR.pos and rL.pos == rR.pos
		local angIdRaw = rL and rR and rL.ang and rR.ang and rL.ang == rR.ang
		local split = true
		if U and U.HandStuckLaw_ShouldSplitIdentity then
			split = U.HandStuckLaw_ShouldSplitIdentity(
				posIdLR or angIdLR or posIdHL or posIdHR or posIdRaw or angIdRaw
			)
		end
		if split then
			if posIdLR then
				R.pos = cloneVec(R.pos)
				identityHealed = true
				if vrmod.logger then
					vrmod.logger.Warn("Healed glued hand pos identity (L==R Vector)")
				end
			end
			if angIdLR then
				R.ang = cloneAng(R.ang)
				identityHealed = true
			end
			if posIdHL then
				L.pos = cloneVec(L.pos)
				identityHealed = true
			end
			if posIdHR then
				R.pos = cloneVec(R.pos)
				identityHealed = true
			end
			if posIdRaw then
				rR.pos = cloneVec(rR.pos)
				identityHealed = true
			end
			if angIdRaw then
				rR.ang = cloneAng(rR.ang)
				identityHealed = true
			end
		end

		-- 2) Value collapse: L/R nearly same world pos but raw is separated → un-stick
		local trackDist, rawDist
		if L and R and L.pos and R.pos and rL and rR and rL.pos and rR.pos then
			trackDist = L.pos:DistToSqr(R.pos)
			rawDist = rL.pos:DistToSqr(rR.pos)
			local wantRaw = false
			if U and U.HandStuckLaw_ShouldUnstickFromRaw then
				wantRaw = U.HandStuckLaw_ShouldUnstickFromRaw({
					track_dist_sqr = trackDist,
					raw_dist_sqr = rawDist,
					foregrip_active = g_VR.foregripActive and true or false,
				})
			else
				wantRaw = not g_VR.foregripActive and trackDist < 4 and rawDist > 36
			end
			if wantRaw then
				L.pos.x, L.pos.y, L.pos.z = rL.pos.x, rL.pos.y, rL.pos.z
				R.pos.x, R.pos.y, R.pos.z = rR.pos.x, rR.pos.y, rR.pos.z
				if rL.ang and L.ang then
					L.ang.p, L.ang.y, L.ang.r = rL.ang.p, rL.ang.y, rL.ang.r
				end
				if rR.ang and R.ang then
					R.ang.p, R.ang.y, R.ang.r = rR.ang.p, rR.ang.y, rR.ang.r
				end
				unstuckApplied = true
				if vrmod.logger then
					vrmod.logger.Warn("Unstuck hands from rawTracking (track collapsed, raw separated)")
				end
			end
		end

		if U and U.HandStuckLaw_Decide then
			local d = U.HandStuckLaw_Decide({
				pos_identity_lr = posIdLR,
				ang_identity_lr = angIdLR,
				pos_identity_hl = posIdHL,
				pos_identity_hr = posIdHR,
				pos_identity_raw_lr = posIdRaw,
				ang_identity_raw_lr = angIdRaw,
				track_dist_sqr = trackDist,
				raw_dist_sqr = rawDist,
				foregrip_active = g_VR.foregripActive and true or false,
				identity_healed = identityHealed,
				unstuck_applied = unstuckApplied,
			})
			g_VR._handStuckLaw = d
			g_VR._handStuckLawLabel = U.HandStuckLaw_StatusLabel and U.HandStuckLaw_StatusLabel(d) or nil
			g_VR._handStuckLawHmdExpect = U.HandStuckLaw_HmdExpect and U.HandStuckLaw_HmdExpect(d) or nil
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
				-- Offsets are authored for the right hand; left uses mirrored yaw/roll.
				if isLeft and offsetAng then
					offsetAng = Angle(offsetAng.p, -offsetAng.y, -offsetAng.r)
				end
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

	local function RequireWindowFocus()
		local cv = convars and convars.vrmod_require_window_focus
		if not cv and GetConVar then cv = GetConVar("vrmod_require_window_focus") end
		return cv and cv.GetBool and cv:GetBool() or false
	end

	local function DrawErrorOverlay()
		-- Default: do NOT require desktop focus — play in HMD while alt-tabbed / unfocused.
		-- Opt-in via vrmod_require_window_focus 1 (old "Please focus the game window" behavior).
		local lostFocus = RequireWindowFocus() and not system.HasFocus()
		local hasErr = g_VR.errorText and #g_VR.errorText > 0
		local isPaused = lostFocus or hasErr
		if isPaused then
			render.Clear(0, 0, 0, 255, true, true)
			cam.Start2D()
			local text = lostFocus and "Please focus the game window\n(or set vrmod_require_window_focus 0)" or g_VR.errorText
			draw.DrawText(text, "DermaLarge", ScrW() / 2, ScrH() / 2, Color(255, 255, 255, 255), TEXT_ALIGN_CENTER)
			cam.End2D()
			-- Soft-pause only: do not clear g_VR.active (that desynced session state).
			g_VR._focusPaused = true
			if not wasPaused then vrmod.logger.Info("VR session paused (%s)", lostFocus and "no window focus" or "error") end
			wasPaused = true
			return true
		else
			g_VR._focusPaused = false
			if wasPaused then vrmod.logger.Info("VR session resumed") end
			wasPaused = false
		end
	end

	local function UpdateViewFromEntity()
		local ply = LocalPlayer()
		if not IsValid(ply) then return end
		local viewEnt = ply:GetViewEntity()
		if not IsValid(viewEnt) then return end
		local hmd = g_VR.tracking and g_VR.tracking.hmd
		if not hmd or not hmd.pos then return end

		-- Keep tracking floor under the player's feet (standing height / stairs / ladders).
		-- Locomotion also sets origin.z; do it here so even without loco the view follows.
		-- While brush-climb is holding a hand, climb owns origin — stomping z from feet
		-- collapses world hand height and makes the next grab attach near the floor.
		local climbHold = false
		if vrmod.climbing then
			if isfunction(vrmod.climbing.IsHoldingLeft) and vrmod.climbing.IsHoldingLeft() then climbHold = true end
			if not climbHold and isfunction(vrmod.climbing.IsHoldingRight) and vrmod.climbing.IsHoldingRight() then climbHold = true end
		end
		if g_VR.origin and not ply:InVehicle() and not climbHold then
			local feet = ply:GetPos()
			g_VR.origin.z = feet.z
		end

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
		if g_VR.vehicle and g_VR.vehicle.glide then
			local forward = g_VR.view.angles:Forward() -- view/vehicle facing direction
			local up = g_VR.view.angles:Up()
			if g_VR.vehicle.type == "motorcycle" then
				-- Move 6 units forward instead of just down
				g_VR.view.origin = finalPos + forward * 8 + up * 3
			else
				-- Move slightly forward and up
				g_VR.view.origin = finalPos + forward * 6 + up * 6
			end

			if g_VR.tracking.pose_lefthand and g_VR.tracking.pose_lefthand.pos then
				g_VR.tracking.pose_lefthand.pos = g_VR.tracking.pose_lefthand.pos + forward * 5
			end
			if g_VR.tracking.pose_righthand and g_VR.tracking.pose_righthand.pos then
				g_VR.tracking.pose_righthand.pos = g_VR.tracking.pose_righthand.pos + forward * 5
			end
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
		-- Radar ortho must not leak: clear all orthographic fields (not just the flag)
		dst.ortho = false
		dst.ortholeft = nil
		dst.orthoright = nil
		dst.orthotop = nil
		dst.orthobottom = nil
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

		-- Cyclopean SoT (public) — never leave g_VR.view stuck on last eye
		local cyclopeanOrigin = view.origin
		-- SHARED orientation for both eyes (HMD). Per-eye rotation from OpenXR causes
		-- vertical disparity / warp when tilting head; tests + OpenVR legacy use one roll.
		local baseAngles = ang
		local znear = view.znear or 1
		local zfar = view.zfar or VIEW_ZFAR
		if zfar < 256 then zfar = VIEW_ZFAR end
		local dopost = view.dopostprocess and true or false
		-- Mode 2: engine post on nested dual RenderView races material workers.
		if (g_VR._matQueueMode or WantedMatQueueMode()) >= 2 then
			dopost = false
		end

		-- Eye placement + projection (rigid roll law).
		-- Source RenderView is symmetric FOV only — different L/R FOV or XR absolute
		-- eye poses + euler HMD angles shear the world when rolling (building "bends").
		-- Rigid policy: shared orientation, shared FOV/aspect, synthetic IPD on head Right().
		local eyeMode = (convars.vrmod_stereo_eye_mode and convars.vrmod_stereo_eye_mode:GetInt()) or 0
		if eyeMode < 0 then eyeMode = 0 end
		if eyeMode > 2 then eyeMode = 2 end
		local rigidCv = convars.vrmod_stereo_rigid
		local rigid = true
		if rigidCv then rigid = rigidCv:GetBool() end

		local eL = (g_VR.tracking and g_VR.tracking.eye_left) or (g_VR.rawTracking and g_VR.rawTracking.eye_left)
		local eR = (g_VR.tracking and g_VR.tracking.eye_right) or (g_VR.rawTracking and g_VR.rawTracking.eye_right)

		local fovL = hfovLeft
		local fovR = hfovRight
		local aspL = aspectLeft
		local aspR = aspectRight
		if eL and tonumber(eL.fov) and tonumber(eL.aspectratio) then
			fovL = tonumber(eL.fov)
			aspL = tonumber(eL.aspectratio)
		end
		if eR and tonumber(eR.fov) and tonumber(eR.aspectratio) then
			fovR = tonumber(eR.fov)
			aspR = tonumber(eR.aspectratio)
		end

		local xrIpdSrc = nil
		if eL and eR and eL.pos and eR.pos then
			local dist = eL.pos:Distance(eR.pos)
			if dist > 0.5 and dist < (scale * 0.2) then xrIpdSrc = dist end
		end

		-- Rigid path promotes legacy default half-IPD (0.5) to full IPD — half IPD flattens
		-- and worsens roll shear perception. Explicit user values other than 0.5 are kept.
		local eyeScaleRigid = eyeScale
		if rigid and math.abs(eyeScale - 0.5) < 0.001 then
			eyeScaleRigid = 1.0
		end

		local sdec = nil
		if vrmod.utils and vrmod.utils.StereoRigid_Decide then
			sdec = vrmod.utils.StereoRigid_Decide({
				rigid = rigid,
				eye_mode = eyeMode,
				has_xr_eyes = xrIpdSrc ~= nil,
				xr_ipd_source = xrIpdSrc,
				ipd_m = ipdUse,
				scale = scale,
				eye_scale = eyeScaleRigid,
				fov_l = fovL,
				fov_r = fovR,
				asp_l = aspL,
				asp_r = aspR,
			})
			g_VR._stereoRigidLaw = sdec
			g_VR._stereoRigidLabel = vrmod.utils.StereoRigid_StatusLabel
				and vrmod.utils.StereoRigid_StatusLabel(sdec) or nil
			g_VR._stereoRigidHmdExpect = vrmod.utils.StereoRigid_HmdExpect
				and vrmod.utils.StereoRigid_HmdExpect(sdec) or nil
		end

		local usedXrEyes = false
		-- Rigid: never use absolute XR eye positions (they fight euler HMD angles under roll).
		local wantXr = (not rigid) and (eyeMode == 0 or eyeMode == 1)
		if wantXr and eL and eR and eL.pos and eR.pos then
			local d = eL.pos:DistToSqr(eR.pos)
			if d > 0.01 and d < (scale * 0.2) * (scale * 0.2) then
				-- Apply vrmod_eyescale even on XR eyes: 1 = full headset IPD, 0 = cyclopean.
				-- (Previously XR path ignored eyescale entirely — IPD cal step did nothing.)
				local es = math.Clamp(eyeScale, 0, 1)
				local mid = (eL.pos + eR.pos) * 0.5
				g_VR.eyePosLeft = mid + (eL.pos - mid) * es
				g_VR.eyePosRight = mid + (eR.pos - mid) * es
				usedXrEyes = true
			end
		end
		if not usedXrEyes then
			-- half_ipd = distance from cyclopean to each eye along head Right()
			local half = (sdec and tonumber(sdec.half_ipd)) or (eyeOffset * 0.5 * eyeScale)
			g_VR.eyePosLeft = cyclopeanOrigin + forwardOffset + right * (-half)
			g_VR.eyePosRight = cyclopeanOrigin + forwardOffset + right * (half)
		end
		g_VR._stereoEyeMode = eyeMode
		g_VR._stereoUsedXrEyes = usedXrEyes
		g_VR._stereoRigid = rigid and true or false

		-- Projection: rigid → identical FOV/aspect both eyes (no L≠R Source frustum mismatch)
		if sdec and sdec.rigid then
			fovL = sdec.fov_l or sdec.fov or fovL
			fovR = sdec.fov_r or sdec.fov or fovR
			aspL = sdec.asp_l or sdec.aspect or aspL
			aspR = sdec.asp_r or sdec.aspect or aspR
		end

		-- G33 / W4: optional eye swap — SBS content only; IPD/FOV/pose single path
		local swapEyes = convars.vrmod_swap_eyes and convars.vrmod_swap_eyes:GetBool()
		local leftX, rightX
		if vrmod.utils and vrmod.utils.SwapEyesLaw_ResolveSbsHalves then
			leftX, rightX = vrmod.utils.SwapEyesLaw_ResolveSbsHalves(rtHalfW, swapEyes)
		else
			leftX, rightX = 0, rtHalfW
			if swapEyes then leftX, rightX = rtHalfW, 0 end
		end
		if vrmod.utils and vrmod.utils.SwapEyesLaw_Decide then
			local ed = vrmod.utils.SwapEyesLaw_Decide({
				swap = swapEyes,
				rt_half_w = rtHalfW,
				dual_pose_fork = false,
				ipd_mutated = false,
				fov_swapped = false,
			})
			g_VR._swapEyesLaw = ed
			g_VR._swapEyesLawLabel = vrmod.utils.SwapEyesLaw_StatusLabel
				and vrmod.utils.SwapEyesLaw_StatusLabel(ed) or nil
			g_VR._swapEyesLawHmdExpect = vrmod.utils.SwapEyesLaw_HmdExpect
				and vrmod.utils.SwapEyesLaw_HmdExpect(ed) or nil
		end

		SyncEyeView(viewLeft, g_VR.eyePosLeft, fovL, aspL, leftX, 0, rtHalfW, rtH, baseAngles, znear, dopost, zfar)
		SyncEyeView(viewRight, g_VR.eyePosRight, fovR, aspR, rightX, 0, rtHalfW, rtH, baseAngles, znear, dopost, zfar)

		renderingEyes = true
		local okEyes, errEyes = pcall(function()
			-- World RT captures (radar ortho, etc.) MUST run with no stereo RT pushed.
			-- Nested RenderView under g_VR.rt flickers the entire map.
			g_VR.stereoEye = nil
			g_VR.stereoRtActive = false
			g_VR.stereoFrame = (g_VR.stereoFrame or 0) + 1
			hook.Call("VRMod_PreStereoCapture", nil)
			-- Barrier: radar ortho / fog / DepthRange / alpha override must not
			-- leak into SBS eyes (model flicker + clipped world).
			if vrmod.SanitizeAfterNestedWorldCapture then
				pcall(vrmod.SanitizeAfterNestedWorldCapture)
			end
			ResetStereoEyeState()
			if view then
				view.ortho = false
				view.ortholeft = nil
				view.orthoright = nil
				view.orthotop = nil
				view.orthobottom = nil
				view.zfar = VIEW_ZFAR
			end

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

			local mqNow = g_VR._matQueueMode or WantedMatQueueMode()
			-- Mode 2: always single-pass (second RenderView = CThread crash on Linux).
			-- Convar only documents intent; dual-eye under 2 is not supported yet.
			local singlePass = mqNow >= 2
			g_VR._mq2SinglePass = singlePass

			-- LEFT eye — draw only (angles = shared HMD roll for both eyes)
			view.origin = g_VR.eyePosLeft
			view.angles = baseAngles
			view.fov = fovL
			view.aspectratio = aspL
			view.x, view.y, view.w, view.h = leftX, 0, rtHalfW, rtH
			g_VR.stereoEye = "left"
			render.SetScissorRect(leftX, 0, leftX + rtHalfW, rtH, true)
			hook.Call("VRMod_PreRender", nil, "left")
			SafeRenderView(viewLeft)

			if singlePass then
				-- mat_queue_mode 2: NO second RenderView (CThread crash on Linux).
				-- Right half of SBS RT stays unpainted — submit maps BOTH eyes to the
				-- LEFT half (mono stereo) so HMD never has one black eye.
				g_VR._mq2MonoLeftForBoth = true
				render.SetScissorRect(0, 0, 0, 0, false)
				ResetStereoEyeState()
				g_VR.stereoEye = "right"
				hook.Call("VRMod_PreRender", nil, "right")
			else
				g_VR._mq2MonoLeftForBoth = false
				-- Depth only — never Clear colour (would wipe left-eye world + decals).
				ResetStereoEyeState()
				render.ClearDepth(true)
				SyncMatQueueBetweenEyes()

				-- RIGHT eye — full second RenderView (mode 0/1); same roll as left
				view.origin = g_VR.eyePosRight
				view.angles = baseAngles
				view.fov = fovR
				view.aspectratio = aspR
				view.x, view.y, view.w, view.h = rightX, 0, rtHalfW, rtH
				g_VR.stereoEye = "right"
				render.SetScissorRect(rightX, 0, rightX + rtHalfW, rtH, true)
				hook.Call("VRMod_PreRender", nil, "right")
				SafeRenderView(viewRight)
			end

			render.SetScissorRect(0, 0, 0, 0, false)
			g_VR.stereoEye = nil
			ResetStereoEyeState()

			-- Restore cyclopean public SoT
			view.origin = cyclopeanOrigin
			view.angles = baseAngles
			view.fov = fovL
			view.aspectratio = aspL
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

		-- Desktop mirror after PopRT (never nested under stereo RT).
		-- Modes: 1=none (black desktop, HMD untouched) 2=left 3=right 4=follow.
		-- Always re-read convar here — do not wait on SoftRefresh (desktopview is not FOV).
		local dv = (convars.vrmod_desktopview and convars.vrmod_desktopview:GetInt()) or g_VR.desktopView or 1
		if vrmod.DesktopCam and vrmod.DesktopCam.ClampDesktopView then
			dv = vrmod.DesktopCam.ClampDesktopView(dv)
		else
			dv = math.floor(tonumber(dv) or 1)
			if dv < 1 then dv = 1 end
			if dv > 4 then dv = 4 end
		end
		g_VR.desktopView = dv
		if g_VR.rtWidth and g_VR.rtHeight and vrmod.utils and vrmod.utils.ComputeDesktopCrop then
			cropVerticalMargin, cropHorizontalOffset = vrmod.utils.ComputeDesktopCrop(dv, g_VR.rtWidth, g_VR.rtHeight)
		end

		-- Restore safe GL state every frame (eye-crop CullMode must not leak into next stereo).
		pcall(function()
			render.SetScissorRect(0, 0, 0, 0, false)
			render.CullMode(0)
		end)

		local DC = vrmod.DesktopCam
		local isFollow = (DC and DC.IsFollowMode and DC.IsFollowMode(dv)) or (dv == 4)
		local isEyeCrop = (DC and DC.IsEyeCropMode and DC.IsEyeCropMode(dv)) or (dv == 2 or dv == 3)
		local isNone = (not isFollow and not isEyeCrop) -- mode 1
		local U = vrmod.utils
		if U and U.DesktopMirror_Decide then
			local d = U.DesktopMirror_Decide({
				desktop_view = dv,
				vr_active = true,
				mid_frame = true,
				after_submit = false,
				sample_stereo_rt = isEyeCrop and true or false,
				attempt_present = isEyeCrop or isFollow,
			})
			g_VR._desktopMirrorLaw = d
			g_VR._desktopMirrorLawLabel = U.DesktopMirror_StatusLabel
				and U.DesktopMirror_StatusLabel(d) or nil
			g_VR._desktopMirrorHmdExpect = U.DesktopMirror_HmdExpect
				and U.DesktopMirror_HmdExpect(d) or nil
		end

		if isNone then
			-- None: stop follow-cam; do NOT sample stereo RT; do NOT SoftRefresh FOV.
			-- Clear desktop to black so the GMod window is intentionally empty (HMD keeps stereo).
			if DC and DC.SyncFromDesktopView then
				pcall(DC.SyncFromDesktopView, dv)
			end
			pcall(function()
				local w, h = ScrW(), ScrH()
				if w and h and w > 0 and h > 0 then
					cam.Start2D()
					surface.SetDrawColor(0, 0, 0, 255)
					surface.DrawRect(0, 0, w, h)
					cam.End2D()
				end
				render.CullMode(0)
			end)
		elseif isFollow then
			if DC then
				if DC.SyncFromDesktopView then pcall(DC.SyncFromDesktopView, dv) end
				if DC.CaptureFrame then pcall(DC.CaptureFrame) end
				if DC.PresentDesktop then pcall(DC.PresentDesktop) end
			end
			pcall(function() render.CullMode(0) end)
		elseif isEyeCrop and g_VR.rtMaterial then
			-- Legacy mid-frame eye crop (samples stereo RT material — after PopRT only).
			pcall(function()
				render.CullMode(1)
				surface.SetDrawColor(255, 255, 255, 255)
				surface.SetMaterial(g_VR.rtMaterial)
				local ho = tonumber(cropHorizontalOffset) or 0
				local vm = tonumber(cropVerticalMargin) or 0
				surface.DrawTexturedRectUV(-1, -1, 2, 2, ho, 1 - vm, 0.5 + ho, vm)
				render.CullMode(0)
			end)
			if DC and DC.SyncFromDesktopView then
				pcall(DC.SyncFromDesktopView, dv)
			end
		elseif DC and DC.SyncFromDesktopView then
			pcall(DC.SyncFromDesktopView, dv)
		end
	end

	-- 1) Startup checks & init
	local function PerformStartup()
		-- Flush any deferred exit first so restart is never racing soft-pause.
		timer.Remove("vrmod_async_shutdown")
		timer.Remove("vrmod_mat_queue_restore")
		timer.Remove("vrmod_mat_queue_apply")
		matQueueAppliedForSession = false
		pcall(function()
			if isfunction(VRMOD_SetSubmitEnabled) then VRMOD_SetSubmitEnabled(false) end
			if isfunction(VRMOD_Shutdown) then VRMOD_Shutdown() end -- full teardown (cb59aeb)
		end)

		-- G39 / W11: human init errors (codes 108/215 + module zip), never silent
		local IL = vrmod.utils
		local err = vrmod.GetStartupError()
		if err then
			vrmod.logger.Err("Failed to start: " .. err)
			local human = IL and IL.InitLaw_Humanize and IL.InitLaw_Humanize({
				err = err,
				module_version = g_VR.moduleVersion or 0,
				backend = (vrmod.GetBackendPolicy and (vrmod.GetBackendPolicy() or {}).backend) or "openxr",
			}) or nil
			local toastShown = false
			if vrmod.Toast then
				vrmod.Toast((human and human.toast) or ("VR start blocked: " .. tostring(err)),
					(IL and IL.InitLaw_ToastSeconds and IL.InitLaw_ToastSeconds()) or 10, "error")
				toastShown = true
			end
			if human and human.overlay then
				g_VR.errorText = human.overlay
			end
			if IL and IL.InitLaw_Decide then
				local d = IL.InitLaw_Decide({
					ok = false,
					err = err,
					module_version = g_VR.moduleVersion or 0,
					toast_shown = toastShown,
				})
				g_VR._initLaw = d
				g_VR._initLawLabel = IL.InitLaw_StatusLabel and IL.InitLaw_StatusLabel(d) or nil
				g_VR._initLawHmdExpect = IL.InitLaw_HmdExpect and IL.InitLaw_HmdExpect(d) or nil
			end
			return false
		end

		local okInit, initErr = pcall(function()
			if VRMOD_Init == false or VRMOD_Init() == false then
				error("VRMOD_Init returned false")
			end
		end)
		if not okInit then
			vrmod.logger.Err("Init failed: %s", tostring(initErr))
			local human = IL and IL.InitLaw_Humanize and IL.InitLaw_Humanize({
				err = initErr,
				module_version = g_VR.moduleVersion or 0,
				backend = (vrmod.GetBackendPolicy and (vrmod.GetBackendPolicy() or {}).backend) or "openxr",
			}) or nil
			local toastShown = false
			if vrmod.Toast then
				vrmod.Toast((human and human.toast) or "VR_Init failed — OpenXR/OpenVR runtime running?",
					(IL and IL.InitLaw_ToastSeconds and IL.InitLaw_ToastSeconds()) or 10, "error")
				toastShown = true
			end
			if human and human.overlay then
				g_VR.errorText = human.overlay
			end
			if IL and IL.InitLaw_Decide then
				local d = IL.InitLaw_Decide({
					ok = false,
					err = initErr,
					module_version = g_VR.moduleVersion or 0,
					toast_shown = toastShown,
				})
				g_VR._initLaw = d
				g_VR._initLawLabel = IL.InitLaw_StatusLabel and IL.InitLaw_StatusLabel(d) or nil
				g_VR._initLawHmdExpect = IL.InitLaw_HmdExpect and IL.InitLaw_HmdExpect(d) or nil
			end
			return false
		end
		if IL and IL.InitLaw_Decide then
			local d = IL.InitLaw_Decide({
				ok = true,
				module_version = g_VR.moduleVersion or 0,
			})
			g_VR._initLaw = d
			g_VR._initLawLabel = IL.InitLaw_StatusLabel and IL.InitLaw_StatusLabel(d) or nil
			g_VR._initLawHmdExpect = IL.InitLaw_HmdExpect and IL.InitLaw_HmdExpect(d) or nil
		end
		return true
	end

	-- 2) Convar overrides for performance
	local function OverridePerformanceConvars()
		timer.Remove("vrmod_mat_queue_restore")
		timer.Remove("vrmod_async_shutdown")
		PERFORMANCE_CONVARS.r_3dsky = tostring(convars.vrmod_skybox:GetBool() and 1 or 0)

		local mq = WantedMatQueueMode()
		g_VR._matQueueMode = mq

		-- Soft pins only — never mat_queue_mode (setConvarValue/overrideConvar ban it).
		-- Under mat_queue 2: skip almost all material/render convar thrash (workers already
		-- fragile; flipping mat_* at VR start can Illegal-termination crash).
		if mq < 2 then
			for cvar, val in pairs(PERFORMANCE_CONVARS) do
				overrideConvar(cvar, val)
			end
			overrideConvar("cl_threaded_bone_setup", "1")
			overrideConvar("r_threaded_particles", "1")
		else
			-- Minimal pins only (audio/focus) — no mat_* / r_* material churn.
			overrideConvar("snd_mute_losefocus", "0")
			overrideConvar("engine_no_focus_sleep", "0")
		end

		if not matQueueAppliedForSession then
			matQueueAppliedForSession = true
			local mcore = GetConVar("gmod_mcore_test")
			local mcoreOn = mcore and (mcore.GetInt and mcore:GetInt() or tonumber(mcore:GetString()) or 0) ~= 0
			if vrmod.logger then
				vrmod.logger.Info(
					"mat_queue_mode=%s mcore=%s single_pass=%s (VR never writes mat_queue/mcore)",
					tostring(mq),
					mcoreOn and "1" or "0",
					tostring(mq >= 2)
				)
			end
			if mq >= 2 and vrmod.Toast and not g_VR._mq2Hint then
				g_VR._mq2Hint = true
				vrmod.Toast(
					mcoreOn
						and "mat_queue 2: mono both eyes (left); set mat_queue_mode 1 for true dual · mcore 0 if crash"
						or "mat_queue 2: mono both eyes from left · set mat_queue_mode 1 for true stereo dual",
					7,
					"hint"
				)
			end
		end
	end

	-- Apply UV submit bounds + C++ crop policy (b1a5e9e-era; ComputeSubmitBounds)
	local function ApplySubmitBounds()
		if not g_VR.active and not leftCalc then return end
		if type(leftCalc) ~= "table" or type(rightCalc) ~= "table" then return end
		if not VRMOD_SetSubmitTextureBounds then return end
		local hOffset = convars.vrmod_horizontaloffset:GetFloat()
		local vOffset = convars.vrmod_verticaloffset:GetFloat()
		local scaleFactor = convars.vrmod_scalefactor:GetFloat()
		local renderOffset = convars.vrmod_renderoffset:GetBool()
		local lensBend = (convars.vrmod_lens_bend and convars.vrmod_lens_bend:GetFloat()) or 0
		local bounds = {vrmod.utils.ComputeSubmitBounds(leftCalc, rightCalc, hOffset, vOffset, scaleFactor, renderOffset, lensBend)}
		-- mq2 single-pass: mirror left UV to both eyes if helpers exist
		local mqLive = g_VR._matQueueMode or WantedMatQueueMode()
		local monoBoth = g_VR._mq2SinglePass or g_VR._mq2MonoLeftForBoth or (mqLive >= 2)
		if monoBoth and vrmod.utils and vrmod.utils.SubmitBounds_MirrorLeftToBoth then
			bounds = {vrmod.utils.SubmitBounds_MirrorLeftToBoth(bounds)}
		elseif monoBoth and #bounds >= 8 then
			bounds[5], bounds[6], bounds[7], bounds[8] = bounds[1], bounds[2], bounds[3], bounds[4]
		end
		g_VR._submitMonoBothEyes = monoBoth and true or false
		VRMOD_SetSubmitTextureBounds(unpack(bounds))
		if isfunction(VRMOD_SetRTTextureFlip) then
			VRMOD_SetRTTextureFlip(not system.IsWindows())
		end
		if isfunction(VRMOD_SetSubmitCropMode) then
			local crop = (convars.vrmod_submit_crop and convars.vrmod_submit_crop:GetInt()) or 0
			if crop < 0 then crop = 0 end
			if crop > 2 then crop = 2 end
			if monoBoth and crop == 2 then crop = 0 end
			VRMOD_SetSubmitCropMode(crop)
			g_VR._submitCropMode = crop
		end
	end

	-- Public force-apply for calibration / live UI (immediate, not deferred cmd)
	function vrmod.ForceApplySubmitBounds()
		ApplySubmitBounds()
	end

	-- Live update: UV bounds + crop mode (offsets/scale/eye dials)
	-- G36 / W5: border cvars → submit_bounds only (never mid-frame FOV fight)
	local function BindBorderConvarCallbacks()
		local names = {
			"vrmod_horizontaloffset",
			"vrmod_verticaloffset",
			"vrmod_scalefactor",
			"vrmod_renderoffset",
			"vrmod_submit_crop",
			"vrmod_lens_bend",
		}
		for _, name in ipairs(names) do
			cvars.RemoveChangeCallback(name, "vrmod_submit_bounds")
			cvars.AddChangeCallback(name, function()
				if not g_VR.active then return end
				local kind = vrmod.utils and vrmod.utils.FovZLaw_RefreshKind
					and vrmod.utils.FovZLaw_RefreshKind(name) or "submit_bounds"
				if kind == "submit_bounds" or kind == "none" then
					ApplySubmitBounds()
				end
				if vrmod.utils and vrmod.utils.FovZLaw_Decide then
					local d = vrmod.utils.FovZLaw_Decide({
						cvar = name,
						vr_active = true,
						soft_refreshed = false,
						mid_frame_uv_and_fov = false,
					})
					g_VR._fovZLaw = d
					g_VR._fovZLawLabel = vrmod.utils.FovZLaw_StatusLabel
						and vrmod.utils.FovZLaw_StatusLabel(d) or nil
					g_VR._fovZLawHmdExpect = vrmod.utils.FovZLaw_HmdExpect
						and vrmod.utils.FovZLaw_HmdExpect(d) or nil
				end
			end, "vrmod_submit_bounds")
		end
	end

	-- True once GetDisplayInfo returned a real (non-identity) projection.
	-- After full OpenXR teardown, session is deferred until Share/Render — first
	-- GetDisplayInfo returns identity FOV, so viewscale/fov/borders look "stuck".
	local displayParamsLive = false

	-- Soft-reload projection/FOV/viewscale (also after cold restart when session goes RUNNING).
	--- Desktop view only (no FOV / GetDisplayInfo). Safe to call when switching to none.
	local function ApplyDesktopViewFromConvar()
		if not convars or not convars.vrmod_desktopview then return end
		local dv = convars.vrmod_desktopview:GetInt()
		if vrmod.DesktopCam and vrmod.DesktopCam.ClampDesktopView then
			dv = vrmod.DesktopCam.ClampDesktopView(dv)
		end
		g_VR.desktopView = dv
		if g_VR.rtWidth and g_VR.rtHeight and vrmod.utils and vrmod.utils.ComputeDesktopCrop then
			cropVerticalMargin, cropHorizontalOffset = vrmod.utils.ComputeDesktopCrop(dv, g_VR.rtWidth, g_VR.rtHeight)
		end
		if vrmod.DesktopCam and vrmod.DesktopCam.SyncFromDesktopView then
			pcall(vrmod.DesktopCam.SyncFromDesktopView, dv)
		end
	end

	local function SoftRefreshDisplayParams()
		if not g_VR.active and not g_VR.rt then return false end
		-- Always apply desktop view first (even if GetDisplayInfo fails).
		ApplyDesktopViewFromConvar()
		local dp = ComputeDisplayParams()
		if not dp then return false end
		local live = dp.projLive and true or false
		leftCalc = dp.leftCalc or leftCalc
		rightCalc = dp.rightCalc or rightCalc
		hfovLeft = dp.hfovL or hfovLeft
		hfovRight = dp.hfovR or hfovRight
		aspectLeft = dp.aspL or aspectLeft
		aspectRight = dp.aspR or aspectRight
		ipd = dp.ipd or ipd
		eyez = dp.eyez or eyez
		ApplySubmitBounds()
		if live then
			displayParamsLive = true
			if vrmod.logger then
				vrmod.logger.Info(
					"Display params live FOV L=%.1f R=%.1f — viewscale/borders applied",
					tonumber(hfovLeft) or 0, tonumber(hfovRight) or 0
				)
			end
		end
		return live
	end

	-- Public for Video calibration FOV / viewscale dials
	function vrmod.SoftRefreshDisplayParams()
		return SoftRefreshDisplayParams()
	end

	-- Re-read session convars into g_VR (offsets, scale, view, pins).
	-- Inlined — do not call later local Setup* (Lua scoping).
	local function ApplySessionSettingsFromConvars()
		g_VR.scale = convars.vrmod_scale:GetFloat()
		g_VR.rightControllerOffsetPos = Vector(
			convars.vrmod_controlleroffset_x:GetFloat(),
			convars.vrmod_controlleroffset_y:GetFloat(),
			convars.vrmod_controlleroffset_z:GetFloat()
		)
		g_VR.leftControllerOffsetPos = g_VR.rightControllerOffsetPos * Vector(1, -1, 1)
		g_VR.rightControllerOffsetAng = Angle(
			convars.vrmod_controlleroffset_pitch:GetFloat(),
			convars.vrmod_controlleroffset_yaw:GetFloat(),
			convars.vrmod_controlleroffset_roll:GetFloat()
		)
		g_VR.leftControllerOffsetAng = g_VR.rightControllerOffsetAng
		if g_VR.view then
			g_VR.view.znear = convars.vrmod_znear:GetFloat()
			g_VR.view.dopostprocess = convars.vrmod_postprocess:GetBool()
			g_VR.view.w = g_VR.view.w or (g_VR.rtWidth and g_VR.rtWidth / 2)
			g_VR.view.h = g_VR.view.h or g_VR.rtHeight
		end
		PERFORMANCE_CONVARS.r_3dsky = tostring(convars.vrmod_skybox:GetBool() and 1 or 0)
		setConvarValue("r_3dsky", PERFORMANCE_CONVARS.r_3dsky)
		SoftRefreshDisplayParams()
		ApplySubmitBounds()
		PushKnownSubmitSize()
	end

	-- After cold Init, session becomes RUNNING a few frames after Share — keep
	-- re-pulling FOV/IPD/submit bounds until live or timeout.
	local function ScheduleDisplayParamsCatchup()
		timer.Remove("vrmod_display_params_catchup")
		displayParamsLive = false
		local tries = 0
		timer.Create("vrmod_display_params_catchup", 0, 90, function()
			tries = tries + 1
			if not g_VR or not g_VR.active then
				timer.Remove("vrmod_display_params_catchup")
				return
			end
			if SoftRefreshDisplayParams() or tries >= 90 then
				timer.Remove("vrmod_display_params_catchup")
				if displayParamsLive then
					-- One more full convar pass once FOV is real
					ApplySessionSettingsFromConvars()
				elseif vrmod.logger then
					vrmod.logger.Warn("Display params still deferred after catchup — FOV may use defaults")
				end
			end
		end)
	end

	local function BindRenderProfileCallbacks()
		-- G36 / W5: FOV profile → SoftRefresh only; znear/session → session path
		local names = {
			"vrmod_fovscale_x",
			"vrmod_fovscale_y",
			"vrmod_viewscale",
			"vrmod_desktopview",
			"vrmod_eyescale",
			"vrmod_swap_eyes",
			"vrmod_znear",
			"vrmod_postprocess",
		}
		for _, name in ipairs(names) do
			cvars.RemoveChangeCallback(name, "vrmod_render_profile")
			cvars.AddChangeCallback(name, function()
				if not g_VR.active then return end
				local kind = vrmod.utils and vrmod.utils.FovZLaw_RefreshKind
					and vrmod.utils.FovZLaw_RefreshKind(name)
				if not kind then
					kind = (name == "vrmod_znear" or name == "vrmod_postprocess") and "session" or "soft_display"
				end
				local softOk = false
				if kind == "desktop_view" then
					-- Mirror mode only — never rewrite FOV/submit (none was blacking HMD).
					ApplyDesktopViewFromConvar()
					softOk = true
				elseif kind == "session" then
					ApplySessionSettingsFromConvars()
					softOk = true -- session path includes SoftRefresh
				else
					SoftRefreshDisplayParams()
					softOk = true -- soft path invoked (proj may still be deferred)
				end
				if vrmod.utils and vrmod.utils.FovZLaw_Decide then
					local fx = convars.vrmod_fovscale_x and convars.vrmod_fovscale_x:GetFloat() or 1
					local fy = convars.vrmod_fovscale_y and convars.vrmod_fovscale_y:GetFloat() or 1
					local zn = convars.vrmod_znear and convars.vrmod_znear:GetFloat() or 1
					local d = vrmod.utils.FovZLaw_Decide({
						cvar = name,
						vr_active = true,
						soft_refreshed = softOk,
						fov_x = fx,
						fov_y = fy,
						znear = zn,
						mid_frame_uv_and_fov = false,
					})
					g_VR._fovZLaw = d
					g_VR._fovZLawLabel = vrmod.utils.FovZLaw_StatusLabel
						and vrmod.utils.FovZLaw_StatusLabel(d) or nil
					g_VR._fovZLawHmdExpect = vrmod.utils.FovZLaw_HmdExpect
						and vrmod.utils.FovZLaw_HmdExpect(d) or nil
				end
			end, "vrmod_render_profile")
		end
		-- Controller offsets / world scale: live re-apply without full restart
		local offsetNames = {
			"vrmod_scale",
			"vrmod_controlleroffset_x",
			"vrmod_controlleroffset_y",
			"vrmod_controlleroffset_z",
			"vrmod_controlleroffset_pitch",
			"vrmod_controlleroffset_yaw",
			"vrmod_controlleroffset_roll",
		}
		for _, name in ipairs(offsetNames) do
			cvars.RemoveChangeCallback(name, "vrmod_session_settings")
			cvars.AddChangeCallback(name, function()
				if not g_VR.active then return end
				ApplySessionSettingsFromConvars()
			end, "vrmod_session_settings")
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
		-- G32 / W7: ShareTexture fail toasts via pure StereoSelfTest law
		local ST = vrmod.utils
		local okBegin, errBegin = SafeShareTextureBegin(
			(dp.passEyeArgs and eyeW) or nil,
			(dp.passEyeArgs and eyeH) or nil
		)
		local toastBegin = false
		local wantBeginToast = (ST and ST.StereoSelfTest_ShouldToastShareBegin
			and ST.StereoSelfTest_ShouldToastShareBegin(okBegin)) or (not okBegin)
		if wantBeginToast and not okBegin then
			if vrmod.logger then
				vrmod.logger.Err("ShareTextureBegin failed: %s (eye %sx%s rt %sx%s)",
					tostring(errBegin), tostring(eyeW), tostring(eyeH),
					tostring(g_VR.rtWidth), tostring(g_VR.rtHeight))
			end
			if vrmod.Toast then
				local msg = (ST and ST.StereoSelfTest_ShareBeginToast and ST.StereoSelfTest_ShareBeginToast(g_VR.rtWidth, g_VR.rtHeight))
					or string.format(
						"ShareTexture begin failed (%sx%s) — HMD may stay black. Lower supersample / check module.",
						tostring(g_VR.rtWidth), tostring(g_VR.rtHeight)
					)
				local sec = (ST and ST.StereoSelfTest_ToastSeconds and ST.StereoSelfTest_ToastSeconds()) or 8
				vrmod.Toast(msg, sec, "error")
				toastBegin = true
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
		local toastFin = false
		if ST and ST.StereoSelfTest_ShouldToastShareFinish and ST.StereoSelfTest_ShouldToastShareFinish(okFin) then
			if vrmod.logger then
				vrmod.logger.Err("ShareTextureFinish failed: %s (rt %sx%s)",
					tostring(errFin), tostring(g_VR.rtWidth), tostring(g_VR.rtHeight))
			end
			if vrmod.Toast then
				local msg = (ST.StereoSelfTest_ShareFinishToast and ST.StereoSelfTest_ShareFinishToast(g_VR.rtWidth, g_VR.rtHeight))
					or string.format(
						"ShareTexture finish failed (rt %sx%s) — desktop OK / HMD black often means this. Restart SteamVR + GMod.",
						tostring(g_VR.rtWidth), tostring(g_VR.rtHeight)
					)
				local sec = (ST.StereoSelfTest_ToastSeconds and ST.StereoSelfTest_ToastSeconds()) or 8
				vrmod.Toast(msg, sec, "error")
				toastFin = true
			end
		elseif not okFin then
			-- Fallback if pure helpers missing
			if vrmod.logger then
				vrmod.logger.Err("ShareTextureFinish failed: %s (rt %sx%s)",
					tostring(errFin), tostring(g_VR.rtWidth), tostring(g_VR.rtHeight))
			end
			if vrmod.Toast then
				vrmod.Toast(string.format(
					"ShareTexture finish failed (rt %sx%s) — desktop OK / HMD black often means this. Restart SteamVR + GMod.",
					tostring(g_VR.rtWidth), tostring(g_VR.rtHeight)
				), 8, "error")
				toastFin = true
			end
		end
		if ST and ST.StereoSelfTest_ShareOk then
			g_VR._shareTextureOk = ST.StereoSelfTest_ShareOk(okBegin, okFin)
		else
			g_VR._shareTextureOk = okBegin and okFin and true or false
		end
		if ST and ST.StereoSelfTest_Decide then
			local d = ST.StereoSelfTest_Decide({
				ok_begin = okBegin,
				ok_finish = okFin,
				share_ok = g_VR._shareTextureOk,
				toast_share_begin = (not okBegin) and toastBegin or nil,
				toast_share_finish = (not okFin) and toastFin or nil,
			})
			g_VR._stereoSelfTestLaw = d
			g_VR._stereoSelfTestLabel = ST.StereoSelfTest_StatusLabel and ST.StereoSelfTest_StatusLabel(d) or nil
			g_VR._stereoSelfTestHmdExpect = ST.StereoSelfTest_HmdExpect and ST.StereoSelfTest_HmdExpect(d) or nil
		end
		-- Authoritative SBS size for OpenXR submit (mat_queue 2 cannot glGetTexLevel)
		PushKnownSubmitSize()
		-- Share may have created the session — re-pull FOV if now live (else catchup).
		SoftRefreshDisplayParams()
		ApplySubmitBounds()
		BindBorderConvarCallbacks()
		BindRenderProfileCallbacks()
	end

	-- 4) Action manifest & input initialization (never abort VR start)
	-- Module resolves: getcwd()/garrysmod/data/<arg> — files must live in DATA/vrmod/.
	local function RewriteActionManifestFiles()
		if not file.Exists("vrmod", "DATA") then file.CreateDir("vrmod") end
		-- Load customs first, then write base manifest WITH custom boolean actions injected.
		-- Without this, every VR start wiped custom actions from the module.
		if isfunction(VRUtilLoadCustomActions) then pcall(VRUtilLoadCustomActions) end
		if isfunction(VRUtilWriteActionManifestWithCustoms) then
			pcall(VRUtilWriteActionManifestWithCustoms)
		elseif g_VR.action_manifest then
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
		-- G31 / W6: force-rewrite self-heal (pure law); never abort VR; toast on fail
		local U = vrmod.utils
		local forceRewrite = not U or not U.BindingsLaw_ForceRewriteOnStart or U.BindingsLaw_ForceRewriteOnStart()
		if forceRewrite then
			RewriteActionManifestFiles()
		end
		local manPath = (U and U.BindingsLaw_ManifestRelPath and U.BindingsLaw_ManifestRelPath())
			or "vrmod/vrmod_action_manifest.txt"
		local hasFile = file.Exists(manPath, "DATA")
		local firstOk, errMan = pcall(VRMOD_SetActionManifest, manPath)
		local retryOk = false
		if not firstOk then
			-- Retry after force rewrite (corrupt DATA / first-run race)
			if not U or not U.BindingsLaw_ShouldRetryAfterFail or U.BindingsLaw_ShouldRetryAfterFail(1) then
				RewriteActionManifestFiles()
				retryOk, errMan = pcall(VRMOD_SetActionManifest, manPath)
			end
		end
		local okMan = firstOk or retryOk
		hasFile = file.Exists(manPath, "DATA")
		local toastShown = false
		if not okMan then
			local detail = tostring(errMan or "unknown")
			if vrmod.logger then
				vrmod.logger.Err("SetActionManifest failed (VR continues without bindings): %s hasFile=%s", detail, tostring(hasFile))
			end
			local toastMsg = (U and U.BindingsLaw_ToastMessage and U.BindingsLaw_ToastMessage())
				or "Controller bindings failed — reinstall VRMod module; ensure data/vrmod/vrmod_action_manifest.txt exists. Restart VR runtime if needed."
			local toastSec = (U and U.BindingsLaw_ToastSeconds and U.BindingsLaw_ToastSeconds()) or 8
			if vrmod.Toast then
				vrmod.Toast(toastMsg, toastSec, "error")
				toastShown = true
			end
			g_VR.errorText = (U and U.BindingsLaw_ErrorOverlayText and U.BindingsLaw_ErrorOverlayText())
				or "Bindings failed — check console / reinstall module"
			local clearSec = (U and U.BindingsLaw_OverlayClearSeconds and U.BindingsLaw_OverlayClearSeconds()) or 12
			timer.Simple(clearSec, function()
				if g_VR and g_VR.errorText and string.find(g_VR.errorText, "Bindings failed", 1, true) then
					g_VR.errorText = ""
				end
			end)
			-- Law: never abort VR start on bindings fail (BindingsLaw_AbortVrOnFail == false)
		else
			g_VR._actionManifestOk = true
		end
		if U and U.BindingsLaw_Decide then
			local d = U.BindingsLaw_Decide({
				force_rewrite = forceRewrite,
				first_ok = firstOk,
				retry_ok = retryOk,
				has_file = hasFile,
				toast_shown = not okMan and toastShown or nil,
			})
			g_VR._bindingsLaw = d
			g_VR._bindingsLawLabel = U.BindingsLaw_StatusLabel and U.BindingsLaw_StatusLabel(d) or nil
			g_VR._bindingsLawHmdExpect = U.BindingsLaw_HmdExpect and U.BindingsLaw_HmdExpect(d) or nil
		end

		-- G34 / W12: action set before first input (pure FlyAwayLaw)
		local ply = LocalPlayer()
		local inVeh = IsValid(ply) and ply.InVehicle and ply:InVehicle()
		local FA = vrmod.utils
		local set = (FA and FA.FlyAwayLaw_ResolveActionSet and FA.FlyAwayLaw_ResolveActionSet(inVeh))
			or (inVeh and "/actions/driving" or "/actions/main")
		local baseSet = (FA and FA.FlyAwayLaw_ActionSetBase and FA.FlyAwayLaw_ActionSetBase()) or "/actions/base"
		pcall(VRMOD_SetActiveActionSets, baseSet, set)
		if FA and FA.FlyAwayLaw_Decide then
			local d = FA.FlyAwayLaw_Decide({
				in_vehicle = inVeh,
				action_set = set,
				expect_action_set = true,
				origin_set_to_feet = nil, -- origin setup follows
			})
			g_VR._flyAwayLaw = d
			g_VR._flyAwayLawLabel = FA.FlyAwayLaw_StatusLabel and FA.FlyAwayLaw_StatusLabel(d) or nil
			g_VR._flyAwayLawHmdExpect = FA.FlyAwayLaw_HmdExpect and FA.FlyAwayLaw_HmdExpect(d) or nil
		end
		-- Customs already loaded in RewriteActionManifestFiles
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
		local ply = LocalPlayer()
		-- Feet of the gmod player = tracking floor. Keep Z in sync so standing height matches.
		g_VR.origin = IsValid(ply) and ply:GetPos() or Vector(0, 0, 0)
		g_VR.originAngle = g_VR.originAngle or Angle(0, 0, 0)
		g_VR._flyAwayOriginFeet = IsValid(ply) and true or false
		g_VR._flyAwayStartTime = CurTime()
		g_VR._flyAwaySnapped = false
		if vrmod.utils and vrmod.utils.FlyAwayLaw_Decide then
			local d = vrmod.utils.FlyAwayLaw_Decide({
				in_vehicle = IsValid(ply) and ply.InVehicle and ply:InVehicle(),
				action_set = g_VR._flyAwayLaw and g_VR._flyAwayLaw.want_action_set or nil,
				origin_set_to_feet = g_VR._flyAwayOriginFeet,
				expect_action_set = true,
			})
			g_VR._flyAwayLaw = d
			g_VR._flyAwayLawLabel = vrmod.utils.FlyAwayLaw_StatusLabel
				and vrmod.utils.FlyAwayLaw_StatusLabel(d) or nil
			g_VR._flyAwayLawHmdExpect = vrmod.utils.FlyAwayLaw_HmdExpect
				and vrmod.utils.FlyAwayLaw_HmdExpect(d) or nil
		end
		-- G34 / W12: one-shot fly-away snap if head vel insane in start window
		timer.Create("vrmod_flyaway_origin_snap", 0.5, 6, function()
			if not g_VR or not g_VR.active or g_VR._flyAwaySnapped then return end
			local FA = vrmod.utils
			if not FA or not FA.FlyAwayLaw_ShouldSnapOrigin then return end
			local ply2 = LocalPlayer()
			local hasPos = IsValid(ply2)
			local vel = (vrmod.cachedHeadPose and vrmod.cachedHeadPose.vel) or (g_VR.tracking and g_VR.tracking.hmd and g_VR.tracking.hmd.vel)
			local vx, vy, vz = 0, 0, 0
			if vel then
				vx = vel.x or 0
				vy = vel.y or 0
				vz = vel.z or 0
			end
			local elapsed = CurTime() - (g_VR._flyAwayStartTime or CurTime())
			if FA.FlyAwayLaw_ShouldSnapOrigin({
				elapsed_sec = elapsed,
				already_snapped = g_VR._flyAwaySnapped,
				vel_z = vz,
				vel_x = vx,
				vel_y = vy,
				has_player_pos = hasPos,
			}) then
				g_VR.origin = ply2:GetPos()
				g_VR._flyAwaySnapped = true
				if vrmod.logger then
					vrmod.logger.Warn("G34 fly-away snap: insane head vel → origin to feet (velz=%.0f)", vz)
				end
				if FA.FlyAwayLaw_Decide then
					local d = FA.FlyAwayLaw_Decide({
						in_vehicle = ply2.InVehicle and ply2:InVehicle(),
						origin_set_to_feet = true,
						already_snapped = true,
						vel_z = vz,
						has_player_pos = true,
						expect_action_set = true,
						action_set = FA.FlyAwayLaw_ResolveActionSet
							and FA.FlyAwayLaw_ResolveActionSet(ply2.InVehicle and ply2:InVehicle()),
					})
					-- after snap path is recovered
					d.path_ok = true
					d.risk = "none"
					d.reason = "snapped_to_feet"
					d.should_snap = false
					g_VR._flyAwayLaw = d
					g_VR._flyAwayLawLabel = "FLY · SNAPPED"
					g_VR._flyAwayLawHmdExpect = FA.FlyAwayLaw_HmdExpect and FA.FlyAwayLaw_HmdExpect(d) or nil
				end
				timer.Remove("vrmod_flyaway_origin_snap")
			end
		end)
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
		-- Menu-first / pre-map: no LocalPlayer — seed at origin so XR session still boots
		local ply = LocalPlayer()
		local origin = (IsValid(ply) and ply.GetPos and ply:GetPos()) or Vector(0, 0, 0)
		local eyeZ = 66.8
		local cvEye = GetConVar("vrmod_charactereyeheight")
		if cvEye then eyeZ = cvEye:GetFloat() end
		g_VR.tracking = {
			hmd = EmptyPose(origin + Vector(0, 0, eyeZ)),
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
		-- Frame energy (stable order — reverse collect/submit raced MatQueue → ~CThread):
		--   UpdatePoses (WaitFrame+Begin) → dual RenderView → optional Collect → Submit EndFrame
		-- Backend still owns XR timing; collect is best-effort isolate, not submit-before-render.
		hook.Add("RenderScene", "vrutil_hook_renderscene", function()
			if DrawErrorOverlay() then return true end

			-- Soft session pins only (never mat_queue_mode — workers are process-global).
			EnsurePinnedConvars()

			-- Keep World Portals suppressed for the entire VR frame (do not restore mid-frame)
			local wp = rawget(_G, "wp")
			if istable(wp) then
				wp.drawing = true
			end

			UpdateTracking()
			ApplyPoseModifiers()
			-- G25: one pose energy path snapshot (pain #4 — no dual-truth forks).
			if vrmod.utils and vrmod.utils.PoseSoT_Decide then
				local tr = g_VR.tracking
				local raw = g_VR.rawTracking
				local pdec = vrmod.utils.PoseSoT_Decide({
					vr_active = true,
					has_raw = istable(raw) and raw.hmd ~= nil,
					has_tracking = istable(tr) and tr.hmd ~= nil,
					gun_reads = "tracking",
					head_vel_from = "raw",
					second_angvel_sot = false,
					dual_public = false,
					modifiers_in_place = true,
				})
				g_VR._poseSoTDecision = pdec
				g_VR._poseSoTLabel = vrmod.utils.PoseSoT_StatusLabel
					and vrmod.utils.PoseSoT_StatusLabel(pdec) or nil
				g_VR._poseSoTHmdExpect = vrmod.utils.PoseSoT_HmdExpect
					and vrmod.utils.PoseSoT_HmdExpect(pdec) or nil
			end
			HandleInput()
			VRUtilNetUpdateLocalPly()
			UpdateViewFromEntity()

			local openxrShouldRender = true
			if isfunction(VRMOD_ShouldRender) then
				local okSR, sr = pcall(VRMOD_ShouldRender)
				if okSR then openxrShouldRender = sr and true or false end
			end

			-- G05: stereo policy during load / early handoff (pure SoT — no dual under mq≥2)
			local mq = g_VR._matQueueMode or WantedMatQueueMode()
			local inGame = true
			if isfunction(IsInGame) then inGame = IsInGame() and true or false end
			local ply = LocalPlayer and LocalPlayer() or nil
			local plyOk = IsValid(ply)
			local mapName = ""
			pcall(function()
				if game and game.GetMap then mapName = tostring(game.GetMap() or "") end
			end)
			local loading = true
			if vrmod.utils and vrmod.utils.StereoLoad_IsLoading then
				loading = vrmod.utils.StereoLoad_IsLoading({
					is_in_game = inGame,
					local_player_valid = plyOk,
					map_name = mapName,
					map_changing = g_VR._mapChanging and true or false,
				})
			else
				loading = (not inGame) or (not plyOk)
			end
			local policy = (vrmod.utils and vrmod.utils.StereoLoadPolicy)
					and vrmod.utils.StereoLoadPolicy({
						mat_queue_mode = mq,
						vr_active = true,
						loading = loading,
						openxr_should_render = openxrShouldRender,
					})
				or { dual_eye = (mq or 1) < 2, keep_submit = true, prefer_paint_while_load = false }
			g_VR._stereoLoadPolicy = policy
			g_VR._stereoLoadLabel = (vrmod.utils and vrmod.utils.StereoLoad_StatusLabel
				and vrmod.utils.StereoLoad_StatusLabel(policy)) or nil
			-- One-shot toast when dual-hold engages (not every load frame)
			if vrmod.utils and vrmod.utils.StereoLoad_ShouldToast
				and vrmod.utils.StereoLoad_ShouldToast(policy, g_VR._stereoLoadToasted) then
				g_VR._stereoLoadToasted = true
				local hint = vrmod.utils.StereoLoadToastHint and vrmod.utils.StereoLoadToastHint(policy)
				local expect = vrmod.utils.StereoLoad_HmdExpect and vrmod.utils.StereoLoad_HmdExpect(policy)
				g_VR._stereoLoadHmdExpect = expect
				if hint then
					if vrmod.logger then
						vrmod.logger.Info("G05 %s", hint)
						if expect and expect.checklist then
							vrmod.logger.Info("G05 HMD %s", tostring(expect.checklist))
						end
					end
					if vrmod.Toast then vrmod.Toast(hint, 3, "hint") end
				end
			end
			local paint = openxrShouldRender
			if vrmod.utils and vrmod.utils.ShouldPaintStereoThisFrame then
				paint = vrmod.utils.ShouldPaintStereoThisFrame(policy, openxrShouldRender)
			end

			local collected = false
			if paint then
				PerformRenderViews()
				-- b1a5e9e-era: optional Collect into staging (mq < 2 only)
				local collectOk = (mq or 1) < 2
				if vrmod.utils and vrmod.utils.SubmitLaw_AllowCollect then
					collectOk = vrmod.utils.SubmitLaw_AllowCollect({ mat_queue_mode = mq })
				end
				if collectOk and isfunction(VRMOD_CollectEyes) then
					PushKnownSubmitSize()
					local okC = pcall(VRMOD_CollectEyes)
					collected = okC and true or false
				end
			end

			-- G19: pure submit decision snapshot (dual OUT only; never eng IN / virgin).
			if vrmod.utils and vrmod.utils.SubmitLaw_Decide then
				local sdec = vrmod.utils.SubmitLaw_Decide({
					mat_queue_mode = mq,
					vr_active = true,
					painted = paint and true or false,
					collected = collected,
					keep_submit = policy.keep_submit ~= false,
					submit_texture = "dual_out_rgba8",
				})
				g_VR._submitLawDecision = sdec
				g_VR._submitLawLabel = vrmod.utils.SubmitLaw_StatusLabel
					and vrmod.utils.SubmitLaw_StatusLabel(sdec) or nil
				g_VR._submitLawHmdExpect = vrmod.utils.SubmitLaw_HmdExpect
					and vrmod.utils.SubmitLaw_HmdExpect(sdec) or nil
			end

			-- G05: keep Submit while active (policy.keep_submit) — avoids HMD void on load frames
			if policy.keep_submit ~= false and isfunction(VRMOD_SubmitSharedTexture) then
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
		-- G38 / W10: single presentation path (floating hands OR worldmodel, not dual ghost)
		local floating = convars.vrmod_floatinghands:GetBool()
		local useWmGlobal = convars.vrmod_useworldmodels and convars.vrmod_useworldmodels:GetBool()
		local classWm = g_VR.currentvmi and g_VR.currentvmi.useWorldModel
		local useWm = useWmGlobal or classWm
		local hideplayer = floating
		if vrmod.utils and vrmod.utils.WorldModelLaw_Decide then
			local d = vrmod.utils.WorldModelLaw_Decide({
				floating_hands = floating,
				use_worldmodels = useWm,
				draw_viewmodel = not useWm,
				draw_worldmodel_vm = useWm and true or false,
				draw_player_body = not floating,
			})
			g_VR._worldModelLaw = d
			g_VR._worldModelLawLabel = vrmod.utils.WorldModelLaw_StatusLabel
				and vrmod.utils.WorldModelLaw_StatusLabel(d) or nil
			g_VR._worldModelLawHmdExpect = vrmod.utils.WorldModelLaw_HmdExpect
				and vrmod.utils.WorldModelLaw_HmdExpect(d) or nil
			-- Enforce single body path: floating hands always hides local player body
			if d.floating_hands then hideplayer = true end
			if d.draw_player_body == false then hideplayer = true end
		end
		hook.Add("PostDrawTranslucentRenderables", "vrutil_hook_drawplayerandviewmodel", function(bSky, _)
			if bSky or not LocalPlayer():Alive() then return end
			-- Pre-G38 path: always DrawModel g_VR.viewModel when valid.
			-- (G38 drawVm=false on useWorldModel skipped drawing worldModelVM too — guns vanished.)
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
			timer.Remove("vrmod_async_shutdown")
			timer.Remove("vrmod_mat_queue_apply")
			timer.Remove("vrmod_display_params_catchup")
			displayParamsLive = false
			g_VR._stereoSelfTestDone = true
			g_VR._stereoLoadToasted = nil
			g_VR._stereoLoadPolicy = nil
			g_VR._stereoLoadLabel = nil
			matQueueAppliedForSession = false

			-- G13: return-to-Cube marker + bridge will relaunch CubeUI after XR free
			pcall(function()
				local isCube = (vrmod.IsOpenXRLaunchSession and vrmod.IsOpenXRLaunchSession())
					or (g_VR._openxrLaunch and g_VR._openxrLaunch.native_wrapper)
				if vrmod.utils and vrmod.utils.CubeReturn_ShouldNotifyCube
					and vrmod.utils.CubeReturn_ShouldNotifyCube(isCube, true) then
					local map = tostring(game.GetMap and game.GetMap() or "")
					local intent = g_VR._cubeReturnIntent or "vr_exit"
					local body = vrmod.utils.CubeReturn_Format("vr_exit", {
						map = map,
						source = "vrmod_exit",
						intent = intent,
						ts = os.time and os.time() or 0,
					})
					file.CreateDir("vrmod")
					file.Write("vrmod/cube_return.txt", body)
					g_VR._cubeReturnPendingRelease = true
					g_VR._cubeReturnRelaunch = true
					if vrmod.logger then
						vrmod.logger.Info("G13 cube_return phase=vr_exit intent=%s map=%s", intent, map)
					end
				end
			end)

			-- === Exit order (mat_queue 2 safe) ===
			-- 1) Stop owning the frame: no more RenderScene / stereo / WaitFrame / Submit.
			g_VR.active = false
			hook.Remove("RenderScene", "vrutil_hook_renderscene")
			hook.Remove("CalcViewModelView", "vrutil_hook_calcviewmodelview")
			hook.Remove("PostDrawTranslucentRenderables", "vrutil_hook_drawplayerandviewmodel")
			hook.Remove("PreDrawPlayerHands", "vrutil_hook_predrawplayerhands")
			hook.Remove("PreDrawViewModel", "vrutil_hook_predrawviewmodel")
			hook.Remove("ShouldDrawLocalPlayer", "vrutil_hook_shoulddrawlocalplayer")
			hook.Remove("CalcView", "vrutil_hook_calcview")

			-- 2) Gate module immediately (UpdatePoses/Submit become no-ops).
			pcall(function()
				if isfunction(VRMOD_SetSubmitEnabled) then
					VRMOD_SetSubmitEnabled(false)
				end
			end)

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
			g_VR.tracking = {}
			g_VR.rawTracking = {}
			g_VR.threePoints = false
			g_VR.sixPoints = false
			g_VR.rt = nil
			g_VR.rtWidth, g_VR.rtHeight = nil, nil
			g_VR.stereoEye = nil
			EndVRNestedRenderLock()

			-- 3) Full OpenXR teardown NOW (hooks already off). Next vrmod_start = cold Init.
			--    Async defer raced Init "already running" with submit still disabled.
			pcall(function()
				if isfunction(VRMOD_Shutdown) then VRMOD_Shutdown() end
			end)

			-- G13: mark XR released; cl_cube_bridge spawns CubeUI after short delay
			pcall(function()
				if g_VR._cubeReturnPendingRelease and vrmod.utils and vrmod.utils.CubeReturn_Format then
					g_VR._cubeReturnPendingRelease = false
					local map = tostring(game.GetMap and game.GetMap() or "")
					local intent = g_VR._cubeReturnIntent or "vr_exit"
					file.Write("vrmod/cube_return.txt", vrmod.utils.CubeReturn_Format("xr_released", {
						map = map,
						source = "vrmod_exit",
						intent = intent,
						ts = os.time and os.time() or 0,
					}))
					if vrmod.Toast then
						vrmod.Toast(
							intent == "temp_return"
								and "OpenXR free · opening Cube launcher (GMod kept)"
								or "OpenXR free · opening Cube launcher…",
							4,
							"hint"
						)
					end
				end
			end)

			-- 4) Restore soft pins only — never thrash mat_queue under OpenXR.
			ScheduleConvarRestore(0.2)

			-- 5) G13: only when ReturnToCubeLauncher set relaunch (not every Cube-session exit)
			if g_VR._cubeReturnRelaunch then
				local intent = g_VR._cubeReturnIntent or "temp_return"
				-- Leave flags for VRMod_Exit hook / schedule once
				if not g_VR._cubeBridgeSpawned and not timer.Exists("vrmod_cube_bridge_spawn") then
					g_VR._cubeBridgeSpawned = true
					timer.Create("vrmod_cube_bridge_spawn", 2.5, 1, function()
						g_VR._cubeBridgeSpawned = false
						g_VR._cubeReturnRelaunch = nil
						g_VR._cubeReturnIntent = nil
						if g_VR and g_VR.active then return end
						if vrmod.CubeBridge_SpawnLauncher then
							vrmod.CubeBridge_SpawnLauncher(intent)
						end
					end)
				end
			end

			vrmod.logger.Info("Ended VR session (full teardown; cold restart OK)")
		end

		hook.Add("ShutDown", "vrutil_hook_shutdown", function()
			if IsValid(LocalPlayer()) and g_VR.net and g_VR.net[LocalPlayer():SteamID()] then
				if g_VR.active then
					g_VR.active = false
					hook.Remove("RenderScene", "vrutil_hook_renderscene")
					pcall(function()
						if isfunction(VRMOD_SetSubmitEnabled) then VRMOD_SetSubmitEnabled(false) end
						if isfunction(VRMOD_Shutdown) then VRMOD_Shutdown() end
					end)
					restoreConvarOverrides()
				end
			end
		end)
	end

	-- Main ----------------------------------------------------------------------
	function VRUtilClientStart()
		if g_VR.active then
			if vrmod.logger then vrmod.logger.Warn("VR already active — stop first") end
			return
		end
		if not PerformStartup() then return end
		-- Soft performance pins only (never mat_queue / mcore).
		OverridePerformanceConvars()
		local okRT, errRT = pcall(SetupRenderTargets)
		if not okRT or not g_VR.rt or not g_VR.rtWidth then
			if vrmod.logger then
				vrmod.logger.Err("SetupRenderTargets failed: %s", errRT)
			end
			if vrmod.Toast then
				vrmod.Toast("Render targets failed — cannot start VR eyes. Check console / module.", 8, "error")
			end
			pcall(function() if isfunction(VRMOD_Shutdown) then VRMOD_Shutdown() end end)
			return
		end
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
		-- Re-apply all convars now that active + RT exist (cold restart path).
		ApplySessionSettingsFromConvars()
		ScheduleDisplayParamsCatchup()
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
		-- Cube W7 / G32: early stereo / tracking self-check (toast once if HMD silent)
		g_VR._stereoSelfTestDone = false
		local delay = (vrmod.utils and vrmod.utils.StereoSelfTest_DelaySeconds
			and vrmod.utils.StereoSelfTest_DelaySeconds()) or 2.5
		timer.Create("vrmod_stereo_selftest", delay, 1, function()
			if not g_VR or not g_VR.active or g_VR._stereoSelfTestDone then return end
			g_VR._stereoSelfTestDone = true
			local hmd = g_VR.tracking and g_VR.tracking.hmd
			local hasHmd = hmd and hmd.pos and true or false
			local ST = vrmod.utils
			local toastNo = false
			local toastUn = false
			if ST and ST.StereoSelfTest_ShouldToastNoHmd and ST.StereoSelfTest_ShouldToastNoHmd(hasHmd, false) then
				if vrmod.Toast then
					local msg = (ST.StereoSelfTest_NoHmdToast and ST.StereoSelfTest_NoHmdToast())
						or "No HMD pose after start — PC may show game while headset stays black/loading. Restart SteamVR; check cable/HMD."
					local sec = (ST.StereoSelfTest_ToastSeconds and ST.StereoSelfTest_ToastSeconds()) or 8
					vrmod.Toast(msg, sec, "error")
					toastNo = true
				end
				if vrmod.logger then
					vrmod.logger.Err("Stereo self-test: no HMD tracking rt=%sx%s shareOk=%s",
						tostring(g_VR.rtWidth), tostring(g_VR.rtHeight), tostring(g_VR._shareTextureOk))
				end
			elseif ST and ST.StereoSelfTest_ShouldToastUnhealthyShare
				and ST.StereoSelfTest_ShouldToastUnhealthyShare(hasHmd, g_VR._shareTextureOk, false) then
				if vrmod.Toast then
					local msg = (ST.StereoSelfTest_UnhealthyShareToast and ST.StereoSelfTest_UnhealthyShareToast())
						or "Stereo share was unhealthy at start — if HMD is black, restart SteamVR + lower supersample."
					local sec = (ST.StereoSelfTest_ShareHintSeconds and ST.StereoSelfTest_ShareHintSeconds()) or 6
					vrmod.Toast(msg, sec, "hint")
					toastUn = true
				end
			elseif not hasHmd then
				-- Fallback if pure helpers missing
				if vrmod.Toast then
					vrmod.Toast(
						"No HMD pose after start — PC may show game while headset stays black/loading. Restart SteamVR; check cable/HMD.",
						8,
						"error"
					)
					toastNo = true
				end
			end
			if ST and ST.StereoSelfTest_Decide then
				local d = ST.StereoSelfTest_Decide({
					ok_begin = g_VR._shareTextureOk ~= false,
					ok_finish = g_VR._shareTextureOk ~= false,
					share_ok = g_VR._shareTextureOk,
					has_hmd = hasHmd,
					selftest_done = false, -- evaluate as if just-before done so should_* fire
					toast_no_hmd = toastNo or nil,
					toast_unhealthy = toastUn or nil,
				})
				-- mark done for status after snapshot
				d.selftest_done = true
				g_VR._stereoSelfTestLaw = d
				g_VR._stereoSelfTestLabel = ST.StereoSelfTest_StatusLabel and ST.StereoSelfTest_StatusLabel(d) or nil
				g_VR._stereoSelfTestHmdExpect = ST.StereoSelfTest_HmdExpect and ST.StereoSelfTest_HmdExpect(d) or nil
			end
		end)
		vrmod.logger.Info("Started VR session (nested RenderView lock active) rt=%sx%s", g_VR.rtWidth, g_VR.rtHeight)
	end
end