-- =============================================================================
-- Cube Weapon Menu — inventory fan
--
-- Large dynamic 3D icons, category rails, glass weapon cards, laser select.
-- Subsections paginate (3 cards / page) with chevron arrows when overflow.
-- Open on changeweapon press; release selects hovered weapon / holster.
-- =============================================================================
if SERVER then return end

local lastWeaponClass = nil
local ICON_RT = 128 -- bake res (high fidelity)
local ICON_DRAW = 88 -- on-card size
local DEFAULT_ICON = Material("icon32/hand_point_090.png", "smooth")
local DEFAULT_MODEL = "models/dav0r/hoverball.mdl"

local MENU_W, MENU_H = 640, 560
local MENU_SCALE = 0.022
local PAGE_SIZE = 3 -- cards per page (fit stage without clip)
local ARROW_W, ARROW_H = 40, 80

local slotNames = {
	[0] = "MELEE",
	[1] = "SIDEARM",
	[2] = "PRIMARY",
	[3] = "RIFLE",
	[4] = "EXPLOSIVE",
	[5] = "TOOLS",
	[6] = "OTHER",
}

local iconMaterials = {}
local rtCache = {}
local solidMat = CreateMaterial("vrmod_wep_solid_cube", "UnlitGeneric", {
	["$basetexture"] = "models/debug/debugwhite",
	["$model"] = 1,
	["$vertexcolor"] = 1,
	["$vertexalpha"] = 1,
})
local wireMat = CreateMaterial("vrmod_wep_wire_cube", "Wireframe", {
	["$basetexture"] = "models/debug/debugwhite",
	["$color"] = "[1 1 1]",
})

local tempEnt
local function EnsureTempEnt()
	if IsValid(tempEnt) then return true end
	tempEnt = ClientsideModel(DEFAULT_MODEL, RENDER_GROUP_OPAQUE_ENTITY)
	if not IsValid(tempEnt) then return false end
	tempEnt:SetNoDraw(true)
	return true
end

local function Theme()
	local C = vrmod.cube
	return (C and C.ThemeLive and C.ThemeLive()) or (C and C.Theme) or {}
end

local function Fonts()
	local C = vrmod.cube
	return {
		title = (C and C.Font and C.Font("CubeTitle")) or "DermaLarge",
		label = (C and C.Font and C.Font("CubeLabel")) or "DermaDefaultBold",
		small = (C and C.Font and C.Font("CubeSmall")) or "DermaDefault",
		huge = (C and C.Font and C.Font("CubeHuge")) or "DermaLarge",
	}
end

local function GetIconRT(className)
	if not rtCache[className] then
		rtCache[className] = GetRenderTarget("vrmod_wepicon_v3_" .. className, ICON_RT, ICON_RT)
	end
	return rtCache[className]
end

