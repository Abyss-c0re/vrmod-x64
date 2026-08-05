-- Pure law: rigid stereo under head roll (Source cannot do off-axis projection).
-- Goal: world stays a rigid body in the image when the HMD rolls (no shear/bend).
-- Policy when rigid=1:
--   • one shared orientation (HMD) for both eyes
--   • one shared FOV + aspect for both eyes (no L≠R symmetric-frustum mismatch)
--   • eye origins = cyclopean ± halfIPD along head Right() (synthetic IPD)
-- XR absolute eye positions + different per-eye FOVs under roll cause shear in Source.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

function vrmod.utils.StereoRigid_DefaultEnabled()
	return true
end

--- opts:
---   rigid bool|nil
---   eye_mode 0|1|2|nil
---   has_xr_eyes bool
---   xr_ipd_source number|nil  -- Dist(eL,eR) in Source units if known
---   ipd_m number|nil          -- meters from display info
---   scale number|nil
---   eye_scale number|nil      -- vrmod_eyescale 0..1
---   fov_l, fov_r, asp_l, asp_r numbers
function vrmod.utils.StereoRigid_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local rigid = opts.rigid
	if rigid == nil then rigid = vrmod.utils.StereoRigid_DefaultEnabled() end
	rigid = rigid and true or false

	local scale = tonumber(opts.scale) or 1
	if scale < 0.01 then scale = 1 end
	local eyeScale = tonumber(opts.eye_scale)
	if eyeScale == nil then eyeScale = 1 end -- rigid default: full IPD, not half
	if eyeScale < 0 then eyeScale = 0 end
	if eyeScale > 1 then eyeScale = 1 end

	local ipdM = tonumber(opts.ipd_m) or 0.064
	if ipdM < 0.02 then ipdM = 0.064 end
	if ipdM > 0.12 then ipdM = 0.12 end

	local half = ipdM * scale * 0.5 * eyeScale
	local xrIpd = tonumber(opts.xr_ipd_source)
	if xrIpd and xrIpd > 0.5 and xrIpd < (scale * 0.2) then
		-- Prefer measured XR separation (Source units), still along head Right()
		half = xrIpd * 0.5 * eyeScale
	end

	local fovL = tonumber(opts.fov_l) or 90
	local fovR = tonumber(opts.fov_r) or fovL
	local aspL = tonumber(opts.asp_l) or (16 / 9)
	local aspR = tonumber(opts.asp_r) or aspL
	if fovL < 30 then fovL = 30 end
	if fovR < 30 then fovR = 30 end
	if aspL < 0.5 then aspL = 0.5 end
	if aspR < 0.5 then aspR = 0.5 end

	local d = {
		valid = true,
		rigid = rigid,
		use_synth_ipd = true,
		half_ipd = half,
		fov = math.max(fovL, fovR),
		aspect = (aspL + aspR) * 0.5,
		fov_l = fovL,
		fov_r = fovR,
		asp_l = aspL,
		asp_r = aspR,
		shared_orientation = true,
		reason = "rigid_synth",
		risk = "none",
	}

	if not rigid then
		-- Legacy path: allow XR absolute eyes + per-eye FOV (can shear under roll in Source)
		d.use_synth_ipd = false
		d.fov = fovL
		d.aspect = aspL
		d.reason = "legacy_per_eye"
		d.risk = "roll_shear"
		return d
	end

	-- Rigid: both eyes identical projection envelope
	d.fov_l = d.fov
	d.fov_r = d.fov
	d.asp_l = d.aspect
	d.asp_r = d.aspect
	d.reason = "rigid_shared_fov_synth_ipd"
	return d
end

function vrmod.utils.StereoRigid_StatusLabel(d)
	if type(d) ~= "table" or not d.valid then return "STEREO · IDLE" end
	if d.rigid then return "STEREO · RIGID ROLL" end
	return "STEREO · LEGACY"
end

function vrmod.utils.StereoRigid_HmdExpect(d)
	local e = {
		verdict = "idle",
		expect_rigid = true,
		checklist = "STEREO · IDLE",
		pass_line = "Vertical lines stay straight when rolling head (rigid transform)",
		fail_line = "World shears/bends when tilting head to shoulder",
	}
	if type(d) ~= "table" or not d.valid then return e end
	if d.rigid then
		e.verdict = "expect_rigid"
		e.checklist = "STEREO · RIGID · halfIPD=" .. string.format("%.2f", tonumber(d.half_ipd) or 0)
			.. " fov=" .. string.format("%.1f", tonumber(d.fov) or 0)
		return e
	end
	e.verdict = "expect_legacy_risk"
	e.expect_rigid = false
	e.checklist = "STEREO · LEGACY · per-eye FOV/pos may shear under roll"
	return e
end
