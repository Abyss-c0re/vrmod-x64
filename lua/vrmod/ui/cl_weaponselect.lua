-- VRMod Weapon Menu UI with Spawnmenu Icons via ContentIcon Cache
-- Restored pre-Cube radial (512 / scale 0.025) + minimal nil-safe guards.
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

local rtCache = {} -- render targets per class
local wireMat = CreateMaterial("vrmod_wireframe_yellow", "Wireframe", {
	["$basetexture"] = "models/debug/debugwhite",
	["$color"] = "[3 3 0]"
})

-- Lazy ClientsideModel — can fail at file load on some maps
local tempEnt
local function EnsureTempEnt()
	if IsValid(tempEnt) then return true end
	tempEnt = ClientsideModel(DEFAULT_MODEL, RENDER_GROUP_OPAQUE_ENTITY)
	if not IsValid(tempEnt) then return false end
	tempEnt:SetNoDraw(true)
	return true
end

local function GetIconRT(className)
	if not rtCache[className] then rtCache[className] = GetRenderTarget("vrmod_rt_" .. className, ICON_SIZE, ICON_SIZE) end
	return rtCache[className]
end

function RenderWeaponToMaterial(className)
	if iconMaterials[className] then return iconMaterials[className] end
	local wepDef = weapons.GetStored(className)
	local worldMdl = wepDef and wepDef.WorldModel or ""
	if worldMdl:find("^models/weapons/c_") then
		worldMdl = ""
	end

	local overrides = vrmod.MODEL_OVERRIDES or {}
	local model = worldMdl ~= "" and worldMdl or overrides[className] or DEFAULT_MODEL
	util.PrecacheModel(model)
	local rt = GetIconRT(className)
	if not rt then return DEFAULT_ICON end
	if not EnsureTempEnt() then return DEFAULT_ICON end
	tempEnt:SetModel(model)
	local mins, maxs = tempEnt:GetRenderBounds()
	local center = (mins + maxs) * 0.5
	local size = maxs - mins
	local radius = size:Length() * 0.5
	local camPos = center + Vector(radius, radius, radius)
	local camAng = (center - camPos):Angle()
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
	local mat = CreateMaterial("vrmod_icon_mat_" .. className, "UnlitGeneric", {
		["$basetexture"] = rt:GetName(),
		["$color"] = "[10 10 0]",
		["$vertexcolor"] = 1,
		["$vertexalpha"] = 1,
		["$translucent"] = 1,
		["$nolod"] = 1,
	})

	iconMaterials[className] = mat
	return mat
end

local function drawSlice(cx, cy, innerR, outerR, startDeg, endDeg, segCount, col)
	local poly = {}
	for i = 0, segCount do
		local frac = i / segCount
		local ang = math.rad(startDeg + (endDeg - startDeg) * frac)
		poly[#poly + 1] = {
			x = cx + math.cos(ang) * outerR,
			y = cy + math.sin(ang) * outerR
		}
	end

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

local function DrawIconLayered(x, y, size, material, repeats, alphaStep, scaleStep)
	if not material then return end
	surface.SetMaterial(material)
	for i = 1, repeats do
		local scale = 1 + (i - 1) * scaleStep
		local alpha = 255 - (i - 1) * alphaStep
		surface.SetDrawColor(255, 255, 0, math.max(0, alpha))
		surface.DrawTexturedRect(x - (size * scale) / 2, y - (size * scale) / 2, size * scale, size * scale)
	end
end

local function GetWeaponAmmo(wep, ply)
	if not IsValid(wep) then return 0, 0, 0 end
	local clip = 0
	local total = 0
	local alt = 0
	if wep.Clip1 then clip = wep:Clip1() or 0 end
	local primaryType = wep.GetPrimaryAmmoType and wep:GetPrimaryAmmoType() or -1
	if primaryType and primaryType > 0 then total = ply:GetAmmoCount(primaryType) or 0 end
	local secondaryType = wep.GetSecondaryAmmoType and wep:GetSecondaryAmmoType() or -1
	if secondaryType and secondaryType > 0 then alt = ply:GetAmmoCount(secondaryType) or 0 end
	if wep.ArcticVR and clip <= 0 then clip = (wep.LoadedRounds or 0) + (wep.Chambered or 0) end
	if total <= 0 and wep.Primary and wep.Primary.Ammo then total = ply:GetAmmoCount(wep.Primary.Ammo) or 0 end
	return clip, total, alt
end

