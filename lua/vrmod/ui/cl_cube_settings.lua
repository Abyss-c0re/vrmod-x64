if SERVER then return end
-- =============================================================================
-- Glorious Crimson Cube — VR-native settings (HL:Alyx energy)
-- Desktop keeps Derma Derma panes (VRUtilOpenMenu). In VR this surface is SoT.
-- Built on vrmod.panel2vr (Derma/VGUI → VR surfaces) + laser focus from cl_ui.
-- =============================================================================

vrmod = vrmod or {}

local UID = "cube_settings"
local open = false
local markDirty = nil
local category = 1
local scroll = 0
local W, H = 640, 720

local Theme = {
	bg = Color(12, 6, 10, 245),
	header = Color(196, 30, 58, 255),
	headerDim = Color(80, 12, 24, 255),
	row = Color(28, 10, 16, 230),
	rowHot = Color(70, 18, 28, 250),
	text = Color(255, 240, 244, 255),
	muted = Color(190, 150, 160, 230),
	accent = Color(255, 70, 100, 255),
	ok = Color(90, 220, 150, 255),
	cube = Color(180, 20, 45, 255),
}

local categories -- forward

local function cv(name)
	return GetConVar(name)
end

local function getBool(name, default)
	local c = cv(name)
	if c then return c:GetBool() end
	return default
end

local function getFloat(name, default)
	local c = cv(name)
	if c then return c:GetFloat() end
	return default
end

local function setBool(name, v)
	RunConsoleCommand(name, v and "1" or "0")
end

local function setFloat(name, v)
	RunConsoleCommand(name, tostring(v))
end

-- Schema: Alyx-style rows — bool toggle, slider, action
categories = {
	{
		id = "vision",
		title = "Vision",
		hint = "Crimson Cube · eyes of the Real",
		rows = {
			{ kind = "slider", label = "Supersample", cvar = "vrmod_supersample", min = 0.5, max = 2.0, decimals = 2,
				help = "Restart VR after change. Cap SBS ≤ 4096." },
			{ kind = "slider", label = "Scale factor", cvar = "vrmod_scalefactor", min = 0.05, max = 4.0, decimals = 2 },
			{ kind = "slider", label = "View scale", cvar = "vrmod_viewscale", min = 0.1, max = 2.0, decimals = 2 },
			{ kind = "slider", label = "FOV scale X", cvar = "vrmod_fovscale_x", min = 0.5, max = 1.5, decimals = 2 },
			{ kind = "slider", label = "FOV scale Y", cvar = "vrmod_fovscale_y", min = 0.5, max = 1.5, decimals = 2 },
			{ kind = "bool", label = "Post-process", cvar = "vrmod_postprocess" },
			{ kind = "bool", label = "3D Skybox", cvar = "vrmod_skybox" },
			{ kind = "bool", label = "Swap eyes (if inverted)", cvar = "vrmod_swap_eyes",
				help = "If world looks inside-out / crossed, toggle this." },
			{ kind = "action", label = "Border calibrate", cmd = "vrmod_border_calibrate" },
			{ kind = "action", label = "Restart Cube Experience", cmd = "vrmod_experience_reset" },
		},
	},
	{
		id = "controls",
		title = "Controls",
		hint = "Hands · will · input",
		rows = {
			{ kind = "bool", label = "Smooth turning", cvar = "vrmod_smoothturn" },
			{ kind = "slider", label = "Turn rate", cvar = "vrmod_smoothturnrate", min = 1, max = 1000, decimals = 0 },
			{ kind = "bool", label = "Teleport (client)", cvar = "vrmod_allow_teleport_client" },
			{ kind = "bool", label = "Teleport left hand", cvar = "vrmod_teleport_use_left" },
			{ kind = "bool", label = "Floating hands", cvar = "vrmod_floatinghands" },
			{ kind = "bool", label = "Laser pointer", cvar = "vrmod_laserpointer" },
			{ kind = "action", label = "Edit actions", cmd = "vrmod_actioneditor" },
		},
	},
	{
		id = "posture",
		title = "Posture",
		hint = "Height · seated · avatar",
		rows = {
			{ kind = "bool", label = "Height menu", cvar = "vrmod_heightmenu" },
			{ kind = "bool", label = "Seated offset", cvar = "vrmod_seated" },
			{ kind = "action", label = "Open height / mirror", action = function()
				if VRUtilOpenHeightMenu then VRUtilOpenHeightMenu() end
			end },
			{ kind = "action", label = "Auto scale height", action = function()
				if vrmod.AutoScaleHeight then vrmod.AutoScaleHeight() end
			end },
			{ kind = "action", label = "Auto seated offset", action = function()
				if vrmod.AutoSeatedOffset then vrmod.AutoSeatedOffset() end
			end },
			{ kind = "action", label = "Restart Cube Experience", cmd = "vrmod_experience_reset" },
		},
	},
	{
		id = "comfort",
		title = "World",
		hint = "Locomotion · doors · climb",
		rows = {
			{ kind = "bool", label = "Climbing replace", cvar = "vrmod_climbing" },
			{ kind = "bool", label = "Door replace", cvar = "vrmod_doors" },
			{ kind = "bool", label = "Autostart VR", cvar = "vrmod_autostart" },
			{ kind = "action", label = "UI reset surfaces", cmd = "vrmod_vgui_reset" },
			{ kind = "action", label = "Close all panel2vr", cmd = "vrmod_panel2vr_closeall" },
		},
	},
	{
		id = "session",
		title = "Session",
		hint = "Start · stop · leave",
		rows = {
			{ kind = "action", label = "Restart VR", action = function()
				vrmod.CubeSettings_Close()
				if g_VR and g_VR.active then
					VRUtilClientExit()
					timer.Simple(1, function() VRUtilClientStart() end)
				end
			end },
			{ kind = "action", label = "Exit VR", action = function()
				vrmod.CubeSettings_Close()
				RunConsoleCommand("vrmod_exit")
			end },
			{ kind = "action", label = "Desktop settings pane", action = function()
				vrmod.CubeSettings_Close()
				-- Force derma even in VR (debug) via panel2vr panel path
				if VRUtilOpenMenu then
					local f = VRUtilOpenMenu()
					if IsValid(f) and vrmod.panel2vr then
						vrmod.panel2vr.ManifestPanel(f, { place = "float", hint = "settings_derma" })
					end
				end
			end },
		},
	},
}

