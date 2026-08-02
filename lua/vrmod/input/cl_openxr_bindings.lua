-- OpenXR controller binding layer (SteamVR binding UI replacement).
-- Maps physical controller sources → logical VRMod boolean actions, including chords.
-- Analogs (sticks/triggers as vector1/2) stay on native OpenXR actions.

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
		-- mode "any" = OR of sources; "all" = AND (chord)
		actions = {
			-- On foot (/actions/main)
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

function vrmod.bindings.SetActionBinding(action, sources, mode, set)
	if not action or action == "" then return end
	sources = sources or {}
	if type(sources) == "string" then sources = { sources } end
	local prev = state.map.actions[action]
	state.map.actions[action] = {
		sources = sources,
		mode = (mode == "all") and "all" or "any",
		set = NormalizeSet(action, set or (prev and prev.set) or nil),
	}
	state.prev[action] = nil
end

function vrmod.bindings.ClearActionBinding(action)
	state.map.actions[action] = nil
	state.prev[action] = nil
end

function vrmod.bindings.ListLogicalActions()
	-- Stable list for the editor UI
	return {
		{ id = "boolean_primaryfire", label = "Primary Fire" },
		{ id = "boolean_secondaryfire", label = "Secondary Fire" },
		{ id = "boolean_jump", label = "Jump" },
		{ id = "boolean_crouch", label = "Crouch" },
		{ id = "boolean_use", label = "Use" },
		{ id = "boolean_spawnmenu", label = "Spawn Menu" },
		{ id = "boolean_changeweapon", label = "Weapon Menu" },
		{ id = "boolean_reload", label = "Reload" },
		{ id = "boolean_sprint", label = "Sprint" },
		{ id = "boolean_flashlight", label = "Flashlight" },
		{ id = "boolean_left_pickup", label = "Left Pickup / Grip" },
		{ id = "boolean_right_pickup", label = "Right Pickup / Grip" },
		{ id = "boolean_teleport", label = "Teleport" },
		{ id = "boolean_undo", label = "Undo" },
		{ id = "boolean_chat", label = "Chat / Zoom" },
		{ id = "boolean_menucontext", label = "Context Menu" },
		{ id = "boolean_walkkey", label = "Walk Key" },
		{ id = "boolean_handbrake", label = "Driving: Handbrake" },
		{ id = "boolean_turbo", label = "Driving: Turbo" },
		{ id = "boolean_exit", label = "Driving: Exit" },
		{ id = "boolean_signal_left", label = "Driving: Signal Left" },
		{ id = "boolean_signal_right", label = "Driving: Signal Right" },
		{ id = "boolean_switch_weapon", label = "Driving: Switch Weapon" },
		{ id = "boolean_alt_turret", label = "Driving: Alt Turret" },
		{ id = "boolean_turret", label = "Driving: Turret" },
		{ id = "boolean_horn", label = "Driving: Horn" },
		{ id = "boolean_shift_up", label = "Driving: Shift Up" },
		{ id = "boolean_shift_down", label = "Driving: Shift Down" },
		{ id = "boolean_lights", label = "Driving: Lights" },
		{ id = "boolean_siren", label = "Driving: Siren" },
		{ id = "boolean_toggle_engine", label = "Driving: Toggle Engine" },
	}
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

function vrmod.bindings.FormatRule(rule)
	if not rule or not rule.sources or #rule.sources == 0 then return "(unbound)" end
	local sep = (rule.mode == "all") and " + " or " | "
	local txt = table.concat(rule.sources, sep) .. (rule.mode == "all" and "  [chord]" or "")
	if rule.set == "main" then txt = txt .. "  [on foot]"
	elseif rule.set == "driving" then txt = txt .. "  [driving]"
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

-- Poll sources (nil-safe if module old)
function vrmod.bindings.GetSources()
	if not VRMOD_GetControllerSources then return nil end
	local ok, src = pcall(VRMOD_GetControllerSources)
	if ok and type(src) == "table" then return src end
	return nil
end

-- Load on file include
vrmod.bindings.Load()
