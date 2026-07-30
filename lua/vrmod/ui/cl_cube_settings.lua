if SERVER then return end
-- =============================================================================
-- Cube Settings — interactive cube on one hand VRMod menu (cubeui_main)
-- Click/close must work: laser lock panel · X button · secondary · rows
-- =============================================================================

vrmod = vrmod or {}

local open = false
local category = 1

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

local categories = {
	{
		id = "vision", title = "Vision", path = "cube_gpu", digit = 2, energy = 0.85,
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
			{ kind = "action", label = "Restart Experience", cmd = "vrmod_experience_reset" },
		},
	},
	{
		id = "controls", title = "Controls", path = "inject_hybrid", digit = 1, energy = 0.7,
		rows = {
			{ kind = "bool", label = "Smooth turning", cvar = "vrmod_smoothturn" },
			{ kind = "slider", label = "Turn rate", cvar = "vrmod_smoothturnrate", min = 1, max = 1000, decimals = 0 },
			{ kind = "bool", label = "Teleport", cvar = "vrmod_allow_teleport_client" },
			{ kind = "bool", label = "Teleport left hand", cvar = "vrmod_teleport_use_left" },
			{ kind = "bool", label = "Floating hands", cvar = "vrmod_floatinghands" },
			{ kind = "bool", label = "Laser pointer", cvar = "vrmod_laserpointer" },
			{ kind = "action", label = "Edit actions", cmd = "vrmod_actioneditor" },
		},
	},
	{
		id = "posture", title = "Posture", path = "hud_line", digit = 0, energy = 0.65,
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
		id = "world", title = "World", path = "wivrn", digit = 4, energy = 0.6,
		rows = {
			{ kind = "bool", label = "Climbing replace", cvar = "vrmod_climbing" },
			{ kind = "bool", label = "Door replace", cvar = "vrmod_doors" },
			{ kind = "bool", label = "Autostart VR", cvar = "vrmod_autostart" },
			{ kind = "action", label = "UI reset", cmd = "vrmod_vgui_reset" },
			{ kind = "action", label = "Close cube", action = function() vrmod.CubeSettings_Close() end },
		},
	},
	{
		id = "session", title = "Session", path = "gpu_unity", digit = 9, energy = 0.95,
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
			{ kind = "action", label = "Desktop Derma", action = function()
				vrmod.CubeSettings_Close()
				if VRUtilOpenMenu then VRUtilOpenMenu() end
			end },
		},
	},
	{
		id = "unity", title = "UNITY", path = "glyph_field", digit = 3, energy = 1.0,
		rows = {
			{ kind = "action", label = "cube SoT · law d2", action = function() end },
			{ kind = "action", label = "helmet=HUD · host=GPU", action = function() end },
			{ kind = "action", label = "Close", action = function() vrmod.CubeSettings_Close() end },
		},
	},
}

local ROW_H = 42
local PAD = 12
local ROW0 = 8

local function text(s, f, x, y, c, ax, ay)
	if vrmod.cubeui and vrmod.cubeui.Text then
		vrmod.cubeui.Text(s, f, x, y, c, ax, ay)
	else
		draw.SimpleText(tostring(s or ""), f or "DermaDefault", x, y, c or color_white, ax or 0, ay or 0)
	end
end

