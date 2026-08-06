-- Controller binding layer (SteamVR binding UI replacement).
-- Maps physical controller sources → logical VRMod boolean actions, including chords.
-- Analogs (sticks/triggers as vector1/2) stay on native OpenXR / OpenVR actions.
--
-- =============================================================================
-- QUEST 3 GOLD DEFAULTS — source of truth (do not change without headset smoke)
-- =============================================================================
-- DefaultMap() freezes the battle-tested Quest 3 / Oculus Touch scheme used on
-- WiVRn + Monado (mirrors vrmod_bindings_oculus_touch.txt + C++ g_ctrlSources).
-- Fresh install / ResetDefaults must feel identical to this map.
-- Interaction profiles: oculus/touch_controller, facebook/touch_controller_pro,
-- meta/touch_controller_plus (see gVRMod/src/input/xr_input.cpp).
-- Rebind UI (VR hand panel / Derma) is optional power-user tooling on top of this gold.
-- =============================================================================

if SERVER then return end

vrmod = vrmod or {}
vrmod.bindings = vrmod.bindings or {}

local BIND_FILE = "vrmod/vrmod_openxr_bindings.json"
local THRESHOLD = 0.55

-- set: "main" = on foot only; "driving" = vehicle only; nil = both (SteamVR action-set scope).
-- sets: optional dual rules { main = {sources,mode}, driving = {sources,mode} } — our chord
-- system uses this so vehicle Weapon Menu can be a chord without fighting turret stick-click.
local function DefaultMap()
	return {
		version = 3,
		preset = "quest3_touch",
		-- mode "any" = OR of sources; "all" = AND (chord)
		actions = {
			-- On foot (/actions/main) — Quest 3 gold
			boolean_primaryfire      = { sources = { "right_trigger" }, mode = "any", set = "main" },
			boolean_secondaryfire    = { sources = { "left_trigger" }, mode = "any", set = "main" },
			boolean_left_primaryfire = { sources = { "left_trigger" }, mode = "any", set = "main" },
			boolean_jump             = { sources = { "right_b" }, mode = "any", set = "main" },
			boolean_crouch           = { sources = { "right_a" }, mode = "any", set = "main" },
			boolean_use              = { sources = { "left_x" }, mode = "any", set = "main" },
			boolean_flashlight       = { sources = { "left_menu" }, mode = "any", set = "main" },
			boolean_sprint           = { sources = { "left_stick_click" }, mode = "any", set = "main" },
			-- Weapon menu: stick click on foot; single reliable button in vehicle
			-- (no grip+Y chord — fights wheel grip / spawnmenu on left_y)
			boolean_changeweapon     = {
				sources = { "right_stick_click" },
				mode = "any",
				set = nil,
				sets = {
					main = { sources = { "right_stick_click" }, mode = "any" },
					driving = { sources = { "left_menu" }, mode = "any" },
				},
			},
			boolean_teleport         = { sources = { "left_stick_click", "right_thumbrest" }, mode = "all", set = "main" },
			-- Both sets (manifest has main + driving duplicates)
			boolean_spawnmenu        = { sources = { "left_y" }, mode = "any" },
			boolean_left_pickup      = { sources = { "left_squeeze" }, mode = "any" },
			boolean_right_pickup     = { sources = { "right_squeeze" }, mode = "any" },
			boolean_reload           = { sources = { "left_thumbrest", "right_thumbrest" }, mode = "all" },
			-- Driving (/actions/driving) — same physical buttons, different logical actions
			boolean_handbrake        = { sources = { "right_a" }, mode = "any", set = "driving" },
			boolean_turbo            = { sources = { "right_b" }, mode = "any", set = "driving" },
			boolean_exit             = { sources = { "left_x" }, mode = "any", set = "driving" },
			boolean_switch_weapon    = { sources = { "left_thumbrest", "right_thumbrest" }, mode = "all", set = "driving" },
			boolean_signal_left      = { sources = { "left_squeeze", "left_thumbrest" }, mode = "all", set = "driving" },
			boolean_signal_right     = { sources = { "right_squeeze", "right_thumbrest" }, mode = "all", set = "driving" },
			boolean_alt_turret       = { sources = { "right_squeeze", "right_stick_click" }, mode = "all", set = "driving" },
			boolean_shift_up         = { sources = { "right_stick_north" }, mode = "any", set = "driving" },
			boolean_shift_down       = { sources = { "right_stick_south" }, mode = "any", set = "driving" },
			boolean_lights           = { sources = { "right_stick_east" }, mode = "any", set = "driving" },
			boolean_siren            = { sources = { "right_stick_west" }, mode = "any", set = "driving" },
			boolean_turret           = { sources = { "right_stick_click" }, mode = "any", set = "driving" },
			boolean_horn             = { sources = { "left_stick_click" }, mode = "any", set = "driving" },
		}
	}
