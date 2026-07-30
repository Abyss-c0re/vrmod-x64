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
		if items[prevHoveredItem] and g_VR.menuItems and g_VR.menuItems[items[prevHoveredItem].index] then
			local fn = g_VR.menuItems[items[prevHoveredItem].index].func
			if isfunction(fn) then fn() end
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
		local buttonWidth, buttonHeight = 82, 53
		local gap = (512 - buttonWidth * 6) / 5
		for i = 1, #items do
			local x, y = items[i].slot, items[i].actualSlotPos
			draw.RoundedBox(8, x * (buttonWidth + gap), 230 + y * (buttonHeight + gap), buttonWidth, buttonHeight, Color(0, 0, 0, hoveredItem == i and 200 or 128))
			local item = g_VR.menuItems and g_VR.menuItems[items[i].index]
			if item then
				local label
				if hoveredItem == i and item.hint then
					label = item.hint
				else
					label = item.name
				end
				label = tostring(label or "")
				local explosion = string.Explode(" ", label, false)
				for j = 1, #explosion do
					draw.SimpleText(explosion[j], "HudSelectionText", buttonWidth / 2 + x * (buttonWidth + gap), 230 + buttonHeight / 2 + y * (buttonHeight + gap) - (#explosion * 6 - 6 - (j - 1) * 12), Color(255, 255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
			end
		end
		if #items == 0 then
			draw.SimpleText("no menu items", "HudSelectionText", 256, 256, Color(200, 200, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
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