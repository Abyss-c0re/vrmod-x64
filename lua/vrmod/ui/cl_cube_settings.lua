if SERVER then return end
-- =============================================================================
-- Cube Settings (VR hand panel)
-- Data SoT: vrmod.SettingsCatalog (shared with desktop Derma menu)
-- Path: VRUtilMenuOpen + PreRender paint + VRMod_Input hit boxes
-- =============================================================================

vrmod = vrmod or {}

local UID = "cube_settings"
local open = false
local category = 1
local rowScroll = 0
local liveScale = 0.025
local livePos, liveAng = Vector(2.5, 3, 4), Angle(0, -90, 55)

-- Color editor (same cvars / "r,g,b,a" as Derma DColorMixer)
local colorEdit = nil -- { cvar, label, col = Color }

local W, H = 560, 640
local HEADER = 56
local TAB_H = 36
local PAD = 12
local ROW_H = 44
local FOOTER = 52
local VISIBLE_ROWS = 8

--- Live density → row/header sizes (Theme density switch must visibly change settings UI)
local function ApplyDensityLayout()
	local M = vrmod.cube and vrmod.cube.Metrics and vrmod.cube.Metrics()
	if not M then return end
	PAD = M.pad
	ROW_H = M.row
	HEADER = math.max(48, M.headerH + 4)
	TAB_H = math.max(28, math.floor(M.row * 0.72))
	FOOTER = math.max(44, M.footerH + 24)
	local y0 = HEADER + 80
	VISIBLE_ROWS = math.Clamp(math.floor((H - y0 - FOOTER) / (ROW_H + 4)), 5, 14)
end

-- Palette matches classic Derma mixer presets + common VR pointer colors
local COLOR_PALETTE = {
	Color(255, 0, 0, 255),
	Color(255, 128, 0, 255),
	Color(255, 255, 0, 255),
	Color(0, 255, 0, 255),
	Color(0, 255, 255, 255),
	Color(0, 128, 255, 255),
	Color(0, 0, 255, 255),
	Color(255, 0, 255, 255),
	Color(255, 255, 255, 255),
	Color(0, 0, 0, 255),
	Color(255, 70, 100, 255),
	Color(196, 30, 58, 255),
}

local function WristHand()
	return (vrmod.GetSecondaryHand and vrmod.GetSecondaryHand()) or "left"
end

local function WristPose()
	local wrist = WristHand()
	if isfunction(VRUtilHandMenuPose) then
		return VRUtilHandMenuPose(W, H, 0.025, Vector(2.5, 3.5, 4), Angle(0, -90, 55), wrist)
	end
	return Vector(2.5, 3, 4), Angle(0, -90, 55), 0.025
end

-- Live theme from Cube framework (Settings → Theme applies to all menus)
local function Theme()
	if vrmod.cube and vrmod.cube.ThemeLive then
		return vrmod.cube.ThemeLive()
	end
	return vrmod.cube and vrmod.cube.Theme or {
		bg = Color(12, 6, 10, 250),
		header = Color(196, 30, 58, 255),
		headerDim = Color(80, 12, 24, 255),
		row = Color(40, 14, 20, 245),
		rowHot = Color(90, 22, 36, 255),
		text = Color(255, 240, 244, 255),
		muted = Color(200, 150, 165, 230),
		hot = Color(255, 70, 100, 255),
		ok = Color(90, 220, 150, 255),
		off = Color(70, 20, 30, 255),
	}
end

local function Catalog()
	-- Live catalog (Quick Menu rows reflect current layout labels)
	if vrmod.GetSettingsCatalog then
		return vrmod.GetSettingsCatalog()
	end
	return vrmod.SettingsCatalog or {}
end

local function getBool(name, default)
	local c = GetConVar(name)
	if c then return c:GetBool() end
	return default
end

local function getFloat(name, default)
	local c = GetConVar(name)
	if c then return c:GetFloat() end
	return default
end

local function getInt(name, default)
	local c = GetConVar(name)
	if c then return c:GetInt() end
	return default
end

