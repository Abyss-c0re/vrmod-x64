if SERVER then return end
-- =============================================================================
-- Cube New Game — pure VR hand surface (NOT Derma/panel2vr)
--
-- Matches stock GMod New Game + multiplayer host options:
--   Maps (categories) · Gamemode · Max players · Hostname · LAN · P2P · Start
-- Layout fits the RT. Laser + trigger. Wrist-dock like settings (faces user).
-- =============================================================================

vrmod = vrmod or {}
g_VR = g_VR or {}

local UID = "vr_newgame"
local open = false
local buttons = {}
local statusMsg, statusUntil = "", 0

-- Wide enough for 3 columns; height fits wrist cinema
local W, H = 720, 640
local livePos, liveAng, liveScale = Vector(4, 5, 6), Angle(0, -90, 55), 0.022
local HEADER, PAD = 64, 10
local COL_CAT, COL_MAP, COL_OPT = 150, 320, 230 -- sum + pads ≈ 720

-- State
local tab = "maps" -- maps | multi
local categories = {} -- { {name=, maps={name,icon}...}, ... }
local catIndex = 1
local mapScroll = 0
local catScroll = 0
local selectedMap = nil
local gamemodes = {}
local gmIndex = 1
local maxPlayersOpts = { 1, 2, 4, 8, 16, 32, 64, 128 }
local maxPlayersIdx = 1
local hostname = "gVRMod"
local svLan = false
local p2p = false
local p2pFriends = false
local optScroll = 0

local MAP_COLS, MAP_ROWS = 3, 4
local MAP_CELL_W, MAP_CELL_H = 96, 108
local VIS_CATS = 10

local function Theme()
	if vrmod.cube and vrmod.cube.ThemeLive then return vrmod.cube.ThemeLive() end
	return {
		bg = Color(12, 6, 10, 250),
		header = Color(196, 30, 58, 255),
		headerDim = Color(80, 12, 24, 255),
		row = Color(40, 14, 20, 245),
		rowHot = Color(90, 22, 36, 255),
		panel = Color(28, 10, 16, 245),
		text = Color(255, 240, 244, 255),
		muted = Color(200, 150, 165, 230),
		hot = Color(255, 70, 100, 255),
		ok = Color(90, 220, 150, 255),
	}
end

local function Font(key)
	if vrmod.cube and vrmod.cube.Font then return vrmod.cube.Font(key) or "DermaDefault" end
	if key == "CubeTitle" then return "DermaLarge" end
	return "DermaDefaultBold"
end

local function WristHand()
	return (vrmod.GetSecondaryHand and vrmod.GetSecondaryHand()) or "left"
end

local function WristPose()
	local wrist = WristHand()
	-- Slightly farther / larger shell so 720 RT is readable
	if isfunction(VRUtilHandMenuPose) then
		return VRUtilHandMenuPose(W, H, 0.022, Vector(5, 5.5, 7), Angle(0, -90, 55), wrist)
	end
	return Vector(5, 5.5, 7), Angle(0, -90, 55), 0.022
end

local function SetStatus(msg, sec)
	statusMsg = tostring(msg or "")
	statusUntil = CurTime() + (sec or 2.5)
end

local function MaxPlayers()
	return maxPlayersOpts[maxPlayersIdx] or 1
end

