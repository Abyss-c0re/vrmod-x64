if SERVER then return end
-- =============================================================================
-- VR Quick Menu (miscmenu) — Cube chrome + multi-page layout
-- Layout SoT: vrmod.QuickMenu (cl_quick_menu_layout.lua)
-- Item activation still on menu close (laser hover); page ◀▶ on trigger press.
-- =============================================================================

g_VR = g_VR or {}
g_VR.menuBackup = g_VR.menuBackup or {}

local open = false
local pageEntries = {} -- current page entries for hit-test / activate
local prevHoveredItem = -2
local hoverNav = nil -- "prev" | "next" | nil
local navPrev = { x = 0, y = 0, w = 0, h = 0 }
local navNext = { x = 0, y = 0, w = 0, h = 0 }

local function QM()
	return vrmod and vrmod.QuickMenu
end

local function ensureLayout()
	local q = QM()
	if q and q.Load and not q.GetLayout then q.Load() end
	if q and q.GetLayout then q.GetLayout() end
end

function g_VR.MenuOpen()
	if hook.Call("VRMod_OpenQuickMenu") == false then return end
	-- Recover if flag stuck after UI reset / crash / failed open
	if open and not (g_VR.menus and g_VR.menus.miscmenu) then open = false end
	if open then return end
	if not g_VR.active or not isfunction(VRUtilMenuOpen) then return end

	-- Empty item list after crash — rebuild defaults
	if not g_VR.menuItems or #g_VR.menuItems == 0 then
		if isfunction(vrmod.RebuildInGameMenuItems) then
			pcall(vrmod.RebuildInGameMenuItems)
		end
	end

	open = true
	ensureLayout()
	prevHoveredItem = -2
	hoverNav = nil

	local qmW, qmH, qmScale = 512, 512, 0.025
	local attachMode = (vrmod.GetQuickMenuAttachMode and vrmod.GetQuickMenuAttachMode()) or "left"
	local useFloat = attachMode == "float"
	local wrist = (not useFloat and vrmod.GetQuickMenuHand and vrmod.GetQuickMenuHand())
		or (vrmod.GetSecondaryHand and vrmod.GetSecondaryHand())
		or "left"
	local qmPos, qmAng = Vector(2.5, 3, 4), Angle(0, -90, 55)
	if useFloat then
		-- Default free-float: in front of HMD (origin-relative)
		if g_VR.tracking and g_VR.tracking.hmd then
			local hmd = g_VR.tracking.hmd
			local yawOnly = Angle(0, hmd.ang.yaw, 0)
			local worldPos = hmd.pos + yawOnly:Forward() * 22 + Vector(0, 0, -4)
			local worldAng = Angle(0, yawOnly.yaw + 180, 90)
			if g_VR.origin and g_VR.originAngle then
				qmPos, qmAng = WorldToLocal(worldPos, worldAng, g_VR.origin, g_VR.originAngle)
			else
				qmPos, qmAng = worldPos, worldAng
			end
		end
		qmScale = 0.025
	elseif isfunction(VRUtilHandMenuPose) then
		qmPos, qmAng, qmScale = VRUtilHandMenuPose(qmW, qmH, 0.025, Vector(2.5, 3.5, 4), Angle(0, -90, 55), wrist)
	end

	local okOpen, errOpen = pcall(function()
		VRUtilMenuOpen("miscmenu", qmW, qmH, nil, not useFloat, qmPos, qmAng, qmScale, true, function()
			hook.Remove("PreRender", "vrutil_hook_renderigm")
			hook.Remove("VRMod_Input", "vrmod_qm_page_nav")
			open = false
			local sel = prevHoveredItem
			local nav = hoverNav
			hoverNav = nil
			if nav then return end
			if sel > 0 and pageEntries[sel] then
				local fn = pageEntries[sel].func
				if isfunction(fn) then
					timer.Simple(0, function()
						if g_VR and g_VR.active then
							local ok, err = pcall(fn)
							if not ok and vrmod.logger then
								vrmod.logger.Warn("quickmenu item: %s", tostring(err))
							end
						end
					end)
				end
			end
		end)
	end)
	if not okOpen then
		open = false
		if vrmod.logger then vrmod.logger.Warn("MenuOpen failed: %s", tostring(errOpen)) end
		return
	end

	if not (g_VR.menus and g_VR.menus.miscmenu) then
		open = false
		return
	end

	do
		local mm = g_VR.menus.miscmenu
		mm.cubeMenu = true
		mm.dirty = true
		mm.scale = qmScale
		mm.baseScale = qmScale
		mm._lastAssignedScale = qmScale
		if useFloat then
			mm.freeFloat = true
			mm.attachment = false
			mm.grabbable = true
			mm.attachHand = nil
			mm.pos = qmPos
			mm.ang = qmAng
			-- Restore last free-float pose if saved
			if vrmod.ApplyMenuLayout then
				vrmod.ApplyMenuLayout("miscmenu", mm)
			end
		else
			mm.freeFloat = false
			mm.attachment = true
			mm.grabbable = false
			mm.grabHand = nil
			mm.grabPos = nil
			mm.grabAng = nil
			mm.attachHand = wrist
			mm.pos = qmPos
			mm.ang = qmAng
			mm.scaleLocked = false
		end
	end

	-- One-shot toast: 3× menu button resets panel poses
	if not cookie.GetNumber("vrmod_hint_qm_v3", 0) or cookie.GetNumber("vrmod_hint_qm_v3", 0) == 0 then
		cookie.Set("vrmod_hint_qm_v3", "1")
		if vrmod.Toast then
			timer.Simple(0.5, function()
				if not g_VR or not g_VR.active then return end
				vrmod.Toast("3× tap Quick Menu button = reset all panel poses / sizes / dock", 6, "hint")
			end)
		end
	end

	local function layoutMetrics()
		local C = vrmod.cube
		local M = (C and C.Metrics and C.Metrics()) or { pad = 14, row = 48, headerH = 48, id = "comfort" }
		local dens = (M.id == "compact" and 0.88) or (M.id == "large" and 1.12) or 1
		-- Always fit 6 columns in 512px (large density used to make gap negative → missing/unclickable Spawn)
		local gap = 6
		local buttonWidth = math.floor((512 - gap * 5) / 6)
		buttonWidth = math.Clamp(math.floor(buttonWidth * math.min(dens, 1.05)), 64, 82)
		-- re-center leftover space into gap
		gap = math.max(4, (512 - buttonWidth * 6) / 5)
		local buttonHeight = math.floor(math.Clamp(math.max((M.row or 48) + 8, 48) * math.min(dens, 1.08), 44, 72))
		local headerH = math.min(M.headerH or 48, 56)
		local baseY = headerH + 36
		return C, M, buttonWidth, buttonHeight, gap, baseY, headerH
	end

	local function rebuildPage()
		local q = QM()
		-- Recover empty registry after lua reload without VR re-start
		if not g_VR.menuItems or #g_VR.menuItems == 0 then
			if vrmod.RebuildInGameMenuItems then
				vrmod.RebuildInGameMenuItems()
			end
		end
		-- If Spawn is unassigned (not intentionally OFF), pin to page 1 slot 0,0
		if q and q.FindItem and q.AssignToPage then
			local pi, _, hid = q.FindItem("spawn")
			if not hid and not pi then
				q.AssignToPage("spawn", 1, 0, 0)
			end
		end
		if q and q.BuildPageEntries then
			pageEntries = q.BuildPageEntries(q.GetCurrentPage and q.GetCurrentPage() or 1)
		else
			-- Fallback: legacy flat sort of all items (no pages)
			pageEntries = {}
			local items = {}
			for k, v in pairs(g_VR.menuItems or {}) do
				local slot, slotPos = v.slot, v.slotPos
				local index = #items + 1
				for i = 1, #items do
					if items[i].slot > slot or items[i].slot == slot and items[i].slotPos > slotPos then
						index = i
						break
					end
				end
				table.insert(items, index, { index = k, slot = slot, slotPos = slotPos })
			end
			local currentSlot, actualSlotPos = 0, 0
			for i = 1, #items do
				if items[i].slot ~= currentSlot then
					actualSlotPos = 0
					currentSlot = items[i].slot
				end
				local mi = g_VR.menuItems[items[i].index]
				pageEntries[#pageEntries + 1] = {
					menuIndex = items[i].index,
					name = mi and mi.name or "?",
					hint = mi and mi.hint,
					func = mi and mi.func,
					col = items[i].slot,
					row = actualSlotPos,
				}
				actualSlotPos = actualSlotPos + 1
			end
		end
	end

	rebuildPage()

	local function paint(hoveredItem)
		if not isfunction(VRUtilMenuRenderStart) then return end
		-- Cube: skip full RT rebuild when nothing changed (unfocused idle)
		if vrmod.MenuShouldRepaint and not vrmod.MenuShouldRepaint("miscmenu") then return end
		if VRUtilMenuRenderStart("miscmenu") == false then return end
		local C, M, buttonWidth, buttonHeight, gap, baseY, headerH = layoutMetrics()
		local T = (C and C.ThemeLive and C.ThemeLive()) or (C and C.Theme) or {}
		local q = QM()
		local pageCount = (q and q.GetPageCount and q.GetPageCount()) or 1
		local pageIdx = (q and q.GetCurrentPage and q.GetCurrentPage()) or 1
		local pageName = (q and q.GetPageName and q.GetPageName(pageIdx)) or "Menu"

		local subtitle = string.format("%s · %d/%d", pageName, pageIdx, pageCount)
		if T.presetLabel then
			subtitle = (T.presetLabel or "") .. " · " .. subtitle
		end

		if C and C.DrawChrome then
			C.DrawChrome(0, 0, 512, 512, "QUICK MENU", {
				subtitle = subtitle,
				pad = M.pad or 14,
				headerH = headerH,
			})
		else
			surface.SetDrawColor(12, 6, 10, 240)
			surface.DrawRect(0, 0, 512, 512)
			surface.SetDrawColor(196, 30, 58, 255)
			surface.DrawRect(0, 0, 512, 4)
			draw.SimpleText("QUICK MENU", "DermaLarge", 16, 12, Color(196, 30, 58))
			draw.SimpleText(subtitle, "DermaDefault", 16, 36, Color(200, 150, 165))
		end

		-- Always-visible UX strip (VR players — no console required)
		local fontHint = (C and C.Font and C.Font("CubeSmall")) or "DermaDefault"
		local hintCol = T.muted or Color(200, 150, 165)
		draw.SimpleText(
			"Point · trigger  ·  grip move  ·  3× menu btn = reset panels",
			fontHint, 256, 512 - 36, hintCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
		)

		-- Page nav: geometric chevrons (unicode arrows render as empty squares on Linux)
		local navY = headerH + 4
		local navH = 32
		local navW = 64
		navPrev.x, navPrev.y, navPrev.w, navPrev.h = 12, navY, navW, navH
		navNext.x, navNext.y, navNext.w, navNext.h = 512 - 12 - navW, navY, navW, navH
		local prevHot = hoverNav == "prev"
		local nextHot = hoverNav == "next"
		local canPage = pageCount > 1
		if C and C.DrawArrowBtn then
			C.DrawArrowBtn(navPrev.x, navPrev.y, navPrev.w, navPrev.h, "left", prevHot, canPage)
			C.DrawArrowBtn(navNext.x, navNext.y, navNext.w, navNext.h, "right", nextHot, canPage)
		else
			surface.SetDrawColor(prevHot and 100 or 55, 14, 24, 250)
			surface.DrawRect(navPrev.x, navPrev.y, navPrev.w, navPrev.h)
			surface.SetDrawColor(nextHot and 100 or 55, 14, 24, 250)
			surface.DrawRect(navNext.x, navNext.y, navNext.w, navNext.h)
			if C and C.DrawChevron then
				C.DrawChevron(navPrev.x + navW * 0.5, navY + navH * 0.5, 12, "left", color_white)
				C.DrawChevron(navNext.x + navW * 0.5, navY + navH * 0.5, 12, "right", color_white)
			else
				draw.SimpleText("<", "DermaLarge", navPrev.x + navW * 0.5, navY + navH * 0.5, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				draw.SimpleText(">", "DermaLarge", navNext.x + navW * 0.5, navY + navH * 0.5, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end
		-- Center page chip with label
		local chip = string.format("PAGE  %d / %d", pageIdx, pageCount)
		local fontChip = (C and C.Font and C.Font("CubeSmall")) or "DermaDefault"
		draw.SimpleText(chip, fontChip, 256, navY + navH * 0.5, T.muted or Color(200, 150, 165), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

		for i = 1, #pageEntries do
			local e = pageEntries[i]
			local bx = e.col * (buttonWidth + gap)
			local by = baseY + e.row * (buttonHeight + gap)
			if by + buttonHeight > 480 then continue end
			local label = ""
			if hoveredItem == i and e.hint then
				label = e.hint
			else
				label = e.name or ""
			end
			label = tostring(label or "")
			if C and C.DrawButtonMultiline then
				C.DrawButtonMultiline(bx, by, buttonWidth, buttonHeight, label, hoveredItem == i, true)
			elseif C and C.DrawSlot then
				C.DrawSlot(bx, by, buttonWidth, buttonHeight, label, hoveredItem == i, false, true)
			else
				draw.RoundedBox(8, bx, by, buttonWidth, buttonHeight, Color(55, 14, 24, hoveredItem == i and 250 or 200))
				draw.SimpleText(label, "HudSelectionText", bx + buttonWidth / 2, by + buttonHeight / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end

		if #pageEntries == 0 then
			local font = (C and C.Font and C.Font("CubeLabel")) or "HudSelectionText"
			draw.SimpleText("empty page — Settings → Quick Menu", font, 256, 300, T.muted or Color(200, 150, 165), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		if C and C.DrawFooterLaw then
			C.DrawFooterLaw(0, 488, 512, 2)
		end
		VRUtilMenuRenderEnd()
	end

	paint(-1)

	-- Primary-hand trigger while open: flip pages without closing
	hook.Add("VRMod_Input", "vrmod_qm_page_nav", function(action, pressed)
		if not open or not pressed then return end
		if not (vrmod.IsMenuPrimaryClick and vrmod.IsMenuPrimaryClick(action)) then return end
		if hoverNav == "prev" then
			local q = QM()
			if q and q.PrevPage then q.PrevPage() end
			rebuildPage()
			prevHoveredItem = -1
			return
		elseif hoverNav == "next" then
			local q = QM()
			if q and q.NextPage then q.NextPage() end
			rebuildPage()
			prevHoveredItem = -1
			return
		end
	end)

	hook.Add("PreRender", "vrutil_hook_renderigm", function()
		if not open or not (g_VR.menus and g_VR.menus.miscmenu) then
			open = false
			hook.Remove("PreRender", "vrutil_hook_renderigm")
			hook.Remove("VRMod_Input", "vrmod_qm_page_nav")
			return
		end
		local mm = g_VR.menus.miscmenu
		local mode = (vrmod.GetQuickMenuAttachMode and vrmod.GetQuickMenuAttachMode()) or "left"
		if mode == "float" then
			-- Free float: allow grab; keep world pose
			mm.grabbable = true
			if not mm.grabHand then
				mm.freeFloat = true
				mm.attachment = false
			end
		else
			-- Left / right hand lock
			local wrist = (vrmod.GetQuickMenuHand and vrmod.GetQuickMenuHand()) or mode
			mm.freeFloat = false
			mm.attachment = true
			mm.grabbable = false
			mm.grabHand = nil
			mm.attachHand = wrist
			if not mm.scaleLocked then
				mm.scale = 0.025
				mm.baseScale = 0.025
				mm._lastAssignedScale = 0.025
			end
		end
		mm.cubeMenu = true
		mm.paintInterval = 12
		mm.paintIntervalFocused = 0 -- dirty-only (never full-rate font spam)

		local _, _, buttonWidth, buttonHeight, gap, baseY = layoutMetrics()
		local hoveredItem = -1
		hoverNav = nil
		local mx, my = g_VR.menuCursorX or -1, g_VR.menuCursorY or -1
		if g_VR.menuFocus == "miscmenu" then
			-- Nav hit
			if mx >= navPrev.x and mx <= navPrev.x + navPrev.w and my >= navPrev.y and my <= navPrev.y + navPrev.h then
				hoverNav = "prev"
			elseif mx >= navNext.x and mx <= navNext.x + navNext.w and my >= navNext.y and my <= navNext.y + navNext.h then
				hoverNav = "next"
			else
				-- Rect hit-test (floor(col) failed when gap was negative / non-uniform)
				for i = 1, #pageEntries do
					local e = pageEntries[i]
					local bx = e.col * (buttonWidth + gap)
					local by = baseY + e.row * (buttonHeight + gap)
					if mx >= bx and mx <= bx + buttonWidth and my >= by and my <= by + buttonHeight then
						hoveredItem = i
						break
					end
				end
			end
		end
		local hoverChanged = false
		if hoverNav then
			if prevHoveredItem ~= -1 or prevHoveredItem == -1 and hoverNav then
				-- only when nav state toggles
			end
			if mm._lastHoverNav ~= hoverNav then hoverChanged = true end
			mm._lastHoverNav = hoverNav
			prevHoveredItem = -1
		else
			mm._lastHoverNav = nil
			if prevHoveredItem ~= hoveredItem then hoverChanged = true end
			prevHoveredItem = hoveredItem
		end
		if hoverChanged then
			mm.dirty = true
		end
		paint(hoveredItem)
	end)
end

function g_VR.MenuClose()
	open = false
	hook.Remove("PreRender", "vrutil_hook_renderigm")
	hook.Remove("VRMod_Input", "vrmod_qm_page_nav")
	if isfunction(VRUtilMenuClose) then
		VRUtilMenuClose("miscmenu")
	end
end

local function AddMenuItemInternal(name, slot, slotpos, func, forceSlot, hint, id)
	g_VR.menuItems = g_VR.menuItems or {}
	for _, item in ipairs(g_VR.menuItems) do
		if item.name == name and item.func == func then return end
	end
	local q = QM()
	id = id or (q and q.IdFromName and q.IdFromName(name)) or nil
	table.insert(g_VR.menuItems, {
		name = name,
		slot = slot,
		slotPos = slotpos,
		func = func,
		internal = forceSlot == true,
		hint = hint,
		id = id,
	})
end

local restoreCooldown = 1
local lastRestore = 0
hook.Add("Think", "SafeRestoreVRMenuItems", function()
	if CurTime() - lastRestore < restoreCooldown then return end
	lastRestore = CurTime()
	for id, data in pairs(g_VR.menuBackup) do
		local exists = false
		for _, item in ipairs(g_VR.menuItems or {}) do
			if item.name == data.name and item.func == data.func then
				exists = true
				break
			end
		end
		if not exists then
			AddMenuItemInternal(data.name, data.slot, data.slotPos, data.func, data.internal, data.hint, data.id)
		end
	end
end)

hook.Add("VRMod_Exit", "PurgeMenuBackup", function()
	open = false
	hook.Remove("PreRender", "vrutil_hook_renderigm")
	hook.Remove("VRMod_Input", "vrmod_qm_page_nav")
	g_VR = g_VR or {}
	g_VR.menuBackup = {}
end)