local function paintContent(w, h, focused, lx, ly)
	local cat = categories[category]
	if not cat then return end
	local T = (vrmod.cubeui and vrmod.cubeui.Theme) or {}
	local muted = T.muted or Color(190, 150, 165)
	local col = T.text or Color(255, 240, 244)
	local hot = T.hot or Color(255, 90, 120)
	local ok = T.ok or Color(90, 220, 150)
	local dim = Color(55, 14, 24, 250)

	text(cat.title .. " settings", "DermaDefaultBold", PAD, 4, col)
	text("trigger rows · laser lock required", "DermaDefault", PAD, 22, muted)

	for i, row in ipairs(cat.rows) do
		local y = ROW0 + 36 + (i - 1) * (ROW_H + 4)
		if y > h - 20 then break end
		local hovered = focused and lx >= PAD and lx <= w - PAD and ly >= y and ly < y + ROW_H
		surface.SetDrawColor(hovered and 80 or 32, hovered and 20 or 12, hovered and 30 or 18, 245)
		surface.DrawRect(PAD, y, w - PAD * 2, ROW_H)
		if hovered then
			surface.SetDrawColor(hot)
			surface.DrawRect(PAD, y, 4, ROW_H)
		end
		text(row.label, "DermaDefaultBold", PAD + 12, y + 12, col)

		if row.kind == "bool" then
			local on = getBool(row.cvar, false)
			local bx = w - PAD - 48
			surface.SetDrawColor(on and ok or dim)
			surface.DrawRect(bx, y + 8, 40, 26)
			text(on and "ON" or "OFF", "DermaDefault", bx + 20, y + 21, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		elseif row.kind == "slider" then
			local val = getFloat(row.cvar, row.min or 0)
			local t = 0
			if row.max and row.min and row.max > row.min then
				t = math.Clamp((val - row.min) / (row.max - row.min), 0, 1)
			end
			local x0, x1 = PAD + 150, w - PAD - 12
			local ty = y + ROW_H * 0.5
			surface.SetDrawColor(dim)
			surface.DrawRect(x0, ty - 3, x1 - x0, 6)
			surface.SetDrawColor(hot)
			surface.DrawRect(x0, ty - 3, (x1 - x0) * t, 6)
			surface.DrawRect(x0 + (x1 - x0) * t - 4, ty - 8, 8, 16)
			text(string.format("%." .. (row.decimals or 2) .. "f", val), "DermaDefault", x0 - 6, ty, muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		elseif row.kind == "action" then
			text("▸", "DermaDefaultBold", w - PAD - 18, y + ROW_H * 0.5, hot, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
end

local function clickContent(lx, ly)
	local cat = categories[category]
	if not cat then return end
	local w = 640 - 246 -- content panel width inside cubeui
	for i, row in ipairs(cat.rows) do
		local y = ROW0 + 36 + (i - 1) * (ROW_H + 4)
		if ly >= y and ly < y + ROW_H and lx >= PAD and lx <= w - PAD then
			if row.kind == "slider" then
				local x0, x1 = PAD + 150, w - PAD - 12
				local t = math.Clamp((lx - x0) / math.max(1, x1 - x0), 0, 1)
				local val = (row.min or 0) + t * ((row.max or 1) - (row.min or 0))
				if row.decimals == 0 then val = math.floor(val + 0.5) end
				setFloat(row.cvar, val)
			elseif row.kind == "bool" then
				setBool(row.cvar, not getBool(row.cvar, false))
			elseif row.kind == "action" then
				if row.cmd then RunConsoleCommand(row.cmd)
				elseif row.action then row.action() end
			end
			return
		end
	end
end

function vrmod.CubeSettings_Close()
	if not open and not (vrmod.cubeui and vrmod.cubeui.IsOpen and vrmod.cubeui.IsOpen()) then
		return
	end
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
	if open or (vrmod.cubeui and vrmod.cubeui.IsOpen and vrmod.cubeui.IsOpen()) then
		vrmod.CubeSettings_Close()
		return
	end
	if not vrmod.cubeui or not vrmod.cubeui.Open then
		if VRUtilOpenMenu then VRUtilOpenMenu() end
		return
	end

	open = true
	category = 1

	local faces = {}
	for i, cat in ipairs(categories) do
		faces[i] = {
			title = cat.title,
			path = cat.path,
			digit = cat.digit,
			energy = cat.energy,
			paint = function(w, h, focused, lx, ly)
				if category == i then
					paintContent(w, h, focused, lx, ly)
				end
			end,
			onSelect = function()
				category = i
			end,
			onClick = function(lx, ly)
				if category == i then
					clickContent(lx, ly)
				end
			end,
		}
	end

	local ok = vrmod.cubeui.Open({
		faces = faces,
		active = 1,
		closeOnSecondary = true,
		closeOnQuickmenu = true,
		onFace = function(i)
			category = i
		end,
		onClose = function()
			open = false
		end,
	})

	if not ok then
		open = false
		if VRUtilOpenMenu then VRUtilOpenMenu() end
	end
end

function vrmod.CubeSettings_IsOpen()
	return open or (vrmod.cubeui and vrmod.cubeui.IsOpen and vrmod.cubeui.IsOpen())
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

hook.Add("VRMod_Exit", "cube_settings_exit", function()
	vrmod.CubeSettings_Close()
end)
