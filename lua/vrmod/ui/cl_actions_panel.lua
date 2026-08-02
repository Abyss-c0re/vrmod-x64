if SERVER then return end
-- =============================================================================
-- Custom actions — native VR hand panel. Text via shared chat-style keyboard.
-- Desktop → Derma cl_actioneditor.
-- =============================================================================

vrmod = vrmod or {}

local UID = "actions_panel"
local open = false
local rowScroll = 0
local selected = 1
local statusMsg, statusUntil = "", 0
local buttons = {}

local W, H = 600, 640
local livePos, liveAng, liveScale = Vector(2.5, 3, 4), Angle(0, -90, 55), 0.024
local HEADER, PAD, ROW_H, FOOTER = 56, 12, 58, 100
local VISIBLE = 7

local function Theme()
	if vrmod.cube and vrmod.cube.ThemeLive then return vrmod.cube.ThemeLive() end
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
	if vrmod.cube and vrmod.cube.Font then return vrmod.cube.Font(key) or "DermaDefault" end
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
	FOOTER = math.max(90, M.footerH + 50)
	local y0 = HEADER + 10
	VISIBLE = math.Clamp(math.floor((H - y0 - FOOTER) / (ROW_H + 4)), 4, 10)
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

local loadedOnce = false

--- In-memory list only. Do NOT reload from disk here (wipes pending Add).
local function List()
	g_VR.CustomActions = g_VR.CustomActions or {}
	return g_VR.CustomActions
end

local function EnsureLoaded()
	if loadedOnce then return end
	if isfunction(VRUtilLoadCustomActions) then pcall(VRUtilLoadCustomActions) end
	g_VR.CustomActions = g_VR.CustomActions or {}
	loadedOnce = true
end