local function setBool(name, v)
	if vrmod.SettingsSetBool then
		vrmod.SettingsSetBool(name, v)
		return
	end
	local c = GetConVar(name)
	if c then c:SetInt(v and 1 or 0) end
	RunConsoleCommand(name, v and "1" or "0")
	if name == "vrmod_hud" and vrmod.RefreshHUD then
		vrmod.RefreshHUD()
	end
end

local function setFloat(name, v)
	if vrmod.SettingsSetFloat then
		vrmod.SettingsSetFloat(name, v)
	else
		local c = GetConVar(name)
		if c then c:SetFloat(tonumber(v) or 0) else RunConsoleCommand(name, tostring(v)) end
	end
end

local function setInt(name, v)
	if vrmod.SettingsSetInt then
		vrmod.SettingsSetInt(name, v)
	else
		local c = GetConVar(name)
		if c then c:SetInt(math.floor(tonumber(v) or 0)) else RunConsoleCommand(name, tostring(math.floor(tonumber(v) or 0))) end
	end
end

local function closeCtx()
	return {
		close = function()
			vrmod.CubeSettings_Close()
		end,
	}
end

local function runRowAction(row)
	if row.cmd then
		RunConsoleCommand(row.cmd)
		return
	end
	if row.action_id and vrmod.SettingsRunAction then
		vrmod.SettingsRunAction(row.action_id, closeCtx())
	end
end

local buttons = {}

local function catRows()
	local cats = Catalog()
	local cat = cats[category]
	return (cat and cat.rows) or {}
end

