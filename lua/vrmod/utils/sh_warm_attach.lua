-- G04: warm process map-attach protocol (pure parse + decide — offline-tested).
-- Cube writes garrysmod/data/vrmod/cube_warm.txt when process already up.
-- Law: allow_changelevel defaults false — never auto changelevel without proven path.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

local function trim(s)
	s = tostring(s or "")
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Normalize map token: lower, strip maps/, strip .bsp
function vrmod.utils.WarmAttach_NormalizeMap(raw)
	local s = string.lower(trim(raw)):gsub("\\", "/")
	s = s:gsub("^maps/", "")
	s = s:gsub("%.bsp$", "")
	return trim(s)
end

--- Pure parse of cube_warm.txt body. Returns table or nil.
function vrmod.utils.WarmAttach_Parse(body)
	if type(body) ~= "string" or body == "" then return nil end
	local out = {
		version = 1,
		action = "warm_request",
		reason = "",
		map = "",
		source = "cube_webui",
		ts = 0,
		valid = false,
	}
	local got = false
	for line in string.gmatch(body, "[^\r\n]+") do
		line = trim(line)
		if line ~= "" and line:sub(1, 1) ~= "#" and line:sub(1, 1) ~= ";" then
			local k, v = line:match("^([^=]+)=(.*)$")
			if k then
				k = trim(k)
				v = trim(v)
				if k == "v" or k == "version" then
					out.version = tonumber(v) or 1
				elseif k == "action" then
					out.action = (v ~= "" and v) or "warm_request"
					got = true
				elseif k == "reason" then
					out.reason = v
				elseif k == "map" then
					out.map = v
					got = true
				elseif k == "source" then
					out.source = (v ~= "" and v) or "cube_webui"
				elseif k == "ts" then
					out.ts = tonumber(v) or 0
				end
			end
		end
	end
	if (out.version or 0) <= 0 then out.version = 1 end
	out.valid = got
	if not out.valid then return nil end
	return out
end

--- Pure attach decision.
--- req: WarmAttach_Parse result
--- opts:
---   current_map       string|nil  game.GetMap()
---   allow_changelevel bool        master switch (default false)
function vrmod.utils.WarmAttach_Decide(req, opts)
	opts = type(opts) == "table" and opts or {}
	local allow = opts.allow_changelevel and true or false
	local d = {
		action = "idle",
		reason = "none",
		request_map = "",
		current_map = "",
		would_changelevel = false,
		valid = true,
	}
	if type(req) ~= "table" or not req.valid then
		d.action = "idle"
		d.reason = "no_request"
		return d
	end
	d.request_map = vrmod.utils.WarmAttach_NormalizeMap(req.map)
	d.current_map = vrmod.utils.WarmAttach_NormalizeMap(opts.current_map)
	if d.request_map == "" then
		d.action = "reject"
		d.reason = "no_map"
		return d
	end
	local act = string.lower(trim(req.action or "warm_request"))
	if act ~= "" and act ~= "warm_request" and act ~= "warm_reuse" then
		d.action = "reject"
		d.reason = "bad_action"
		return d
	end
	if d.current_map == "" then
		d.action = allow and "changelevel" or "deferred"
		d.reason = allow and "menu_or_unknown" or "eligible_deferred"
		d.would_changelevel = allow
		return d
	end
	if d.request_map == d.current_map then
		d.action = "same_map"
		d.reason = "already_on_map"
		d.would_changelevel = false
		return d
	end
	if allow then
		d.action = "changelevel"
		d.reason = "eligible"
		d.would_changelevel = true
	else
		d.action = "deferred"
		d.reason = "eligible_deferred"
		d.would_changelevel = false
	end
	return d
end

--- Human toast / log line. nil when idle.
function vrmod.utils.WarmAttach_Toast(decision)
	if type(decision) ~= "table" or not decision.valid then return nil end
	if decision.action == "idle" then return nil end
	if decision.action == "same_map" then
		return "Warm attach · same map · changelevel not needed"
	end
	if decision.action == "deferred" then
		if decision.current_map and decision.current_map ~= "" then
			return string.format("Warm attach · want %s · on %s · deferred",
				tostring(decision.request_map), tostring(decision.current_map))
		end
		return string.format("Warm attach · want %s · changelevel deferred",
			tostring(decision.request_map))
	end
	if decision.action == "changelevel" then
		return string.format("Warm attach · changelevel → %s", tostring(decision.request_map))
	end
	if decision.action == "reject" then
		return string.format("Warm attach · rejected (%s)", tostring(decision.reason))
	end
	return nil
end

-- ── G04 careful changelevel plan executor (default OFF) ─────────────────────
-- Product never auto-changelevels unless opt-in flag is set. Pure helpers only;
-- openxr_launch supplies RunConsoleCommand wrapper when armed.

