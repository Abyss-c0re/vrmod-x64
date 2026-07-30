if SERVER then return end
-- =============================================================================
-- Glorious Crimson Cube — VR settings as INTERACTIVE CUBE
-- Manifest: vrmod.cubeui → VRUtilMenuOpen faces (proper VRMod render path)
-- Desktop: VRUtilOpenMenu Derma
-- =============================================================================

vrmod = vrmod or {}

local open = false
local category = 1
local scroll = 0

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

-- Categories map to cube faces (algocube path digits)
local categories = {
	{
		id = "vision",
		title = "Vision",
		hint = "eyes of the Real",
		path = "cube_gpu",
		digit = 2,
		energy = 0.85,
		rows = {
			{ kind = "slider", label = "Supersample", cvar = "vrmod_supersample", min = 0.5, max = 2.0, decimals = 2,
				help = "Restart VR after change. Cap SBS ≤ 4096." },
			{ kind = "slider", label = "Scale factor", cvar = "vrmod_scalefactor", min = 0.05, max = 4.0, decimals = 2 },
			{ kind = "slider", label = "View scale", cvar = "vrmod_viewscale", min = 0.1, max = 2.0, decimals = 2 },
			{ kind = "slider", label = "FOV scale X", cvar = "vrmod_fovscale_x", min = 0.5, max = 1.5, decimals = 2 },
			{ kind = "slider", label = "FOV scale Y", cvar = "vrmod_fovscale_y", min = 0.5, max = 1.5, decimals = 2 },
			{ kind = "bool", label = "Post-process", cvar = "vrmod_postprocess" },
			{ kind = "bool", label = "3D Skybox", cvar = "vrmod_skybox" },
			{ kind = "bool", label = "Swap eyes", cvar = "vrmod_swap_eyes", help = "If world looks crossed, toggle." },
			{ kind = "action", label = "Border calibrate", cmd = "vrmod_border_calibrate" },
			{ kind = "action", label = "Restart Experience", cmd = "vrmod_experience_reset" },
		},
	},
	{
		id = "controls",
		title = "Controls",
		hint = "hands · will",
		path = "inject_hybrid",
		digit = 1,
		energy = 0.7,
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
		hint = "height · avatar",
		path = "hud_line",
		digit = 0,
		energy = 0.65,
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
		},
	},
	{
		id = "world",
		title = "World",
		hint = "locomotion · climb",
		path = "wivrn",
		digit = 4,
		energy = 0.6,
		rows = {
			{ kind = "bool", label = "Climbing replace", cvar = "vrmod_climbing" },
			{ kind = "bool", label = "Door replace", cvar = "vrmod_doors" },
			{ kind = "bool", label = "Autostart VR", cvar = "vrmod_autostart" },
			{ kind = "action", label = "UI reset surfaces", cmd = "vrmod_vgui_reset" },
			{ kind = "action", label = "Close cube UI", action = function()
				vrmod.CubeSettings_Close()
			end },
		},
	},
	{
		id = "session",
		title = "Session",
		hint = "start · stop",
		path = "gpu_unity",
		digit = 9,
		energy = 0.95,
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
			{ kind = "action", label = "Desktop Derma pane", action = function()
				vrmod.CubeSettings_Close()
				if VRUtilOpenMenu then
					local f = VRUtilOpenMenu()
					if IsValid(f) and vrmod.panel2vr then
						vrmod.panel2vr.ManifestPanel(f, { place = "popup", kind = "panel", hint = "settings_derma" })
					end
				end
			end },
		},
	},
	{
		id = "unity",
		title = "UNITY",
		hint = "algocube law",
		path = "glyph_field",
		digit = 3,
		energy = 1.0,
		rows = {
			{ kind = "action", label = "Law: cube is SoT", action = function() end },
			{ kind = "action", label = "helmet=HUD · blackcube=GPU", action = function() end },
			{ kind = "action", label = "Close interactive cube", action = function()
				vrmod.CubeSettings_Close()
			end },
		},
	},
}

local HEADER = 70
local ROW_H = 44
local PAD = 14
local ROW_TOP = 86

local function rowAt(cat, my)
	if not cat then return nil end
	local y0 = ROW_TOP - scroll
	for i, row in ipairs(cat.rows) do
		local y = y0 + (i - 1) * (ROW_H + 4)
		if my >= y and my < y + ROW_H then
			return i, y, row
		end
	end
end

