if SERVER then return end
-- =============================================================================
-- Custom actions — native VR hand panel (same chrome as settings/bindings).
-- Desktop falls back to Derma cl_actioneditor.
-- =============================================================================

vrmod = vrmod or {}

local UID = "actions_panel"
local open = false
local rowScroll = 0
local selected = 1
local statusMsg, statusUntil = "", 0
local buttons = {}
local edit = nil -- { index, field = "name"|"press"|"release", text = "" }

local W, H = 600, 720
local livePos, liveAng, liveScale = Vector(2.5, 3, 4), Angle(0, -90, 55), 0.024
local HEADER, PAD, ROW_H, FOOTER = 56, 12, 58, 120
local VISIBLE = 6

local KEYS = {
	{ "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "_" },
	{ "q", "w", "e", "r", "t", "y", "u", "i", "o", "p" },
	{ "a", "s", "d", "f", "g", "h", "j", "k", "l" },
	{ "z", "x", "c", "v", "b", "n", "m", "-", ";", " " },
}

local function Theme()
	if vrmod.cube and vrmod.cube.ThemeLive then
		return vrmod.cube.ThemeLive()
	end
	return {
		bg = Color(12, 6, 10, 250),
		header = Color(196, 30, 58, 255),
		headerDim = Color(80, 12, 24, 255),
		row = Color(40, 14, 20, 245),
		rowHot = Color(90, 22, 36, 255),
		text = Color(255, 240, 244, 255),
		muted = Color(200, 150, 165, 230),
		hot = Color(255, 70, 100, 255),
		ok = Color(90, 220, 150, 255),
	}
end

local function Font(key)
	if vrmod.cube and vrmod.cube.Font then
		return vrmod.cube.Font(key) or "DermaDefault"
	end
	if key == "CubeTitle" then return "DermaLarge" end
	if key == "CubeSmall" then return "DermaDefault" end
	return "DermaDefaultBold"
end

local function ApplyDensity()
	local M = vrmod.cube and vrmod.cube.Metrics and vrmod.cube.Metrics()
	if not M then return end
	PAD = M.pad
	ROW_H = math.max(52, M.row + 12)
	HEADER = math.max(52, M.headerH + 4)
	FOOTER = math.max(110, M.footerH + 64)
	local y0 = HEADER + 10
	VISIBLE = math.Clamp(math.floor((H - y0 - FOOTER - (edit and 200 or 0)) / (ROW_H + 4)), 4, 10)
end

local function WristHand()
	return (vrmod.GetSecondaryHand and vrmod.GetSecondaryHand()) or "left"
end

local function WristPose()
	local wrist = WristHand()
	if isfunction(VRUtilHandMenuPose) then
		return VRUtilHandMenuPose(W, H, 0.024, Vector(2.5, 3.5, 4), Angle(0, -90, 55), wrist)
	end
	return Vector(2.5, 3, 4), Angle(0, -90, 55), 0.024
end

local function SetStatus(msg, sec)
	statusMsg = tostring(msg or "")
	statusUntil = CurTime() + (sec or 2.5)
end

local function List()
	if isfunction(VRUtilLoadCustomActions) then pcall(VRUtilLoadCustomActions) end
	return g_VR.CustomActions or {}
end

local function maxScroll()
	return math.max(0, #List() - VISIBLE)
end

local function IsDriving(row)
	return row and (row.driving or row[4] == "1")
end

local function SaveAll()
	if isfunction(VRUtilSaveCustomActions) then
		pcall(VRUtilSaveCustomActions)
	end
end

local function CommitEdit()
	if not edit then return end
	local list = List()
	local row = list[edit.index]
	if not row then
		edit = nil
		return
	end
	local t = edit.text or ""
	if edit.field == "name" then
		t = string.lower(string.gsub(t, "[^a-z0-9_]", ""))
		row[1] = t
	elseif edit.field == "press" then
		row[2] = t
	elseif edit.field == "release" then
		row[3] = t
	end
	edit = nil
	SaveAll()
	SetStatus("Saved field", 2)
end

local function rebuildButtons()
	ApplyDensity()
	buttons = {}
	buttons[#buttons + 1] = { x = W - 52, y = 8, w = 40, h = 36, kind = "close" }

	if edit then
		-- Keyboard overlay
		local ky0 = H - FOOTER - 200
		local keyH, gap = 32, 4
		for ri, row in ipairs(KEYS) do
			local n = #row
			local keyW = math.floor((W - PAD * 2 - (n - 1) * gap) / n)
			for ci, ch in ipairs(row) do
				local x = PAD + (ci - 1) * (keyW + gap)
				local y = ky0 + (ri - 1) * (keyH + gap)
				buttons[#buttons + 1] = { x = x, y = y, w = keyW, h = keyH, kind = "key", ch = ch }
			end
		end
		local by = H - FOOTER + 10
		buttons[#buttons + 1] = { x = PAD, y = by, w = 100, h = 34, kind = "kb_back" }
		buttons[#buttons + 1] = { x = PAD + 110, y = by, w = 100, h = 34, kind = "kb_clear" }
		buttons[#buttons + 1] = { x = W - PAD - 200, y = by, w = 90, h = 34, kind = "kb_cancel" }
		buttons[#buttons + 1] = { x = W - PAD - 100, y = by, w = 100, h = 34, kind = "kb_done" }
		return
	end

	local y0 = HEADER + 10
	local list = List()
	for i = 1, VISIBLE do
		local ri = rowScroll + i
		local row = list[ri]
		if not row then break end
		local y = y0 + (i - 1) * (ROW_H + 4)
		if y + ROW_H > H - FOOTER then break end
		buttons[#buttons + 1] = { x = PAD, y = y, w = W - PAD * 2 - 170, h = ROW_H, kind = "row", index = ri }
		local bx = W - PAD - 160
		buttons[#buttons + 1] = { x = bx, y = y + 6, w = 50, h = 22, kind = "edit_name", index = ri }
		buttons[#buttons + 1] = { x = bx + 54, y = y + 6, w = 50, h = 22, kind = "edit_press", index = ri }
		buttons[#buttons + 1] = { x = bx + 108, y = y + 6, w = 52, h = 22, kind = "edit_rel", index = ri }
		buttons[#buttons + 1] = { x = bx, y = y + 32, w = 50, h = 20, kind = "toggle_drive", index = ri }
		buttons[#buttons + 1] = { x = bx + 54, y = y + 32, w = 106, h = 20, kind = "delete", index = ri }
	end

	local fy = H - FOOTER + 10
	buttons[#buttons + 1] = { x = PAD, y = fy, w = 64, h = 34, kind = "scroll", dir = -1 }
	buttons[#buttons + 1] = { x = PAD + 72, y = fy, w = 64, h = 34, kind = "scroll", dir = 1 }
	buttons[#buttons + 1] = { x = PAD + 150, y = fy, w = 90, h = 34, kind = "add" }
	buttons[#buttons + 1] = { x = W - PAD - 200, y = fy, w = 90, h = 34, kind = "save" }
	buttons[#buttons + 1] = { x = W - PAD - 100, y = fy, w = 100, h = 34, kind = "close_btn" }
end

local function paint()
	if not open or not (g_VR and g_VR.menus and g_VR.menus[UID]) then return end
	if isfunction(VRUtilMenuRenderStart) then VRUtilMenuRenderStart(UID) end

	local T = Theme()
	local focused = g_VR.menuFocus == UID
	local mx, my = g_VR.menuCursorX or -1, g_VR.menuCursorY or -1
	rebuildButtons()

	local sub = edit and ("Edit " .. tostring(edit.field) .. ": " .. (edit.text or "")) or "Custom console actions"
	if vrmod.cube and vrmod.cube.DrawChrome then
		vrmod.cube.DrawChrome(0, 0, W, H, "CUSTOM ACTIONS", { subtitle = sub, headerH = HEADER })
	else
		surface.SetDrawColor(T.bg)
		surface.DrawRect(0, 0, W, H)
		surface.SetDrawColor(T.headerDim)
		surface.DrawRect(0, 0, W, HEADER)
		surface.SetDrawColor(T.header)
		surface.DrawRect(0, HEADER - 4, W, 4)
		draw.SimpleText("CUSTOM ACTIONS", Font("CubeTitle"), PAD, 10, T.header, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		draw.SimpleText(sub, Font("CubeSmall"), PAD, 36, T.muted)
	end

	local closeHot = focused and mx >= W - 52 and mx <= W - 12 and my >= 8 and my <= 44
	surface.SetDrawColor(closeHot and T.hot or T.header)
	surface.DrawRect(W - 52, 8, 40, 36)
	draw.SimpleText("X", "DermaLarge", W - 32, 26, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	if edit then
		local ky0 = H - FOOTER - 200
		surface.SetDrawColor(T.row)
		surface.DrawRect(PAD, HEADER + 8, W - PAD * 2, 40)
		draw.SimpleText(edit.text or "", Font("CubeLabel"), PAD + 10, HEADER + 28, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		for _, btn in ipairs(buttons) do
			if btn.kind == "key" then
				local hot = focused and mx >= btn.x and mx <= btn.x + btn.w and my >= btn.y and my <= btn.y + btn.h
				surface.SetDrawColor(hot and T.rowHot or T.headerDim)
				surface.DrawRect(btn.x, btn.y, btn.w, btn.h)
				local lab = btn.ch == " " and "spc" or btn.ch
				draw.SimpleText(lab, Font("CubeSmall"), btn.x + btn.w * 0.5, btn.y + btn.h * 0.5, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end
		local fy = H - FOOTER + 10
		local function foot(x, w, lab, hot)
			surface.SetDrawColor(hot and T.rowHot or T.row)
			surface.DrawRect(x, fy, w, 34)
			draw.SimpleText(lab, Font("CubeLabel"), x + w * 0.5, fy + 17, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		foot(PAD, 100, "Bksp", focused and mx >= PAD and mx <= PAD + 100 and my >= fy and my <= fy + 34)
		foot(PAD + 110, 100, "Clear", focused and mx >= PAD + 110 and mx <= PAD + 210 and my >= fy and my <= fy + 34)
		foot(W - PAD - 200, 90, "Cancel", focused and mx >= W - PAD - 200 and mx <= W - PAD - 110 and my >= fy and my <= fy + 34)
		foot(W - PAD - 100, 100, "Done", focused and mx >= W - PAD - 100 and mx <= W - PAD and my >= fy and my <= fy + 34)
	else
		local y0 = HEADER + 10
		local list = List()
		for i = 1, VISIBLE do
			local ri = rowScroll + i
			local row = list[ri]
			if not row then break end
			local y = y0 + (i - 1) * (ROW_H + 4)
			if y + ROW_H > H - FOOTER then break end
			local sel = selected == ri
			local hot = focused and mx >= PAD and mx <= W - PAD and my >= y and my < y + ROW_H
			surface.SetDrawColor(sel and T.header or (hot and T.rowHot or T.row))
			surface.DrawRect(PAD, y, W - PAD * 2, ROW_H)
			local name = (row[1] and row[1] ~= "") and row[1] or "(unnamed)"
			local press = row[2] or ""
			local drive = IsDriving(row) and "[vehicle]" or "[on foot]"
			draw.SimpleText(name .. "  " .. drive, Font("CubeLabel"), PAD + 10, y + 14, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText("press: " .. press, Font("CubeSmall"), PAD + 10, y + 36, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			local bx = W - PAD - 160
			local function mini(x, lab)
				surface.SetDrawColor(T.headerDim)
				surface.DrawRect(x, y + 6, 50, 22)
				draw.SimpleText(lab, Font("CubeSmall"), x + 25, y + 17, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			mini(bx, "Name")
			mini(bx + 54, "Press")
			surface.SetDrawColor(T.headerDim)
			surface.DrawRect(bx + 108, y + 6, 52, 22)
			draw.SimpleText("Rel", Font("CubeSmall"), bx + 134, y + 17, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			surface.SetDrawColor(T.headerDim)
			surface.DrawRect(bx, y + 32, 50, 20)
			draw.SimpleText(IsDriving(row) and "Veh" or "Foot", Font("CubeSmall"), bx + 25, y + 42, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			surface.SetDrawColor(T.headerDim)
			surface.DrawRect(bx + 54, y + 32, 106, 20)
			draw.SimpleText("Delete", Font("CubeSmall"), bx + 107, y + 42, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		local fy = H - FOOTER + 10
		local function foot(x, w, lab, hot)
			surface.SetDrawColor(hot and T.rowHot or T.row)
			surface.DrawRect(x, fy, w, 34)
			draw.SimpleText(lab, Font("CubeLabel"), x + w * 0.5, fy + 17, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		if vrmod.cube and vrmod.cube.DrawArrowBtn then
			local sL = focused and mx >= PAD and mx <= PAD + 64 and my >= fy and my <= fy + 34
			local sR = focused and mx >= PAD + 72 and mx <= PAD + 136 and my >= fy and my <= fy + 34
			vrmod.cube.DrawArrowBtn(PAD, fy, 64, 34, "up", sL, true)
			vrmod.cube.DrawArrowBtn(PAD + 72, fy, 64, 34, "down", sR, true)
		else
			foot(PAD, 64, "^", false)
			foot(PAD + 72, 64, "v", false)
		end
		foot(PAD + 150, 90, "Add", focused and mx >= PAD + 150 and mx <= PAD + 240 and my >= fy and my <= fy + 34)
		foot(W - PAD - 200, 90, "Save", focused and mx >= W - PAD - 200 and mx <= W - PAD - 110 and my >= fy and my <= fy + 34)
		foot(W - PAD - 100, 100, "Close", focused and mx >= W - PAD - 100 and mx <= W - PAD and my >= fy and my <= fy + 34)

		local n = #list
		draw.SimpleText(string.format("%d–%d / %d", rowScroll + 1, math.min(rowScroll + VISIBLE, n), n), Font("CubeSmall"), W * 0.5, H - 48, T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	end

	if statusMsg ~= "" and CurTime() < statusUntil then
		draw.SimpleText(statusMsg, Font("CubeLabel"), W * 0.5, H - 28, T.ok, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	end

	if focused and mx >= 0 and my >= 0 then
		surface.SetDrawColor(T.hot)
		surface.DrawRect(mx - 2, my - 14, 4, 28)
		surface.DrawRect(mx - 14, my - 2, 28, 4)
	end

	if isfunction(VRUtilMenuRenderEnd) then VRUtilMenuRenderEnd() end
end

local function StartEdit(index, field)
	local list = List()
	local row = list[index]
	if not row then return end
	local text = ""
	if field == "name" then text = row[1] or ""
	elseif field == "press" then text = row[2] or ""
	elseif field == "release" then text = row[3] or ""
	end
	edit = { index = index, field = field, text = text }
	SetStatus("Type with keys, then Done", 3)
end

local function activateAt(mx, my)
	for _, btn in ipairs(buttons) do
		if mx >= btn.x and mx <= btn.x + btn.w and my >= btn.y and my <= btn.y + btn.h then
			if btn.kind == "close" or btn.kind == "close_btn" then
				vrmod.ActionsPanel_Close()
				return
			elseif btn.kind == "key" and edit then
				edit.text = (edit.text or "") .. (btn.ch or "")
				return
			elseif btn.kind == "kb_back" and edit then
				local t = edit.text or ""
				edit.text = string.sub(t, 1, math.max(0, #t - 1))
				return
			elseif btn.kind == "kb_clear" and edit then
				edit.text = ""
				return
			elseif btn.kind == "kb_cancel" then
				edit = nil
				return
			elseif btn.kind == "kb_done" then
				CommitEdit()
				return
			elseif btn.kind == "scroll" then
				rowScroll = math.Clamp(rowScroll + (btn.dir or 0) * VISIBLE, 0, maxScroll())
				return
			elseif btn.kind == "row" and btn.index then
				selected = btn.index
				return
			elseif btn.kind == "edit_name" and btn.index then
				StartEdit(btn.index, "name")
				return
			elseif btn.kind == "edit_press" and btn.index then
				StartEdit(btn.index, "press")
				return
			elseif btn.kind == "edit_rel" and btn.index then
				StartEdit(btn.index, "release")
				return
			elseif btn.kind == "toggle_drive" and btn.index then
				local list = List()
				local row = list[btn.index]
				if row then
					local on = not IsDriving(row)
					row[4] = on and "1" or ""
					row.driving = on
					SaveAll()
					SetStatus(on and "Vehicle set" or "On foot set", 2)
				end
				return
			elseif btn.kind == "delete" and btn.index then
				table.remove(List(), btn.index)
				SaveAll()
				selected = math.max(1, selected - 1)
				SetStatus("Removed", 2)
				return
			elseif btn.kind == "add" then
				g_VR.CustomActions = g_VR.CustomActions or {}
				g_VR.CustomActions[#g_VR.CustomActions + 1] = { "", "", "", "" }
				SaveAll()
				rowScroll = maxScroll()
				selected = #g_VR.CustomActions
				StartEdit(selected, "name")
				SetStatus("New action — set name", 3)
				return
			elseif btn.kind == "save" then
				SaveAll()
				SetStatus("Saved", 2)
				return
			end
		end
	end
end

function vrmod.ActionsPanel_Close()
	if not open then
		if isfunction(VRUtilMenuClose) and g_VR and g_VR.menus and g_VR.menus[UID] then
			g_VR.menus[UID].closeFunc = nil
			VRUtilMenuClose(UID)
		end
		return
	end
	if edit then CommitEdit() end
	SaveAll()
	open = false
	edit = nil
	hook.Remove("PreRender", "actions_panel_paint")
	hook.Remove("VRMod_Input", "actions_panel_input")
	hook.Remove("VRMod_Exit", "actions_panel_exit")
	hook.Remove("VRMod_OpenQuickMenu", "actions_panel_qm")
	if g_VR and g_VR.menus and g_VR.menus[UID] then
		g_VR.menus[UID].closeFunc = nil
	end
	if isfunction(VRUtilMenuClose) then VRUtilMenuClose(UID) end
end

function vrmod.ActionsPanel_IsOpen()
	return open
end

function vrmod.ActionsPanel_Open()
	if not (g_VR and g_VR.active) then
		RunConsoleCommand("vrmod_actioneditor")
		return
	end
	if open and g_VR.menus and g_VR.menus[UID] then
		g_VR.menus[UID].dirty = true
		return
	end
	if not isfunction(VRUtilMenuOpen) then return end

	if g_VR.menus then
		for _, uid in ipairs({ "miscmenu", "cube_settings", "avatar_menu", "cubeui_main", "heightmenu", "weapon_settings", "bindings_panel" }) do
			if g_VR.menus[uid] and isfunction(VRUtilMenuClose) then
				g_VR.menus[uid].closeFunc = nil
				VRUtilMenuClose(uid)
			end
		end
	end
	if vrmod.CubeSettings_Close then pcall(vrmod.CubeSettings_Close) end
	if vrmod.BindingsPanel_Close then pcall(vrmod.BindingsPanel_Close) end

	if isfunction(VRUtilLoadCustomActions) then pcall(VRUtilLoadCustomActions) end
	ApplyDensity()
	open = true
	edit = nil
	rowScroll = 0
	selected = 1
	statusMsg = ""
	livePos, liveAng, liveScale = WristPose()

	VRUtilMenuOpen(UID, W, H, nil, true, livePos, liveAng, liveScale, true, function()
		open = false
		edit = nil
		hook.Remove("PreRender", "actions_panel_paint")
		hook.Remove("VRMod_Input", "actions_panel_input")
		hook.Remove("VRMod_OpenQuickMenu", "actions_panel_qm")
		SaveAll()
	end)

	if not (g_VR.menus and g_VR.menus[UID]) then
		open = false
		return
	end

	local sm = g_VR.menus[UID]
	sm.cubeMenu = true
	sm.grabbable = true
	sm.resizable = true
	if vrmod.MenuApplyHandAnchor then
		vrmod.MenuApplyHandAnchor(sm, liveScale, livePos, liveAng, WristHand())
	else
		if not sm.scaleLocked then sm.scale = liveScale end
		sm.pos, sm.ang = livePos, liveAng
		sm.attachment = true
		sm.attachHand = WristHand()
	end

	paint()

	hook.Add("PreRender", "actions_panel_paint", function()
		if not open then
			hook.Remove("PreRender", "actions_panel_paint")
			return
		end
		if not (g_VR.menus and g_VR.menus[UID]) then
			open = false
			return
		end
		if vrmod.MenuApplyHandAnchor and not g_VR.menus[UID].freeFloat and not g_VR.menus[UID].grabHand then
			vrmod.MenuApplyHandAnchor(g_VR.menus[UID], liveScale, livePos, liveAng, WristHand())
		end
		paint()
	end)

	hook.Add("VRMod_Input", "actions_panel_input", function(action, pressed)
		if not open then return end
		if pressed and action == "boolean_chat" then
			vrmod.ActionsPanel_Close()
			return
		end
		if g_VR.menus and g_VR.menus[UID] then g_VR.menus[UID].dirty = true end
		if not pressed then return end
		if g_VR.menuFocus ~= UID then return end
		if not (vrmod.IsMenuPrimaryClick and vrmod.IsMenuPrimaryClick(action)) then return end
		activateAt(g_VR.menuCursorX or 0, g_VR.menuCursorY or 0)
	end)

	local openedAt = CurTime()
	hook.Add("VRMod_OpenQuickMenu", "actions_panel_qm", function()
		if not open then return end
		if CurTime() - openedAt < 0.4 then return end
		timer.Simple(0, function()
			if open then vrmod.ActionsPanel_Close() end
		end)
	end)

	hook.Add("VRMod_Exit", "actions_panel_exit", function()
		vrmod.ActionsPanel_Close()
	end)
end

hook.Add("InitPostEntity", "actions_panel_register", function()
	timer.Simple(0.25, function()
		if not vrmod.panel2vr or not vrmod.panel2vr.RegisterNative then return end
		local openNative = function()
			vrmod.ActionsPanel_Open()
			return true
		end
		vrmod.panel2vr.RegisterNative("actions", openNative)
		vrmod.panel2vr.RegisterNative("actions_panel", openNative)
		vrmod.panel2vr.RegisterNative("vrmod_actioneditor", openNative)
	end)
end)

concommand.Add("vrmod_actions_panel", function()
	vrmod.ActionsPanel_Open()
end)
