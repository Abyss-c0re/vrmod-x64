if SERVER then return end
local convars, convarValues = vrmod.GetConvars()
hook.Add("VRMod_Menu", "addarcvr", function(frame)
    --ArcticVR Start
    if ConVarExists("arcticvr_virtualstock") then
        --add VRMod_Menu Settings02 propertysheet start
        local sheet = vgui.Create("DPropertySheet", frame.DPropertySheet)
        frame.DPropertySheet:AddSheet("ArcticVR", sheet)
        sheet:Dock(FILL)
        --add VRMod_Menu ArcticVR propertysheet end
        --Panel3 "TAB3" Start
        local panelArcVR1 = vgui.Create("DPanel", sheet)
        sheet:AddSheet("Settings1", panelArcVR1, "icon16/tick.png")
        -- panelArcVR1.Paint = function( self, w, h ) draw.RoundedBox( 4, 0, 0, w, h, Color( 0, 0, 0, self:GetAlpha() ) ) end 
        --DCheckBoxLabel Start
        local gripreloadkey = panelArcVR1:Add("DCheckBoxLabel") -- Create the checkbox
        gripreloadkey:SetPos(25, 30) -- Set the position
        gripreloadkey:SetText("[arcticvr_grip_with_reloadkey]\nON = Reloadkey with\nOFF = Boolean_left_secondaryfire") -- Set the text next to the box
        gripreloadkey:SetConVar("arcticvr_grip_withreloadkey") -- Change a ConVar when the box it ticked/unticked
        gripreloadkey:SizeToContents() -- Make its size the same as the contents
        --DCheckBoxLabel end
        --DCheckBoxLabel Start
        local mag_bumpreload = panelArcVR1:Add("DCheckBoxLabel") -- Create the checkbox
        mag_bumpreload:SetPos(25, 80) -- Set the position
        mag_bumpreload:SetText("[mag_bumpreload] \n You can reload a magazine with the Reload key enabled gun \n by popping the magazine with the magazine.") -- Set the text next to the box
        mag_bumpreload:SetConVar("arcticvr_mag_bumpreload") -- Change a ConVar when the box it ticked/unticked
        mag_bumpreload:SizeToContents() -- Make its size the same as the contents
        --DCheckBoxLabel end
        --DCheckBoxLabel Start
        local frontgrip = panelArcVR1:Add("DCheckBoxLabel") -- Create the checkbox
        frontgrip:SetPos(25, 130) -- Set the position
        frontgrip:SetText("[frontgrip alternative mode] \n The leftpickup key will no longer allow you to grip the foregrip\nbut only while pressing the reload or left_secondary_fire set above\nThis reduces the chance of accidentally removing the magazine.") -- Set the text next to the box
        frontgrip:SetConVar("arcticvr_grip_alternative_mode") -- Change a ConVar when the box it ticked/unticked
        frontgrip:SizeToContents() -- Make its size the same as the contents
        --DCheckBoxLabel end
        --DNumSlider Start
        --arcticvr_slide_magnification
        local arcticvr_slide_magnification = vgui.Create("DNumSlider", panelArcVR1)
        arcticvr_slide_magnification:SetPos(25, 190) -- Set the position (X,Y)
        arcticvr_slide_magnification:SetSize(320, 50) -- Set the size (X,Y)
        arcticvr_slide_magnification:SetText("[slide_magnification]\n A higher value allows \n cocking even when the \n hand is away from the slide.") -- Set the text above the slider
        arcticvr_slide_magnification:SetMin(1) -- Set the minimum number you can slide to
        arcticvr_slide_magnification:SetMax(10) -- Set the maximum number you can slide to
        arcticvr_slide_magnification:SetDecimals(2) -- Decimal places - zero for whole number (set 2 -> 0.00)
        arcticvr_slide_magnification:SetConVar("arcticvr_slide_magnification") -- Changes the ConVar when you slide
        -- If not using convars, you can use this hook + Panel.SetValue()
        arcticvr_slide_magnification.OnValueChanged = function(self, value)
            -- Called when the slider value changes
        end

        --DNumSlider end
        --DNumSlider Start
        --arcticvr_grip_magnification
        local arcticvr_grip_magnification = vgui.Create("DNumSlider", panelArcVR1)
        arcticvr_grip_magnification:SetPos(25, 250) -- Set the position (X,Y)
        arcticvr_grip_magnification:SetSize(320, 50) -- Set the size (X,Y)
        arcticvr_grip_magnification:SetText("[arcticvr_grip_magnification]\nThe larger the value\nthe greater the decision\nto start holding the foregrip") -- Set the text above the slider
        arcticvr_grip_magnification:SetMin(1.00) -- Set the minimum number you can slide to
        arcticvr_grip_magnification:SetMax(10.00) -- Set the maximum number you can slide to
        arcticvr_grip_magnification:SetDecimals(2) -- Decimal places - zero for whole number (set 2 -> 0.00)
        arcticvr_grip_magnification:SetConVar("arcticvr_grip_magnification") -- Changes the ConVar when you slide
        -- If not using convars, you can use this hook + Panel.SetValue()
        arcticvr_grip_magnification.OnValueChanged = function(self, value)
            -- Called when the slider value changes
        end

        --DNumSlider end
        --DCheckBoxLabel Start
        local arcticvr_disable_reloadkey = panelArcVR1:Add("DCheckBoxLabel") -- Create the checkbox
        arcticvr_disable_reloadkey:SetPos(25, 310) -- Set the position
        arcticvr_disable_reloadkey:SetText("[arcticvr_disable_reload_with_key]") -- Set the text next to the box
        arcticvr_disable_reloadkey:SetConVar("arcticvr_disable_reloadkey") -- Change a ConVar when the box it ticked/unticked
        arcticvr_disable_reloadkey:SizeToContents() -- Make its size the same as the contents
        --DCheckBoxLabel end
        --DCheckBoxLabel Start
        local arcticvr_disable_grabreload = panelArcVR1:Add("DCheckBoxLabel") -- Create the checkbox
        arcticvr_disable_grabreload:SetPos(25, 330) -- Set the position
        arcticvr_disable_grabreload:SetText("[arcticvr_disable_grabreload]") -- Set the text next to the box
        arcticvr_disable_grabreload:SetConVar("arcticvr_disable_grabreload") -- Change a ConVar when the box it ticked/unticked
        arcticvr_disable_grabreload:SizeToContents() -- Make its size the same as the contents
        --DCheckBoxLabel end
        --panel1 "TAB1" end
        --Panel2 "TAB2" Start		
        local panelArcVR2 = vgui.Create("DPanel", sheet)
        sheet:AddSheet("Settings2", panelArcVR2, "icon16/tick.png")
        -- panelArcVR2.Paint = function( self, w, h ) draw.RoundedBox( 4, 0, 0, w, h, Color( 0, 0, 0, self:GetAlpha() ) ) end 
        --DCheckBoxLabel Start
        local oldcharacteryaw = panelArcVR2:Add("DCheckBoxLabel") -- Create the checkbox
        oldcharacteryaw:SetPos(25, 10) -- Set the position
        oldcharacteryaw:SetText("[ArcticVR Virtualstock] \n Using a VR weapon with a stock close to the shoulder or head \n will help stabilize the sight.") -- Set the text next to the box
        oldcharacteryaw:SetConVar("arcticvr_virtualstock") -- Change a ConVar when the box it ticked/unticked
        oldcharacteryaw:SizeToContents() -- Make its size the same as the contents
        --DCheckBoxLabel end
        --DNumSlider Start
        --sens
        local sens = vgui.Create("DNumSlider", panelArcVR2)
        sens:SetPos(25, 70) -- Set the position (X,Y)
        sens:SetSize(320, 70) -- Set the size (X,Y)
        sens:SetText("[Frontgrip_Power]\nhow much the movement\nof your left hand affects\nthe sight of the gun\nwhen you grab the foregrip") -- Set the text above the slider
        sens:SetMin(0) -- Set the minimum number you can slide to
        sens:SetMax(2) -- Set the maximum number you can slide to
        sens:SetDecimals(2) -- Decimal places - zero for whole number (set 2 -> 0.00)
        sens:SetConVar("arcticvr_2h_sens") -- Changes the ConVar when you slide
        -- If not using convars, you can use this hook + Panel.SetValue()
        sens.OnValueChanged = function(self, value)
            -- Called when the slider value changes
        end

        --DNumSlider end
        --DCheckBoxLabel Start
        local nadepin = panelArcVR2:Add("DCheckBoxLabel") -- Create the checkbox
        nadepin:SetPos(25, 150) -- Set the position
        nadepin:SetText("[Grenade_pin_enable] \n When set to false\n the specification allows a grenade to be thrown without\npulling out the safety pin.") -- Set the text next to the box
        nadepin:SetConVar("arcticvr_grenade_pin_enable") -- Change a ConVar when the box it ticked/unticked
        nadepin:SizeToContents() -- Make its size the same as the contents
        --DCheckBoxLabel end
        --DCheckBoxLabel Start
        local miscfix = panelArcVR2:Add("DCheckBoxLabel") -- Create the checkbox
        miscfix:SetPos(25, 270) -- Set the position
        miscfix:SetText("[test_cl_misc_fix]\nFor some ArcVR weapons\ncheck the box if the magazine cannot be removed.") -- Set the text next to the box
        miscfix:SetConVar("arcticvr_test_cl_misc_fix") -- Change a ConVar when the box it ticked/unticked
        miscfix:SizeToContents() -- Make its size the same as the contents
        --DCheckBoxLabel end
        --DCheckBoxLabel Start
        local shootsys = panelArcVR2:Add("DCheckBoxLabel") -- Create the checkbox
        shootsys:SetPos(25, 220) -- Set the position
        shootsys:SetText("[Shoot System Fix] \n Check the box if the shotgun sights are significantly misaligned \n and uncheck the box if some ArcVR weapons become unusable.") -- Set the text next to the box
        shootsys:SetConVar("arcticvr_shootsys") -- Change a ConVar when the box it ticked/unticked
        shootsys:SizeToContents() -- Make its size the same as the contents
        --Panel4 "TAB4" Start
        local panelArcVR4 = vgui.Create("DPanel", sheet)
        -- panelArcVR4.Paint = function( self, w, h ) draw.RoundedBox( 4, 0, 0, w, h, Color( 0, 0, 0, self:GetAlpha() ) ) end 
        sheet:AddSheet("MagPouch", panelArcVR4, "icon16/briefcase.png")
        --DNumSlider Start
        --defpouchdist
        local defpouchdist = vgui.Create("DNumSlider", panelArcVR4)
        defpouchdist:SetPos(25, 10) -- Set the position (X,Y)
        defpouchdist:SetSize(320, 25) -- Set the size (X,Y)
        defpouchdist:SetText("Default Pouch Distance") -- Set the text above the slider
        defpouchdist:SetMin(0) -- Set the minimum number you can slide to
        defpouchdist:SetMax(200) -- Set the maximum number you can slide to
        defpouchdist:SetDecimals(2) -- Decimal places - zero for whole number (set 2 -> 0.00)
        defpouchdist:SetConVar("arcticvr_defpouchdist") -- Changes the ConVar when you slide
        -- If not using convars, you can use this hook + Panel.SetValue()
        defpouchdist.OnValueChanged = function(self, value)
            -- Called when the slider value changes
        end

        --DNumSlider end
        --DCheckBoxLabel Start
        local hybridpouch = panelArcVR4:Add("DCheckBoxLabel") -- Create the checkbox
        hybridpouch:SetPos(25, 40) -- Set the position
        hybridpouch:SetText("[hybridpouch]") -- Set the text next to the box
        hybridpouch:SetConVar("arcticvr_hybridpouch") -- Change a ConVar when the box it ticked/unticked
        hybridpouch:SizeToContents() -- Make its size the same as the contents
        --DCheckBoxLabel end
        --DNumSlider Start
        --hybridpouchdist
        local hybridpouchdist = vgui.Create("DNumSlider", panelArcVR4)
        hybridpouchdist:SetPos(25, 55) -- Set the position (X,Y)
        hybridpouchdist:SetSize(320, 25) -- Set the size (X,Y)
        hybridpouchdist:SetText("Hybrid Pouch Distance") -- Set the text above the slider
        hybridpouchdist:SetMin(0) -- Set the minimum number you can slide to
        hybridpouchdist:SetMax(200) -- Set the maximum number you can slide to
        hybridpouchdist:SetDecimals(1) -- Decimal places - zero for whole number (set 2 -> 0.00)
        hybridpouchdist:SetConVar("arcticvr_hybridpouchdist") -- Changes the ConVar when you slide
        -- If not using convars, you can use this hook + Panel.SetValue()
        hybridpouchdist.OnValueChanged = function(self, value)
            -- Called when the slider value changes
        end

        --DNumSlider end
        --DCheckBoxLabel Start
        local headpouch = panelArcVR4:Add("DCheckBoxLabel") -- Create the checkbox
        headpouch:SetPos(25, 85) -- Set the position
        headpouch:SetText("[headpouch]") -- Set the text next to the box
        headpouch:SetConVar("arcticvr_headpouch") -- Change a ConVar when the box it ticked/unticked
        headpouch:SizeToContents() -- Make its size the same as the contents
        --DCheckBoxLabel end
        --DNumSlider Start
        --headpouchdist
        local headpouchdist = vgui.Create("DNumSlider", panelArcVR4)
        headpouchdist:SetPos(25, 100) -- Set the position (X,Y)
        headpouchdist:SetSize(320, 25) -- Set the size (X,Y)
        headpouchdist:SetText("head Pouch Distance") -- Set the text above the slider
        headpouchdist:SetMin(0) -- Set the minimum number you can slide to
        headpouchdist:SetMax(200) -- Set the maximum number you can slide to
        headpouchdist:SetDecimals(1) -- Decimal places - zero for whole number (set 2 -> 0.00)
        headpouchdist:SetConVar("arcticvr_headpouchdist") -- Changes the ConVar when you slide
        -- If not using convars, you can use this hook + Panel.SetValue()
        headpouchdist.OnValueChanged = function(self, value)
            -- Called when the slider value changes
        end

        --DNumSlider end
        --DCheckBoxLabel Start
        local headpouch = panelArcVR4:Add("DCheckBoxLabel") -- Create the checkbox
        headpouch:SetPos(25, 130) -- Set the position
        headpouch:SetText("[infinity range pouch]") -- Set the text next to the box
        headpouch:SetConVar("arcticvr_infpouch") -- Change a ConVar when the box it ticked/unticked
        headpouch:SizeToContents() -- Make its size the same as the contents
        --DCheckBoxLabel end
        --Panel4 "TAB4" end
        --Panel5 "TAB5" Start
        local panelArcVR5 = vgui.Create("DPanel", sheet)
        sheet:AddSheet("Server", panelArcVR5, "icon16/tick.png")
        -- panelArcVR5.Paint = function( self, w, h ) draw.RoundedBox( 4, 0, 0, w, h, Color( 0, 0, 0, self:GetAlpha() ) ) end 
        --DCheckBoxLabel Start
        local arcticvr_allgun_allow_reloadkey = panelArcVR5:Add("DCheckBoxLabel") -- Create the checkbox
        arcticvr_allgun_allow_reloadkey:SetPos(25, 60) -- Set the position
        arcticvr_allgun_allow_reloadkey:SetText("[arcticvr_allgun_allow_reloadkey]") -- Set the text next to the box
        arcticvr_allgun_allow_reloadkey:SetConVar("arcticvr_allgun_allow_reloadkey") -- Change a ConVar when the box it ticked/unticked
        arcticvr_allgun_allow_reloadkey:SizeToContents() -- Make its size the same as the contents
        --DCheckBoxLabel end
        --DCheckBoxLabel Start
        local arcticvr_allgun_allow_reloadkey_client = panelArcVR5:Add("DCheckBoxLabel") -- Create the checkbox
        arcticvr_allgun_allow_reloadkey_client:SetPos(25, 80) -- Set the position
        arcticvr_allgun_allow_reloadkey_client:SetText("[arcticvr_allgun_allow_reloadkey_client]") -- Set the text next to the box
        arcticvr_allgun_allow_reloadkey_client:SetConVar("arcticvr_allgun_allow_reloadkey_client") -- Change a ConVar when the box it ticked/unticked
        arcticvr_allgun_allow_reloadkey_client:SizeToContents() -- Make its size the same as the contents
        --DCheckBoxLabel end
        --DCheckBoxLabel Start
        local arcticvr_bumpreload_allgun = panelArcVR5:Add("DCheckBoxLabel") -- Create the checkbox
        arcticvr_bumpreload_allgun:SetPos(25, 100) -- Set the position
        arcticvr_bumpreload_allgun:SetText("[arcticvr_bumpreload_allgun]") -- Set the text next to the box
        arcticvr_bumpreload_allgun:SetConVar("arcticvr_bumpreload_allgun") -- Change a ConVar when the box it ticked/unticked
        arcticvr_bumpreload_allgun:SizeToContents() -- Make its size the same as the contents
        --DCheckBoxLabel end
        --DCheckBoxLabel Start
        local arcticvr_bumpreload_allgun_client = panelArcVR5:Add("DCheckBoxLabel") -- Create the checkbox
        arcticvr_bumpreload_allgun_client:SetPos(25, 120) -- Set the position
        arcticvr_bumpreload_allgun_client:SetText("[arcticvr_bumpreload_allgun_client]") -- Set the text next to the box
        arcticvr_bumpreload_allgun_client:SetConVar("arcticvr_bumpreload_allgun_client") -- Change a ConVar when the box it ticked/unticked
        arcticvr_bumpreload_allgun_client:SizeToContents() -- Make its size the same as the contents
        --DCheckBoxLabel end
        --DCheckBoxLabel Start
        local defaultammo_normalize = panelArcVR5:Add("DCheckBoxLabel") -- Create the checkbox
        defaultammo_normalize:SetPos(25, 140) -- Set the position
        defaultammo_normalize:SetText("[defaultammo_normalize]") -- Set the text next to the box
        defaultammo_normalize:SetConVar("arcticvr_defaultammo_normalize") -- Change a ConVar when the box it ticked/unticked
        defaultammo_normalize:SizeToContents() -- Make its size the same as the contents
        --DCheckBoxLabel end
        --DCheckBoxLabel Start
        local alternative_phys_bullet = panelArcVR5:Add("DCheckBoxLabel") -- Create the checkbox
        alternative_phys_bullet:SetPos(25, 160) -- Set the position
        alternative_phys_bullet:SetText("[alternative_phys_bullet]") -- Set the text next to the box
        alternative_phys_bullet:SetConVar("arcticvr_physical_bullets") -- Change a ConVar when the box it ticked/unticked
        alternative_phys_bullet:SizeToContents() -- Make its size the same as the contents
        --DCheckBoxLabel end
        --DNumSlider Start
        --arcticvr_net_magtimertime
        local arcticvr_net_magtimertime = vgui.Create("DNumSlider", panelArcVR5)
        arcticvr_net_magtimertime:SetPos(25, 200) -- Set the position (X,Y)
        arcticvr_net_magtimertime:SetSize(320, 90) -- Set the size (X,Y)
        arcticvr_net_magtimertime:SetText("[mag pickup delay]\nTry raising it\nby 0.01 when the\nclient cannot hold the\nmag properly online") -- Set the text above the slider
        arcticvr_net_magtimertime:SetMin(0.00) -- Set the minimum number you can slide to
        arcticvr_net_magtimertime:SetMax(1.00) -- Set the maximum number you can slide to
        arcticvr_net_magtimertime:SetDecimals(2) -- Decimal places - zero for whole number (set 2 -> 0.00)
        arcticvr_net_magtimertime:SetConVar("arcticvr_net_magtimertime") -- Changes the ConVar when you slide
        -- If not using convars, you can use this hook + Panel.SetValue()
        arcticvr_net_magtimertime.OnValueChanged = function(self, value)
            -- Called when the slider value changes
        end
        --DNumSlider end
        --panel5 "TAB5" end
    end
end)