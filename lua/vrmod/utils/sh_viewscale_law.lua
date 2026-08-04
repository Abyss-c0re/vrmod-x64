-- G35: viewscale fisheye law (pure, offline-tested).
-- Watchlist W8: fisheye everything — usually viewscale / FOV scale / wrong projection.
-- Cube way: default 1.0; clamp comfort band; prefer HMD projection (projLive), not free-cam FOV.
-- Extreme viewscale warps projection params → fisheye / tunnel vision.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

function vrmod.utils.ViewScaleLaw_CubeDefault()
	return 1.0
end

function vrmod.utils.ViewScaleLaw_Min()
	return 0.1
end

function vrmod.utils.ViewScaleLaw_Max()
	return 2.0
end

--- Soft comfort band: outside still allowed but flagged fisheye risk.
function vrmod.utils.ViewScaleLaw_ComfortMin()
	return 0.75
end

function vrmod.utils.ViewScaleLaw_ComfortMax()
	return 1.25
end

function vrmod.utils.ViewScaleLaw_Clamp(v)
	v = tonumber(v)
	if v == nil then return vrmod.utils.ViewScaleLaw_CubeDefault() end
	local lo = vrmod.utils.ViewScaleLaw_Min()
	local hi = vrmod.utils.ViewScaleLaw_Max()
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

function vrmod.utils.ViewScaleLaw_IsFisheyeRisk(v)
	v = tonumber(v)
	if v == nil then return false end
	return v < vrmod.utils.ViewScaleLaw_ComfortMin() or v > vrmod.utils.ViewScaleLaw_ComfortMax()
end

--- Projection must come from HMD (projLive), not free-cam identity FOV.
function vrmod.utils.ViewScaleLaw_PreferHmdProjection()
	return true
end

function vrmod.utils.ViewScaleLaw_IsProjectionLive(projLive)
	return projLive and true or false
end

--- Pure decision snapshot.
--- opts:
---   viewscale number|nil
---   proj_live bool|nil
---   fovscale_x, fovscale_y number|nil  (extreme FOV also fisheye-adjacent)
function vrmod.utils.ViewScaleLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local raw = tonumber(opts.viewscale)
	local applied = vrmod.utils.ViewScaleLaw_Clamp(raw)
	local projLive = opts.proj_live and true or false
	local fx = tonumber(opts.fovscale_x) or 1
	local fy = tonumber(opts.fovscale_y) or 1
	local d = {
		valid = true,
		requested = raw,
		applied = applied,
		clamped = (raw ~= nil) and (math.abs(applied - raw) > 1e-6) or false,
		proj_live = projLive,
		fisheye_risk = vrmod.utils.ViewScaleLaw_IsFisheyeRisk(applied),
		risk = "none", -- none | fisheye | clamp | dead_proj | fov_extreme
		reason = "ok",
		path_ok = true,
	}
	local fovExtreme = fx < 0.5 or fx > 1.5 or fy < 0.5 or fy > 1.5
	if not projLive and opts.require_proj_live then
		d.risk = "dead_proj"
		d.reason = "projection_not_live_use_hmd"
		d.path_ok = false
	elseif d.clamped then
		d.risk = "clamp"
		d.reason = "viewscale_clamped"
		d.path_ok = true -- clamp is product law, not fail
	elseif d.fisheye_risk then
		d.risk = "fisheye"
		d.reason = "viewscale_outside_comfort"
		d.path_ok = true -- allowed but flagged
	elseif fovExtreme then
		d.risk = "fov_extreme"
		d.reason = "fovscale_outside_comfort"
		d.path_ok = true
	else
		d.reason = "viewscale_ok"
		d.path_ok = true
	end
	return d
end

function vrmod.utils.ViewScaleLaw_StatusLabel(decision)
	if type(decision) ~= "table" then return "VS · IDLE" end
	if decision.risk == "dead_proj" then return "VS · DEAD PROJ" end
	if decision.risk == "clamp" then return "VS · CLAMP" end
	if decision.risk == "fisheye" then return "VS · FISHEYE RISK" end
	if decision.risk == "fov_extreme" then return "VS · FOV RISK" end
	if decision.path_ok then return "VS · OK" end
	return "VS · HOLD"
end

function vrmod.utils.ViewScaleLaw_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_natural = true,
		checklist = "G35 · IDLE · no viewscale decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if decision.risk == "dead_proj" then
		e.verdict = "expect_dead_proj"
		e.expect_natural = false
		e.checklist = "G35 · DEAD PROJ · wait HMD projection (not free-cam FOV)"
		e.pass_line = "Soft-refresh until projLive; viewscale applies to HMD frusta"
		e.fail_line = "Stuck identity FOV; borders look wrong forever"
		return e
	end
	if decision.risk == "fisheye" or decision.risk == "fov_extreme" then
		e.verdict = "expect_fisheye_risk"
		e.expect_natural = false
		e.checklist = "G35 · FISHEYE RISK · " .. tostring(decision.reason)
		e.pass_line = "Reset viewscale/fov to 1.0 or Vision defaults"
		e.fail_line = "Everything fisheye / tunnel with extreme scales"
		return e
	end
	e.verdict = "expect_ok"
	e.checklist = "G35 · OK · viewscale=" .. string.format("%.2f", tonumber(decision.applied) or 1)
	e.pass_line = "Natural edges; no fisheye; HMD projection live"
	e.fail_line = "Fisheye at default 1.0 / wrong projection source"
	return e
end

function vrmod.utils.ViewScaleLaw_IsFisheyeDecision(decision)
	if type(decision) ~= "table" then return false end
	return decision.risk == "fisheye" or decision.risk == "fov_extreme"
end
