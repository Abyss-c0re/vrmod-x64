-- Cold Start must not pass +map while workshop addons are still downloading.
-- That race sticks the loading screen on "Downloading addons from the Workshop".
-- The menu waits until workshop is idle, then runs `map`.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

function vrmod.utils.WorkshopMap_PassMapOnCommandLine()
	return false
end

local function norm(raw)
	local s = string.lower(tostring(raw or ""))
	s = s:gsub("\\", "/")
	s = s:gsub("^maps/", "")
	s = s:gsub("%.bsp$", "")
	s = (s:gsub("^%s+", ""):gsub("%s+$", ""))
	return s
end

local function token_ok(s)
	return s ~= "" and string.match(s, "^[%w_%-]+$") ~= nil
end

--- Pure: when may Cube issue `map`?
--- opts.want_map, current_map, elapsed_sec
--- opts.workshop_busy, subscriptions_busy, workshop_idle_seen (menu hooks)
--- opts.list_ready, addon_count, pending_downloads (engine.GetAddons)
--- opts.quiet_sec: seconds the list has stayed idle (menu). Nil uses elapsed.
--- opts.require_bsp, bsp_visible
--- action: idle | already | wait | load
function vrmod.utils.WorkshopMap_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local want = norm(opts.want_map)
	local cur = norm(opts.current_map)
	local elapsed = tonumber(opts.elapsed_sec) or 0
	if elapsed < 0 then elapsed = 0 end
	local pending = tonumber(opts.pending_downloads) or 0
	if pending < 0 then pending = 0 end
	local d = {
		action = "wait",
		reason = "workshop_settle",
		want_map = want,
		pending = pending,
		pass_map_on_command_line = false,
	}
	if not token_ok(want) then
		d.action = "idle"
		d.reason = want == "" and "no_map" or "bad_map"
		return d
	end
	if cur ~= "" and cur == want then
		d.action = "already"
		d.reason = "on_map"
		return d
	end
	-- A download still in progress. No timeout: mapping now is the stuck plaque.
	if opts.workshop_busy or opts.subscriptions_busy or pending > 0 then
		d.reason = "workshop_downloading"
		return d
	end
	local quiet = opts.quiet_sec
	if quiet ~= nil then
		quiet = tonumber(quiet) or 0
		if quiet < 0 then quiet = 0 end
	end
	-- Nil quiet means the caller has no idle clock, so elapsed is the clock.
	-- An explicit 0 means activity just stopped. That is not idle yet.
	local held = quiet ~= nil and quiet or elapsed
	local QUIET_LOAD = 12
	if opts.list_ready ~= nil then
		if not opts.list_ready then
			-- GetAddons is not readable yet. Menu state often never sees
			-- WorkshopEnd. A long quiet with nothing pending is still idle.
			if not opts.workshop_idle_seen and held < QUIET_LOAD then
				d.reason = "list_not_ready"
				return d
			end
		else
			local n = tonumber(opts.addon_count) or 0
			if n == 0 and not opts.workshop_idle_seen and elapsed < 5 then
				d.reason = "list_settle"
				return d
			end
			-- A non-empty list with no WorkshopEnd yet is often the previous
			-- boot's cache. Steam can still start this boot's download.
			-- Do not run `map` until that reading has stayed quiet.
			if n > 0 and not opts.workshop_idle_seen and held < QUIET_LOAD then
				d.reason = "workshop_confirm"
				return d
			end
		end
	elseif not opts.workshop_idle_seen and held < QUIET_LOAD then
		-- No addon list and no WorkshopEnd yet. Waiting forever left Cube
		-- on the main menu. Quiet long enough, with nothing pending, loads.
		d.reason = "workshop_settle"
		return d
	end
	if opts.workshop_idle_seen and quiet ~= nil and quiet < 2 then
		d.reason = "workshop_confirm"
		return d
	end
	if opts.require_bsp and not opts.bsp_visible then
		d.reason = "bsp_missing"
		return d
	end
	d.action = "load"
	d.reason = "addons_ready"
	return d
end
