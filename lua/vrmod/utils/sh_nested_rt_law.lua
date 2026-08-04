-- G43: nested RT / menu-open crash law (pure, offline-tested).
-- Ship bar: menu-open crash ~2s after open (malloc / nested RT under stereo).
-- Cube way:
--   never nest menu/HUD panel RTs while stereoRtActive (g_VR.rt pushed)
--   HUD capture only in PreStereoCapture (before stereo push)
--   always PopRenderTarget after menu paint (stack corruption → hard crash)
--   no drawmonitors / nested portal RenderView under VR RT
--   radar/ortho capture scrubbed before stereo push
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

function vrmod.utils.NestedRtLaw_AllowNestUnderStereo()
	return false
end

function vrmod.utils.NestedRtLaw_RequirePopAfterMenuPaint()
	return true
end

function vrmod.utils.NestedRtLaw_HudCaptureBeforeStereoPush()
	return true
end

function vrmod.utils.NestedRtLaw_AllowDrawMonitorsInVrRt()
	return false
end

function vrmod.utils.NestedRtLaw_AllowPortalRenderViewInStereo()
	return false
end

--- Pure: may this path PushRenderTarget a menu/HUD RT right now?
--- opts: stereo_rt_active, stereo_eye, rendering_hud_rt, radar_capturing, phase
--- phase: "pre_stereo_capture" | "pre_stereo" | "stereo_eye" | "post" | nil
function vrmod.utils.NestedRtLaw_AllowMenuRtPaint(opts)
	opts = type(opts) == "table" and opts or {}
	if opts.stereo_rt_active and not vrmod.utils.NestedRtLaw_AllowNestUnderStereo() then
		return false
	end
	if opts.stereo_eye and not vrmod.utils.NestedRtLaw_AllowNestUnderStereo() then
		return false
	end
	return true
end

--- Pure: may HUD RT capture run in this phase?
function vrmod.utils.NestedRtLaw_AllowHudCapture(opts)
	opts = type(opts) == "table" and opts or {}
	if opts.stereo_rt_active then return false end
	if opts.stereo_eye then return false end
	if opts.phase == "stereo_eye" then return false end
	if opts.phase == "pre_stereo_capture" or opts.phase == "pre_stereo" or opts.phase == nil then
		return true
	end
	-- post is ok only if not under stereo RT
	return not opts.stereo_rt_active
end

--- Pure: may radar / nested world capture run?
function vrmod.utils.NestedRtLaw_AllowNestedWorldCapture(opts)
	opts = type(opts) == "table" and opts or {}
	if opts.stereo_rt_active or opts.stereo_eye or opts.rendering_hud_rt or opts.radar_capturing then
		return false
	end
	-- mat_queue_mode 2: nested ortho races workers
	local mq = tonumber(opts.mat_queue_mode)
	if mq == 2 then return false end
	return true
end

function vrmod.utils.NestedRtLaw_DeferMenuWhenStereoActive()
	return true -- mark dirty, paint next PreStereoCapture
end

--- Pure decision.
--- opts: stereo_rt_active, stereo_eye, menu_open, menu_paint_attempt,
---       hud_capture_phase, nested_world_attempt, pop_after_paint,
---       mat_queue_mode, drawmonitors
function vrmod.utils.NestedRtLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local stereo = opts.stereo_rt_active and true or false
	local eye = opts.stereo_eye and true or false
	local allowMenu = vrmod.utils.NestedRtLaw_AllowMenuRtPaint(opts)
	local allowHud = vrmod.utils.NestedRtLaw_AllowHudCapture({
		stereo_rt_active = opts.stereo_rt_active,
		stereo_eye = opts.stereo_eye,
		phase = opts.hud_capture_phase,
	})
	local allowWorld = vrmod.utils.NestedRtLaw_AllowNestedWorldCapture(opts)
	local d = {
		valid = true,
		stereo_rt_active = stereo,
		stereo_eye = eye,
		allow_menu_rt = allowMenu,
		allow_hud_capture = allowHud,
		allow_nested_world = allowWorld,
		defer_menu = stereo and vrmod.utils.NestedRtLaw_DeferMenuWhenStereoActive(),
		risk = "none", -- none | nest_menu | nest_hud | nest_world | no_pop | drawmonitors
		reason = "ok",
		path_ok = true,
	}
	if opts.menu_paint_attempt and not allowMenu then
		d.risk = "nest_menu"
		d.reason = "menu_rt_under_stereo_forbidden"
		d.path_ok = false -- attempt was illegal; product should have deferred
	elseif opts.hud_nested_under_stereo then
		d.risk = "nest_hud"
		d.reason = "hud_rt_under_stereo_forbidden"
		d.path_ok = false
	elseif opts.nested_world_attempt and not allowWorld then
		d.risk = "nest_world"
		d.reason = "nested_world_under_stereo_or_mq2"
		d.path_ok = false
	elseif opts.pop_after_paint == false and opts.menu_paint_attempt and allowMenu then
		d.risk = "no_pop"
		d.reason = "missing_pop_rendertarget"
		d.path_ok = false
	elseif opts.drawmonitors == true and (stereo or eye) then
		d.risk = "drawmonitors"
		d.reason = "drawmonitors_under_vr_rt"
		d.path_ok = false
	elseif stereo then
		d.reason = "stereo_active_defer_menu"
		d.path_ok = true
	else
		d.reason = "nested_rt_safe"
		d.path_ok = true
	end
	return d
end

function vrmod.utils.NestedRtLaw_StatusLabel(decision)
	if type(decision) ~= "table" then return "NEST · IDLE" end
	if decision.risk == "nest_menu" then return "NEST · MENU FORBIDDEN" end
	if decision.risk == "nest_hud" then return "NEST · HUD FORBIDDEN" end
	if decision.risk == "nest_world" then return "NEST · WORLD FORBIDDEN" end
	if decision.risk == "no_pop" then return "NEST · NO POP" end
	if decision.risk == "drawmonitors" then return "NEST · DRAWMONITORS" end
	if decision.stereo_rt_active then return "NEST · STEREO DEFER" end
	if decision.path_ok then return "NEST · OK" end
	return "NEST · HOLD"
end

function vrmod.utils.NestedRtLaw_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_stable_menu = true,
		checklist = "G43 · IDLE · no nested-RT decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if decision.risk == "nest_menu" or decision.risk == "nest_hud" or decision.risk == "no_pop" then
		e.verdict = "expect_crash_risk"
		e.expect_stable_menu = false
		e.checklist = "G43 · CRASH RISK · " .. tostring(decision.reason)
		e.pass_line = "Defer menu/HUD RT until outside stereo; always PopRenderTarget"
		e.fail_line = "Malloc crash ~2s after menu open / RT stack corruption"
		return e
	end
	if decision.risk == "nest_world" or decision.risk == "drawmonitors" then
		e.verdict = "expect_flicker_risk"
		e.checklist = "G43 · FLICKER RISK · " .. tostring(decision.reason)
		e.pass_line = "No nested world under stereo; drawmonitors off in VR RT"
		e.fail_line = "Map flicker / heap thrash after menu or radar"
		return e
	end
	e.verdict = "expect_ok"
	e.checklist = "G43 · OK · menu/HUD outside stereo RT"
	e.pass_line = "Open Cube/settings menus stable; no crash ~2s later"
	e.fail_line = "Crash or black after menu open under stereo"
	return e
end

function vrmod.utils.NestedRtLaw_IsCrashRisk(decision)
	if type(decision) ~= "table" then return false end
	return decision.risk == "nest_menu"
		or decision.risk == "nest_hud"
		or decision.risk == "no_pop"
end
