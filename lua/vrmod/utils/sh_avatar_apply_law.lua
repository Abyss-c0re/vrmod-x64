-- Avatar SAVE/APPLY must keep the twin-validated PM.
-- Probe SetModel + immediate LookupBone is pending, not incompatible.
-- Caching false / reverting to lastGood mid ReloadCharacterSystem =
-- old model, no bones, until respawn.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

function vrmod.utils.AvatarApplyLaw_ApplyWindowSeconds()
	return 2.5
end

function vrmod.utils.AvatarApplyLaw_AllowProbeFalseCache()
	return false
end

function vrmod.utils.AvatarApplyLaw_AllowRevertOnPending()
	return false
end

--- Pure: may we revert / cache-false / mark incompatible this apply?
--- opts:
---   phase        "apply"|"validate_probe"|"reload_local"|"sync_all"|"character_init"
---   twin_ok      bool   -- ValidatePlayerModelOnEnt on the live twin
---   trusted      bool   -- apply window or MarkPlayerModelValid
---   probe_ok     true|false|nil
---   live_path    string
---   last_good    string
---   apply_path   string
---   apply_age    number seconds since apply (optional)
---   from_net     bool   -- pmchange net/poll during an in-flight apply
function vrmod.utils.AvatarApplyLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local phase = tostring(opts.phase or "reload_local")
	local live = tostring(opts.live_path or opts.apply_path or "")
	local lastGood = tostring(opts.last_good or "")
	local applyPath = tostring(opts.apply_path or "")
	local twinOk = opts.twin_ok == true
	local trusted = opts.trusted == true or twinOk
	local applyAge = tonumber(opts.apply_age)
	local window = vrmod.utils.AvatarApplyLaw_ApplyWindowSeconds()
	if applyAge ~= nil and applyAge >= 0 and applyAge < window then
		trusted = true
	end
	if applyPath ~= "" and live ~= "" and applyPath == live then
		-- same path we just applied — treat as trusted even if the clock slipped
		if opts.trusted ~= false and (twinOk or opts.trusted == true or applyAge == nil) then
			-- keep caller trusted flag; do not force
		end
	end
	local probeOk = opts.probe_ok
	local d = {
		valid = true,
		path_ok = true,
		revert = false,
		cache_false = false,
		treat_pending = false,
		keep_live = true,
		update_last_good = false,
		mark_incompatible = false,
		skip_reload = false,
		pin_apply_path = false,
		risk = "none",
		reason = "idle",
		phase = phase,
	}

	if phase == "apply" then
		if twinOk then
			d.update_last_good = true
			d.pin_apply_path = true
			d.reason = "twin_validated"
			return d
		end
		if probeOk == false then
			d.path_ok = false
			d.keep_live = false
			d.reason = "twin_blocked"
			return d
		end
		d.treat_pending = true
		d.reason = "apply_pending"
		return d
	end

	if phase == "validate_probe" then
		if trusted then
			d.treat_pending = probeOk ~= true
			d.cache_false = false
			d.update_last_good = true
			d.reason = "trusted_skip_probe"
			return d
		end
		if probeOk == true then
			d.update_last_good = true
			d.reason = "probe_ok"
			return d
		end
		d.treat_pending = true
		d.cache_false = vrmod.utils.AvatarApplyLaw_AllowProbeFalseCache()
		d.reason = "probe_pending"
		if d.cache_false then
			d.risk = "false_cache"
		end
		return d
	end

	if phase == "reload_local" or phase == "sync_all" then
		if trusted then
			d.keep_live = true
			d.revert = false
			d.update_last_good = true
			d.pin_apply_path = true
			d.skip_reload = opts.from_net == true
			d.reason = "apply_window"
			return d
		end
		if probeOk == nil then
			d.keep_live = true
			d.revert = vrmod.utils.AvatarApplyLaw_AllowRevertOnPending()
			d.treat_pending = true
			d.reason = "validate_pending"
			if d.revert then d.risk = "apply_revert" end
			return d
		end
		if probeOk == false then
			d.keep_live = false
			d.revert = lastGood ~= "" and lastGood ~= live
			d.reason = "confirmed_incompatible"
			if d.revert then d.risk = "apply_revert" end
			return d
		end
		d.keep_live = true
		d.update_last_good = true
		d.reason = "validated"
		return d
	end

	if phase == "character_init" then
		if trusted then
			d.mark_incompatible = false
			d.pin_apply_path = true
			d.update_last_good = true
			if probeOk ~= true then
				d.treat_pending = true
				d.reason = "init_retry"
			else
				d.reason = "init_trusted"
			end
			return d
		end
		if probeOk == false then
			d.mark_incompatible = true
			d.reason = "init_incompatible"
			return d
		end
		d.update_last_good = probeOk == true
		d.reason = "init_ok"
		return d
	end

	return d
end

function vrmod.utils.AvatarApplyLaw_StatusLabel(decision)
	if type(decision) ~= "table" then return "APPLY · IDLE" end
	if decision.risk == "apply_revert" then return "APPLY · REVERT BONES" end
	if decision.risk == "false_cache" then return "APPLY · FALSE CACHE" end
	if decision.reason == "apply_window" or decision.reason == "twin_validated" then
		return "APPLY · HOLD PATH"
	end
	if decision.treat_pending then return "APPLY · PENDING" end
	if decision.revert then return "APPLY · REVERT BONES" end
	return "APPLY · KEEP"
end

function vrmod.utils.AvatarApplyLaw_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_keep_applied = true,
		checklist = "G52 · IDLE · no apply decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if decision.risk == "apply_revert" or decision.revert then
		e.verdict = "expect_old_no_bones"
		e.expect_keep_applied = false
		e.checklist = "G52 · REVERT · lastGood stomps twin-validated PM"
		e.pass_line = "Must not ship — apply flashes then old T-pose"
		e.fail_line = "Player turns into old model without bones until respawn"
		return e
	end
	if decision.risk == "false_cache" then
		e.verdict = "expect_false_cache"
		e.expect_keep_applied = false
		e.checklist = "G52 · FALSE CACHE · probe LookupBone after SetModel"
		e.pass_line = "Must not ship — 120s blocked after apply"
		e.fail_line = "Probe cached missing bones on a valid PM"
		return e
	end
	e.verdict = "expect_applied"
	e.expect_keep_applied = true
	e.checklist = "G52 · HOLD · twin-validated path stays"
	e.pass_line = "Apply keeps the new PM and rebuilds IK"
	e.fail_line = "Model snaps back / bones empty until respawn"
	return e
end

function vrmod.utils.AvatarApplyLaw_IsRevertRisk(decision)
	if type(decision) ~= "table" then return false end
	return decision.revert == true or decision.risk == "apply_revert" or decision.risk == "false_cache"
end
