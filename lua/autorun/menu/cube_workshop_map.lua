-- Menu state: load the Cube map only after workshop addons finish.
-- Command-line +map starts the map during that download and the loading
-- screen stays on "Downloading addons from the Workshop".
if not pcall(include, "vrmod/utils/sh_workshop_map_law.lua")
	or not (vrmod and vrmod.utils and vrmod.utils.WorkshopMap_Decide) then
	print("[gVRMod] workshop map law missing — Cube map stays on the menu")
	return
end

local MARKER = "vrmod/openxr_launch.txt"
local busy = false
local saw_work = false
local saw_end = false
local subs_cur, subs_max, subs_seen = 0, 0, false
local quiet_since = nil
local t0 = SysTime()

local function want_map()
	if not file.Exists(MARKER, "DATA") then return "" end
	local raw = file.Read(MARKER, "DATA") or ""
	return raw:match("bg_map%s*=%s*([%w_%-]+)") or ""
end

local function mark_busy()
	busy = true
	saw_work = true
end

hook.Add("WorkshopStart", "gvr_cube_workshop_map", mark_busy)
hook.Add("WorkshopDownloadFile", "gvr_cube_workshop_map", mark_busy)
hook.Add("WorkshopDownloadProgress", "gvr_cube_workshop_map", mark_busy)
hook.Add("WorkshopExtractProgress", "gvr_cube_workshop_map", mark_busy)

hook.Add("WorkshopDownloadTotals", "gvr_cube_workshop_map", function(remain)
	remain = tonumber(remain) or 0
	if remain > 0 then
		mark_busy()
	elseif saw_work then
		busy = false
		saw_end = true
	end
end)

hook.Add("WorkshopEnd", "gvr_cube_workshop_map", function()
	busy = false
	saw_end = true
end)

hook.Add("WorkshopSubscriptionsProgress", "gvr_cube_workshop_map", function(cur, max)
	subs_seen = true
	subs_cur = tonumber(cur) or 0
	subs_max = tonumber(max) or 0
end)

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
	local want = want_map()
	local now = SysTime()
	local list_ready, count, pending = addon_snapshot()
	local subs_busy = subs_seen and subs_max > 0 and subs_cur < subs_max
	local downloading = busy or subs_busy or pending > 0
	if downloading then
		quiet_since = nil
	elseif not quiet_since then
		quiet_since = now
	end
	local d = vrmod.utils.WorkshopMap_Decide({
		want_map = want,
		elapsed_sec = now - t0,
		workshop_busy = busy or pending > 0,
		subscriptions_busy = subs_busy,
		workshop_idle_seen = saw_end,
		list_ready = list_ready,
		addon_count = count,
		pending_downloads = pending,
		quiet_sec = quiet_since and (now - quiet_since) or 0,
	})
	if d.action == "idle" then
		if now - t0 > 3 then timer.Remove("gvr_cube_workshop_map") end
		return
	end
	if d.action ~= "load" then return end
	timer.Remove("gvr_cube_workshop_map")
	print("[gVRMod] workshop idle — map " .. d.want_map .. " (" .. d.reason .. ")")
	RunConsoleCommand("map", d.want_map)
end)
