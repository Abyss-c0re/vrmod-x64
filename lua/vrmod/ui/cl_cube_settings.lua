if SERVER then return end
-- =============================================================================
-- Cube Settings — heightmenu-proven VRMod path (CLICKABLE)
--
-- SoT: VRUtilMenuOpen left hand + PreRender paint + VRMod_Input hit boxes
-- Same contract as cl_heightadjust (that one works). No multi-plane cube.
-- =============================================================================

vrmod = vrmod or {}

local UID = "cube_settings"
local open = false
local category = 1
local liveScale = 0.025
local livePos, liveAng = Vector(2.5, 3, 4), Angle(0, -90, 55)

local W, H = 512, 560
local function WristPose()
	-- Recompute at open (cl_ui may load after this file)
	if isfunction(VRUtilHandMenuPose) then
		return VRUtilHandMenuPose(W, H, 0.025, Vector(2.5, 3.5, 4), Angle(0, -90, 55))
	end
	return Vector(2.5, 3, 4), Angle(0, -90, 55), 0.025
end

local Theme = {
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

local function setBool(name, v)
	RunConsoleCommand(name, v and "1" or "0")
end

local function setFloat(name, v)
	RunConsoleCommand(name, tostring(v))
end

local categories = {
	{
		title = "Vision",
		rows = {
			{ kind = "slider", label = "Supersample", cvar = "vrmod_supersample", min = 0.5, max = 2.0, decimals = 2 },
			{ kind = "slider", label = "Scale factor", cvar = "vrmod_scalefactor", min = 0.05, max = 4.0, decimals = 2 },
			{ kind = "slider", label = "View scale", cvar = "vrmod_viewscale", min = 0.1, max = 2.0, decimals = 2 },
			{ kind = "slider", label = "FOV X", cvar = "vrmod_fovscale_x", min = 0.5, max = 1.5, decimals = 2 },
			{ kind = "slider", label = "FOV Y", cvar = "vrmod_fovscale_y", min = 0.5, max = 1.5, decimals = 2 },
			{ kind = "bool", label = "Post-process", cvar = "vrmod_postprocess" },
			{ kind = "bool", label = "3D Skybox", cvar = "vrmod_skybox" },
			{ kind = "bool", label = "Swap eyes", cvar = "vrmod_swap_eyes" },
			{ kind = "action", label = "Border calibrate", cmd = "vrmod_border_calibrate" },
		},
	},
	{
		title = "Controls",
		rows = {
			{ kind = "bool", label = "Smooth turning", cvar = "vrmod_smoothturn" },
			{ kind = "slider", label = "Turn rate", cvar = "vrmod_smoothturnrate", min = 1, max = 1000, decimals = 0 },
			{ kind = "bool", label = "Teleport", cvar = "vrmod_allow_teleport_client" },
			{ kind = "bool", label = "Teleport L hand", cvar = "vrmod_teleport_use_left" },
			{ kind = "bool", label = "Floating hands", cvar = "vrmod_floatinghands" },
			{ kind = "bool", label = "Laser pointer", cvar = "vrmod_laserpointer" },
			{ kind = "action", label = "Edit actions", cmd = "vrmod_actioneditor" },
		},
	},
	{
		title = "Posture",
		rows = {
			{ kind = "bool", label = "Height menu", cvar = "vrmod_heightmenu" },
			{ kind = "bool", label = "Seated", cvar = "vrmod_seated" },
			{ kind = "action", label = "Open height", action = function()
				if VRUtilOpenHeightMenu then VRUtilOpenHeightMenu() end
			end },
			{ kind = "action", label = "Auto height", action = function()
				if vrmod.AutoScaleHeight then vrmod.AutoScaleHeight() end
			end },
			{ kind = "action", label = "Auto seated", action = function()
				if vrmod.AutoSeatedOffset then vrmod.AutoSeatedOffset() end
			end },
		},
	},
	{
		title = "World",
		rows = {
			{ kind = "bool", label = "Climbing", cvar = "vrmod_climbing" },
			{ kind = "bool", label = "Doors", cvar = "vrmod_doors" },
			{ kind = "bool", label = "Autostart", cvar = "vrmod_autostart" },
			{ kind = "action", label = "UI reset", cmd = "vrmod_vgui_reset" },
		},
	},
	{
		title = "Session",
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
			{ kind = "action", label = "CLOSE", action = function()
				vrmod.CubeSettings_Close()
			end },
		},
	},
}

