if SERVER then return end
-- =============================================================================
-- Shared VR keyboard (chat layout). Visible free-float in front of HMD.
-- vrmod.VRKeyboard_Open({ title, text, onDone, onCancel, filter })
-- =============================================================================

vrmod = vrmod or {}

local UID = "vrmod_shared_keyboard"
local open = false
local session = nil

local KW, KH = 555, 300
local KEY_W, KEY_H = 45, 42
local SPACE_W, ENTER_W, SPEC_W = 545, 65, 48
local SPACING = 1.5

local lowerCase = "1234567890\1\nqwertyuiop\nasdfghjkl\2\n\3zxcvbnm?\4\3\n "
local upperCase = "!@%\"*+=-_:\1\nQWERTYUIOP\nASDFGHJKL\2\n\3ZXCVBNM/\4\3\n "

local function Theme()
	if vrmod.cube and vrmod.cube.ThemeLive then return vrmod.cube.ThemeLive() end
	return {
		text = Color(255, 240, 244, 255),
		muted = Color(200, 150, 165, 230),
		hot = Color(255, 70, 100, 255),
	}
end

local function Font(key)
	if vrmod.cube and vrmod.cube.Font then return vrmod.cube.Font(key) end
	return key == "CubeSmall" and "DermaDefault" or "DermaDefaultBold"
end

function vrmod.VRKeyboard_IsOpen()
	return open == true
end

function vrmod.VRKeyboard_GetText()
	return session and session.text or ""
end

function vrmod.VRKeyboard_Close(commit)
	if not open then return end
	local s = session
	open = false
	session = nil
	hook.Remove("PreRender", "vrmod_shared_kb_paint")
	hook.Remove("VRMod_Input", "vrmod_shared_kb_input")
	hook.Remove("VRMod_Exit", "vrmod_shared_kb_exit")
	if g_VR and g_VR.menus and g_VR.menus[UID] then
		g_VR.menus[UID].closeFunc = nil
	end
	if isfunction(VRUtilMenuClose) then
		pcall(VRUtilMenuClose, UID)
	end
	if s then
		if commit and s.onDone then
			pcall(s.onDone, s.text or "")
		elseif not commit and s.onCancel then
			pcall(s.onCancel)
		end
	end
end

local function PoseKeyboard()
	-- Prefer free-float in front of HMD so it is never hidden under the actions panel
	if vrmod.panel2vr and isfunction(vrmod.panel2vr.ComputeFloatPose) then
		local p, a = vrmod.panel2vr.ComputeFloatPose(20, -8)
		if p and a then return p, a, false end
	end
	if g_VR and g_VR.tracking and g_VR.tracking.hmd then
		local hmd = g_VR.tracking.hmd
		local yaw = Angle(0, hmd.ang.yaw, 0)
		local pos = hmd.pos + yaw:Forward() * 18 + Vector(0, 0, -8)
		local ang = Angle(0, yaw.yaw + 180, 90)
		if g_VR.origin and g_VR.originAngle then
			pos, ang = WorldToLocal(pos, ang, g_VR.origin, g_VR.originAngle)
		end
		return pos, ang, false
	end
	return Vector(5, 4, 3.5), Angle(0, -90, 10), true
end

