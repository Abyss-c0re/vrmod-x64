if SERVER then return end

-- Height / seated calibration.
-- Avatar: idle PM twin (no bone-stretch tracking — that made giraffe heads).
-- UI: Compact Cube/border-cal style, not a text wall.

local convars, convarValues = vrmod.GetConvars()
local heightSession

local Theme = {
	bg = Color(18, 8, 12, 230),
	btn = Color(70, 18, 28, 250),
	btnOff = Color(40, 12, 18, 220),
	accent = Color(196, 30, 58, 255),
	text = Color(255, 240, 244, 255),
	muted = Color(200, 160, 170, 230),
	ok = Color(90, 220, 150, 255),
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

	-- Idle PM twin only — tracking SetBoneWorld was stretching head/arms (cursed)
	if vrmod.avatar and vrmod.avatar.OpenHeightCal then
		heightSession = vrmod.avatar.OpenHeightCal("heightmenu")
	end

	-- Compact panel (border-cal energy): 220×280, no essay
	local W, H = 220, 280
	VRUtilMenuOpen("heightmenu", W, H, nil, nil, Vector(), Angle(), 0.03, true, function()
		StopAvatar()
		hook.Remove("VRMod_Input", "vrmodheightmenuinput")
		hook.Remove("PreRender", "vrmodheightmenuplace")
	end)

	local buttons, renderControls
	local function seated()
		return convars.vrmod_seated:GetBool()
	end

	buttons = {
		{
			x = W - 36, y = 8, w = 28, h = 28,
			label = "X",
			enabled = true,
			fn = function()
				VRUtilMenuClose("heightmenu")
				convars.vrmod_heightmenu:SetBool(false)
			end
		},
		{
			x = 16, y = 88, w = 56, h = 44,
			label = "+",
			enabled = function() return not seated() end,
			fn = function()
				g_VR.scale = g_VR.scale + 0.5
				convars.vrmod_scale:SetFloat(g_VR.scale)
			end
		},
		{
			x = 82, y = 88, w = 56, h = 44,
			label = "AUTO",
			enabled = function() return not seated() end,
			fn = function() AutoScale() end
		},
		{
			x = 148, y = 88, w = 56, h = 44,
			label = "−",
			enabled = function() return not seated() end,
			fn = function()
				g_VR.scale = g_VR.scale - 0.5
				convars.vrmod_scale:SetFloat(g_VR.scale)
			end
		},
		{
			x = 16, y = 148, w = 90, h = 44,
			label = function() return seated() and "SEATED ON" or "SEATED OFF" end,
			enabled = true,
			fn = function()
				convars.vrmod_seated:SetBool(not seated())
				renderControls()
			end
		},
		{
			x = 114, y = 148, w = 90, h = 44,
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
		surface.DrawRect(0, 0, W, 3)
		surface.DrawOutlinedRect(0, 0, W, H)

		draw.SimpleText("HEIGHT", "DermaDefaultBold", 12, 14, Theme.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		draw.SimpleText("stand · match twin", "DermaDefault", 12, 32, Theme.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

		local sc = g_VR.scale or 1
		draw.SimpleText(string.format("scale  %.2f", sc), "DermaLarge", W * 0.5, 56, Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

		for _, btn in ipairs(buttons) do
			local on = btnEnabled(btn)
			surface.SetDrawColor(on and Theme.btn or Theme.btnOff)
			surface.DrawRect(btn.x, btn.y, btn.w, btn.h)
			if on then
				surface.SetDrawColor(Theme.accent)
				surface.DrawOutlinedRect(btn.x, btn.y, btn.w, btn.h)
			end
			draw.SimpleText(btnLabel(btn), "DermaDefaultBold", btn.x + btn.w * 0.5, btn.y + btn.h * 0.5, Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		draw.SimpleText("point · trigger", "DermaDefault", W * 0.5, H - 22, Theme.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		VRUtilMenuRenderEnd()
	end

	renderControls()

	-- Float panel beside twin (or in front of HMD if avatar missing)
	hook.Add("PreRender", "vrmodheightmenuplace", function()
		if not VRUtilIsMenuOpen or not VRUtilIsMenuOpen("heightmenu") then
			hook.Remove("PreRender", "vrmodheightmenuplace")
			return
		end
		local menu = g_VR.menus and g_VR.menus["heightmenu"]
		if not menu then return end
		local hmd = g_VR.tracking and g_VR.tracking.hmd
		if not hmd or not hmd.pos then return end

		local pos, ang
		if heightSession and heightSession.GetStand then
			local sp, sa = heightSession:GetStand()
			if sp and sa then
				pos = sp + Vector(0, 0, 52) + sa:Right() * -20
				ang = Angle(0, sa.y + 90, 90)
			end
		end
		if not pos then
			local yaw = Angle(0, hmd.ang.yaw, 0)
			pos = hmd.pos + yaw:Forward() * 36 - Vector(0, 0, 8)
			if g_VR.origin and g_VR.originAngle then
				pos, ang = WorldToLocal(pos, Angle(0, yaw.yaw + 180, 90), g_VR.origin, g_VR.originAngle)
			else
				ang = Angle(0, yaw.yaw + 180, 90)
			end
			menu.attachment = false
			menu.pos = pos
			menu.ang = ang
			menu.scale = 0.03
			return
		end
		-- World-space stand → origin-local for non-attachment menus
		if g_VR.origin and g_VR.originAngle then
			pos, ang = WorldToLocal(pos, ang, g_VR.origin, g_VR.originAngle)
		end
		menu.attachment = false
		menu.pos = pos
		menu.ang = ang
		menu.scale = 0.03
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
