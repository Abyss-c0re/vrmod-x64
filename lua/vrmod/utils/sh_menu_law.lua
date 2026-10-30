-- G26: in-game / Quick Menu thrash law (pure, offline-tested).
-- Pain point #9: QM VRClimb menu dupes — dedupe by id/name, register once.
-- Cube UI: no menu thrash; stable layout id preferred over function identity
-- (addons re-call AddInGameMenuItem with new anonymous funcs every Start).
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

--- Normalize display name for name-key dedupe.
function vrmod.utils.MenuLaw_NormalizeName(name)
	name = tostring(name or "")
	-- trim + lower (pure; no engine string.Trim dependency)
	name = name:gsub("^%s+", ""):gsub("%s+$", "")
	return string.lower(name)
end

--- Stable backup / dedupe key. Prefer layout id; never function identity.
function vrmod.utils.MenuLaw_StableKey(name, id)
	if id ~= nil and tostring(id) ~= "" then
		return "id:" .. string.lower(tostring(id))
	end
	return "name:" .. vrmod.utils.MenuLaw_NormalizeName(name)
end

--- Climb-related labels collapse to one layout id (pain #9).
function vrmod.utils.MenuLaw_CanonicalClimbId()
	return "vrclimb"
end

function vrmod.utils.MenuLaw_IsClimbName(name)
	local n = vrmod.utils.MenuLaw_NormalizeName(name)
	return n == "vrclimb" or n == "vr climb" or n == "vr climbing"
end

--- True when item matches name and/or id (update-in-place, no second button).
--- Does not compare function refs (anonymous re-register is the thrash source).
function vrmod.utils.MenuLaw_ItemsMatch(item, name, id)
	if type(item) ~= "table" then return false end
	if id and item.id and string.lower(tostring(item.id)) == string.lower(tostring(id)) then
		return true
	end
	if vrmod.utils.MenuLaw_NormalizeName(item.name) == vrmod.utils.MenuLaw_NormalizeName(name) then
		return true
	end
	-- Climb aliases: VRClimb / VR Climb / VR Climbing ↔ id vrclimb
	local climbId = vrmod.utils.MenuLaw_CanonicalClimbId()
	if id and string.lower(tostring(id)) == climbId and vrmod.utils.MenuLaw_IsClimbName(item.name) then
		return true
	end
	if item.id and string.lower(tostring(item.id)) == climbId and vrmod.utils.MenuLaw_IsClimbName(name) then
		return true
	end
	return false
end

--- Pure dedupe of a list of menu item tables (keep first occurrence order).
--- items: { {name=, id=}, ... }  Returns new list + dropped count.
function vrmod.utils.MenuLaw_DedupList(items)
	items = type(items) == "table" and items or {}
	local seen = {}
	local out = {}
	local dropped = 0
	for i = 1, #items do
		local item = items[i]
		if type(item) == "table" then
			local key = vrmod.utils.MenuLaw_StableKey(item.name, item.id)
			if seen[key] then
				dropped = dropped + 1
			else
				seen[key] = true
				out[#out + 1] = item
			end
		end
	end
	return out, dropped
end

--- Pure decision snapshot.
--- opts:
---   items table|nil          menuItems-like
---   register_count number|nil how many AddInGameMenuItem calls this session for same key
---   climb_dupes number|nil
---   vr_active bool|nil
function vrmod.utils.MenuLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local items = type(opts.items) == "table" and opts.items or {}
	local deduped, dropped = vrmod.utils.MenuLaw_DedupList(items)
	local climbNames = 0
	local climbIds = 0
	for i = 1, #items do
		local it = items[i]
		if type(it) == "table" then
			if vrmod.utils.MenuLaw_IsClimbName(it.name) then climbNames = climbNames + 1 end
			if it.id and string.lower(tostring(it.id)) == vrmod.utils.MenuLaw_CanonicalClimbId() then
				climbIds = climbIds + 1
			end
		end
	end
	local climbDupes = tonumber(opts.climb_dupes)
	if climbDupes == nil then
		-- Approximate: more than one climb-tagged entry before dedupe
		local climbTagged = 0
		for i = 1, #items do
			local it = items[i]
			if type(it) == "table" and (vrmod.utils.MenuLaw_IsClimbName(it.name)
				or (it.id and string.lower(tostring(it.id)) == "vrclimb")) then
				climbTagged = climbTagged + 1
			end
		end
		climbDupes = math.max(0, climbTagged - 1)
	end
	local d = {
		valid = true,
		vr_active = opts.vr_active and true or false,
		item_count = #items,
		unique_count = #deduped,
		dropped = dropped,
		climb_dupes = climbDupes,
		risk = "none", -- none | thrash | climb_dupe
		reason = "ok",
		path_ok = true,
	}
	if climbDupes > 0 then
		d.risk = "climb_dupe"
		d.reason = "vrclimb_menu_dupes"
		d.path_ok = false
	elseif dropped > 0 then
		d.risk = "thrash"
		d.reason = "duplicate_id_or_name"
		d.path_ok = false
	else
		d.reason = "dedupe_clean"
		d.path_ok = true
	end
	return d
end

function vrmod.utils.MenuLaw_StatusLabel(decision)
	if type(decision) ~= "table" then return "MENU · IDLE" end
	if decision.risk == "climb_dupe" then return "MENU · CLIMB DUPE" end
	if decision.risk == "thrash" then return "MENU · THRASH" end
	if decision.path_ok then return "MENU · DEDUPED" end
	return "MENU · HOLD"
end

--- Pure HMD observer contract (offline ≠ headset proof).
function vrmod.utils.MenuLaw_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_no_dupes = true,
		checklist = "G26 · IDLE · no menu decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if not decision.path_ok then
		e.verdict = "expect_dupe_fail"
		e.expect_no_dupes = false
		e.checklist = "G26 · DUPE RISK · " .. tostring(decision.reason or decision.risk)
		e.pass_line = "Must collapse by id/name; one VRClimb button"
		e.fail_line = "Double VRClimb / thrash register every Start"
		return e
	end
	e.verdict = "expect_clean"
	e.expect_no_dupes = true
	e.checklist = string.format(
		"G26 · CLEAN · %d unique · 0 dropped · climb_dupes=0",
		tonumber(decision.unique_count) or 0
	)
	e.pass_line = "One button per id/name; VRClimb single; laser click stable"
	e.fail_line = "Duplicate QM tiles or re-register thrash"
	return e
end

function vrmod.utils.MenuLaw_IsThrashRisk(decision)
	if type(decision) ~= "table" then return true end
	return not decision.path_ok
end

--- Spawn/context is showing only when the VR surface and the panel are both live.
--- A stale bind, or a panel the engine already hid, is not showing.
function vrmod.utils.MenuLaw_ShellShowing(opts)
	opts = type(opts) == "table" and opts or {}
	if not opts.bound then return false end
	if not opts.surface then return false end
	if not opts.panel_valid then return false end
	if opts.panel_visible == false then return false end
	return true
end

--- What a spawn/context request should do: "open" | "close" | "keep".
--- force=true is a deferred retry. A retry must not toggle-close a shell that just appeared.
function vrmod.utils.MenuLaw_ShellRequest(opts)
	opts = type(opts) == "table" and opts or {}
	local showing = opts.showing and true or false
	if opts.force then
		if showing then return "keep" end
		return "open"
	end
	if showing then return "close" end
	return "open"
end

--- Q/C key-up fires OnSpawnMenuClose even when HangOpen left the panel visible.
--- Keep the VR surface then. Tear it down only when the panel actually hid.
function vrmod.utils.MenuLaw_KeepShellOnEngineClose(opts)
	opts = type(opts) == "table" and opts or {}
	if not opts.vr_active then return false end
	if not opts.bound then return false end
	if opts.panel_visible then return true end
	return false
end

--- Scrollbar zone along one axis. vertical=true uses up/down names; else left/right.
--- pos is local to the bar. Returns up|down|left|right|grip|page_dec|page_inc|miss.
function vrmod.utils.ScrollLaw_Zone(pos, gripPos, gripSize, btn, track, vertical)
	pos = tonumber(pos) or 0
	gripPos = tonumber(gripPos) or 0
	gripSize = math.max(tonumber(gripSize) or 0, 0)
	btn = math.max(tonumber(btn) or 0, 0)
	track = tonumber(track) or 0
	if pos < -0.5 or (track > 0 and pos > track + 0.5) then return "miss" end
	if btn > 0 and pos < btn then
		return vertical and "up" or "left"
	end
	if btn > 0 and track > 0 and pos > track - btn then
		return vertical and "down" or "right"
	end
	if gripSize > 0 and pos >= gripPos and pos <= gripPos + gripSize then
		return "grip"
	end
	if pos < gripPos then return "page_dec" end
	return "page_inc"
end

--- While a mouse button is held, VGUI drag (scrollbar grip) only moves if cursor-moved is pumped.
function vrmod.utils.ScrollLaw_PumpWhileHeld(held)
	return held and true or false
end

--- Focus for a click.
--- A hit on this stereo frame is the surface under the laser and wins over a stored focus.
--- Stored focus is the fallback when this frame has not hit anything yet.
--- The previous frame's hit is only used when there is no stored focus (input before draw).
function vrmod.utils.MenuLaw_ClickFocus(opts)
	opts = type(opts) == "table" and opts or {}
	local sf = tonumber(opts.stereo_frame) or 0
	local bestNow, bestNowD, bestPrev, bestPrevD
	local hits = opts.hits
	if type(hits) == "table" then
		for i = 1, #hits do
			local h = hits[i]
			if type(h) == "table" and h.uid and h.frame ~= nil then
				local age = sf - (tonumber(h.frame) or sf)
				local d = tonumber(h.dist) or 0
				if age == 0 and (not bestNow or d < bestNowD) then
					bestNow = h.uid
					bestNowD = d
				elseif age == 1 and (not bestPrev or d < bestPrevD) then
					bestPrev = h.uid
					bestPrevD = d
				end
			end
		end
	end
	if bestNow then return bestNow end
	if opts.focus and opts.focus ~= false and tostring(opts.focus) ~= "" then
		return opts.focus
	end
	return bestPrev
end

--- Keep the desktop clicker while a Derma panel is the focused VR surface.
--- Turning it off leaves InternalMousePressed ignored until focus changes, so the first presses do nothing.
function vrmod.utils.MenuLaw_KeepScreenClicker(opts)
	opts = type(opts) == "table" and opts or {}
	return opts.derma_focused and true or false
end

--- Engine quit that does not wait on a confirm dialog.
--- "quit" opens that dialog; the VR unpause hook then hides GameUI and the quit vanishes.
function vrmod.utils.MenuLaw_QuitArgs()
	return "gamemenucommand", "QuitNoConfirm"
end

--- Force-unpause / HideGameUI must stand down while a quit is in flight,
--- while Shift is held, or while the stock pause menu is up.
function vrmod.utils.MenuLaw_AllowForceUnpause(opts)
	opts = type(opts) == "table" and opts or {}
	if opts.quitting then return false end
	if opts.shift_down then return false end
	if opts.stock_pause then return false end
	return true
end

--- ESC while VR is live.
--- "desktop" outside VR, "stock" for Shift / an open engine pause, "hub" for the Cube pause.
function vrmod.utils.MenuLaw_EscAction(opts)
	opts = type(opts) == "table" and opts or {}
	if not opts.vr_active then return "desktop" end
	if opts.shift_down or opts.stock_pause then return "stock" end
	return "hub"
end