-- Layout constants
local HEADER_H = 72
local TAB_H = 36
local ROW_H = 52
local PAD = 16

local function hitTest(mx, my)
	-- category tabs
	local tabW = (W - PAD * 2) / #categories
	if my >= HEADER_H and my < HEADER_H + TAB_H then
		local i = math.floor((mx - PAD) / tabW) + 1
		if i >= 1 and i <= #categories then
			return "tab", i
		end
	end

	local cat = categories[category]
	if not cat then return end
	local y0 = HEADER_H + TAB_H + PAD - scroll
	for i, row in ipairs(cat.rows) do
		local y = y0 + (i - 1) * (ROW_H + 6)
		if my >= y and my < y + ROW_H and mx >= PAD and mx <= W - PAD then
			if row.kind == "bool" or row.kind == "action" then
				return "row", i
			elseif row.kind == "slider" then
				local trackX0 = PAD + 200
				local trackX1 = W - PAD - 20
				if mx >= trackX0 and mx <= trackX1 then
					return "slider", i, (mx - trackX0) / math.max(1, trackX1 - trackX0)
				end
				return "row", i
			end
		end
	end
end

local function drawCubeGlyph(cx, cy, s)
	-- Simple crimson cube mark (rects — reliable under 3D2D RT)
	surface.SetDrawColor(Theme.cube)
	surface.DrawRect(cx - s, cy - s, s * 2, s * 2)
	surface.SetDrawColor(Theme.accent)
	surface.DrawOutlinedRect(cx - s, cy - s, s * 2, s * 2)
	surface.SetDrawColor(Theme.header)
	surface.DrawRect(cx - s + 3, cy - s + 3, s * 2 - 6, 4)
	surface.DrawRect(cx - s + 3, cy + s - 7, s * 2 - 6, 4)
end

