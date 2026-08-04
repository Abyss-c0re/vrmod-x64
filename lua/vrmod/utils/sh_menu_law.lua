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