local function paint()
	if not open or not session then return end
	if not (g_VR and g_VR.menus and g_VR.menus[UID]) then return end

	-- Always repaint
	g_VR.menus[UID].dirty = true

	if isfunction(VRUtilMenuRenderStart) then VRUtilMenuRenderStart(UID) end

	local T = Theme()
	local C = vrmod.cube
	local headerH = 48
	local title = session.title or "KEYBOARD"

	-- Full clear background + field so text is always visible
	surface.SetDrawColor(12, 6, 10, 250)
	surface.DrawRect(0, 0, KW, KH)
	surface.SetDrawColor(196, 30, 58, 255)
	surface.DrawRect(0, 0, KW, 4)

	draw.SimpleText(title, Font("CubeLabel"), 10, 8, T.hot or Color(255, 70, 100), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

	-- Input field
	surface.SetDrawColor(40, 14, 20, 255)
	surface.DrawRect(8, 26, KW - 16, 28)
	surface.SetDrawColor(255, 70, 100, 200)
	surface.DrawOutlinedRect(8, 26, KW - 16, 28, 2)
	local show = session.text or ""
	if show == "" then show = "…" end
	draw.SimpleText(show, Font("CubeLabel"), 14, 40, T.text or color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

	local caseStr = session.upper and upperCase or lowerCase
	local x = SPACING
	local y = headerH + SPACING
	local rowIndex = 0
	local closeKeyCount = 0
	local focused = (g_VR.menuFocus == UID)
	local cx, cy = g_VR.menuCursorX or -1, g_VR.menuCursorY or -1
	local clicked = session.pendingClick == true
	if clicked then session.pendingClick = false end

	for i = 1, #caseStr do
		local char = string.sub(caseStr, i, i)
		if char == "\n" then
			y = y + KEY_H + SPACING
			rowIndex = rowIndex + 1
			x = (rowIndex == 1 and 20) or (rowIndex == 2 and 35) or (rowIndex == 3 and 5) or (rowIndex == 4 and 127) or 5
		else
			if char == "\3" then closeKeyCount = closeKeyCount + 1 end
			local txt
			if char == "\1" then txt = "Del"
			elseif char == "\2" then txt = "Done"
			elseif char == "\4" then txt = "Shift"
			elseif char == "\3" then txt = (closeKeyCount == 1) and "Cancel" or "Close"
			elseif char == " " then txt = "space"
			else txt = char
			end

			local special = char == "\1" or char == "\2" or char == "\3" or char == "\4" or char == " "
			local w = char == " " and SPACE_W
				or char == "\2" and ENTER_W
				or (char == "\4" or char == "\3") and SPEC_W
				or KEY_W
			local h = KEY_H
			if y + h > KH - 2 then h = math.max(18, KH - 2 - y) end
			local hovered = focused and cx > x and cx < x + w and cy > y and cy < y + h

			surface.SetDrawColor(hovered and Color(120, 30, 48, 255) or Color(55, 14, 24, 240))
			surface.DrawRect(x, y, w, h)
			surface.SetDrawColor(196, 30, 58, hovered and 255 or 120)
			surface.DrawOutlinedRect(x, y, w, h, 1)
			draw.SimpleText(txt, Font("CubeSmall"), x + w * 0.5, y + h * 0.5, T.text or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

			if hovered and clicked then
				if txt == "Del" then
					local t = session.text or ""
					session.text = string.sub(t, 1, math.max(0, #t - 1))
				elseif txt == "Done" then
					vrmod.VRKeyboard_Close(true)
					if isfunction(VRUtilMenuRenderEnd) then VRUtilMenuRenderEnd() end
					return
				elseif txt == "Shift" then
					session.upper = not session.upper
				elseif txt == "Cancel" or txt == "Close" then
					vrmod.VRKeyboard_Close(false)
					if isfunction(VRUtilMenuRenderEnd) then VRUtilMenuRenderEnd() end
					return
				else
					local ch = (txt == "space") and " " or char
					if session.filter and isfunction(session.filter) then
						local ok, out = pcall(session.filter, ch, session.text or "")
						if ok then
							if out == false or out == nil then ch = "" else ch = tostring(out) end
						end
					end
					if ch ~= "" then
						session.text = (session.text or "") .. ch
					end
				end
			end

			x = x + w + SPACING
		end
	end

	if focused and cx >= 0 and cy >= 0 then
		surface.SetDrawColor(255, 70, 100, 255)
		surface.DrawRect(cx - 2, cy - 12, 4, 24)
		surface.DrawRect(cx - 12, cy - 2, 24, 4)
	end

	if isfunction(VRUtilMenuRenderEnd) then VRUtilMenuRenderEnd() end
end

function vrmod.VRKeyboard_Open(opts)
	opts = opts or {}
	if open then
		vrmod.VRKeyboard_Close(false)
	end
	if not (g_VR and g_VR.active) then
		return false
	end
	if not isfunction(VRUtilMenuOpen) then
		if vrmod.Toast then vrmod.Toast("VR menus unavailable", 3, "error") end
		return false
	end

	session = {
		title = opts.title or "KEYBOARD",
		text = opts.text or "",
		onDone = opts.onDone,
		onCancel = opts.onCancel,
		filter = opts.filter,
		upper = false,
		pendingClick = false,
	}
	open = true

	local pos, ang, attach = PoseKeyboard()
	VRUtilMenuOpen(UID, KW, KH, nil, attach, pos, ang, 0.028, true, function()
		if open then
			local s = session
			open = false
			session = nil
			hook.Remove("PreRender", "vrmod_shared_kb_paint")
			hook.Remove("VRMod_Input", "vrmod_shared_kb_input")
			if s and s.onCancel then pcall(s.onCancel) end
		end
	end)

	if not (g_VR.menus and g_VR.menus[UID] and g_VR.menus[UID].rt) then
		open = false
		session = nil
		if vrmod.Toast then vrmod.Toast("Keyboard failed to open", 3, "error") end
		return false
	end

	local sm = g_VR.menus[UID]
	sm.cubeMenu = true
	sm.grabbable = true
	sm.freeFloat = not attach
	sm.attachment = attach and true or false
	sm.dirty = true
	sm.pos = pos
	sm.ang = ang
	if not sm.scaleLocked then sm.scale = 0.028 end

	hook.Add("PreRender", "vrmod_shared_kb_paint", function()
		if not open then
			hook.Remove("PreRender", "vrmod_shared_kb_paint")
			return
		end
		if not (g_VR.menus and g_VR.menus[UID]) then
			open = false
			return
		end
		paint()
	end)

	hook.Add("VRMod_Input", "vrmod_shared_kb_input", function(action, pressed)
		if not open or not pressed then return end
		if g_VR.menuFocus ~= UID then return end
		if vrmod.IsMenuPrimaryClick and vrmod.IsMenuPrimaryClick(action) then
			if session then session.pendingClick = true end
		end
	end)

	hook.Add("VRMod_Exit", "vrmod_shared_kb_exit", function()
		vrmod.VRKeyboard_Close(false)
	end)

	if vrmod.Toast then
		vrmod.Toast((opts.title or "Keyboard") .. " — laser + trigger, Done to confirm", 3, "hint")
	end
	return true
end