-- Named paintSettings so we do not shadow global draw.* (SimpleText etc.)
local function paintSettings(w, h, focused)
	W, H = w, h
	surface.SetDrawColor(Theme.bg)
	surface.DrawRect(0, 0, w, h)

	-- Header bar
	surface.SetDrawColor(Theme.headerDim)
	surface.DrawRect(0, 0, w, HEADER_H)
	surface.SetDrawColor(Theme.header)
	surface.DrawRect(0, HEADER_H - 3, w, 3)

	drawCubeGlyph(36, 34, 14)
	draw.SimpleText("GLORIOUS CRIMSON CUBE", "DermaDefaultBold", 60, 18, Theme.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	draw.SimpleText("Settings · Ideal VR", "DermaDefault", 60, 40, Theme.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

	-- Tabs
	local tabW = (w - PAD * 2) / #categories
	for i, cat in ipairs(categories) do
		local x = PAD + (i - 1) * tabW
		local hot = (i == category)
		surface.SetDrawColor(hot and Theme.header or Theme.row)
		surface.DrawRect(x, HEADER_H, tabW - 4, TAB_H)
		draw.SimpleText(cat.title, "DermaDefault", x + (tabW - 4) / 2, HEADER_H + TAB_H / 2, Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	local cat = categories[category]
	if cat then
		draw.SimpleText(cat.hint or "", "DermaDefault", PAD, HEADER_H + TAB_H + 4, Theme.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

		local y0 = HEADER_H + TAB_H + PAD + 8 - scroll
		local mx, my = g_VR.menuCursorX or -1, g_VR.menuCursorY or -1
		local focusHere = focused and g_VR.menuFocus == UID

		for i, row in ipairs(cat.rows) do
			local y = y0 + (i - 1) * (ROW_H + 6)
			if y + ROW_H >= HEADER_H + TAB_H and y <= h then
				local hovered = focusHere and mx >= PAD and mx <= w - PAD and my >= y and my < y + ROW_H
				surface.SetDrawColor(hovered and Theme.rowHot or Theme.row)
				surface.DrawRect(PAD, y, w - PAD * 2, ROW_H)
				if hovered then
					surface.SetDrawColor(Theme.accent)
					surface.DrawRect(PAD, y, 4, ROW_H)
				end

				draw.SimpleText(row.label, "DermaDefaultBold", PAD + 16, y + 10, Theme.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

				if row.kind == "bool" then
					local on = getBool(row.cvar, false)
					local bx, by, bw, bh = w - PAD - 56, y + 12, 40, 28
					surface.SetDrawColor(on and Theme.ok or Theme.headerDim)
					surface.DrawRect(bx, by, bw, bh)
					draw.SimpleText(on and "ON" or "OFF", "DermaDefault", bx + bw / 2, by + bh / 2, Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				elseif row.kind == "slider" then
					local val = getFloat(row.cvar, row.min or 0)
					local t = 0
					if row.max and row.min and row.max > row.min then
						t = math.Clamp((val - row.min) / (row.max - row.min), 0, 1)
					end
					local trackX0, trackX1 = PAD + 200, w - PAD - 20
					local trackY = y + ROW_H / 2
					surface.SetDrawColor(Theme.headerDim)
					surface.DrawRect(trackX0, trackY - 3, trackX1 - trackX0, 6)
					surface.SetDrawColor(Theme.header)
					surface.DrawRect(trackX0, trackY - 3, (trackX1 - trackX0) * t, 6)
					surface.SetDrawColor(Theme.accent)
					surface.DrawRect(trackX0 + (trackX1 - trackX0) * t - 5, trackY - 10, 10, 20)
					local fmt = string.format("%." .. (row.decimals or 2) .. "f", val)
					draw.SimpleText(fmt, "DermaDefault", trackX0 - 8, trackY, Theme.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
				elseif row.kind == "action" then
					draw.SimpleText(">", "DermaDefaultBold", w - PAD - 24, y + ROW_H / 2, Theme.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end

				if row.help and hovered then
					draw.SimpleText(row.help, "DermaDefault", PAD + 16, y + 32, Theme.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
				end
			end
		end
	end

	-- Footer laser hint
	draw.SimpleText("Point · Trigger select · Grip / Quickmenu close", "DermaDefault", w / 2, h - 18, Theme.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	-- Cursor
	if focused and g_VR.menuFocus == UID then
		local cx, cy = g_VR.menuCursorX or 0, g_VR.menuCursorY or 0
		surface.SetDrawColor(Theme.accent)
		surface.DrawRect(cx - 2, cy - 8, 4, 16)
		surface.DrawRect(cx - 8, cy - 2, 16, 4)
	end
end

local function activate(hit, a, b, c)
	if hit == "tab" then
		category = a
		scroll = 0
		if markDirty then markDirty() end
		return
	end
	local cat = categories[category]
	if not cat then return end
	local row = cat.rows[a]
	if not row then return end

	if hit == "slider" and row.kind == "slider" then
		local t = math.Clamp(b or 0, 0, 1)
		local val = (row.min or 0) + t * ((row.max or 1) - (row.min or 0))
		if row.decimals == 0 then val = math.floor(val + 0.5) end
		setFloat(row.cvar, val)
		if markDirty then markDirty() end
		return
	end

	if hit == "row" then
		if row.kind == "bool" then
			setBool(row.cvar, not getBool(row.cvar, false))
		elseif row.kind == "action" then
			if row.cmd then
				RunConsoleCommand(row.cmd)
			elseif row.action then
				row.action()
			end
		end
		if markDirty then markDirty() end
	end
end

function vrmod.CubeSettings_Close()
	if not open then return end
	open = false
	hook.Remove("VRMod_Input", "cube_settings_input")
	if vrmod.panel2vr then
		vrmod.panel2vr.Close(UID)
	elseif VRUtilMenuClose then
		VRUtilMenuClose(UID)
	end
end

local opening = false

function vrmod.CubeSettings_Open()
	if not (g_VR and g_VR.active) then
		if VRUtilOpenMenu then VRUtilOpenMenu() end
		return
	end
	if open then
		vrmod.CubeSettings_Close()
		return
	end
	if opening then return end
	opening = true

	if not vrmod.panel2vr or not vrmod.panel2vr.ManifestNative then
		opening = false
		-- Fallback: paint Derma as VR surface (kind=panel skips native redirect)
		if VRUtilOpenMenu then
			local f = VRUtilOpenMenu()
			if IsValid(f) and vrmod.panel2vr and vrmod.panel2vr.ManifestPanel then
				vrmod.panel2vr.ManifestPanel(f, {
					place = "float",
					hint = "settings_derma",
					kind = "panel",
				})
			end
		end
		return
	end

	open = true
	category = 1
	scroll = 0

	local uid, dirty = vrmod.panel2vr.ManifestNative(UID, W, H, paintSettings, {
		place = "float",
		alwaysRedraw = true,
		onClose = function()
			open = false
			opening = false
			hook.Remove("VRMod_Input", "cube_settings_input")
		end,
	})
	markDirty = dirty
	opening = false

	hook.Add("VRMod_Input", "cube_settings_input", function(action, pressed)
		if not open or not pressed then return end
		if g_VR.menuFocus ~= UID then return end
		if action == "boolean_primaryfire" or action == "boolean_car_mouse_left" then
			local mx, my = g_VR.menuCursorX or 0, g_VR.menuCursorY or 0
			local hit, a, b = hitTest(mx, my)
			if hit then activate(hit, a, b) end
		elseif action == "boolean_secondaryfire" or action == "boolean_chat" then
			vrmod.CubeSettings_Close()
		end
	end)

	-- Close when quickmenu reopens
	hook.Add("VRMod_OpenQuickMenu", "cube_settings_qm", function()
		hook.Remove("VRMod_OpenQuickMenu", "cube_settings_qm")
		vrmod.CubeSettings_Close()
		return false
	end)

	if vrmod.logger then
		vrmod.logger.Info("[CubeSettings] Glorious Crimson Cube open")
	end
end

function vrmod.CubeSettings_IsOpen()
	return open
end

-- Register as native adapter for settings-like panels
hook.Add("InitPostEntity", "cube_settings_register", function()
	timer.Simple(0.1, function()
		if not vrmod.panel2vr then return end
		vrmod.panel2vr.RegisterNative("settings", function(_panel, _opts)
			vrmod.CubeSettings_Open()
			return true
		end)
		-- Do not steal spawnmenu — paint path is correct there
	end)
end)

concommand.Add("vrmod_cube_settings", function()
	vrmod.CubeSettings_Open()
end)

hook.Add("VRMod_Exit", "cube_settings_exit", function()
	vrmod.CubeSettings_Close()
end)
