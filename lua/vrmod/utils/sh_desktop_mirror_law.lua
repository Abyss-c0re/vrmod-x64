-- G46: desktop mirror vs HMD submit isolation (pure, offline-tested).
-- History: post-submit live RT sample blacked HMD (Quest nonblack≈0.10).
-- 2026-08-05: product restored b1a5e9e mid-frame CullMode(1)+NDC eye-crop by user ask.
-- Cube way now:
--   prefer desktopview 1 or follow(4) private RT for product HMD
--   mid-frame eye-crop (2/3) allowed as legacy but flagged live_rt_risk
--   follow-cam uses private RT only
--   never thrash climbing / mat_queue 2
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

--- Post-submit second sample of live stereo RT is still forbidden (double-bind risk).
function vrmod.utils.DesktopMirror_AllowSampleStereoRtAfterSubmit()
	return false
end

--- b1a5e9e mid-frame NDC eye-crop from live RT is allowed (legacy product path).
function vrmod.utils.DesktopMirror_AllowEyeCropFromLiveRt()
	return true
end

function vrmod.utils.DesktopMirror_PreferFollowPrivateRt()
	return true
end

--- Prefer present after submit for isolation; mid-frame still used in restored path.
function vrmod.utils.DesktopMirror_PresentOnlyAfterSubmit()
	return false -- mid-frame restored (b1a5e9e)
end

function vrmod.utils.DesktopMirror_PreferDesktopViewForHmd()
	return 1 -- none: HMD product surface first
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

--- Pure: may desktop mirror draw this frame?
--- opts: desktop_view, vr_active, after_submit, mid_frame, sample_stereo_rt
function vrmod.utils.DesktopMirror_AllowPresent(opts)
	opts = type(opts) == "table" and opts or {}
	if not opts.vr_active then return false end
	if opts.after_submit == false and opts.mid_frame ~= true
		and vrmod.utils.DesktopMirror_PresentOnlyAfterSubmit() then
		return false
	end
	-- Post-submit second live RT sample still forbidden
	if opts.after_submit == true and opts.sample_stereo_rt
		and not vrmod.utils.DesktopMirror_AllowSampleStereoRtAfterSubmit() then
		return false
	end
	local dv = tonumber(opts.desktop_view) or 1
	if vrmod.utils.DesktopMirror_IsNoneMode(dv) then return false end
	if vrmod.utils.DesktopMirror_IsFollowMode(dv) then
		return vrmod.utils.DesktopMirror_PreferFollowPrivateRt()
	end
	if vrmod.utils.DesktopMirror_IsEyeCropMode(dv) then
		return vrmod.utils.DesktopMirror_AllowEyeCropFromLiveRt()
	end
	return false
end

function vrmod.utils.DesktopMirror_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local dv = tonumber(opts.desktop_view) or 1
	local mid = opts.mid_frame == true
	local after = opts.after_submit == true
	local allow = vrmod.utils.DesktopMirror_AllowPresent(opts)
	local d = {
		valid = true,
		desktop_view = dv,
		allow_present = allow,
		eye_crop = vrmod.utils.DesktopMirror_IsEyeCropMode(dv),
		follow = vrmod.utils.DesktopMirror_IsFollowMode(dv),
		mid_frame = mid,
		after_submit = after,
		sample_stereo_rt = opts.sample_stereo_rt and true or false,
		risk = "none", -- none | live_rt_post | mid_live_rt | black_hmd | ok_legacy
		reason = "ok",
		path_ok = true,
	}
	if after and opts.sample_stereo_rt
		and not vrmod.utils.DesktopMirror_AllowSampleStereoRtAfterSubmit() then
		d.risk = "live_rt_post"
		d.reason = "post_submit_live_rt_forbidden"
		d.path_ok = false
		d.allow_present = false
	elseif mid and d.eye_crop and opts.sample_stereo_rt then
		-- b1a5e9e path: allowed but HMD-risk flagged
		d.risk = "mid_live_rt"
		d.reason = "mid_frame_live_rt_legacy"
		d.path_ok = true
		d.allow_present = allow
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
	if decision.risk == "live_rt_post" then return "DESK · POST LIVE RT FORBIDDEN" end
	if decision.risk == "mid_live_rt" then return "DESK · MID LIVE RT LEGACY" end
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
	if decision.risk == "live_rt_post" then
		e.verdict = "expect_black_risk"
		e.expect_hmd_clear = false
		e.checklist = "G46 · BLACK RISK · post-submit live RT sample"
		e.pass_line = "Never bind g_VR.rt after submit; use desktopview 1 or follow"
		e.fail_line = "HMD near-black after post-submit desktop crop"
		return e
	end
	if decision.risk == "mid_live_rt" then
		e.verdict = "expect_legacy_risk"
		e.expect_hmd_clear = true -- may still be OK (b1a5e9e)
		e.checklist = "G46 · LEGACY MID · live RT eye-crop (prefer desktopview 1)"
		e.pass_line = "HMD clear with mid-frame NDC crop; else set desktopview 1"
		e.fail_line = "HMD black/strip with desktopview 2/3 mid-frame"
		return e
	end
	e.verdict = "expect_ok"
	e.checklist = "G46 · OK · desktop isolated from HMD submit"
	e.pass_line = "Both eyes clear; follow private RT if mode 4"
	e.fail_line = "HMD black / strip after present"
	return e
end

function vrmod.utils.DesktopMirror_IsBlackRisk(decision)
	if type(decision) ~= "table" then return false end
	return decision.risk == "live_rt_post"
end

