-- Menu state: load the Cube map only after workshop addons finish.
-- Command-line +map starts the map during that download and the loading
-- screen stays on "Downloading addons from the Workshop".
-- This file has to stand alone. The menu state does not include() files
-- under lua/vrmod/, and bailing out there leaves GMod on the main menu.
if not (hook and hook.Add and timer and timer.Create and SysTime) then
	return
end

local MARKER = "vrmod/openxr_launch.txt"
local LAST_PLAY = "vrmod/cube_last_play.txt"
local ACTIVITY_SEC = 3
local BOOT_FALLBACK_SEC = 180
local QUIET_LOAD = 12

local function norm_map(raw)
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

-- Used only when the shared law cannot be loaded in this state.
-- Outcomes match vrmod.utils.WorkshopMap_Decide for the options this
-- menu passes: no command-line +map, no load while a download is active,
-- load after a quiet stretch even if WorkshopEnd never fired.
local function menu_decide(opts)
	opts = type(opts) == "table" and opts or {}
	local want = norm_map(opts.want_map)
	local cur = norm_map(opts.current_map)
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
	if opts.workshop_busy or opts.subscriptions_busy or pending > 0 then
		d.reason = "workshop_downloading"
		return d
	end
	local quiet = opts.quiet_sec
	if quiet ~= nil then
		quiet = tonumber(quiet) or 0
		if quiet < 0 then quiet = 0 end
	end
	local held = quiet ~= nil and quiet or elapsed
	if not opts.workshop_idle_seen and held < QUIET_LOAD then
		d.reason = opts.list_ready == false and "list_not_ready" or "workshop_confirm"
		return d
	end
	if opts.workshop_idle_seen and quiet ~= nil and quiet < 2 then
		d.reason = "workshop_confirm"
		return d
	end
	d.action = "load"
	d.reason = "addons_ready"
	return d
end

local function law_ready()
	return vrmod and vrmod.utils and vrmod.utils.WorkshopMap_Decide
end

local function try_source(src)
	if not src or src == "" or not RunString then return false end
	local ok = pcall(RunString, src, "sh_workshop_map_law.lua", false)
	return ok and law_ready()
end

local function ensure_law()
	if law_ready() then return vrmod.utils.WorkshopMap_Decide end
	if include then
		pcall(include, "vrmod/utils/sh_workshop_map_law.lua")
		if law_ready() then return vrmod.utils.WorkshopMap_Decide end
	end
	if file and file.Read then
		local reads = {
			{ "vrmod/utils/sh_workshop_map_law.lua", "LUA" },
			{ "addons/vrmod-x64/lua/vrmod/utils/sh_workshop_map_law.lua", "GAME" },
			{ "lua/vrmod/utils/sh_workshop_map_law.lua", "GAME" },
		}
		for i = 1, #reads do
			local src = file.Read(reads[i][1], reads[i][2])
			if try_source(src) then return vrmod.utils.WorkshopMap_Decide end
		end
	end
	return nil
end

local decide = ensure_law()
if not decide then
	if file then
		print("[gVRMod] workshop map law not on the menu path — menu decider will start the map")
	end
	decide = menu_decide
end

local last_work_at = nil
local last_sub_at = nil
local saw_end = false
local subs_cur, subs_max = 0, 0
local quiet_since = nil
local t0 = SysTime()
local issued_at = nil
local issue_count = 0
local last_log = -100

local function mark_work()
	last_work_at = SysTime()
end

hook.Add("WorkshopStart", "gvr_cube_workshop_map", mark_work)
hook.Add("WorkshopDownloadFile", "gvr_cube_workshop_map", mark_work)
hook.Add("WorkshopDownloadProgress", "gvr_cube_workshop_map", mark_work)
hook.Add("WorkshopExtractProgress", "gvr_cube_workshop_map", mark_work)
hook.Add("WorkshopDownloadedFile", "gvr_cube_workshop_map", mark_work)

hook.Add("WorkshopDownloadTotals", "gvr_cube_workshop_map", function(remain)
	remain = tonumber(remain) or 0
	if remain > 0 then
		mark_work()
	else
		saw_end = true
	end
end)

