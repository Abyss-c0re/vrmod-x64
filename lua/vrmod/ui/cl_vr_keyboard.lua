if SERVER then return end
-- =============================================================================
-- Shared VR keyboard (extracted for chat + custom actions + any future input).
-- vrmod.VRKeyboard_Open({ title, text, onDone, onCancel, filter })
-- =============================================================================

vrmod = vrmod or {}

local UID = "vrmod_shared_keyboard"
local open = false
local session = nil

local KW, KH = 555, 275
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
	}
end

local function Font(key)
	if vrmod.cube and vrmod.cube.Font then return vrmod.cube.Font(key) end
	return key == "CubeSmall" and "DermaDefault" or "DermaDefaultBold"
end

function vrmod.VRKeyboard_IsOpen()
	return open
end

function vrmod.VRKeyboard_Close(commit)
	if not open then return end
	local s = session
	open = false
	session = nil
	hook.Remove("PreRender", "vrmod_shared_kb_paint")
	hook.Remove("VRMod_Input", "vrmod_shared_kb_input")
	hook.Remove("VRMod_Exit", "vrmod_shared_kb_exit")
	if isfunction(VRUtilMenuClose) then
		if g_VR and g_VR.menus and g_VR.menus[UID] then
			g_VR.menus[UID].closeFunc = nil
		end
		VRUtilMenuClose(UID)
	end
	if s then
		if commit and s.onDone then
			pcall(s.onDone, s.text or "")
		elseif (not commit) and s.onCancel then
			pcall(s.onCancel)
		end
	end
end

local function paint()
	if not open or not session then return end
	if not (g_VR and g_VR.menus and g_VR.menus[UID]) then return end
	if isfunction(VRUtilMenuRenderStart) then VRUtilMenuRenderStart(UID) end

	local T = Theme()
	local C = vrmod.cube
	local headerH = 22
	local title = session.title or "KEYBOARD"

	if C and C.DrawChrome then
		C.DrawChrome(0, 0, KW, KH, title, {
			subtitle = session.text or "",
			pad = 6,
			headerH = headerH,
			barH = 3,
		})
	else
		surface.SetDrawColor(12, 6, 10, 245)
		surface.DrawRect(0, 0, KW, KH)
		surface.SetDrawColor(196, 30, 58, 255)
		surface.DrawRect(0, 0, KW, 3)
		draw.SimpleText(title, Font("CubeLabel"), 8, 6, T.text)
		draw.SimpleText(session.text or "", Font("CubeSmall"), 8, headerH - 2, T.muted)
	end

	local case = session.upper and upperCase or lowerCase
	local x = SPACING
	local y = headerH + SPACING
	local rowIndex = 0
	local closeKeyCount = 0
	local focused = g_VR.menuFocus == UID
	local cx, cy = g_VR.menuCursorX or -1, g_VR.menuCursorY or -1
	local clicked = session.justClicked and focused
	session.justClicked = false

	for i = 1, #case do
		local char = case:sub(i, i)
		if char == "\n" then
			y = y + KEY_H + SPACING
			rowIndex = rowIndex + 1
			x = (rowIndex == 1 and 20) or (rowIndex == 2 and 35) or (rowIndex == 3 and 5) or (rowIndex == 4 and 127) or 5
		else
			if char == "\3" then closeKeyCount = closeKeyCount + 1 end
			local txt
			if char == "\1" then txt = "Del"
			elseif char == "\2" then txt = "Enter"
			elseif char == "\4" then txt = "Shift"
			elseif char == "\3" then txt = closeKeyCount == 1 and "Cancel" or "Close"
			else txt = char == " " and " " or char
			end

			local special = char == "\1" or char == "\2" or char == "\3" or char == "\4"
			local w = char == " " and SPACE_W
				or char == "\2" and ENTER_W
				or (char == "\4" or char == "\3") and SPEC_W
				or KEY_W
			local h = KEY_H
			if y + h > KH - 2 then h = math.max(20, KH - 2 - y) end
			local hovered = focused and cx > x and cx < x + w and cy > y and cy < y + h

			if C and C.DrawSlot then
				C.DrawSlot(x, y, w, h, txt == " " and "spc" or txt, hovered, special and hovered, true)
			else
				surface.SetDrawColor(hovered and Color(100, 22, 38, 255) or Color(55, 14, 24, 220))
				surface.DrawRect(x, y, w, h)
				draw.SimpleText(txt == " " and "spc" or txt, Font("CubeSmall"), x + w * 0.5, y + h * 0.5, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end

			if hovered and clicked then
				if txt == "Del" then
					local t = session.text or ""
					session.text = string.sub(t, 1, math.max(0, #t - 1))
				elseif txt == "Enter" then
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
					local ch = char
					if session.filter and isfunction(session.filter) then
						local ok, filtered = pcall(session.filter, ch, session.text or "")
						if ok and filtered ~= nil then ch = filtered end
						if ch == false or ch == nil then ch = "" end
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
		surface.DrawRect(cx - 2, cy - 10, 4, 20)
		surface.DrawRect(cx - 10, cy - 2, 20, 4)
	end

	if isfunction(VRUtilMenuRenderEnd) then VRUtilMenuRenderEnd() end
end

--- opts: title, text, onDone(text), onCancel(), filter(char, text) -> char|false
function vrmod.VRKeyboard_Open(opts)
	opts = opts or {}
	if open then
		vrmod.VRKeyboard_Close(false)
	end
	if not (g_VR and g_VR.active) or not isfunction(VRUtilMenuOpen) then
		if opts.onDone then pcall(opts.onDone, opts.text or "") end
		return false
	end

	session = {
		title = opts.title or "KEYBOARD",
		text = opts.text or "",
		onDone = opts.onDone,
		onCancel = opts.onCancel,
		filter = opts.filter,
		upper = false,
		justClicked = false,
	}
	open = true

	local pos = Vector(5, 4, 3.5)
	local ang = Angle(0, -90, 10)
	VRUtilMenuOpen(UID, KW, KH, nil, true, pos, ang, 0.03, true, function()
		if open then
			open = false
			local s = session
			session = nil
			hook.Remove("PreRender", "vrmod_shared_kb_paint")
			hook.Remove("VRMod_Input", "vrmod_shared_kb_input")
			if s and s.onCancel then pcall(s.onCancel) end
		end
	end)

	if not (g_VR.menus and g_VR.menus[UID]) then
		open = false
		session = nil
		return false
	end

	local sm = g_VR.menus[UID]
	sm.cubeMenu = true
	if vrmod.MenuApplyHandAnchor then
		local hand = (vrmod.GetSecondaryHand and vrmod.GetSecondaryHand()) or "left"
		vrmod.MenuApplyHandAnchor(sm, 0.03, pos, ang, hand)
	end

	hook.Add("PreRender", "vrmod_shared_kb_paint", function()
		if not open then
			hook.Remove("PreRender", "vrmod_shared_kb_paint")
			return
		end
		paint()
	end)

	hook.Add("VRMod_Input", "vrmod_shared_kb_input", function(action, pressed)
		if not open then return end
		if not pressed then return end
		if g_VR.menuFocus ~= UID then return end
		if not (vrmod.IsMenuPrimaryClick and vrmod.IsMenuPrimaryClick(action)) then return end
		if session then session.justClicked = true end
	end)

	hook.Add("VRMod_Exit", "vrmod_shared_kb_exit", function()
		vrmod.VRKeyboard_Close(false)
	end)

	return true
end
