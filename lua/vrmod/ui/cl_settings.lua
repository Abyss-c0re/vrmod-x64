if SERVER then return end
-- =============================================================================
-- VRMod Settings (Derma) — desktop / non-VR
-- Data SoT: vrmod.SettingsCatalog (same as VR Cube settings)
-- =============================================================================

local frame = nil

local function AddRowToForm(parent, row, y)
	-- parent is DScrollPanel or DPanel; returns next y
	if row.kind == "header" then
		local lbl = vgui.Create("DLabel", parent)
		lbl:SetText(row.label or "")
		lbl:SetFont("DermaDefaultBold")
		lbl:SetDark(true)
		lbl:SetPos(16, y)
		lbl:SizeToContents()
		return y + 22
	end
	if row.kind == "help" then
		local lbl = vgui.Create("DLabel", parent)
		lbl:SetText(row.label or "")
		lbl:SetDark(true)
		lbl:SetTextColor(Color(90, 90, 90))
		lbl:SetPos(20, y)
		lbl:SetWide(360)
		lbl:SetWrap(true)
		lbl:SetAutoStretchVertical(true)
		lbl:SizeToContentsY()
		return y + math.max(18, lbl:GetTall() + 4)
	end
	if row.kind == "bool" and row.cvar then
		local cb = vgui.Create("DCheckBoxLabel", parent)
		cb:SetDark(true)
		cb:SetText(row.label or row.cvar)
		cb:SetPos(20, y)
		local cv = GetConVar(row.cvar)
		if cv then cb:SetValue(cv:GetBool() and 1 or 0) end
		-- Don't only SetConVar: force SetBool + HUD refresh so toggle always sticks
		function cb:OnChange(val)
			if vrmod.SettingsSetBool then
				vrmod.SettingsSetBool(row.cvar, val)
			elseif cv then
				cv:SetBool(val)
			else
				RunConsoleCommand(row.cvar, val and "1" or "0")
			end
		end
		cb:SizeToContents()
		return y + 22
	end
	if row.kind == "slider" and row.cvar then
		local s = vgui.Create("DNumSlider", parent)
		s:SetPos(16, y)
		s:SetSize(380, 28)
		s:SetDark(true)
		s:SetText(row.label or row.cvar)
		s:SetMin(row.min or 0)
		s:SetMax(row.max or 1)
		s:SetDecimals(row.decimals or 2)
		s:SetConVar(row.cvar)
		return y + 36
	end
	if row.kind == "combo" and row.cvar and row.choices then
		local lbl = vgui.Create("DLabel", parent)
		lbl:SetText(row.label or row.cvar)
		lbl:SetDark(true)
		lbl:SetPos(20, y + 4)
		lbl:SizeToContents()
		local cb = vgui.Create("DComboBox", parent)
		cb:SetPos(160, y)
		cb:SetSize(200, 24)
		local cv = GetConVar(row.cvar)
		local cur = cv and cv:GetInt() or row.choices[1].value
		cb._silent = false
		for _, ch in ipairs(row.choices) do
			cb:AddChoice(ch.text, ch.value, ch.value == cur)
		end
		function cb:OnSelect(_, _, data)
			if self._silent then return end
			RunConsoleCommand(row.cvar, tostring(data))
		end
		function cb:Think()
			local c = GetConVar(row.cvar)
			if not c then return end
			local v = c:GetInt()
			if self._last == v then return end
			self._last = v
			self._silent = true
			for i, ch in ipairs(row.choices) do
				if ch.value == v then
					self:ChooseOptionID(i)
					break
				end
			end
			self._silent = false
		end
		return y + 32
	end
	if row.kind == "color" and row.cvar then
		-- Same DColorMixer pattern as classic VRMod HUD/UI tab
		local lbl = vgui.Create("DLabel", parent)
		lbl:SetText(row.label or row.cvar)
		lbl:SetDark(true)
		lbl:SetFont("DermaDefaultBold")
		lbl:SetPos(20, y)
		lbl:SizeToContents()
		y = y + 20
		local mixer = vgui.Create("DColorMixer", parent)
		mixer:SetPos(20, y)
		mixer:SetSize(380, 160)
		mixer:SetPalette(true)
		mixer:SetAlphaBar(true)
		mixer:SetWangs(true)
		local col = vrmod.SettingsGetColor and vrmod.SettingsGetColor(row.cvar) or Color(255, 0, 0, 255)
		mixer:SetColor(col)
		mixer._cvar = row.cvar
		mixer._silent = false
		function mixer:ValueChanged(c)
			if self._silent then return end
			if vrmod.SettingsSetColor then
				vrmod.SettingsSetColor(self._cvar, c)
			else
				RunConsoleCommand(self._cvar, string.format("%d,%d,%d,%d", c.r, c.g, c.b, c.a))
			end
		end
		function mixer:Think()
			local c = GetConVar(self._cvar)
			if not c then return end
			local s = c:GetString()
			if self._lastStr == s then return end
			self._lastStr = s
			local parsed = vrmod.SettingsParseColor and vrmod.SettingsParseColor(s) or Color(255, 0, 0, 255)
			self._silent = true
			self:SetColor(parsed)
			self._silent = false
		end
		return y + 170
	end
	if row.kind == "action" then
		local btn = vgui.Create("DButton", parent)
		btn:SetText(row.label or "Action")
		btn:SetPos(20, y)
		btn:SetSize(360, 28)
		function btn:DoClick()
			if row.cmd then
				RunConsoleCommand(row.cmd)
			elseif row.action_id and vrmod.SettingsRunAction then
				vrmod.SettingsRunAction(row.action_id, {
					close = function()
						if IsValid(frame) then frame:Remove() end
					end,
				})
			end
		end
		return y + 34
	end
	return y