end

-- Infer set for user-saved rules that predate version 2 / editor binds without set.
local DRIVING_ACTION_IDS = {
	boolean_handbrake = true, boolean_turbo = true, boolean_exit = true,
	boolean_switch_weapon = true, boolean_signal_left = true, boolean_signal_right = true,
	boolean_alt_turret = true, boolean_shift_up = true, boolean_shift_down = true,
	boolean_lights = true, boolean_siren = true, boolean_turret = true, boolean_horn = true,
	boolean_toggle_engine = true, boolean_shift_neutral = true,
}
local MAIN_ONLY_ACTION_IDS = {
	boolean_primaryfire = true, boolean_secondaryfire = true, boolean_left_primaryfire = true,
	boolean_jump = true, boolean_crouch = true, boolean_use = true, boolean_flashlight = true,
	boolean_sprint = true, boolean_teleport = true,
	boolean_undo = true, boolean_chat = true, boolean_menucontext = true, boolean_walkkey = true,
	-- boolean_changeweapon is dual-set (foot + vehicle) — not main-only
}

local function NormalizeSet(action, set)
	if set == "main" or set == "driving" then return set end
	if DRIVING_ACTION_IDS[action] then return "driving" end
	if MAIN_ONLY_ACTION_IDS[action] then return "main" end
	-- Custom actions: honor their driving flag from CustomActions table
	for _, row in ipairs(g_VR.CustomActions or {}) do
		if row and row[1] == action then
			if row.driving or row[4] == "1" then return "driving" end
			return "main"
		end
	end
	return nil -- both / either set
end

local state = {
	map = DefaultMap(),
	prev = {}, -- last boolean state per action
	enabled = true,
	listenSuppress = false, -- when rebind UI listens, mute remapped game actions
}

