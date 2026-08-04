-- G40: Vision / border fill law (pure, offline-tested).
-- Watchlist W1: black bars / edge bleed / FOV not filling HMD.
-- Cube way: Vision-guided path only (scale → V → H → save); defaults scale=1, offsets=0.
-- Prefer guide + profile over anonymous slider maze or Z spam. Soft care: never thrash FOV archives.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

function vrmod.utils.BorderLaw_ProfilePath()
	return "vrmod/border_profile.txt"
end

function vrmod.utils.BorderLaw_DefaultScale()
	return 1.0
end

function vrmod.utils.BorderLaw_DefaultVertical()
	return 0.0
end

function vrmod.utils.BorderLaw_DefaultHorizontal()
	return 0.0
end

function vrmod.utils.BorderLaw_ScaleMin()
	return 0.05
end

function vrmod.utils.BorderLaw_ScaleMax()
	return 4.0
end

function vrmod.utils.BorderLaw_OffsetMin()
	return -1.0
end

function vrmod.utils.BorderLaw_OffsetMax()
	return 1.0
end

--- Soft comfort: extreme scale / offsets flag bleed risk (still allowed for guide).
function vrmod.utils.BorderLaw_ComfortScaleMin()
	return 0.7
end

function vrmod.utils.BorderLaw_ComfortScaleMax()
	return 1.35
end

function vrmod.utils.BorderLaw_ComfortOffsetAbsMax()
	return 0.35
end

function vrmod.utils.BorderLaw_ScaleStep()
	return 0.02
end

function vrmod.utils.BorderLaw_OffsetStep()
	return 0.01
end

--- Guided Vision step order (W1): not a slider maze.
function vrmod.utils.BorderLaw_StepIds()
	return { "reset", "scale", "vertical", "horizontal", "done" }
end

function vrmod.utils.BorderLaw_IsGuidedPathOnly()
	return true
end

function vrmod.utils.BorderLaw_PreferGuideOverZSpam()
	return true -- W5: use Border guide, not Z spam
end

function vrmod.utils.BorderLaw_RequireRenderOffsetOnGuide()
	return true -- auto UV offset on during cal baseline
end

function vrmod.utils.BorderLaw_ClampScale(v)
	v = tonumber(v)
	if v == nil then return vrmod.utils.BorderLaw_DefaultScale() end
	local lo, hi = vrmod.utils.BorderLaw_ScaleMin(), vrmod.utils.BorderLaw_ScaleMax()
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

function vrmod.utils.BorderLaw_ClampOffset(v)
	v = tonumber(v)
	if v == nil then return 0.0 end
	local lo, hi = vrmod.utils.BorderLaw_OffsetMin(), vrmod.utils.BorderLaw_OffsetMax()
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

function vrmod.utils.BorderLaw_IsBleedRisk(opts)
	opts = type(opts) == "table" and opts or {}
	local s = tonumber(opts.scalefactor) or vrmod.utils.BorderLaw_DefaultScale()
	local vo = math.abs(tonumber(opts.verticaloffset) or 0)
	local ho = math.abs(tonumber(opts.horizontaloffset) or 0)
	if s < vrmod.utils.BorderLaw_ComfortScaleMin() or s > vrmod.utils.BorderLaw_ComfortScaleMax() then
		return true
	end
	local lim = vrmod.utils.BorderLaw_ComfortOffsetAbsMax()
	if vo > lim or ho > lim then return true end
	return false
end

--- Baseline for guided start: clean center, scale 1, offsets 0.
function vrmod.utils.BorderLaw_GuideBaseline()
	return {
		scalefactor = vrmod.utils.BorderLaw_DefaultScale(),
		verticaloffset = vrmod.utils.BorderLaw_DefaultVertical(),
		horizontaloffset = vrmod.utils.BorderLaw_DefaultHorizontal(),
		renderoffset = vrmod.utils.BorderLaw_RequireRenderOffsetOnGuide() and 1 or 0,
	}
end

