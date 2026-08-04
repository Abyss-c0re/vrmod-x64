-- G36: FOV / Z soft-refresh law (pure, offline-tested).
-- Watchlist W5: right eye jitter / wrap when adjusting Z / FOV.
-- Cube way: don't let submit UV + FOV scale fight mid-frame.
-- Live FOV applies only via SoftRefresh (next eye sync); clamp extreme FOV;
-- Znear updates session view only; border offsets → submit bounds only.
-- Prefer Border guide over Z spam.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

function vrmod.utils.FovZLaw_FovMin()
	return 0.1
end

function vrmod.utils.FovZLaw_FovMax()
	return 2.0
end

function vrmod.utils.FovZLaw_FovComfortMin()
	return 0.5
end

function vrmod.utils.FovZLaw_FovComfortMax()
	return 1.5
end

function vrmod.utils.FovZLaw_ZnearMin()
	return 0.1
end

function vrmod.utils.FovZLaw_ZnearMax()
	return 64.0
end

function vrmod.utils.FovZLaw_ZnearDefault()
	return 1.0
end

function vrmod.utils.FovZLaw_ClampFovScale(v)
	v = tonumber(v)
	if v == nil then return 1.0 end
	local lo = vrmod.utils.FovZLaw_FovMin()
	local hi = vrmod.utils.FovZLaw_FovMax()
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

function vrmod.utils.FovZLaw_ClampZnear(v)
	v = tonumber(v)
	if v == nil then return vrmod.utils.FovZLaw_ZnearDefault() end
	local lo = vrmod.utils.FovZLaw_ZnearMin()
	local hi = vrmod.utils.FovZLaw_ZnearMax()
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

function vrmod.utils.FovZLaw_IsFovExtreme(v)
	v = tonumber(v)
	if v == nil then return false end
	return v < vrmod.utils.FovZLaw_FovComfortMin() or v > vrmod.utils.FovZLaw_FovComfortMax()
end

--- Never rewrite UV + FOV mid stereo eye (W5 jitter).
function vrmod.utils.FovZLaw_AllowMidFrameUvFight()
	return false
end

--- Live FOV must go through SoftRefreshDisplayParams, not ad-hoc mid-frame.
function vrmod.utils.FovZLaw_AllowLiveFovWithoutSoftRefresh()
	return false
end

local BORDER = {
	vrmod_horizontaloffset = true,
	vrmod_verticaloffset = true,
	vrmod_scalefactor = true,
	vrmod_renderoffset = true,
	vrmod_submit_crop = true,
}

local FOV_PROFILE = {
	vrmod_fovscale_x = true,
	vrmod_fovscale_y = true,
	vrmod_viewscale = true,
	vrmod_desktopview = true,
	vrmod_eyescale = true,
	vrmod_swap_eyes = true,
}

local SESSION = {
	vrmod_znear = true,
	vrmod_postprocess = true,
	vrmod_scale = true,
	vrmod_controlleroffset_x = true,
	vrmod_controlleroffset_y = true,
	vrmod_controlleroffset_z = true,
	vrmod_controlleroffset_pitch = true,
	vrmod_controlleroffset_yaw = true,
	vrmod_controlleroffset_roll = true,
}

function vrmod.utils.FovZLaw_NormalizeCvar(name)
	name = tostring(name or "")
	name = name:gsub("^%s+", ""):gsub("%s+$", "")
	return string.lower(name)
end

--- Pure refresh kind for a convar change while VR active.
--- soft_display | submit_bounds | session | none
function vrmod.utils.FovZLaw_RefreshKind(cvarName)
	local n = vrmod.utils.FovZLaw_NormalizeCvar(cvarName)
	if n == "" then return "none" end
	if BORDER[n] then return "submit_bounds" end
	if FOV_PROFILE[n] then return "soft_display" end
	if SESSION[n] then return "session" end
	return "none"
end

function vrmod.utils.FovZLaw_IsBorderCvar(name)
	return vrmod.utils.FovZLaw_RefreshKind(name) == "submit_bounds"
end

function vrmod.utils.FovZLaw_IsFovProfileCvar(name)
	return vrmod.utils.FovZLaw_RefreshKind(name) == "soft_display"
end

function vrmod.utils.FovZLaw_IsSessionCvar(name)
	return vrmod.utils.FovZLaw_RefreshKind(name) == "session"
end

--- Prefer Border guide over Z spam for edge fill (docs).
function vrmod.utils.FovZLaw_PreferBorderGuideOverZSpam()
	return true
