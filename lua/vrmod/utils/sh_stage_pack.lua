-- G03: Cube STAGE / cal continuity pack — pure parse + hint (offline-tested).
-- Launcher writes garrysmod/data/vrmod/cube_stage_pack.txt; GMod may read after claim.
-- Law: do not auto-apply head/origin/scale from this pack without a careful, tested path.
-- This module only parses + builds toast copy. No convar / origin mutation.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

local function trim(s)
	s = tostring(s or "")
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Normalize ref space token (STAGE | LOCAL | VIEW | other upper).
function vrmod.utils.StagePack_NormalizeSpace(raw)
	local s = string.upper(trim(raw))
	if s == "STAGE" or s == "LOCAL" or s == "VIEW" then return s end
	if s == "" then return "LOCAL" end
	return s
end

--- True when pack is usable for space preference (STAGE or LOCAL). head_ok optional.
function vrmod.utils.StagePack_IsUsable(pack)
	if type(pack) ~= "table" or not pack.valid then return false end
	local sp = vrmod.utils.StagePack_NormalizeSpace(pack.ref_space)
	return sp == "STAGE" or sp == "LOCAL"
end

--- Parse key=value body from cube_stage_pack.txt. Pure — no file I/O.
--- Returns snapshot table or nil if invalid.
function vrmod.utils.StagePack_Parse(body)
	if type(body) ~= "string" or body == "" then return nil end
	local out = {
		version = 1,
		ref_space = "LOCAL",
		head_x = 0,
		head_y = 0,
		head_z = 0,
		head_ok = false,
		viewscale = 1,
		scalefactor = 1,
		supersample = 1,
		map = "",
		source = "cube_webui",
		ts = 0,
		valid = false,
	}
	local gotSpace = false
	for line in string.gmatch(body, "[^\r\n]+") do
		line = trim(line)
		if line ~= "" and line:sub(1, 1) ~= "#" and line:sub(1, 1) ~= ";" then
			local k, v = line:match("^([^=]+)=(.*)$")
			if k then
				k = trim(k)
				v = trim(v)
				if k == "v" or k == "version" then
					out.version = tonumber(v) or 1
				elseif k == "ref_space" or k == "space" then
					out.ref_space = vrmod.utils.StagePack_NormalizeSpace(v)
					gotSpace = out.ref_space ~= ""
				elseif k == "head_x_m" or k == "head_x" then
					out.head_x = tonumber(v) or 0
				elseif k == "head_y_m" or k == "head_y" then
					out.head_y = tonumber(v) or 0
				elseif k == "head_z_m" or k == "head_z" then
					out.head_z = tonumber(v) or 0
				elseif k == "head_ok" then
					out.head_ok = (v == "1" or v == "true")
				elseif k == "viewscale" then
					out.viewscale = tonumber(v) or 1
				elseif k == "scalefactor" then
					out.scalefactor = tonumber(v) or 1
				elseif k == "supersample" then
					out.supersample = tonumber(v) or 1
				elseif k == "map" then
					out.map = v
				elseif k == "source" then
					out.source = (v ~= "" and v) or "cube_webui"
				elseif k == "ts" then
					out.ts = tonumber(v) or 0
				end
			end
		end
	end
	if (out.version or 0) <= 0 then out.version = 1 end
	-- Clamp scales (match launcher sanity)
	if out.viewscale < 0.05 then out.viewscale = 1 end
	if out.viewscale > 4 then out.viewscale = 4 end
	if out.scalefactor < 0.05 then out.scalefactor = 1 end
	if out.scalefactor > 4 then out.scalefactor = 4 end
	if out.supersample < 0.5 then out.supersample = 0.5 end
	if out.supersample > 3 then out.supersample = 3 end
	-- Extreme head Y → clear head_ok (space pack still valid)
	if out.head_ok and (out.head_y < 0.2 or out.head_y > 2.8) then
		out.head_ok = false
	end
	out.valid = gotSpace
	if not out.valid then return nil end
	return out
end

--- Short toast / log line for continuity awareness. No mutation advice.
--- Returns string or nil if pack not usable.
function vrmod.utils.StagePack_ToastHint(pack)
	if not vrmod.utils.StagePack_IsUsable(pack) then return nil end
	local sp = vrmod.utils.StagePack_NormalizeSpace(pack.ref_space)
	if pack.head_ok and tonumber(pack.head_y) then
		return string.format("Cube pack · %s · head Y %.2fm · height apply deferred",
			sp, tonumber(pack.head_y))
	end
	return string.format("Cube pack · %s · height apply deferred", sp)
end

