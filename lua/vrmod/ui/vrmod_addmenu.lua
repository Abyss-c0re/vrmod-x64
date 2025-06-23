if SERVER then return end
local convarValues = vrmod.GetConvars()
hook.Add("VRMod_Menu", "addsettings", function(frame)
	--Settings02 Start
	--add VRMod_Menu Settings02 propertysheet start
	local sheet = vgui.Create("DPropertySheet", frame.DPropertySheet)
	frame.DPropertySheet:AddSheet("Gameplay", sheet)
	sheet:Dock(FILL)
	--add VRMod_Menu Settings02 propertysheet end
	-- MenuTab02  Start
	local MenuTab02 = vgui.Create("DPanel", sheet)
	sheet:AddSheet("GamePlay", MenuTab02, "icon16/joystick.png")
	MenuTab02.Paint = function(self, w, h) end -- -- draw.RoundedBox(4, 0, 0, w, h, Color(0, 0, 0, self:GetAlpha()))
	--DCheckBoxLabel Start
	local allow_teleport_client = MenuTab02:Add("DCheckBoxLabel") -- Create the checkbox
	allow_teleport_client:SetPos(20, 10) -- Set the position
	allow_teleport_client:SetText("Teleport Button Enable(Client)") -- Set the text next to the box
	allow_teleport_client:SetConVar("vrmod_allow_teleport_client") -- Change a ConVar when the box it ticked/unticked
	allow_teleport_client:SizeToContents() -- Make its size the same as the contents
	--DCheckBoxLabel end
	--DNumSlider Start
	--flashlight_attachment
	--character_restart
	local pickup_disable_client = MenuTab02:Add("DCheckBoxLabel") -- Create the checkbox
	pickup_disable_client:SetPos(20, 30) -- Set the position
	pickup_disable_client:SetText("VR Disable Pickup(Client)") -- Set the text next to the box
	pickup_disable_client:SetConVar("vr_pickup_disable_client") -- Change a ConVar when the box it ticked/unticked
	pickup_disable_client:SizeToContents() -- Make its size the same as the contents
	local drop_weapons = MenuTab02:Add("DCheckBoxLabel") -- Create the checkbox
	drop_weapons:SetText("Drop weapon") -- Set the text next to the box
	drop_weapons:SetConVar("vrmod_weapondrop_enable") -- Change a ConVar when the box it ticked/unticked
	drop_weapons:SizeToContents() -- Make its size the same as the contents
	drop_weapons:SetPos(20, 50) -- Set the position
	local vrmod_manualpickup = MenuTab02:Add("DCheckBoxLabel")
	vrmod_manualpickup:SetText("Manual item pickup")
	vrmod_manualpickup:SetConVar("vrmod_manualpickups")
	vrmod_manualpickup:SizeToContents()
	vrmod_manualpickup:SetPos(20, 70)
	--DCheckBoxLabel end
	--DNumSlider Start
	--vrmod_pickup_weight
	local pickup_weight = vgui.Create("DNumSlider", MenuTab02)
	pickup_weight:SetPos(20, 140) -- Set the position (X,Y)
	pickup_weight:SetSize(370, 25) -- Set the size (X,Y)
	pickup_weight:SetText("pickup_weight(server)") -- Set the text above the slider
	pickup_weight:SetMin(1) -- Set the minimum number you can slide to
	pickup_weight:SetMax(99999) -- Set the maximum number you can slide to
	pickup_weight:SetDecimals(0) -- Decimal places - zero for whole number (set 2 -> 0.00)
	pickup_weight:SetConVar("vrmod_pickup_weight") -- Changes the ConVar when you slide
	-- If not using convars, you can use this hook + Panel.SetValue()
	pickup_weight.OnValueChanged = function(self, value) end -- Called when the slider value changes
	--DNumSlider end
	--DNumSlider Start
	--vr_vrmod_pickup_range
	local vrmod_pickup_range = vgui.Create("DNumSlider", MenuTab02)
	vrmod_pickup_range:SetPos(20, 180) -- Set the position (X,Y)
	vrmod_pickup_range:SetSize(370, 25) -- Set the size (X,Y)
	vrmod_pickup_range:SetText("pickup_range(server)") -- Set the text above the slider
	vrmod_pickup_range:SetMin(0.0) -- Set the minimum number you can slide to
	vrmod_pickup_range:SetMax(10.0) -- Set the maximum number you can slide to
	vrmod_pickup_range:SetDecimals(1) -- Decimal places - zero for whole number (set 2 -> 0.00)
	vrmod_pickup_range:SetConVar("vrmod_pickup_range") -- Changes the ConVar when you slide
	-- If not using convars, you can use this hook + Panel.SetValue()
	vrmod_pickup_range.OnValueChanged = function(self, value) end -- Called when the slider value changes
	--DNumSlider end
	--DNumSlider Start
	--vr_vrmod_pickup_limit
	local vrmod_pickup_limit = vgui.Create("DNumSlider", MenuTab02)
	vrmod_pickup_limit:SetPos(20, 220) -- Set the position (X,Y)
	vrmod_pickup_limit:SetSize(370, 25) -- Set the size (X,Y)
	vrmod_pickup_limit:SetText("pickup_limit(server)") -- Set the text above the slider
	vrmod_pickup_limit:SetMin(0) -- Set the minimum number you can slide to
	vrmod_pickup_limit:SetMax(3) -- Set the maximum number you can slide to
	vrmod_pickup_limit:SetDecimals(0) -- Decimal places - zero for whole number (set 2 -> 0.00)
	vrmod_pickup_limit:SetConVar("vrmod_pickup_limit") -- Changes the ConVar when you slide
	-- If not using convars, you can use this hook + Panel.SetValue()
	vrmod_pickup_limit.OnValueChanged = function(self, value) end -- Called when the slider value changes
	--DNumSlider end
	--DButton Start
	--GamePlay_defaultbutton
	local GamePlay_defaultbutton = vgui.Create("DButton", MenuTab02) -- Create the button and parent it to the frame
	GamePlay_defaultbutton:SetText("Reset") -- Set the text on the button
	GamePlay_defaultbutton:SetPos(190, 255) -- Set the position on the frame
	GamePlay_defaultbutton:SetSize(160, 30) -- Set the size
	-- A custom function run when clicked ( note the . instead of : )
	GamePlay_defaultbutton.DoClick = function()
		RunConsoleCommand("vrmod_allow_teleport_client", "0")
		RunConsoleCommand("vr_pickup_disable_client", "0")
		RunConsoleCommand("vrmod_weapondrop_enable", "1")
		RunConsoleCommand("vrmod_manualpickups", "1")
		RunConsoleCommand("vrmod_pickup_weight", "150")
		RunConsoleCommand("vrmod_pickup_range", "1.1")
		RunConsoleCommand("vrmod_pickup_limit", "1")
	end

	--****************************
	--MenuTab03 "1" end
	-- MenuTab03  Start
	local MenuTab03 = vgui.Create("DScrollPanel", sheet)
	sheet:AddSheet("HUD/UI", MenuTab03, "icon16/layers.png")
	MenuTab03.Paint = function(self, w, h) end -- draw.RoundedBox(4, 0, 0, w, h, Color(0, 0, 0, self:GetAlpha()))
	--DCheckBoxLabel Start
	local vrmod_hud = MenuTab03:Add("DCheckBoxLabel") -- Create the checkbox
	vrmod_hud:SetPos(20, 10) -- Set the position
	vrmod_hud:SetText("Hud Enable") -- Set the text next to the box
	vrmod_hud:SetConVar("vrmod_hud") -- Change a ConVar when the box it ticked/unticked
	vrmod_hud:SizeToContents() -- Make its size the same as the contents
	--DCheckBoxLabel end
	--DNumSlider Start
	--hudcurve
	local hudcurve = vgui.Create("DNumSlider", MenuTab03)
	hudcurve:SetPos(20, 30) -- Set the position (X,Y)
	hudcurve:SetSize(370, 25) -- Set the size (X,Y)
	hudcurve:SetText("Hud curve") -- Set the text above the slider
	hudcurve:SetMin(1) -- Set the minimum number you can slide to
	hudcurve:SetMax(60) -- Set the maximum number you can slide to
	hudcurve:SetDecimals(0) -- Decimal places - zero for whole number (set 2 -> 0.00)
	hudcurve:SetConVar("vrmod_hudcurve") -- Changes the ConVar when you slide
	-- If not using convars, you can use this hook + Panel.SetValue()
	hudcurve.OnValueChanged = function(self, value) end -- Called when the slider value changes
	--DNumSlider end
	--DNumSlider Start
	--huddistance
	local huddistance = vgui.Create("DNumSlider", MenuTab03)
	huddistance:SetPos(20, 55) -- Set the position (X,Y)
	huddistance:SetSize(370, 25) -- Set the size (X,Y)
	huddistance:SetText("Hud distance") -- Set the text above the slider
	huddistance:SetMin(1) -- Set the minimum number you can slide to
	huddistance:SetMax(60) -- Set the maximum number you can slide to
	huddistance:SetDecimals(0) -- Decimal places - zero for whole number (set 2 -> 0.00)
	huddistance:SetConVar("vrmod_huddistance") -- Changes the ConVar when you slide
	-- If not using convars, you can use this hook + Panel.SetValue()
	huddistance.OnValueChanged = function(self, value) end -- Called when the slider value changes
	--DNumSlider end
	--DNumSlider Start
	--hudscale
	local hudscale = vgui.Create("DNumSlider", MenuTab03)
	hudscale:SetPos(20, 80) -- Set the position (X,Y)
	hudscale:SetSize(370, 25) -- Set the size (X,Y)
	hudscale:SetText("Hud scale") -- Set the text above the slider
	hudscale:SetMin(0.01) -- Set the minimum number you can slide to
	hudscale:SetMax(0.1) -- Set the maximum number you can slide to
	hudscale:SetDecimals(2) -- Decimal places - zero for whole number (set 2 -> 0.00)
	hudscale:SetConVar("vrmod_hudscale") -- Changes the ConVar when you slide
	-- If not using convars, you can use this hook + Panel.SetValue()
	hudscale.OnValueChanged = function(self, value) end -- Called when the slider value changes
	--DNumSlider end
	--DNumSlider Start
	--hudtestalpha
	local hudtestalpha = vgui.Create("DNumSlider", MenuTab03)
	hudtestalpha:SetPos(20, 105) -- Set the position (X,Y)
	hudtestalpha:SetSize(370, 25) -- Set the size (X,Y)
	hudtestalpha:SetText("Hud alpha Transparency") -- Set the text above the slider
	hudtestalpha:SetMin(0) -- Set the minimum number you can slide to
	hudtestalpha:SetMax(255) -- Set the maximum number you can slide to
	hudtestalpha:SetDecimals(0) -- Decimal places - zero for whole number (set 2 -> 0.00)
	hudtestalpha:SetConVar("vrmod_hudtestalpha") -- Changes the ConVar when you slide
	-- If not using convars, you can use this hook + Panel.SetValue()
	hudtestalpha.OnValueChanged = function(self, value) end -- Called when the slider value changes
	local vrmod_hud_visible_quickmenukey = MenuTab03:Add("DCheckBoxLabel") -- Create the checkbox
	vrmod_hud_visible_quickmenukey:SetPos(20, 135) -- Set the position
	vrmod_hud_visible_quickmenukey:SetText("HUD only while pressing menu key") -- Set the text next to the box
	vrmod_hud_visible_quickmenukey:SetConVar("vrmod_hud_visible_quickmenukey") -- Change a ConVar when the box it ticked/unticked
	vrmod_hud_visible_quickmenukey:SizeToContents() -- Make its size the same as the contents
	--DCheckBoxLabel Start
	local vrmod_ui_outline = MenuTab03:Add("DCheckBoxLabel") -- Create the checkbox
	vrmod_ui_outline:SetPos(20, 165) -- Set the position
	vrmod_ui_outline:SetText("[Menu&UI Red outline]") -- Set the text next to the box
	vrmod_ui_outline:SetConVar("vrmod_ui_outline") -- Change a ConVar when the box it ticked/unticked
	vrmod_ui_outline:SizeToContents() -- Make its size the same as the contents
	--Beam color selection
	local label = vgui.Create("DLabel", MenuTab03) -- 'parentPanel' is the parent container
	label:SetPos(20, 185) -- Set the position on the parent panel
	label:SetSize(200, 30) -- Set the size of the label
	label:SetText("Beam color") -- Set the text for the label
	label:SetTextColor(Color(255, 255, 255)) -- Set the text color (optional)
	label:SetFont("Default") -- Set the font (optional)
	label:SetWrap(true)
	local colorMixer = vgui.Create("DColorMixer", MenuTab03)
	colorMixer:SetPos(20, 205)
	colorMixer:SetSize(360, 200)
	colorMixer:SetPalette(true) -- Allow the user to choose custom colors from a palette
	colorMixer:SetAlphaBar(true) -- Show alpha channel (opacity)
	colorMixer:SetWangs(true) -- Show RGB wangs (sliders)
	-- Load the stored color from the ConVar and set it as the default color
	--local storedColor = string.ToColor(convarValues.vrmod_beam_color)
	local defaultColor = Color(255, 255, 255, 255)
	local colorStr = convarValues.vrmod_beam_color:GetString()
	local r, g, b, a = string.match(colorStr, "(%d+),(%d+),(%d+),(%d+)")
	r, g, b, a = tonumber(r), tonumber(g), tonumber(b), tonumber(a)
	-- Validate all components
	if not (r and g and b and a) then
		storedColor = defaultColor
	else
		storedColor = Color(r, g, b, a)
	end

	colorMixer:SetColor(storedColor)
	-- Add an event listener to handle color changes
	colorMixer.ValueChanged = function(picker, color)
		-- Save the new color to the ConVar
		local colorString = string.format("%d,%d,%d,%d", color.r, color.g, color.b, color.a)
		RunConsoleCommand("vrmod_beam_color", colorString)
	end

	--DButton Start
	--HUD_defaultbutton
	local HUD_defaultbutton = vgui.Create("DButton", MenuTab03) -- Create the button and parent it to the frame
	HUD_defaultbutton:SetText("set defaults") -- Set the text on the button
	HUD_defaultbutton:SetPos(190, 450) -- Set the position on the frame
	HUD_defaultbutton:SetSize(160, 30) -- Set the size
	HUD_defaultbutton.DoClick = function()
		RunConsoleCommand("vrmod_hud", "1")
		RunConsoleCommand("vrmod_hudcurve", "60")
		RunConsoleCommand("vrmod_huddistance", "60")
		RunConsoleCommand("vrmod_hudscale", "0.05")
		RunConsoleCommand("vrmod_hudtestalpha", "0")
		RunConsoleCommand("vrmod_hudblacklist", "")
		RunConsoleCommand("vrmod_hud_visible_quickmenukey", "0")
		RunConsoleCommand("vrmod_beam_color", "255,0,0,255")
	end

	--MenuTab04  Start
	local MenuTab04 = vgui.Create("DPanel", sheet)
	sheet:AddSheet("Rendering", MenuTab04, "icon16/cog_add.png")
	MenuTab04.Paint = function(self, w, h) end -- Clear painting for the panel
	local realtime_render = MenuTab04:Add("DCheckBoxLabel") -- Create the checkbox
	realtime_render:SetPos(20, 10) -- Set the position
	realtime_render:SetText("[Realtime UI rendering]") -- Set the text next to the box
	realtime_render:SetConVar("vrmod_ui_realtime") -- Change a ConVar when the box it ticked/unticked
	realtime_render:SizeToContents() -- Make its size the same as the contents
	--DButton end
	local sheet = vgui.Create("DPropertySheet", frame.DPropertySheet)
	frame.DPropertySheet:AddSheet("Melee", sheet)
	sheet:Dock(FILL)
	local MenuTabmelee = vgui.Create("DPanel", sheet)
	sheet:AddSheet("VRMelee1", MenuTabmelee, "icon16/briefcase.png")
	MenuTabmelee.Paint = function(self, w, h) end
	local form = vgui.Create("DForm", sheet)
	form:SetName("Melee")
	form:Dock(TOP)
	form.Header:SetVisible(false)
	form.Paint = function(self, w, h) end
	-- form:CheckBox("Allow Gun Melee", "vrmelee_gunmelee")
	form:CheckBox("Use Gun Melee", "vrmelee_usegunmelee")
	-- form:CheckBox("Allow Fist Attacks", "vrmelee_fist")
	form:CheckBox("Use Fist Attacks", "vrmelee_usefist")
	-- form:CheckBox("Allow Kick Attacks [FBT]", "vrmelee_kick")
	form:CheckBox("Use Kick Attacks [FBT]", "vrmelee_usekick")
	form:NumSlider("Melee Velocity Threshold", "vrmelee_velthreshold", 0.1, 10, 1)
	form:NumSlider("Melee Damage", "vrmelee_damage", 0, 1000, 0)
	form:NumSlider("Melee Delay", "vrmelee_delay", 0.01, 1, 2)
	form:CheckBox("Fist Collision", "vrmelee_fist_collision")
	form:CheckBox("Fist Collision Visible", "vrmelee_fist_visible")
	form:TextEntry("Collision Model", "vrmelee_fist_collisionmodel")
end)