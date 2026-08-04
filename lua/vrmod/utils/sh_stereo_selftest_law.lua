-- G32: stereo ShareTexture / HMD self-test toast law (pure, offline-tested).
-- Watchlist W7: PC shows game, HMD black/loading — honest toast, never silent death.
-- Product: ShareTexture begin/finish fail toast; delayed HMD pose self-check (toast once).
-- Law: require toast on share fail; toast on missing HMD pose after start; VR continues.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

function vrmod.utils.StereoSelfTest_DelaySeconds()
	return 2.5
end

function vrmod.utils.StereoSelfTest_ToastSeconds()
	return 8
end

function vrmod.utils.StereoSelfTest_ShareHintSeconds()
	return 6
end

--- Fail path must toast (no silent black HMD).
function vrmod.utils.StereoSelfTest_RequireToastOnShareFail()
	return true
end

function vrmod.utils.StereoSelfTest_RequireToastOnNoHmd()
	return true
end

--- Never abort VR start solely because share/pose self-test failed.
function vrmod.utils.StereoSelfTest_AbortVrOnFail()
	return false
end

function vrmod.utils.StereoSelfTest_ShareBeginToast(rtW, rtH)
	return string.format(
		"ShareTexture begin failed (%sx%s) — HMD may stay black. Lower supersample / check module.",
		tostring(rtW or "?"),
		tostring(rtH or "?")
	)
end

function vrmod.utils.StereoSelfTest_ShareFinishToast(rtW, rtH)
	return string.format(
		"ShareTexture finish failed (rt %sx%s) — desktop OK / HMD black often means this. Restart SteamVR + GMod.",
		tostring(rtW or "?"),
		tostring(rtH or "?")
	)
end

function vrmod.utils.StereoSelfTest_NoHmdToast()
	return "No HMD pose after start — PC may show game while headset stays black/loading. Restart SteamVR; check cable/HMD."
end

function vrmod.utils.StereoSelfTest_UnhealthyShareToast()
	return "Stereo share was unhealthy at start — if HMD is black, restart SteamVR + lower supersample."
end

--- Pure: should toast ShareTexture begin fail?
function vrmod.utils.StereoSelfTest_ShouldToastShareBegin(okBegin)
	return not (okBegin and true or false)
end

function vrmod.utils.StereoSelfTest_ShouldToastShareFinish(okFinish)
	return not (okFinish and true or false)
end

--- Combined share health after begin+finish.
function vrmod.utils.StereoSelfTest_ShareOk(okBegin, okFinish)
	return (okBegin and true or false) and (okFinish and true or false)
end

--- After delay: toast if no HMD pose (once).
function vrmod.utils.StereoSelfTest_ShouldToastNoHmd(hasHmdPose, alreadyDone)
	if alreadyDone then return false end
	return not (hasHmdPose and true or false)
end

--- After delay: soft hint if share was unhealthy but pose present.
function vrmod.utils.StereoSelfTest_ShouldToastUnhealthyShare(hasHmdPose, shareOk, alreadyDone)
	if alreadyDone then return false end
	if not hasHmdPose then return false end -- no-HMD path wins
	return shareOk == false
end

