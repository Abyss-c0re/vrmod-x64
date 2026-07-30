-- VRMod Weapon Menu UI with Spawnmenu Icons via ContentIcon Cache
if SERVER then return end
local lastWeaponClass = nil
local ICON_SIZE = 44
local iconMaterials = {}
local DEFAULT_ICON = Material("icon32/hand_point_090.png")
local DEFAULT_MODEL = "models/dav0r/hoverball.mdl"
-- Slot names mapping
local slotNames = {
	[0] = "Melee",
	[1] = "Sidearm",
	[2] = "Primary",
	[3] = "Rifle",
	[4] = "Explosive",
	[5] = "Tools",
	[6] = "Other"
}

-- Fonts
local defFont = "Trebuchet24"
surface.CreateFont("vrmod_font_normal", {
	font = defFont,
	size = 20,
	antialias = true
})

surface.CreateFont("vrmod_font_mid", {
	font = defFont,
	size = 16,
	weight = 600,
	antialias = true
})

surface.CreateFont("vrmod_font_small", {
	font = defFont,
	size = 12,
	antialias = true
})

local iconMaterials = {} -- final UnlitGenerics
local rtCache = {} -- render targets per class
local wireMat = CreateMaterial("vrmod_wireframe_yellow", "Wireframe", {
	["$basetexture"] = "models/debug/debugwhite",
	["$color"] = "[3 3 0]"
})

-- Single reusable ent
local tempEnt = ClientsideModel(DEFAULT_MODEL, RENDER_GROUP_OPAQUE_ENTITY)
tempEnt:SetNoDraw(true)
-- Helper to get (or create) an RT
local function GetIconRT(className)
	if not rtCache[className] then rtCache[className] = GetRenderTarget("vrmod_rt_" .. className, ICON_SIZE, ICON_SIZE) end
	return rtCache[className]
end

function RenderWeaponToMaterial(className)
	-- 1) Return cached final material
	if iconMaterials[className] then return iconMaterials[className] end
	-- 2) Pick a valid world model
	local wepDef = weapons.GetStored(className)
	local worldMdl = wepDef and wepDef.WorldModel or ""
	if worldMdl:find("^models/weapons/c_") then
		worldMdl = "" -- reject any c_ viewmodel
	end

	local model = worldMdl ~= "" and worldMdl or vrmod.MODEL_OVERRIDES[className] or DEFAULT_MODEL
	-- 3) Ensure model is loaded
	util.PrecacheModel(model)
	-- 4) Grab (or create) our RT
	local rt = GetIconRT(className)
	if not rt then return DEFAULT_ICON end
	-- 5) Reuse our temporary entity
	tempEnt:SetModel(model)
	local mins, maxs = tempEnt:GetRenderBounds()
	local center = (mins + maxs) * 0.5
	local size = maxs - mins
	local radius = size:Length() * 0.5
	local camPos = center + Vector(radius, radius, radius)
	local camAng = (center - camPos):Angle()
	-- 6) Render into the RT
	render.PushRenderTarget(rt)
	render.Clear(0, 0, 0, 0, true, true)
	cam.Start3D(camPos, camAng, 35, 0, 0, ICON_SIZE, ICON_SIZE)
	render.SuppressEngineLighting(true)
	render.SetColorModulation(3, 3, 0)
	render.SetBlend(1)
	render.MaterialOverride(wireMat)
	tempEnt:DrawModel()
	render.MaterialOverride(nil)
	render.SetColorModulation(1, 1, 1)
	render.SuppressEngineLighting(false)
	cam.End3D()
	render.PopRenderTarget()
	-- 7) Create and cache the final UnlitGeneric
	local mat = CreateMaterial("vrmod_icon_mat_" .. className, "UnlitGeneric", {
		["$basetexture"] = rt:GetName(),
		["$vertexcolor"] = 1,
		["$vertexalpha"] = 1
	})

	iconMaterials[className] = mat
	return mat
end

local function drawSlice(cx, cy, innerR, outerR, startDeg, endDeg, segCount, col)
	local poly = {}
	-- Outer arc points
	for i = 0, segCount do
		local frac = i / segCount
		local ang = math.rad(startDeg + (endDeg - startDeg) * frac)
		poly[#poly + 1] = {
			x = cx + math.cos(ang) * outerR,
			y = cy + math.sin(ang) * outerR
		}
	end

	-- Inner arc points (in reverse)
	for i = segCount, 0, -1 do
		local frac = i / segCount
		local ang = math.rad(startDeg + (endDeg - startDeg) * frac)
		poly[#poly + 1] = {
			x = cx + math.cos(ang) * innerR,
			y = cy + math.sin(ang) * innerR
		}
	end

	surface.SetDrawColor(col)
	surface.DrawPoly(poly)
