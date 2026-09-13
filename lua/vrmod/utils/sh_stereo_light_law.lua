-- Dual RenderView consumes ProjectedTexture / DynamicLight once.
-- Cube way: refresh lights on each stereo eye, never left-only or PreStereo-only.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

function vrmod.utils.StereoLightLaw_UpdateProjectedPerEye()
	return true
end

function vrmod.utils.StereoLightLaw_AllowSingleEyeUpdate()
	return false
end

function vrmod.utils.StereoLightLaw_SkipWhenNoStereoEye()
	return true
end

function vrmod.utils.StereoLightLaw_RefreshDynamicPerEye()
	return true
end

--- Pure: may we refresh world lights for this eye?
--- opts:
---   eye                    "left"|"right"|nil
---   vr_active              bool
---   update_left_only       bool
---   update_pre_stereo_only bool
---   projected_count        number
function vrmod.utils.StereoLightLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local eye = opts.eye
	if eye ~= nil then eye = tostring(eye) end
	local d = {
		valid = true,
		path_ok = true,
		refresh = false,
		update_projected = false,
		update_dynamic = false,
		eye = eye,
		risk = "none",
		reason = "idle",
	}
	if opts.vr_active == false then
		d.reason = "vr_inactive"
		return d
	end
	if eye ~= "left" and eye ~= "right" then
		d.reason = "no_stereo_eye"
		if vrmod.utils.StereoLightLaw_SkipWhenNoStereoEye() then
			return d
		end
	end
	if opts.update_left_only or opts.update_pre_stereo_only then
		d.path_ok = false
		d.risk = "right_eye_only"
		d.reason = opts.update_left_only and "left_only_update" or "pre_stereo_only"
		return d
	end
	d.refresh = true
	d.update_projected = vrmod.utils.StereoLightLaw_UpdateProjectedPerEye()
	d.update_dynamic = vrmod.utils.StereoLightLaw_RefreshDynamicPerEye()
	d.reason = "per_eye"
	return d
end

function vrmod.utils.StereoLightLaw_StatusLabel(decision)
	if type(decision) ~= "table" then return "LIGHT · IDLE" end
	if decision.risk == "right_eye_only" then return "LIGHT · RIGHT EYE ONLY" end
	if decision.refresh then
		return "LIGHT · PER EYE " .. string.upper(tostring(decision.eye or "?"))
	end
	if decision.reason == "no_stereo_eye" then return "LIGHT · SKIP NEST" end
	return "LIGHT · IDLE"
end

function vrmod.utils.StereoLightLaw_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_both_eyes = true,
		checklist = "G49 · IDLE · no light decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if decision.risk == "right_eye_only" then
		e.verdict = "expect_right_only"
		e.expect_both_eyes = false
		e.checklist = "G49 · RIGHT ONLY · PT/dlight consumed by last view"
		e.pass_line = "Must not ship — left eye unlit"
		e.fail_line = "Light sources only on the right eye"
		return e
	end
	if decision.refresh then
		e.verdict = "expect_both_eyes"
		e.expect_both_eyes = true
		e.checklist = "G49 · PER EYE · ProjectedTexture + DynamicLight"
		e.pass_line = "Lamps / flashlight / sprites in both eyes"
		e.fail_line = "Lights missing on one eye"
		return e
	end
	e.verdict = "expect_skip"
	e.checklist = "G49 · SKIP · no stereo eye / VR off"
	e.pass_line = "Nested views do not consume lights"
	e.fail_line = "Radar/HUD stole the once-per-eye token"
	return e
end

function vrmod.utils.StereoLightLaw_IsRightEyeOnlyRisk(decision)
	return type(decision) == "table" and decision.risk == "right_eye_only"
end