local function DeepCopy(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do
		c[k] = DeepCopy(v)
	end
	return c
end

function vrmod.bindings.GetDefaults()
	return DefaultMap()
end

function vrmod.bindings.GetMap()
	return state.map
end

function vrmod.bindings.IsEnabled()
	return state.enabled
end

function vrmod.bindings.SetEnabled(on)
	state.enabled = not not on
end

-- While rebind listen is active, remapped booleans stay false so
-- the button being bound does not also fire jump/fire/etc.
function vrmod.bindings.SetListenSuppress(on)
	state.listenSuppress = not not on
	if not on then
		-- edge state will re-arm cleanly on next Apply
		state.prev = {}
	end
end

function vrmod.bindings.IsListenSuppress()
	return state.listenSuppress
end

--- Human label for a physical source id (uses live GetSources when available).
function vrmod.bindings.SourceLabel(id)
	if not id then return "?" end
	local src = vrmod.bindings.GetSources()
	if src and src[id] and src[id].label then return src[id].label end
	return id
end

local function CopyRuleLeaf(rule)
	if type(rule) ~= "table" or type(rule.sources) ~= "table" then return nil end
	local src = {}
	for i, id in ipairs(rule.sources) do src[i] = id end
	return {
		sources = src,
		mode = (rule.mode == "all") and "all" or "any",
	}
end

--- Normalize a stored action rule (legacy single set and dual sets{}).
local function NormalizeStoredRule(action, rule)
	if type(rule) ~= "table" then return nil end
	local out = {
		sources = type(rule.sources) == "table" and rule.sources or {},
		mode = (rule.mode == "all") and "all" or "any",
		set = NormalizeSet(action, rule.set),
	}
	if type(rule.sets) == "table" then
		local sets = {}
		if rule.sets.main then sets.main = CopyRuleLeaf(rule.sets.main) end
		if rule.sets.driving then sets.driving = CopyRuleLeaf(rule.sets.driving) end
		if sets.main or sets.driving then
			out.sets = sets
			out.set = nil -- dual-set rules are live in both modes via sets{}
			-- Prefer main leaf as flat fallback for old Format/UI
			local pref = sets.main or sets.driving
			if pref then
				out.sources = pref.sources
				out.mode = pref.mode
			end
		end
	end
	return out
end

--- Active leaf rule for current mode (dual sets or legacy single).
local function ActiveRuleForMode(rule, driving)
	if type(rule) ~= "table" then return nil, false end
	if type(rule.sets) == "table" and (rule.sets.main or rule.sets.driving) then
		local leaf = driving and rule.sets.driving or rule.sets.main
		if leaf then return leaf, true end
		return nil, true -- dual-set action has no rule for this mode → force false
	end
	return rule, false
end

--- Restore one action to Quest gold default (or clear if no default).
function vrmod.bindings.RestoreActionDefault(action)
	if not action or action == "" then return end
	local def = DefaultMap().actions[action]
	if def then
		state.map.actions[action] = NormalizeStoredRule(action, def)
		state.prev[action] = nil
	else
		vrmod.bindings.ClearActionBinding(action)
	end
end

function vrmod.bindings.Load()
	state.map = DefaultMap()
	if not file.Exists(BIND_FILE, "DATA") then return state.map end
	local raw = file.Read(BIND_FILE, "DATA")
	if not raw or raw == "" then return state.map end
	local ok, data = pcall(util.JSONToTable, raw)
	if not ok or type(data) ~= "table" or type(data.actions) ~= "table" then
		vrmod.logger.Warn("OpenXR bindings file corrupt; using defaults")
		return state.map
	end
	-- Merge user actions over defaults so new defaults appear after updates
	local merged = DefaultMap()
	for action, rule in pairs(data.actions) do
		local norm = NormalizeStoredRule(action, rule)
		if norm and (norm.sources[1] or (norm.sets and (norm.sets.main or norm.sets.driving))) then
			-- changeweapon: ensure dual-set; upgrade flaky grip+Y vehicle chord → left_menu
			if action == "boolean_changeweapon" then
				local gold = DefaultMap().actions.boolean_changeweapon
				norm.sets = norm.sets or {}
				if not norm.sets.main and norm.sources[1] then
					norm.sets.main = { sources = norm.sources, mode = norm.mode }
				end
				local d = norm.sets.driving
				local flaky = d and d.sources and #d.sources >= 2
					and (table.HasValue(d.sources, "right_squeeze") or table.HasValue(d.sources, "left_squeeze"))
					and table.HasValue(d.sources, "left_y")
				if not d or flaky then
					norm.sets.driving = gold.sets and CopyRuleLeaf(gold.sets.driving) or { sources = { "left_menu" }, mode = "any" }
				end
				norm.set = nil
			end
			merged.actions[action] = norm
		end
	end
	state.map = merged
	state.prev = {}
	vrmod.logger.Info("Loaded OpenXR controller bindings from %s", BIND_FILE)
	return state.map
end

function vrmod.bindings.Save()
	file.CreateDir("vrmod")
	file.Write(BIND_FILE, util.TableToJSON(state.map, true))
	vrmod.logger.Info("Saved OpenXR controller bindings to %s", BIND_FILE)
end

function vrmod.bindings.ResetDefaults()
	-- Same Quest 3 gold as C++ Bindings_DefaultMap / launcher RESET button.
	-- Writes garrysmod/data/vrmod/vrmod_openxr_bindings.json (shared with launcher).
	state.map = DefaultMap()
	state.map.preset = "quest3_touch"
	state.prev = {}
	-- Best-effort backup of previous user file
	if file.Exists(BIND_FILE, "DATA") then
		local raw = file.Read(BIND_FILE, "DATA")
		if raw and #raw > 0 then
			local stamp = os.date("%Y%m%d_%H%M%S")
			file.Write("vrmod/vrmod_openxr_bindings.json.bak." .. stamp, raw)
		end
	end
	vrmod.bindings.Save()
	vrmod.logger.Info("OpenXR bindings reset to Quest 3 gold (%s)", BIND_FILE)
end

--- Dedupe sources, drop empties, stable order.
local function NormalizeSources(sources)
	if type(sources) == "string" then sources = { sources } end
	if type(sources) ~= "table" then return {} end
	local seen, out = {}, {}
	for _, id in ipairs(sources) do
		if type(id) == "string" and id ~= "" and not seen[id] then
			seen[id] = true
			out[#out + 1] = id
		end
	end
	return out
end

--- Make chord rules sensible. Returns sources, mode, warnings{string}.
function vrmod.bindings.NormalizeRule(sources, mode)
	sources = NormalizeSources(sources)
	mode = (mode == "all") and "all" or "any"
	local warnings = {}
	if #sources == 0 then
		return sources, mode, warnings
	end
	if mode == "all" and #sources < 2 then
		-- Chord of one button is nonsense — become single bind.
		mode = "any"
		warnings[#warnings + 1] = "Chord needs 2+ buttons; saved as single bind"
	end
	if mode == "any" and #sources > 1 then
		-- Multi-source OR is valid (SteamVR multi-path) but note it.
		warnings[#warnings + 1] = "Multiple buttons = OR (any one fires); use Chord for AND"
	end
	return sources, mode, warnings
end

function vrmod.bindings.SetActionBinding(action, sources, mode, set)
	if not action or action == "" then return nil end
	local prev = state.map.actions[action]
	local src, m, warnings = vrmod.bindings.NormalizeRule(sources, mode)
	set = NormalizeSet(action, set or (prev and prev.set) or nil)

	-- Dual-set actions (Weapon Menu): bind writes into sets[main|driving] so foot + vehicle
	-- can use different chords without wiping each other.
	local dual = action == "boolean_changeweapon"
		or (prev and type(prev.sets) == "table" and (prev.sets.main or prev.sets.driving))
	if dual and (set == "main" or set == "driving") then
		local sets = {}
		if prev and type(prev.sets) == "table" then
			if prev.sets.main then sets.main = CopyRuleLeaf(prev.sets.main) end
			if prev.sets.driving then sets.driving = CopyRuleLeaf(prev.sets.driving) end
		elseif prev and type(prev.sources) == "table" and prev.sources[1] then
			-- Migrate flat rule into the previous set (or main)
			local oldSet = prev.set == "driving" and "driving" or "main"
			sets[oldSet] = { sources = prev.sources, mode = (prev.mode == "all") and "all" or "any" }
		end
		sets[set] = { sources = src, mode = m }
		local pref = sets.main or sets.driving
		state.map.actions[action] = {
			sources = pref and pref.sources or src,
			mode = pref and pref.mode or m,
			set = nil,
			sets = sets,
		}
	else
		state.map.actions[action] = {
			sources = src,
			mode = m,
			set = set,
		}
	end
	state.prev[action] = nil
	return warnings
end

function vrmod.bindings.ClearActionBinding(action, set)
	if not action then return end
	-- Optional: clear only one set for dual actions
	if set == "main" or set == "driving" then
		local prev = state.map.actions[action]
		if prev and type(prev.sets) == "table" then
			prev.sets[set] = nil
			if not prev.sets.main and not prev.sets.driving then
				state.map.actions[action] = nil
			else
				local pref = prev.sets.main or prev.sets.driving
				prev.sources = pref.sources
				prev.mode = pref.mode
			end
			state.prev[action] = nil
			return
		end
	end
	state.map.actions[action] = nil
	state.prev[action] = nil
end

local function ActionLabel(id)
	for _, info in ipairs(vrmod.bindings.ListLogicalActions()) do
		if info.id == id then return info.label end
	end
	return id
end

function vrmod.bindings.ActionLabel(id)
	return ActionLabel(id)
end

--- Sets can be live at the same time (nil = both / either).
local function SetsCanOverlap(setA, setB)
	if setA == nil or setB == nil then return true end
	return setA == setB
end

local function SourceSet(rule)
	local t = {}
	if not rule or type(rule.sources) ~= "table" then return t end
	for _, id in ipairs(rule.sources) do
		t[id] = true
	end
	return t
end

local function SourceListSorted(rule)
	local t = {}
	if not rule or type(rule.sources) ~= "table" then return t end
	for _, id in ipairs(rule.sources) do
		t[#t + 1] = id
	end
	table.sort(t)
	return t
end

local function IsSubset(small, big)
	for id in pairs(small) do
		if not big[id] then return false end
	end
	return true
end

local function SharedSources(a, b)
	local out = {}
	for id in pairs(a) do
		if b[id] then out[#out + 1] = id end
	end
	table.sort(out)
	return out
end

-- Quest gold pairs that intentionally share a source (not user error).
local INTENTIONAL_SHARED = {
	["boolean_left_primaryfire|boolean_secondaryfire"] = true, -- left trigger dual-wield
}

local function PairKey(a, b)
	return (a < b) and (a .. "|" .. b) or (b .. "|" .. a)
end

--- Detect binding conflicts (hard dual-fire / soft chord-overlap).
--- Returns list of { severity="hard"|"soft", a, b, sources={}, message=string }
function vrmod.bindings.DetectConflicts(map)
	map = map or state.map
	local actions = map and map.actions or {}
	local ids = {}
	for id, rule in pairs(actions) do
		if type(rule) == "table" and type(rule.sources) == "table" and #rule.sources > 0 then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)

	local conflicts = {}
	local seenPair = {}

	local function add(sev, a, b, sources, msg)
		local key = PairKey(a, b) .. "|" .. sev .. "|" .. (msg or "")
		if seenPair[key] then return end
		seenPair[key] = true
		conflicts[#conflicts + 1] = {
			severity = sev,
			a = a,
			b = b,
			sources = sources or {},
			message = msg,
		}
	end

	for i = 1, #ids do
		local idA = ids[i]
		local ruleA = actions[idA]
		local setA = ruleA.set
		local modeA = ruleA.mode or "any"
		local srcA = SourceSet(ruleA)
		local listA = SourceListSorted(ruleA)

		if modeA == "all" and #listA < 2 then
			add("hard", idA, idA, listA, ActionLabel(idA) .. ": invalid chord (need 2+ buttons)")
		end

		for j = i + 1, #ids do
			local idB = ids[j]
			local ruleB = actions[idB]
			if SetsCanOverlap(setA, ruleB.set) then
				local modeB = ruleB.mode or "any"
				local srcB = SourceSet(ruleB)
				local listB = SourceListSorted(ruleB)
				local shared = SharedSources(srcA, srcB)
				if #shared == 0 then
					-- ok
				elseif INTENTIONAL_SHARED[PairKey(idA, idB)] then
					-- Quest dual-wield / known shared paths — skip
				elseif modeA == "any" and modeB == "any" then
					add("hard", idA, idB, shared,
						ActionLabel(idA) .. " and " .. ActionLabel(idB)
						.. " both fire on " .. table.concat(shared, ", "))
				elseif modeA == "all" and modeB == "all" then
					local same = (#listA == #listB)
					if same then
						for k = 1, #listA do
							if listA[k] ~= listB[k] then same = false break end
						end
					end
					if same then
						add("hard", idA, idB, listA,
							ActionLabel(idA) .. " and " .. ActionLabel(idB)
							.. " use the same chord")
					elseif IsSubset(srcA, srcB) or IsSubset(srcB, srcA) then
						add("soft", idA, idB, shared,
							"Nested chords: " .. ActionLabel(idA) .. " / " .. ActionLabel(idB)
							.. " — longer chord also fires the shorter")
					end
				else
					-- Chord vs single: e.g. teleport chord includes sprint stick-click
					local chordId = (modeA == "all") and idA or idB
					local anyId = (modeA == "any") and idA or idB
					add("soft", chordId, anyId, shared,
						"Chord " .. ActionLabel(chordId) .. " includes "
						.. ActionLabel(anyId) .. "'s button — both active while chord held")
				end
			end
		end
	end

	table.sort(conflicts, function(x, y)
		if x.severity ~= y.severity then return x.severity == "hard" end
		return (x.message or "") < (y.message or "")
	end)
	return conflicts
end

function vrmod.bindings.ConflictsForAction(action, map)
	local all = vrmod.bindings.DetectConflicts(map)
	local out = {}
	for _, c in ipairs(all) do
		if c.a == action or c.b == action then
			out[#out + 1] = c
		end
	end
	return out
end

function vrmod.bindings.HasHardConflicts(map)
	for _, c in ipairs(vrmod.bindings.DetectConflicts(map)) do
		if c.severity == "hard" then return true end
	end
	return false
end

function vrmod.bindings.ListLogicalActions()
	-- Stable list for editor UI. group = "main" | "driving" | "both" for filters.
	local list = {
		{ id = "boolean_primaryfire", label = "Primary Fire", group = "main" },
		{ id = "boolean_secondaryfire", label = "Secondary Fire", group = "main" },
		{ id = "boolean_left_primaryfire", label = "Left Primary Fire", group = "main" },
		{ id = "boolean_jump", label = "Jump", group = "main" },
		{ id = "boolean_crouch", label = "Crouch", group = "main" },
		{ id = "boolean_use", label = "Use", group = "main" },
		{ id = "boolean_spawnmenu", label = "Spawn Menu", group = "both" },
		-- On foot + Vehicle tabs (dual-set: stick on foot, chord in vehicle)
		{ id = "boolean_changeweapon", label = "Weapon Menu", group = "both" },
		{ id = "boolean_reload", label = "Reload", group = "both" },
		{ id = "boolean_sprint", label = "Sprint", group = "main" },
		{ id = "boolean_flashlight", label = "Flashlight", group = "main" },
		{ id = "boolean_left_pickup", label = "Left Pickup / Grip", group = "both" },
		{ id = "boolean_right_pickup", label = "Right Pickup / Grip", group = "both" },
		{ id = "boolean_teleport", label = "Teleport", group = "main" },
		{ id = "boolean_undo", label = "Undo", group = "main" },
		{ id = "boolean_chat", label = "Chat / Zoom", group = "main" },
		{ id = "boolean_menucontext", label = "Context Menu", group = "main" },
		{ id = "boolean_walkkey", label = "Walk Key", group = "main" },
		{ id = "boolean_handbrake", label = "Handbrake", group = "driving" },
		{ id = "boolean_turbo", label = "Turbo", group = "driving" },
		{ id = "boolean_exit", label = "Exit Vehicle", group = "driving" },
		{ id = "boolean_signal_left", label = "Signal Left", group = "driving" },
		{ id = "boolean_signal_right", label = "Signal Right", group = "driving" },
		{ id = "boolean_switch_weapon", label = "Switch Weapon", group = "driving" },
		{ id = "boolean_alt_turret", label = "Alt Turret", group = "driving" },
		{ id = "boolean_turret", label = "Turret", group = "driving" },
		{ id = "boolean_horn", label = "Horn", group = "driving" },
		{ id = "boolean_shift_up", label = "Shift Up", group = "driving" },
		{ id = "boolean_shift_down", label = "Shift Down", group = "driving" },
		{ id = "boolean_lights", label = "Lights", group = "driving" },
		{ id = "boolean_siren", label = "Siren", group = "driving" },
		{ id = "boolean_toggle_engine", label = "Toggle Engine", group = "driving" },
	}
	-- User custom actions (name → console cmds). Must be bound under Controller rebind on OpenXR.
	if isfunction(VRUtilLoadCustomActions) then pcall(VRUtilLoadCustomActions) end
	for _, row in ipairs(g_VR.CustomActions or {}) do
		local name = row and row[1]
		if type(name) == "string" and name ~= "" then
			local driving = row.driving or row[4] == "1"
			list[#list + 1] = {
				id = name,
				label = "Custom: " .. name,
				group = driving and "driving" or "main",
			}
		end
	end
	return list
end

--- Filtered action list for editor UI (filter: "all"|"main"|"driving").
function vrmod.bindings.ListLogicalActionsFiltered(filter)
	filter = filter or "all"
	local out = {}
	for _, info in ipairs(vrmod.bindings.ListLogicalActions()) do
		local g = info.group or "main"
		if filter == "all"
			or filter == g
			or (filter == "main" and g == "both")
			or (filter == "driving" and g == "both")
		then
			out[#out + 1] = info
		end
	end
	return out
end

local function SourcePressed(sourcesTable, id)
	local s = sourcesTable and sourcesTable[id]
	if not s then return false end
	-- Prefer raw value so a stale/false pressed (old modules gated on isActive)
	-- cannot kill a chord. pressed is only a fast path when true.
	local v = tonumber(s.value) or 0
	if s.analog then
		if v >= THRESHOLD then return true end
		return s.pressed == true
	end
	if v >= 0.5 then return true end
	return s.pressed == true
end

function vrmod.bindings.EvalRule(rule, sourcesTable)
	if not rule or type(rule.sources) ~= "table" or #rule.sources == 0 then
		return false
	end
	local mode = rule.mode or "any"
	if mode == "all" then
		for _, id in ipairs(rule.sources) do
			if not SourcePressed(sourcesTable, id) then return false end
		end
		return true
	end
	-- any
	for _, id in ipairs(rule.sources) do
		if SourcePressed(sourcesTable, id) then return true end
	end
	return false
end

local function FormatLeaf(leaf, useLabels)
	if not leaf or not leaf.sources or #leaf.sources == 0 then return "(unbound)" end
	local parts = {}
	for _, id in ipairs(leaf.sources) do
		parts[#parts + 1] = (useLabels ~= false and vrmod.bindings.SourceLabel and vrmod.bindings.SourceLabel(id)) or id
	end
	local sep = (leaf.mode == "all") and " + " or " | "
	local txt = table.concat(parts, sep)
	if leaf.mode == "all" then txt = txt .. " [chord]" end
	return txt
end

function vrmod.bindings.FormatRule(rule, useLabels, preferSet)
	if not rule then return "(unbound)" end
	-- Dual-set: show active tab's leaf, or both when no preference
	if type(rule.sets) == "table" and (rule.sets.main or rule.sets.driving) then
		if preferSet == "main" or preferSet == "driving" then
			return FormatLeaf(rule.sets[preferSet], useLabels)
		end
		local bits = {}
		if rule.sets.main then bits[#bits + 1] = "foot: " .. FormatLeaf(rule.sets.main, useLabels) end
		if rule.sets.driving then bits[#bits + 1] = "veh: " .. FormatLeaf(rule.sets.driving, useLabels) end
		if #bits == 0 then return "(unbound)" end
		return table.concat(bits, " · ")
	end
	if not rule.sources or #rule.sources == 0 then return "(unbound)" end
	local txt = FormatLeaf(rule, useLabels)
	if rule.set == "main" then txt = txt .. "  [on foot]"
	elseif rule.set == "driving" then txt = txt .. "  [vehicle]"
	end
	return txt
end

local function IsDrivingNow()
	if not g_VR then return false end
	if g_VR.vehicle and g_VR.vehicle.driving then return true end
	-- Fallback: Glide / stock vehicle before vehicle.driving is set this frame
	local ply = LocalPlayer and LocalPlayer()
	if not IsValid(ply) then return false end
	if ply.InVehicle and ply:InVehicle() then return true end
	if g_VR.vehicle and (g_VR.vehicle.glide or g_VR.vehicle.inside) then return true end
	return false
end

-- Apply Lua bindings over native GetActions result.
-- Overwrites booleans that have a binding rule; leaves vectors/poses alone.
-- Rules with set="main"|"driving" only apply in that mode (mirrors SteamVR action sets).
-- Returns input, changed (edge-triggered for remapped booleans + untouched native edges for non-mapped).
function vrmod.bindings.Apply(input, nativeChanged, sourcesTable)
	input = input or {}
	nativeChanged = type(nativeChanged) == "table" and nativeChanged or {}
	if not state.enabled or not sourcesTable then
		return input, nativeChanged
	end

	-- If no source path is live yet (pre-attach / failed suggest), keep native booleans.
	-- Live = active OR non-zero value (isActive alone is flaky on some runtimes).
	local sourcesLive = false
	for _, s in pairs(sourcesTable) do
		if type(s) == "table" then
			if s.active or (tonumber(s.value) or 0) > 0.05 then
				sourcesLive = true
				break
			end
		end
	end
	if not sourcesLive then
		return input, nativeChanged
	end

	-- Rebind listen: mute remapped actions so hardware presses only feed the UI.
	if state.listenSuppress then
		local changed = {}
		for action, _ in pairs(state.map.actions) do
			input[action] = false
			local prev = state.prev[action]
			if prev == nil then prev = false end
			if prev ~= false then
				changed[action] = false
			end
			state.prev[action] = false
		end
		-- Still forward native edges for actions we do not remap (rare).
		for k, v in pairs(nativeChanged) do
			if not state.map.actions[k] then
				changed[k] = v
			end
		end
		return input, changed
	end

	local driving = IsDrivingNow()
	local changed = {}
	-- Keep native edges for actions we do NOT remap
	for k, v in pairs(nativeChanged) do
		if not state.map.actions[k] then
			changed[k] = v
		end
	end

	for action, rule in pairs(state.map.actions) do
		local pressed = false
		local leaf, isDual = ActiveRuleForMode(rule, driving)
		if isDual then
			-- Dual-set: only the active mode's chord/bind (vehicle Weapon Menu ≠ foot stick)
			if leaf then
				pressed = vrmod.bindings.EvalRule(leaf, sourcesTable)
			end
		else
			local rset = rule.set
			local inScope = (rset == nil) or (rset == "driving" and driving) or (rset == "main" and not driving)
			if inScope then
				pressed = vrmod.bindings.EvalRule(rule, sourcesTable)
			end
			-- Out-of-scope remaps force false so shared hardware cannot dual-fire
		end
		input[action] = pressed
		local prev = state.prev[action]
		if prev == nil then prev = false end
		if prev ~= pressed then
			changed[action] = pressed
		end
		state.prev[action] = pressed
	end

	return input, changed
end

-- Poll sources (nil-safe if module old / OpenVR without bridge).
-- OpenXR: VRMOD_GetControllerSources from gVRMod. OpenVR: same export when present.
function vrmod.bindings.GetSources()
	if not VRMOD_GetControllerSources then return nil end
	local ok, src = pcall(VRMOD_GetControllerSources)
	if ok and type(src) == "table" then return src end
	return nil
end

--- True when physical rebind sources are available (OpenXR / bridged OpenVR).
function vrmod.bindings.HasSourcesAPI()
	return isfunction(VRMOD_GetControllerSources)
end

--- Treat as pressed even if isActive is flaky (value still updates on some runtimes).
function vrmod.bindings.SourceIsPressed(s)
	if type(s) ~= "table" then return false end
	local v = tonumber(s.value) or 0
	if s.analog then
		if v >= THRESHOLD then return true end
		return s.pressed == true
	end
	if v >= 0.5 then return true end
	return s.pressed == true
end

--- Snapshot of currently held source ids (for arming listen without eating the UI click).
function vrmod.bindings.SnapshotHeldSources()
	local held = {}
	local src = vrmod.bindings.GetSources()
	if not src then return held end
	for id, s in pairs(src) do
		if type(id) == "string" and vrmod.bindings.SourceIsPressed(s) then
			held[id] = true
		end
	end
	return held
end

--- Rising-edge poll for single-bind listen.
--- held: table mutated across frames (id → true while down).
--- Returns: newPressIds{}, liveCount, hasAPI
function vrmod.bindings.PollListenPresses(held)
	held = held or {}
	if not vrmod.bindings.HasSourcesAPI() then
		return {}, 0, false
	end
	local src = vrmod.bindings.GetSources()
	if not src then
		return {}, 0, true
	end
	local news = {}
	local live = 0
	for id, s in pairs(src) do
		if type(id) == "string" and type(s) == "table" then
			if s.active or vrmod.bindings.SourceIsPressed(s) then
				live = live + 1
			end
			local down = vrmod.bindings.SourceIsPressed(s)
			if down then
				if not held[id] then
					news[#news + 1] = id
					held[id] = true
				end
			else
				held[id] = nil
			end
		end
	end
	return news, live, true
end

--- Currently held source ids (sorted), ignoring an optional set (UI click leftovers).
--- Returns: ids{}, idSet{}, hasAPI
function vrmod.bindings.GetHeldSourceList(ignoreSet)
	ignoreSet = ignoreSet or {}
	if not vrmod.bindings.HasSourcesAPI() then
		return {}, {}, false
	end
	local src = vrmod.bindings.GetSources()
	if not src then
		return {}, {}, true
	end
	local ids, set = {}, {}
	for id, s in pairs(src) do
		if type(id) == "string" and type(s) == "table" and vrmod.bindings.SourceIsPressed(s) then
			if not ignoreSet[id] then
				ids[#ids + 1] = id
				set[id] = true
			end
		end
	end
	table.sort(ids)
	return ids, set, true
end

local function SameIdSet(a, b)
	if not a or not b then return false end
	local na, nb = 0, 0
	for _ in pairs(a) do na = na + 1 end
	for _ in pairs(b) do nb = nb + 1 end
	if na ~= nb then return false end
	for id in pairs(a) do
		if not b[id] then return false end
	end
	return true
end

--- Chord hold-to-save state machine.
--- state: { ignore, chordSet, holdStart }
--- holdSec: seconds to hold a stable simultaneous set (default 3)
--- Returns: statusMsg, savedSources or nil, hasAPI
function vrmod.bindings.TickChordHold(state, holdSec)
	holdSec = holdSec or 3
	state = state or {}
	state.ignore = state.ignore or {}

	-- Clear ignore for buttons that have been released
	local rawHeld = vrmod.bindings.SnapshotHeldSources()
	for id in pairs(state.ignore) do
		if not rawHeld[id] then
			state.ignore[id] = nil
		end
	end

	local ids, set, hasAPI = vrmod.bindings.GetHeldSourceList(state.ignore)
	if not hasAPI then
		return "No controller source API", nil, false
	end

	if #ids < 2 then
		state.chordSet = nil
		state.holdStart = nil
		if #ids == 1 then
			return "Need 2+ held… (only " .. ids[1] .. ")", nil, true
		end
		return "Hold 2+ buttons together for " .. tostring(holdSec) .. "s", nil, true
	end

	if not state.chordSet or not SameIdSet(state.chordSet, set) then
		-- Set changed — restart timer (does not accumulate past presses)
		state.chordSet = set
		state.holdStart = CurTime()
		return "Hold steady: " .. table.concat(ids, " + ") .. "  0.0/" .. holdSec .. "s", nil, true
	end

	local elapsed = CurTime() - (state.holdStart or CurTime())
	if elapsed >= holdSec then
		local out = {}
		for _, id in ipairs(ids) do out[#out + 1] = id end
		return "Chord saved", out, true
	end

	return string.format("Hold steady: %s  %.1f/%ds", table.concat(ids, " + "), elapsed, holdSec), nil, true
end

-- Load on file include
vrmod.bindings.Load()
