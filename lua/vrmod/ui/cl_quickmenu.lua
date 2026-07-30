if SERVER then return end
-- =============================================================================
-- Cube Quick Menu — left-hand grid, crimson prophecy
-- Experience worth dying for: clear labels, reachable hits, laser + trigger
-- =============================================================================
g_VR.menuBackup = g_VR.menuBackup or {}
local open = false

local SIZE = 640
local COLS = 6
local PAD = 20
local HEADER = 72
local BTN_W, BTN_H = 92, 68
local GAP = 10

function g_VR.MenuOpen()
	if hook.Call("VRMod_OpenQuickMenu") == false then return end
	if open then return end
	open = true

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

	local prevHoveredItem = -2
	local gridOriginX = PAD
	local gridOriginY = HEADER + 12
	local cellW = BTN_W + GAP
	local cellH = BTN_H + GAP

	-- Large left-hand surface (not crushed by 0.02 default — see cl_ui cube menus)
	VRUtilMenuOpen("miscmenu", SIZE, SIZE, nil, true, Vector(5, 3.5, 10), Angle(0, -90, 58), 0.038, true, function()
		hook.Remove("PreRender", "vrutil_hook_renderigm")
		open = false
		if items[prevHoveredItem] and g_VR.menuItems[items[prevHoveredItem].index] then
			g_VR.menuItems[items[prevHoveredItem].index].func()
		end
	end)

	if g_VR.menus and g_VR.menus.miscmenu then
		g_VR.menus.miscmenu.scale = 0.038
		g_VR.menus.miscmenu.cubeMenu = true
	end

	local function hitTest(mx, my)
		if mx < gridOriginX or my < gridOriginY then return -1 end
		local col = math.floor((mx - gridOriginX) / cellW)
		local row = math.floor((my - gridOriginY) / cellH)
		if col < 0 or row < 0 then return -1 end
		-- local hit within cell
		local lx = (mx - gridOriginX) - col * cellW
		local ly = (my - gridOriginY) - row * cellH
		if lx > BTN_W or ly > BTN_H then return -1 end
		for i = 1, #items do
			if items[i].slot == col and items[i].actualSlotPos == row then
				return i
			end
		end
		return -1
	end

	hook.Add("PreRender", "vrutil_hook_renderigm", function()
		if not open then return end
		local hoveredItem = -1
		if g_VR.menuFocus == "miscmenu" then
			hoveredItem = hitTest(g_VR.menuCursorX or -1, g_VR.menuCursorY or -1)
		end
		local changes = hoveredItem ~= prevHoveredItem
		prevHoveredItem = hoveredItem
		-- Always redraw when focused so hover feels alive
		if not changes and g_VR.menuFocus ~= "miscmenu" then return end

		local T = vrmod.cube and vrmod.cube.Theme or {
			bg = Color(12, 6, 10, 245),
			crimson = Color(196, 30, 58),
			text = color_white,
			muted = Color(200, 160, 170),
		}

		VRUtilMenuRenderStart("miscmenu")
		surface.SetDrawColor(T.bg)
		surface.DrawRect(0, 0, SIZE, SIZE)
		surface.SetDrawColor(T.crimson)
		surface.DrawRect(0, 0, SIZE, 5)
		surface.DrawOutlinedRect(0, 0, SIZE, SIZE, 2)

		draw.SimpleText("CUBE", "CubeTitle", PAD, 18, T.crimson, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		draw.SimpleText("quick · point · release to act", "CubeSmall", PAD, 48, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

		-- cube glyph
		surface.SetDrawColor(T.crimson)
		surface.DrawRect(SIZE - 48, 18, 28, 28)
		surface.SetDrawColor(T.crimsonHot or Color(255, 70, 100))
		surface.DrawOutlinedRect(SIZE - 48, 18, 28, 28, 2)

		for i = 1, #items do
			local col, row = items[i].slot, items[i].actualSlotPos
			local x = gridOriginX + col * cellW
			local y = gridOriginY + row * cellH
			local item = g_VR.menuItems[items[i].index]
			local label = (hoveredItem == i and item.hint) and item.hint or item.name
			if vrmod.cube and vrmod.cube.DrawButtonMultiline then
				vrmod.cube.DrawButtonMultiline(x, y, BTN_W, BTN_H, label, hoveredItem == i, true)
			else
				surface.SetDrawColor(hoveredItem == i and 100 or 40, 20, 30, 230)
				surface.DrawRect(x, y, BTN_W, BTN_H)
				draw.SimpleText(tostring(label or ""), "CubeLabel", x + BTN_W * 0.5, y + BTN_H * 0.5, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end

		if hoveredItem > 0 and g_VR.menuItems[items[hoveredItem].index] then
			local name = g_VR.menuItems[items[hoveredItem].index].name
			draw.SimpleText(tostring(name), "CubeLabel", SIZE * 0.5, SIZE - 28, T.crimsonHot or T.crimson, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		VRUtilMenuRenderEnd()
	end)
end

function g_VR.MenuClose()
	VRUtilMenuClose("miscmenu")
end

local function AddMenuItemInternal(name, slot, slotpos, func, forceSlot, hint)
	g_VR.menuItems = g_VR.menuItems or {}
	for _, item in ipairs(g_VR.menuItems) do
		if item.name == name and item.func == func then return end
	end
	table.insert(g_VR.menuItems, {
		name = name,
		slot = slot,
		slotPos = slotpos,
		func = func,
		internal = forceSlot == true,
		hint = hint,
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
			AddMenuItemInternal(data.name, data.slot, data.slotPos, data.func, data.internal, data.hint)
		end
	end
end)

hook.Add("VRMod_Exit", "PurgeMenuBackup", function()
	g_VR = g_VR or {}
	g_VR.menuBackup = {}
end)
