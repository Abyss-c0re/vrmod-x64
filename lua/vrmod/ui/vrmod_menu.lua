if SERVER then return end
surface.CreateFont("vrmod_Trebuchet24", {
	font = "Trebuchet MS",
	size = 38,
	weight = 100
})

local frame = nil
local function OpenMenu()
	if IsValid(frame) then return frame end
	frame = vgui.Create("DFrame")
	frame:SetSize(400, 485)
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
		tmp:SetFont("vrmod_Trebuchet24") --default Trebuchet24 causes this text to not show up on some systems for some reason (even though it works elsewhere...)
		function tmp:PerformLayout()
			tmp:Center()
		end
		return frame
	end

	local sheet = vgui.Create("DPropertySheet", frame)
	sheet:SetPadding(1)
	sheet:Dock(FILL)
	frame.DPropertySheet = sheet
	local panel1 = vgui.Create("DPanel", sheet)
	sheet:AddSheet("Settings", panel1)
	local scrollPanel = vgui.Create("DScrollPanel", panel1)
	scrollPanel:Dock(FILL)
	local form = vgui.Create("DForm", scrollPanel)
	form:SetName("Settings")
	form:Dock(TOP)
	form.Header:SetVisible(false)
	form.Paint = function(self, w, h) end
	frame.SettingsForm = form
	local panel = vgui.Create("DPanel", frame)
	panel:Dock(BOTTOM)
	panel:SetTall(35)
	panel.Paint = function(self, w, h) end
	local tmp = vgui.Create("DLabel", panel)
	tmp:SetText("Addon version: " .. vrmod.GetVersion() .. "\nModule version: " .. vrmod.GetModuleVersion())
	tmp:SizeToContents()
	tmp:SetPos(5, 5)
	local tmp = vgui.Create("DButton", panel)
	tmp:SetText("Exit")
	tmp:Dock(RIGHT)
	tmp:DockMargin(0, 5, 0, 0)
	tmp:SetWide(96)
	tmp:SetEnabled(g_VR.active)
	function tmp:DoClick()
		frame:Remove()
		VRUtilClientExit()
	end

	local tmp = vgui.Create("DButton", panel)
	tmp:SetText(g_VR.active and "Restart" or "Start")
	tmp:Dock(RIGHT)
	tmp:DockMargin(0, 5, 5, 0)
	tmp:SetWide(96)
	function tmp:DoClick()
		frame:Remove()
		if g_VR.active then
			VRUtilClientExit()
			timer.Simple(1, function() VRUtilClientStart() end)
		else
			VRUtilClientStart()
		end
	end

	if not error or error == "Already running" then
		--hook.Call("VRMod_Menu",nil,frame)
		local hooks = hook.GetTable().VRMod_Menu
		local names = {}
		for k, v in pairs(hooks) do
			names[#names + 1] = k
		end

		table.sort(names)
		for k, v in ipairs(names) do
			hooks[v](frame)
		end
	end
	return frame
end

concommand.Add("vrmod", function(ply, cmd, args)
	if vgui.CursorVisible() then print("vrmod: menu will open when game is unpaused") end
	timer.Create("vrmod_open_menu", 0.1, 0, function()
		if not vgui.CursorVisible() then
			OpenMenu()
			timer.Remove("vrmod_open_menu")
		end
	end)
end)

concommand.Add("vrmod_togglelaserpointer", function(ply, cmd, args)
	if not GetConVar("vrmod_laserpointer"):GetBool() then
		local mat = Material("cable/redlaser")
		hook.Add("PostDrawTranslucentRenderables", "vr_laserpointer", function(bDrawingDepth, bDrawingSkybox)
			if bDrawingSkybox then return end
			if g_VR.viewModelMuzzle and not g_VR.menuFocus then
				render.SetMaterial(mat)
				render.DrawBeam(g_VR.viewModelMuzzle.Pos, g_VR.viewModelMuzzle.Pos + g_VR.viewModelMuzzle.Ang:Forward() * 10000, 1, 0, 1, Color(255, 255, 255, 255))
			end
		end)

		LocalPlayer():ConCommand("vrmod_laserpointer 1")
	else
		hook.Remove("PostDrawTranslucentRenderables", "vr_laserpointer")
		LocalPlayer():ConCommand("vrmod_laserpointer 0")
	end
end)

local convars = vrmod.AddCallbackedConvar("vrmod_showonstartup", nil, "0")
if convars.vrmod_showonstartup:GetBool() then
	hook.Add("CreateMove", "vrmod_showonstartup", function()
		hook.Remove("CreateMove", "vrmod_showonstartup")
		timer.Simple(1, function() RunConsoleCommand("vrmod") end)
	end)
end

vrmod.AddInGameMenuItem("Settings", 4, 0, function()
	OpenMenu()
	hook.Add("VRMod_OpenQuickMenu", "closesettings", function()
		hook.Remove("VRMod_OpenQuickMenu", "closesettings")
		if IsValid(frame) then
			frame:Remove()
			frame = nil
			return false
		end
	end)
end)