------------------------------------------------------------------------
-- Catalog (maps + gamemodes)
------------------------------------------------------------------------
local function buildCatalog()
	categories = {}
	local mapCategories = {
		["Sandbox"] = { "^gm_", "^gmod_", "^phys_" },
		["Roleplay"] = { "rp_" },
		["TTT"] = { "ttt_", "gm_ttt" },
		["DarkRP"] = { "rp_downtown", "rp_" },
		["Surf"] = { "surf_" },
		["Bhop"] = { "bhop_" },
		["Deathrun"] = { "deathrun_", "dr_" },
		["Prop Hunt"] = { "ph_" },
		["Zombie Survival"] = { "zm_", "zs_", "zombiesurvival_" },
		["Counter-Strike"] = { "de_", "cs_", "fy_", "ar_" },
		["TF2"] = { "cp_", "ctf_", "pl_", "koth_", "mvm_" },
		["HL2"] = { "d1_", "d2_", "d3_" },
		["Other"] = {},
	}
	local order = {
		"Sandbox", "Roleplay", "TTT", "DarkRP", "Surf", "Bhop", "Deathrun",
		"Prop Hunt", "Zombie Survival", "Counter-Strike", "TF2", "HL2", "Other",
	}
	local byCat = {}
	for _, n in ipairs(order) do byCat[n] = {} end

	local gms = engine.GetGamemodes() or {}
	for _, gm in ipairs(gms) do
		local title = gm.title or gm.name or "?"
		if not byCat[title] then
			byCat[title] = {}
			order[#order + 1] = title
		end
		local pats = string.Split(gm.maps or "", "|")
		mapCategories[title] = mapCategories[title] or {}
		for _, p in ipairs(pats) do
			if p ~= "" then mapCategories[title][#mapCategories[title] + 1] = string.lower(p) end
		end
	end

	local ignore = { "^background", "^devtest", "sdk_", "test_", "credits", "intro" }
	local files = file.Find("maps/*.bsp", "GAME") or {}
	for _, f in ipairs(files) do
		local name = string.gsub(f, "%.bsp$", "")
		local low = string.lower(name)
		local skip = false
		for _, ig in ipairs(ignore) do
			if string.find(low, ig) then skip = true break end
		end
		if skip then continue end
		local cat = "Other"
		for _, cn in ipairs(order) do
			local pats = mapCategories[cn]
			if pats then
				for _, p in ipairs(pats) do
					if p ~= "" and string.find(low, p) then cat = cn break end
				end
			end
			if cat ~= "Other" then break end
		end
		byCat[cat] = byCat[cat] or {}
		local icon = Material("maps/thumb/" .. name .. ".png")
		if icon:IsError() then icon = Material("gui/noicon.png") end
		byCat[cat][#byCat[cat] + 1] = { name = name, icon = icon }
	end

	for _, cn in ipairs(order) do
		local maps = byCat[cn]
		if maps and #maps > 0 then
			table.sort(maps, function(a, b) return a.name < b.name end)
			categories[#categories + 1] = { name = cn, maps = maps }
		end
	end
	if #categories == 0 then
		categories[1] = { name = "Other", maps = { { name = "gm_construct", icon = Material("gui/noicon.png") } } }
	end
	catIndex = 1
	mapScroll = 0
	if categories[1] and categories[1].maps[1] then
		selectedMap = categories[1].maps[1]
	end

	gamemodes = {}
	for _, gm in ipairs(gms) do
		local menusys = gm.menusystem
		local ok = (menusys == nil) or (menusys == true) or (tostring(menusys) == "1")
		if ok or gm.name == "sandbox" then
			gamemodes[#gamemodes + 1] = { name = gm.name or "sandbox", title = gm.title or gm.name or "?" }
		end
	end
	if #gamemodes == 0 then
		gamemodes[1] = { name = "sandbox", title = "Sandbox" }
	end
	table.sort(gamemodes, function(a, b) return a.title < b.title end)
	gmIndex = 1
	local active = engine.ActiveGamemode and engine.ActiveGamemode() or "sandbox"
	for i, g in ipairs(gamemodes) do
		if g.name == active then gmIndex = i break end
	end

	hostname = (GetConVar("hostname") and GetConVar("hostname"):GetString()) or "gVRMod"
	if hostname == "" then hostname = "gVRMod" end
	svLan = GetConVar("sv_lan") and GetConVar("sv_lan"):GetBool() or false
	p2p = GetConVar("p2p_enabled") and GetConVar("p2p_enabled"):GetBool() or false
	p2pFriends = GetConVar("p2p_friendsonly") and GetConVar("p2p_friendsonly"):GetBool() or false
end

local function currentMaps()
	local c = categories[catIndex]
	return (c and c.maps) or {}
end

local function maxMapScroll()
	local n = #currentMaps()
	local vis = MAP_COLS * MAP_ROWS
	return math.max(0, math.ceil(n / MAP_COLS) - MAP_ROWS)
end

------------------------------------------------------------------------
-- Start — shared vrmod.MapStart (same path as classic VR map browser)
------------------------------------------------------------------------
local function startGame()
	if not selectedMap or not selectedMap.name then
		SetStatus("Select a map", 2)
		return
	end
	local mapName = selectedMap.name
	local gm = gamemodes[gmIndex] and gamemodes[gmIndex].name or "sandbox"
	local mp = MaxPlayers()

	local MS = vrmod.MapStart
	if not MS or not MS.StartFromVR then
		-- Fallback: original map browser one-liner
		RunConsoleCommand("vrmod_autostart", "1")
		RunConsoleCommand("changelevel", mapName)
		vrmod.VRNewGame_Close()
		return
	end

	SetStatus("Starting " .. mapName .. "…", 3)
	local ok, msg = MS.StartFromVR(mapName, {
		gamemode = gm,
		maxplayers = mp,
		hostname = hostname ~= "" and hostname or "gVRMod",
		sv_lan = svLan,
		p2p_enabled = p2p,
		p2p_friendsonly = p2pFriends,
		keepVR = true,
		delay = 0.2,
	})
	if not ok then
		SetStatus(msg or "start failed", 3)
	elseif msg and string.find(msg, "unchanged", 1, true) then
		SetStatus(msg, 4)
	end
	vrmod.VRNewGame_Close()
end

------------------------------------------------------------------------
-- Hitboxes
------------------------------------------------------------------------
local function rebuildButtons()
	buttons = {}
	local y0 = HEADER + 8

	-- Close
	buttons[#buttons + 1] = { x = W - 48, y = 12, w = 36, h = 36, kind = "close" }

	-- Tabs
	local tw = 120
	buttons[#buttons + 1] = { x = PAD, y = y0, w = tw, h = 32, kind = "tab", id = "maps", label = "MAPS" }
	buttons[#buttons + 1] = { x = PAD + tw + 6, y = y0, w = tw + 20, h = 32, kind = "tab", id = "multi", label = "MULTIPLAYER" }

	local bodyY = y0 + 40
	local bodyH = H - bodyY - 56

	if tab == "maps" then
		-- Categories
		local cx, cy = PAD, bodyY
		buttons[#buttons + 1] = { x = cx, y = cy, w = 28, h = 28, kind = "cat_scroll", dir = -1 }
		buttons[#buttons + 1] = { x = cx + COL_CAT - 34, y = cy, w = 28, h = 28, kind = "cat_scroll", dir = 1 }
		local catY = cy + 32
		local cats = categories
		for i = 1, VIS_CATS do
			local idx = catScroll + i
			if not cats[idx] then break end
			buttons[#buttons + 1] = {
				x = cx, y = catY + (i - 1) * 34, w = COL_CAT - 8, h = 30,
				kind = "cat", index = idx, label = cats[idx].name,
			}
		end

		-- Maps grid
		local mx0 = PAD + COL_CAT + 6
		local my0 = bodyY + 4
		buttons[#buttons + 1] = { x = mx0, y = bodyY + bodyH - 32, w = 40, h = 28, kind = "map_scroll", dir = -1 }
		buttons[#buttons + 1] = { x = mx0 + 48, y = bodyY + bodyH - 32, w = 40, h = 28, kind = "map_scroll", dir = 1 }
		local maps = currentMaps()
		local start = mapScroll * MAP_COLS
		for row = 0, MAP_ROWS - 1 do
			for col = 0, MAP_COLS - 1 do
				local i = start + row * MAP_COLS + col + 1
				local m = maps[i]
				if not m then break end
				buttons[#buttons + 1] = {
					x = mx0 + col * (MAP_CELL_W + 6),
					y = my0 + row * (MAP_CELL_H + 4),
					w = MAP_CELL_W, h = MAP_CELL_H,
					kind = "map", map = m,
				}
			end
		end

		-- Options column (mode + players always visible)
		local ox = PAD + COL_CAT + COL_MAP + 12
		local oy = bodyY
		buttons[#buttons + 1] = { x = ox, y = oy, w = 36, h = 28, kind = "gm_nav", dir = -1 }
		buttons[#buttons + 1] = { x = ox + COL_OPT - 50, y = oy, w = 36, h = 28, kind = "gm_nav", dir = 1 }
		oy = oy + 56
		buttons[#buttons + 1] = { x = ox, y = oy, w = 36, h = 28, kind = "mp_nav", dir = -1 }
		buttons[#buttons + 1] = { x = ox + COL_OPT - 50, y = oy, w = 36, h = 28, kind = "mp_nav", dir = 1 }
	else
		-- Multiplayer page — full width options
		local ox, oy = PAD, bodyY
		local rowH = 40
		-- Max players
		buttons[#buttons + 1] = { x = ox, y = oy, w = 44, h = 32, kind = "mp_nav", dir = -1 }
		buttons[#buttons + 1] = { x = ox + 200, y = oy, w = 44, h = 32, kind = "mp_nav", dir = 1 }
		oy = oy + rowH + 8
		-- Gamemode
		buttons[#buttons + 1] = { x = ox, y = oy, w = 44, h = 32, kind = "gm_nav", dir = -1 }
		buttons[#buttons + 1] = { x = ox + 280, y = oy, w = 44, h = 32, kind = "gm_nav", dir = 1 }
		oy = oy + rowH + 12
		if MaxPlayers() > 1 then
			buttons[#buttons + 1] = { x = ox, y = oy, w = 28, h = 28, kind = "toggle", id = "lan", on = svLan }
			oy = oy + 36
			buttons[#buttons + 1] = { x = ox, y = oy, w = 28, h = 28, kind = "toggle", id = "p2p", on = p2p }
			oy = oy + 36
			buttons[#buttons + 1] = { x = ox, y = oy, w = 28, h = 28, kind = "toggle", id = "p2pf", on = p2pFriends }
			oy = oy + 40
			-- Hostname cycle presets (keyboard later)
			buttons[#buttons + 1] = { x = ox, y = oy, w = 200, h = 32, kind = "host_cycle" }
		end
	end

	-- Start
	buttons[#buttons + 1] = {
		x = W - 200 - PAD, y = H - 48, w = 200, h = 40,
		kind = "start",
	}
end

------------------------------------------------------------------------
-- Paint (must never error mid-RT — that causes End2D/PopRT leaks + flicker)
------------------------------------------------------------------------
local function colRGBA(c, fallback)
	if IsColor and IsColor(c) then return c.r, c.g, c.b, c.a or 255 end
	if istable(c) and c.r then return c.r, c.g, c.b, c.a or 255 end
	if fallback then return colRGBA(fallback, nil) end
	return 255, 255, 255, 255
end

local function setCol(c)
	local r, g, b, a = colRGBA(c)
	surface.SetDrawColor(r, g, b, a)
end

local function paintInner()
	local T = Theme()
	local focused = g_VR.menuFocus == UID
	local mx, my = g_VR.menuCursorX or -1, g_VR.menuCursorY or -1
	rebuildButtons()

	if vrmod.cube and vrmod.cube.DrawChrome then
		vrmod.cube.DrawChrome(0, 0, W, H, "NEW GAME", {
			subtitle = "CUBE · MAPS · MODE · MULTIPLAYER",
			headerH = HEADER,
		})
	else
		setCol(T.bg)
		surface.DrawRect(0, 0, W, H)
		setCol(T.header)
		surface.DrawRect(0, 0, W, 5)
		draw.SimpleText("NEW GAME", Font("CubeTitle"), PAD, 14, T.header)
	end

	local function hot(b)
		return focused and mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h
	end

	local function drawBtn(b, label, primary)
		local hov = hot(b)
		if vrmod.cube and vrmod.cube.DrawSlot then
			vrmod.cube.DrawSlot(b.x, b.y, b.w, b.h, nil, hov, primary, true)
		else
			setCol(hov and T.rowHot or T.row)
			surface.DrawRect(b.x, b.y, b.w, b.h)
			if primary or hov then
				setCol(T.header)
				surface.DrawRect(b.x, b.y, 4, b.h)
			end
		end
		if label then
			draw.SimpleText(label, Font("CubeLabel") or "DermaDefaultBold",
				b.x + b.w * 0.5, b.y + b.h * 0.5, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end

	for _, b in ipairs(buttons) do
		if b.kind == "close" then
			drawBtn(b, "X", true)
		elseif b.kind == "tab" then
			drawBtn(b, b.label, tab == b.id)
		elseif b.kind == "cat" then
			drawBtn(b, nil, b.index == catIndex)
			local name = b.label or ""
			if #name > 14 then name = string.sub(name, 1, 13) .. "…" end
			draw.SimpleText(name, "DermaDefault", b.x + 10, b.y + b.h * 0.5, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		elseif b.kind == "cat_scroll" or b.kind == "map_scroll" then
			drawBtn(b, b.dir < 0 and "▲" or "▼", false)
		elseif b.kind == "gm_nav" or b.kind == "mp_nav" then
			drawBtn(b, b.dir < 0 and "◀" or "▶", false)
		elseif b.kind == "map" then
			local sel = selectedMap and b.map and selectedMap.name == b.map.name
			local hov = hot(b)
			-- Parentheses required: "hov or sel and X" is wrong and passes bool to SetDrawColor
			local bg = (hov or sel) and T.rowHot or T.panel
			setCol(bg)
			surface.DrawRect(b.x, b.y, b.w, b.h)
			setCol(sel and T.header or T.headerDim)
			surface.DrawOutlinedRect(b.x, b.y, b.w, b.h, sel and 3 or 1)
			if b.map and b.map.icon and not b.map.icon:IsError() then
				surface.SetDrawColor(255, 255, 255, 255)
				surface.SetMaterial(b.map.icon)
				surface.DrawTexturedRect(b.x + 4, b.y + 4, b.w - 8, b.w - 8)
			end
			local nm = b.map and b.map.name or "?"
			if #nm > 12 then nm = string.sub(nm, 1, 11) .. "…" end
			draw.SimpleText(nm, "DermaDefault", b.x + b.w * 0.5, b.y + b.h - 10, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		elseif b.kind == "toggle" then
			setCol(b.on and T.header or T.row)
			surface.DrawRect(b.x, b.y, b.w, b.h)
			setCol(T.header)
			surface.DrawOutlinedRect(b.x, b.y, b.w, b.h, 1)
			if b.on then
				draw.SimpleText("✓", "DermaDefaultBold", b.x + b.w * 0.5, b.y + b.h * 0.5, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		elseif b.kind == "host_cycle" then
			drawBtn(b, nil, false)
			local hn = hostname
			if #hn > 18 then hn = string.sub(hn, 1, 17) .. "…" end
			draw.SimpleText(hn, "DermaDefault", b.x + 10, b.y + b.h * 0.5, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		elseif b.kind == "start" then
			drawBtn(b, selectedMap and ("START  " .. string.upper(string.sub(selectedMap.name, 1, 14))) or "SELECT MAP", true)
		end
	end

	local bodyY = HEADER + 48
	if tab == "maps" then
		local ox = PAD + COL_CAT + COL_MAP + 12
		local gm = gamemodes[gmIndex]
		draw.SimpleText("MODE", "DermaDefault", ox + 40, bodyY + 6, T.muted)
		draw.SimpleText(gm and gm.title or "?", Font("CubeLabel") or "DermaDefaultBold",
			ox + 40, bodyY + 28, T.text)
		draw.SimpleText("PLAYERS", "DermaDefault", ox + 40, bodyY + 62, T.muted)
		local mp = MaxPlayers()
		draw.SimpleText(mp == 1 and "Singleplayer" or (mp .. " players"), Font("CubeLabel") or "DermaDefaultBold",
			ox + 40, bodyY + 84, T.text)
		if mp > 1 then
			draw.SimpleText("→ Multiplayer tab for LAN/P2P", "DermaDefault", ox, bodyY + 130, T.muted)
		end
		draw.SimpleText(string.format("maps %d", #currentMaps()), "DermaDefault",
			PAD + COL_CAT + 100, H - 40, T.muted)
	else
		local oy = bodyY
		draw.SimpleText("MAX PLAYERS", "DermaDefault", PAD + 56, oy + 8, T.muted)
		local mp = MaxPlayers()
		draw.SimpleText(mp == 1 and "Singleplayer" or (tostring(mp) .. " players"),
			Font("CubeLabel") or "DermaDefaultBold", PAD + 56, oy + 28, T.text)
		oy = oy + 48
		draw.SimpleText("GAMEMODE", "DermaDefault", PAD + 56, oy + 8, T.muted)
		draw.SimpleText(gamemodes[gmIndex] and gamemodes[gmIndex].title or "?",
			Font("CubeLabel") or "DermaDefaultBold", PAD + 56, oy + 28, T.text)
		oy = oy + 56
		if MaxPlayers() > 1 then
			draw.SimpleText("LAN server", "DermaDefault", PAD + 40, oy + 6, T.text)
			oy = oy + 36
			draw.SimpleText("Peer-to-peer (P2P)", "DermaDefault", PAD + 40, oy + 6, T.text)
			oy = oy + 36
			draw.SimpleText("P2P friends only", "DermaDefault", PAD + 40, oy + 6, T.text)
			oy = oy + 40
			draw.SimpleText("Server name (tap to cycle)", "DermaDefault", PAD, oy - 4, T.muted)
		else
			draw.SimpleText("Set players > 1 for multiplayer host options", "DermaDefault", PAD, oy + 8, T.muted)
		end
	end

	if statusMsg ~= "" and CurTime() < statusUntil then
		draw.SimpleText(statusMsg, Font("CubeLabel") or "DermaDefaultBold", PAD, H - 40, T.ok)
	end

	if focused and mx >= 0 and my >= 0 then
		setCol(T.hot)
		surface.DrawRect(mx - 2, my - 12, 4, 24)
		surface.DrawRect(mx - 12, my - 2, 24, 4)
	end
end

local function paint()
	if not open or not (g_VR and g_VR.menus and g_VR.menus[UID]) then return end
	local m = g_VR.menus[UID]
	-- Steady paint: no alwaysRedraw thrash (was fighting RT + hand anchor → flicker)
	m.alwaysRedraw = false
	m.paintInterval = 0
	m.paintIntervalFocused = 0
	m.dirty = true

	local started = false
	if isfunction(VRUtilMenuRenderStart) then
		started = VRUtilMenuRenderStart(UID) and true or false
	end
	if not started then return end

	local ok, err = pcall(paintInner)
	if isfunction(VRUtilMenuRenderEnd) then
		pcall(VRUtilMenuRenderEnd)
	end
	if not ok and vrmod.logger then
		vrmod.logger.Warn("[newgame] paint: %s", tostring(err))
	end
end

------------------------------------------------------------------------
-- Input
------------------------------------------------------------------------
local HOST_PRESETS = { "gVRMod", "Cube Server", "Sandbox Night", "My Server" }

local function activateAt(mx, my)
	for _, b in ipairs(buttons) do
		if mx < b.x or mx > b.x + b.w or my < b.y or my > b.y + b.h then continue end
		if b.kind == "close" then
			vrmod.VRNewGame_Close()
			return
		elseif b.kind == "tab" then
			tab = b.id
			return
		elseif b.kind == "cat" then
			catIndex = b.index
			mapScroll = 0
			local maps = currentMaps()
			if maps[1] then selectedMap = maps[1] end
			return
		elseif b.kind == "cat_scroll" then
			catScroll = math.Clamp(catScroll + b.dir, 0, math.max(0, #categories - VIS_CATS))
			return
		elseif b.kind == "map_scroll" then
			mapScroll = math.Clamp(mapScroll + b.dir, 0, maxMapScroll())
			return
		elseif b.kind == "map" then
			selectedMap = b.map
			return
		elseif b.kind == "gm_nav" then
			gmIndex = gmIndex + b.dir
			if gmIndex < 1 then gmIndex = #gamemodes end
			if gmIndex > #gamemodes then gmIndex = 1 end
			return
		elseif b.kind == "mp_nav" then
			maxPlayersIdx = maxPlayersIdx + b.dir
			if maxPlayersIdx < 1 then maxPlayersIdx = #maxPlayersOpts end
			if maxPlayersIdx > #maxPlayersOpts then maxPlayersIdx = 1 end
			return
		elseif b.kind == "toggle" then
			if b.id == "lan" then
				svLan = not svLan
				if svLan then p2p = false end
			elseif b.id == "p2p" then
				p2p = not p2p
				if p2p then svLan = false end
			elseif b.id == "p2pf" then
				p2pFriends = not p2pFriends
			end
			return
		elseif b.kind == "host_cycle" then
			local found = 1
			for i, h in ipairs(HOST_PRESETS) do
				if h == hostname then found = i break end
			end
			hostname = HOST_PRESETS[(found % #HOST_PRESETS) + 1]
			return
		elseif b.kind == "start" then
			startGame()
			return
		end
	end
end

------------------------------------------------------------------------
-- Open / close
------------------------------------------------------------------------
function vrmod.VRNewGame_Close()
	if not open then
		if isfunction(VRUtilMenuClose) and g_VR and g_VR.menus and g_VR.menus[UID] then
			g_VR.menus[UID].closeFunc = nil
			VRUtilMenuClose(UID)
		end
		return
	end
	open = false
	hook.Remove("PreRender", "vr_newgame_paint")
	hook.Remove("VRMod_Input", "vr_newgame_input")
	hook.Remove("VRMod_Exit", "vr_newgame_exit")
	if g_VR and g_VR.menus and g_VR.menus[UID] then
		g_VR.menus[UID].closeFunc = nil
	end
	if isfunction(VRUtilMenuClose) then VRUtilMenuClose(UID) end
end

function vrmod.VRNewGame_IsOpen()
	return open
end

function vrmod.VRNewGame_Open()
	if not (g_VR and g_VR.active) then
		-- Desktop: stock-style Derma browser
		if isfunction(VRUtilCreateMapBrowserWindow) then
			VRUtilCreateMapBrowserWindow()
		end
		return
	end
	if vrmod.VRUnpauseWorld then vrmod.VRUnpauseWorld() end
	if open and g_VR.menus and g_VR.menus[UID] then
		g_VR.menus[UID].dirty = true
		return
	end
	if not isfunction(VRUtilMenuOpen) then return end

	buildCatalog()
	tab = "maps"
	mapScroll = 0
	catScroll = 0

	-- Close competing hand shells
	if g_VR.menus then
		for _, uid in ipairs({ "miscmenu", "cube_settings", "bindings_panel", "actions_panel" }) do
			if g_VR.menus[uid] and isfunction(VRUtilMenuClose) then
				g_VR.menus[uid].closeFunc = nil
				VRUtilMenuClose(uid)
			end
		end
	end

	open = true
	livePos, liveAng, liveScale = WristPose()
	local wrist = WristHand()

	VRUtilMenuOpen(UID, W, H, nil, true, livePos, liveAng, liveScale, true, function()
		open = false
		hook.Remove("PreRender", "vr_newgame_paint")
		hook.Remove("VRMod_Input", "vr_newgame_input")
	end)

	if not (g_VR.menus and g_VR.menus[UID]) then
		open = false
		return
	end

	local sm = g_VR.menus[UID]
	sm.cubeMenu = true
	sm.grabbable = true
	sm.resizable = true
	sm.attachment = true
	sm.freeFloat = false
	sm.attachHand = wrist
	sm.persistOpen = true
	sm.keepAlive = true
	sm.alwaysRedraw = false
	sm.paintInterval = 0
	sm.paintIntervalFocused = 0
	sm.pos = livePos
	sm.ang = liveAng
	sm.scale = liveScale
	sm.baseScale = liveScale
	if vrmod.MenuApplyHandAnchor then
		vrmod.MenuApplyHandAnchor(sm, liveScale, livePos, liveAng, wrist)
	end

	pcall(function() RunConsoleCommand("vrmod_laserpointer", "1") end)
	if vrmod.Toast then
		vrmod.Toast("New Game — laser + trigger · Multiplayer tab", 4, "hint")
	end

	local lastAnchor = 0
	paint()
	hook.Add("PreRender", "vr_newgame_paint", function()
		if not open then
			hook.Remove("PreRender", "vr_newgame_paint")
			return
		end
		if not (g_VR.menus and g_VR.menus[UID]) then
			open = false
			return
		end
		local m = g_VR.menus[UID]
		-- Re-anchor at most ~10Hz (every-frame anchor jitters → flicker)
		local now = CurTime()
		if not m.grabHand and not m.freeFloat and vrmod.MenuApplyHandAnchor and (now - lastAnchor) > 0.1 then
			lastAnchor = now
			livePos, liveAng, liveScale = WristPose()
			vrmod.MenuApplyHandAnchor(m, liveScale, livePos, liveAng, WristHand())
		end
		paint()
	end)

	hook.Add("VRMod_Input", "vr_newgame_input", function(action, pressed)
		if not open then return end
		if pressed and (vrmod.IsMenuCloseAction and vrmod.IsMenuCloseAction(action)) then
			vrmod.VRNewGame_Close()
			return
		end
		if g_VR.menus and g_VR.menus[UID] then g_VR.menus[UID].dirty = true end
		if not pressed then return end
		if g_VR.menuFocus ~= UID then return end
		if not (vrmod.IsMenuPrimaryClick and vrmod.IsMenuPrimaryClick(action)) then return end
		activateAt(g_VR.menuCursorX or 0, g_VR.menuCursorY or 0)
	end)

	hook.Add("VRMod_Exit", "vr_newgame_exit", function()
		vrmod.VRNewGame_Close()
	end)
end

-- Public API used by hub / quick menu
function vrmod.OpenNewGame()
	vrmod.VRNewGame_Open()
end

concommand.Add("vrmod_newgame", function()
	if vrmod.OpenNewGameUnpaused then
		vrmod.OpenNewGameUnpaused()
	else
		vrmod.VRNewGame_Open()
	end
end)
