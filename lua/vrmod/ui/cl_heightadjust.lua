if SERVER then return end

-- Height / seated calibration.
-- Avatar: puppeteer-style copy of player (Pescorr 2-bone IK).
-- UI: large, left-hand attached — reachable like quickmenu / border cal.

local convars = vrmod.GetConvars()
local heightSession

local Theme = {
	bg = Color(18, 8, 12, 240),
	btn = Color(70, 18, 28, 255),
	btnOff = Color(40, 12, 18, 230),
	accent = Color(196, 30, 58, 255),
	text = Color(255, 240, 244, 255),
	muted = Color(200, 160, 170, 230),
}

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

	-- Large RT + hand attachment (world size ≈ 512*0.04 = 20u — hit-friendly)
	local W, H = 512, 600
	local scale = 0.04
	-- Left hand: same energy as quickmenu / miscmenu
	VRUtilMenuOpen(
		"heightmenu",
		W, H,
		nil,
		true, -- attachment = left hand
		Vector(6, 4, 8),
		Angle(0, -90, 55),
		scale,
		true,
		function()
			StopAvatar()
			hook.Remove("VRMod_Input", "vrmodheightmenuinput")
			hook.Remove("PreRender", "vrmodheightmenuplace")
		end
	)

	-- cl_ui forces scale 0.02 for non-heightmenu only — keep ours large
	if g_VR.menus and g_VR.menus.heightmenu then
		g_VR.menus.heightmenu.scale = scale
	end

	local buttons, renderControls
	local function seated()
		return convars.vrmod_seated:GetBool()
	end

	local pad = 24
	local btnH = 72
	local btnW = (W - pad * 2 - 16) / 3

	buttons = {
		{
			x = W - 64, y = 16, w = 48, h = 48,
			label = "X",
			enabled = true,
			fn = function()
				VRUtilMenuClose("heightmenu")
				convars.vrmod_heightmenu:SetBool(false)
			end
		},
		{
			x = pad, y = 160, w = btnW, h = btnH,
			label = "+",
			enabled = function() return not seated() end,
			fn = function()
				g_VR.scale = g_VR.scale + 0.5
				convars.vrmod_scale:SetFloat(g_VR.scale)
			end
		},
		{
			x = pad + btnW + 8, y = 160, w = btnW, h = btnH,
			label = "AUTO",
			enabled = function() return not seated() end,
			fn = function() AutoScale() end
		},
		{
			x = pad + (btnW + 8) * 2, y = 160, w = btnW, h = btnH,
			label = "-",
			enabled = function() return not seated() end,
			fn = function()
				g_VR.scale = g_VR.scale - 0.5
				convars.vrmod_scale:SetFloat(g_VR.scale)
			end
		},
		{
			x = pad, y = 160 + btnH + 16, w = (W - pad * 2 - 8) / 2, h = btnH,
			label = function() return seated() and "SEATED ON" or "SEATED OFF" end,
			enabled = true,
			fn = function()
				convars.vrmod_seated:SetBool(not seated())
				renderControls()
			end
		},
		{
			x = pad + (W - pad * 2 - 8) / 2 + 8, y = 160 + btnH + 16, w = (W - pad * 2 - 8) / 2, h = btnH,
			label = "OFFSET",
			enabled = function() return seated() end,
			fn = function()
				vrmod.AutoSeatedOffset()
			end
		},
	}

	local function btnEnabled(btn)
		if btn.enabled == nil then return true end
		if isfunction(btn.enabled) then return btn.enabled() end
		return btn.enabled and true or false
	end

	local function btnLabel(btn)
		if isfunction(btn.label) then return btn.label() end
		return btn.label or ""
	end

	renderControls = function()
		VRUtilMenuRenderStart("heightmenu")
		surface.SetDrawColor(Theme.bg)
		surface.DrawRect(0, 0, W, H)
		surface.SetDrawColor(Theme.accent)
		surface.DrawRect(0, 0, W, 6)
		surface.DrawOutlinedRect(0, 0, W, H, 2)

		draw.SimpleText("HEIGHT", "DermaLarge", pad, 20, Theme.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		draw.SimpleText("twin copies you · stand IRL", "DermaDefault", pad, 56, Theme.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

		local sc = g_VR.scale or 1
		draw.SimpleText(string.format("scale  %.2f", sc), "DermaLarge", W * 0.5, 100, Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

		for _, btn in ipairs(buttons) do
			local on = btnEnabled(btn)
			surface.SetDrawColor(on and Theme.btn or Theme.btnOff)
			surface.DrawRect(btn.x, btn.y, btn.w, btn.h)
			surface.SetDrawColor(on and Theme.accent or Color(80, 40, 50))
			surface.DrawOutlinedRect(btn.x, btn.y, btn.w, btn.h, 2)
			draw.SimpleText(btnLabel(btn), "DermaLarge", btn.x + btn.w * 0.5, btn.y + btn.h * 0.5, Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		draw.SimpleText("point laser · trigger", "DermaDefault", W * 0.5, H - 36, Theme.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		VRUtilMenuRenderEnd()
	end

	renderControls()

	-- Keep scale large if something else overwrites
	hook.Add("PreRender", "vrmodheightmenuplace", function()
		if not VRUtilIsMenuOpen or not VRUtilIsMenuOpen("heightmenu") then
			hook.Remove("PreRender", "vrmodheightmenuplace")
			return
		end
		local menu = g_VR.menus and g_VR.menus.heightmenu
		if menu then
			menu.scale = scale
			menu.attachment = true
		end
	end)

	hook.Add("VRMod_Input", "vrmodheightmenuinput", function(action, pressed)
		if not pressed or g_VR.menuFocus ~= "heightmenu" then return end
		if action ~= "boolean_primaryfire" and action ~= "boolean_car_mouse_left" then return end
		for _, btn in ipairs(buttons) do
			if btnEnabled(btn)
				and g_VR.menuCursorX > btn.x and g_VR.menuCursorX < btn.x + btn.w
				and g_VR.menuCursorY > btn.y and g_VR.menuCursorY < btn.y + btn.h
			then
				btn.fn()
				renderControls()
				break
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
