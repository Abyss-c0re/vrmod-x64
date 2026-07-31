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
		cb:SetConVar(row.cvar)
		cb:SetPos(20, y)
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
	local catalog = vrmod.SettingsCatalog
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

local function TryAddArcVR(sheet)
	if not ConVarExists("arcticvr_virtualstock") then return end
	local t = vgui.Create("DScrollPanel", sheet)
	sheet:AddSheet("ArcVR", t, "icon16/gun.png")
	local function AddSection(parentList, title, builder)
		local cat = vgui.Create("DCollapsibleCategory", parentList)
		cat:SetLabel(title)
		cat:Dock(TOP)
		cat:DockMargin(0, 0, 0, 5)
		cat:SetExpanded(false)
		local form = vgui.Create("DForm", cat)
		form:Dock(FILL)
		form.Header:SetVisible(false)
		form:InvalidateLayout(true)
		builder(form)
		cat:SetContents(form)
		return cat
	end

	AddSection(t, "Controls", function(f)
		f:CheckBox("Grip with reload key", "arcticvr_grip_withreloadkey")
		f:CheckBox("Magazine bump preload", "arcticvr_mag_bumpreload")
		f:CheckBox("Alternative frontgrip mode", "arcticvr_grip_alternative_mode")
		f:NumSlider("Slide magnification", "arcticvr_slide_magnification", 1, 10, 2)
		f:NumSlider("Grip magnification", "arcticvr_grip_magnification", 1, 10, 2)
		f:CheckBox("Disable reload with key", "arcticvr_disable_reloadkey")
		f:CheckBox("Disable grab reload", "arcticvr_disable_grabreload")
	end)
	AddSection(t, "Virtual Stock & Fixes", function(f)
		f:CheckBox("Enable virtual stock", "arcticvr_virtualstock")
		f:NumSlider("Frontgrip power", "arcticvr_2h_sens", 0, 2, 2)
		f:CheckBox("Grenade pin enable", "arcticvr_grenade_pin_enable")
		f:CheckBox("Shoot system fix", "arcticvr_shootsys")
		f:CheckBox("Misc client fix", "arcticvr_test_cl_misc_fix")
	end)
	AddSection(t, "Mag Pouches", function(f)
		f:NumSlider("Default pouch distance", "arcticvr_defpouchdist", 0, 200, 2)
		f:CheckBox("Hybrid pouch", "arcticvr_hybridpouch")
		f:NumSlider("Hybrid pouch distance", "arcticvr_hybridpouchdist", 0, 200, 1)
		f:CheckBox("Head pouch", "arcticvr_headpouch")
		f:NumSlider("Head pouch distance", "arcticvr_headpouchdist", 0, 200, 1)
		f:CheckBox("Infinite pouch range", "arcticvr_infpouch")
	end)
	AddSection(t, "Server Settings", function(f)
		f:CheckBox("Allow reload key (all guns)", "arcticvr_allgun_allow_reloadkey")
		f:CheckBox("Allow reload key (client)", "arcticvr_allgun_allow_reloadkey_client")
		f:CheckBox("Bump reload (all guns)", "arcticvr_bumpreload_allgun")
		f:CheckBox("Bump reload (client)", "arcticvr_bumpreload_allgun_client")
		f:CheckBox("Normalize default ammo", "arcticvr_defaultammo_normalize")
		f:CheckBox("Alternate physics bullets", "arcticvr_physical_bullets")
		f:NumSlider("Mag pickup delay", "arcticvr_net_magtimertime", 0, 1, 2)
	end)
end

function VRUtilOpenMenu()
	if IsValid(frame) then
		frame:MakePopup()
		frame:MoveToFront()
		return frame
	end

	frame = vgui.Create("DFrame")
	frame:SetSize(440, 560)
	frame:SetTitle("VRMod Menu")
	frame:MakePopup()
	frame:Center()

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

	-- Same catalog as VR cube settings
	PopulateFromCatalog(sheet)

	-- ArcVR if present (optional third-party)
	if ConVarExists("arcticvr_virtualstock") then
		TryAddArcVR(sheet)
	else
		timer.Create("VRMod_CheckArcVR", 1, 3, function()
			if not IsValid(sheet) then
				timer.Remove("VRMod_CheckArcVR")
				return
			end
			if ConVarExists("arcticvr_virtualstock") then
				timer.Remove("VRMod_CheckArcVR")
				TryAddArcVR(sheet)
			end
		end)
	end

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
