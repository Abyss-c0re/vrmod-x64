-- Avatar open must not hitch the stereo frame (sync Precache + list validate).
-- Cube way: open menu now, spawn a ready mesh, load/validate later (1/tick).
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

function vrmod.utils.AvatarLoadLaw_MaxValidatePerTick()
	return 1
end

function vrmod.utils.AvatarLoadLaw_AllowSyncListFilter()
	return false
end

function vrmod.utils.AvatarLoadLaw_AllowSyncPrecacheOnOpen()
	return false
end

function vrmod.utils.AvatarLoadLaw_AllowSyncValidateOnOpen()
	return false
end

function vrmod.utils.AvatarLoadLaw_PlaceholderModel()
	return "models/player/kleiner.mdl"
end

function vrmod.utils.AvatarLoadLaw_DeferTwinSpawn()
	return true
end

function vrmod.utils.AvatarLoadLaw_DeferIkOnOpen()
	return true
end

--- Pure: what the open/load path may do this frame.
--- opts:
---   phase              "menu_open"|"twin_open"|"set_model"|"list"|"validate_tick"
---   model_loaded       bool
---   sync_precache      bool
---   sync_validate_all  bool
---   validate_budget    number
---   defer_twin         bool
function vrmod.utils.AvatarLoadLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local phase = tostring(opts.phase or "menu_open")
	local budget = tonumber(opts.validate_budget)
	if not budget or budget < 1 then
		budget = vrmod.utils.AvatarLoadLaw_MaxValidatePerTick()
	end
	if budget > 4 then budget = 4 end
	budget = math.floor(budget)
	local d = {
		valid = true,
		path_ok = true,
		phase = phase,
		risk = "none",
		open_now = true,
		list_now = true,
		validate_now = false,
		precache_now = false,
		spawn_placeholder = false,
		defer_twin = vrmod.utils.AvatarLoadLaw_DeferTwinSpawn(),
		defer_ik = vrmod.utils.AvatarLoadLaw_DeferIkOnOpen(),
		validate_budget = budget,
		placeholder = vrmod.utils.AvatarLoadLaw_PlaceholderModel(),
		reason = "async_open",
	}
	if opts.sync_validate_all or (phase == "list" and opts.sync_validate_all ~= false
		and vrmod.utils.AvatarLoadLaw_AllowSyncListFilter()) then
		d.path_ok = false
		d.risk = "sync_list"
		d.reason = "sync_validate_all"
		return d
	end
	if (phase == "menu_open" or phase == "twin_open") and opts.sync_precache then
		d.path_ok = false
		d.risk = "sync_precache"
		d.reason = "sync_precache_on_open"
		return d
	end
	if phase == "twin_open" or phase == "set_model" then
		if opts.model_loaded then
			d.precache_now = false
			d.spawn_placeholder = false
			d.reason = "model_ready"
			return d
		end
		d.spawn_placeholder = true
		d.precache_now = false
		d.reason = "defer_precache"
		return d
	end
	if phase == "validate_tick" then
		d.validate_now = true
		d.reason = "budget_tick"
		return d
	end
	d.reason = "menu_open_async"
	return d
end

function vrmod.utils.AvatarLoadLaw_StatusLabel(decision)
	if type(decision) ~= "table" then return "AVATAR · IDLE" end
	if decision.risk == "sync_list" then return "AVATAR · SYNC LIST FREEZE" end
	if decision.risk == "sync_precache" then return "AVATAR · SYNC PRECACHE FREEZE" end
	if decision.spawn_placeholder then return "AVATAR · PLACEHOLDER" end
	if decision.reason == "model_ready" then return "AVATAR · READY" end
	if decision.path_ok then return "AVATAR · ASYNC" end
	return "AVATAR · HOLD"
end

function vrmod.utils.AvatarLoadLaw_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_no_hitch = true,
		checklist = "G48 · IDLE · no avatar load decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if decision.risk == "sync_list" or decision.risk == "sync_precache" then
		e.verdict = "expect_freeze"
		e.expect_no_hitch = false
		e.checklist = "G48 · FREEZE · sync model work on open"
		e.pass_line = "Must not ship — menu open hitch"
		e.fail_line = "Avatar open freezes the game"
		return e
	end
	e.verdict = "expect_async"
	e.expect_no_hitch = true
	e.checklist = "G48 · ASYNC · menu now · load later"
	e.pass_line = "Avatar menu opens; twin/models load next frames"
	e.fail_line = "Stereo hitch / freeze on Avatar open"
	return e
end

function vrmod.utils.AvatarLoadLaw_IsFreezeRisk(decision)
	return type(decision) == "table" and (decision.risk == "sync_list" or decision.risk == "sync_precache")
end
