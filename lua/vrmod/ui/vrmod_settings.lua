if SERVER then return end
local convars = vrmod.GetConvars()
local frame = nil
function VRUtilOpenMenu()
	if IsValid(frame) then return frame end
	frame = vgui.Create("DFrame")
	frame:SetSize(420, 505)
	frame:SetTitle("VRMod Menu")
	frame:MakePopup()
	frame:Center()
	local error = vrmod.GetStartupError()
	if error and error ~= "Already running" then
		local tmp = vgui.Create("DLabel", frame)
		tmp:SetText(error)
		tmp:SetWrap(true)
		tmp:SetSize(250, 100)
		tmp:SetAutoStretchVertical(true)
		tmp:SetFont("vrmod_Trebuchet24")
		function tmp:PerformLayout()
			tmp:Center()
		end
		return frame
	end

	local sheet = vgui.Create("DPropertySheet", frame)
	sheet:SetPadding(1)
	sheet:Dock(FILL)
	frame.DPropertySheet = sheet
	-- Create "Settings" tab container
	local settingsPanel = vgui.Create("DPanel", sheet)
	settingsPanel:Dock(FILL)
	-- Add the tab
	sheet:AddSheet("Settings", settingsPanel, "icon16/cog.png")
	-- Scrollable panel
	local scrollPanel = vgui.Create("DScrollPanel", settingsPanel)
	scrollPanel:Dock(FILL)
	-- Form container used by settings hook
	local form = vgui.Create("DForm", scrollPanel)
	form:SetName("Settings")
	form:Dock(TOP)
	form.Header:SetVisible(false)
	form.Paint = nil
	-- Expose the form to the hook
	frame.SettingsForm = form
	-- Bottom info and buttons
	local bottomPanel = vgui.Create("DPanel", frame)
	bottomPanel:Dock(BOTTOM)
	bottomPanel:SetTall(35)
	bottomPanel.Paint = nil
	local versionLabel = vgui.Create("DLabel", bottomPanel)
	versionLabel:SetText("Addon version: " .. vrmod.GetVersion() .. "\nModule version: " .. vrmod.GetModuleVersion())
	versionLabel:SizeToContents()
	versionLabel:SetPos(5, 5)
	local exitBtn = vgui.Create("DButton", bottomPanel)
	exitBtn:SetText("Exit")
	exitBtn:Dock(RIGHT)
	exitBtn:DockMargin(0, 5, 0, 0)
	exitBtn:SetWide(96)
	exitBtn:SetEnabled(g_VR.active)
	function exitBtn:DoClick()
		frame:Remove()
		VRUtilClientExit()
	end

	local startBtn = vgui.Create("DButton", bottomPanel)
	startBtn:SetText(g_VR.active and "Restart" or "Start")
	startBtn:Dock(RIGHT)
	startBtn:DockMargin(0, 5, 5, 0)
	startBtn:SetWide(96)
	function startBtn:DoClick()
		frame:Remove()
		if g_VR.active then
			VRUtilClientExit()
			timer.Simple(1, function() VRUtilClientStart() end)
		else
			VRUtilClientStart()
		end
	end

	local form = frame.SettingsForm
	-- Controls Section
	local controlsPanel = vgui.Create("DForm", form)
	controlsPanel:SetName("Controls")
	controlsPanel:Dock(TOP)
	controlsPanel:DockMargin(10, 10, 10, 0)
	controlsPanel:SetExpanded(true)
	-- Controller oriented locomotion
	local controllerLocomotion = vgui.Create("DCheckBoxLabel", controlsPanel)
	controlsPanel:AddItem(controllerLocomotion)
	controllerLocomotion:SetDark(true)
	controllerLocomotion:SetText("Controller oriented locomotion")
	controllerLocomotion:SetChecked(convars.vrmod_controlleroriented:GetBool())
	function controllerLocomotion:OnChange(val)
		convars.vrmod_controlleroriented:SetBool(val)
	end

	-- Smooth turning
	local smoothTurning = vgui.Create("DCheckBoxLabel", controlsPanel)
	controlsPanel:AddItem(smoothTurning)
	smoothTurning:SetDark(true)
	smoothTurning:SetText("Smooth turning")
	smoothTurning:SetChecked(convars.vrmod_smoothturn:GetBool())
	function smoothTurning:OnChange(val)
		convars.vrmod_smoothturn:SetBool(val)
	end

	-- Smooth turn rate slider
	local turnRateSlider = vgui.Create("DNumSlider", controlsPanel)
	controlsPanel:AddItem(turnRateSlider)
	turnRateSlider:SetMin(1)
	turnRateSlider:SetMax(360)
	turnRateSlider:SetDecimals(0)
	turnRateSlider:SetValue(convars.vrmod_smoothturnrate:GetInt())
	turnRateSlider:SetDark(true)
	turnRateSlider:SetText("Smooth turn rate")
	function turnRateSlider:OnValueChanged(val)
		convars.vrmod_smoothturnrate:SetInt(val)
	end

	-- Teleportation
	controlsPanel:CheckBox("Teleportation (Client)", "vrmod_allow_teleport_client")
	-- Alternative head angles
	local headAngleBox = vgui.Create("DCheckBoxLabel", controlsPanel)
	controlsPanel:AddItem(headAngleBox)
	headAngleBox:SetDark(true)
	headAngleBox:SetText("Alternative head angle manipulation method")
	headAngleBox:SetChecked(convars.vrmod_althead:GetBool())
	function headAngleBox:OnChange(val)
		convars.vrmod_althead:SetBool(val)
	end

	controlsPanel:ControlHelp("Less precise, compatibility for jigglebones")
	-- Edit custom input actions
	local actionBtn = vgui.Create("DButton", controlsPanel)
	controlsPanel:AddItem(actionBtn)
	actionBtn:SetText("Edit custom controller input actions")
	function actionBtn:DoClick()
		RunConsoleCommand("vrmod_actioneditor")
	end

	-- Controller-offset sliders under Controls
	local offsetForm = vgui.Create("DForm", form)
	offsetForm:SetName("Controller offsets")
	offsetForm:Dock(TOP)
	offsetForm:DockMargin(10, 10, 10, 0)
	offsetForm:SetExpanded(false)
	local function AddOffsetSlider(name, convar, mn, mx)
		local s = offsetForm:NumSlider(name, convar, mn, mx, 0)
		function s:PerformLayout()
			self.TextArea:SetWide(30)
			self.Label:SetWide(30)
		end
	end

	AddOffsetSlider("X", "vrmod_controlleroffset_x", -30, 30)
	AddOffsetSlider("Y", "vrmod_controlleroffset_y", -30, 30)
	AddOffsetSlider("Z", "vrmod_controlleroffset_z", -30, 30)
	AddOffsetSlider("Pitch", "vrmod_controlleroffset_pitch", -180, 180)
	AddOffsetSlider("Yaw", "vrmod_controlleroffset_yaw", -180, 180)
	AddOffsetSlider("Roll", "vrmod_controlleroffset_roll", -180, 180)
	local applyBtn = offsetForm:Button("Apply offsets", nil)
	function applyBtn:OnReleased()
		local x = convars.vrmod_controlleroffset_x:GetFloat()
		local y = convars.vrmod_controlleroffset_y:GetFloat()
		local z = convars.vrmod_controlleroffset_z:GetFloat()
		local p = convars.vrmod_controlleroffset_pitch:GetFloat()
		local yw = convars.vrmod_controlleroffset_yaw:GetFloat()
		local r = convars.vrmod_controlleroffset_roll:GetFloat()
		if g_VR then
			g_VR.rightControllerOffsetPos = Vector(x, y, z)
			g_VR.leftControllerOffsetPos = Vector(x, -y, z)
			g_VR.rightControllerOffsetAng = Angle(p, yw, r)
			g_VR.leftControllerOffsetAng = g_VR.rightControllerOffsetAng
		end
	end

	local resetBtn = offsetForm:Button("Reset offsets", "")
	function resetBtn:OnReleased()
		-- Reset convars to their default values
		RunConsoleCommand("vrmod_controlleroffset_x", "-15")
		RunConsoleCommand("vrmod_controlleroffset_y", "-1")
		RunConsoleCommand("vrmod_controlleroffset_z", "5")
		RunConsoleCommand("vrmod_controlleroffset_pitch", "50")
		RunConsoleCommand("vrmod_controlleroffset_yaw", "0")
		RunConsoleCommand("vrmod_controlleroffset_roll", "0")
		-- Also immediately apply to g_VR (if table exists)
		if g_VR then
			g_VR.rightControllerOffsetPos = Vector(-15, -1, 5)
			g_VR.leftControllerOffsetPos = Vector(-15, 1, 5)
			g_VR.rightControllerOffsetAng = Angle(50, 0, 0)
			g_VR.leftControllerOffsetAng = Angle(50, 0, 0)
		end
	end

	-- Core settings
	form:CheckBox("Use floating hands", "vrmod_floatinghands")
	form:CheckBox("Use weapon world models", "vrmod_useworldmodels")
	local laser_pointer = form:CheckBox("Add laser pointer to tools/weapons")
	laser_pointer:SetChecked(GetConVar("vrmod_laserpointer"):GetBool())
	function laser_pointer:OnChange(val)
		RunConsoleCommand("vrmod_togglelaserpointer")
	end

	local heightCheckbox = form:CheckBox("Show height adjustment menu", "vrmod_heightmenu")
	local checkTime = 0
	function heightCheckbox:OnChange(checked)
		if checked and SysTime() - checkTime < 0.1 then VRUtilOpenHeightMenu() end
		checkTime = SysTime()
	end

	form:CheckBox("Enable seated offset", "vrmod_seated")
	form:ControlHelp("Adjust from height adjustment menu")
	form:CheckBox("Automatically start VR after map loads", "vrmod_autostart")
	form:CheckBox("Replace climbing mechanics (when available)", "vrmod_climbing")
	form:CheckBox("Replace door use mechanics (when available)", "vrmod_doors")
	form:Button("Reset settings to default", "vrmod_reset")
	-- ─────────────── Rendering Tab ───────────────
	do
		local t = vgui.Create("DScrollPanel", sheet)
		sheet:AddSheet("Rendering", t, "icon16/monitor.png")
		function t:Paint(w, h)
			surface.SetDrawColor(234, 234, 234) -- solid white
			surface.DrawRect(0, 0, w, h)
		end

		local function AddCB(lbl, cv, y)
			local cb = t:Add("DCheckBoxLabel")
			cb:SetDark(true)
			cb:SetText(lbl)
			cb:SetConVar(cv)
			cb:SetPos(20, y)
			cb:SizeToContents()
			return y + 25
		end

		local y = 10
		surface.CreateFont("BoldSliderFont", {
			font = "Tahoma",
			size = 13,
			weight = 1000,
		})

		-- Desktop-view combo
		do
			local panel = vgui.Create("DPanel", t)
			panel:SetSize(300, 30)
			panel:SetPos(20, y)
			panel.Paint = nil
			local lbl = vgui.Create("DLabel", panel)
			lbl:SetPos(0, 5)
			lbl:SetSize(90, 20)
			lbl:SetDark(true)
			lbl:SetText("Desktop view:")
			lbl:SetColor(Color(0, 0, 0))
			local cb = vgui.Create("DComboBox", panel)
			cb:SetPos(95, 2)
			cb:SetSize(150, 25)
			cb:AddChoice("none")
			cb:AddChoice("left eye")
			cb:AddChoice("right eye")
			function cb:OnSelect(index)
				convars.vrmod_desktopview:SetInt(index)
			end

			function cb:Think()
				local v = convars.vrmod_desktopview:GetInt()
				if self.ConvarVal ~= v then
					self.ConvarVal = v
					self:ChooseOptionID(v)
				end
			end

			y = y + 40
		end

		y = AddCB("Enable engine postprocessing", "vrmod_postprocess", y)
		y = AddCB("Auto offset (disable if having distortion)", "vrmod_renderoffset", y)
		do
			local s = vgui.Create("DNumSlider", t)
			s:SetPos(20, y + 10)
			s:SetSize(370, 25)
			s:SetDark(true)
			s:SetText("View scale")
			s:SetMin(0.1)
			s:SetMax(2.0)
			s:SetDecimals(2)
			s:SetConVar("vrmod_viewscale")
			y = y + 40
		end

		do
			local label = vgui.Create("DLabel", t)
			label:SetPos(20, y + 5)
			label:SetSize(370, 30)
			label:SetDark(true)
			label:SetText("Increasing this makes the world appear smaller—useful for correcting scale if everything feels giant or too close.")
			label:SetWrap(true)
			label:SetAutoStretchVertical(true)
			label:SetFont("BoldSliderFont")
			y = y + 35
		end

		do
			local s = vgui.Create("DNumSlider", t)
			s:SetPos(20, y + 10)
			s:SetSize(370, 25)
			s:SetDark(true)
			s:SetText("Fov scale X")
			s:SetMin(0.1)
			s:SetMax(2.0)
			s:SetDecimals(2)
			s:SetConVar("vrmod_fovscale_x")
			y = y + 40
		end

		do
			local s = vgui.Create("DNumSlider", t)
			s:SetPos(20, y + 10)
			s:SetSize(370, 25)
			s:SetDark(true)
			s:SetText("Fov scale Y")
			s:SetMin(0.1)
			s:SetMax(2.0)
			s:SetDecimals(2)
			s:SetConVar("vrmod_fovscale_y")
			y = y + 40
		end

		do
			local label = vgui.Create("DLabel", t)
			label:SetPos(20, y + 5)
			label:SetSize(370, 30)
			label:SetDark(true)
			label:SetText("FOV scale lets you fine-tune horizontal and vertical field of view.\nUse only if you notice lens warping or feel discomfort. \nValues below 1.0 will make FOV wider")
			label:SetWrap(true)
			label:SetAutoStretchVertical(true)
			label:SetFont("BoldSliderFont")
			y = y + 35
		end

		do
			local s = vgui.Create("DNumSlider", t)
			s:SetPos(20, y + 10)
			s:SetSize(370, 25)
			s:SetDark(true)
			s:SetText("ZNear")
			s:SetMin(-3.0)
			s:SetMax(3.0)
			s:SetDecimals(2)
			s:SetConVar("vrmod_znear")
			y = y + 40
		end

		do
			local label = vgui.Create("DLabel", t)
			label:SetPos(20, y + 5)
			label:SetSize(370, 30)
			label:SetDark(true)
			label:SetText("Determines how far away is the 'camera' from your face")
			label:SetWrap(true)
			label:SetAutoStretchVertical(true)
			label:SetFont("BoldSliderFont")
			y = y + 35
		end

		do
			local label = vgui.Create("DLabel", t)
			label:SetPos(20, y + 5)
			label:SetSize(370, 30)
			label:SetDark(true)
			label:SetText("Adjust parameters below if you see borders, start with small values like 0.01")
			label:SetWrap(true)
			label:SetAutoStretchVertical(true)
			y = y + 35
		end

		do
			local s = vgui.Create("DNumSlider", t)
			s:SetPos(20, y + 10)
			s:SetSize(370, 25)
			s:SetDark(true)
			s:SetText("Scale Factor")
			s:SetMin(0.1)
			s:SetMax(2.0)
			s:SetDecimals(2)
			s:SetConVar("vrmod_scalefactor")
			y = y + 40
		end

		do
			local s = vgui.Create("DNumSlider", t)
			s:SetPos(20, y + 10)
			s:SetSize(370, 25)
			s:SetDark(true)
			s:SetText("Vertical offset")
			s:SetMin(-1.0)
			s:SetMax(1.0)
			s:SetDecimals(2)
			s:SetConVar("vrmod_verticaloffset")
			y = y + 40
		end

		do
			local s = vgui.Create("DNumSlider", t)
			s:SetPos(20, y + 10)
			s:SetSize(370, 25)
			s:SetDark(true)
			s:SetText("Horizontal offset")
			s:SetMin(-1.0)
			s:SetMax(1.0)
			s:SetDecimals(2)
			s:SetConVar("vrmod_horizontaloffset")
			y = y + 40
		end

		local reset = vgui.Create("DButton", t)
		reset:SetPos(20, y + 10)
		reset:SetSize(200, 30)
		reset:SetText("Reset")
		reset.DoClick = function()
			RunConsoleCommand("vrmod_postprocess", "0")
			RunConsoleCommand("vrmod_renderoffset", "1")
			RunConsoleCommand("vrmod_viewscale", "1.0")
			RunConsoleCommand("vrmod_fovscale_x", "1.0")
			RunConsoleCommand("vrmod_fovscale_y", "1.0")
			RunConsoleCommand("vrmod_znear", "1.0")
			RunConsoleCommand("vrmod_scalefactor", "1.0")
			RunConsoleCommand("vrmod_verticaloffset", "0")
			RunConsoleCommand("vrmod_horizontaloffset", "0")
		end

		y = y + 50
	end

	-- ─────────────── Shared PropertySheet ───────────────
	local sheet = frame.DPropertySheet
	-- ─────────────── Gameplay Tab ───────────────
	do
		local t = vgui.Create("DPanel", sheet)
		sheet:AddSheet("Gameplay", t, "icon16/joystick.png")
		local y = 10
		local function AddCB(lbl, cv)
			local cb = t:Add("DCheckBoxLabel")
			cb:SetDark(true)
			cb:SetText(lbl)
			cb:SetConVar(cv)
			cb:SetPos(20, y)
			cb:SizeToContents()
			y = y + 20
		end

		AddCB("VR Disable Pickup (Client)", "vr_pickup_disable_client")
		AddCB("Drop weapon", "vrmod_weapondrop_enable")
		AddCB("Manual item pickup", "vrmod_manualpickups")
		AddCB("Weight limit", "vrmod_pickup_limit")
		local function AddSl(lbl, cv, mn, mx, dec)
			local s = vgui.Create("DNumSlider", t)
			s:SetPos(20, y + 10)
			s:SetSize(370, 25)
			s:SetDark(true)
			s:SetText(lbl)
			s:SetMin(mn)
			s:SetMax(mx)
			s:SetDecimals(dec)
			s:SetConVar(cv)
			y = y + 40
		end

		AddSl("Pickup weight (server)", "vrmod_pickup_weight", 1, 10000, 0)
		AddSl("Pickup range  (server)", "vrmod_pickup_range", 0.0, 10.0, 1)
		local btn = vgui.Create("DButton", t)
		btn:SetText("Reset")
		btn:SetPos(190, 255)
		btn:SetSize(160, 30)
		function btn:DoClick()
			RunConsoleCommand("vrmod_allow_teleport_client", "0")
			RunConsoleCommand("vr_pickup_disable_client", "0")
			RunConsoleCommand("vrmod_weapondrop_enable", "1")
			RunConsoleCommand("vrmod_manualpickups", "1")
			RunConsoleCommand("vrmod_pickup_weight", "150")
			RunConsoleCommand("vrmod_pickup_range", "1.1")
			RunConsoleCommand("vrmod_pickup_limit", "1")
		end
	end

	-- ─────────────── HUD/UI Tab ───────────────
	do
		local t = vgui.Create("DScrollPanel", sheet)
		sheet:AddSheet("HUD/UI", t, "icon16/layers.png")
		function t:Paint(w, h)
			surface.SetDrawColor(234, 234, 234) -- solid white
			surface.DrawRect(0, 0, w, h)
		end

		local function AddSl(lbl, cv, mn, mx, dec, py)
			local s = vgui.Create("DNumSlider", t)
			s:SetPos(20, py)
			s:SetSize(370, 25)
			s:SetDark(true)
			s:SetText(lbl)
			s:SetMin(mn)
			s:SetMax(mx)
			s:SetDecimals(dec)
			s:SetConVar(cv)
		end

		local cY = 10
		local cb = t:Add("DCheckBoxLabel")
		cb:SetPos(20, cY)
		cb:SetDark(true)
		cb:SetText("Enable HUD")
		cb:SetConVar("vrmod_hud")
		cb:SizeToContents()
		AddSl("HUD Curve", "vrmod_hudcurve", -100, 100, 0, 30)
		AddSl("HUD Distance", "vrmod_huddistance", 1, 100, 0, 55)
		AddSl("HUD Scale", "vrmod_hudscale", 0.01, 0.1, 2, 80)
		AddSl("HUD Transparency", "vrmod_hudtestalpha", 0, 255, 0, 105)
		cY = 135
		local cb2 = t:Add("DCheckBoxLabel")
		cb2:SetPos(20, cY)
		cb2:SetDark(true)
		cb2:SetText("HUD only while pressing menu key")
		cb2:SetConVar("vrmod_hud_visible_quickmenukey")
		cb2:SizeToContents()
		cY = 165
		local cb3 = t:Add("DCheckBoxLabel")
		cb3:SetPos(20, cY)
		cb3:SetDark(true)
		cb3:SetText("[Menu & UI Red Outline]")
		cb3:SetConVar("vrmod_ui_outline")
		cb3:SizeToContents()
		-- Beam Color
		local lbl = vgui.Create("DLabel", t)
		lbl:SetPos(20, 185)
		lbl:SetSize(200, 30)
		surface.SetDrawColor(75, 75, 75, 255)
		lbl:SetText("Beam color")
		lbl:SetTextColor(Color(0, 0, 0))
		local mixer = vgui.Create("DColorMixer", t)
		mixer:SetPos(20, 220)
		mixer:SetSize(360, 200)
		mixer:SetPalette(true)
		mixer:SetAlphaBar(true)
		mixer:SetWangs(true)
		local str = convars.vrmod_beam_color:GetString()
		local r, g, b, a = string.match(str, "(%d+),(%d+),(%d+),(%d+)")
		if r and g and b and a then mixer:SetColor(Color(tonumber(r), tonumber(g), tonumber(b), tonumber(a))) end
		mixer.ValueChanged = function(_, col) RunConsoleCommand("vrmod_beam_color", string.format("%d,%d,%d,%d", col.r, col.g, col.b, col.a)) end
		local btn2 = vgui.Create("DButton", t)
		btn2:SetText("Set Defaults")
		btn2:SetPos(190, 450)
		btn2:SetSize(160, 30)
		btn2.DoClick = function()
			RunConsoleCommand("vrmod_hud", "1")
			RunConsoleCommand("vrmod_hudcurve", "60")
			RunConsoleCommand("vrmod_huddistance", "60")
			RunConsoleCommand("vrmod_hudscale", "0.05")
			RunConsoleCommand("vrmod_hudtestalpha", "0")
			RunConsoleCommand("vrmod_hudblacklist", "")
			RunConsoleCommand("vrmod_hud_visible_quickmenukey", "0")
			RunConsoleCommand("vrmod_beam_color", "255,0,0,255")
		end
	end

	-- ─────────────── VR Melee Tab ───────────────
	do
		local t = vgui.Create("DPanel", sheet)
		sheet:AddSheet("Melee", t, "icon16/asterisk_orange.png")
		local y = 10
		local defaultModel = "models/hunter/misc/sphere025x025.mdl"
		local function AddCB(lbl, cv)
			local cb = t:Add("DCheckBoxLabel")
			cb:SetDark(true)
			cb:SetText(lbl)
			cb:SetConVar(cv)
			cb:SizeToContents()
			cb:SetPos(20, y)
			y = y + 20
		end

		local function AddSl(lbl, cv, mn, mx, dec)
			local s = vgui.Create("DNumSlider", t)
			s:SetPos(20, y + 10)
			s:SetSize(370, 25)
			s:SetDark(true)
			s:SetText(lbl)
			s:SetMin(mn)
			s:SetMax(mx)
			s:SetDecimals(dec)
			s:SetConVar(cv)
			y = y + 40
		end

		AddCB("Use Gun Melee", "vrmod_melee_gunmelee")
		AddCB("Use Fist Attacks", "vrmod_melee_usefist")
		AddCB("Use Kick Attacks", "vrmod_melee_usekick")
		AddSl("Melee Velocity Threshold", "vrmod_melee_velthreshold", 0.1, 10, 1)
		AddSl("Melee Damage", "vrmod_melee_damage", 0, 1000, 0)
		AddSl("Melee Delay", "vrmod_melee_delay", 0.01, 1, 2)
		AddCB("Visible Collision", "vrmod_melee_fist_visible")
		-- Collision Model Label
		local lbl = vgui.Create("DLabel", t)
		lbl:SetDark(true)
		lbl:SetText("Collision Model")
		lbl:SizeToContents()
		lbl:SetPos(20, y + 15)
		-- Collision Model Text Entry
		local te = vgui.Create("DTextEntry", t)
		te:SetPos(20, y + 35)
		te:SetSize(280, 20)
		te:SetConVar("vrmod_melee_fist_collisionmodel")
		-- Set Model Button
		local btnSet = vgui.Create("DButton", t)
		btnSet:SetText("Set Model")
		btnSet:SetPos(310, y + 35)
		btnSet:SetSize(80, 20)
		function btnSet:DoClick()
			local model = te:GetValue()
			local fullPath = model:lower()
			-- Ensure it starts with "models/"
			if not fullPath:StartWith("models/") then fullPath = "models/" .. fullPath end
			-- Ensure it ends with ".mdl"
			if not fullPath:EndsWith(".mdl") then fullPath = fullPath .. ".mdl" end
			if file.Exists(fullPath, "GAME") then
				RunConsoleCommand("vrmod_melee_fist_collisionmodel", fullPath)
				te:SetText(fullPath)
				notification.AddLegacy("Model set successfully", NOTIFY_GENERIC, 2)
				surface.PlaySound("buttons/button14.wav")
			else
				RunConsoleCommand("vrmod_melee_fist_collisionmodel", defaultModel)
				te:SetText(defaultModel)
				notification.AddLegacy("Invalid model. Reset to default.", NOTIFY_ERROR, 3)
				surface.PlaySound("buttons/button10.wav")
			end
		end

		-- Reset Button
		local btn = vgui.Create("DButton", t)
		btn:SetText("Reset")
		btn:SetPos(190, y + 70)
		btn:SetSize(160, 30)
		function btn:DoClick()
			RunConsoleCommand("vrmod_melee_gunmelee", "1")
			RunConsoleCommand("vrmod_melee_velthreshold", "1.2")
			RunConsoleCommand("vrmod_melee_damage", "50")
			RunConsoleCommand("vrmod_melee_delay", "0.15")
			RunConsoleCommand("vrmod_melee_usefist", "1")
			RunConsoleCommand("vrmod_melee_usekick", "0")
			RunConsoleCommand("vrmod_melee_fist_visible", "0")
			RunConsoleCommand("vrmod_melee_fist_collisionmodel", defaultModel)
			te:SetText(defaultModel)
		end

		y = y + 110
	end

	local maxChecks = 30
	local checks = 0
	timer.Create("VRMod_CheckArcVR", 1, 0, function()
		if ConVarExists("arcticvr_virtualstock") then
			timer.Remove("VRMod_CheckArcVR")
			if not IsValid(sheet) then return end
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
		else
			checks = checks + 1
			if checks >= maxChecks then
				timer.Remove("VRMod_CheckArcVR")
				print("[VRMod] Timed out waiting for ArcVR convars.")
			end
		end
	end)

	local hooks = hook.GetTable().VRMod_Menu or {}
	local names = {}
	for _, v in ipairs(names) do
		local func = hooks[v]
		if isfunction(func) then pcall(func, frame) end
	end

	table.sort(names)
	for _, v in ipairs(names) do
		hooks[v](frame)
	end
	return frame
end