--- Sanitize live border params (clamp only; does not rewrite FOV archives).
function vrmod.utils.BorderLaw_Sanitize(opts)
	opts = type(opts) == "table" and opts or {}
	local rawS = tonumber(opts.scalefactor)
	local rawV = tonumber(opts.verticaloffset)
	local rawH = tonumber(opts.horizontaloffset)
	local s = vrmod.utils.BorderLaw_ClampScale(rawS)
	local vo = vrmod.utils.BorderLaw_ClampOffset(rawV)
	local ho = vrmod.utils.BorderLaw_ClampOffset(rawH)
	local clamped = false
	if rawS ~= nil and math.abs(s - rawS) > 1e-6 then clamped = true end
	if rawV ~= nil and math.abs(vo - rawV) > 1e-6 then clamped = true end
	if rawH ~= nil and math.abs(ho - rawH) > 1e-6 then clamped = true end
	return {
		scalefactor = s,
		verticaloffset = vo,
		horizontaloffset = ho,
		clamped = clamped,
		bleed_risk = vrmod.utils.BorderLaw_IsBleedRisk({
			scalefactor = s,
			verticaloffset = vo,
			horizontaloffset = ho,
		}),
	}
end

--- Pure decision.
--- opts: scalefactor, verticaloffset, horizontaloffset,
---       guide_active, profile_loaded, fill_ok (optional HMD observation)
function vrmod.utils.BorderLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local san = vrmod.utils.BorderLaw_Sanitize(opts)
	local d = {
		valid = true,
		scalefactor = san.scalefactor,
		verticaloffset = san.verticaloffset,
		horizontaloffset = san.horizontaloffset,
		clamped = san.clamped,
		bleed_risk = san.bleed_risk,
		guide_active = opts.guide_active and true or false,
		profile_loaded = opts.profile_loaded and true or false,
		fill_ok = opts.fill_ok, -- nil unknown | true | false
		risk = "none", -- none | bleed | clamp | bars | guide
		reason = "ok",
		path_ok = true,
	}
	if opts.fill_ok == false then
		d.risk = "bars"
		d.reason = "hmd_bars_or_bleed"
		d.path_ok = false
	elseif d.guide_active then
		d.risk = "guide"
		d.reason = "vision_guide_active"
		d.path_ok = true
	elseif d.clamped then
		d.risk = "clamp"
		d.reason = "border_params_clamped"
		d.path_ok = true
	elseif d.bleed_risk then
		d.risk = "bleed"
		d.reason = "border_outside_comfort"
		d.path_ok = true -- flagged, not fail
	elseif d.profile_loaded then
		d.reason = "profile_ok"
		d.path_ok = true
	else
		d.reason = "defaults_ok"
		d.path_ok = true
	end
	return d
end

function vrmod.utils.BorderLaw_StatusLabel(decision)
	if type(decision) ~= "table" then return "BORDER · IDLE" end
	if decision.risk == "bars" then return "BORDER · BARS" end
	if decision.risk == "guide" then return "BORDER · GUIDE" end
	if decision.risk == "clamp" then return "BORDER · CLAMP" end
	if decision.risk == "bleed" then return "BORDER · BLEED RISK" end
	if decision.path_ok then return "BORDER · OK" end
	return "BORDER · HOLD"
end

function vrmod.utils.BorderLaw_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_fill = true,
		checklist = "G40 · IDLE · no border decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if decision.risk == "bars" then
		e.verdict = "expect_bars"
		e.expect_fill = false
		e.checklist = "G40 · BARS · black bars / edge bleed in HMD"
		e.pass_line = "Run vrmod_border_calibrate (scale→V→H→save); reload profile later"
		e.fail_line = "FOV not filling HMD; permanent black bars"
		return e
	end
	if decision.risk == "guide" then
		e.verdict = "expect_guide"
		e.checklist = "G40 · GUIDE · Vision border path active"
		e.pass_line = "Complete scale → vertical → horizontal → save profile"
		e.fail_line = "Cancel mid-path without profile; bars remain"
		return e
	end
	if decision.risk == "bleed" then
		e.verdict = "expect_bleed_risk"
		e.expect_fill = false
		e.checklist = "G40 · BLEED RISK · extreme scale/offset (comfort)"
		e.pass_line = "Reset defaults or re-run Vision guide"
		e.fail_line = "Edge bleed / tunnel crop from extreme UV crop"
		return e
	end
	e.verdict = "expect_ok"
	e.checklist = string.format(
		"G40 · OK · scale=%.2f v=%.2f h=%.2f",
		tonumber(decision.scalefactor) or 1,
		tonumber(decision.verticaloffset) or 0,
		tonumber(decision.horizontaloffset) or 0
	)
	e.pass_line = "HMD filled; no black bars; profile or defaults stable"
	e.fail_line = "Bars/bleed with scale≈1 and offsets≈0"
	return e
end

function vrmod.utils.BorderLaw_IsBleedDecision(decision)
	if type(decision) ~= "table" then return false end
	return decision.risk == "bleed" or decision.risk == "bars"
end