local function maxScroll()
	return math.max(0, #catRows() - VISIBLE_ROWS)
end

local function rebuildButtons()
	ApplyDensityLayout()
	buttons = {}
	local cats = Catalog()
	-- Close
	buttons[#buttons + 1] = { x = W - 52, y = 8, w = 40, h = 36, kind = "close" }
	-- Tabs (scrollable strip if many)
	local n = #cats
	if n < 1 then return end
	local tabW = math.max(48, (W - PAD * 2) / math.min(n, 6))
	local tabStart = 1
	-- show all tabs in 2 rows if many
	local tabsPerRow = math.min(n, 5)
	tabW = (W - PAD * 2) / tabsPerRow
	for i = 1, n do
		local col = (i - 1) % tabsPerRow
		local row = math.floor((i - 1) / tabsPerRow)
		buttons[#buttons + 1] = {
			x = PAD + col * tabW,
			y = HEADER + row * (TAB_H + 2),
			w = tabW - 3,
			h = TAB_H,
			kind = "tab",
			index = i,
		}
	end
	local tabRows = math.ceil(n / tabsPerRow)
	local y0 = HEADER + tabRows * (TAB_H + 2) + 8
	-- Scroll controls
	buttons[#buttons + 1] = {
		x = PAD, y = H - FOOTER + 8, w = 70, h = 32,
		kind = "scroll", dir = -1,
	}
	buttons[#buttons + 1] = {
		x = PAD + 78, y = H - FOOTER + 8, w = 70, h = 32,
		kind = "scroll", dir = 1,
	}
	-- Visible rows
	local rows = catRows()
	for i = 1, VISIBLE_ROWS do
		local ri = rowScroll + i
		local row = rows[ri]
		if not row then break end
		local y = y0 + (i - 1) * (ROW_H + 4)
		if y + ROW_H > H - FOOTER then break end
		buttons[#buttons + 1] = {
			x = PAD, y = y, w = W - PAD * 2, h = ROW_H,
			kind = "row",
			index = ri,
			row = row,
		}
	end
end

local function tabRowsCount()
	local n = #Catalog()
	local tabsPerRow = math.min(math.max(n, 1), 5)
	return math.ceil(n / tabsPerRow)
end

local function getColorCvar(cvar)
	if vrmod.SettingsGetColor then return vrmod.SettingsGetColor(cvar) end
	return Color(255, 0, 0, 255)
end

local function setColorCvar(cvar, col)
	if vrmod.SettingsSetColor then
		vrmod.SettingsSetColor(cvar, col)
	else
		RunConsoleCommand(cvar, string.format("%d,%d,%d,%d", col.r, col.g, col.b, col.a))
	end
end

local function paintColorEditor(focused, mx, my)
	buttons = {}
	local ce = colorEdit
	if not ce then return end
	local col = ce.col or getColorCvar(ce.cvar)

	-- Back
	buttons[#buttons + 1] = { x = PAD, y = 8, w = 80, h = 36, kind = "color_back" }
	-- Done
	buttons[#buttons + 1] = { x = W - PAD - 90, y = 8, w = 90, h = 36, kind = "color_done" }

	surface.SetDrawColor(Theme().bg)
	surface.DrawRect(0, 0, W, H)
	surface.SetDrawColor(Theme().headerDim)
	surface.DrawRect(0, 0, W, HEADER)
	surface.SetDrawColor(Theme().header)
	surface.DrawRect(0, HEADER - 4, W, 4)
	draw.SimpleText("COLOR", "DermaLarge", W * 0.5, 10, Theme().header, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	draw.SimpleText(ce.label or ce.cvar, "DermaDefault", W * 0.5, 36, Theme().muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

	local backHot = focused and mx >= PAD and mx <= PAD + 80 and my >= 8 and my <= 44
	local doneHot = focused and mx >= W - PAD - 90 and mx <= W - PAD and my >= 8 and my <= 44
	local C = vrmod.cube
	if C and C.DrawArrowBtn then
		C.DrawArrowBtn(PAD, 8, 36, 36, "left", backHot, true)
		surface.SetDrawColor(backHot and Theme().rowHot or Theme().row)
		surface.DrawRect(PAD + 40, 8, 48, 36)
		draw.SimpleText("BACK", "DermaDefaultBold", PAD + 64, 26, Theme().text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	else
		surface.SetDrawColor(backHot and Theme().rowHot or Theme().row)
		surface.DrawRect(PAD, 8, 80, 36)
		draw.SimpleText("< BACK", "DermaDefaultBold", PAD + 40, 26, Theme().text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	surface.SetDrawColor(doneHot and Theme().ok or Theme().header)
	surface.DrawRect(W - PAD - 90, 8, 90, 36)
	draw.SimpleText("DONE", "DermaDefaultBold", W - PAD - 45, 26, Theme().text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	-- Large swatch (like mixer preview)
	local swX, swY, swW, swH = PAD, HEADER + 12, W - PAD * 2, 56
	surface.SetDrawColor(col.r, col.g, col.b, 255)
	surface.DrawRect(swX, swY, swW, swH)
	surface.SetDrawColor(Theme().header)
	surface.DrawOutlinedRect(swX, swY, swW, swH, 2)
	draw.SimpleText(string.format("%d, %d, %d, %d", col.r, col.g, col.b, col.a), "DermaDefaultBold", W * 0.5, swY + swH * 0.5, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	-- Live sample bar + laser dots (visible proof the color applied)
	local sampleY = swY + swH + 6
	surface.SetDrawColor(col.r, col.g, col.b, 255)
	surface.DrawRect(PAD, sampleY, W - PAD * 2, 12)
	for i = 0, 24 do
		local t = i / 24
		surface.SetDrawColor(col.r, col.g, col.b, 255)
		surface.DrawRect(PAD + t * (W - PAD * 2 - 6), sampleY + 16 + t * 6, 6, 6)
	end

	-- Palette (Derma SetPalette)
	local py = sampleY + 36
	local pw = 36
	local gap = 6
	local cols = 6
	for i, pcol in ipairs(COLOR_PALETTE) do
		local ci = (i - 1) % cols
		local ri = math.floor((i - 1) / cols)
		local x = PAD + ci * (pw + gap)
		local y = py + ri * (pw + gap)
		buttons[#buttons + 1] = { x = x, y = y, w = pw, h = pw, kind = "color_swatch", col = pcol }
		local hot = focused and mx >= x and mx <= x + pw and my >= y and my <= y + pw
		surface.SetDrawColor(pcol.r, pcol.g, pcol.b, 255)
		surface.DrawRect(x, y, pw, pw)
		if hot then
			surface.SetDrawColor(Theme().hot)
			surface.DrawOutlinedRect(x, y, pw, pw, 3)
		else
			surface.SetDrawColor(40, 40, 40, 200)
			surface.DrawOutlinedRect(x, y, pw, pw, 1)
		end
	end

	-- RGBA sliders (Derma wangs)
	local channels = {
		{ key = "r", label = "R", c = Color(220, 60, 60) },
		{ key = "g", label = "G", c = Color(60, 200, 80) },
		{ key = "b", label = "B", c = Color(60, 120, 255) },
		{ key = "a", label = "A", c = Color(200, 200, 200) },
	}
	local sy = py + 2 * (pw + gap) + 16
	for i, ch in ipairs(channels) do
		local y = sy + (i - 1) * 48
		local x0, x1 = PAD + 40, W - PAD - 8
		buttons[#buttons + 1] = {
			x = x0, y = y, w = x1 - x0, h = 36,
			kind = "color_channel", channel = ch.key,
		}
		local val = col[ch.key] or 255
		local t = val / 255
		draw.SimpleText(ch.label, "DermaDefaultBold", PAD + 16, y + 18, ch.c, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		surface.SetDrawColor(Theme().headerDim)
		surface.DrawRect(x0, y + 12, x1 - x0, 12)
		surface.SetDrawColor(ch.c.r, ch.c.g, ch.c.b, 255)
		surface.DrawRect(x0, y + 12, (x1 - x0) * t, 12)
		surface.SetDrawColor(Theme().hot)
		surface.DrawRect(x0 + (x1 - x0) * t - 5, y + 6, 10, 24)
		draw.SimpleText(tostring(val), "DermaDefault", x1, y + 18, Theme().muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end

	draw.SimpleText("same convar as Derma DColorMixer", "DermaDefault", W * 0.5, H - 18, Theme().muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	if focused and mx >= 0 and my >= 0 then
		surface.SetDrawColor(Theme().hot)
		surface.DrawRect(mx - 2, my - 14, 4, 28)
		surface.DrawRect(mx - 14, my - 2, 28, 4)
	end
end

local function paint()
	if not open or not isfunction(VRUtilMenuRenderStart) then return end
	if not (g_VR.menus and g_VR.menus[UID]) then return end

	local m = g_VR.menus[UID]
	m.paintInterval = m.paintInterval or 12
	m.paintIntervalFocused = 0 -- dirty/cursor only (no full-rate DrawText)
	if vrmod.MenuApplyHandAnchor then
		vrmod.MenuApplyHandAnchor(m, liveScale, livePos, liveAng, WristHand())
	elseif not m.freeFloat and not m.grabHand then
		if not m.scaleLocked then m.scale = liveScale end
		m.pos = livePos
		m.ang = liveAng
		m.cubeMenu = true
		m.attachment = true
		m.attachHand = WristHand()
	end

	local focused = (g_VR.menuFocus == UID)
	local mx = g_VR.menuCursorX or -1
	local my = g_VR.menuCursorY or -1
	-- Cube: only rebuild RT when dirty / focused cursor / idle heartbeat
	if vrmod.MenuShouldRepaint and not vrmod.MenuShouldRepaint(UID) then return end

	if VRUtilMenuRenderStart(UID) == false then return end
	ApplyDensityLayout()
	pcall(function()
		if colorEdit then
			paintColorEditor(focused, mx, my)
			return
		end

		rebuildButtons()

		surface.SetDrawColor(Theme().bg)
		surface.DrawRect(0, 0, W, H)
		surface.SetDrawColor(Theme().headerDim)
		surface.DrawRect(0, 0, W, HEADER)
		surface.SetDrawColor(Theme().header)
		surface.DrawRect(0, HEADER - 4, W, 4)

		draw.SimpleText("SETTINGS", "DermaLarge", PAD, 10, Theme().header, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		draw.SimpleText(focused and "LASER · trigger" or "point laser · VR + desktop share catalog", "DermaDefault", PAD, 36, focused and Theme().ok or Theme().muted)

		local cx = W - 52
		local closeHot = focused and mx >= cx and mx <= cx + 40 and my >= 8 and my <= 44
		surface.SetDrawColor(closeHot and Theme().hot or Theme().header)
		surface.DrawRect(cx, 8, 40, 36)
		draw.SimpleText("X", "DermaLarge", cx + 20, 26, Theme().text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

		local cats = Catalog()
		local n = #cats
		local tabsPerRow = math.min(math.max(n, 1), 5)
		local tabW = (W - PAD * 2) / tabsPerRow
		for i, cat in ipairs(cats) do
			local col = (i - 1) % tabsPerRow
			local trow = math.floor((i - 1) / tabsPerRow)
			local x = PAD + col * tabW
			local y = HEADER + trow * (TAB_H + 2)
			local hot = focused and mx >= x and mx < x + tabW - 3 and my >= y and my < y + TAB_H
			local on = (i == category)
			surface.SetDrawColor(on and Theme().header or (hot and Theme().rowHot or Theme().row))
			surface.DrawRect(x, y, tabW - 3, TAB_H)
			draw.SimpleText(cat.title or "?", "DermaDefaultBold", x + (tabW - 3) * 0.5, y + TAB_H * 0.5, Theme().text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		local y0 = HEADER + tabRowsCount() * (TAB_H + 2) + 8
		local rows = catRows()
		for i = 1, VISIBLE_ROWS do
			local ri = rowScroll + i
			local row = rows[ri]
			if not row then break end
			local y = y0 + (i - 1) * (ROW_H + 4)
			if y + ROW_H > H - FOOTER then break end
			local hot = focused and mx >= PAD and mx <= W - PAD and my >= y and my < y + ROW_H

			if row.kind == "header" then
				draw.SimpleText(row.label or "", "DermaDefaultBold", PAD + 4, y + ROW_H * 0.5, Theme().header, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			elseif row.kind == "help" then
				draw.SimpleText(row.label or "", "DermaDefault", PAD + 8, y + ROW_H * 0.5, Theme().muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			else
				-- Active density / theme preset rows light up so density switch is obvious
				local selected = false
				if row.kind == "action" and row.action_id then
					if string.StartWith(row.action_id, "cube_density_") then
						local id = string.match(row.action_id, "^cube_density_(.+)$")
						local cur = GetConVar("vrmod_cube_density")
						selected = cur and cur:GetString() == id
					elseif string.StartWith(row.action_id, "cube_preset_") then
						local id = string.match(row.action_id, "^cube_preset_(.+)$")
						local cur = GetConVar("vrmod_cube_preset")
						selected = cur and cur:GetString() == id
					end
				end
				surface.SetDrawColor(selected and Theme().header or (hot and Theme().rowHot or Theme().row))
				surface.DrawRect(PAD, y, W - PAD * 2, ROW_H)
				if hot or selected then
					surface.SetDrawColor(Theme().hot)
					surface.DrawRect(PAD, y, selected and 6 or 4, ROW_H)
				end
				local fontRow = (vrmod.cube and vrmod.cube.Font and vrmod.cube.Font("CubeLabel")) or "DermaDefaultBold"
				draw.SimpleText(row.label or "?", fontRow, PAD + 12, y + ROW_H * 0.5, Theme().text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

				if row.kind == "bool" then
					local on = getBool(row.cvar, false)
					local bx = W - PAD - 52
					surface.SetDrawColor(on and Theme().ok or Theme().off)
					surface.DrawRect(bx, y + 8, 40, 28)
					local label = on and "ON" or "OFF"
					if row.cvar == "vrmod_hud" and on and vrmod.IsHUDActive and not vrmod.IsHUDActive() then
						label = "…" -- convar on, wait for rebind
					end
					draw.SimpleText(label, "DermaDefaultBold", bx + 20, y + ROW_H * 0.5, Theme().text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				elseif row.kind == "slider" then
					local val = getFloat(row.cvar, row.min or 0)
					local t = 0
					if row.max and row.min and row.max > row.min then
						t = math.Clamp((val - row.min) / (row.max - row.min), 0, 1)
					end
					local x0, x1 = PAD + 170, W - PAD - 12
					local ty = y + ROW_H * 0.5
					surface.SetDrawColor(Theme().headerDim)
					surface.DrawRect(x0, ty - 4, x1 - x0, 8)
					surface.SetDrawColor(Theme().header)
					surface.DrawRect(x0, ty - 4, (x1 - x0) * t, 8)
					surface.SetDrawColor(Theme().hot)
					surface.DrawRect(x0 + (x1 - x0) * t - 5, ty - 10, 10, 20)
					draw.SimpleText(string.format("%." .. (row.decimals or 2) .. "f", val), "DermaDefault", x0 - 6, ty, Theme().muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
				elseif row.kind == "combo" then
					local cur = getInt(row.cvar, 0)
					local text = tostring(cur)
					if row.choices then
						for _, ch in ipairs(row.choices) do
							if ch.value == cur then text = ch.text break end
						end
					end
					local bx = W - PAD - 120
					surface.SetDrawColor(Theme().headerDim)
					surface.DrawRect(bx, y + 8, 108, 28)
					draw.SimpleText(text .. " ▸", "DermaDefaultBold", bx + 54, y + ROW_H * 0.5, Theme().text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				elseif row.kind == "color" and row.cvar then
					local c = getColorCvar(row.cvar)
					local bx = W - PAD - 52
					surface.SetDrawColor(c.r, c.g, c.b, 255)
					surface.DrawRect(bx, y + 8, 40, 28)
					surface.SetDrawColor(Theme().hot)
					surface.DrawOutlinedRect(bx, y + 8, 40, 28, 2)
					local Cchev = vrmod.cube
					if Cchev and Cchev.DrawChevron then
						Cchev.DrawChevron(bx - 14, y + ROW_H * 0.5, 10, "right", Theme().hot)
					else
						draw.SimpleText(">", "DermaLarge", bx - 16, y + ROW_H * 0.5, Theme().hot, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					end
				elseif row.kind == "action" then
					local Cchev = vrmod.cube
					if selected then
						draw.SimpleText("*", "DermaLarge", W - PAD - 20, y + ROW_H * 0.5, Theme().ok, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					elseif Cchev and Cchev.DrawChevron then
						Cchev.DrawChevron(W - PAD - 18, y + ROW_H * 0.5, 9, "right", Theme().hot)
					else
						draw.SimpleText(">", "DermaLarge", W - PAD - 20, y + ROW_H * 0.5, Theme().hot, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					end
				end
			end
		end

		-- Footer scroll (geometric chevrons — unicode ▲▼ show as empty squares on Linux)
		local sHotL = focused and mx >= PAD and mx <= PAD + 70 and my >= H - FOOTER + 8 and my <= H - FOOTER + 40
		local sHotR = focused and mx >= PAD + 78 and mx <= PAD + 148 and my >= H - FOOTER + 8 and my <= H - FOOTER + 40
		local C = vrmod.cube
		if C and C.DrawArrowBtn then
			C.DrawArrowBtn(PAD, H - FOOTER + 8, 70, 32, "up", sHotL, true)
			C.DrawArrowBtn(PAD + 78, H - FOOTER + 8, 70, 32, "down", sHotR, true)
		else
			surface.SetDrawColor(sHotL and Theme().rowHot or Theme().row)
			surface.DrawRect(PAD, H - FOOTER + 8, 70, 32)
			surface.SetDrawColor(sHotR and Theme().rowHot or Theme().row)
			surface.DrawRect(PAD + 78, H - FOOTER + 8, 70, 32)
			draw.SimpleText("^", "DermaLarge", PAD + 35, H - FOOTER + 24, Theme().text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			draw.SimpleText("v", "DermaLarge", PAD + 113, H - FOOTER + 24, Theme().text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		draw.SimpleText(string.format("%d–%d / %d", rowScroll + 1, math.min(rowScroll + VISIBLE_ROWS, #rows), #rows), "DermaDefault", W - PAD, H - FOOTER + 24, Theme().muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

		if focused and mx >= 0 and my >= 0 then
			surface.SetDrawColor(Theme().hot)
			surface.DrawRect(mx - 2, my - 14, 4, 28)
			surface.DrawRect(mx - 14, my - 2, 28, 4)
		end
	end)
	if isfunction(VRUtilMenuRenderEnd) then VRUtilMenuRenderEnd() end
end

local function cycleCombo(row)
	if not row.choices or #row.choices < 1 then return end
	local cur = getInt(row.cvar, row.choices[1].value)
	local idx = 1
	for i, ch in ipairs(row.choices) do
		if ch.value == cur then idx = i break end
	end
	idx = idx % #row.choices + 1
	setInt(row.cvar, row.choices[idx].value)
end

local function activateAt(mx, my)
	for _, btn in ipairs(buttons) do
		if mx >= btn.x and mx <= btn.x + btn.w and my >= btn.y and my <= btn.y + btn.h then
			if btn.kind == "color_back" or btn.kind == "color_done" then
				if colorEdit and colorEdit.cvar and colorEdit.col then
					setColorCvar(colorEdit.cvar, colorEdit.col)
				end
				colorEdit = nil
				paint()
				return
			elseif btn.kind == "color_swatch" and btn.col and colorEdit then
				colorEdit.col = Color(btn.col.r, btn.col.g, btn.col.b, colorEdit.col and colorEdit.col.a or 255)
				setColorCvar(colorEdit.cvar, colorEdit.col)
				paint()
				return
			elseif btn.kind == "color_channel" and colorEdit and btn.channel then
				local t = math.Clamp((mx - btn.x) / math.max(1, btn.w), 0, 1)
				local v = math.floor(t * 255 + 0.5)
				local c0 = colorEdit.col or getColorCvar(colorEdit.cvar)
				local r, g, b, a = c0.r, c0.g, c0.b, c0.a
				if btn.channel == "r" then r = v
				elseif btn.channel == "g" then g = v
				elseif btn.channel == "b" then b = v
				else a = v end
				colorEdit.col = Color(r, g, b, a)
				setColorCvar(colorEdit.cvar, colorEdit.col)
				paint()
				return
			elseif btn.kind == "close" then
				vrmod.CubeSettings_Close()
				return
			elseif btn.kind == "tab" then
				category = btn.index
				rowScroll = 0
				paint()
				return
			elseif btn.kind == "scroll" then
				rowScroll = math.Clamp(rowScroll + (btn.dir or 0) * VISIBLE_ROWS, 0, maxScroll())
				paint()
				return
			elseif btn.kind == "row" and btn.row then
				local row = btn.row
				if row.kind == "bool" and row.cvar then
					setBool(row.cvar, not getBool(row.cvar, false))
				elseif row.kind == "slider" and row.cvar then
					local x0, x1 = PAD + 170, W - PAD - 12
					local t = math.Clamp((mx - x0) / math.max(1, x1 - x0), 0, 1)
					local val = (row.min or 0) + t * ((row.max or 1) - (row.min or 0))
					if row.decimals == 0 then val = math.floor(val + 0.5) end
					setFloat(row.cvar, val)
				elseif row.kind == "combo" then
					cycleCombo(row)
				elseif row.kind == "color" and row.cvar then
					local c = getColorCvar(row.cvar)
					colorEdit = {
						cvar = row.cvar,
						label = row.label,
						col = Color(c.r, c.g, c.b, c.a),
					}
				elseif row.kind == "action" then
					runRowAction(row)
				end
				paint()
				return
			end
		end
	end
end

function vrmod.CubeSettings_Close()
	if not open then
		if isfunction(VRUtilMenuClose) and g_VR and g_VR.menus and g_VR.menus[UID] then
			if g_VR.menus[UID] then g_VR.menus[UID].closeFunc = nil end
			VRUtilMenuClose(UID)
		end
		return
	end
	if colorEdit and colorEdit.cvar and colorEdit.col then
		setColorCvar(colorEdit.cvar, colorEdit.col)
	end
	colorEdit = nil
	open = false
	hook.Remove("PreRender", "cube_settings_paint")
	hook.Remove("VRMod_Input", "cube_settings_input")
	hook.Remove("VRMod_Exit", "cube_settings_exit")
	hook.Remove("VRMod_OpenQuickMenu", "cube_settings_qm")
	if g_VR and g_VR.menus and g_VR.menus[UID] then
		g_VR.menus[UID].closeFunc = nil
	end
	if isfunction(VRUtilMenuClose) then
		VRUtilMenuClose(UID)
	end
	if vrmod.cubeui and vrmod.cubeui.IsOpen and vrmod.cubeui.IsOpen() then
		vrmod.cubeui.Close()
	end
end

function vrmod.CubeSettings_Open()
	-- Non-VR: full Derma from same catalog
	if not (g_VR and g_VR.active) then
		if VRUtilOpenMenu then VRUtilOpenMenu() end
		return
	end
	-- Already open: do NOT toggle-close (felt like "press twice to open" from QM)
	if open and g_VR.menus and g_VR.menus[UID] then
		g_VR.menus[UID].dirty = true
		if not g_VR.menus[UID].freeFloat and not g_VR.menus[UID].grabHand then
			livePos, liveAng, liveScale = WristPose()
			if vrmod.MenuApplyHandAnchor then
				vrmod.MenuApplyHandAnchor(g_VR.menus[UID], liveScale, livePos, liveAng, WristHand())
			end
		end
		return
	end
	open = false -- recover stuck flag without menu table
	if not isfunction(VRUtilMenuOpen) then return end
	if not vrmod.SettingsCatalog then
		if vrmod.logger then vrmod.logger.Warn("SettingsCatalog missing") end
		if VRUtilOpenMenu then VRUtilOpenMenu() end
		return
	end

	if vrmod.cubeui and vrmod.cubeui.Close then pcall(vrmod.cubeui.Close) end

	open = true
	category = 1
	rowScroll = 0
	colorEdit = nil
	livePos, liveAng, liveScale = WristPose()

	VRUtilMenuOpen(UID, W, H, nil, true, livePos, liveAng, liveScale, true, function()
		open = false
		hook.Remove("PreRender", "cube_settings_paint")
		hook.Remove("VRMod_Input", "cube_settings_input")
		hook.Remove("VRMod_OpenQuickMenu", "cube_settings_qm")
	end)

	if not (g_VR.menus and g_VR.menus[UID]) then
		open = false
		return
	end
	if vrmod.MenuApplyHandAnchor then
		vrmod.MenuApplyHandAnchor(g_VR.menus[UID], liveScale, livePos, liveAng, WristHand())
	else
		local sm = g_VR.menus[UID]
		if not sm.scaleLocked then sm.scale = liveScale end
		sm.pos = livePos
		sm.ang = liveAng
		sm.cubeMenu = true
		sm.attachment = true
		sm.attachHand = WristHand()
	end

	paint()

	hook.Add("PreRender", "cube_settings_paint", function()
		if not open then
			hook.Remove("PreRender", "cube_settings_paint")
			return
		end
		if not (g_VR.menus and g_VR.menus[UID]) then
			open = false
			hook.Remove("PreRender", "cube_settings_paint")
			return
		end
		paint()
	end)

	hook.Add("VRMod_Input", "cube_settings_input", function(action, pressed)
		if not open then return end
		if pressed and (vrmod.IsMenuCloseAction and vrmod.IsMenuCloseAction(action) or action == "boolean_secondaryfire" or action == "boolean_chat") then
			vrmod.CubeSettings_Close()
			return
		end
		-- Any interaction dirties RT for next paint
		if g_VR.menus and g_VR.menus[UID] then g_VR.menus[UID].dirty = true end
		if not pressed then return end
		if g_VR.menuFocus ~= UID then return end
		if not (vrmod.IsMenuPrimaryClick and vrmod.IsMenuPrimaryClick(action)) then return end
		activateAt(g_VR.menuCursorX or 0, g_VR.menuCursorY or 0)
	end)

	local openedAt = CurTime()
	hook.Add("VRMod_OpenQuickMenu", "cube_settings_qm", function()
		if not open then return end
		if CurTime() - openedAt < 0.4 then return end
		timer.Simple(0, function()
			if open then vrmod.CubeSettings_Close() end
		end)
	end)

	hook.Add("VRMod_Exit", "cube_settings_exit", function()
		vrmod.CubeSettings_Close()
	end)
end

function vrmod.CubeSettings_IsOpen()
	return open
end

hook.Add("InitPostEntity", "cube_settings_register", function()
	timer.Simple(0.1, function()
		if not vrmod.panel2vr then return end
		vrmod.panel2vr.RegisterNative("settings", function()
			vrmod.CubeSettings_Open()
			return true
		end)
	end)
end)

concommand.Add("vrmod_cube_settings", function()
	vrmod.CubeSettings_Open()
end)

concommand.Add("vrmod_settings", function()
	if vrmod.Settings_Open then
		vrmod.Settings_Open()
	else
		vrmod.CubeSettings_Open()
	end
end)
