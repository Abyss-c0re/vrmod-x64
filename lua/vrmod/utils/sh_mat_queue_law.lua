-- G17: mat_queue_mode Cube pin law (pure, offline-tested).
-- Pain point: never "optimize" to mat_queue_mode 2; pin preference is 1.
-- Product: VR never SetInt mat_queue_mode (CThread crash law).
-- Dual-eye paint only legal when live mode < 2 (G05 stereo-load aligns).
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

--- Cube preferred pin (display / prefer convar only — not engine write).
function vrmod.utils.MatQueueLaw_CubePin()
	return 1
end

--- Clamp engine-read value to 0..2 (observation only).
function vrmod.utils.MatQueueLaw_ClampRead(n)
	n = math.floor(tonumber(n) or vrmod.utils.MatQueueLaw_CubePin())
	if n < 0 then n = 0 end
	if n > 2 then n = 2 end
	return n
end

--- Product must never write mat_queue_mode mid-VR (CThread / worker thrash).
--- context: "vr_session" | "settings" | "exit" | "test" — all false for product.
function vrmod.utils.MatQueueLaw_ShouldWrite(context)
	context = tostring(context or "vr_session")
	if context == "force_test" then return true end -- unit only
	return false
end

--- Dual RealRenderView legal only under mq < 2.
function vrmod.utils.MatQueueLaw_AllowDualEye(mq)
	mq = vrmod.utils.MatQueueLaw_ClampRead(mq)
	return mq < 2
end

--- Pure decision snapshot.
--- opts.live_mode number|nil engine mat_queue_mode read
--- opts.prefer number|nil vrmod_prefer_mat_queue
--- Returns mode, dual_ok, write_forbidden, pin, reason, risk
function vrmod.utils.MatQueueLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local pin = vrmod.utils.MatQueueLaw_CubePin()
	local live = vrmod.utils.MatQueueLaw_ClampRead(opts.live_mode ~= nil and opts.live_mode or pin)
	local prefer = vrmod.utils.MatQueueLaw_ClampRead(opts.prefer ~= nil and opts.prefer or pin)
	local d = {
		valid = true,
		live_mode = live,
		prefer = prefer,
		pin = pin,
		dual_ok = vrmod.utils.MatQueueLaw_AllowDualEye(live),
		write_forbidden = not vrmod.utils.MatQueueLaw_ShouldWrite(opts.context or "vr_session"),
		risk = "none", -- none | mq2_single | prefer_not_pin
		reason = "ok",
	}
	if live >= 2 then
		d.risk = "mq2_single"
		d.reason = "live_mq2_single_pass"
		d.dual_ok = false
	elseif prefer ~= pin then
		d.risk = "prefer_not_pin"
		d.reason = "prefer_differs_pin_display_only"
	else
		d.reason = "pin_aligned"
	end
	return d
end

function vrmod.utils.MatQueueLaw_StatusLabel(decision)
	if type(decision) ~= "table" then return "MQ · IDLE" end
	if decision.live_mode and decision.live_mode >= 2 then
		return "MQ · LIVE 2 · SINGLE"
	end
	if decision.live_mode == 1 then
		return "MQ · LIVE 1 · PIN"
	end
	if decision.live_mode == 0 then
		return "MQ · LIVE 0"
	end
	return "MQ · HOLD"
end

--- Pure HMD observer contract.
function vrmod.utils.MatQueueLaw_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_dual = true,
		checklist = "G17 · IDLE · no mat_queue decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if not decision.write_forbidden then
		e.verdict = "expect_write_fail"
		e.expect_dual = false
		e.checklist = "G17 · WRITE FORBIDDEN VIOLATION"
		e.pass_line = "Must not ship — VR must never SetInt mat_queue_mode"
		e.fail_line = "CThread / worker thrash from mq write"
		return e
	end
	if decision.live_mode >= 2 then
		e.verdict = "expect_mq2_single"
		e.expect_dual = false
		e.checklist = "G17 · MQ2 LIVE · single-pass only · never dual-paint"
		e.pass_line = "Single-pass stereo; no dual nested RenderView"
		e.fail_line = "Dual under mq2 (CThread risk) or forced write to 2"
		return e
	end
	e.verdict = "expect_pin"
	e.expect_dual = decision.dual_ok and true or false
	e.checklist = string.format("G17 · MQ%d · dual_ok · no write · pin prefer %d",
		tonumber(decision.live_mode) or 1, tonumber(decision.pin) or 1)
	e.pass_line = "mat_queue stays 1 (or user 0); dual stereo legal; VR never writes mq"
	e.fail_line = "Product SetInt mat_queue_mode or forced 2"
	return e
end

function vrmod.utils.MatQueueLaw_IsWriteRisk(decision)
	if type(decision) ~= "table" then return true end
	return not decision.write_forbidden
end