end

local function PopulateFromCatalog(sheet)
	local catalog = (vrmod.GetSettingsCatalog and vrmod.GetSettingsCatalog()) or vrmod.SettingsCatalog
	if not catalog then
		local err = vgui.Create("DLabel", sheet)
		err:SetText("Settings catalog missing (sh_settings_catalog.lua)")
		err:Dock(FILL)
		return
	end

	for _, cat in ipairs(catalog) do
		local scroll = vgui.Create("DScrollPanel", sheet)
		sheet:AddSheet(cat.title or cat.id or "?", scroll, cat.icon)
		function scroll:Paint(w, h)
			surface.SetDrawColor(234, 234, 234)
			surface.DrawRect(0, 0, w, h)
		end
		local canvas = scroll:GetCanvas()
		local y = 10
		for _, row in ipairs(cat.rows or {}) do
			y = AddRowToForm(scroll, row, y)
		end
		-- spacer so last rows are reachable
		local pad = vgui.Create("DPanel", scroll)
		pad:SetPos(0, y + 8)
		pad:SetSize(10, 20)
		pad.Paint = nil
	end
end

-- ArcVR pane is injected by vrmod.GetSettingsCatalog() when ArcVR is mounted.
-- No separate DPropertySheet sheet — avoids double UI and keeps VR Cube in sync.

