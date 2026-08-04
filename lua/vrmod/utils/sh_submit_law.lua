-- G19: submit path law (pure, offline-tested).
-- Pain point #6: never Submit eng IN texture; dual OUT RGBA8 only;
-- no virgin OUT before blit. Energy: eng IN → blit → dual OUT → Submit.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

--- Legal submit texture kinds (module dual OUT only).
function vrmod.utils.SubmitLaw_PreferTextureKind()
	return "dual_out_rgba8"
end

--- Product must never submit the live engine RT (IN) to OpenXR.
function vrmod.utils.SubmitLaw_AllowSubmitEngIn()
	return false
end

--- Product must never submit an unallocated / empty OUT swapchain image.
function vrmod.utils.SubmitLaw_AllowVirginOut()
	return false
end

--- Blit eng IN → dual OUT is required before Submit when collect path runs.
--- Under mq≥2 collect is skipped (worker race); single-pass may use staged OUT only.
function vrmod.utils.SubmitLaw_RequireBlitBeforeSubmit(opts)
	opts = type(opts) == "table" and opts or {}
	local mq = tonumber(opts.mat_queue_mode)
	if mq == nil then mq = 1 end
	-- Collect/blit legal only under mq < 2
	return mq < 2
end

--- Whether CollectEyes-style isolate is allowed this frame.
function vrmod.utils.SubmitLaw_AllowCollect(opts)
	return vrmod.utils.SubmitLaw_RequireBlitBeforeSubmit(opts)
end

--- Pure decision snapshot.
--- opts:
---   mat_queue_mode number|nil
---   vr_active bool|nil
---   painted bool|nil          dual/single paint ran this frame
---   collected bool|nil        CollectEyes / blit ran
---   submit_texture string|nil "dual_out_rgba8" | "eng_in" | "virgin_out" | other
---   keep_submit bool|nil
--- Returns valid, allow_submit, collect_ok, texture_kind, risk, reason
function vrmod.utils.SubmitLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local mq = tonumber(opts.mat_queue_mode)
	if mq == nil then mq = 1 end
	local active = opts.vr_active and true or false
	local painted = opts.painted and true or false
	local collected = opts.collected and true or false
	local keep = opts.keep_submit
	if keep == nil then keep = active end
	keep = keep and true or false
	local tex = tostring(opts.submit_texture or vrmod.utils.SubmitLaw_PreferTextureKind())
	local prefer = vrmod.utils.SubmitLaw_PreferTextureKind()
	local collectOk = vrmod.utils.SubmitLaw_AllowCollect({ mat_queue_mode = mq })
	local d = {
		valid = true,
		mat_queue_mode = mq,
		vr_active = active,
		painted = painted,
		collected = collected,
		keep_submit = keep,
		collect_ok = collectOk,
		texture_kind = tex,
		prefer_kind = prefer,
		allow_submit = false,
		risk = "none", -- none | eng_in | virgin_out | no_paint | mq2_no_collect
		reason = "ok",
	}
	if not active or not keep then
		d.allow_submit = false
		d.reason = "inactive_or_no_submit"
		return d
	end
	if tex == "eng_in" or tex == "engine_in" then
		d.risk = "eng_in"
		d.reason = "submit_eng_in_forbidden"
		d.allow_submit = false
		return d
	end
	if tex == "virgin_out" then
		d.risk = "virgin_out"
		d.reason = "virgin_out_before_blit"
		d.allow_submit = false
		return d
	end
	-- Only dual OUT (and short alias) are legal submit kinds.
	if tex ~= prefer and tex ~= "dual_out" then
		d.risk = "eng_in"
		d.reason = "unknown_submit_texture"
		d.allow_submit = false
		return d
	end
	if not painted and not collected then
		-- OpenXR still needs EndFrame; product may submit last good dual OUT (not virgin).
		d.risk = "no_paint"
		d.reason = "no_paint_keep_last_out"
		d.allow_submit = true -- last OUT only; never invent eng_in
		return d
	end
	if mq >= 2 then
		d.risk = "mq2_no_collect"
		d.reason = "mq2_single_pass_no_live_blit"
		d.allow_submit = true -- staged single path; still dual OUT ids
		return d
	end
	-- Happy path: dual OUT after paint (+ optional collect)
	d.allow_submit = true
	d.reason = collected and "blit_then_submit" or "paint_submit_dual_out"
	return d
end

function vrmod.utils.SubmitLaw_StatusLabel(decision)
	if type(decision) ~= "table" then return "SUBMIT · IDLE" end
	if decision.risk == "eng_in" then return "SUBMIT · FORBID ENG IN" end
	if decision.risk == "virgin_out" then return "SUBMIT · FORBID VIRGIN" end
	if not decision.allow_submit then return "SUBMIT · HOLD" end
	if decision.risk == "mq2_no_collect" then return "SUBMIT · MQ2 OUT" end
	if decision.risk == "no_paint" then return "SUBMIT · LAST OUT" end
	if decision.collected then return "SUBMIT · BLIT OUT" end
	return "SUBMIT · DUAL OUT"
end

--- Pure HMD observer contract (offline ≠ headset proof).
function vrmod.utils.SubmitLaw_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_dual_out = true,
		checklist = "G19 · IDLE · no submit decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if decision.risk == "eng_in" then
		e.verdict = "expect_eng_in_fail"
		e.expect_dual_out = false
		e.checklist = "G19 · ENG IN FORBIDDEN · must not ship"
		e.pass_line = "Never Submit eng RT id"
		e.fail_line = "HMD flash / wrong texture from eng IN submit"
		return e
	end
	if decision.risk == "virgin_out" then
		e.verdict = "expect_virgin_fail"
		e.expect_dual_out = false
		e.checklist = "G19 · VIRGIN OUT FORBIDDEN · blit first"
		e.pass_line = "OUT filled before Submit"
		e.fail_line = "Black virgin flash both eyes"
		return e
	end
	if not decision.allow_submit then
		e.verdict = "expect_hold"
		e.expect_dual_out = false
		e.checklist = "G19 · HOLD · no submit this frame"
		e.pass_line = "No thrash submit when inactive"
		e.fail_line = "Submit while session dead"
		return e
	end
	e.verdict = "expect_dual_out"
	e.expect_dual_out = true
	e.checklist = string.format(
		"G19 · DUAL OUT RGBA8 · mq%d · %s",
		tonumber(decision.mat_queue_mode) or 1,
		tostring(decision.reason or "ok")
	)
	e.pass_line = "Both eyes dual OUT; no eng IN; no virgin flash"
	e.fail_line = "eng IN submit or virgin OUT before blit"
	return e
end

function vrmod.utils.SubmitLaw_IsEngInRisk(decision)
	if type(decision) ~= "table" then return true end
	return decision.risk == "eng_in"
end
