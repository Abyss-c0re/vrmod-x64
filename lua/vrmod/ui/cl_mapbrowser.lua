if SERVER then return end
-- =============================================================================
-- Map Browser / New Game — stock GMod New Game parity for VR launcher
--
-- Matches menu CEF New Game (control.NewGame.js + gamesettings):
--   · Map categories + thumbnails + search
--   · Gamemode selector (engine.GetGamemodes, menusystem)
--   · Max players 1…128
--   · Server: hostname, sv_lan, p2p_enabled, p2p_friendsonly (when MP)
--   · Gamemode settings from gamemodes/<gm>/<gm>.txt
--   · Start → maxplayers + gamemode + settings + map (stock order)
--
-- VR  → Cube chrome + panel2vr freefloat
-- Desktop → usable grey frame (no regression)
-- =============================================================================

vrmod = vrmod or {}

local window = nil

local MAX_PLAYERS_OPTS = { 1, 2, 4, 8, 16, 32, 64, 128 }

local function inVR()
	return g_VR and g_VR.active and true or false
end

local function theme()
	local C = vrmod and vrmod.cube
	local T = (C and C.ThemeLive and C.ThemeLive()) or (C and C.Theme) or {}
	return C, T
end

local function font(name, fallback)
	local C = vrmod and vrmod.cube
	if C and C.Font then
		local f = C.Font(name)
		if f then return f end
	end
	return fallback
end

local function col(T, key, r, g, b, a)
	local c = T and T[key]
	if c then return c end
	return Color(r, g, b, a or 255)
end

local function phrase(key, fallback)
	if not key or key == "" then return fallback or "" end
	if language and language.GetPhrase then
		local p = language.GetPhrase(key)
		if p and p ~= key and p ~= "#" .. key then return p end
		p = language.GetPhrase("#" .. key)
		if p and p ~= "#" .. key then return p end
	end
	return fallback or key
end

