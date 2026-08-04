-- G47: false per-eye / dual FBO guard (pure, offline-tested).
-- Evidence: gen-steal color+depth as L/R left black eye (WiVRn/Quest).
-- Cube way (matches xr_render.cpp Submit path):
--   per-eye only when both color tex IDs distinct AND both FBOs non-zero
--   otherwise fall back to single SBS source (both eyes crop halves)
--   never invent dual from one texture + depth
--   mat_queue_mode 2: never thrash rebind (pain); use staged IDs only
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

function vrmod.utils.FalsePerEyeLaw_RequireBothFbos()
	return true
end

function vrmod.utils.FalsePerEyeLaw_RequireDistinctColorTex()
	return true
end

function vrmod.utils.FalsePerEyeLaw_AllowColorDepthAsDual()
	return false -- gen-steal false dual
end

function vrmod.utils.FalsePerEyeLaw_FallbackToSbsWhenInvalid()
	return true
end

--- Pure: are L/R IDs a legal per-eye pair?
--- opts: left_tex, right_tex, left_fbo, right_fbo (0/nil = missing)
function vrmod.utils.FalsePerEyeLaw_IsLegalPair(opts)
	opts = type(opts) == "table" and opts or {}
	local lt = tonumber(opts.left_tex) or 0
	local rt = tonumber(opts.right_tex) or 0
	local lf = tonumber(opts.left_fbo) or 0
	local rf = tonumber(opts.right_fbo) or 0
	if lt == 0 or rt == 0 then return false end
	if vrmod.utils.FalsePerEyeLaw_RequireDistinctColorTex() and lt == rt then
		return false
	end
	if vrmod.utils.FalsePerEyeLaw_RequireBothFbos() and (lf == 0 or rf == 0) then
		return false
	end
	return true
end

--- Pure path resolution.
--- Returns "per_eye" | "sbs" | "none"
function vrmod.utils.FalsePerEyeLaw_ResolvePath(opts)
	opts = type(opts) == "table" and opts or {}
	if vrmod.utils.FalsePerEyeLaw_IsLegalPair(opts) then
		return "per_eye"
	end
	local sbs = tonumber(opts.sbs_tex) or tonumber(opts.stolen_tex) or 0
	if sbs ~= 0 and vrmod.utils.FalsePerEyeLaw_FallbackToSbsWhenInvalid() then
		return "sbs"
	end
	if opts.left_tex and opts.right_tex and opts.left_tex == opts.right_tex
		and not vrmod.utils.FalsePerEyeLaw_AllowColorDepthAsDual() then
		-- same id both eyes is SBS, not false dual, if we treat as sbs
		local t = tonumber(opts.left_tex) or 0
		if t ~= 0 then return "sbs" end
	end
	return "none"
end

--- Pure decision.
--- opts: left_tex, right_tex, left_fbo, right_fbo, sbs_tex, stolen_tex,
---       claimed_per_eye (bool product thought it had dual)
function vrmod.utils.FalsePerEyeLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local path = vrmod.utils.FalsePerEyeLaw_ResolvePath(opts)
	local legal = vrmod.utils.FalsePerEyeLaw_IsLegalPair(opts)
	local d = {
		valid = true,
		path = path,
		legal_pair = legal,
		left_tex = tonumber(opts.left_tex) or 0,
		right_tex = tonumber(opts.right_tex) or 0,
		left_fbo = tonumber(opts.left_fbo) or 0,
		right_fbo = tonumber(opts.right_fbo) or 0,
		risk = "none", -- none | false_dual | missing_fbo | same_tex | no_src
		reason = "ok",
		path_ok = path ~= "none",
	}
	local lt, rt = d.left_tex, d.right_tex
	local lf, rf = d.left_fbo, d.right_fbo
	if opts.claimed_per_eye and not legal then
		if lt ~= 0 and rt ~= 0 and lt ~= rt and (lf == 0 or rf == 0) then
			d.risk = "missing_fbo"
			d.reason = "claimed_dual_without_both_fbos"
		elseif lt ~= 0 and rt ~= 0 and lt == rt then
			d.risk = "same_tex"
			d.reason = "same_color_tex_not_dual"
		elseif (lt ~= 0 or rt ~= 0) and not vrmod.utils.FalsePerEyeLaw_AllowColorDepthAsDual() then
			d.risk = "false_dual"
			d.reason = "color_depth_or_partial_dual"
		else
			d.risk = "false_dual"
			d.reason = "invalid_per_eye_claim"
		end
		d.path_ok = path == "sbs" -- OK if we fell back
	elseif path == "none" then
		d.risk = "no_src"
		d.reason = "no_per_eye_and_no_sbs"
		d.path_ok = false
	elseif path == "per_eye" then
		d.reason = "legal_per_eye_pair"
		d.path_ok = true
	else
		d.reason = "sbs_fallback"
		d.path_ok = true
	end
	return d
end

function vrmod.utils.FalsePerEyeLaw_StatusLabel(decision)
	if type(decision) ~= "table" then return "EYE · IDLE" end
	if decision.risk == "false_dual" then return "EYE · FALSE DUAL" end
	if decision.risk == "missing_fbo" then return "EYE · MISSING FBO" end
	if decision.risk == "same_tex" then return "EYE · SAME TEX" end
	if decision.risk == "no_src" then return "EYE · NO SRC" end
	if decision.path == "per_eye" then return "EYE · PER-EYE OK" end
	if decision.path == "sbs" then return "EYE · SBS FALLBACK" end
	return "EYE · HOLD"
end

function vrmod.utils.FalsePerEyeLaw_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_both_eyes = true,
		checklist = "G47 · IDLE · no eye-pair decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if decision.risk == "false_dual" or decision.risk == "missing_fbo" then
		e.verdict = "expect_black_eye_risk"
		e.expect_both_eyes = false
		e.checklist = "G47 · BLACK EYE RISK · " .. tostring(decision.reason)
		e.pass_line = "Require both FBOs+distinct color; else SBS halves"
		e.fail_line = "One eye black / 1/8 strip from false dual"
		return e
	end
	if decision.risk == "no_src" then
		e.verdict = "expect_no_src"
		e.expect_both_eyes = false
		e.checklist = "G47 · NO SRC · no per-eye and no SBS"
		e.pass_line = "ShareTexture / stolen SBS before submit"
		e.fail_line = "Both eyes black / no submit source"
		return e
	end
	if decision.path == "sbs" then
		e.verdict = "expect_sbs"
		e.checklist = "G47 · SBS · both eyes from one RT halves"
		e.pass_line = "Clear stereo pair from SBS crop"
		e.fail_line = "Wrong half crop / mono void"
		return e
	end
	e.verdict = "expect_per_eye"
	e.checklist = "G47 · PER-EYE · both FBOs + distinct color"
	e.pass_line = "Both eyes clear from dual textures"
	e.fail_line = "One eye black despite claimed dual"
	return e
end

function vrmod.utils.FalsePerEyeLaw_IsBlackEyeRisk(decision)
	if type(decision) ~= "table" then return false end
	return decision.risk == "false_dual"
		or decision.risk == "missing_fbo"
		or decision.risk == "no_src"
end