--- Map token safe for console changelevel: [a-z0-9_]+ after normalize, len 1..64.
function vrmod.utils.WarmAttach_MapTokenOk(raw)
	local s = vrmod.utils.WarmAttach_NormalizeMap(raw)
	if s == "" or #s > 64 then return false end
	return s:match("^[a-z0-9_]+$") ~= nil
end

--- G04 careful allow gate (pure). Product default OFF.
--- flags:
---   convar_on     bool  vrmod_warm_changelevel GetBool
---   file_enable   bool  DATA vrmod/warm_changelevel_enable.txt exists
---   env_on        bool  GVRMOD_WARM_CHANGELEVEL truthy (launcher mirror)
---   force         bool  test override
function vrmod.utils.WarmAttach_AllowChangelevelFromFlags(flags)
	flags = type(flags) == "table" and flags or {}
	if flags.force then return true end
	if flags.convar_on then return true end
	if flags.file_enable then return true end
	if flags.env_on then return true end
	return false
end

--- Pure changelevel plan from WarmAttach_Decide result.
--- plan.do_changelevel only when decision.action == "changelevel" and map token ok.
function vrmod.utils.WarmAttach_ChangelevelPlan(decision)
	local p = {
		valid = true,
		do_changelevel = false,
		map = "",
		from_map = "",
		method = "none", -- none | changelevel
		reason = "none",
		cmd = "",
	}
	if type(decision) ~= "table" or not decision.valid then
		p.valid = false
		p.reason = "invalid_decision"
		return p
	end
	p.map = vrmod.utils.WarmAttach_NormalizeMap(decision.request_map)
	p.from_map = vrmod.utils.WarmAttach_NormalizeMap(decision.current_map)
	if decision.action == "same_map" then
		p.reason = "already_on_map"
		return p
	end
	if decision.action == "idle" or decision.action == "reject" then
		p.reason = tostring(decision.reason or decision.action)
		return p
	end
	if decision.action == "deferred" then
		p.reason = "eligible_deferred"
		return p
	end
	if decision.action ~= "changelevel" or not decision.would_changelevel then
		p.reason = "not_armed"
		return p
	end
	if not vrmod.utils.WarmAttach_MapTokenOk(p.map) then
		p.reason = "bad_map_token"
		return p
	end
	p.do_changelevel = true
	p.method = "changelevel"
	p.reason = tostring(decision.reason or "eligible")
	p.cmd = "changelevel " .. p.map
	return p
end

--- Console cmd string or nil when plan not armed.
function vrmod.utils.WarmAttach_ChangelevelCmd(plan)
	if type(plan) ~= "table" or not plan.valid or not plan.do_changelevel then return nil end
	if type(plan.cmd) == "string" and plan.cmd ~= "" then return plan.cmd end
	if plan.map and plan.map ~= "" and vrmod.utils.WarmAttach_MapTokenOk(plan.map) then
		return "changelevel " .. plan.map
	end
	return nil
end

--- True when executor may run changelevel (plan armed + allow).
function vrmod.utils.WarmAttach_ShouldExecuteChangelevel(plan, allowChangelevel)
	if not allowChangelevel then return false end
	if type(plan) ~= "table" or not plan.valid then return false end
	if not plan.do_changelevel then return false end
	if plan.method ~= "changelevel" then return false end
	if not vrmod.utils.WarmAttach_MapTokenOk(plan.map) then return false end
	return true
end

--- Pure executor: run changelevel via injectable runner(map) → ok,err.
--- Never calls engine itself — openxr_launch supplies RunConsoleCommand wrapper.
--- Returns { applied=bool, map=string, ok=bool, error=string|nil }
function vrmod.utils.WarmAttach_ExecuteChangelevel(plan, runner)
	local res = { applied = false, map = "", ok = true, error = nil }
	if type(plan) ~= "table" or not plan.valid or not plan.do_changelevel then
		res.ok = false
		res.error = "plan_not_armed"
		return res
	end
	res.map = tostring(plan.map or "")
	if not vrmod.utils.WarmAttach_MapTokenOk(res.map) then
		res.ok = false
		res.error = "bad_map_token"
		return res
	end
	if type(runner) ~= "function" then
		res.ok = false
		res.error = "no_runner"
		return res
	end
	local ok, err = runner(res.map)
	if ok then
		res.applied = true
		res.ok = true
	else
		res.ok = false
		res.error = tostring(err or "runner_fail")
	end
	return res
end

--- Toast after execute attempt (pure).
function vrmod.utils.WarmAttach_ExecuteToast(execRes, plan)
	if type(execRes) ~= "table" then return nil end
	if execRes.applied and execRes.ok then
		return string.format("Warm attach · changelevel → %s", tostring(execRes.map or (plan and plan.map) or "?"))
	end
	if execRes.error then
		return "Warm attach · changelevel failed · " .. tostring(execRes.error)
	end
	return nil
end