--- Dynamic model icon: dark solid body + bright wireframe edge (Alyx-readable on dark glass)
function RenderWeaponToMaterial(className)
	if iconMaterials[className] then return iconMaterials[className] end

	local wepDef = weapons.GetStored(className)
	local worldMdl = wepDef and wepDef.WorldModel or ""
	if isstring(worldMdl) and worldMdl:find("^models/weapons/c_") then
		worldMdl = ""
	end
	local overrides = vrmod.MODEL_OVERRIDES or {}
	local model = (worldMdl ~= "" and worldMdl) or overrides[className] or DEFAULT_MODEL
	util.PrecacheModel(model)

	local rt = GetIconRT(className)
	if not rt or not EnsureTempEnt() then return DEFAULT_ICON end

	tempEnt:SetModel(model)
	local mins, maxs = tempEnt:GetRenderBounds()
	local center = (mins + maxs) * 0.5
	local size = maxs - mins
	local radius = math.max(size:Length() * 0.5, 4)
	-- ¾ view — more readable than pure isometric
	local camPos = center + Vector(radius * 1.15, radius * 0.95, radius * 0.7)
	local camAng = (center - camPos):Angle()

	render.PushRenderTarget(rt)
	render.Clear(0, 0, 0, 0, true, true)
	cam.Start3D(camPos, camAng, 32, 0, 0, ICON_RT, ICON_RT)
	render.SuppressEngineLighting(true)
	render.SetBlend(1)

	-- Pass 1: solid silhouette (readable mass)
	render.MaterialOverride(solidMat)
	render.SetColorModulation(0.22, 0.08, 0.12) -- deep crimson body
	tempEnt:DrawModel()

	-- Pass 2: bright wireframe edges (Alyx silhouette clarity)
	render.MaterialOverride(wireMat)
	render.SetColorModulation(1.6, 1.5, 1.55)
	tempEnt:DrawModel()

	render.MaterialOverride(nil)
	render.SetColorModulation(1, 1, 1)
	render.SuppressEngineLighting(false)
	cam.End3D()
	render.PopRenderTarget()

	local mat = CreateMaterial("vrmod_wepicon_mat_v3_" .. className, "UnlitGeneric", {
		["$basetexture"] = rt:GetName(),
		["$vertexcolor"] = 1,
		["$vertexalpha"] = 1,
		["$translucent"] = 1,
		["$nolod"] = 1,
		["$ignorez"] = 1,
	})
	iconMaterials[className] = mat
	return mat
end

local function GetWeaponAmmo(wep, ply)
	if not IsValid(wep) then return -1, -1, -1 end
	local clip, total = -1, -1
	if vrmod.utils and vrmod.utils.GetWeaponAmmoDisplay then
		clip, total = vrmod.utils.GetWeaponAmmoDisplay(wep, ply)
	else
		clip = wep.Clip1 and (wep:Clip1() or -1) or -1
		local primaryType = wep.GetPrimaryAmmoType and wep:GetPrimaryAmmoType() or -1
		if primaryType and primaryType >= 0 then total = ply:GetAmmoCount(primaryType) or 0 end
	end
	local alt = -1
	local secondaryType = wep.GetSecondaryAmmoType and wep:GetSecondaryAmmoType() or -1
	if secondaryType and secondaryType >= 0 then alt = ply:GetAmmoCount(secondaryType) or 0 end
	return clip or -1, total or -1, alt or -1
end

local function FormatAmmo(clip, total)
	if clip >= 0 and total >= 0 then return string.format("%d  |  %d", clip, total) end
	if clip >= 0 then return tostring(clip) end
	if total >= 0 then return tostring(total) end
	return "—"
end

local function Hit(mx, my, x, y, w, h)
	return mx >= x and my >= y and mx <= x + w and my <= y + h
end