--- G03 apply gate (pure) — decide if height/origin from pack could ever be applied.
--- Law: default allow_apply=false so product never auto-jumps; this only classifies.
---
--- pack: StagePack_Parse result
--- opts:
---   measured_head_y_m  number|nil  live HMD Y in tracking meters (OpenXR Y-up)
---   allow_apply        bool        master switch (default false)
---   close_m            number      already-close band (default 0.05)
---   max_delta_m        number      reject jumps larger than this (default 0.35)
---
--- Returns decision table:
---   action  "none" | "hint_only" | "apply_scale" | "apply_seated"
---   reason  stable code string
---   safe    bool — within band for a future careful apply
---   delta_y number|nil
function vrmod.utils.StagePack_ApplyDecision(pack, opts)
	opts = type(opts) == "table" and opts or {}
	local allow = opts.allow_apply and true or false
	local closeM = tonumber(opts.close_m) or 0.05
	local maxD = tonumber(opts.max_delta_m) or 0.35
	if closeM < 0.01 then closeM = 0.05 end
	if maxD < closeM then maxD = 0.35 end

	local dec = {
		action = "none",
		reason = "unusable",
		safe = false,
		delta_y = nil,
		allow_apply = allow,
	}

	if not vrmod.utils.StagePack_IsUsable(pack) then
		return dec
	end
	if not pack.head_ok then
		dec.reason = "no_head"
		return dec
	end

	local packY = tonumber(pack.head_y)
	if not packY then
		dec.reason = "no_head"
		return dec
	end

	local measured = tonumber(opts.measured_head_y_m)
	if not measured then
		-- Space pack known; height needs live HMD before any apply
		dec.action = "hint_only"
		dec.reason = "no_measured"
		dec.safe = false
		return dec
	end

	local delta = measured - packY
	dec.delta_y = delta
	local ad = math.abs(delta)
	if ad <= closeM then
		dec.action = "none"
		dec.reason = "already_close"
		dec.safe = true
		return dec
	end
	if ad > maxD then
		dec.action = "none"
		dec.reason = "too_far"
		dec.safe = false
		return dec
	end

	-- Eligible band: only apply when master switch on (product keeps it off)
	dec.safe = true
	if allow then
		-- Prefer scale path over seated origin rewrite (less dual-truth risk)
		dec.action = "apply_scale"
		dec.reason = "eligible"
	else
		dec.action = "hint_only"
		dec.reason = "eligible_deferred"
	end
	return dec
end

--- Toast line from ApplyDecision (pure). Nil if nothing useful to say.
function vrmod.utils.StagePack_ApplyToast(decision)
	if type(decision) ~= "table" then return nil end
	local r = tostring(decision.reason or "")
	if r == "already_close" then
		return "Cube pack · height already close · no apply"
	end
	if r == "too_far" then
		return "Cube pack · height delta too large · no auto-apply"
	end
	if r == "no_head" then
		return "Cube pack · space only · no head sample"
	end
	if r == "no_measured" then
		return "Cube pack · wait for HMD pose before height apply"
	end
	if r == "eligible_deferred" then
		local d = tonumber(decision.delta_y)
		if d then
			return string.format("Cube pack · ΔY %.2fm · apply deferred (safe band)", d)
		end
		return "Cube pack · apply deferred (safe band)"
	end
	if r == "eligible" and decision.action == "apply_scale" then
		return "Cube pack · scale apply allowed"
	end
	if r == "unusable" then
		return nil
	end
	return nil
end