local open = false
function VRUtilWeaponMenuOpen()
	if open and not (g_VR.menus and g_VR.menus.weaponmenu) then open = false end
	if open then return end
	if not g_VR or not g_VR.active or not isfunction(VRUtilMenuOpen) then return end
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local hmd = g_VR.tracking and g_VR.tracking.hmd
	local rh = g_VR.tracking and g_VR.tracking.pose_righthand
	if not hmd or not hmd.ang or not rh or not rh.pos or not rh.ang then return end

	open = true
	local innerClick = false
	local flatItems = {}
	for _, wep in ipairs(ply:GetWeapons()) do
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

	-- Original placement
	local tmpAng = Angle(0, hmd.ang.yaw - 90, 60)
	local pos, ang = WorldToLocal(
		rh.pos + rh.ang:Forward() * 7 + tmpAng:Right() * -3.68 + tmpAng:Forward() * -5.45,
		tmpAng,
		g_VR.origin or Vector(),
		g_VR.originAngle or Angle()
	)
	VRUtilMenuOpen("weaponmenu", 512, 512, nil, false, pos, ang, 0.025, true, function()
		hook.Remove("PreRender", "vrutil_hook_renderweaponselect")
		open = false
		local p = LocalPlayer()
		if not IsValid(p) then return end
		if innerClick then
			local aw = p:GetActiveWeapon()
			local activeClass = IsValid(aw) and aw:GetClass() or nil
			if activeClass ~= "weapon_vrmod_empty" then
				lastWeaponClass = activeClass
				local emptyWep = p:GetWeapon("weapon_vrmod_empty")
				if IsValid(emptyWep) then input.SelectWeapon(emptyWep) end
			elseif activeClass == "weapon_vrmod_empty" and lastWeaponClass and lastWeaponClass ~= "weapon_vrmod_empty" then
				local prevWep = p:GetWeapon(lastWeaponClass)
				if IsValid(prevWep) then input.SelectWeapon(prevWep) end
			end
			return
		end

		local sel = slots[chosenSlot or prev.hoveredSlot]
		local chosen = sel and sel.items[prev.hoveredItem]
		if chosen and IsValid(chosen.wep) then input.SelectWeapon(chosen.wep) end
	end)

	if not (g_VR.menus and g_VR.menus.weaponmenu) then
		open = false
		return
	end

	-- Keep open-time scale; do not force attachment (opened with world/hand pos already set)
	g_VR.menus.weaponmenu.cubeMenu = true
	if g_VR.menus.weaponmenu.scale and g_VR.menus.weaponmenu.scale < 0.02 then
		g_VR.menus.weaponmenu.scale = 0.025
	end

	local CX, CY = 256, 256
	local INNER_R = 60
	local OUTER_R = 140
	local SLOT_MIN_DIST = 40
	local SLOT_MAX_DIST = INNER_R + 20
	local ICON_RADIUS_FACTOR = 0.9
	local PETAL_HOVER_RADIUS = ICON_SIZE * 0.75
	local SLICE_SEGMENTS = 64

	local function paintWeapon(values)
		if not isfunction(VRUtilMenuRenderStart) then return end
		VRUtilMenuRenderStart("weaponmenu")
		surface.SetDrawColor(0, 0, 0, 200)
		do
			local poly = {}
			for i = 0, 32 do
				local a = math.rad(i / 32 * 360)
				poly[#poly + 1] = {
					x = CX + math.cos(a) * (OUTER_R + 20),
					y = CY + math.sin(a) * (OUTER_R + 20)
				}
			end
			surface.DrawPoly(poly)
		end

		surface.SetDrawColor(0, 0, 0, 230)
		do
			local poly = {}
			for i = 0, 64 do
				local a = math.rad(i / 64 * 360)
				poly[#poly + 1] = {
					x = CX + math.cos(a) * INNER_R,
					y = CY + math.sin(a) * INNER_R
				}
			end
			surface.DrawPoly(poly)
		end

		if #slots > 0 then
			local sliceAngle = 360 / #slots
			for i, slot in ipairs(slots) do
				local sa, ea = (i - 1) * sliceAngle, i * sliceAngle
				local col = values.hoveredSlot == i and Color(0, 0, 0, 230) or Color(0, 0, 0, 200)
				drawSlice(CX, CY, INNER_R, INNER_R + 20, sa, ea, SLICE_SEGMENTS, col)
				local mid = (sa + ea) / 2
				local lx = CX + math.cos(math.rad(mid)) * (INNER_R + 10)
				local ly = CY + math.sin(math.rad(mid)) * (INNER_R + 10)
				local tcol = values.hoveredSlot == i and Color(255, 255, 255) or Color(255, 255, 0)
				draw.SimpleText(slotNames[slot.slot] or "?", "vrmod_font_mid", lx, ly, tcol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end

		if chosenSlot and slots[chosenSlot] then
			local sel = slots[chosenSlot]
			local itemCount = #sel.items
			local arc = math.min(90, itemCount * 20)
			local startAng = (chosenSlot - 1) * 360 / math.max(1, #slots) - arc / 2
			local iconR = OUTER_R * ICON_RADIUS_FACTOR
			for i, item in ipairs(sel.items) do
				local a = startAng + (itemCount == 1 and 0 or (i - 1) * arc / math.max(1, itemCount - 1))
				local rad = math.rad(a)
				local rx = CX + math.cos(rad) * iconR
				local ry = CY + math.sin(rad) * iconR
				DrawIconLayered(rx, ry, ICON_SIZE, RenderWeaponToMaterial(item.class), 10, 0, 0.01)
			end
		end

		local name = "Select Slot"
		if chosenSlot and values.hoveredItem >= 1 and slots[chosenSlot] and slots[chosenSlot].items[values.hoveredItem] then
			name = slots[chosenSlot].items[values.hoveredItem].label
		elseif values.hoveredSlot >= 1 and slots[values.hoveredSlot] then
			name = slotNames[slots[values.hoveredSlot].slot] or name
		end

		draw.SimpleText(name, "vrmod_font_normal", CX, CY, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		local function ds(x, w, label, val, col)
			draw.RoundedBox(6, x, 20, w, 45, Color(0, 0, 0, 128))
			draw.SimpleText(label, "vrmod_font_small", x + 10, 50, col)
			draw.SimpleText(val, "vrmod_font_mid", x + w - 10, 55, col, TEXT_ALIGN_RIGHT)
		end

		local ammoText = string.format("%d / %d", values.clip or 0, values.total or 0)
		local ammoCol = Color(255, (values.clip == 0 and values.total == 0) and 0 or 250, 0, 255)
		ds(20, 120, "HEALTH", values.health, Color(255, (values.health or 0) > 19 and 250 or 0, 0, 255))
		ds(160, 110, "SUIT", values.suit, Color(255, 250, 0))
		ds(290, 130, "AMMO", ammoText, ammoCol)
		ds(440, 70, "ALT", values.alt, Color(255, 250, 0))
		VRUtilMenuRenderEnd()
	end

	-- Immediate paint so RT is never blank before laser focus
	do
		local seed = {
			hoveredSlot = -1, hoveredItem = -1,
			health = IsValid(ply) and ply:Health() or 0,
			suit = IsValid(ply) and ply:Armor() or 0,
			clip = 0, total = 0, alt = 0,
		}
		if IsValid(ply) then
			seed.clip, seed.total, seed.alt = GetWeaponAmmo(ply:GetActiveWeapon(), ply)
		end
		paintWeapon(seed)
		prev = seed
	end

	hook.Add("PreRender", "vrutil_hook_renderweaponselect", function()
		if not open or not (g_VR.menus and g_VR.menus.weaponmenu) then
			open = false
			hook.Remove("PreRender", "vrutil_hook_renderweaponselect")
			return
		end

		local values = {
			hoveredSlot = prev.hoveredSlot or -1,
			hoveredItem = prev.hoveredItem or -1
		}

		if IsValid(ply) then
			values.health, values.suit = ply:Health(), ply:Armor()
			values.clip, values.total, values.alt = GetWeaponAmmo(ply:GetActiveWeapon(), ply)
		else
			values.health, values.suit, values.clip, values.total, values.alt = 0, 0, 0, 0, 0
		end

		-- Ray-test only when focused; still always paint while open
		if g_VR.menuFocus == "weaponmenu" and #slots > 0 then
			values.hoveredSlot, values.hoveredItem = -1, -1
			local dx, dy = (g_VR.menuCursorX or 0) - CX, (g_VR.menuCursorY or 0) - CY
			local dist = math.sqrt(dx * dx + dy * dy)
			local angDeg = math.deg(math.atan2(dy, dx))
			if angDeg < 0 then angDeg = angDeg + 360 end

			if dist > SLOT_MIN_DIST and dist < SLOT_MAX_DIST then
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
				local arc = math.min(90, itemCount * 20)
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
		end

		prev = values
		-- ALWAYS paint while open (blank RT = unsummonable menu)
		paintWeapon(values)
	end)
end

function VRUtilWeaponMenuClose()
	open = false
	hook.Remove("PreRender", "vrutil_hook_renderweaponselect")
	if isfunction(VRUtilMenuClose) then
		VRUtilMenuClose("weaponmenu")
	end
end

hook.Add("VRMod_Exit", "vrmod_weaponmenu_exit", function()
	open = false
	hook.Remove("PreRender", "vrutil_hook_renderweaponselect")
end)
