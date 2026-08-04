-- G46: desktop mirror vs HMD submit isolation (pure, offline-tested).
-- Evidence (Quest autotest): binding g_VR.rtMaterial after submit for eye-crop
-- left HMD near-black (nonblack≈0.10). Desktop is secondary; HMD is product surface.
-- Cube way:
--   never sample live stereo RT for desktop eye-crop after submit
--   follow-cam (mode 4) uses private RT only
--   present desktop only after OpenXR submit (never mid Collect/Submit)
--   submit V: ordered src Y + dest flip on Linux (one flip total)
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

function vrmod.utils.DesktopMirror_AllowSampleStereoRtAfterSubmit()
	return false -- emergency law until private copy path
end

function vrmod.utils.DesktopMirror_AllowEyeCropFromLiveRt()
	return false
end

function vrmod.utils.DesktopMirror_PreferFollowPrivateRt()
	return true
end

function vrmod.utils.DesktopMirror_PresentOnlyAfterSubmit()
	return true
end

--- desktopView: 1=none 2=left 3=right 4=follow
function vrmod.utils.DesktopMirror_IsEyeCropMode(dv)
	dv = tonumber(dv) or 1
	return dv == 2 or dv == 3
end

function vrmod.utils.DesktopMirror_IsFollowMode(dv)
	dv = tonumber(dv) or 1
	return dv == 4
end

function vrmod.utils.DesktopMirror_IsNoneMode(dv)
	dv = tonumber(dv) or 1
	return dv == 1 or dv < 1
end

--- Pure: may PresentDesktopMirror draw this frame for given mode?
--- opts: desktop_view, vr_active, after_submit, has_private_follow_rt
function vrmod.utils.DesktopMirror_AllowPresent(opts)
	opts = type(opts) == "table" and opts or {}
	if not opts.vr_active then return false end
	if opts.after_submit == false and vrmod.utils.DesktopMirror_PresentOnlyAfterSubmit() then
		return false
	end
	local dv = tonumber(opts.desktop_view) or 1
	if vrmod.utils.DesktopMirror_IsNoneMode(dv) then return false end
	if vrmod.utils.DesktopMirror_IsFollowMode(dv) then
		return vrmod.utils.DesktopMirror_PreferFollowPrivateRt()
	end
	if vrmod.utils.DesktopMirror_IsEyeCropMode(dv) then
		-- Live stereo RT sample forbidden; private copy not available yet
		return vrmod.utils.DesktopMirror_AllowEyeCropFromLiveRt()
	end
	return false
end

function vrmod.utils.DesktopMirror_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local dv = tonumber(opts.desktop_view) or 1
	local allow = vrmod.utils.DesktopMirror_AllowPresent(opts)
	local d = {
		valid = true,
		desktop_view = dv,
		allow_present = allow,
		eye_crop = vrmod.utils.DesktopMirror_IsEyeCropMode(dv),
		follow = vrmod.utils.DesktopMirror_IsFollowMode(dv),
		sample_stereo_rt = false,
		risk = "none", -- none | live_rt | mid_submit | black_hmd
		reason = "ok",
		path_ok = true,
	}
	if opts.sample_stereo_rt and not vrmod.utils.DesktopMirror_AllowSampleStereoRtAfterSubmit() then
		d.sample_stereo_rt = true
		d.risk = "live_rt"
		d.reason = "stereo_rt_sample_forbidden"
		d.path_ok = false
		d.allow_present = false
	elseif opts.after_submit == false and opts.attempt_present then
		d.risk = "mid_submit"
		d.reason = "present_before_submit_forbidden"
		d.path_ok = false
		d.allow_present = false
	elseif d.eye_crop and not allow then
		d.risk = "black_hmd"
		d.reason = "eye_crop_deferred_protect_hmd"
		d.path_ok = true -- intentional skip is OK
	elseif d.follow and allow then
		d.reason = "follow_private_rt"
		d.path_ok = true
	elseif not opts.vr_active then
		d.reason = "vr_inactive"
		d.path_ok = true
	else
		d.reason = allow and "present_ok" or "present_skip"
		d.path_ok = true
	end
	return d
end

function vrmod.utils.DesktopMirror_StatusLabel(decision)
	if type(decision) ~= "table" then return "DESK · IDLE" end
	if decision.risk == "live_rt" then return "DESK · LIVE RT FORBIDDEN" end
	if decision.risk == "mid_submit" then return "DESK · MID SUBMIT" end
	if decision.risk == "black_hmd" then return "DESK · EYE CROP HOLD" end
	if decision.follow and decision.allow_present then return "DESK · FOLLOW" end
	if decision.allow_present then return "DESK · PRESENT" end
	if decision.path_ok then return "DESK · SKIP" end
	return "DESK · HOLD"
end

function vrmod.utils.DesktopMirror_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_hmd_clear = true,
		checklist = "G46 · IDLE · no desktop decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if decision.risk == "live_rt" or decision.risk == "mid_submit" then
		e.verdict = "expect_black_risk"
		e.expect_hmd_clear = false
		e.checklist = "G46 · BLACK RISK · " .. tostring(decision.reason)
		e.pass_line = "Skip live RT desktop bind; submit HMD first"
		e.fail_line = "HMD near-black after desktopview left/right crop"
		return e
	end
	if decision.risk == "black_hmd" then
		e.verdict = "expect_crop_hold"
		e.checklist = "G46 · EYE CROP HOLD · desktop 2/3 off until private RT"
		e.pass_line = "HMD stereo clear; desktop mirror optional later"
		e.fail_line = "HMD black with desktopview 2/3"
		return e
	end
	e.verdict = "expect_ok"
	e.checklist = "G46 · OK · desktop after submit; HMD isolated"
	e.pass_line = "Both eyes clear; follow-cam private RT if mode 4"
	e.fail_line = "HMD black / strip after present"
	return e
end

function vrmod.utils.DesktopMirror_IsBlackRisk(decision)
	if type(decision) ~= "table" then return false end
	return decision.risk == "live_rt" or decision.risk == "mid_submit"
end