--- G03 pure apply *plan* (preview numbers only — never mutates convars).
--- Builds seated-offset continuity so live HMD Y can match Cube shell pack head_y.
---
--- pack: StagePack_Parse result
--- decision: StagePack_ApplyDecision result
--- opts:
---   world_scale           number  g_VR.scale (Source units per meter), default 1
---   current_seatedoffset  number  current vrmod_seatedoffset, default 0
---   max_seated_abs        number  clamp |new offset| (default 40 Source units)
---   allow_apply           bool    if true, plan.do_apply may become true
---
--- Returns plan table with preview + do_apply=false unless allow_apply and eligible.
function vrmod.utils.StagePack_ComputeApplyPlan(pack, decision, opts)
	opts = type(opts) == "table" and opts or {}
	local plan = {
		valid = false,
		do_apply = false,
		method = "none",
		reason = "no_decision",
		seated_delta_source = 0,
		seated_new = 0,
		viewscale = nil,
		scalefactor = nil,
		delta_y_m = nil,
	}
	if type(decision) ~= "table" then return plan end
	plan.reason = tostring(decision.reason or "none")
	plan.delta_y_m = tonumber(decision.delta_y)
	plan.valid = true

	local allow = opts.allow_apply and true or false
	if decision.allow_apply ~= nil then
		-- Prefer decision's allow flag when present
		allow = decision.allow_apply and true or false
	end

	local scale = tonumber(opts.world_scale) or 1
	if scale < 1 then scale = 1 end
	local curSeat = tonumber(opts.current_seatedoffset) or 0
	local maxAbs = tonumber(opts.max_seated_abs) or 40
	if maxAbs < 5 then maxAbs = 40 end

	-- Continuity scales from pack (informational; height uses seated)
	if type(pack) == "table" then
		plan.viewscale = tonumber(pack.viewscale)
		plan.scalefactor = tonumber(pack.scalefactor)
	end

	local r = plan.reason
	if r == "already_close" or r == "too_far" or r == "no_head" or r == "no_measured" or r == "unusable" then
		plan.method = "none"
		plan.do_apply = false
		return plan
	end

	-- Eligible band: prefer seated offset (less dual-truth than rewriting world scale)
	local dY = plan.delta_y_m
	if not dY then
		plan.method = "none"
		plan.reason = "no_delta"
		return plan
	end

	-- Live is above pack when delta>0; lift origin by (pack-measured) so head matches pack
	local deltaSource = -dY * scale
	-- Clamp single-step seated change
	if deltaSource > maxAbs then deltaSource = maxAbs end
	if deltaSource < -maxAbs then deltaSource = -maxAbs end
	local newSeat = curSeat + deltaSource
	if newSeat > maxAbs then newSeat = maxAbs end
	if newSeat < -maxAbs then newSeat = -maxAbs end

	plan.method = "seated_offset"
	plan.seated_delta_source = deltaSource
	plan.seated_new = newSeat
	plan.do_apply = allow and (decision.safe and true or false) and true or false
	if allow and plan.do_apply then
		plan.reason = "eligible"
	elseif decision.safe then
		plan.reason = "eligible_deferred"
		plan.do_apply = false
	end
	return plan
end

--- Toast for apply plan preview (pure).
function vrmod.utils.StagePack_PlanToast(plan)
	if type(plan) ~= "table" or not plan.valid then return nil end
	if plan.method == "seated_offset" then
		local d = tonumber(plan.seated_delta_source) or 0
		if plan.do_apply then
			return string.format("Cube pack · seated Δ %.1f · apply armed", d)
		end
		return string.format("Cube pack · seated Δ %.1f preview · apply deferred", d)
	end
	return vrmod.utils.StagePack_ApplyToast({
		reason = plan.reason,
		action = plan.do_apply and "apply_scale" or "hint_only",
		delta_y = plan.delta_y_m,
	})
end

--- Pure mutation list from plan. Empty unless plan.do_apply (executor stays separate).
--- Returns array of { convar=, value= } — caller may apply; this module never sets them.
function vrmod.utils.StagePack_MutationsFromPlan(plan)
	local out = {}
	if type(plan) ~= "table" or not plan.do_apply then return out end
	if plan.method == "seated_offset" and tonumber(plan.seated_new) then
		out[#out + 1] = {
			convar = "vrmod_seatedoffset",
			value = tonumber(plan.seated_new),
		}
	end
	return out
end

--- G03 careful apply allow gate (pure). Product default OFF.
--- flags:
---   convar_on     bool  vrmod_stage_apply GetBool
---   file_enable   bool  DATA vrmod/stage_apply_enable.txt exists
---   force         bool  test override
function vrmod.utils.StagePack_AllowApplyFromFlags(flags)
	flags = type(flags) == "table" and flags or {}
	if flags.force then return true end
	if flags.convar_on then return true end
	if flags.file_enable then return true end
	return false
end

--- True when executor may run mutations (plan armed + allow).
function vrmod.utils.StagePack_ShouldExecutePlan(plan, allowApply)
	if not allowApply then return false end
	if type(plan) ~= "table" or not plan.valid then return false end
	if not plan.do_apply then return false end
	if plan.method == "none" or plan.method == nil then return false end
	return true
end

