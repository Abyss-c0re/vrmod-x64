if SERVER then return end

-- Height / seated calibration UI.
-- Avatar: vrmod.avatar (shared with FBT) — same PM, tracks HMD/hands in mirror mode.

local convars, convarValues = vrmod.GetConvars()
local heightSession

local function AutoScale()
	if not g_VR.tracking or not g_VR.tracking.hmd then return end
	local eyeH = g_VR.tracking.hmd.pos.z - g_VR.origin.z
	if eyeH < 8 then eyeH = 66.8 end
	g_VR.scale = 66.8 / (eyeH / math.max(g_VR.scale, 0.01))
	convars.vrmod_scale:SetFloat(g_VR.scale)
end

function vrmod.AutoScaleHeight()
	if not g_VR or not g_VR.tracking or not g_VR.tracking.hmd then return false end
	AutoScale()
	return true, g_VR.scale
end

function vrmod.AutoSeatedOffset()
	if not g_VR or not g_VR.origin then return false end
	local hmd = (g_VR.rawTracking and g_VR.rawTracking.hmd) or (g_VR.tracking and g_VR.tracking.hmd)
	if not hmd or not hmd.pos then return false end
	local offset = 66.8 - (hmd.pos.z - g_VR.origin.z)
	convars.vrmod_seatedoffset:SetFloat(offset)
	convars.vrmod_seated:SetBool(true)
	return true, offset
end

local function StopAvatar()
	if heightSession then
		heightSession:Close()
		heightSession = nil
	end
	if vrmod.avatar then
		vrmod.avatar.Close("height")
	end
end

function VRUtilOpenHeightMenu()
	if not g_VR.threePoints or VRUtilIsMenuOpen("heightmenu") then return end

	if vrmod.avatar and vrmod.avatar.OpenHeightCal then
		heightSession = vrmod.avatar.OpenHeightCal("heightmenu")
	end

	VRUtilMenuOpen("heightmenu", 300, 512, nil, nil, Vector(), Angle(), 0.1, true, function()
		StopAvatar()
		hook.Remove("VRMod_Input", "vrmodheightmenuinput")
	end)

	local buttons, renderControls
	buttons = {
		{
			x = 250, y = 0, w = 50, h = 50,
			text = "X", font = "Trebuchet24", text_x = 25, text_y = 15, enabled = true,
			fn = function()
				VRUtilMenuClose("heightmenu")
				convars.vrmod_heightmenu:SetBool(false)
			end
		},
		{
			x = 250, y = 200, w = 50, h = 50,
			text = "+", font = "Trebuchet24", text_x = 25, text_y = 15,
			enabled = not convarValues.vrmod_seated,
			fn = function()
				g_VR.scale = g_VR.scale + 0.5
				convars.vrmod_scale:SetFloat(g_VR.scale)
			end
		},
		{
			x = 250, y = 255, w = 50, h = 50,
			text = "Auto\nScale", font = "Trebuchet24", text_x = 25, text_y = 0,
			enabled = not convarValues.vrmod_seated,
			fn = function() AutoScale() end
		},
		{
			x = 250, y = 310, w = 50, h = 50,
			text = "-", font = "Trebuchet24", text_x = 25, text_y = 15,
			enabled = not convarValues.vrmod_seated,
			fn = function()
				g_VR.scale = g_VR.scale - 0.5
				convars.vrmod_scale:SetFloat(g_VR.scale)
			end
		},
		{
			x = 0, y = 200, w = 50, h = 50,
			text = convarValues.vrmod_seated and "Disable\nSeated\nOffset" or "Enable\nSeated\nOffset",
			font = "Trebuchet18", text_x = 25, text_y = -2, enabled = true,
			fn = function()
				local newState = not convarValues.vrmod_seated
				convars.vrmod_seated:SetBool(newState)
				buttons[5].text = newState and "Disable\nSeated\nOffset" or "Enable\nSeated\nOffset"
				buttons[2].enabled = not newState
				buttons[3].enabled = not newState
				buttons[4].enabled = not newState
				buttons[6].enabled = newState
				renderControls()
			end
		},
		{
			x = 0, y = 255, w = 50, h = 50,
			text = "Auto\nOffset", font = "Trebuchet18", text_x = 25, text_y = 5,
			enabled = convarValues.vrmod_seated,
			fn = function()
				vrmod.AutoSeatedOffset()
			end
		}
	}

	renderControls = function()
		VRUtilMenuRenderStart("heightmenu")
		surface.SetDrawColor(30, 34, 48, 255)
		surface.DrawRect(0, 0, 300, 512)
		surface.SetDrawColor(80, 90, 120, 255)
		surface.DrawOutlinedRect(0, 0, 300, 512)
		draw.DrawText("3D avatar = your body (PM + tracking).\nStand IRL · Auto Scale for height.\nSeated: enable then Auto Offset.\nFBT uses the same avatar util.", "Trebuchet18", 3, 4, color_white, TEXT_ALIGN_LEFT)
		for _, btn in ipairs(buttons) do
			surface.SetDrawColor(btn.enabled and 70 or 40, btn.enabled and 80 or 45, btn.enabled and 110 or 55, 255)
			surface.DrawRect(btn.x, btn.y, btn.w, btn.h)
			draw.DrawText(btn.text, btn.font, btn.x + btn.text_x, btn.y + btn.text_y, color_white, TEXT_ALIGN_CENTER)
		end
		VRUtilMenuRenderEnd()
	end

	renderControls()
	hook.Add("VRMod_Input", "vrmodheightmenuinput", function(action, pressed)
		if g_VR.menuFocus == "heightmenu" and action == "boolean_primaryfire" and pressed then
			for _, btn in ipairs(buttons) do
				if btn.enabled and g_VR.menuCursorX > btn.x and g_VR.menuCursorX < btn.x + btn.w and g_VR.menuCursorY > btn.y and g_VR.menuCursorY < btn.y + btn.h then
					btn.fn()
				end
			end
		end
	end)
end

hook.Add("VRMod_Start", "vrmod_OpenHeightMenuOnStartup", function(ply)
	if ply ~= LocalPlayer() then return end
	if vrmod.Experience_ShouldRun and vrmod.Experience_ShouldRun() then return end
	if not convars.vrmod_heightmenu:GetBool() then return end
	timer.Create("vrmod_HeightMenuStartupWait", 1, 0, function()
		if g_VR.threePoints then
			timer.Remove("vrmod_HeightMenuStartupWait")
			VRUtilOpenHeightMenu()
		end
	end)
end)

hook.Add("VRMod_Exit", "vrmod_height_avatar_cleanup", function(ply)
	if ply ~= LocalPlayer() then return end
	StopAvatar()
end)
