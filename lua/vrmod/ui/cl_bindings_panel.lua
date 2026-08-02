if SERVER then return end
-- =============================================================================
-- Controller bindings — SteamVR-style action sets in a true VR hand surface
-- (laser + trigger hitboxes). Quest 3 gold defaults live under vrmod.bindings.
-- Desktop falls back to Derma cl_bindingeditor. Never MakePopup Derma in HMD.
-- =============================================================================

vrmod = vrmod or {}

local UID = "bindings_panel"
local open = false
local filter = "main" -- main | driving  (SteamVR action sets)
local rowScroll = 0
local listen = nil -- { action, chord, collected={} }
local statusMsg, statusUntil = "", 0
local lastListenRefresh = 0
local buttons = {}

local W, H = 600, 720
local livePos, liveAng, liveScale = Vector(2.5, 3, 4), Angle(0, -90, 55), 0.024
local HEADER, TAB_H, PAD, ROW_H, FOOTER = 56, 40, 12, 54, 110
local VISIBLE = 7

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
		warn = Color(230, 180, 80, 255),
		bad = Color(255, 100, 90, 255),
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
	ROW_H = math.max(48, M.row + 10)
	HEADER = math.max(52, M.headerH + 4)
	TAB_H = math.max(32, math.floor(M.row * 0.8))
	FOOTER = math.max(100, M.footerH + 60)
	local y0 = HEADER + TAB_H + 12
	VISIBLE = math.Clamp(math.floor((H - y0 - FOOTER) / (ROW_H + 4)), 5, 12)
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

local function Actions()
	if not vrmod.bindings then return {} end
	if vrmod.bindings.ListLogicalActionsFiltered then
		return vrmod.bindings.ListLogicalActionsFiltered(filter)
	end
	return vrmod.bindings.ListLogicalActions() or {}
end

