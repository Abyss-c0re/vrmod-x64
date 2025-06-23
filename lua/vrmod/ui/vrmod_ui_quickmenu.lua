if SERVER then return end
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
	local tmp = Angle(0, g_VR.tracking.hmd.ang.yaw - 90, 60) --Forward() = right, Right() = back, Up() = up (relative to panel, panel forward is looking at top of panel from middle of panel, up is normal)
	local pos, ang = WorldToLocal(g_VR.tracking.pose_righthand.pos + g_VR.tracking.pose_righthand.ang:Forward() * 9 + tmp:Right() * -7.68 + tmp:Forward() * -6.45, tmp, g_VR.origin, g_VR.originAngle)
	--uid, width, height, panel, attachment, pos, ang, scale, cursorEnabled, closeFunc
	VRUtilMenuOpen("miscmenu", 512, 512, nil, false, pos, ang, 0.03, true, function()
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
		--buttons
		local buttonWidth, buttonHeight = 82, 53
		local gap = (512 - buttonWidth * 6) / 5
		for i = 1, #items do
			local x, y = items[i].slot, items[i].actualSlotPos
			draw.RoundedBox(8, x * (buttonWidth + gap), 230 + y * (buttonHeight + gap), buttonWidth, buttonHeight, Color(0, 0, 0, hoveredItem == i and 200 or 128))
			local explosion = string.Explode(" ", g_VR.menuItems[items[i].index].name, false)
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