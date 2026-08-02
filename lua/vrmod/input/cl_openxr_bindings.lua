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
-- Face buttons share hardware across sets — without set scoping, right stick click would
-- open the weapon menu *and* fire the turret while driving.
local function DefaultMap()
	return {
		version = 2,
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
			boolean_changeweapon     = { sources = { "right_stick_click" }, mode = "any", set = "main" },
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
	boolean_sprint = true, boolean_changeweapon = true, boolean_teleport = true,
	boolean_undo = true, boolean_chat = true, boolean_menucontext = true, boolean_walkkey = true,
}

local function NormalizeSet(action, set)
	if set == "main" or set == "driving" then return set end
	if DRIVING_ACTION_IDS[action] then return "driving" end
	if MAIN_ONLY_ACTION_IDS[action] then return "main" end
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

--- Restore one action to Quest gold default (or clear if no default).
function vrmod.bindings.RestoreActionDefault(action)
	if not action or action == "" then return end
	local def = DefaultMap().actions[action]
	if def then
		vrmod.bindings.SetActionBinding(action, def.sources, def.mode, def.set)
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
		if type(rule) == "table" and type(rule.sources) == "table" then
			merged.actions[action] = {
				sources = rule.sources,
				mode = (rule.mode == "all") and "all" or "any",
				set = NormalizeSet(action, rule.set),
			}
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
	state.map = DefaultMap()
	state.prev = {}
	vrmod.bindings.Save()
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
	state.map.actions[action] = {
		sources = src,
		mode = m,
		set = NormalizeSet(action, set or (prev and prev.set) or nil),
	}
	state.prev[action] = nil
	return warnings
end

function vrmod.bindings.ClearActionBinding(action)
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
	return {
		{ id = "boolean_primaryfire", label = "Primary Fire", group = "main" },
		{ id = "boolean_secondaryfire", label = "Secondary Fire", group = "main" },
		{ id = "boolean_left_primaryfire", label = "Left Primary Fire", group = "main" },
		{ id = "boolean_jump", label = "Jump", group = "main" },
		{ id = "boolean_crouch", label = "Crouch", group = "main" },
		{ id = "boolean_use", label = "Use", group = "main" },
		{ id = "boolean_spawnmenu", label = "Spawn Menu", group = "both" },
		{ id = "boolean_changeweapon", label = "Weapon Menu", group = "main" },
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
	if s.pressed ~= nil then return s.pressed end
	if s.analog then return (s.value or 0) >= THRESHOLD end
	return (s.value or 0) >= 0.5
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

function vrmod.bindings.FormatRule(rule, useLabels)
	if not rule or not rule.sources or #rule.sources == 0 then return "(unbound)" end
	local parts = {}
	for _, id in ipairs(rule.sources) do
		parts[#parts + 1] = (useLabels ~= false and vrmod.bindings.SourceLabel and vrmod.bindings.SourceLabel(id)) or id
	end
	local sep = (rule.mode == "all") and " + " or " | "
	local txt = table.concat(parts, sep)
	if rule.mode == "all" then txt = txt .. "  [chord]" end
	if rule.set == "main" then txt = txt .. "  [on foot]"
	elseif rule.set == "driving" then txt = txt .. "  [vehicle]"
	end
	return txt
end

local function IsDrivingNow()
	return g_VR and g_VR.vehicle and g_VR.vehicle.driving
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
	local sourcesLive = false
	for _, s in pairs(sourcesTable) do
		if type(s) == "table" and s.active then
			sourcesLive = true
			break
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
		local rset = rule.set
		local inScope = (rset == nil) or (rset == "driving" and driving) or (rset == "main" and not driving)
		local pressed = false
		if inScope then
			pressed = vrmod.bindings.EvalRule(rule, sourcesTable)
		end
		-- Out-of-scope remaps force false so shared hardware cannot dual-fire
		-- (e.g. stick click → weapon menu while driving).
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

-- Load on file include
vrmod.bindings.Load()
