-- Head latch law (pure, offline-tested). G53.
-- Cameras sample the head immediately before the stereo paints (late latch).
-- The OpenXR layer locates again at submit. WiVRn reprojects that layer pose
-- to the display pose. A pose taken before both RenderViews is a large
-- correction, and Source submits no depth layer, so the turn flashes.
-- HMD orientation is never smoothed. Smoothing is another frame of lag.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

function vrmod.utils.HeadLatch_AllowHmdSmoothing()
	return false
end

-- The layer pose is a locate after the paint. The camera latch is not the layer.
function vrmod.utils.HeadLatch_AllowSubmitRelocate()
	return true
end

function vrmod.utils.HeadLatch_PipelineSteps()
	return {
		"wait_begin",
		"early_latch",
		"gameplay",
		"late_latch",
		"paint_eyes",
		"submit_fresh_pose",
	}
end

--- "submit" = layer pose located after the eyes. "paint" = pre-render latch on the layer.
function vrmod.utils.HeadLatch_PoseSource(usePaintPose)
	if usePaintPose then
		return "paint"
	end
	return "submit"
end

--- opts: vr_active, late_latch, hmd_smoothed, use_paint_pose
function vrmod.utils.HeadLatch_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local active = opts.vr_active
	if active == nil then active = true end
	active = active and true or false
	local late = opts.late_latch and true or false
	local smoothed = opts.hmd_smoothed and true or false
	local usePaint = opts.use_paint_pose and true or false
	local source = vrmod.utils.HeadLatch_PoseSource(usePaint)
	local d = {
		valid = true,
		vr_active = active,
		late_latch = late,
		hmd_smoothed = smoothed,
		use_paint_pose = usePaint,
		pose_source = source,
		allow_hmd_smoothing = false,
		allow_submit_relocate = true,
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
	if source == "paint" then
		d.path_ok = false
		d.risk = "reproject"
		d.reason = "paint_pose_on_layer"
		return d
	end
	d.path_ok = true
	d.risk = "none"
	d.reason = late and "late_paint_submit_locate" or "early_paint_submit_locate"
	return d
end

function vrmod.utils.HeadLatch_IsLagRisk(decision)
	if type(decision) ~= "table" then return false end
	return decision.risk == "reproject" or decision.risk == "hmd_smooth"
end

function vrmod.utils.HeadLatch_StatusLabel(decision)
	if type(decision) ~= "table" then return "HEAD · IDLE" end
	if not decision.vr_active then return "HEAD · IDLE" end
	if decision.risk == "hmd_smooth" then return "HEAD · SMOOTHED" end
	if decision.risk == "reproject" then return "HEAD · REPROJECT" end
	if decision.late_latch then return "HEAD · LATE LATCH" end
	if decision.path_ok then return "HEAD · SUBMIT" end
	return "HEAD · HOLD"
end

function vrmod.utils.HeadLatch_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_latched_pose = false,
		checklist = "G53 · IDLE · no head latch",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if not decision.vr_active then return e end
	if not decision.path_ok then
		if decision.risk == "reproject" then
			e.verdict = "expect_flicker"
			e.checklist = "G53 · FLICKER · paint pose on the layer"
			e.pass_line = "Layer pose is located after the eyes"
			e.fail_line = "Pre-render pose on the layer — the turn flashes"
			return e
		end
		e.verdict = "expect_lag"
		e.checklist = "G53 · LAG · " .. tostring(decision.reason or decision.risk)
		e.pass_line = "HMD is unsmoothed and the layer locates at submit"
		e.fail_line = "Smoothing on the HMD adds a frame of lag"
		return e
	end
	e.verdict = decision.late_latch and "expect_late_latch" or "expect_submit"
	e.expect_latched_pose = decision.late_latch and true or false
	e.checklist = decision.late_latch
		and "G53 · LATE PAINT · layer pose is the submit locate"
		or "G53 · SUBMIT · layer pose is the submit locate"
	e.pass_line = "Cameras use the late head sample. The layer locates after the paint."
	e.fail_line = "Paint pose submitted on the layer, or smoothing on the HMD"
	return e
end
