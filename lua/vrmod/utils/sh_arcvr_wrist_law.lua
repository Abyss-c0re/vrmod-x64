-- ArcVR grip writes ForegripAngle (often 0,-90,-90) onto tracking.pose_lefthand.ang.
-- That is gun-space, not ValveBiped / device wrist — the hand looks twisted.
-- Cube way: keep ArcVR grip *position*; restore device wrist angle from rawTracking.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

function vrmod.utils.ArcVrWristLaw_KeepDeviceAngleOnGrip()
	return true
end

function vrmod.utils.ArcVrWristLaw_AllowForegripAngleAsWrist()
	return false
end

--- Pure: may we overwrite left-hand angle with ArcVR ForegripAngle?
--- opts: arcvr, foregrip_grabbed, vr_active
function vrmod.utils.ArcVrWristLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local d = {
		valid = true,
		path_ok = true,
		restore_device_ang = false,
		keep_grip_pos = false,
		risk = "none",
		reason = "idle",
	}
	if opts.vr_active == false then
		d.reason = "vr_inactive"
		return d
	end
	if not opts.arcvr then
		d.reason = "not_arcvr"
		return d
	end
	if not opts.foregrip_grabbed then
		d.reason = "not_gripping"
		return d
	end
	d.keep_grip_pos = true
	if vrmod.utils.ArcVrWristLaw_KeepDeviceAngleOnGrip()
		and not vrmod.utils.ArcVrWristLaw_AllowForegripAngleAsWrist() then
		d.restore_device_ang = true
		d.reason = "device_wrist"
		return d
	end
	d.path_ok = false
	d.risk = "twisted_wrist"
	d.reason = "foregrip_angle_as_wrist"
	return d
end

function vrmod.utils.ArcVrWristLaw_StatusLabel(decision)
	if type(decision) ~= "table" then return "WRIST · IDLE" end
	if decision.risk == "twisted_wrist" then return "WRIST · TWIST" end
	if decision.restore_device_ang then return "WRIST · DEVICE" end
	return "WRIST · IDLE"
end

function vrmod.utils.ArcVrWristLaw_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_untwisted = true,
		checklist = "G50 · IDLE · no ArcVR grip",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if decision.risk == "twisted_wrist" then
		e.verdict = "expect_twist"
		e.expect_untwisted = false
		e.checklist = "G50 · TWIST · ForegripAngle as ValveBiped wrist"
		e.pass_line = "Must not ship — left wrist 90° off"
		e.fail_line = "ArcVR grip twists the wrist"
		return e
	end
	if decision.restore_device_ang then
		e.verdict = "expect_device_wrist"
		e.expect_untwisted = true
		e.checklist = "G50 · DEVICE WRIST · grip pos kept"
		e.pass_line = "Hand on gun; wrist matches controller"
		e.fail_line = "Twisted wrist on ArcVR grip"
		return e
	end
	e.verdict = "expect_idle"
	return e
end

function vrmod.utils.ArcVrWristLaw_IsTwistRisk(decision)
	return type(decision) == "table" and decision.risk == "twisted_wrist"
end
