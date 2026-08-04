-- G27: GMod x64 engine blacklist law (pure, offline-tested).
-- Watchlist W2 / Cube standard: never call Blocked_ConCommands.
-- Known spam: "Command is blocked!" on r_shadowrendertotexture,
-- mat_reduceparticles, viewmodel_fov. Soft-skip only — never thrash Set*.
-- Separate class: lifecycle bans (mat_queue_mode, gmod_mcore_test) — CThread death.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

--- Hard engine Blocked_ConCommands (Lua Set/RCC spam; cannot change mid-session).
local BLOCKED = {
	r_shadowrendertotexture = true,
	mat_reduceparticles = true,
	viewmodel_fov = true,
}

--- Worker / thread lifecycle — write restarts CThread (pain #3 adjacent).
local LIFECYCLE = {
	mat_queue_mode = true,
	gmod_mcore_test = true,
}

function vrmod.utils.EngineBlacklist_NormalizeName(name)
	name = tostring(name or "")
	name = name:gsub("^%s+", ""):gsub("%s+$", "")
	return string.lower(name)
end

function vrmod.utils.EngineBlacklist_IsBlocked(name)
	name = vrmod.utils.EngineBlacklist_NormalizeName(name)
	return BLOCKED[name] == true
end

function vrmod.utils.EngineBlacklist_IsLifecycleBan(name)
	name = vrmod.utils.EngineBlacklist_NormalizeName(name)
	return LIFECYCLE[name] == true
end

--- Product must never SetInt/SetString/RunConsoleCommand these from VR Lua.
function vrmod.utils.EngineBlacklist_AllowWrite(name)
	name = vrmod.utils.EngineBlacklist_NormalizeName(name)
	if name == "" then return false end
	if BLOCKED[name] then return false end
	if LIFECYCLE[name] then return false end
	return true
end

--- RunConsoleCommand path is especially noisy for blocked names.
function vrmod.utils.EngineBlacklist_AllowRunConsoleCommand(name)
	return vrmod.utils.EngineBlacklist_AllowWrite(name)
end

--- Pure filter: drop blocked/lifecycle keys from a name→value map (performance pins).
function vrmod.utils.EngineBlacklist_FilterMap(map)
	map = type(map) == "table" and map or {}
	local out = {}
	local dropped = {}
	for k, v in pairs(map) do
		if vrmod.utils.EngineBlacklist_AllowWrite(k) then
			out[k] = v
		else
			dropped[#dropped + 1] = vrmod.utils.EngineBlacklist_NormalizeName(k)
		end
	end
	return out, dropped
end

--- List of known blocked names (copy for docs/tests).
function vrmod.utils.EngineBlacklist_BlockedNames()
	local t = {}
	for k in pairs(BLOCKED) do t[#t + 1] = k end
	table.sort(t)
	return t
end

function vrmod.utils.EngineBlacklist_LifecycleNames()
	local t = {}
	for k in pairs(LIFECYCLE) do t[#t + 1] = k end
	table.sort(t)
	return t
end

--- Pure decision snapshot.
--- opts:
---   attempted table|nil   list of convar names product tried to write
---   performance_map table|nil  PERFORMANCE_CONVARS-like
---   vr_active bool|nil
function vrmod.utils.EngineBlacklist_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local attempted = type(opts.attempted) == "table" and opts.attempted or {}
	local bad = {}
	local lifecycle_hits = {}
	for i = 1, #attempted do
		local n = vrmod.utils.EngineBlacklist_NormalizeName(attempted[i])
		if BLOCKED[n] then bad[#bad + 1] = n end
		if LIFECYCLE[n] then lifecycle_hits[#lifecycle_hits + 1] = n end
	end
	local perf = opts.performance_map
	local filtered, dropped = nil, {}
	if type(perf) == "table" then
		filtered, dropped = vrmod.utils.EngineBlacklist_FilterMap(perf)
	end
	local d = {
		valid = true,
		vr_active = opts.vr_active and true or false,
		blocked_hits = bad,
		lifecycle_hits = lifecycle_hits,
		perf_dropped = dropped,
		risk = "none", -- none | blocked_spam | lifecycle_write | dirty_perf
		reason = "ok",
		path_ok = true,
	}
	if #lifecycle_hits > 0 then
		d.risk = "lifecycle_write"
		d.reason = "lifecycle_cvar_write"
		d.path_ok = false
	elseif #bad > 0 then
		d.risk = "blocked_spam"
		d.reason = "engine_blocked_convar"
		d.path_ok = false
	elseif dropped and #dropped > 0 then
		d.risk = "dirty_perf"
		d.reason = "performance_map_had_blocked"
		d.path_ok = false
	else
		d.reason = "clean_no_blocked_writes"
		d.path_ok = true
	end
	d.filtered_map = filtered
	return d
end

function vrmod.utils.EngineBlacklist_StatusLabel(decision)
	if type(decision) ~= "table" then return "ENG · IDLE" end
	if decision.risk == "lifecycle_write" then return "ENG · LIFECYCLE BAN" end
	if decision.risk == "blocked_spam" then return "ENG · BLOCKED SPAM" end
	if decision.risk == "dirty_perf" then return "ENG · DIRTY PERF" end
	if decision.path_ok then return "ENG · CLEAN" end
	return "ENG · HOLD"
end

--- Pure observer contract (offline ≠ console walk proof).
function vrmod.utils.EngineBlacklist_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_no_blocked = true,
		checklist = "G27 · IDLE · no engine blacklist decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if not decision.path_ok then
		e.verdict = "expect_blocked_fail"
		e.expect_no_blocked = false
		e.checklist = "G27 · FAIL · " .. tostring(decision.reason or decision.risk)
		e.pass_line = "Must not Set/RCC blocked or lifecycle convars"
		e.fail_line = "Console 'Command is blocked!' or CThread thrash"
		return e
	end
	e.verdict = "expect_clean"
	e.expect_no_blocked = true
	e.checklist = "G27 · CLEAN · no blocked/lifecycle writes · soft-skip only"
	e.pass_line = "No Command is blocked! spam; mat_queue untouched by VR"
	e.fail_line = "viewmodel_fov / r_shadowrendertotexture / mat_reduceparticles write"
	return e
end

function vrmod.utils.EngineBlacklist_IsWriteRisk(decision)
	if type(decision) ~= "table" then return true end
	return not decision.path_ok
end
