if SERVER then return end
-- Cube Quick Menu — left-hand grid
-- CRITICAL: paint every frame while open; use only engine fonts (never unregistered names).
g_VR.menuBackup = g_VR.menuBackup or {}

local open = false
local SIZE = 640
local PAD = 20
local HEADER = 72
local BTN_W, BTN_H = 92, 68
local GAP = 10

-- Engine fonts only — never "CubeTitle" etc. (invalid font → crash → blank menu)
local F_TITLE = "DermaLarge"
local F_LABEL = "DermaDefaultBold"
local F_SMALL = "DermaDefault"

local C_BG = Color(12, 6, 10, 250)
local C_CRIMSON = Color(196, 30, 58, 255)
local C_HOT = Color(255, 70, 100, 255)
local C_BTN = Color(55, 14, 24, 250)
local C_BTN_HOV = Color(100, 22, 38, 255)
local C_TEXT = Color(255, 240, 244, 255)
local C_MUTED = Color(200, 150, 165, 230)

local function PaintButton(x, y, w, h, label, hovered)
	surface.SetDrawColor(hovered and C_BTN_HOV or C_BTN)
	surface.DrawRect(x, y, w, h)
	surface.SetDrawColor(hovered and C_HOT or C_CRIMSON)
	surface.DrawOutlinedRect(x, y, w, h)
	if hovered then
		surface.DrawRect(x, y, 4, h)
	end
	label = tostring(label or "")
	local words = string.Explode(" ", label, false)
	if #words <= 1 then
		draw.SimpleText(label, F_LABEL, x + w * 0.5, y + h * 0.5, C_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	else
		local mid = math.ceil(#words / 2)
		local l1 = table.concat(words, " ", 1, mid)
		local l2 = table.concat(words, " ", mid + 1)
		draw.SimpleText(l1, F_LABEL, x + w * 0.5, y + h * 0.5 - 10, C_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText(l2, F_LABEL, x + w * 0.5, y + h * 0.5 + 10, C_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

function g_VR.MenuOpen()
	-- Never block forever: stuck OpenQuickMenu hooks can return false
	local block = hook.Call("VRMod_OpenQuickMenu")
	if block == false then return end
	if open then return end
	if not g_VR.active then return end
	if not isfunction(VRUtilMenuOpen) then return end

	open = true

	local items = {}
	for k, v in pairs(g_VR.menuItems or {}) do
		local slot, slotPos = v.slot or 0, v.slotPos or 0
		local index = #items + 1
		for i = 1, #items do
			if items[i].slot > slot or (items[i].slot == slot and items[i].slotPos > slotPos) then
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

	local currentSlot, actualSlotPos = -1, 0
	for i = 1, #items do
		if items[i].slot ~= currentSlot then
			actualSlotPos = 0
			currentSlot = items[i].slot
		end
		items[i].actualSlotPos = actualSlotPos
		actualSlotPos = actualSlotPos + 1
	end

	local prevHoveredItem = -1
	local gridOriginX = PAD
	local gridOriginY = HEADER + 12
	local cellW = BTN_W + GAP
	local cellH = BTN_H + GAP

	local function paint(hoveredItem)
		if not isfunction(VRUtilMenuRenderStart) then return end
		pcall(function()
			VRUtilMenuRenderStart("miscmenu")
			surface.SetDrawColor(C_BG)
			surface.DrawRect(0, 0, SIZE, SIZE)
			surface.SetDrawColor(C_CRIMSON)
			surface.DrawRect(0, 0, SIZE, 5)
			surface.DrawOutlinedRect(0, 0, SIZE, SIZE)

			draw.SimpleText("CUBE", F_TITLE, PAD, 16, C_CRIMSON, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
			draw.SimpleText("quick · point · release to act", F_SMALL, PAD, 48, C_MUTED, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

			surface.SetDrawColor(C_CRIMSON)
			surface.DrawRect(SIZE - 48, 18, 28, 28)

			for i = 1, #items do
				local col, row = items[i].slot, items[i].actualSlotPos
				local x = gridOriginX + col * cellW
				local y = gridOriginY + row * cellH
				local item = g_VR.menuItems[items[i].index]
				if item then
					local label = (hoveredItem == i and item.hint) and item.hint or item.name
					PaintButton(x, y, BTN_W, BTN_H, label, hoveredItem == i)
				end
			end

			if hoveredItem > 0 and items[hoveredItem] and g_VR.menuItems[items[hoveredItem].index] then
				draw.SimpleText(
					tostring(g_VR.menuItems[items[hoveredItem].index].name),
					F_LABEL, SIZE * 0.5, SIZE - 28, C_HOT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
				)
			elseif #items == 0 then
				draw.SimpleText("no menu items", F_LABEL, SIZE * 0.5, SIZE * 0.5, C_MUTED, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end

			VRUtilMenuRenderEnd()
		end)
	end

	local function hitTest(mx, my)
		if not mx or not my or mx < gridOriginX or my < gridOriginY then return -1 end
		local col = math.floor((mx - gridOriginX) / cellW)
		local row = math.floor((my - gridOriginY) / cellH)
		if col < 0 or row < 0 then return -1 end
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

	local okOpen = pcall(function()
		VRUtilMenuOpen("miscmenu", SIZE, SIZE, nil, true, Vector(5, 3.5, 10), Angle(0, -90, 58), 0.038, true, function()
			hook.Remove("PreRender", "vrutil_hook_renderigm")
			local sel = prevHoveredItem
			open = false
			if sel > 0 and items[sel] and g_VR.menuItems[items[sel].index] then
				local fn = g_VR.menuItems[items[sel].index].func
				if isfunction(fn) then pcall(fn) end
			end
		end)
	end)

	if not okOpen or not (g_VR.menus and g_VR.menus.miscmenu) then
		open = false
		return
	end

	g_VR.menus.miscmenu.scale = 0.038
	g_VR.menus.miscmenu.cubeMenu = true

	-- Immediate paint so menu is visible without waiting for laser focus
	paint(-1)

	hook.Add("PreRender", "vrutil_hook_renderigm", function()
		if not open then return end
		if not g_VR.menus or not g_VR.menus.miscmenu then
			open = false
			hook.Remove("PreRender", "vrutil_hook_renderigm")
			return
		end
		g_VR.menus.miscmenu.scale = 0.038
		local hovered = -1
		if g_VR.menuFocus == "miscmenu" then
			hovered = hitTest(g_VR.menuCursorX, g_VR.menuCursorY)
		end
		prevHoveredItem = hovered
		-- ALWAYS paint while open (blank RT = "can't summon menu")
		paint(hovered)
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
	for id, data in pairs(g_VR.menuBackup or {}) do
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
	open = false
	hook.Remove("PreRender", "vrutil_hook_renderigm")
	g_VR = g_VR or {}
	g_VR.menuBackup = {}
end)

concommand.Add("vrmod_quickmenu", function()
	if g_VR and g_VR.active then g_VR.MenuOpen() end
end)