end

local function DrawIconLayered(x, y, size, material, hovered)
	surface.SetMaterial(material)
	if hovered then
		surface.SetDrawColor(255, 90, 110, 255)
	else
		surface.SetDrawColor(255, 200, 210, 230)
	end
	surface.DrawTexturedRect(x - size / 2, y - size / 2, size, size)
end

-- =============================================
-- SMART AMMO GETTER (only ArcticVR uses custom count)
-- =============================================
local function GetWeaponAmmo(wep, ply)
	if not IsValid(wep) then return 0, 0, 0 end
	local clip = 0
	local total = 0
	local alt = 0
	-- Standard methods first
	if wep.Clip1 then clip = wep:Clip1() or 0 end
	local primaryType = wep.GetPrimaryAmmoType and wep:GetPrimaryAmmoType() or -1
	if primaryType and primaryType > 0 then total = ply:GetAmmoCount(primaryType) or 0 end
	local secondaryType = wep.GetSecondaryAmmoType and wep:GetSecondaryAmmoType() or -1
	if secondaryType and secondaryType > 0 then alt = ply:GetAmmoCount(secondaryType) or 0 end
	-- === ONLY FOR ARCTICVR WEAPONS ===
	if wep.ArcticVR and clip <= 0 then clip = (wep.LoadedRounds or 0) + (wep.Chambered or 0) end
	-- Fallback for total if still zero
	if total <= 0 and wep.Primary and wep.Primary.Ammo then total = ply:GetAmmoCount(wep.Primary.Ammo) or 0 end
	return clip, total, alt
end

