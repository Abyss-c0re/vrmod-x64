if SERVER then return end
g_VR.menuBackup = g_VR.menuBackup or {}
local open = false
function g_VR.MenuOpen()
	if hook.Call("VRMod_OpenQuickMenu") == false then return end
	if open then return end
	open = true
	--
	local items = {}
	for k, v in pairs(g_VR.menuItems) do
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
	VRUtilMenuOpen("miscmenu", 512, 512, nil, true, Vector(4, 3, 9.5), Angle(0, -90, 60), 0.03, true, function()
		hook.Remove("PreRender", "vrutil_hook_renderigm")
		open = false
		if items[prevHoveredItem] and g_VR.menuItems[items[prevHoveredItem].index] then g_VR.menuItems[items[prevHoveredItem].index].func() end
	end)

	hook.Add("PreRender", "vrutil_hook_renderigm", function()
		hoveredItem = -1
		local hoveredSlot, hoveredSlotPos = -1, -1
		if g_VR.menuFocus == "miscmenu" then hoveredSlot, hoveredSlotPos = math.floor(g_VR.menuCursorX / 86), math.floor((g_VR.menuCursorY - 230) / 57) end
		for i = 1, #items do
			if items[i].slot == hoveredSlot and items[i].actualSlotPos == hoveredSlotPos then
				hoveredItem = i
				break
			end
		end

		local changes = hoveredItem ~= prevHoveredItem
		prevHoveredItem = hoveredItem
		if not changes then return end
		VRUtilMenuRenderStart("miscmenu")
		-- buttons
		local buttonWidth, buttonHeight = 82, 53
		local gap = (512 - buttonWidth * 6) / 5
		for i = 1, #items do
			local x, y = items[i].slot, items[i].actualSlotPos
			draw.RoundedBox(8, x * (buttonWidth + gap), 230 + y * (buttonHeight + gap), buttonWidth, buttonHeight, Color(0, 0, 0, hoveredItem == i and 200 or 128))
			local item = g_VR.menuItems[items[i].index]
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

		VRUtilMenuRenderEnd()
	end)
end

function g_VR.MenuClose()
	VRUtilMenuClose("miscmenu")
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
	g_VR = g_VR or {}
	g_VR.menuBackup = {}
end)