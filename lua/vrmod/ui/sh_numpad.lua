if CLIENT then
	local open = false
	local wasClicking = false
	local justClicked = false
	local holdKey = nil
	local binder = nil
	local holdStart = 0
	local holdDelay = 0.5
	local holdRate = 0.1
	local keyMap = {
		["1"] = KEY_PAD_1,
		["2"] = KEY_PAD_2,
		["3"] = KEY_PAD_3,
		["4"] = KEY_PAD_4,
		["5"] = KEY_PAD_5,
		["6"] = KEY_PAD_6,
		["7"] = KEY_PAD_7,
		["8"] = KEY_PAD_8,
		["9"] = KEY_PAD_9,
		["0"] = KEY_PAD_0,
		["CLR"] = KEY_BACKSPACE,
		["ENT"] = KEY_PAD_ENTER,
		["+"] = KEY_PAD_PLUS,
		["-"] = KEY_PAD_MINUS,
		["*"] = KEY_PAD_MULTIPLY,
	}

	local keys = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "CLR", "0", "ENT", "+", "-", "*"}

	local function emitKey(name, down)
		local code = keyMap[name]
		if not code then return end
		net.Start("vrmod_numpad_emit")
		net.WriteUInt(code, 8)
		net.WriteBool(down)
		net.SendToServer()
	end

	local function FindCtrlNumPadUnderCursor()
		local hovered = vgui.GetHoveredPanel()
		if not IsValid(hovered) then return end
		local function IsChildOf(panel, parent)
			while IsValid(panel) do
				if panel == parent then return true end
				panel = panel:GetParent()
			end
			return false
		end

		local function FindNamedPanelAncestor(panel, targetName)
			while IsValid(panel) do
				if panel:GetName() == targetName then return panel end
				panel = panel:GetParent()
			end
			return nil
		end

		local ctrlPanel = FindNamedPanelAncestor(hovered, "CtrlNumPad")
		if not IsValid(ctrlPanel) then return end
		if IsValid(ctrlPanel.NumPad1) and IsChildOf(hovered, ctrlPanel.NumPad1) then
			binder = ctrlPanel.NumPad1
		elseif IsValid(ctrlPanel.NumPad2) and IsChildOf(hovered, ctrlPanel.NumPad2) then
			binder = ctrlPanel.NumPad2
		end
	end

	local CLOSE_BTN = { x = 512 - 52, y = 8, w = 40, h = 36 }

	local function layoutKeys(rtW, rtH)
		local headerH = 52
		local footerH = 28
		local pad = 12
		local gap = 10
		local cols, rows = 3, 5
		local usableH = rtH - headerH - footerH - pad * 2
		local usableW = rtW - pad * 2
		local bw = (usableW - gap * (cols - 1)) / cols
		local bh = (usableH - gap * (rows - 1)) / rows
		return headerH, pad, gap, bw, bh
	end

	local function hitClose(cx, cy)
		local b = CLOSE_BTN
		return cx >= b.x and cx <= b.x + b.w and cy >= b.y and cy <= b.y + b.h
	end

	function VRUtilNumpadMenuOpen()
		if open then return end
		open = true
		VRUtilMenuOpen("numpadmenu", 512, 512, nil, true, Vector(6, -10, 5.5), Angle(0, -90, 55), 0.03, true, function()
			hook.Remove("PreRender", "vrutil_hook_rendernumpad")
			hook.Remove("VRMod_Input", "vrmod_numpad_clickdetect")
			hook.Remove("Think", "vrmod_numpad_holdrepeat")
			if holdKey then
				emitKey(holdKey, false)
				holdKey = nil
			end

			wasClicking = false
			justClicked = false
			open = false
		end)

		if g_VR.menus and g_VR.menus.numpadmenu then
			g_VR.menus.numpadmenu.cubeMenu = true
			g_VR.menus.numpadmenu.grabbable = true
		end

		hook.Add("VRMod_Input", "vrmod_numpad_clickdetect", function(action, pressed)
			if action == "boolean_primaryfire" or action == "boolean_car_mouse_left" then
				justClicked = pressed and not wasClicking
				wasClicking = pressed
				FindCtrlNumPadUnderCursor()
				if not pressed and holdKey then
					emitKey(holdKey, false)
					holdKey = nil
				end
			end
		end)

		hook.Add("PreRender", "vrutil_hook_rendernumpad", function()
			if not VRUtilIsMenuOpen("numpadmenu") then return end
			if not g_VR.menuCursorX then return end
			if g_VR.menus and g_VR.menus.numpadmenu then
				g_VR.menus.numpadmenu.cubeMenu = true
				-- Keep free-float if user grabbed the panel (WayVR-style)
				if not g_VR.menus.numpadmenu.freeFloat then
					g_VR.menus.numpadmenu.attachment = true
				end
			end

			local cx, cy = g_VR.menuCursorX, g_VR.menuCursorY
			local focused = (g_VR.menuFocus == "numpadmenu")
			local headerH, pad, gap, bw, bh = layoutKeys(512, 512)
			local C = vrmod.cube
			local T = (C and C.ThemeLive and C.ThemeLive()) or (C and C.Theme) or {}

			VRUtilMenuRenderStart("numpadmenu")
			if C and C.DrawChrome then
				C.DrawChrome(0, 0, 512, 512, "NUMPAD", {
					subtitle = "", -- room for X close
					pad = 14,
					headerH = headerH,
				})
			else
				surface.SetDrawColor(12, 6, 10, 245)
				surface.DrawRect(0, 0, 512, 512)
				surface.SetDrawColor(196, 30, 58, 255)
				surface.DrawRect(0, 0, 512, 4)
				draw.SimpleText("NUMPAD", "DermaLarge", 16, 14, Color(196, 30, 58), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
			end

			-- Close (X) — top-right, Cube slot chrome
			local cb = CLOSE_BTN
			local closeHot = focused and hitClose(cx, cy)
			if C and C.DrawSlot then
				C.DrawSlot(cb.x, cb.y, cb.w, cb.h, "X", closeHot, false, true)
			else
				local bg = closeHot and Color(100, 22, 38, 255) or Color(55, 14, 24, 230)
				surface.SetDrawColor(bg)
				surface.DrawRect(cb.x, cb.y, cb.w, cb.h)
				surface.SetDrawColor(196, 30, 58, closeHot and 255 or 160)
				surface.DrawOutlinedRect(cb.x, cb.y, cb.w, cb.h, 2)
				draw.SimpleText("X", "DermaLarge", cb.x + cb.w * 0.5, cb.y + cb.h * 0.5,
					color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			if closeHot and justClicked then
				VRUtilMenuRenderEnd()
				justClicked = false
				timer.Simple(0, function()
					if isfunction(VRUtilNumpadMenuClose) then VRUtilNumpadMenuClose() end
				end)
				return
			end

			for i = 0, #keys - 1 do
				local col = i % 3
				local row = math.floor(i / 3)
				local x = pad + col * (bw + gap)
				local y = headerH + pad + row * (bh + gap)
				local key = keys[i + 1]
				local hovered = focused and cx > x and cx < x + bw and cy > y and cy < y + bh
				local special = key == "CLR" or key == "ENT" or key == "+" or key == "-" or key == "*"

				if C and C.DrawSlot then
					C.DrawSlot(x, y, bw, bh, key, hovered, special and hovered, true)
				else
					local bg = hovered and Color(100, 22, 38, 255) or Color(55, 14, 24, 230)
					draw.RoundedBox(6, x, y, bw, bh, bg)
					surface.SetDrawColor(196, 30, 58, hovered and 255 or 160)
					surface.DrawOutlinedRect(x, y, bw, bh, 2)
					draw.SimpleText(key, "DermaLarge", x + bw / 2, y + bh / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end

				if hovered and justClicked and not closeHot then
					if IsValid(binder) then
						binder:SetSelectedNumber(keyMap[key])
						binder:GetValue()
						binder = nil
					end

					emitKey(key, true)
					holdKey = key
					holdStart = SysTime()
				end
			end

			if C and C.DrawFooterLaw then
				C.DrawFooterLaw(0, 488, 512, 2)
			end

			VRUtilMenuRenderEnd()
			justClicked = false
		end)

		hook.Add("Think", "vrmod_numpad_holdrepeat", function()
			if not holdKey then return end
			if not wasClicking then
				emitKey(holdKey, false)
				holdKey = nil
				return
			end

			local dt = SysTime() - holdStart
			if dt >= holdDelay then
				emitKey(holdKey, true)
				holdStart = holdStart + holdRate
			end
		end)
	end

	function VRUtilNumpadMenuClose()
		VRUtilMenuClose("numpadmenu")
	end

	concommand.Add("vrmod_numpad", function()
		if VRUtilIsMenuOpen("numpadmenu") then
			VRUtilNumpadMenuClose()
		else
			VRUtilNumpadMenuOpen()
		end
	end)
end

if SERVER then
	util.AddNetworkString("vrmod_numpad_emit")
	net.Receive("vrmod_numpad_emit", function(len, ply)
		local key = net.ReadUInt(8)
		local down = net.ReadBool()
		if down then
			numpad.Activate(ply, key)
		else
			numpad.Deactivate(ply, key)
		end
	end)
end