-- Main menu open
local open = false
function VRUtilWeaponMenuOpen()
	if open then return end
	open = true
	local innerClick = false
	-- Collect & sort weapons
	local flatItems = {}
	for _, wep in ipairs(LocalPlayer():GetWeapons()) do
		flatItems[#flatItems + 1] = {
			wep = wep,
			class = wep:GetClass(),
			label = wep:GetPrintName(),
			slot = wep:GetSlot(),
			slotPos = wep:GetSlotPos()
		}
	end

	table.sort(flatItems, function(a, b)
		if a.slot ~= b.slot then return a.slot < b.slot end
		return a.slotPos < b.slotPos
	end)

	-- Group by slot
	local slotList = {}
	for _, item in ipairs(flatItems) do
		slotList[item.slot] = slotList[item.slot] or {
			slot = item.slot,
			items = {}
		}

		slotList[item.slot].items[#slotList[item.slot].items + 1] = item
	end

	local slots = {}
	for _, data in pairs(slotList) do
		slots[#slots + 1] = data
	end

	table.sort(slots, function(a, b) return a.slot < b.slot end)
	-- Tracking state
	local chosenSlot
	local prev = {
		hoveredSlot = -1,
		hoveredItem = -1,
		health = -1,
		suit = -1,
		clip = -1,
		total = -1,
		alt = -1
	}

	local ply = LocalPlayer()
	-- Position VR panel
	-- Cube weapon radial — right-hand side, large, crimson
	local W, H = 640, 640
	local menuScale = 0.036
	local tmpAng = Angle(0, g_VR.tracking.hmd.ang.yaw - 90, 55)
	local worldPos = g_VR.tracking.pose_righthand.pos
		+ g_VR.tracking.pose_righthand.ang:Forward() * 9
		+ tmpAng:Right() * -5
		+ tmpAng:Forward() * -4
	local pos, ang = WorldToLocal(worldPos, tmpAng, g_VR.origin, g_VR.originAngle)
	VRUtilMenuOpen("weaponmenu", W, H, nil, false, pos, ang, menuScale, true, function()
		hook.Remove("PreRender", "vrutil_hook_renderweaponselect")
		open = false
		local ply = LocalPlayer()
		if innerClick then
			local aw = ply:GetActiveWeapon()
			local activeClass = IsValid(aw) and aw:GetClass() or nil
			if activeClass ~= "weapon_vrmod_empty" then
				lastWeaponClass = activeClass
				local emptyWep = ply:GetWeapon("weapon_vrmod_empty")
				if IsValid(emptyWep) then input.SelectWeapon(emptyWep) end
			elseif activeClass == "weapon_vrmod_empty" and lastWeaponClass and lastWeaponClass ~= "weapon_vrmod_empty" then
				local prevWep = ply:GetWeapon(lastWeaponClass)
				if IsValid(prevWep) then input.SelectWeapon(prevWep) end
			end
			return
		end

		local sel = slots[chosenSlot or prev.hoveredSlot]
		local chosen = sel and sel.items[prev.hoveredItem]
		if chosen and IsValid(chosen.wep) then input.SelectWeapon(chosen.wep) end
	end)

	if g_VR.menus and g_VR.menus.weaponmenu then
		g_VR.menus.weaponmenu.scale = menuScale
		g_VR.menus.weaponmenu.cubeMenu = true
	end

	hook.Add("PreRender", "vrutil_hook_renderweaponselect", function()
		if g_VR.menuFocus ~= "weaponmenu" then return end
		if g_VR.menus and g_VR.menus.weaponmenu then
			g_VR.menus.weaponmenu.scale = menuScale
		end

		local CX, CY = W * 0.5, H * 0.5
		local INNER_R = 78
		local OUTER_R = 185
		local SLOT_MIN_DIST = 50
		local SLOT_MAX_DIST = INNER_R + 28
		local ICON_RADIUS_FACTOR = 0.88
		local PETAL_HOVER_RADIUS = ICON_SIZE * 0.9
		local SLICE_SEGMENTS = 48
		local T = vrmod.cube and vrmod.cube.Theme or {
			bg = Color(12, 6, 10, 245),
			crimson = Color(196, 30, 58),
			crimsonHot = Color(255, 70, 100),
			btn = Color(55, 14, 24),
			text = color_white,
			muted = Color(200, 160, 170),
		}

		local values = {
			hoveredSlot = -1,
			hoveredItem = -1
		}

		values.health, values.suit = ply:Health(), ply:Armor()
		local aw = ply:GetActiveWeapon()
		values.clip, values.total, values.alt = GetWeaponAmmo(aw, ply)
		local dx, dy = (g_VR.menuCursorX or 0) - CX, (g_VR.menuCursorY or 0) - CY
		local dist = math.sqrt(dx * dx + dy * dy)
		local angDeg = math.deg(math.atan2(dy, dx))
		if angDeg < 0 then angDeg = angDeg + 360 end

		if #slots > 0 and dist > SLOT_MIN_DIST and dist < SLOT_MAX_DIST then
			local segSize = 360 / #slots
			local idx = math.floor(angDeg / segSize) + 1
			if idx >= 1 and idx <= #slots then
				values.hoveredSlot = idx
				chosenSlot = idx
			end
		end

		innerClick = dist <= INNER_R
		if chosenSlot and slots[chosenSlot] then
			local sel = slots[chosenSlot]
			local itemCount = #sel.items
			local arc = math.min(100, itemCount * 22)
			local startAngle = (chosenSlot - 1) * 360 / #slots - arc / 2
			local iconR = OUTER_R * ICON_RADIUS_FACTOR
			local hoverR2 = PETAL_HOVER_RADIUS * PETAL_HOVER_RADIUS
			for i, item in ipairs(sel.items) do
				local a = startAngle + (itemCount == 1 and 0 or (i - 1) * arc / math.max(1, itemCount - 1))
				local rad = math.rad(a)
				local rx = CX + math.cos(rad) * iconR
				local ry = CY + math.sin(rad) * iconR
				local ddx = (g_VR.menuCursorX or 0) - rx
				local ddy = (g_VR.menuCursorY or 0) - ry
				if ddx * ddx + ddy * ddy <= hoverR2 then
					values.hoveredItem = i
					break
				end
			end
		end

		local dirty = false
		for k, v in pairs(values) do
			if prev[k] ~= v then dirty = true break end
		end
		if not dirty then
			-- still update stats sometimes
			if prev.health == values.health and prev.clip == values.clip then return end
		end
		prev.hoveredSlot = values.hoveredSlot
		prev.hoveredItem = values.hoveredItem
		prev.health, prev.suit = values.health, values.suit
		prev.clip, prev.total, prev.alt = values.clip, values.total, values.alt

		VRUtilMenuRenderStart("weaponmenu")
		-- void
		surface.SetDrawColor(T.bg)
		surface.DrawRect(0, 0, W, H)

		draw.NoTexture()
		-- outer disc
		surface.SetDrawColor(22, 10, 16, 240)
		local polyOut = {}
		for i = 0, 48 do
			local a = math.rad(i / 48 * 360)
			polyOut[#polyOut + 1] = { x = CX + math.cos(a) * (OUTER_R + 28), y = CY + math.sin(a) * (OUTER_R + 28) }
		end
		surface.DrawPoly(polyOut)

		-- crimson ring outline
		surface.SetDrawColor(T.crimson)
		for i = 0, 63 do
			local a0 = math.rad(i / 64 * 360)
			local a1 = math.rad((i + 1) / 64 * 360)
			local r = OUTER_R + 28
			surface.DrawLine(CX + math.cos(a0) * r, CY + math.sin(a0) * r, CX + math.cos(a1) * r, CY + math.sin(a1) * r)
		end

		-- center core
		surface.SetDrawColor(18, 8, 12, 250)
		local polyIn = {}
		for i = 0, 48 do
			local a = math.rad(i / 48 * 360)
			polyIn[#polyIn + 1] = { x = CX + math.cos(a) * INNER_R, y = CY + math.sin(a) * INNER_R }
		end
		surface.DrawPoly(polyIn)
		surface.SetDrawColor(innerClick and T.crimsonHot or T.crimson)
		surface.DrawOutlinedRect(CX - 8, CY - 8, 16, 16) -- cube glyph core

		-- slot ring
		if #slots > 0 then
			local sliceAngle = 360 / #slots
			for i, slot in ipairs(slots) do
				local sa, ea = (i - 1) * sliceAngle, i * sliceAngle
				local col = values.hoveredSlot == i and Color(120, 25, 45, 250) or Color(50, 12, 22, 230)
				drawSlice(CX, CY, INNER_R, INNER_R + 26, sa, ea, SLICE_SEGMENTS, col)
				local mid = (sa + ea) / 2
				local lx = CX + math.cos(math.rad(mid)) * (INNER_R + 13)
				local ly = CY + math.sin(math.rad(mid)) * (INNER_R + 13)
				local tcol = values.hoveredSlot == i and T.crimsonHot or T.muted
				draw.SimpleText(slotNames[slot.slot] or "?", "CubeSmall", lx, ly, tcol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end

		-- petals
		if chosenSlot and slots[chosenSlot] then
			local sel = slots[chosenSlot]
			local itemCount = #sel.items
			local arc = math.min(100, itemCount * 22)
			local startAng = (chosenSlot - 1) * 360 / #slots - arc / 2
			local iconR = OUTER_R * ICON_RADIUS_FACTOR
			for i, item in ipairs(sel.items) do
				local a = startAng + (itemCount == 1 and 0 or (i - 1) * arc / math.max(1, itemCount - 1))
				local rad = math.rad(a)
				local rx = CX + math.cos(rad) * iconR
				local ry = CY + math.sin(rad) * iconR
				local hovered = values.hoveredItem == i
				if hovered then
					surface.SetDrawColor(T.crimson)
					surface.DrawOutlinedRect(rx - ICON_SIZE * 0.55, ry - ICON_SIZE * 0.55, ICON_SIZE * 1.1, ICON_SIZE * 1.1, 2)
				end
				local mat = RenderWeaponToMaterial(item.class)
				DrawIconLayered(rx, ry, ICON_SIZE, mat, hovered)
			end
		end

		local name = "CUBE · arms"
		if chosenSlot and prev.hoveredItem >= 1 and slots[chosenSlot] and slots[chosenSlot].items[prev.hoveredItem] then
			name = slots[chosenSlot].items[prev.hoveredItem].label
		elseif values.hoveredSlot >= 1 and slots[values.hoveredSlot] then
			name = slotNames[slots[values.hoveredSlot].slot] or name
		elseif innerClick then
			name = "empty hands"
		end
		draw.SimpleText(name, "CubeLabel", CX, CY - 4, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

		local function ds(x, w, label, val, col)
			surface.SetDrawColor(T.btn)
			surface.DrawRect(x, 16, w, 52)
			surface.SetDrawColor(T.crimsonDim or T.crimson)
			surface.DrawOutlinedRect(x, 16, w, 52)
			draw.SimpleText(label, "CubeSmall", x + 12, 24, T.muted)
			draw.SimpleText(tostring(val), "CubeLabel", x + w - 12, 40, col or T.text, TEXT_ALIGN_RIGHT)
		end

		local ammoText = string.format("%d / %d", prev.clip, prev.total)
		local ammoCol = (prev.clip == 0 and prev.total == 0) and T.crimsonHot or T.text
		ds(24, 140, "HEALTH", prev.health, prev.health > 19 and T.ok or T.crimsonHot)
		ds(180, 120, "SUIT", prev.suit, T.warn or T.muted)
		ds(316, 150, "AMMO", ammoText, ammoCol)
		ds(480, 90, "ALT", prev.alt, T.muted)

		draw.SimpleText("point · release to select", "CubeSmall", CX, H - 24, T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		VRUtilMenuRenderEnd()
	end)
end

function VRUtilWeaponMenuClose()
	VRUtilMenuClose("weaponmenu")
end