local function maxScroll()
	return math.max(0, #List() - VISIBLE)
end

local function IsDriving(row)
	return row and (row.driving or row[4] == "1")
end

-- Soft save: JSON only from memory. Never reload before write.
local function SoftSave()
	if not file.Exists("vrmod", "DATA") then file.CreateDir("vrmod") end
	file.Write("vrmod/vrmod_custom_actions.txt", util.TableToJSON(List(), false))
end

-- Hard save on close: JSON + manifest (no SetActionManifest while in VR)
local function HardSave()
	if isfunction(VRUtilSanitizeCustomActions) then pcall(VRUtilSanitizeCustomActions) end
	SoftSave()
	if isfunction(VRUtilWriteActionManifestWithCustoms) then
		pcall(VRUtilWriteActionManifestWithCustoms)
	end
end

local editing = nil -- { index, field } while keyboard open

local function StartEdit(index, field)
	EnsureLoaded()
	local list = List()
	local row = list[index]
	if not row then
		-- Defensive: if index stale, edit last row
		index = #list
		row = list[index]
	end
	if not row then
		SetStatus("No row to edit — press Add first", 3)
		return
	end
	local text = ""
	if field == "name" then text = row[1] or ""
	elseif field == "press" then text = row[2] or ""
	elseif field == "release" then text = row[3] or ""
	end

	if not isfunction(vrmod.VRKeyboard_Open) then
		SetStatus("Keyboard missing — lua_refresh / restart", 4)
		if vrmod.Toast then vrmod.Toast("VR keyboard not loaded", 4, "error") end
		return
	end

	local title = (field == "name" and "ACTION NAME")
		or (field == "press" and "PRESS CMD")
		or "RELEASE CMD"

	local editIndex = index
	editing = { index = editIndex, field = field }

	-- Defer so the Add/Name click does not steal focus from the new keyboard menu
	timer.Simple(0.15, function()
		if not open then return end
		-- Re-resolve row (must still exist in memory — no disk reload)
		if not List()[editIndex] then
			SetStatus("Row vanished — try Add again", 3)
			editing = nil
			return
		end
		local ok = vrmod.VRKeyboard_Open({
			title = title,
			text = text,
			filter = field == "name" and function(ch)
				ch = string.lower(ch or "")
				if string.find("abcdefghijklmnopqrstuvwxyz0123456789_", ch, 1, true) then
					return ch
				end
				return false
			end or nil,
			onDone = function(result)
				editing = nil
				local r = List()[editIndex]
				if not r then
					SetStatus("Row lost on save", 3)
					return
				end
				if field == "name" then
					local n = string.lower(string.gsub(result or "", "[^a-z0-9_]", ""))
					if n == "" then n = "action_" .. tostring(editIndex) end
					r[1] = n
				elseif field == "press" then
					r[2] = result or ""
				else
					r[3] = result or ""
				end
				SoftSave()
				SetStatus("Saved " .. field .. ": " .. tostring(r[field == "name" and 1 or field == "press" and 2 or 3] or ""), 3)
				if g_VR.menus and g_VR.menus[UID] then g_VR.menus[UID].dirty = true end
			end,
			onCancel = function()
				editing = nil
				SetStatus("Edit cancelled", 1.5)
			end,
		})
		if not ok then
			editing = nil
			SetStatus("Keyboard failed to open", 4)
			if vrmod.Toast then vrmod.Toast("Keyboard failed to open", 4, "error") end
		else
			SetStatus("Keyboard open — type, then Done", 4)
		end
	end)
end

local function rebuildButtons()
	ApplyDensity()
	buttons = {}
	buttons[#buttons + 1] = { x = W - 52, y = 8, w = 40, h = 36, kind = "close" }

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

	local sub = "Add → keyboard in front of you · laser + trigger · Done"
	if editing and vrmod.VRKeyboard_IsOpen and vrmod.VRKeyboard_IsOpen() then
		sub = "Typing: " .. tostring(vrmod.VRKeyboard_GetText and vrmod.VRKeyboard_GetText() or "…")
	end
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
		local function mini(x, lab, w)
			w = w or 50
			surface.SetDrawColor(T.headerDim)
			surface.DrawRect(x, y + 6, w, 22)
			draw.SimpleText(lab, Font("CubeSmall"), x + w * 0.5, y + 17, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		mini(bx, "Name")
		mini(bx + 54, "Press")
		mini(bx + 108, "Rel", 52)
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
	draw.SimpleText(string.format("%d–%d / %d", rowScroll + 1, math.min(rowScroll + VISIBLE, n), n), Font("CubeSmall"), W * 0.5, H - 42, T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	if statusMsg ~= "" and CurTime() < statusUntil then
		draw.SimpleText(statusMsg, Font("CubeLabel"), W * 0.5, H - 24, T.ok, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	end

	if focused and mx >= 0 and my >= 0 then
		surface.SetDrawColor(T.hot)
		surface.DrawRect(mx - 2, my - 14, 4, 28)
		surface.DrawRect(mx - 14, my - 2, 28, 4)
	end

	if isfunction(VRUtilMenuRenderEnd) then VRUtilMenuRenderEnd() end
end

local function activateAt(mx, my)
	for _, btn in ipairs(buttons) do
		if mx >= btn.x and mx <= btn.x + btn.w and my >= btn.y and my <= btn.y + btn.h then
			if btn.kind == "close" or btn.kind == "close_btn" then
				vrmod.ActionsPanel_Close()
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
				local row = List()[btn.index]
				if row then
					local on = not IsDriving(row)
					row[4] = on and "1" or ""
					row.driving = on
					SoftSave()
					SetStatus(on and "Vehicle set" or "On foot set", 2)
				end
				return
			elseif btn.kind == "delete" and btn.index then
				table.remove(List(), btn.index)
				SoftSave()
				selected = math.max(1, math.min(selected, #List()))
				SetStatus("Removed", 2)
				return
			elseif btn.kind == "add" then
				-- Do NOT reload from disk or SetActionManifest here.
				EnsureLoaded()
				local list = List()
				local n = #list + 1
				local name = "action_" .. tostring(n)
				list[n] = { name, "echo " .. name, "", "" }
				SoftSave() -- write memory → disk only (no Load)
				rowScroll = maxScroll()
				selected = n
				SetStatus("Added " .. name, 2)
				StartEdit(n, "name")
				return
			elseif btn.kind == "save" then
				HardSave()
				SetStatus("Saved (restart VR if new names don't fire)", 4)
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
	if vrmod.VRKeyboard_IsOpen and vrmod.VRKeyboard_IsOpen() then
		vrmod.VRKeyboard_Close(false)
	end
	HardSave()
	open = false
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

	loadedOnce = false
	EnsureLoaded()
	ApplyDensity()
	open = true
	rowScroll = 0
	selected = math.max(1, #List())
	statusMsg = ""
	editing = nil
	livePos, liveAng, liveScale = WristPose()

	VRUtilMenuOpen(UID, W, H, nil, true, livePos, liveAng, liveScale, true, function()
		open = false
		hook.Remove("PreRender", "actions_panel_paint")
		hook.Remove("VRMod_Input", "actions_panel_input")
		hook.Remove("VRMod_OpenQuickMenu", "actions_panel_qm")
		HardSave()
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
		-- Anchor once at open only (continuous re-dock ruins free-float / UX)
		paint()
	end)

	hook.Add("VRMod_Input", "actions_panel_input", function(action, pressed)
		if not open then return end
		-- Don't steal clicks while shared keyboard is focused
		if vrmod.VRKeyboard_IsOpen and vrmod.VRKeyboard_IsOpen() then return end
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
		vrmod.panel2vr.RegisterNative("vrmod_actioneditor", function()
			vrmod.ActionsPanel_Open()
			return true
		end)
	end)
end)

concommand.Add("vrmod_actions_panel", function()
	vrmod.ActionsPanel_Open()
end)