--- Pure executor: apply mutation list via injectable applier(convar, value) → ok,err.
--- Never calls engine itself — openxr_launch supplies SetFloat wrapper.
--- Returns { applied=n, skipped=n, errors={...}, ok=bool }
function vrmod.utils.StagePack_ExecuteMutations(mutations, applier)
	local res = { applied = 0, skipped = 0, errors = {}, ok = true }
	if type(mutations) ~= "table" or #mutations == 0 then
		res.skipped = 0
		return res
	end
	if type(applier) ~= "function" then
		res.ok = false
		res.errors[#res.errors + 1] = "no_applier"
		return res
	end
	for _, m in ipairs(mutations) do
		if type(m) == "table" and m.convar and m.value ~= nil then
			local ok, err = applier(tostring(m.convar), tonumber(m.value) or m.value)
			if ok then
				res.applied = res.applied + 1
			else
				res.ok = false
				res.errors[#res.errors + 1] = tostring(err or m.convar)
			end
		else
			res.skipped = res.skipped + 1
		end
	end
	return res
end

--- Toast after execute attempt (pure).
function vrmod.utils.StagePack_ExecuteToast(execRes, plan)
	if type(execRes) ~= "table" then return nil end
	if execRes.applied and execRes.applied > 0 and execRes.ok then
		local d = plan and tonumber(plan.seated_delta_source)
		if d then
			return string.format("Cube pack · applied seated Δ %.1f", d)
		end
		return "Cube pack · height apply done"
	end
	if execRes.errors and #execRes.errors > 0 then
		return "Cube pack · apply failed · " .. tostring(execRes.errors[1])
	end
	return nil
end

-- ── G03 HMD stage-apply expect (pure observer contract) ──────────────────────
-- Offline tokens for headset height continuity smoke. Never claims HMD passed.
-- Does not mutate seated offset.

--- Pure HMD observer expectation from ApplyDecision + optional plan/exec.
--- decision: StagePack_ApplyDecision
--- plan: StagePack_ComputeApplyPlan or nil
--- execRes: StagePack_ExecuteMutations result or nil
--- Returns:
---   verdict     expect_deferred | expect_applied | expect_close | expect_blocked | idle
---   height_risk none | jump | blocked | unknown
---   expect_no_jump bool  true when product should not have changed height
---   checklist / pass_line / fail_line
function vrmod.utils.StagePack_HmdExpect(decision, plan, execRes)
	local e = {
		verdict = "idle",
		height_risk = "unknown",
		expect_no_jump = true,
		checklist = "G03 · IDLE · no stage pack decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" then return e end
	local r = tostring(decision.reason or "")

	if execRes and type(execRes) == "table" and execRes.applied and execRes.applied > 0 and execRes.ok then
		local d = plan and tonumber(plan.seated_delta_source)
		e.verdict = "expect_applied"
		e.height_risk = "none"
		e.expect_no_jump = false -- intentional small seated step
		e.checklist = string.format("G03 · APPLIED · seated Δ %s · opt-in only",
			d and string.format("%.1f", d) or "?")
		e.pass_line = "Head height continuous with Cube pack; no multi-meter pop"
		e.fail_line = "Sudden floor jump / ceiling crush / dual height truth"
		return e
	end

	if r == "already_close" then
		e.verdict = "expect_close"
		e.height_risk = "none"
		e.expect_no_jump = true
		e.checklist = "G03 · CLOSE · no apply needed"
		e.pass_line = "Standing height matches pack; no seated thrash"
		e.fail_line = "Unnecessary seated rewrite"
		return e
	end

	if r == "too_far" or r == "unusable" or r == "no_head" then
		e.verdict = "expect_blocked"
		e.height_risk = "blocked"
		e.expect_no_jump = true
		e.checklist = "G03 · BLOCKED · " .. r
		e.pass_line = "No auto height apply outside safe band"
		e.fail_line = "Forced apply despite too_far/unusable"
		return e
	end

	if r == "no_measured" then
		e.verdict = "expect_deferred"
		e.height_risk = "unknown"
		e.expect_no_jump = true
		e.checklist = "G03 · WAIT HMD · no measured pose yet"
		e.pass_line = "Toast waits for HMD; no blind apply"
		e.fail_line = "Apply before tracking valid"
		return e
	end

	if plan and type(plan) == "table" and plan.do_apply then
		e.verdict = "expect_applied"
		e.height_risk = "none"
		e.expect_no_jump = false
		e.checklist = "G03 · ARMED · seated apply (opt-in)"
		e.pass_line = "Opt-in apply lands soft continuity step"
		e.fail_line = "Ear-pop height jump or wrong sign seated"
		return e
	end

	if r == "eligible_deferred" or r == "eligible" then
		e.verdict = "expect_deferred"
		e.height_risk = "none"
		e.expect_no_jump = true
		local d = tonumber(decision.delta_y)
		e.checklist = string.format("G03 · DEFERRED · ΔY %s · default no auto",
			d and string.format("%.2fm", d) or "?")
		e.pass_line = "Preview toast only; height unchanged without opt-in"
		e.fail_line = "Silent auto seatedoffset without vrmod_stage_apply"
		return e
	end

	e.verdict = "idle"
	e.height_risk = "unknown"
	e.checklist = "G03 · HOLD · reason=" .. r
	e.pass_line = "Observe only"
	e.fail_line = "Unexpected height thrash"
	return e
end

--- True when HMD observer should treat path as dangerous height jump risk.
function vrmod.utils.StagePack_HeightJumpRiskIsBad(expect)
	if type(expect) ~= "table" then return true end
	return expect.height_risk == "jump"
end