end

--- Pure decision snapshot.
--- opts:
---   cvar string|nil
---   fov_x, fov_y number|nil
---   znear number|nil
---   mid_frame_uv_and_fov bool|nil   forbidden dual path
---   soft_refreshed bool|nil
---   vr_active bool|nil
function vrmod.utils.FovZLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local kind = vrmod.utils.FovZLaw_RefreshKind(opts.cvar)
	local fx = vrmod.utils.FovZLaw_ClampFovScale(opts.fov_x)
	local fy = vrmod.utils.FovZLaw_ClampFovScale(opts.fov_y)
	local zn = vrmod.utils.FovZLaw_ClampZnear(opts.znear)
	local d = {
		valid = true,
		vr_active = opts.vr_active and true or false,
		cvar = vrmod.utils.FovZLaw_NormalizeCvar(opts.cvar),
		refresh_kind = kind,
		fov_x = fx,
		fov_y = fy,
		znear = zn,
		fov_extreme = vrmod.utils.FovZLaw_IsFovExtreme(fx) or vrmod.utils.FovZLaw_IsFovExtreme(fy),
		soft_refreshed = opts.soft_refreshed and true or false,
		risk = "none", -- none | mid_frame_fight | no_soft | extreme_fov | z_spam
		reason = "ok",
		path_ok = true,
	}
	if opts.mid_frame_uv_and_fov then
		d.risk = "mid_frame_fight"
		d.reason = "uv_and_fov_same_frame"
		d.path_ok = false
	elseif kind == "soft_display" and opts.vr_active and opts.soft_refreshed == false then
		d.risk = "no_soft"
		d.reason = "fov_without_soft_refresh"
		d.path_ok = false
	elseif d.fov_extreme then
		d.risk = "extreme_fov"
		d.reason = "fov_outside_comfort_use_border_guide"
		d.path_ok = true -- allowed but flagged
	elseif kind == "session" and d.cvar == "vrmod_znear" and opts.z_spam then
		d.risk = "z_spam"
		d.reason = "prefer_border_guide"
		d.path_ok = true
	else
		d.reason = kind == "none" and "idle" or ("refresh_" .. kind)
		d.path_ok = true
	end
	return d
end

function vrmod.utils.FovZLaw_StatusLabel(decision)
	if type(decision) ~= "table" then return "FOVZ · IDLE" end
	if decision.risk == "mid_frame_fight" then return "FOVZ · MID-FRAME FIGHT" end
	if decision.risk == "no_soft" then return "FOVZ · NEED SOFT" end
	if decision.risk == "extreme_fov" then return "FOVZ · EXTREME FOV" end
	if decision.risk == "z_spam" then return "FOVZ · Z SPAM" end
	if decision.refresh_kind == "submit_bounds" then return "FOVZ · BOUNDS" end
	if decision.refresh_kind == "soft_display" then return "FOVZ · SOFT" end
	if decision.refresh_kind == "session" then return "FOVZ · SESSION" end
	if decision.path_ok then return "FOVZ · OK" end
	return "FOVZ · HOLD"
end

function vrmod.utils.FovZLaw_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_stable_eye = true,
		checklist = "G36 · IDLE · no FOV/Z decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if decision.risk == "mid_frame_fight" or decision.risk == "no_soft" then
		e.verdict = "expect_jitter_fail"
		e.expect_stable_eye = false
		e.checklist = "G36 · FAIL · " .. tostring(decision.reason)
		e.pass_line = "SoftRefresh only; no mid-frame UV+FOV fight"
		e.fail_line = "Right eye wrap/jitter; HMD freeze on Z/FOV spam"
		return e
	end
	if decision.risk == "extreme_fov" then
		e.verdict = "expect_extreme"
		e.checklist = "G36 · EXTREME FOV · use Border guide"
		e.pass_line = "Clamp + Border calibrate; not Z spam"
		e.fail_line = "One eye wraps; freeze"
		return e
	end
	e.verdict = "expect_ok"
	e.checklist = "G36 · OK · kind=" .. tostring(decision.refresh_kind)
	e.pass_line = "Live FOV/Z stable both eyes; soft path only"
	e.fail_line = "Right eye jitter when adjusting FOV/Z"
	return e
end

function vrmod.utils.FovZLaw_IsJitterRisk(decision)
	if type(decision) ~= "table" then return true end
	return decision.risk == "mid_frame_fight" or decision.risk == "no_soft"
end