-- Hit boxes rebuilt every paint (heightmenu style)
local buttons = {}

local HEADER = 56
local TAB_H = 40
local PAD = 16
local ROW_H = 48

local function rebuildButtons()
	buttons = {}
	-- Close X
	buttons[#buttons + 1] = {
		x = W - 56, y = 8, w = 44, h = 40,
		kind = "close",
	}
	-- Tabs
	local n = #categories
	local tabW = (W - PAD * 2) / n
	for i = 1, n do
		buttons[#buttons + 1] = {
			x = PAD + (i - 1) * tabW,
			y = HEADER,
			w = tabW - 4,
			h = TAB_H,
			kind = "tab",
			index = i,
		}
	end
	-- Rows
	local cat = categories[category]
	if not cat then return end
	local y0 = HEADER + TAB_H + 16
	for i, row in ipairs(cat.rows) do
		local y = y0 + (i - 1) * (ROW_H + 6)
		if y + ROW_H > H - 40 then break end
		buttons[#buttons + 1] = {
			x = PAD, y = y, w = W - PAD * 2, h = ROW_H,
			kind = "row",
			index = i,
			row = row,
		}
	end
end

local function paint()
	if not open or not isfunction(VRUtilMenuRenderStart) then return end
	if not (g_VR.menus and g_VR.menus[UID]) then return end

	local m = g_VR.menus[UID]
	m.scale = liveScale
	m.pos = livePos
	m.ang = liveAng
	m.cubeMenu = true
	m.attachment = true

	local focused = (g_VR.menuFocus == UID)
	local mx = g_VR.menuCursorX or -1
	local my = g_VR.menuCursorY or -1

	rebuildButtons()

	pcall(function()
		VRUtilMenuRenderStart(UID)

		surface.SetDrawColor(Theme.bg)
		surface.DrawRect(0, 0, W, H)
		surface.SetDrawColor(Theme.headerDim)
		surface.DrawRect(0, 0, W, HEADER)
		surface.SetDrawColor(Theme.header)
		surface.DrawRect(0, HEADER - 4, W, 4)

		draw.SimpleText("CUBE", "DermaLarge", PAD, 12, Theme.header, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		draw.SimpleText(focused and "LASER LOCK · trigger" or "point laser here", "DermaDefault", PAD, 36, focused and Theme.ok or Theme.muted)

		-- Close
		local cx = W - 56
		local closeHot = focused and mx >= cx and mx <= cx + 44 and my >= 8 and my <= 48
		surface.SetDrawColor(closeHot and Theme.hot or Theme.header)
		surface.DrawRect(cx, 8, 44, 40)
		draw.SimpleText("X", "DermaLarge", cx + 22, 28, Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

		-- Tabs
		local n = #categories
		local tabW = (W - PAD * 2) / n
		for i, cat in ipairs(categories) do
			local x = PAD + (i - 1) * tabW
			local hot = focused and mx >= x and mx < x + tabW - 4 and my >= HEADER and my < HEADER + TAB_H
			local on = (i == category)
			surface.SetDrawColor(on and Theme.header or (hot and Theme.rowHot or Theme.row))
			surface.DrawRect(x, HEADER, tabW - 4, TAB_H)
			draw.SimpleText(cat.title, "DermaDefaultBold", x + (tabW - 4) * 0.5, HEADER + TAB_H * 0.5, Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		local cat = categories[category]
		if cat then
			for i, row in ipairs(cat.rows) do
				local y = HEADER + TAB_H + 16 + (i - 1) * (ROW_H + 6)
				if y + ROW_H > H - 40 then break end
				local hot = focused and mx >= PAD and mx <= W - PAD and my >= y and my < y + ROW_H
				surface.SetDrawColor(hot and Theme.rowHot or Theme.row)
				surface.DrawRect(PAD, y, W - PAD * 2, ROW_H)
				if hot then
					surface.SetDrawColor(Theme.hot)
					surface.DrawRect(PAD, y, 5, ROW_H)
				end
				draw.SimpleText(row.label, "DermaDefaultBold", PAD + 14, y + ROW_H * 0.5, Theme.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

				if row.kind == "bool" then
					local on = getBool(row.cvar, false)
					local bx = W - PAD - 56
					surface.SetDrawColor(on and Theme.ok or Theme.off)
					surface.DrawRect(bx, y + 10, 44, 28)
					draw.SimpleText(on and "ON" or "OFF", "DermaDefaultBold", bx + 22, y + ROW_H * 0.5, Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				elseif row.kind == "slider" then
					local val = getFloat(row.cvar, row.min or 0)
					local t = 0
					if row.max and row.min and row.max > row.min then
						t = math.Clamp((val - row.min) / (row.max - row.min), 0, 1)
					end
					local x0, x1 = PAD + 160, W - PAD - 14
					local ty = y + ROW_H * 0.5
					surface.SetDrawColor(Theme.headerDim)
					surface.DrawRect(x0, ty - 4, x1 - x0, 8)
					surface.SetDrawColor(Theme.header)
					surface.DrawRect(x0, ty - 4, (x1 - x0) * t, 8)
					surface.SetDrawColor(Theme.hot)
					surface.DrawRect(x0 + (x1 - x0) * t - 6, ty - 12, 12, 24)
					draw.SimpleText(string.format("%." .. (row.decimals or 2) .. "f", val), "DermaDefault", x0 - 8, ty, Theme.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
				elseif row.kind == "action" then
					draw.SimpleText("▸", "DermaLarge", W - PAD - 24, y + ROW_H * 0.5, Theme.hot, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
			end
		end

		draw.SimpleText("secondary = close", "DermaDefault", W * 0.5, H - 20, Theme.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

		if focused and mx >= 0 and my >= 0 then
			surface.SetDrawColor(Theme.hot)
			surface.DrawRect(mx - 2, my - 14, 4, 28)
			surface.DrawRect(mx - 14, my - 2, 28, 4)
		end

		VRUtilMenuRenderEnd()
	end)
end

local function activateAt(mx, my)
	for _, btn in ipairs(buttons) do
		if mx >= btn.x and mx <= btn.x + btn.w and my >= btn.y and my <= btn.y + btn.h then
			if btn.kind == "close" then
				vrmod.CubeSettings_Close()
				return
			elseif btn.kind == "tab" then
				category = btn.index
				paint()
				return
			elseif btn.kind == "row" and btn.row then
				local row = btn.row
				if row.kind == "bool" then
					setBool(row.cvar, not getBool(row.cvar, false))
				elseif row.kind == "slider" then
					local x0, x1 = PAD + 160, W - PAD - 14
					local t = math.Clamp((mx - x0) / math.max(1, x1 - x0), 0, 1)
					local val = (row.min or 0) + t * ((row.max or 1) - (row.min or 0))
					if row.decimals == 0 then val = math.floor(val + 0.5) end
					setFloat(row.cvar, val)
				elseif row.kind == "action" then
					if row.cmd then RunConsoleCommand(row.cmd)
					elseif row.action then row.action() end
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
	-- drop fancy cubeui if still open
	if vrmod.cubeui and vrmod.cubeui.IsOpen and vrmod.cubeui.IsOpen() then
		vrmod.cubeui.Close()
	end
end

function vrmod.CubeSettings_Open()
	if not (g_VR and g_VR.active) then
		if VRUtilOpenMenu then VRUtilOpenMenu() end
		return
	end
	if open then
		vrmod.CubeSettings_Close()
		return
	end
	if not isfunction(VRUtilMenuOpen) then return end

	-- Close competing surfaces
	if vrmod.cubeui and vrmod.cubeui.Close then pcall(vrmod.cubeui.Close) end

	open = true
	category = 1
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
	g_VR.menus[UID].scale = liveScale
	g_VR.menus[UID].pos = livePos
	g_VR.menus[UID].ang = liveAng
	g_VR.menus[UID].cubeMenu = true
	g_VR.menus[UID].attachment = true

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
		g_VR.menus[UID].scale = liveScale
		g_VR.menus[UID].pos = livePos
		g_VR.menus[UID].ang = liveAng
		g_VR.menus[UID].cubeMenu = true
		g_VR.menus[UID].attachment = true
		paint()
	end)

	-- Exact heightmenu input pattern
	hook.Add("VRMod_Input", "cube_settings_input", function(action, pressed)
		if not open then return end
		if pressed and (action == "boolean_secondaryfire" or action == "boolean_chat") then
			vrmod.CubeSettings_Close()
			return
		end
		if not pressed then return end
		if g_VR.menuFocus ~= UID then return end
		if action ~= "boolean_primaryfire" and action ~= "boolean_car_mouse_left" then return end
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

	if vrmod.logger then
		vrmod.logger.Info("[CubeSettings] open hand panel %s (heightmenu path)", UID)
	end
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