--- Pure decision snapshot.
--- opts:
---   ok_begin, ok_finish bool
---   has_hmd bool|nil
---   share_ok bool|nil          if nil, derived from begin/finish
---   selftest_done bool|nil
---   toast_share_begin bool|nil
---   toast_share_finish bool|nil
---   toast_no_hmd bool|nil
---   toast_unhealthy bool|nil
function vrmod.utils.StereoSelfTest_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local okB = opts.ok_begin and true or false
	local okF = opts.ok_finish and true or false
	local shareOk = opts.share_ok
	if shareOk == nil then
		shareOk = vrmod.utils.StereoSelfTest_ShareOk(okB, okF)
	else
		shareOk = shareOk and true or false
	end
	-- has_hmd nil = pose not evaluated yet (share-only snapshot at RT setup)
	local hmdKnown = opts.has_hmd ~= nil
	local hasHmd = opts.has_hmd and true or false
	local done = opts.selftest_done and true or false
	local d = {
		valid = true,
		ok_begin = okB,
		ok_finish = okF,
		share_ok = shareOk,
		has_hmd = hasHmd,
		hmd_known = hmdKnown,
		selftest_done = done,
		should_toast_begin = vrmod.utils.StereoSelfTest_ShouldToastShareBegin(okB),
		should_toast_finish = vrmod.utils.StereoSelfTest_ShouldToastShareFinish(okF),
		should_toast_no_hmd = hmdKnown and vrmod.utils.StereoSelfTest_ShouldToastNoHmd(hasHmd, done) or false,
		should_toast_unhealthy = hmdKnown and vrmod.utils.StereoSelfTest_ShouldToastUnhealthyShare(hasHmd, shareOk, done) or false,
		abort_vr = vrmod.utils.StereoSelfTest_AbortVrOnFail(),
		risk = "none", -- none | share_begin | share_finish | no_hmd | unhealthy_share | silent_fail
		reason = "ok",
		path_ok = true,
	}
	-- Silent fail if share failed but toast not shown when required
	local silent = false
	if d.should_toast_begin and opts.toast_share_begin == false then silent = true end
	if d.should_toast_finish and opts.toast_share_finish == false then silent = true end
	if d.should_toast_no_hmd and opts.toast_no_hmd == false then silent = true end

	if silent then
		d.risk = "silent_fail"
		d.reason = "fail_without_toast"
		d.path_ok = false
	elseif not okB then
		d.risk = "share_begin"
		d.reason = "share_texture_begin_failed"
		d.path_ok = false
	elseif not okF then
		d.risk = "share_finish"
		d.reason = "share_texture_finish_failed"
		d.path_ok = false
	elseif d.should_toast_no_hmd then
		d.risk = "no_hmd"
		d.reason = "no_hmd_pose_after_start"
		d.path_ok = false
	elseif d.should_toast_unhealthy or (hmdKnown and hasHmd and shareOk == false) then
		d.risk = "unhealthy_share"
		d.reason = "share_unhealthy_with_pose"
		d.path_ok = false
	else
		d.reason = hmdKnown and "share_ok_hmd_ok" or "share_ok_pending_hmd"
		d.path_ok = true
	end
	return d
end

function vrmod.utils.StereoSelfTest_StatusLabel(decision)
	if type(decision) ~= "table" then return "STEREO · IDLE" end
	if decision.risk == "silent_fail" then return "STEREO · SILENT FAIL" end
	if decision.risk == "share_begin" then return "STEREO · SHARE BEGIN FAIL" end
	if decision.risk == "share_finish" then return "STEREO · SHARE FINISH FAIL" end
	if decision.risk == "no_hmd" then return "STEREO · NO HMD" end
	if decision.risk == "unhealthy_share" then return "STEREO · SHARE UNHEALTHY" end
	if decision.path_ok then return "STEREO · OK" end
	return "STEREO · HOLD"
end

function vrmod.utils.StereoSelfTest_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_toast_on_fail = true,
		expect_vr_continues = true,
		checklist = "G32 · IDLE · no stereo self-test decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if decision.risk == "silent_fail" then
		e.verdict = "expect_silent_fail"
		e.expect_toast_on_fail = false
		e.checklist = "G32 · SILENT · black HMD without toast (forbidden)"
		e.pass_line = "Toast on ShareTexture/HMD fail"
		e.fail_line = "Desktop OK / HMD black with no toast"
		return e
	end
	if decision.path_ok then
		e.verdict = "expect_ok"
		e.checklist = "G32 · OK · share + HMD pose"
		e.pass_line = "Both eyes live; no share/HMD toast"
		e.fail_line = "Black HMD despite share_ok"
		return e
	end
	e.verdict = "expect_fail_honest"
	e.checklist = "G32 · FAIL HONEST · " .. tostring(decision.reason)
	e.pass_line = "Toast + log sizes; VR continues; user can restart runtime"
	e.fail_line = "Silent black or abort VR start"
	return e
end

function vrmod.utils.StereoSelfTest_IsSilentFailRisk(decision)
	if type(decision) ~= "table" then return true end
	return decision.risk == "silent_fail"
end
