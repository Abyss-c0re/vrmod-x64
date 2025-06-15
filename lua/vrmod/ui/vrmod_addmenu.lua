if SERVER then return end
local convars, convarValues = vrmod.GetConvars()
hook.Add(
	"VRMod_Menu",
	"addsettings",
	function(frame)
		--Settings02 Start
		--add VRMod_Menu Settings02 propertysheet start
		local sheet = vgui.Create("DPropertySheet", frame.DPropertySheet)
		frame.DPropertySheet:AddSheet("Gameplay", sheet)
		sheet:Dock(FILL)
		--add VRMod_Menu Settings02 propertysheet end
		--MenuTab01  Start
		local MenuTab01 = vgui.Create("DPanel", sheet)
		sheet:AddSheet("Rendering", MenuTab01, "icon16/cog_add.png")
		MenuTab01.Paint = function(self, w, h) end -- Clear painting for the panel
		
		local realtime_render = MenuTab01:Add("DCheckBoxLabel") -- Create the checkbox
		realtime_render:SetPos(5, 120) -- Set the position
		realtime_render:SetText("[Realtime UI rendering]") -- Set the text next to the box
		realtime_render:SetConVar("vrmod_ui_realtime") -- Change a ConVar when the box it ticked/unticked
		realtime_render:SizeToContents() -- Make its size the same as the contents
		--DButton end
		-- MenuTab02  Start
		local MenuTab02 = vgui.Create("DPanel", sheet)
		sheet:AddSheet("GamePlay", MenuTab02, "icon16/joystick.png")
		MenuTab02.Paint = function(self, w, h) end -- -- draw.RoundedBox(4, 0, 0, w, h, Color(0, 0, 0, self:GetAlpha()))
		--DCheckBoxLabel Start
		local autojumpduck = MenuTab02:Add("DCheckBoxLabel") -- Create the checkbox
		autojumpduck:SetPos(20, 10) -- Set the position
		autojumpduck:SetText("[Jumpkey Auto Duck]\nON => Jumpkey = IN_DUCK + IN_JUMP\nOFF => Jumpkey = IN_JUMP") -- Set the text next to the box
		autojumpduck:SetConVar("vrmod_autojumpduck") -- Change a ConVar when the box it ticked/unticked
		autojumpduck:SizeToContents() -- Make its size the same as the contents
		--DCheckBoxLabel end
		--DCheckBoxLabel Start
		local allow_teleport_client = MenuTab02:Add("DCheckBoxLabel") -- Create the checkbox
		allow_teleport_client:SetPos(20, 60) -- Set the position
		allow_teleport_client:SetText("Teleport Button Enable(Client)") -- Set the text next to the box
		allow_teleport_client:SetConVar("vrmod_allow_teleport_client") -- Change a ConVar when the box it ticked/unticked
		allow_teleport_client:SizeToContents() -- Make its size the same as the contents
		--DCheckBoxLabel end
		--DNumSlider Start
		--flashlight_attachment

		--character_restart
		local togglelaserpointer = vgui.Create("DButton", MenuTab02) -- Create the button and parent it to the frame
		togglelaserpointer:SetText("Toggle Laser Pointer") -- Set the text on the button
		togglelaserpointer:SetPos(20, 130) -- Set the position on the frame
		togglelaserpointer:SetSize(160, 30) -- Set the size
		-- A custom function run when clicked ( note the . instead of : )
		togglelaserpointer.DoClick = function()
			RunConsoleCommand("vrmod_togglelaserpointer") -- Run the console command "say hi" when you click it ( command, args )
		end

		togglelaserpointer.DoRightClick = function() end
		--DButton end
		--DCheckBoxLabel Start
		local pickup_disable_client = MenuTab02:Add("DCheckBoxLabel") -- Create the checkbox
		pickup_disable_client:SetPos(20, 175) -- Set the position
		pickup_disable_client:SetText("VR Disable Pickup(Client)") -- Set the text next to the box
		pickup_disable_client:SetConVar("vr_pickup_disable_client") -- Change a ConVar when the box it ticked/unticked
		pickup_disable_client:SizeToContents() -- Make its size the same as the contents
		--DCheckBoxLabel end
		--DNumSlider Start
		--vrmod_pickup_weight
		local pickup_weight = vgui.Create("DNumSlider", MenuTab02)
		pickup_weight:SetPos(20, 200) -- Set the position (X,Y)
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
		vrmod_pickup_range:SetPos(20, 225) -- Set the position (X,Y)
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
		vrmod_pickup_limit:SetPos(20, 250) -- Set the position (X,Y)
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
		GamePlay_defaultbutton:SetText("setdefaultvalue") -- Set the text on the button
		GamePlay_defaultbutton:SetPos(190, 310) -- Set the position on the frame
		GamePlay_defaultbutton:SetSize(160, 30) -- Set the size
		-- A custom function run when clicked ( note the . instead of : )
		GamePlay_defaultbutton.DoClick = function()
			RunConsoleCommand("vrmod_allow_teleport_client", "0") 
			RunConsoleCommand("vr_pickup_disable_client", "0")
			RunConsoleCommand("vrmod_pickup_weight", "333") 
			RunConsoleCommand("vrmod_pickup_range", "1.1")
			RunConsoleCommand("vrmod_pickup_limit", "1") 
		end

		--****************************
		
		local MenuTab03 = vgui.Create("DPanel", sheet)
        sheet:AddSheet("Non-VR Weapons", MenuTab03, "icon16/gun.png")
        MenuTab03.Paint = function(self, w, h) end
        local dropenable_checkbox = MenuTab03:Add("DCheckBoxLabel")
        dropenable_checkbox:SetPos(20, 10)
        dropenable_checkbox:SetText("Drop weapon")
        dropenable_checkbox:SetConVar("vrmod_weapondrop_enable")
        dropenable_checkbox:SizeToContents()
        local dropmode_checkbox = MenuTab03:Add("DCheckBoxLabel")
        dropmode_checkbox:SetPos(20, 40)
        dropmode_checkbox:SetText("Trash Weapon on Drop")
        dropmode_checkbox:SetConVar("vrmod_weapondrop_trashwep")
        dropmode_checkbox:SizeToContents()


		
		--MenuTab03 "1" end
		-- MenuTab04  Start
		local MenuTab04 = vgui.Create("DScrollPanel", sheet)
		sheet:AddSheet("HUD/UI", MenuTab04, "icon16/layers.png")
		MenuTab04.Paint = function(self, w, h) end -- draw.RoundedBox(4, 0, 0, w, h, Color(0, 0, 0, self:GetAlpha()))
		--DCheckBoxLabel Start
		local vrmod_hud = MenuTab04:Add("DCheckBoxLabel") -- Create the checkbox
		vrmod_hud:SetPos(20, 10) -- Set the position
		vrmod_hud:SetText("Hud Enable") -- Set the text next to the box
		vrmod_hud:SetConVar("vrmod_hud") -- Change a ConVar when the box it ticked/unticked
		vrmod_hud:SizeToContents() -- Make its size the same as the contents
		--DCheckBoxLabel end
		--DNumSlider Start
		--hudcurve
		local hudcurve = vgui.Create("DNumSlider", MenuTab04)
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
		local huddistance = vgui.Create("DNumSlider", MenuTab04)
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
		local hudscale = vgui.Create("DNumSlider", MenuTab04)
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
		local hudtestalpha = vgui.Create("DNumSlider", MenuTab04)
		hudtestalpha:SetPos(20, 105) -- Set the position (X,Y)
		hudtestalpha:SetSize(370, 25) -- Set the size (X,Y)
		hudtestalpha:SetText("Hud alpha Transparency") -- Set the text above the slider
		hudtestalpha:SetMin(0) -- Set the minimum number you can slide to
		hudtestalpha:SetMax(255) -- Set the maximum number you can slide to
		hudtestalpha:SetDecimals(0) -- Decimal places - zero for whole number (set 2 -> 0.00)
		hudtestalpha:SetConVar("vrmod_hudtestalpha") -- Changes the ConVar when you slide
		-- If not using convars, you can use this hook + Panel.SetValue()
		hudtestalpha.OnValueChanged = function(self, value) end -- Called when the slider value changes
		--DNumSlider end
		--DCheckBoxLabel Start
		local vrmod_test_ui_testver = MenuTab04:Add("DCheckBoxLabel") -- Create the checkbox
		vrmod_test_ui_testver:SetPos(20, 135) -- Set the position
		vrmod_test_ui_testver:SetText("vrmod_test_ui_testver") -- Set the text next to the box
		vrmod_test_ui_testver:SetConVar("vrmod_test_ui_testver") -- Change a ConVar when the box it ticked/unticked
		vrmod_test_ui_testver:SizeToContents() -- Make its size the same as the contents
		--DCheckBoxLabel end
		--DCheckBoxLabel Start
		local vrmod_hud_visible_quickmenukey = MenuTab04:Add("DCheckBoxLabel") -- Create the checkbox
		vrmod_hud_visible_quickmenukey:SetPos(20, 165) -- Set the position
		vrmod_hud_visible_quickmenukey:SetText("HUD only while pressing menu key") -- Set the text next to the box
		vrmod_hud_visible_quickmenukey:SetConVar("vrmod_hud_visible_quickmenukey") -- Change a ConVar when the box it ticked/unticked
		vrmod_hud_visible_quickmenukey:SizeToContents() -- Make its size the same as the contents
		--DCheckBoxLabel 

		--vrmod_attach_quickmenu
		local attach_quickmenu = vgui.Create("DComboBox", MenuTab04)
		attach_quickmenu:SetPos(20, 215) -- Set the position (X,Y)
		attach_quickmenu:SetSize(320, 25) -- Set the size (X,Y)
		attach_quickmenu:SetText("[quickmenu Attach Position]") -- Set the text above the slider
		attach_quickmenu:AddChoice("left hand")
		attach_quickmenu:AddChoice("HMD")
		attach_quickmenu:AddChoice("Right Static")
		attach_quickmenu.OnSelect = function(self, index, value)
			LocalPlayer():ConCommand("vrmod_attach_quickmenu " .. index)
		end

		--DNumSlider end
		--vrmod_attach_weaponmenu
		local attach_weaponmenu = vgui.Create("DComboBox", MenuTab04)
		attach_weaponmenu:SetPos(20, 245) -- Set the position (X,Y)
		attach_weaponmenu:SetSize(320, 25) -- Set the size (X,Y)
		attach_weaponmenu:SetText("[weaponmenu Attach Position]") -- Set the text above the slider
		attach_weaponmenu:AddChoice("left hand")
		attach_weaponmenu:AddChoice("HMD")
		attach_weaponmenu:AddChoice("Right Static")
		attach_weaponmenu.OnSelect = function(self, index, value)
			LocalPlayer():ConCommand("vrmod_attach_weaponmenu " .. index)
		end

		--DNumSlider end
		--vrmod_attach_popup
		local attach_popup = vgui.Create("DComboBox", MenuTab04)
		attach_popup:SetPos(20, 275) -- Set the position (X,Y)
		attach_popup:SetSize(320, 25) -- Set the size (X,Y)
		attach_popup:SetText("[popup Window Attach Position]") -- Set the text above the slider
		attach_popup:AddChoice("left hand")
		attach_popup:AddChoice("HMD")
		attach_popup:AddChoice("Right Static")
		attach_popup.OnSelect = function(self, index, value)
			LocalPlayer():ConCommand("vrmod_attach_popup " .. index)
		end

		--DCheckBoxLabel end
		--DCheckBoxLabel Start
		local vrmod_ui_outline = MenuTab04:Add("DCheckBoxLabel") -- Create the checkbox
		vrmod_ui_outline:SetPos(20, 335) -- Set the position
		vrmod_ui_outline:SetText("[Menu&UI Red outline]") -- Set the text next to the box
		vrmod_ui_outline:SetConVar("vrmod_ui_outline") -- Change a ConVar when the box it ticked/unticked
		vrmod_ui_outline:SizeToContents() -- Make its size the same as the contents
		

		local label = vgui.Create("DLabel", MenuTab04)  -- 'parentPanel' is the parent container
		label:SetPos(20, 340)                             -- Set the position on the parent panel
		label:SetSize(200, 30)                           -- Set the size of the label
		label:SetText("Beam color")                 -- Set the text for the label
		label:SetTextColor(Color(255, 255, 255))         -- Set the text color (optional)
		label:SetFont("Default")                         -- Set the font (optional)
		label:SetWrap(true)       

		local colorMixer = vgui.Create("DColorMixer", MenuTab04)
		colorMixer:SetPos(20, 360)
		colorMixer:SetSize(360, 200)
		colorMixer:SetPalette(true)  -- Allow the user to choose custom colors from a palette
		colorMixer:SetAlphaBar(true) -- Show alpha channel (opacity)
		colorMixer:SetWangs(true)    -- Show RGB wangs (sliders)
	
		-- Load the stored color from the ConVar and set it as the default color
		--local storedColor = string.ToColor(convarValues.vrmod_beam_color)

		local r, g, b, a = string.match(convarValues.vrmod_beam_color, "(%d+),(%d+),(%d+),(%d+)")
		local storedColor = Color(tonumber(r), tonumber(g), tonumber(b), tonumber(a))
		colorMixer:SetColor(storedColor)
	
		-- Add an event listener to handle color changes
		colorMixer.ValueChanged = function(picker, color)
			-- Save the new color to the ConVar
			local colorString = string.format("%d,%d,%d,%d", color.r, color.g, color.b, color.a)
			RunConsoleCommand("vrmod_beam_color", colorString)
		end
		--DButton Start
		--HUD_defaultbutton

		local HUD_defaultbutton = vgui.Create("DButton", MenuTab04) -- Create the button and parent it to the frame
		HUD_defaultbutton:SetText("set defaults") -- Set the text on the button
		HUD_defaultbutton:SetPos(190, 600) -- Set the position on the frame
		HUD_defaultbutton:SetSize(160, 30) -- Set the size

		HUD_defaultbutton.DoClick = function()
			RunConsoleCommand("vrmod_hud", "1")
			RunConsoleCommand("vrmod_hudcurve", "60") 
			RunConsoleCommand("vrmod_huddistance", "60") 
			RunConsoleCommand("vrmod_hudscale", "0.05") 
			RunConsoleCommand("vrmod_hudtestalpha", "0") 
			RunConsoleCommand("vrmod_test_ui_testver", "0")
			RunConsoleCommand("vrmod_hudblacklist", "") 
			RunConsoleCommand("vrmod_hud_visible_quickmenukey", "0")
		end
		
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