local function maxScroll()
	return math.max(0, #Actions() - VISIBLE)
end

local function SourceLabel(id)
	if vrmod.bindings and vrmod.bindings.SourceLabel then
		return vrmod.bindings.SourceLabel(id)
	end
	return id
end

local function StopListen()
	listen = nil
	if vrmod.bindings and vrmod.bindings.SetListenSuppress then
		vrmod.bindings.SetListenSuppress(false)
	end
end

local function BeginListen(action, chord)
	listen = { action = action, chord = not not chord, collected = {} }
	if vrmod.bindings and vrmod.bindings.SetListenSuppress then
		vrmod.bindings.SetListenSuppress(true)
	end
	SetStatus(chord and "Hold 2+ buttons, then Confirm" or "Press one button…", 8)
end

local function ConfirmChord()
	if not listen or not listen.chord then return end
	if #(listen.collected or {}) < 2 then
		SetStatus("Chord needs 2+ buttons", 2)
		return
	end
	local prev = vrmod.bindings.GetMap().actions[listen.action]
	local set = prev and prev.set or nil
	local warnings = vrmod.bindings.SetActionBinding(listen.action, listen.collected, "all", set)
	vrmod.bindings.Save()
	StopListen()
	if warnings and warnings[1] then
		SetStatus(warnings[1], 3)
	else
		SetStatus("Chord saved", 2)
	end
end

local function HardConflict(id)
	if not vrmod.bindings.ConflictsForAction then return false end
	for _, c in ipairs(vrmod.bindings.ConflictsForAction(id)) do
		if c.severity == "hard" then return true end
	end
	return false
end

local function SoftConflict(id)
	if not vrmod.bindings.ConflictsForAction then return false end
	for _, c in ipairs(vrmod.bindings.ConflictsForAction(id)) do
		if c.severity == "soft" then return true end
	end
	return false
end

local function ConflictSummary()
	if not vrmod.bindings.DetectConflicts then return "Conflicts: —", false end
	local hard, soft = 0, 0
	for _, c in ipairs(vrmod.bindings.DetectConflicts()) do
		if c.severity == "hard" then hard = hard + 1 else soft = soft + 1 end
	end
	if hard == 0 and soft == 0 then return "Conflicts: none", false end
	if hard > 0 then return string.format("HARD %d · note %d", hard, soft), true end
	return string.format("Notes: %d (chord overlaps)", soft), false
end

local function rebuildButtons()
	ApplyDensity()
	buttons = {}
	buttons[#buttons + 1] = { x = W - 52, y = 8, w = 40, h = 36, kind = "close" }

	local tabs = {
		{ id = "main", label = "On foot" },
		{ id = "driving", label = "Vehicle" },
	}
	local tabW = (W - PAD * 2) / #tabs
	for i, t in ipairs(tabs) do
		buttons[#buttons + 1] = {
			x = PAD + (i - 1) * tabW,
			y = HEADER,
			w = tabW - 4,
			h = TAB_H,
			kind = "filter",
			filter = t.id,
		}
	end

	local y0 = HEADER + TAB_H + 10
	local list = Actions()
	local btnW, gap, nBtns = 52, 4, 3
	for i = 1, VISIBLE do
		local ri = rowScroll + i
		local info = list[ri]
		if not info then break end
		local y = y0 + (i - 1) * (ROW_H + 4)
		if y + ROW_H > H - FOOTER then break end
		local right = W - PAD
		for bi = 0, nBtns - 1 do
			local kind = (bi == 0 and "bind") or (bi == 1 and "chord") or "def"
			buttons[#buttons + 1] = {
				x = right - (nBtns - bi) * (btnW + gap) + gap,
				y = y + 10,
				w = btnW,
				h = ROW_H - 20,
				kind = kind,
				action = info.id,
			}
		end
		buttons[#buttons + 1] = {
			x = PAD, y = y,
			w = W - PAD * 2 - nBtns * (btnW + gap) - 4,
			h = ROW_H,
			kind = "row",
			action = info.id,
		}
	end

	local fy = H - FOOTER + 10
	buttons[#buttons + 1] = { x = PAD, y = fy, w = 64, h = 34, kind = "scroll", dir = -1 }
	buttons[#buttons + 1] = { x = PAD + 72, y = fy, w = 64, h = 34, kind = "scroll", dir = 1 }
	buttons[#buttons + 1] = { x = PAD + 150, y = fy, w = 100, h = 34, kind = "confirm" }
	buttons[#buttons + 1] = { x = PAD + 258, y = fy, w = 90, h = 34, kind = "cancel" }
	buttons[#buttons + 1] = { x = W - PAD - 200, y = fy, w = 90, h = 34, kind = "reset" }
	buttons[#buttons + 1] = { x = W - PAD - 100, y = fy, w = 100, h = 34, kind = "save" }
end

local function paint()
	if not open or not (g_VR and g_VR.menus and g_VR.menus[UID]) then return end
	if isfunction(VRUtilMenuRenderStart) then VRUtilMenuRenderStart(UID) end

	local T = Theme()
	local focused = g_VR.menuFocus == UID
	local mx, my = g_VR.menuCursorX or -1, g_VR.menuCursorY or -1
	rebuildButtons()

	local sub = "Replaces SteamVR bind UI · Quest 3 defaults"
	if listen then
		sub = listen.chord and "CHORD: hold buttons…" or "BIND: press button…"
	end
	local confTxt, confHard = ConflictSummary()

	if vrmod.cube and vrmod.cube.DrawChrome then
		vrmod.cube.DrawChrome(0, 0, W, H, "BINDINGS", { subtitle = sub, headerH = HEADER })
	else
		surface.SetDrawColor(T.bg)
		surface.DrawRect(0, 0, W, H)
		surface.SetDrawColor(T.headerDim)
		surface.DrawRect(0, 0, W, HEADER)
		surface.SetDrawColor(T.header)
		surface.DrawRect(0, HEADER - 4, W, 4)
		draw.SimpleText("BINDINGS", Font("CubeTitle"), PAD, 10, T.header, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		draw.SimpleText(sub, Font("CubeSmall"), PAD, 36, focused and T.ok or T.muted)
	end

	-- Close
	local closeHot = focused and mx >= W - 52 and mx <= W - 12 and my >= 8 and my <= 44
	surface.SetDrawColor(closeHot and T.hot or T.header)
	surface.DrawRect(W - 52, 8, 40, 36)
	draw.SimpleText("X", "DermaLarge", W - 32, 26, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	-- Tabs
	local tabs = { { id = "main", label = "On foot" }, { id = "driving", label = "Vehicle" } }
	local tabW = (W - PAD * 2) / #tabs
	for i, t in ipairs(tabs) do
		local x = PAD + (i - 1) * tabW
		local y = HEADER
		local hot = focused and mx >= x and mx < x + tabW - 4 and my >= y and my < y + TAB_H
		local on = filter == t.id
		surface.SetDrawColor(on and T.header or (hot and T.rowHot or T.row))
		surface.DrawRect(x, y, tabW - 4, TAB_H)
		draw.SimpleText(t.label, Font("CubeLabel"), x + (tabW - 4) * 0.5, y + TAB_H * 0.5, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	-- Rows
	local y0 = HEADER + TAB_H + 10
	local list = Actions()
	local map = vrmod.bindings.GetMap()
	for i = 1, VISIBLE do
		local ri = rowScroll + i
		local info = list[ri]
		if not info then break end
		local y = y0 + (i - 1) * (ROW_H + 4)
		if y + ROW_H > H - FOOTER then break end

		local listening = listen and listen.action == info.id
		local hard = HardConflict(info.id)
		local soft = (not hard) and SoftConflict(info.id)
		local hot = focused and mx >= PAD and mx <= W - PAD and my >= y and my < y + ROW_H

		if listening then
			surface.SetDrawColor(60, 100, 40, 230)
		elseif hard then
			surface.SetDrawColor(90, 28, 28, 230)
		elseif soft then
			surface.SetDrawColor(70, 50, 20, 220)
		else
			surface.SetDrawColor(hot and T.rowHot or T.row)
		end
		surface.DrawRect(PAD, y, W - PAD * 2, ROW_H)
		if listening or hot or hard then
			surface.SetDrawColor(hard and T.bad or T.hot)
			surface.DrawRect(PAD, y, 4, ROW_H)
		end

		draw.SimpleText(info.label or info.id, Font("CubeLabel"), PAD + 12, y + 14, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

		local rule = map.actions and map.actions[info.id]
		local ruleTxt = vrmod.bindings.FormatRule and vrmod.bindings.FormatRule(rule, true) or "(unbound)"
		if listening then
			if listen.chord then
				local parts = {}
				for _, id in ipairs(listen.collected or {}) do
					parts[#parts + 1] = SourceLabel(id)
				end
				ruleTxt = "CHORD: " .. (#parts > 0 and table.concat(parts, " + ") or "…")
			else
				ruleTxt = "Press a button…"
			end
		elseif hard then
			ruleTxt = ruleTxt .. "  ! conflict"
		end
		draw.SimpleText(ruleTxt, Font("CubeSmall"), PAD + 12, y + 36,
			hard and T.bad or Color(180, 220, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

		local labels = { "Bind", "Chord", "Def" }
		local btnW, gap = 52, 4
		local right = W - PAD
		for bi = 0, 2 do
			local bx = right - (3 - bi) * (btnW + gap) + gap
			local by = y + 10
			local bhot = focused and mx >= bx and mx <= bx + btnW and my >= by and my <= by + ROW_H - 20
			surface.SetDrawColor(bhot and T.header or T.headerDim)
			surface.DrawRect(bx, by, btnW, ROW_H - 20)
			draw.SimpleText(labels[bi + 1], Font("CubeSmall"), bx + btnW * 0.5, by + (ROW_H - 20) * 0.5, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end

	-- Footer
	local fy = H - FOOTER + 10
	local function foot(x, w, label, hot)
		surface.SetDrawColor(hot and T.rowHot or T.row)
		surface.DrawRect(x, fy, w, 34)
		draw.SimpleText(label, Font("CubeLabel"), x + w * 0.5, fy + 17, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	local sL = focused and mx >= PAD and mx <= PAD + 64 and my >= fy and my <= fy + 34
	local sR = focused and mx >= PAD + 72 and mx <= PAD + 136 and my >= fy and my <= fy + 34
	if vrmod.cube and vrmod.cube.DrawArrowBtn then
		vrmod.cube.DrawArrowBtn(PAD, fy, 64, 34, "up", sL, true)
		vrmod.cube.DrawArrowBtn(PAD + 72, fy, 64, 34, "down", sR, true)
	else
		foot(PAD, 64, "^", sL)
		foot(PAD + 72, 64, "v", sR)
	end
	foot(PAD + 150, 100, "Confirm", focused and mx >= PAD + 150 and mx <= PAD + 250 and my >= fy and my <= fy + 34)
	foot(PAD + 258, 90, "Cancel", focused and mx >= PAD + 258 and mx <= PAD + 348 and my >= fy and my <= fy + 34)
	foot(W - PAD - 200, 90, "Reset", focused and mx >= W - PAD - 200 and mx <= W - PAD - 110 and my >= fy and my <= fy + 34)
	foot(W - PAD - 100, 100, "Save", focused and mx >= W - PAD - 100 and mx <= W - PAD and my >= fy and my <= fy + 34)

	-- Live + conflicts
	local liveY = H - 52
	local liveTxt = "Live: (start VR)"
	local sources = vrmod.bindings.GetSources and vrmod.bindings.GetSources()
	if sources then
		local pressed = {}
		for id, s in pairs(sources) do
			if type(s) == "table" and s.pressed then
				pressed[#pressed + 1] = s.label or id
			end
		end
		table.sort(pressed)
		liveTxt = "Live: " .. (#pressed > 0 and table.concat(pressed, ", ") or "(none)")
	end
	draw.SimpleText(liveTxt, Font("CubeSmall"), PAD, liveY, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	draw.SimpleText(confTxt, Font("CubeSmall"), W - PAD, liveY, confHard and T.bad or T.ok, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
	if statusMsg ~= "" and CurTime() < statusUntil then
		draw.SimpleText(statusMsg, Font("CubeLabel"), W * 0.5, liveY + 16, T.ok, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	else
		draw.SimpleText(
			string.format("%d–%d / %d", rowScroll + 1, math.min(rowScroll + VISIBLE, #list), #list),
			Font("CubeSmall"), W * 0.5, liveY + 16, T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP
		)
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
			if btn.kind == "close" then
				vrmod.BindingsPanel_Close()
				return
			elseif btn.kind == "filter" then
				filter = btn.filter or "main"
				rowScroll = 0
				StopListen()
				return
			elseif btn.kind == "scroll" then
				rowScroll = math.Clamp(rowScroll + (btn.dir or 0) * VISIBLE, 0, maxScroll())
				return
			elseif btn.kind == "bind" and btn.action then
				BeginListen(btn.action, false)
				return
			elseif btn.kind == "chord" and btn.action then
				BeginListen(btn.action, true)
				return
			elseif btn.kind == "def" and btn.action then
				if listen and listen.action == btn.action then StopListen() end
				if vrmod.bindings.RestoreActionDefault then
					vrmod.bindings.RestoreActionDefault(btn.action)
				end
				vrmod.bindings.Save()
				SetStatus("Restored default", 2)
				return
			elseif btn.kind == "row" and btn.action then
				BeginListen(btn.action, false)
				return
			elseif btn.kind == "confirm" then
				ConfirmChord()
				return
			elseif btn.kind == "cancel" then
				StopListen()
				SetStatus("Cancelled", 1.5)
				return
			elseif btn.kind == "reset" then
				StopListen()
				vrmod.bindings.ResetDefaults()
				SetStatus("All → Quest 3 defaults", 3)
				return
			elseif btn.kind == "save" then
				vrmod.bindings.Save()
				local hard = vrmod.bindings.HasHardConflicts and vrmod.bindings.HasHardConflicts()
				SetStatus(hard and "Saved (hard conflicts remain)" or "Saved", 2)
				return
			end
		end
	end
end

local function pollListen()
	if not listen or not open then return end
	local sources = vrmod.bindings.GetSources()
	if not sources then return end
	for id, s in pairs(sources) do
		if type(s) == "table" and s.pressed then
			if listen.chord then
				local found = false
				for _, c in ipairs(listen.collected) do
					if c == id then found = true break end
				end
				if not found then
					listen.collected[#listen.collected + 1] = id
					lastListenRefresh = CurTime()
				end
			else
				local prev = vrmod.bindings.GetMap().actions[listen.action]
				local set = prev and prev.set or nil
				vrmod.bindings.SetActionBinding(listen.action, { id }, "any", set)
				vrmod.bindings.Save()
				StopListen()
				SetStatus("Bound → " .. SourceLabel(id), 2)
				return
			end
		end
	end
end

function vrmod.BindingsPanel_Close()
	if not open then
		if isfunction(VRUtilMenuClose) and g_VR and g_VR.menus and g_VR.menus[UID] then
			g_VR.menus[UID].closeFunc = nil
			VRUtilMenuClose(UID)
		end
		return
	end
	StopListen()
	if vrmod.bindings and vrmod.bindings.Save then pcall(vrmod.bindings.Save) end
	open = false
	hook.Remove("PreRender", "bindings_panel_paint")
	hook.Remove("VRMod_Input", "bindings_panel_input")
	hook.Remove("Think", "bindings_panel_listen")
	hook.Remove("VRMod_Exit", "bindings_panel_exit")
	hook.Remove("VRMod_OpenQuickMenu", "bindings_panel_qm")
	if g_VR and g_VR.menus and g_VR.menus[UID] then
		g_VR.menus[UID].closeFunc = nil
	end
	if isfunction(VRUtilMenuClose) then VRUtilMenuClose(UID) end
end

function vrmod.BindingsPanel_IsOpen()
	return open
end

function vrmod.BindingsPanel_Open()
	if not vrmod.bindings then
		if vrmod.logger then vrmod.logger.Warn("vrmod.bindings not loaded") end
		return
	end

	-- Desktop → Derma editor
	if not (g_VR and g_VR.active) then
		RunConsoleCommand("vrmod_bindingeditor")
		return
	end

	if open and g_VR.menus and g_VR.menus[UID] then
		g_VR.menus[UID].dirty = true
		return
	end
	open = false
	if not isfunction(VRUtilMenuOpen) then return end

	-- Close competing menus
	if g_VR.menus then
		for _, uid in ipairs({ "miscmenu", "cube_settings", "avatar_menu", "cubeui_main", "heightmenu", "weapon_settings" }) do
			if g_VR.menus[uid] and isfunction(VRUtilMenuClose) then
				g_VR.menus[uid].closeFunc = nil
				VRUtilMenuClose(uid)
			end
		end
	end
	if vrmod.CubeSettings_Close then pcall(vrmod.CubeSettings_Close) end

	vrmod.bindings.Load()
	ApplyDensity()
	open = true
	filter = "main"
	rowScroll = 0
	listen = nil
	statusMsg = ""
	livePos, liveAng, liveScale = WristPose()

	VRUtilMenuOpen(UID, W, H, nil, true, livePos, liveAng, liveScale, true, function()
		open = false
		StopListen()
		hook.Remove("PreRender", "bindings_panel_paint")
		hook.Remove("VRMod_Input", "bindings_panel_input")
		hook.Remove("Think", "bindings_panel_listen")
		hook.Remove("VRMod_OpenQuickMenu", "bindings_panel_qm")
		if vrmod.bindings and vrmod.bindings.Save then pcall(vrmod.bindings.Save) end
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

	hook.Add("PreRender", "bindings_panel_paint", function()
		if not open then
			hook.Remove("PreRender", "bindings_panel_paint")
			return
		end
		if not (g_VR.menus and g_VR.menus[UID]) then
			open = false
			StopListen()
			return
		end
		if vrmod.MenuApplyHandAnchor and not g_VR.menus[UID].freeFloat and not g_VR.menus[UID].grabHand then
			vrmod.MenuApplyHandAnchor(g_VR.menus[UID], liveScale, livePos, liveAng, WristHand())
		end
		paint()
	end)

	hook.Add("Think", "bindings_panel_listen", function()
		if not open then
			hook.Remove("Think", "bindings_panel_listen")
			return
		end
		pollListen()
	end)

	hook.Add("VRMod_Input", "bindings_panel_input", function(action, pressed)
		if not open then return end
		if pressed and action == "boolean_chat" then
			vrmod.BindingsPanel_Close()
			return
		end
		if g_VR.menus and g_VR.menus[UID] then g_VR.menus[UID].dirty = true end
		if not pressed then return end
		if g_VR.menuFocus ~= UID then return end
		if not (vrmod.IsMenuPrimaryClick and vrmod.IsMenuPrimaryClick(action)) then return end
		activateAt(g_VR.menuCursorX or 0, g_VR.menuCursorY or 0)
	end)

	local openedAt = CurTime()
	hook.Add("VRMod_OpenQuickMenu", "bindings_panel_qm", function()
		if not open then return end
		if CurTime() - openedAt < 0.4 then return end
		timer.Simple(0, function()
			if open then vrmod.BindingsPanel_Close() end
		end)
	end)

	hook.Add("VRMod_Exit", "bindings_panel_exit", function()
		vrmod.BindingsPanel_Close()
	end)
end

hook.Add("InitPostEntity", "bindings_panel_register", function()
	timer.Simple(0.2, function()
		if not vrmod.panel2vr or not vrmod.panel2vr.RegisterNative then return end
		local openNative = function()
			vrmod.BindingsPanel_Open()
			return true
		end
		vrmod.panel2vr.RegisterNative("bindings", openNative)
		vrmod.panel2vr.RegisterNative("bindings_panel", openNative)
		vrmod.panel2vr.RegisterNative("vrmod_bindingeditor", openNative)
		vrmod.panel2vr.RegisterNative("vrmod_bindings", openNative)
		vrmod.panel2vr.RegisterNative("vrmod_controller_bindings", openNative)
	end)
end)

concommand.Add("vrmod_controller_bindings", function()
	vrmod.BindingsPanel_Open()
end)