------------------------------------------------------------------------
-- Catalog
------------------------------------------------------------------------
local function buildSortedMaps()
	local sortedMaps = {}
	local mapCategories = {
		["Age of Chivalry"] = {"aoc_"},
		["INFRA"] = {"infra_"},
		["Alien Swarm"] = {"^asi-", "lobby"},
		["Blade Symphony"] = {"cp_docks", "cp_parkour", "cp_sequence", "cp_terrace", "cp_test", "duel_", "ffa_community", "free_", "practice_box", "tut_training", "lightstyle_test"},
		["Counter-Strike"] = {"ar_", "cs_", "de_", "es_", "fy_", "gd_", "dz_", "training1"},
		["Day Of Defeat"] = {"dod_"},
		["Dino D-Day"] = {"ddd_"},
		["DIPRIP"] = {"de_dam", "dm_city", "dm_refinery", "dm_supermarket", "dm_village", "ur_city", "ur_refinery", "ur_supermarket", "ur_village"},
		["Dystopia"] = {"dys_", "pb_dojo", "pb_rooftop", "pb_round", "pb_urbandome", "sav_dojo6", "varena"},
		["Half-Life 2"] = {"d1_", "d2_", "d3_"},
		["Half-Life 2: Deathmatch"] = {"dm_", "halls3"},
		["Half-Life 2: Episode 1"] = {"ep1_"},
		["Half-Life 2: Episode 2"] = {"ep2_"},
		["Half-Life 2: Episode 3"] = {"ep3_"},
		["Half-Life 2: Lost Coast"] = {"d2_lostcoast"},
		["Half-Life"] = {"^c[%d]a", "^t0a"},
		["Half-Life Deathmatch"] = {"boot_camp", "bounce", "crossfire", "datacore", "frenzy", "lambda_bunker", "rapidcore", "snarkpit", "stalkyard", "subtransit", "undertow"},
		["Insurgency"] = {"ins_"},
		["Left 4 Dead"] = {"l4d_"},
		["Left 4 Dead 2"] = {"^c[%d]m", "^c1[%d]m", "curling_stadium", "tutorial_standards", "tutorial_standards_vs"},
		["Nuclear Dawn"] = {"clocktower", "coast", "downtown", "gate", "hydro", "metro", "metro_training", "oasis", "oilfield", "silo", "sk_metro", "training"},
		["Pirates, Vikings, & Knights II"] = {"bt_", "lts_", "te_", "tw_"},
		["Portal"] = {"escape_", "testchmb_"},
		["Portal 2"] = {"e1912", "^mp_coop_", "^sp_a"},
		["Team Fortress 2"] = {"achievement_", "arena_", "cp_", "ctf_", "itemtest", "koth_", "mvm_", "pl_", "plr_", "rd_", "pd_", "sd_", "tc_", "tr_", "trade_", "pass_"},
		["Zombie Panic! Source"] = {"zpa_", "zpl_", "zpo_", "zps_", "zph_"},
		["Bunny Hop"] = {"bhop_"},
		["Cinema"] = {"cinema_", "theater_"},
		["Climb"] = {"xc_"},
		["Deathrun"] = {"deathrun_", "dr_"},
		["Flood"] = {"fm_"},
		["GMod Tower"] = {"gmt_"},
		["Gun Game"] = {"gg_", "scoutzknivez"},
		["Jailbreak"] = {"ba_", "jail_", "jb_"},
		["Minigames"] = {"mg_"},
		["Pirate Ship Wars"] = {"pw_"},
		["Prop Hunt"] = {"ph_"},
		["Roleplay"] = {"rp_"},
		["Sled Build"] = {"slb_"},
		["Spacebuild"] = {"sb_"},
		["Stop it Slender"] = {"slender_"},
		["Stranded"] = {"gms_"},
		["Surf"] = {"surf_"},
		["The Stalker"] = {"ts_"},
		["Zombie Survival"] = {"zm_", "zombiesurvival_", "zs_"},
		["Sandbox"] = {"^gm_", "^gmod_", "^phys_"},
	}

	local ignore = {"^background", "^devtest", "^ep1_background", "^ep2_background", "^styleguide", "sdk_", "test_", "vst_", "c4a1y", "credits", "d2_coast_02", "d3_c17_02_camera", "ep1_citadel_00_demo", "intro", "test"}
	local gamemodes = engine.GetGamemodes() or {}
	for i = 1, #gamemodes do
		local title = gamemodes[i].title or gamemodes[i].name or "?"
		mapCategories[title] = mapCategories[title] or {}
		local patterns = string.Split(gamemodes[i].maps or "", "|")
		for j = 1, #patterns do
			if patterns[j] == "" then continue end
			patterns[j] = string.lower(patterns[j])
			local found = false
			for k = 1, #mapCategories[title] do
				if mapCategories[title][k] == patterns[j] then found = true break end
			end
			if not found then mapCategories[title][#mapCategories[title] + 1] = patterns[j] end
		end
	end

	local files = file.Find("maps/*", "GAME") or {}
	for i = 1, #files do
		if not string.find(files[i], ".bsp$") then continue end
		local cont = false
		for j = 1, #ignore do
			if string.find(files[i], ignore[j]) then cont = true break end
		end
		if cont then continue end
		local category = "Other"
		for k, v in pairs(mapCategories) do
			for j = 1, #v do
				if string.find(string.lower(files[i]), v[j]) then
					category = k
					break
				end
			end
			if category ~= "Other" then break end
		end
		local index = nil
		for j = 1, #sortedMaps do
			if sortedMaps[j].category == category then index = j break end
		end
		if not index then
			index = #sortedMaps + 1
			sortedMaps[index] = { category = category }
		end
		local name = string.sub(files[i], 1, #files[i] - 4)
		local icon = Material("maps/thumb/" .. name .. ".png")
		if icon:IsError() then icon = Material("materials/gui/noicon.png") end
		sortedMaps[index][#sortedMaps[index] + 1] = {
			filename = files[i],
			name = name,
			icon = icon,
		}
	end
	table.sort(sortedMaps, function(a, b)
		if a.category == "Sandbox" then return true end
		if b.category == "Sandbox" then return false end
		return tostring(a.category) < tostring(b.category)
	end)
	if #sortedMaps == 0 then sortedMaps[1] = { category = "Other" } end
	return sortedMaps
end

local function listMenuGamemodes()
	local out = {}
	local gms = engine.GetGamemodes() or {}
	for _, gm in ipairs(gms) do
		-- menusystem "1" = shows in New Game; always include sandbox/base
		local menusys = gm.menusystem
		local ok = (menusys == nil) or (menusys == true) or (tostring(menusys) == "1")
		if not ok and gm.name ~= "sandbox" and gm.name ~= "base" then continue end
		out[#out + 1] = {
			name = gm.name or "sandbox",
			title = gm.title or gm.name or "?",
			maps = gm.maps or "",
		}
	end
	table.sort(out, function(a, b) return a.title < b.title end)
	if #out == 0 then
		out[1] = { name = "sandbox", title = "Sandbox", maps = "" }
	end
	return out
end

--- Load settings block from gamemodes/<name>/<name>.txt (stock New Game)
local function loadGamemodeSettings(gmName)
	gmName = tostring(gmName or "sandbox")
	local path = "gamemodes/" .. gmName .. "/" .. gmName .. ".txt"
	local raw = file.Read(path, "GAME")
	if not raw or raw == "" then return {} end
	local ok, settings = pcall(util.KeyValuesToTable, raw)
	if not ok or not istable(settings) then return {} end
	-- KeyValuesToTable lowercases keys
	local block = settings.settings or settings.Settings
	if not istable(block) then return {} end
	local list = {}
	for k, v in pairs(block) do
		if not istable(v) then continue end
		local name = v.name or v.Name
		if not name then continue end
		local typ = string.lower(tostring(v.type or v.Type or "checkbox"))
		local def = v.default or v.Default or ""
		local cvar = GetConVar(name)
		local val = cvar and cvar:GetString() or tostring(def)
		list[#list + 1] = {
			name = name,
			text = v.text or v.Text or name,
			help = v.help or v.Help or "",
			type = typ,
			default = tostring(def),
			value = val,
			singleplayer = tobool(v.singleplayer or v.Singleplayer),
			order = tonumber(k) or 999,
		}
	end
	table.sort(list, function(a, b) return a.order < b.order end)
	return list
end

------------------------------------------------------------------------
-- Start game (stock control.NewGame.js order)
------------------------------------------------------------------------
local function startGame(mapName, gmName, maxPlayers, serverOpts, settingRows)
	if not mapName or mapName == "" then return end
	mapName = string.Trim(mapName)
	gmName = gmName or "sandbox"
	maxPlayers = tonumber(maxPlayers) or 1
	serverOpts = serverOpts or {}
	settingRows = settingRows or {}

	RunConsoleCommand("vrmod_autostart", "1")
	RunConsoleCommand("progress_enable")

	-- Apply gamemode first
	RunConsoleCommand("gamemode", gmName)
	RunConsoleCommand("maxplayers", tostring(maxPlayers))

	if maxPlayers > 1 then
		RunConsoleCommand("sv_cheats", "0")
	end

	if serverOpts.hostname and serverOpts.hostname ~= "" then
		RunConsoleCommand("hostname", serverOpts.hostname)
	end
	if serverOpts.sv_lan ~= nil then
		RunConsoleCommand("sv_lan", serverOpts.sv_lan and "1" or "0")
	end
	if serverOpts.p2p_enabled ~= nil then
		RunConsoleCommand("p2p_enabled", serverOpts.p2p_enabled and "1" or "0")
	end
	if serverOpts.p2p_friendsonly ~= nil then
		RunConsoleCommand("p2p_friendsonly", serverOpts.p2p_friendsonly and "1" or "0")
	end

	for _, row in ipairs(settingRows) do
		if not row.name then continue end
		-- Skip SP-only when multiplayer and vice-versa stock-style: show both when SP or flagged
		local show = (maxPlayers <= 1) or (not row.singleplayer) or row.singleplayer
		if not show and maxPlayers > 1 and row.singleplayer then continue end
		local v = row.value
		if row.type == "checkbox" then
			v = tobool(v) and "1" or "0"
		end
		RunConsoleCommand(row.name, tostring(v))
	end

	-- Delay map like stock JS (settings apply first)
	timer.Simple(0.25, function()
		RunConsoleCommand("maxplayers", tostring(maxPlayers))
		RunConsoleCommand("map", mapName)
	end)

	if vrmod.Toast then
		vrmod.Toast(string.format("Starting %s · %s · %sp", mapName, gmName, maxPlayers), 3, "hint")
	end
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
function VRUtilCreateMapBrowserWindow()
	if IsValid(window) then
		window:MakePopup()
		window:SetVisible(true)
		if inVR() and vrmod.cube and vrmod.cube.ApplyDermaSkin then
			vrmod.cube.ApplyDermaSkin(window)
		end
		if inVR() and vrmod.panel2vr and vrmod.panel2vr.ManifestPanel then
			vrmod.panel2vr.ManifestPanel(window, {
				kind = "mainmenu",
				place = "cinema",
				hint = "newgame",
				uid = "p2v_newgame",
			})
		end
		return window
	end

	local sortedMaps = buildSortedMaps()
	local gamemodes = listMenuGamemodes()
	local selectedCategory = 1
	local categoryLists = {}
	local selectedMap = sortedMaps[1] and sortedMaps[1][1] or nil
	local selectedGm = engine.ActiveGamemode and engine.ActiveGamemode() or "sandbox"
	local maxPlayers = 1
	local searchFilter = ""
	local hostname = GetConVar("hostname") and GetConVar("hostname"):GetString() or "Garry's Mod"
	local svLan = GetConVar("sv_lan") and GetConVar("sv_lan"):GetBool() or false
	local p2p = GetConVar("p2p_enabled") and GetConVar("p2p_enabled"):GetBool() or false
	local p2pFriends = GetConVar("p2p_friendsonly") and GetConVar("p2p_friendsonly"):GetBool() or false
	local settingRows = loadGamemodeSettings(selectedGm)
	local settingsHost -- panel rebuilt on gamemode change

	-- Prefer sandbox category if present
	for i, cat in ipairs(sortedMaps) do
		if cat.category == "Sandbox" then selectedCategory = i break end
	end
	if sortedMaps[selectedCategory] and sortedMaps[selectedCategory][1] then
		selectedMap = sortedMaps[selectedCategory][1]
	end

	local WIN_W, WIN_H = inVR() and 1100 or 1000, inVR() and 640 or 560

	window = vgui.Create("DFrame")
	window:SetSize(WIN_W, WIN_H)
	window:Center()
	window:SetDraggable(not inVR())
	window:ShowCloseButton(true)
	window._mapBrowser = true
	window._newGame = true

	if inVR() then
		-- Do NOT MakePopup in VR — steals focus / can pause SP and kill VR input.
		-- panel2vr PaintManual + laser owns interaction.
		window:SetTitle("")
		window:DockPadding(8, 40, 8, 8)
		window:SetVisible(true)
		if window.SetMouseInputEnabled then window:SetMouseInputEnabled(true) end
		if window.SetKeyboardInputEnabled then window:SetKeyboardInputEnabled(false) end
		if window.SetPaintedManually then window:SetPaintedManually(true) end
		if vrmod.VRUnpauseWorld then vrmod.VRUnpauseWorld() end
	else
		window:SetTitle("New Game")
		window:DockPadding(5, 28, 5, 5)
		window:MakePopup()
	end

	function window:Paint(w, h)
		if inVR() then
			local C, T = theme()
			if C and C.DrawChrome then
				C.DrawChrome(0, 0, w, h, "NEW GAME", {
					subtitle = "Map · Mode · Settings",
					pad = 12,
					headerH = 36,
				})
			else
				surface.SetDrawColor(12, 6, 10, 245)
				surface.DrawRect(0, 0, w, h)
				surface.SetDrawColor(196, 30, 58, 255)
				surface.DrawRect(0, 0, w, 4)
				draw.SimpleText("NEW GAME", "DermaLarge", 12, 10, Color(196, 30, 58), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
			end
		else
			surface.SetDrawColor(255, 255, 255, 255)
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(80, 80, 80, 255)
			surface.DrawRect(0, 0, w, 28)
		end
	end

	if inVR() and vrmod.cube and vrmod.cube.ApplyDermaSkin then
		vrmod.cube.ApplyDermaSkin(window)
	end

	------------------------------------------------------------------------
	-- RIGHT: game settings (stock gamesettings column)
	------------------------------------------------------------------------
	local rightW = inVR() and 280 or 260
	local right = vgui.Create("DPanel", window)
	right:SetWide(rightW)
	right:Dock(RIGHT)
	right:DockMargin(inVR() and 8 or 6, inVR() and 4 or 6, 0, 0)
	function right:Paint(w, h)
		if not inVR() then
			surface.SetDrawColor(240, 240, 240, 255)
			surface.DrawRect(0, 0, w, h)
			return
		end
		local _, T = theme()
		surface.SetDrawColor(col(T, "panel", 36, 12, 18, 240))
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(col(T, "crimsonDim", 120, 20, 40, 220))
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end

	local function lbl(parent, text)
		local l = vgui.Create("DLabel", parent)
		l:SetText(text)
		l:SetFont(font("CubeSmall", "DermaDefault"))
		l:Dock(TOP)
		l:DockMargin(6, 6, 6, 2)
		l:SetTextColor(inVR() and Color(255, 230, 236) or Color(40, 40, 40))
		return l
	end

	lbl(right, "Gamemode")
	local gmCombo = vgui.Create("DComboBox", right)
	gmCombo:Dock(TOP)
	gmCombo:DockMargin(6, 0, 6, 4)
	gmCombo:SetTall(28)
	local gmIndex = 1
	for i, gm in ipairs(gamemodes) do
		gmCombo:AddChoice(gm.title, gm.name, gm.name == selectedGm)
		if gm.name == selectedGm then gmIndex = i end
	end
	if #gamemodes > 0 then
		gmCombo:ChooseOptionID(math.Clamp(gmIndex, 1, #gamemodes))
		selectedGm = gamemodes[math.Clamp(gmIndex, 1, #gamemodes)].name
	end

	lbl(right, "Max players")
	local plyCombo = vgui.Create("DComboBox", right)
	plyCombo:Dock(TOP)
	plyCombo:DockMargin(6, 0, 6, 4)
	plyCombo:SetTall(28)
	for _, n in ipairs(MAX_PLAYERS_OPTS) do
		local label = (n == 1) and "Singleplayer" or (n .. " players")
		plyCombo:AddChoice(label, n, n == maxPlayers)
	end
	plyCombo:ChooseOptionID(1)

	-- Multiplayer server block
	local mpBlock = vgui.Create("DPanel", right)
	mpBlock:Dock(TOP)
	mpBlock:SetTall(120)
	mpBlock:DockMargin(0, 4, 0, 0)
	mpBlock:SetPaintBackground(false)
	mpBlock:SetVisible(false)

	lbl(mpBlock, "Server name")
	local hostEntry = vgui.Create("DTextEntry", mpBlock)
	hostEntry:Dock(TOP)
	hostEntry:DockMargin(6, 0, 6, 4)
	hostEntry:SetTall(24)
	hostEntry:SetText(hostname)
	hostEntry:SetUpdateOnType(true)
	hostEntry.OnValueChange = function(_, v) hostname = v end

	local function mkCheck(parent, text, initial, onChange)
		local c = vgui.Create("DCheckBoxLabel", parent)
		c:SetText(text)
		c:SetValue(initial and 1 or 0)
		c:Dock(TOP)
		c:DockMargin(6, 2, 6, 2)
		c:SetTextColor(inVR() and Color(255, 230, 236) or Color(40, 40, 40))
		c.OnChange = function(_, val) onChange(val) end
		return c
	end

	mkCheck(mpBlock, "LAN server", svLan, function(v) svLan = v end)
	mkCheck(mpBlock, "Peer-to-peer", p2p, function(v)
		p2p = v
		if v then svLan = false end
	end)
	mkCheck(mpBlock, "P2P friends only", p2pFriends, function(v) p2pFriends = v end)

	local function refreshMpVis()
		mpBlock:SetVisible(maxPlayers > 1)
		mpBlock:SetTall(maxPlayers > 1 and 130 or 0)
		if IsValid(right) then right:InvalidateLayout(true) end
	end

	plyCombo.OnSelect = function(_, _, _, data)
		maxPlayers = tonumber(data) or 1
		refreshMpVis()
		if IsValid(settingsHost) then settingsHost:Rebuild() end
	end

	-- Gamemode settings scroll
	settingsHost = vgui.Create("DScrollPanel", right)
	settingsHost:Dock(FILL)
	settingsHost:DockMargin(4, 6, 4, 4)

	function settingsHost:Rebuild()
		self:Clear()
		settingRows = loadGamemodeSettings(selectedGm)
		-- Stock CEF: ng-show="MaxPlayers > 1 || s.Singleplayer"
		-- If that filters everything (common), show full list so SP sandbox stays useful.
		local visible = {}
		for _, row in ipairs(settingRows) do
			if (maxPlayers > 1) or row.singleplayer then
				visible[#visible + 1] = row
			end
		end
		if #visible == 0 then visible = settingRows end

		for _, row in ipairs(visible) do
			local label = phrase(row.text, row.text)
			if row.type == "checkbox" then
				local c = vgui.Create("DCheckBoxLabel", self)
				c:SetText(label)
				c:SetTooltip(row.help or "")
				c:SetValue(tobool(row.value) and 1 or 0)
				c:Dock(TOP)
				c:DockMargin(4, 3, 4, 2)
				c:SetTextColor(inVR() and Color(255, 230, 236) or Color(40, 40, 40))
				c.OnChange = function(_, val) row.value = val and "1" or "0" end
			elseif row.type == "numeric" then
				local l = vgui.Create("DLabel", self)
				l:SetText(label)
				l:Dock(TOP)
				l:DockMargin(4, 4, 4, 0)
				l:SetTextColor(inVR() and Color(255, 230, 236) or Color(40, 40, 40))
				local e = vgui.Create("DTextEntry", self)
				e:SetText(tostring(row.value or row.default or "0"))
				e:Dock(TOP)
				e:DockMargin(4, 0, 4, 2)
				e:SetTall(22)
				e:SetNumeric(true)
				e:SetUpdateOnType(true)
				e.OnValueChange = function(_, v) row.value = v end
			else -- text
				local l = vgui.Create("DLabel", self)
				l:SetText(label)
				l:Dock(TOP)
				l:DockMargin(4, 4, 4, 0)
				l:SetTextColor(inVR() and Color(255, 230, 236) or Color(40, 40, 40))
				local e = vgui.Create("DTextEntry", self)
				e:SetText(tostring(row.value or row.default or ""))
				e:Dock(TOP)
				e:DockMargin(4, 0, 4, 2)
				e:SetTall(22)
				e:SetUpdateOnType(true)
				e.OnValueChange = function(_, v) row.value = v end
			end
		end
	end

	gmCombo.OnSelect = function(_, _, _, data)
		selectedGm = data or "sandbox"
		settingsHost:Rebuild()
	end

	settingsHost:Rebuild()
	refreshMpVis()

	local startBtn = vgui.Create("DButton", right)
	startBtn:SetText("")
	startBtn:Dock(BOTTOM)
	startBtn:SetTall(inVR() and 48 or 40)
	startBtn:DockMargin(6, 6, 6, 6)
	function startBtn:DoClick()
		if not selectedMap or not selectedMap.name then return end
		startGame(selectedMap.name, selectedGm, maxPlayers, {
			hostname = hostname,
			sv_lan = svLan,
			p2p_enabled = p2p,
			p2p_friendsonly = p2pFriends,
		}, settingRows)
		if IsValid(window) then window:Close() end
	end
	function startBtn:Paint(w, h)
		local ok = selectedMap ~= nil
		if inVR() then
			local C, T = theme()
			local hot = self.Hovered and ok
			if C and C.DrawSlot then
				C.DrawSlot(0, 0, w, h, nil, hot, ok, ok)
			else
				surface.SetDrawColor(ok and (hot and 100 or 196) or 40, ok and 30 or 10, ok and 58 or 16, 255)
				surface.DrawRect(0, 0, w, h)
			end
			local label = selectedMap and ("START · " .. string.upper(string.sub(selectedMap.name, 1, 16))) or "SELECT MAP"
			draw.SimpleText(label, font("CubeLabel", "Trebuchet24"), w * 0.5, h * 0.5, Color(255, 240, 244), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		else
			surface.SetDrawColor(0, 108, 204, 255)
			surface.DrawRect(0, 0, w, h)
			draw.SimpleText("Start Game", "Trebuchet24", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end

	------------------------------------------------------------------------
	-- LEFT: categories
	------------------------------------------------------------------------
	local DPanel = vgui.Create("DPanel", window)
	DPanel:SetWide(180)
	DPanel:Dock(LEFT)
	DPanel:DockMargin(0, inVR() and 4 or 6, inVR() and 8 or 6, 0)
	function DPanel:Paint(w, h)
		if not inVR() then return end
		local _, T = theme()
		surface.SetDrawColor(col(T, "bgGlass", 22, 10, 16, 230))
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(col(T, "crimsonDim", 120, 20, 40, 220))
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end
	if not inVR() then DPanel:SetPaintBackground(false) end

	local DScrollPanel = vgui.Create("DScrollPanel", DPanel)
	DScrollPanel:Dock(FILL)
	if inVR() then DScrollPanel:DockMargin(4, 4, 4, 4) end

	local catFont = font("CubeSmall", "Trebuchet18")

	for i = 1, #sortedMaps do
		local DButton = DScrollPanel:Add("DButton")
		DButton:SetText("")
		DButton:Dock(TOP)
		DButton:SetTall(inVR() and 28 or 25)
		DButton:DockMargin(0, 0, 0, inVR() and 4 or 5)
		function DButton:Paint(w, h)
			if inVR() then
				local C, T = theme()
				local selected = (selectedCategory == i)
				if C and C.DrawSlot then
					C.DrawSlot(0, 0, w, h, nil, self.Hovered, selected, true)
				else
					surface.SetDrawColor(selected and 100 or 55, selected and 22 or 14, selected and 38 or 24, 250)
					surface.DrawRect(0, 0, w, h)
				end
				draw.SimpleText(sortedMaps[i].category, catFont, 10, h * 0.5, Color(255, 240, 244), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			else
				surface.SetDrawColor(selectedCategory == i and 153 or 221, selectedCategory == i and 204 or 221, 255, 255)
				surface.DrawRect(0, 0, w, h)
				draw.SimpleText(sortedMaps[i].category, "Trebuchet18", 5, 5, Color(85, 85, 85), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
			end
		end
		function DButton:DoClick()
			if categoryLists[selectedCategory] then categoryLists[selectedCategory]:SetVisible(false) end
			selectedCategory = i
			if categoryLists[selectedCategory] then categoryLists[selectedCategory]:SetVisible(true) end
		end
	end

	------------------------------------------------------------------------
	-- CENTER: search + map grid
	------------------------------------------------------------------------
	local center = vgui.Create("DPanel", window)
	center:Dock(FILL)
	center:DockMargin(0, inVR() and 4 or 6, 0, 0)
	center:SetPaintBackground(false)

	local search = vgui.Create("DTextEntry", center)
	search:Dock(TOP)
	search:SetTall(28)
	search:DockMargin(0, 0, 0, 6)
	search:SetPlaceholderText("Search maps…")
	search:SetUpdateOnType(true)

	local mapArea = vgui.Create("DPanel", center)
	mapArea:Dock(FILL)
	mapArea:SetPaintBackground(false)

	local mapNameFont = font("CubeSmall", "DermaDefault")

	for i = 1, #sortedMaps do
		local mapScroll = vgui.Create("DScrollPanel", mapArea)
		mapScroll:Dock(FILL)
		mapScroll:SetVisible(i == selectedCategory)
		function mapScroll:Paint(w, h)
			if not inVR() then return end
			local _, T = theme()
			surface.SetDrawColor(col(T, "panel", 36, 12, 18, 240))
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(col(T, "crimsonDim", 120, 20, 40, 220))
			surface.DrawOutlinedRect(0, 0, w, h, 1)
		end
		categoryLists[#categoryLists + 1] = mapScroll
		local List = vgui.Create("DIconLayout", mapScroll)
		List:Dock(FILL)
		if inVR() then List:DockMargin(6, 6, 6, 6) end
		List:SetSpaceY(inVR() and 6 or 5)
		List:SetSpaceX(inVR() and 6 or 5)

		local function rebuildIcons()
			List:Clear()
			local filt = string.lower(searchFilter or "")
			for j = 1, #sortedMaps[i] do
				local mapEntry = sortedMaps[i][j]
				if filt ~= "" and not string.find(string.lower(mapEntry.name), filt, 1, true) then
					continue
				end
				local ListItem = List:Add("DButton")
				ListItem:SetSize(130, inVR() and 148 or 145)
				ListItem:SetText("")
				ListItem.DoClick = function() selectedMap = mapEntry end
				ListItem.DoDoubleClick = function()
					selectedMap = mapEntry
					startBtn:DoClick()
				end
				function ListItem:Paint(w, h)
					if inVR() then
						local _, T = theme()
						local selected = (selectedMap == mapEntry)
						local hot = self.Hovered or selected
						surface.SetDrawColor(col(T, hot and "btnHover" or "btn", 55, 14, 24, 250))
						surface.DrawRect(0, 0, w, h)
						surface.SetDrawColor(col(T, selected and "crimson" or "crimsonDim", 120, 20, 40, 220))
						surface.DrawOutlinedRect(0, 0, w, h, selected and 3 or 2)
						surface.SetDrawColor(255, 255, 255, 255)
						surface.SetMaterial(mapEntry.icon)
						surface.DrawTexturedRect(4, 4, w - 8, w - 8)
						surface.SetDrawColor(col(T, "bg", 12, 6, 10, 245))
						surface.DrawRect(2, w - 2, w - 4, h - (w - 2))
						draw.SimpleText(mapEntry.name, mapNameFont, w * 0.5, h - 8, Color(255, 240, 244), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
					else
						if selectedMap == mapEntry then
							surface.SetDrawColor(151, 197, 255, 255)
							surface.DrawRect(0, 0, w, h)
						end
						surface.SetDrawColor(255, 255, 255, 255)
						surface.SetMaterial(mapEntry.icon)
						surface.DrawTexturedRect(2, 2, w - 4, w - 4)
						draw.SimpleText(mapEntry.name, "DermaDefault", w / 2, h - 2, Color(0, 0, 0), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
					end
				end
			end
		end
		mapScroll._rebuildIcons = rebuildIcons
		rebuildIcons()
	end

	search.OnValueChange = function(_, v)
		searchFilter = v or ""
		for _, sc in ipairs(categoryLists) do
			if sc._rebuildIcons then sc._rebuildIcons() end
		end
	end

	if inVR() and vrmod.cube and vrmod.cube.ApplyDermaSkin then
		timer.Simple(0, function()
			if IsValid(window) and inVR() then vrmod.cube.ApplyDermaSkin(window) end
		end)
	end

	-- Lift into freefloat cinema in VR (launcher)
	if inVR() and vrmod.panel2vr and vrmod.panel2vr.ManifestPanel then
		timer.Simple(0.05, function()
			if not IsValid(window) then return end
			vrmod.panel2vr.ManifestPanel(window, {
				kind = "mainmenu",
				place = "cinema",
				hint = "newgame",
				uid = "p2v_newgame",
				width = WIN_W,
				height = WIN_H,
			})
		end)
	end

	hook.Add("VRMod_Exit", "vrmod_mapbrowser_skin", function()
		if IsValid(window) and vrmod.cube and vrmod.cube.RestoreDermaSkin then
			vrmod.cube.RestoreDermaSkin(window)
		end
	end)

	window.OnClose = function()
		if vrmod.panel2vr and vrmod.panel2vr.Close then
			pcall(vrmod.panel2vr.Close, "p2v_newgame")
		end
	end

	return window
end

function vrmod.OpenNewGame()
	return VRUtilCreateMapBrowserWindow()
end

concommand.Add("vrmod_mapbrowser", function()
	VRUtilCreateMapBrowserWindow()
end)

concommand.Add("vrmod_newgame", function()
	VRUtilCreateMapBrowserWindow()
end)
