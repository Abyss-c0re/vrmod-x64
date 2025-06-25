if SERVER then return end
local convars = vrmod.GetConvars()

hook.Add("VRMod_Menu", "vrmod_combined_options", function(frame)
	local form = frame.SettingsForm

	-- ─────────────── Locomotion Settings (moved to top) ───────────────
	do
		local panel = vgui.Create("DForm", form)
		panel:SetName("Locomotion")
		panel:Dock(TOP)
		panel:DockMargin(10, 10, 10, 0)
		panel:SetExpanded(true)

		local controllerLocomotion = vgui.Create("DCheckBoxLabel", panel)
		panel:AddItem(controllerLocomotion)
		controllerLocomotion:SetDark(true)
		controllerLocomotion:SetText("Controller oriented locomotion")
		controllerLocomotion:SetChecked(convars.vrmod_controlleroriented:GetBool())
		function controllerLocomotion:OnChange(val)
			convars.vrmod_controlleroriented:SetBool(val)
		end

		local smoothTurning = vgui.Create("DCheckBoxLabel", panel)
		panel:AddItem(smoothTurning)
		smoothTurning:SetDark(true)
		smoothTurning:SetText("Smooth turning")
		smoothTurning:SetChecked(convars.vrmod_smoothturn:GetBool())
		function smoothTurning:OnChange(val)
			convars.vrmod_smoothturn:SetBool(val)
		end

		local turnRateSlider = vgui.Create("DNumSlider", panel)
		panel:AddItem(turnRateSlider)
		turnRateSlider:SetMin(1)
		turnRateSlider:SetMax(360)
		turnRateSlider:SetDecimals(0)
		turnRateSlider:SetValue(convars.vrmod_smoothturnrate:GetInt())
		turnRateSlider:SetDark(true)
		turnRateSlider:SetText("Smooth turn rate")
		function turnRateSlider:OnValueChanged(val)
			convars.vrmod_smoothturnrate:SetInt(val)
		end
	end

	-- ─────────────── Core Settings ───────────────
	form:CheckBox("Teleportation (Client)", "vrmod_allow_teleport_client")
	form:CheckBox("Use floating hands", "vrmod_floatinghands")
	form:CheckBox("Use weapon world models", "vrmod_useworldmodels")
	form:CheckBox("Add laser pointer to tools/weapons", "vrmod_laserpointer")

	local heightCheckbox = form:CheckBox("Show height adjustment menu", "vrmod_heightmenu")
	local checkTime = 0
	function heightCheckbox:OnChange(checked)
		if checked and SysTime() - checkTime < 0.1 then VRUtilOpenHeightMenu() end
		checkTime = SysTime()
	end

	form:CheckBox("Enable seated offset", "vrmod_seated")
	form:ControlHelp("Adjust from height adjustment menu")
	form:CheckBox("Alternative head angle manipulation method", "vrmod_althead")
	form:ControlHelp("Less precise, compatibility for jigglebones")
	form:CheckBox("Automatically start VR after map loads", "vrmod_autostart")
	form:CheckBox("Replace climbing mechanics (when available)", "vrmod_climbing")
	form:CheckBox("Replace door use mechanics (when available)", "vrmod_doors")
	form:CheckBox("Enable engine postprocessing", "vrmod_postprocess")

	-- Desktop-view combo
	do
		local panel = vgui.Create("DPanel")
		panel:SetSize(300, 30)
		panel.Paint = nil
		local lbl = vgui.Create("DLabel", panel)
		lbl:SetPos(0, -3)
		lbl:SetSize(100, 30)
		lbl:SetText("Desktop view:")
		lbl:SetColor(Color(0, 0, 0))
		local cb = vgui.Create("DComboBox", panel)
		cb:Dock(TOP)
		cb:DockMargin(70, 0, 0, 5)
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

		form:AddItem(panel)
	end

	form:Button("Edit custom controller input actions", "vrmod_actioneditor")
	form:Button("Reset settings to default", "vrmod_reset")

	-- Controller-offset sliders
	do
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

		local applyBtn = offsetForm:Button("Apply offsets", "")
		function applyBtn:OnReleased()
			local x = convars.vrmod_controlleroffset_x:GetFloat()
			local y = convars.vrmod_controlleroffset_y:GetFloat()
			local z = convars.vrmod_controlleroffset_z:GetFloat()
			local p = convars.vrmod_controlleroffset_pitch:GetFloat()
			local yw = convars.vrmod_controlleroffset_yaw:GetFloat()
			local r = convars.vrmod_controlleroffset_roll:GetFloat()
			g_VR.rightControllerOffsetPos = Vector(x, y, z)
			g_VR.leftControllerOffsetPos = Vector(x, -y, z)
			g_VR.rightControllerOffsetAng = Angle(p, yw, r)
			g_VR.leftControllerOffsetAng = g_VR.rightControllerOffsetAng
		end
	end

	-- ─────────────── Shared PropertySheet ───────────────
	local sheet = frame.DPropertySheet
	-- ─────────────── Gameplay Tab ───────────────
	do
		local t = vgui.Create("DPanel", sheet)
		t.Paint = nil
		sheet:AddSheet("Gameplay", t, "icon16/joystick.png")
		local y = 10
		local function AddCB(lbl, cv)
			local cb = t:Add("DCheckBoxLabel")
			cb:SetText(lbl)
			cb:SetConVar(cv)
			cb:SetPos(20, y)
			cb:SizeToContents()
			y = y + 20
		end

		AddCB("VR Disable Pickup (Client)", "vr_pickup_disable_client")
		AddCB("Drop weapon", "vrmod_weapondrop_enable")
		AddCB("Manual item pickup", "vrmod_manualpickups")
		local function AddSl(lbl, cv, mn, mx, dec)
			local s = vgui.Create("DNumSlider", t)
			s:SetPos(20, y + 10)
			s:SetSize(370, 25)
			s:SetText(lbl)
			s:SetMin(mn)
			s:SetMax(mx)
			s:SetDecimals(dec)
			s:SetConVar(cv)
			y = y + 40
		end

		AddSl("Pickup weight (server)", "vrmod_pickup_weight", 1, 99999, 0)
		AddSl("Pickup range  (server)", "vrmod_pickup_range", 0.0, 10.0, 1)
		AddSl("Pickup limit  (server)", "vrmod_pickup_limit", 0, 3, 0)
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
		t.Paint = nil
		sheet:AddSheet("HUD/UI", t, "icon16/layers.png")
		local function AddSl(lbl, cv, mn, mx, dec, py)
			local s = vgui.Create("DNumSlider", t)
			s:SetPos(20, py)
			s:SetSize(370, 25)
			s:SetText(lbl)
			s:SetMin(mn)
			s:SetMax(mx)
			s:SetDecimals(dec)
			s:SetConVar(cv)
		end

		local cY = 10
		local cb = t:Add("DCheckBoxLabel")
		cb:SetPos(20, cY)
		cb:SetText("Enable HUD")
		cb:SetConVar("vrmod_hud")
		cb:SizeToContents()
		AddSl("HUD Curve", "vrmod_hudcurve", 1, 60, 0, 30)
		AddSl("HUD Distance", "vrmod_huddistance", 1, 60, 0, 55)
		AddSl("HUD Scale", "vrmod_hudscale", 0.01, 0.1, 2, 80)
		AddSl("HUD Transparency", "vrmod_hudtestalpha", 0, 255, 0, 105)
		cY = 135
		local cb2 = t:Add("DCheckBoxLabel")
		cb2:SetPos(20, cY)
		cb2:SetText("HUD only while pressing menu key")
		cb2:SetConVar("vrmod_hud_visible_quickmenukey")
		cb2:SizeToContents()
		cY = 165
		local cb3 = t:Add("DCheckBoxLabel")
		cb3:SetPos(20, cY)
		cb3:SetText("[Menu & UI Red Outline]")
		cb3:SetConVar("vrmod_ui_outline")
		cb3:SizeToContents()
		-- Beam Color
		local lbl = vgui.Create("DLabel", t)
		lbl:SetPos(20, 185)
		lbl:SetSize(200, 30)
		lbl:SetText("Beam color")
		lbl:SetTextColor(Color(255, 255, 255))
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
		t.Paint = nil
		sheet:AddSheet("VR Melee", t, "icon16/briefcase.png")
		local y = 10
		-- Checkbox helper
		local function AddCB(lbl, cv)
			local cb = t:Add("DCheckBoxLabel")
			cb:SetText(lbl)
			cb:SetConVar(cv)
			cb:SizeToContents()
			cb:SetPos(20, y)
			y = y + 20
		end

		-- Slider helper
		local function AddSl(lbl, cv, mn, mx, dec)
			local s = vgui.Create("DNumSlider", t)
			s:SetPos(20, y + 10)
			s:SetSize(370, 25)
			s:SetText(lbl)
			s:SetMin(mn)
			s:SetMax(mx)
			s:SetDecimals(dec)
			s:SetConVar(cv)
			y = y + 40
		end

		AddCB("Use Gun Melee", "vrmelee_usegunmelee")
		AddCB("Use Fist Attacks", "vrmelee_usefist")
		AddCB("Use Kick Attacks", "vrmelee_usekick")
		AddSl("Melee Velocity Threshold", "vrmelee_velthreshold", 0.1, 10, 1)
		AddSl("Melee Damage", "vrmelee_damage", 0, 1000, 0)
		AddSl("Melee Delay", "vrmelee_delay", 0.01, 1, 2)
		AddCB("Fist Collision", "vrmelee_fist_collision")
		AddCB("Fist Collision Visible", "vrmelee_fist_visible")
		-- Text entry
		local te = vgui.Create("DTextEntry", t)
		te:SetPos(20, y + 15)
		te:SetSize(370, 20)
		te:SetConVar("vrmelee_fist_collisionmodel")
		local lbl = vgui.Create("DLabel", t)
		lbl:SetText("Collision Model")
		lbl:SizeToContents()
		lbl:SetPos(20, y)
	end
end)