hook.Add("WorkshopEnd", "gvr_cube_workshop_map", function()
	saw_end = true
end)

hook.Add("WorkshopSubscriptionsProgress", "gvr_cube_workshop_map", function(cur, max)
	last_sub_at = SysTime()
	subs_cur = tonumber(cur) or 0
	subs_max = tonumber(max) or 0
end)

local function read_key(path, key)
	if not file or not file.Exists or not file.Exists(path, "DATA") then return "" end
	local raw = file.Read(path, "DATA") or ""
	return raw:match(key .. "%s*=%s*([%w_%-]+)") or ""
end

local function file_age(path)
	if not file or not file.Time or not os or not os.time then return nil end
	if not file.Exists(path, "DATA") then return nil end
	local t = file.Time(path, "DATA") or 0
	if t <= 0 then return nil end
	return os.time() - t
end

local function want_map()
	local from_marker = read_key(MARKER, "bg_map")
	if from_marker ~= "" then return from_marker end
	-- Client deletes the marker after a map comes up. If that load fell
	-- back to the menu in this same boot, the Cube map is still last play.
	-- An older snapshot must not hijack a later plain GMod menu.
	-- SysTime is seconds since this GMod process started, not since this
	-- menu visit. Quitting to the menu after a played map must not reload it.
	if SysTime() > BOOT_FALLBACK_SEC then return "" end
	local age = file_age(LAST_PLAY)
	if age ~= nil and age > BOOT_FALLBACK_SEC then return "" end
	return read_key(LAST_PLAY, "map")
end

local function addon_snapshot()
	if not engine or not engine.GetAddons then return false, 0, 0 end
	local ok, res = pcall(engine.GetAddons)
	if not ok or type(res) ~= "table" then return false, 0, 0 end
	local count, pending = 0, 0
	for _, a in pairs(res) do
		if type(a) == "table" then
			local id = tostring(a.wsid or "")
			if id ~= "" and id ~= "0" then
				count = count + 1
				-- mounted == false is a disabled addon, not a download.
				if a.downloaded == false then pending = pending + 1 end
			end
		end
	end
	return true, count, pending
end

timer.Create("gvr_cube_workshop_map", 0.5, 0, function()
	local now = SysTime()
	local want = want_map()
	local list_ready, count, pending = addon_snapshot()
	local work_busy = last_work_at ~= nil and (now - last_work_at) < ACTIVITY_SEC
	local subs_busy = last_sub_at ~= nil
		and (now - last_sub_at) < ACTIVITY_SEC
		and subs_max > 0
		and subs_cur < subs_max
	local downloading = work_busy or subs_busy or pending > 0
	if downloading then
		quiet_since = nil
	elseif not quiet_since then
		quiet_since = now
	end
	local d = decide({
		want_map = want,
		elapsed_sec = now - t0,
		workshop_busy = work_busy or pending > 0,
		subscriptions_busy = subs_busy,
		workshop_idle_seen = saw_end,
		list_ready = list_ready,
		addon_count = count,
		pending_downloads = pending,
		quiet_sec = (quiet_since ~= nil) and (now - quiet_since) or 0,
	})
	if d.action == "idle" then return end
	if d.action ~= "load" then
		if now - last_log >= 10 then
			last_log = now
			print(string.format(
				"[gVRMod] map %s waiting (%s) pending=%s",
				tostring(d.want_map),
				tostring(d.reason),
				tostring(d.pending)
			))
		end
		return
	end
	if issue_count >= 3 then
		if issued_at ~= nil and (now - issued_at) < 20 then return end
		issue_count = 4
		print("[gVRMod] map " .. d.want_map .. " did not leave the menu")
		timer.Remove("gvr_cube_workshop_map")
		return
	end
	if issued_at ~= nil and (now - issued_at) < 20 then return end
	issue_count = issue_count + 1
	issued_at = now
	print("[gVRMod] workshop idle — map " .. d.want_map .. " (" .. d.reason .. ")")
	if RunConsoleCommand then
		RunConsoleCommand("map", d.want_map)
	end
end)
