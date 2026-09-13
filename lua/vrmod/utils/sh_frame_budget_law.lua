-- Frame budget after xrWaitFrame: Submit first, desktop/collect/input later.
-- Late frames (shutter) come from extra RenderView / live-RT blit / collect
-- still sitting on the WaitFrame → EndFrame path.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

function vrmod.utils.FrameBudget_DesktopSkipMs()
	return 14
end

function vrmod.utils.FrameBudget_InputAfterSubmit()
	return false
end

function vrmod.utils.FrameBudget_FollowCamAfterSubmit()
	return false
end

function vrmod.utils.FrameBudget_AllowNestedMonitorsInFollowCam()
	return false
end

--- Pure: what to drop this frame so Submit still hits the compositor.
--- opts: frame_ms, desktop_view, follow, eye_crop, collect
function vrmod.utils.FrameBudget_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local ms = tonumber(opts.frame_ms) or 0
	if ms < 0 then ms = 0 end
	local lim = vrmod.utils.FrameBudget_DesktopSkipMs()
	local late = ms > lim
	local dv = tonumber(opts.desktop_view) or 1
	local follow = opts.follow == true or dv == 4
	local eyeCrop = opts.eye_crop == true or dv == 2 or dv == 3
	local d = {
		valid = true,
		path_ok = not late,
		late = late,
		frame_ms = ms,
		skip_ms = lim,
		skip_desktop = late and follow,
		skip_collect = false,
		follow_after_submit = vrmod.utils.FrameBudget_FollowCamAfterSubmit(),
		input_after_submit = vrmod.utils.FrameBudget_InputAfterSubmit(),
		drawmonitors = vrmod.utils.FrameBudget_AllowNestedMonitorsInFollowCam(),
		risk = late and "late_frame" or "none",
		reason = late and "over_budget" or "on_time",
	}
	return d
end

function vrmod.utils.FrameBudget_StatusLabel(decision)
	if type(decision) ~= "table" then return "BUDGET · IDLE" end
	if decision.late then return "BUDGET · LATE SKIP DESKTOP" end
	return "BUDGET · ON TIME"
end

function vrmod.utils.FrameBudget_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_submit_first = true,
		checklist = "G51 · IDLE · no frame budget",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if decision.late then
		e.verdict = "expect_skip_desktop"
		e.checklist = string.format("G51 · LATE %.1fms · skip desktop/collect",
			tonumber(decision.frame_ms) or 0)
		e.pass_line = "HMD Submit still hits; desktop may stall one frame"
		e.fail_line = "Shutter — desktop RenderView/collect before EndFrame"
		return e
	end
	e.verdict = "expect_on_time"
	e.checklist = "G51 · ON TIME · Submit before desktop/input"
	e.pass_line = "Stereo Submit before follow-cam / input / net"
	e.fail_line = "Third RenderView or input before Submit"
	return e
end

function vrmod.utils.FrameBudget_IsLateRisk(decision)
	return type(decision) == "table" and decision.late == true
end