function VRUtilOpenMenu()
	if IsValid(frame) then
		frame:MakePopup()
		frame:MoveToFront()
		return frame
	end

	frame = vgui.Create("DFrame")
	-- Global UI scale (same convar as VR menus / Derma shells)
	local uiS = (vrmod.GetUIScale and vrmod.GetUIScale()) or 1
	local fw, fh
	if vrmod.GetVRUIPanelMetrics and g_VR and g_VR.active then
		fw, fh = vrmod.GetVRUIPanelMetrics("settings")
	else
		fw, fh = math.floor(440 * uiS + 0.5), math.floor(560 * uiS + 0.5)
		fw = math.Clamp(fw, 360, math.min(ScrW() - 20, 900))
		fh = math.Clamp(fh, 420, math.min(ScrH() - 20, 1000))
	end
	frame:SetSize(fw, fh)
	frame:SetTitle("VRMod Menu")
	frame:MakePopup()
	frame:Center()
	-- Live rescale when vrmod_ui_scale changes while open
	frame._uiBaseW, frame._uiBaseH = 440, 560
	function frame:Think()
		if not vrmod.GetUIScale then return end
		local s = vrmod.GetUIScale()
		if self._lastUiS == s then return end
		self._lastUiS = s
		local nw = math.Clamp(math.floor(self._uiBaseW * s + 0.5), 360, math.min(ScrW() - 20, 900))
		local nh = math.Clamp(math.floor(self._uiBaseH * s + 0.5), 420, math.min(ScrH() - 20, 1000))
		self:SetSize(nw, nh)
		self:Center()
	end

	local error = vrmod.GetStartupError and vrmod.GetStartupError()
	if error and error ~= "Already running" then
		local tmp = vgui.Create("DLabel", frame)
		tmp:SetText(error)
		tmp:SetWrap(true)
		tmp:SetSize(250, 100)
		tmp:SetAutoStretchVertical(true)
		tmp:SetFont("Trebuchet24")
		function tmp:PerformLayout()
			tmp:Center()
		end
		return frame
	end

	local sheet = vgui.Create("DPropertySheet", frame)
	sheet:SetPadding(1)
	sheet:Dock(FILL)
	frame.DPropertySheet = sheet

	-- Same catalog as VR cube settings (includes ArcVR when addon is present)
	PopulateFromCatalog(sheet)

	-- Late ArcVR load: if convars appear after menu open, user reopens for ArcVR tab
	-- (Cube Settings always re-reads GetSettingsCatalog each paint — no rebuild needed)

	-- Extra debug subsystem toggles (dynamic, not in static catalog)
	do
		local scroll = vgui.Create("DScrollPanel", sheet)
		sheet:AddSheet("Debug+", scroll, "icon16/bug.png")
		local y = 10
		local order = vrmod.subsystemOrder or { "api", "utils", "core", "network", "input", "player", "physics", "pickup", "combat", "ui" }
		for _, subsystem in ipairs(order) do
			local cvarName = "vrmod_debug_" .. subsystem
			if GetConVar(cvarName) then
				local cb = vgui.Create("DCheckBoxLabel", scroll)
				cb:SetDark(true)
				cb:SetText("Debug " .. subsystem)
				cb:SetConVar(cvarName)
				cb:SetPos(20, y)
				cb:SizeToContents()
				y = y + 22
			end
		end
	end

	local bottomPanel = vgui.Create("DPanel", frame)
	bottomPanel:Dock(BOTTOM)
	bottomPanel:SetTall(40)
	bottomPanel.Paint = nil

	local versionLabel = vgui.Create("DLabel", bottomPanel)
	local ver = (vrmod.GetVersion and vrmod.GetVersion()) or "?"
	local mod = (vrmod.GetModuleVersion and vrmod.GetModuleVersion()) or "?"
	versionLabel:SetText("Addon " .. ver .. " · Module " .. mod)
	versionLabel:SizeToContents()
	versionLabel:SetPos(5, 12)

	local exitBtn = vgui.Create("DButton", bottomPanel)
	exitBtn:SetText("Exit VR")
	exitBtn:Dock(RIGHT)
	exitBtn:DockMargin(0, 5, 0, 5)
	exitBtn:SetWide(80)
	exitBtn:SetEnabled(g_VR and g_VR.active)
	function exitBtn:DoClick()
		frame:Remove()
		if VRUtilClientExit then VRUtilClientExit() end
	end

	local startBtn = vgui.Create("DButton", bottomPanel)
	startBtn:SetText((g_VR and g_VR.active) and "Restart" or "Start")
	startBtn:Dock(RIGHT)
	startBtn:DockMargin(0, 5, 5, 5)
	startBtn:SetWide(80)
	function startBtn:DoClick()
		frame:Remove()
		if g_VR and g_VR.active then
			VRUtilClientExit()
			timer.Simple(1, function() VRUtilClientStart() end)
		else
			VRUtilClientStart()
		end
	end

	-- Extension hook (legacy)
	local hooks = hook.GetTable().VRMod_Menu or {}
	local names = {}
	for k in pairs(hooks) do
		names[#names + 1] = k
	end
	table.sort(names)
	for _, v in ipairs(names) do
		local func = hooks[v]
		if isfunction(func) then pcall(func, frame) end
	end

	return frame
end

-- Desktop concommand
concommand.Add("vrmod_menu", function()
	if vrmod.Settings_Open then
		vrmod.Settings_Open()
	else
		VRUtilOpenMenu()
	end
end)