local function paintContent(w, h, focused, mx, my)
	local cat = categories[category]
	if not cat then return end
	local CU = vrmod.cubeui
	local Text = CU and CU.Text or function(s, f, x, y, c, ax, ay)
		draw.SimpleText(tostring(s or ""), f or "DermaDefault", x, y, c or color_white, ax or 0, ay or 0)
	end
	local muted = (CU and CU.Theme and CU.Theme.muted) or Color(190, 150, 165)
	local text = (CU and CU.Theme and CU.Theme.text) or Color(255, 240, 244)
	local hot = (CU and CU.Theme and CU.Theme.hot) or Color(255, 90, 120)
	local ok = (CU and CU.Theme and CU.Theme.ok) or Color(90, 220, 150)
	local dim = Color(55, 14, 24, 250)

	Text(cat.hint or "", "DermaDefault", PAD, HEADER + 8, muted)

	local y0 = ROW_TOP - scroll
	for i, row in ipairs(cat.rows) do
		local y = y0 + (i - 1) * (ROW_H + 4)
		if y + ROW_H < HEADER + 20 or y > h - 28 then continue end

		local hovered = focused and mx >= PAD and mx <= w - PAD and my >= y and my < y + ROW_H
		surface.SetDrawColor(hovered and 70 or 28, hovered and 18 or 10, hovered and 28 or 16, 240)
		surface.DrawRect(PAD, y, w - PAD * 2, ROW_H)
		if hovered then
			surface.SetDrawColor(hot)
			surface.DrawRect(PAD, y, 4, ROW_H)
		end

		Text(row.label, "DermaDefaultBold", PAD + 14, y + 8, text)

		if row.kind == "bool" then
			local on = getBool(row.cvar, false)
			local bx, by, bw, bh = w - PAD - 52, y + 8, 38, 26
			surface.SetDrawColor(on and ok or dim)
			surface.DrawRect(bx, by, bw, bh)
			Text(on and "ON" or "OFF", "DermaDefault", bx + bw * 0.5, by + bh * 0.5, text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		elseif row.kind == "slider" then
			local val = getFloat(row.cvar, row.min or 0)
			local t = 0
			if row.max and row.min and row.max > row.min then
				t = math.Clamp((val - row.min) / (row.max - row.min), 0, 1)
			end
			local x0, x1 = PAD + 170, w - PAD - 16
			local ty = y + ROW_H * 0.5
			surface.SetDrawColor(dim)
			surface.DrawRect(x0, ty - 3, x1 - x0, 6)
			surface.SetDrawColor(hot)
			surface.DrawRect(x0, ty - 3, (x1 - x0) * t, 6)
			surface.DrawRect(x0 + (x1 - x0) * t - 4, ty - 9, 8, 18)
			local fmt = string.format("%." .. (row.decimals or 2) .. "f", val)
			Text(fmt, "DermaDefault", x0 - 6, ty, muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		elseif row.kind == "action" then
			Text("▸", "DermaDefaultBold", w - PAD - 20, y + ROW_H * 0.5, hot, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		if row.help and hovered then
			Text(row.help, "DermaDefault", PAD + 14, y + 26, muted)
		end
	end

	Text("laser · trigger  ·  secondary closes", "DermaDefault", w * 0.5, h - 14, muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function clickContent(mx, my)
	local cat = categories[category]
	if not cat then return end
	local idx, y, row = rowAt(cat, my)
	if not row then return end

	if row.kind == "slider" then
		local x0, x1 = PAD + 170, 480 - PAD - 16
		local t = math.Clamp((mx - x0) / math.max(1, x1 - x0), 0, 1)
		local val = (row.min or 0) + t * ((row.max or 1) - (row.min or 0))
		if row.decimals == 0 then val = math.floor(val + 0.5) end
		setFloat(row.cvar, val)
		return
	end

	if row.kind == "bool" then
		setBool(row.cvar, not getBool(row.cvar, false))
	elseif row.kind == "action" then
		if row.cmd then
			RunConsoleCommand(row.cmd)
		elseif row.action then
			row.action()
		end
	end
end

function vrmod.CubeSettings_Close()
	if not open then return end
	open = false
	if vrmod.cubeui and vrmod.cubeui.Close then
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
	if not vrmod.cubeui or not vrmod.cubeui.Open then
		if vrmod.logger then vrmod.logger.Warn("[CubeSettings] cubeui missing") end
		if VRUtilOpenMenu then VRUtilOpenMenu() end
		return
	end

	open = true
	category = 1
	scroll = 0

	local faces = {}
	for i, cat in ipairs(categories) do
		faces[i] = {
			title = cat.title,
			path = cat.path,
			digit = cat.digit,
			energy = cat.energy,
			paint = function(w, h, focused, mx, my)
				if category == i then
					paintContent(w, h, focused, mx, my)
				end
			end,
			onSelect = function()
				category = i
				scroll = 0
			end,
			onClick = function(mx, my)
				if category == i then
					clickContent(mx, my)
				end
			end,
		}
	end

	local ok = vrmod.cubeui.Open({
		faces = faces,
		active = category,
		closeOnSecondary = true,
		closeOnQuickmenu = true,
		onFace = function(i)
			category = i
			scroll = 0
		end,
		onClose = function()
			open = false
		end,
	})

	if not ok then
		open = false
		if VRUtilOpenMenu then VRUtilOpenMenu() end
		return
	end

	if vrmod.logger then
		vrmod.logger.Info("[CubeSettings] interactive cube via VRUtilMenuOpen faces")
	end
end

function vrmod.CubeSettings_IsOpen()
	return open
end

-- Derma VRMod Menu title → interactive cube (not float pane)
hook.Add("InitPostEntity", "cube_settings_register", function()
	timer.Simple(0.1, function()
		if not vrmod.panel2vr then return end
		vrmod.panel2vr.RegisterNative("settings", function(_panel, _opts)
			vrmod.CubeSettings_Open()
			return true
		end)
	end)
end)

concommand.Add("vrmod_cube_settings", function()
	vrmod.CubeSettings_Open()
end)

hook.Add("VRMod_Exit", "cube_settings_exit", function()
	vrmod.CubeSettings_Close()
end)
