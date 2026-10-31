-- Head latch law (pure, offline-tested).
-- The stereo cameras and the OpenXR projection layer share one XrView.
-- Relocating at xrEndFrame attaches a newer pose to older pixels. Runtime
-- timewarp then under-corrects, and turning the head feels late.
-- HMD orientation is never smoothed. Smoothing is another frame of lag.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

function vrmod.utils.HeadLatch_AllowHmdSmoothing()
	return false
end

-- Same-frame paint pose wins. Relocate is only the missing-latch fallback.
function vrmod.utils.HeadLatch_AllowSubmitRelocate()
	return false
end

function vrmod.utils.HeadLatch_PipelineSteps()
	return {
		"wait_begin",
		"early_latch",
		"gameplay",
		"late_latch",
		"paint_eyes",
		"submit_latched_pose",
	}
end

--- "latch" when the layer pose is the one the eyes were painted for.
function vrmod.utils.HeadLatch_PoseSource(latched, timeMatch)
	if latched and timeMatch ~= false then
		return "latch"
	end
	return "relocate"
end

--- opts: vr_active, latched, time_match, late_latch, hmd_smoothed
function vrmod.utils.HeadLatch_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local active = opts.vr_active
	if active == nil then active = true end
	active = active and true or false
	local latched = opts.latched and true or false
	local timeMatch = opts.time_match
	if timeMatch == nil then timeMatch = latched end
	timeMatch = timeMatch and true or false
	local late = opts.late_latch and true or false
	local smoothed = opts.hmd_smoothed and true or false
	local source = vrmod.utils.HeadLatch_PoseSource(latched, timeMatch)
	local d = {
		valid = true,
		vr_active = active,
		latched = latched,
		time_match = timeMatch,
		late_latch = late,
		hmd_smoothed = smoothed,
		pose_source = source,
		allow_hmd_smoothing = false,
		allow_submit_relocate = false,
		path_ok = true,
		risk = "none",
		reason = "ok",
	}
	if not active then
		d.reason = "inactive"
		return d
	end
	if smoothed then
		d.path_ok = false
		d.risk = "hmd_smooth"
		d.reason = "hmd_smoothing_adds_lag"
		return d
	end
	if source ~= "latch" then
		d.path_ok = false
		d.risk = "relocate"
		d.reason = "submit_pose_newer_than_paint"
		return d
	end
	d.path_ok = true
	d.risk = "none"
	d.reason = late and "late_latch_matches_submit" or "early_latch_matches_submit"
	return d
end

function vrmod.utils.HeadLatch_IsLagRisk(decision)
	if type(decision) ~= "table" then return false end
	return decision.risk == "relocate" or decision.risk == "hmd_smooth"
end

function vrmod.utils.HeadLatch_StatusLabel(decision)
	if type(decision) ~= "table" then return "HEAD · IDLE" end
	if not decision.vr_active then return "HEAD · IDLE" end
	if decision.risk == "hmd_smooth" then return "HEAD · SMOOTHED" end
	if decision.risk == "relocate" then return "HEAD · RELOCATE LAG" end
	if decision.late_latch then return "HEAD · LATE LATCH" end
	if decision.path_ok then return "HEAD · LATCHED" end
	return "HEAD · HOLD"
end

function vrmod.utils.HeadLatch_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_latched_pose = true,
		checklist = "G53 · IDLE · no head latch",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if not decision.vr_active then return e end
	if not decision.path_ok then
		e.verdict = "expect_lag"
		e.expect_latched_pose = false
		e.checklist = "G53 · LAG · " .. tostring(decision.reason or decision.risk)
		e.pass_line = "Layer pose equals the painted view"
		e.fail_line = "Head turns feel late — timewarp under-corrects"
		return e
	end
	e.verdict = decision.late_latch and "expect_late_latch" or "expect_latched"
	e.expect_latched_pose = true
	e.checklist = decision.late_latch
		and "G53 · LATE LATCH · submit uses paint pose"
		or "G53 · LATCH · submit uses paint pose"
	e.pass_line = "Turning the head stays on the painted pose; runtime timewarp covers the render"
	e.fail_line = "Second locate at EndFrame, or smoothing on the HMD"
	return e
end
