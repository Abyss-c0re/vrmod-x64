if SERVER then return end
g_VR.menuBackup = g_VR.menuBackup or {}
local open = false
function g_VR.MenuOpen()
	if hook.Call("VRMod_OpenQuickMenu") == false then return end
	-- Recover if flag stuck after UI reset / failed open
	if open and not (g_VR.menus and g_VR.menus.miscmenu) then open = false end
	if open then return end
	if not g_VR.active or not isfunction(VRUtilMenuOpen) then return end
	open = true
	--
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

		table.insert(items, index, {
			index = k,
			slot = slot,
			slotPos = slotPos
		})
	end

	local currentSlot, actualSlotPos = 0, 0
	for i = 1, #items do
		if items[i].slot ~= currentSlot then
			actualSlotPos = 0
			currentSlot = items[i].slot
		end

		items[i].actualSlotPos = actualSlotPos
		actualSlotPos = actualSlotPos + 1
	end

	--
	local prevHoveredItem = -2
	local qmW, qmH, qmScale = 512, 512, 0.025
	local qmPos, qmAng = Vector(2.5, 3, 4), Angle(0, -90, 55)
	if isfunction(VRUtilHandMenuPose) then
		qmPos, qmAng, qmScale = VRUtilHandMenuPose(qmW, qmH, 0.025, Vector(2.5, 3.5, 4), Angle(0, -90, 55))
	end
	VRUtilMenuOpen("miscmenu", qmW, qmH, nil, true, qmPos, qmAng, qmScale, true, function()
		hook.Remove("PreRender", "vrutil_hook_renderigm")
		open = false
		local sel = prevHoveredItem
		-- Run after miscmenu is fully closed so nested VRUtilMenuOpen works (Avatar/Settings)
		if sel > 0 and items[sel] and g_VR.menuItems and g_VR.menuItems[items[sel].index] then
			local fn = g_VR.menuItems[items[sel].index].func
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
	if g_VR.menus and g_VR.menus.miscmenu then
		g_VR.menus.miscmenu.scale = qmScale
		g_VR.menus.miscmenu.cubeMenu = true
		g_VR.menus.miscmenu.attachment = true
	end

	if not (g_VR.menus and g_VR.menus.miscmenu) then
		open = false
		return
	end

	-- Keep hand scale; never let cl_ui crush attached menus
	g_VR.menus.miscmenu.scale = 0.03
	g_VR.menus.miscmenu.cubeMenu = true
	g_VR.menus.miscmenu.attachment = true

	local function paint(hoveredItem)
		if not isfunction(VRUtilMenuRenderStart) then return end
		VRUtilMenuRenderStart("miscmenu")
		local C = vrmod.cube
		local T = (C and C.ThemeLive and C.ThemeLive()) or (C and C.Theme) or {}
		local buttonWidth, buttonHeight = 82, 56
		local gap = (512 - buttonWidth * 6) / 5

		-- Crimson Cube chrome (not flat black boxes)
		if C and C.DrawChrome then
			C.DrawChrome(0, 0, 512, 512, "QUICK MENU", {
				subtitle = (T.presetLabel or "Theme"),
				pad = 14,
				headerH = 48,
			})
		else
			surface.SetDrawColor(12, 6, 10, 240)
			surface.DrawRect(0, 0, 512, 512)
			surface.SetDrawColor(196, 30, 58, 255)
			surface.DrawRect(0, 0, 512, 4)
		end

		for i = 1, #items do
			local x, y = items[i].slot, items[i].actualSlotPos
			local bx = x * (buttonWidth + gap)
			local by = 200 + y * (buttonHeight + gap)
			local item = g_VR.menuItems and g_VR.menuItems[items[i].index]
			local label = ""
			if item then
				if hoveredItem == i and item.hint then
					label = item.hint
				else
					label = item.name
				end
				label = tostring(label or "")
			end
			if C and C.DrawButtonMultiline then
				C.DrawButtonMultiline(bx, by, buttonWidth, buttonHeight, label, hoveredItem == i, true)
			elseif C and C.DrawSlot then
				C.DrawSlot(bx, by, buttonWidth, buttonHeight, label, hoveredItem == i, false, true)
			else
				draw.RoundedBox(8, bx, by, buttonWidth, buttonHeight, Color(55, 14, 24, hoveredItem == i and 250 or 200))
				draw.SimpleText(label, "HudSelectionText", bx + buttonWidth / 2, by + buttonHeight / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end
		if #items == 0 then
			local font = (C and C.Font and C.Font("CubeLabel")) or "HudSelectionText"
			draw.SimpleText("no menu items", font, 256, 280, T.muted or Color(200, 150, 165), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		if C and C.DrawFooterLaw then
			C.DrawFooterLaw(0, 488, 512, 2)
		end
		VRUtilMenuRenderEnd()
	end

	-- Immediate paint so RT is never blank before laser focus
	paint(-1)

	hook.Add("PreRender", "vrutil_hook_renderigm", function()
		if not open or not (g_VR.menus and g_VR.menus.miscmenu) then
			open = false
			hook.Remove("PreRender", "vrutil_hook_renderigm")
			return
		end
		g_VR.menus.miscmenu.scale = 0.03
		g_VR.menus.miscmenu.cubeMenu = true
		local hoveredItem = -1
		local hoveredSlot, hoveredSlotPos = -1, -1
		if g_VR.menuFocus == "miscmenu" then
			hoveredSlot = math.floor((g_VR.menuCursorX or 0) / 86)
			hoveredSlotPos = math.floor(((g_VR.menuCursorY or 0) - 230) / 57)
		end
		for i = 1, #items do
			if items[i].slot == hoveredSlot and items[i].actualSlotPos == hoveredSlotPos then
				hoveredItem = i
				break
			end
		end
		prevHoveredItem = hoveredItem
		-- ALWAYS paint while open (blank RT = unsummonable menu)
		paint(hoveredItem)
	end)
end

function g_VR.MenuClose()
	open = false
	hook.Remove("PreRender", "vrutil_hook_renderigm")
	if isfunction(VRUtilMenuClose) then
		VRUtilMenuClose("miscmenu")
	end
end

local function AddMenuItemInternal(name, slot, slotpos, func, forceSlot, hint)
	g_VR.menuItems = g_VR.menuItems or {}
	-- Avoid duplicates
	for _, item in ipairs(g_VR.menuItems) do
		if item.name == name and item.func == func then return end
	end

	table.insert(g_VR.menuItems, {
		name = name,
		slot = slot,
		slotPos = slotpos,
		func = func, -- always string or nil
		internal = forceSlot == true,
		hint = hint, -- track forced slot
	})
end

-- Restore missing items safely
local restoreCooldown = 1 -- seconds
local lastRestore = 0
hook.Add("Think", "SafeRestoreVRMenuItems", function()
	if CurTime() - lastRestore < restoreCooldown then return end
	lastRestore = CurTime()
	for id, data in pairs(g_VR.menuBackup) do
		local exists = false
		for _, item in ipairs(g_VR.menuItems) do
			if item.name == data.name and item.func == data.func then
				exists = true
				break
			end
		end

		if not exists then
			-- revive both forced slot and hint safely
			AddMenuItemInternal(data.name, data.slot, data.slotPos, data.func, data.internal, data.hint)
		end
	end
end)

hook.Add("VRMod_Exit", "PurgeMenuBackup", function()
	open = false
	hook.Remove("PreRender", "vrutil_hook_renderigm")
	g_VR = g_VR or {}
	g_VR.menuBackup = {}
end)