--- Alyx-style glass weapon card
local function DrawWeaponCard(x, y, w, h, item, hovered, selected, ply, fonts, T, C)
	local bg = hovered and (T.btnHover or Color(100, 22, 38, 255))
		or selected and (T.panel or Color(36, 12, 18, 240))
		or (T.btn or Color(55, 14, 24, 250))
	surface.SetDrawColor(bg.r, bg.g, bg.b, hovered and 255 or 235)
	surface.DrawRect(x, y, w, h)

	local edge = (hovered or selected) and (T.crimsonHot or Color(255, 70, 100)) or (T.crimsonDim or Color(120, 20, 40))
	surface.SetDrawColor(edge.r, edge.g, edge.b, 255)
	surface.DrawOutlinedRect(x, y, w, h, hovered and 3 or 2)
	if hovered or selected then
		surface.SetDrawColor(T.crimson or Color(196, 30, 58))
		surface.DrawRect(x, y, 5, h)
		-- top crown
		surface.DrawRect(x, y, w, 3)
	end

	-- Icon stage (dark glass well for contrast)
	local pad = 10
	local stageH = h - 52
	local stageY = y + pad
	local stageX = x + pad
	local stageW = w - pad * 2
	surface.SetDrawColor(8, 4, 6, 220)
	surface.DrawRect(stageX, stageY, stageW, stageH)
	surface.SetDrawColor((T.crimsonDim or Color(120, 20, 40)).r, (T.crimsonDim or Color(120, 20, 40)).g, (T.crimsonDim or Color(120, 20, 40)).b, 140)
	surface.DrawOutlinedRect(stageX, stageY, stageW, stageH, 1)

	local mat = RenderWeaponToMaterial(item.class)
	local iconSz = math.min(ICON_DRAW, stageW - 8, stageH - 8)
	local ix = stageX + stageW * 0.5
	local iy = stageY + stageH * 0.5
	if mat then
		surface.SetMaterial(mat)
		-- Soft crimson bloom under icon
		if hovered then
			for i = 3, 1, -1 do
				local s = iconSz * (1 + i * 0.08)
				local a = 25 * (4 - i)
				local hot = T.crimsonHot or Color(255, 70, 100)
				surface.SetDrawColor(hot.r, hot.g, hot.b, a)
				surface.DrawTexturedRect(ix - s * 0.5, iy - s * 0.5, s, s)
			end
		end
		-- Bright white core (max visibility)
		surface.SetDrawColor(255, 255, 255, 255)
		surface.DrawTexturedRect(ix - iconSz * 0.5, iy - iconSz * 0.5, iconSz, iconSz)
		-- Crimson tint pass
		local tint = hovered and (T.crimsonHot or Color(255, 90, 120)) or (T.crimson or Color(196, 30, 58))
		surface.SetDrawColor(tint.r, tint.g, tint.b, hovered and 90 or 55)
		surface.DrawTexturedRect(ix - iconSz * 0.5, iy - iconSz * 0.5, iconSz, iconSz)
	end

	-- Name + ammo
	local name = item.label or item.class or "?"
	if #name > 18 then name = string.sub(name, 1, 16) .. "…" end
	draw.SimpleText(name, fonts.small, x + w * 0.5, y + h - 34,
		T.text or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

	local clip, total = -1, -1
	if IsValid(item.wep) and IsValid(ply) then
		clip, total = GetWeaponAmmo(item.wep, ply)
	end
	local ammoCol = T.ammo or T.muted or Color(200, 150, 165)
	draw.SimpleText(FormatAmmo(clip, total), fonts.small, x + w * 0.5, y + h - 18,
		ammoCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end

local open = false

function VRUtilWeaponMenuOpen()
	if open and not (g_VR.menus and g_VR.menus.weaponmenu) then open = false end
	if open then return end
	if not g_VR or not g_VR.active or not isfunction(VRUtilMenuOpen) then return end
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local hmd = g_VR.tracking and g_VR.tracking.hmd
	local primary = (vrmod.GetPrimaryHand and vrmod.GetPrimaryHand()) or "right"
	local ph = g_VR.tracking and (
		primary == "left" and g_VR.tracking.pose_lefthand or g_VR.tracking.pose_righthand
	)
	if not hmd or not hmd.ang or not ph or not ph.pos or not ph.ang then return end

	open = true
	local selectHolster = false
	local flatItems = {}
	for _, wep in ipairs(ply:GetWeapons()) do
		if not IsValid(wep) then continue end
		local class = wep:GetClass()
		if class == "weapon_vrmod_empty" then continue end
		flatItems[#flatItems + 1] = {
			wep = wep,
			class = class,
			label = language.GetPhrase(wep:GetPrintName() or class),
			slot = wep:GetSlot() or 0,
			slotPos = wep:GetSlotPos() or 0,
		}
	end
	table.sort(flatItems, function(a, b)
		if a.slot ~= b.slot then return a.slot < b.slot end
		return a.slotPos < b.slotPos
	end)

	local slotMap = {}
	local slotOrder = {}
	for _, item in ipairs(flatItems) do
		if not slotMap[item.slot] then
			slotMap[item.slot] = { slot = item.slot, items = {} }
			slotOrder[#slotOrder + 1] = item.slot
		end
		slotMap[item.slot].items[#slotMap[item.slot].items + 1] = item
	end
	table.sort(slotOrder, function(a, b) return a < b end)

	local activeWep = ply:GetActiveWeapon()
	local activeClass = IsValid(activeWep) and activeWep:GetClass() or nil
	local activeSlot = IsValid(activeWep) and activeWep:GetSlot() or (slotOrder[1] or 0)

	local state = {
		catIndex = 1,
		page = 1,
		pageByCat = {}, -- remember page when switching categories
		hoveredCat = -1,
		hoveredItem = -1, -- global index into current category items
		hoveredPrev = false,
		hoveredNext = false,
		hoveredHolster = false,
		selectedSlot = activeSlot,
	}
	for i, s in ipairs(slotOrder) do
		if s == activeSlot then state.catIndex = i break end
	end
	if #slotOrder == 0 then state.catIndex = 0 end
	-- Open on the page that holds the active weapon
	do
		local bag = slotMap[activeSlot]
		if bag and activeClass then
			for i, item in ipairs(bag.items) do
				if item.class == activeClass then
					state.page = math.max(1, math.ceil(i / PAGE_SIZE))
					state.pageByCat[state.catIndex] = state.page
					break
				end
			end
		end
	end

	-- World placement: Alyx-like in front of primary hand, slightly tilted
	local tmpAng = Angle(0, hmd.ang.yaw - 90, 55)
	local pos, ang = WorldToLocal(
		ph.pos + ph.ang:Forward() * 9 + tmpAng:Right() * -(MENU_W * MENU_SCALE * 0.35) + tmpAng:Forward() * -4,
		tmpAng,
		g_VR.origin or Vector(),
		g_VR.originAngle or Angle()
	)

	VRUtilMenuOpen("weaponmenu", MENU_W, MENU_H, nil, false, pos, ang, MENU_SCALE, true, function()
		hook.Remove("PreRender", "vrutil_hook_renderweaponselect")
		open = false
		local p = LocalPlayer()
		if not IsValid(p) then return end

		if selectHolster or state.hoveredHolster then
			local aw = p:GetActiveWeapon()
			local ac = IsValid(aw) and aw:GetClass() or nil
			if ac and ac ~= "weapon_vrmod_empty" then
				lastWeaponClass = ac
				local emptyWep = p:GetWeapon("weapon_vrmod_empty")
				if IsValid(emptyWep) then input.SelectWeapon(emptyWep) end
			elseif ac == "weapon_vrmod_empty" and lastWeaponClass then
				local prevWep = p:GetWeapon(lastWeaponClass)
				if IsValid(prevWep) then input.SelectWeapon(prevWep) end
			end
			return
		end

		local slotId = slotOrder[state.catIndex]
		local bag = slotId and slotMap[slotId]
		local item = bag and bag.items[state.hoveredItem]
		if item and IsValid(item.wep) then
			input.SelectWeapon(item.wep)
		end
	end)

	if not (g_VR.menus and g_VR.menus.weaponmenu) then
		open = false
		return
	end

	local m = g_VR.menus.weaponmenu
	m.cubeMenu = true
	m.grabbable = true
	m.scale = MENU_SCALE

	-- Layout constants
	local HEADER_H = 52
	local CAT_Y, CAT_H = 60, 40
	local STAGE_Y = 112
	local DETAIL_H = 64
	local FOOTER_H = 28
	local PAD = 16
	local CARD_W, CARD_H = 148, 200
	local CARD_GAP = 14
	local ARROW_GUTTER = ARROW_W + 8 -- leave room so cards never cover arrows
	local HOLSTER_W, HOLSTER_H = 120, 40
	local DOT_Y_OFF = 8 -- page dots below card row

	local function currentItems()
		local slotId = slotOrder[state.catIndex]
		if not slotId then return {} end
		local bag = slotMap[slotId]
		return bag and bag.items or {}
	end

	local function pageCount(n)
		return math.max(1, math.ceil(math.max(n, 0) / PAGE_SIZE))
	end

	local function clampPage()
		local n = #currentItems()
		local pages = pageCount(n)
		state.page = math.Clamp(tonumber(state.page) or 1, 1, pages)
		if state.catIndex > 0 then
			state.pageByCat[state.catIndex] = state.page
		end
		return pages
	end

	--- Visible slice + global start index (1-based into category items)
	local function pageSlice()
		local items = currentItems()
		local pages = clampPage()
		local start = (state.page - 1) * PAGE_SIZE + 1
		local slice = {}
		for i = start, math.min(start + PAGE_SIZE - 1, #items) do
			slice[#slice + 1] = { item = items[i], global = i }
		end
		return items, slice, start, pages
	end

	local function layoutCards(slice)
		local n = #slice
		if n == 0 then return {} end
		local stageW = MENU_W - PAD * 2 - ARROW_GUTTER * 2
		local stageH = MENU_H - STAGE_Y - DETAIL_H - FOOTER_H - 8
		local totalW = n * CARD_W + math.max(0, n - 1) * CARD_GAP
		local startX = PAD + ARROW_GUTTER + math.max(0, (stageW - totalW) * 0.5)
		local baseY = STAGE_Y + math.max(0, (stageH - CARD_H) * 0.5) - 6
		-- Alyx fan: slight arc — middle cards sit lower, edges higher
		local out = {}
		local mid = (n + 1) * 0.5
		for i = 1, n do
			local t = (i - mid) / math.max(n * 0.5, 1)
			local lift = -math.abs(t) * 12 -- mild arc
			out[i] = {
				x = startX + (i - 1) * (CARD_W + CARD_GAP),
				y = baseY + lift,
				w = CARD_W,
				h = CARD_H,
			}
		end
		return out
	end

	--- Geometric chevrons (unicode ◀▶ are empty squares on many Linux fonts)
	local function drawPageArrow(x, y, w, h, dir, enabled, hot, C, T)
		if C and C.DrawArrowBtn then
			C.DrawArrowBtn(x, y, w, h, dir, hot, enabled)
			return
		end
		local bg = not enabled and Color(30, 12, 16, 180)
			or hot and (T.btnHover or Color(100, 22, 38, 255))
			or (T.btn or Color(55, 14, 24, 250))
		surface.SetDrawColor(bg.r, bg.g, bg.b, bg.a or 250)
		surface.DrawRect(x, y, w, h)
		local edge = (enabled and (hot and (T.crimsonHot or Color(255, 70, 100)) or (T.crimson or Color(196, 30, 58))))
			or (T.crimsonDim or Color(80, 20, 30))
		surface.SetDrawColor(edge.r, edge.g, edge.b, enabled and 255 or 120)
		surface.DrawOutlinedRect(x, y, w, h, hot and enabled and 2 or 1)
		if C and C.DrawChevron then
			C.DrawChevron(x + w * 0.5, y + h * 0.5, 14, dir, enabled and color_white or (T.muted or Color(120, 80, 90)))
		else
			local glyph = dir == "left" and "<" or ">"
			draw.SimpleText(glyph, "DermaLarge", x + w * 0.5, y + h * 0.5,
				enabled and color_white or (T.muted or Color(120, 80, 90)), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end

	local function paint()
		if not isfunction(VRUtilMenuRenderStart) then return end
		local wm = g_VR.menus and g_VR.menus.weaponmenu
		if wm then
			wm.paintInterval = wm.paintInterval or 8
			wm.paintIntervalFocused = 1
		end
		if vrmod.MenuShouldRepaint and not vrmod.MenuShouldRepaint("weaponmenu") then return end
		if VRUtilMenuRenderStart("weaponmenu") == false then return end
		local C = vrmod.cube
		local T = Theme()
		local fonts = Fonts()
		local mx = (g_VR.menuFocus == "weaponmenu") and (g_VR.menuCursorX or -1) or -1
		local my = (g_VR.menuFocus == "weaponmenu") and (g_VR.menuCursorY or -1) or -1

		-- ── Chrome plate ──────────────────────────────────────────
		if C and C.DrawChrome then
			C.DrawChrome(0, 0, MENU_W, MENU_H, "WEAPONS", {
				subtitle = T.presetLabel or "CUBE",
				pad = 16,
				headerH = HEADER_H,
			})
		else
			surface.SetDrawColor(12, 6, 10, 250)
			surface.DrawRect(0, 0, MENU_W, MENU_H)
			surface.SetDrawColor(196, 30, 58)
			surface.DrawRect(0, 0, MENU_W, 4)
			draw.SimpleText("WEAPONS", fonts.title, 16, 12, Color(196, 30, 58))
		end

		-- ── Category rail (HL:A inventory groups) ─────────────────
		state.hoveredCat = -1
		local cats = #slotOrder
		if cats > 0 then
			local gap = 8
			local usable = MENU_W - PAD * 2 - (cats - 1) * gap
			local tw = math.floor(usable / cats)
			tw = math.Clamp(tw, 64, 120)
			local total = cats * tw + (cats - 1) * gap
			local cx0 = (MENU_W - total) * 0.5
			for i, slotId in ipairs(slotOrder) do
				local x = cx0 + (i - 1) * (tw + gap)
				local label = slotNames[slotId] or ("S" .. tostring(slotId))
				local hot = Hit(mx, my, x, CAT_Y, tw, CAT_H)
				local sel = state.catIndex == i
				if hot then state.hoveredCat = i end
				if C and C.DrawSlot then
					C.DrawSlot(x, CAT_Y, tw, CAT_H, label, hot, sel, true)
				else
					local col = (hot or sel) and Color(100, 22, 38) or Color(55, 14, 24)
					surface.SetDrawColor(col)
					surface.DrawRect(x, CAT_Y, tw, CAT_H)
					draw.SimpleText(label, fonts.small, x + tw * 0.5, CAT_Y + CAT_H * 0.5,
						color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
			end
		end

		-- Soft stage well
		local stageBottom = MENU_H - DETAIL_H - FOOTER_H
		surface.SetDrawColor((T.bgGlass or Color(22, 10, 16, 230)).r, 8, 10, 120)
		surface.DrawRect(PAD, STAGE_Y - 4, MENU_W - PAD * 2, stageBottom - STAGE_Y + 4)

		-- ── Weapon cards (Alyx fan, paginated) ─────────────────────
		local items, slice, _pageStart, pages = pageSlice()
		local cards = layoutCards(slice)
		state.hoveredItem = -1
		state.hoveredPrev = false
		state.hoveredNext = false

		local stageH = stageBottom - STAGE_Y
		local arrowY = STAGE_Y + math.max(0, (stageH - ARROW_H) * 0.5) - 10
		local prevX = PAD
		local nextX = MENU_W - PAD - ARROW_W
		local canPrev = pages > 1 and state.page > 1
		local canNext = pages > 1 and state.page < pages
		if pages > 1 then
			state.hoveredPrev = canPrev and Hit(mx, my, prevX, arrowY, ARROW_W, ARROW_H)
			state.hoveredNext = canNext and Hit(mx, my, nextX, arrowY, ARROW_W, ARROW_H)
			drawPageArrow(prevX, arrowY, ARROW_W, ARROW_H, "left", canPrev, state.hoveredPrev, C, T)
			drawPageArrow(nextX, arrowY, ARROW_W, ARROW_H, "right", canNext, state.hoveredNext, C, T)
		end

		if #items == 0 then
			draw.SimpleText("no weapons in this group", fonts.label, MENU_W * 0.5, STAGE_Y + 100,
				T.muted or Color(200, 150, 165), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		else
			for i, entry in ipairs(slice) do
				local item = entry.item
				local r = cards[i]
				if not r then continue end
				local hot = Hit(mx, my, r.x, r.y, r.w, r.h)
				if hot then state.hoveredItem = entry.global end
				local isActive = activeClass and item.class == activeClass
				-- Hover scale (Alyx pop)
				local dx, dy, dw, dh = r.x, r.y, r.w, r.h
				if hot then
					local s = 1.04
					local nw, nh = dw * s, dh * s
					dx = dx - (nw - dw) * 0.5
					dy = dy - (nh - dh) * 0.5
					dw, dh = nw, nh
				end
				DrawWeaponCard(dx, dy, dw, dh, item, hot, isActive, ply, fonts, T, C)
			end

			-- Page dots under the fan (laser-readable)
			if pages > 1 then
				local dotR = 5
				local gap = 14
				local totalDots = pages * (dotR * 2) + (pages - 1) * gap
				local dx0 = (MENU_W - totalDots) * 0.5
				local dyDots = stageBottom - 18 - DOT_Y_OFF
				for p = 1, pages do
					local cx = dx0 + (p - 1) * (dotR * 2 + gap) + dotR
					local sel = p == state.page
					local col = sel and (T.crimsonHot or Color(255, 70, 100)) or (T.crimsonDim or Color(120, 20, 40))
					surface.SetDrawColor(col.r, col.g, col.b, sel and 255 or 160)
					-- filled disc via small rects (no circle helper guaranteed)
					local s = sel and (dotR + 1) or dotR
					surface.DrawRect(cx - s, dyDots - s, s * 2, s * 2)
				end
			end
		end

		-- ── Detail / action bar ───────────────────────────────────
		local dy = MENU_H - DETAIL_H - FOOTER_H + 4
		surface.SetDrawColor((T.bgGlass or Color(22, 10, 16)).r, (T.bgGlass or Color(22, 10, 16)).g, (T.bgGlass or Color(22, 10, 16)).b, 240)
		surface.DrawRect(0, dy, MENU_W, DETAIL_H)
		surface.SetDrawColor((T.crimson or Color(196, 30, 58)).r, (T.crimson or Color(196, 30, 58)).g, (T.crimson or Color(196, 30, 58)).b, 200)
		surface.DrawRect(0, dy, MENU_W, 2)

		local focusItem = state.hoveredItem > 0 and items[state.hoveredItem] or nil
		local title = "Point · release to equip"
		local sub = "grip to free-move panel"
		local clip, total, alt = -1, -1, -1
		if focusItem and IsValid(focusItem.wep) then
			title = focusItem.label or focusItem.class
			clip, total, alt = GetWeaponAmmo(focusItem.wep, ply)
			sub = "AMMO  " .. FormatAmmo(clip, total)
			if alt and alt > 0 then sub = sub .. "    ALT  " .. tostring(alt) end
		elseif state.hoveredPrev then
			title = "PREVIOUS"
			sub = string.format("page %d → %d", state.page, state.page - 1)
		elseif state.hoveredNext then
			title = "NEXT"
			sub = string.format("page %d → %d", state.page, state.page + 1)
		elseif state.hoveredHolster then
			title = "HOLSTER"
			sub = "stow active weapon"
		elseif #items > 0 then
			local slotId = slotOrder[state.catIndex]
			title = slotNames[slotId] or "WEAPONS"
			if pages > 1 then
				sub = string.format("%d ready · page %d / %d", #items, state.page, pages)
			else
				sub = string.format("%d ready", #items)
			end
		end

		draw.SimpleText(title, fonts.title, PAD + 4, dy + 12, T.crimson or Color(196, 30, 58), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		draw.SimpleText(sub, fonts.label, PAD + 4, dy + 36, T.muted or Color(200, 150, 165), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

		-- Holster chip (Alyx empty-hand)
		local hx = MENU_W - PAD - HOLSTER_W
		local hy = dy + (DETAIL_H - HOLSTER_H) * 0.5
		state.hoveredHolster = Hit(mx, my, hx, hy, HOLSTER_W, HOLSTER_H)
		if C and C.DrawSlot then
			C.DrawSlot(hx, hy, HOLSTER_W, HOLSTER_H, "HOLSTER", state.hoveredHolster, false, true)
		else
			surface.SetDrawColor(state.hoveredHolster and 100 or 55, 14, 24, 250)
			surface.DrawRect(hx, hy, HOLSTER_W, HOLSTER_H)
			draw.SimpleText("HOLSTER", fonts.small, hx + HOLSTER_W * 0.5, hy + HOLSTER_H * 0.5,
				color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		-- Laser cursor
		if mx >= 0 and my >= 0 then
			local hot = T.crimsonHot or Color(255, 70, 100)
			surface.SetDrawColor(0, 0, 0, 200)
			surface.DrawRect(mx - 2, my - 12, 4, 24)
			surface.DrawRect(mx - 12, my - 2, 24, 4)
			surface.SetDrawColor(hot.r, hot.g, hot.b, 255)
			surface.DrawRect(mx - 1, my - 10, 2, 20)
			surface.DrawRect(mx - 10, my - 1, 20, 2)
		end

		if C and C.DrawFooterLaw then
			C.DrawFooterLaw(0, MENU_H - 20, MENU_W, 2)
		end

		VRUtilMenuRenderEnd()
	end

	-- Click categories / page arrows while menu held open
	hook.Add("VRMod_Input", "vrmod_weaponmenu_nav", function(action, pressed)
		if not open then return end
		if not pressed then return end
		if not (vrmod.IsMenuPrimaryClick and vrmod.IsMenuPrimaryClick(action)) then return end
		if g_VR.menuFocus ~= "weaponmenu" then return end
		if state.hoveredCat > 0 then
			state.catIndex = state.hoveredCat
			state.hoveredItem = -1
			state.page = state.pageByCat[state.catIndex] or 1
			clampPage()
			return
		end
		if state.hoveredPrev then
			local pages = clampPage()
			if state.page > 1 then
				state.page = state.page - 1
				state.pageByCat[state.catIndex] = state.page
				state.hoveredItem = -1
			end
			return
		end
		if state.hoveredNext then
			local pages = clampPage()
			if state.page < pages then
				state.page = state.page + 1
				state.pageByCat[state.catIndex] = state.page
				state.hoveredItem = -1
			end
			return
		end
		if state.hoveredHolster then
			selectHolster = true
		end
	end)

	paint()

	hook.Add("PreRender", "vrutil_hook_renderweaponselect", function()
		if not open or not (g_VR.menus and g_VR.menus.weaponmenu) then
			open = false
			hook.Remove("PreRender", "vrutil_hook_renderweaponselect")
			hook.Remove("VRMod_Input", "vrmod_weaponmenu_nav")
			return
		end
		local menu = g_VR.menus.weaponmenu
		menu.cubeMenu = true
		menu.grabbable = true
		-- dirty only on hover change (set in paint path via MenuShouldRepaint cursor quantize)
		paint()
	end)
end

function VRUtilWeaponMenuClose()
	open = false
	hook.Remove("PreRender", "vrutil_hook_renderweaponselect")
	hook.Remove("VRMod_Input", "vrmod_weaponmenu_nav")
	if isfunction(VRUtilMenuClose) then
		VRUtilMenuClose("weaponmenu")
	end
end

hook.Add("VRMod_Exit", "vrmod_weaponmenu_exit", function()
	open = false
	hook.Remove("PreRender", "vrutil_hook_renderweaponselect")
	hook.Remove("VRMod_Input", "vrmod_weaponmenu_nav")
end)
