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
