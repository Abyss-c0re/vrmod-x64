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
-- Engine fonts only — never unregistered Cube* names
local F_LABEL = "DermaDefaultBold"
local F_SMALL = "DermaDefault"
local F_MID = "DermaDefaultBold"

function VRUtilWeaponMenuOpen()
	if open then return end
	if not g_VR or not g_VR.active then return end
	if not isfunction(VRUtilMenuOpen) then return end

	open = true
	local innerClick = false
	local flatItems = {}
	local ply = LocalPlayer()
	if not IsValid(ply) then
		open = false
		return
	end

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
		slotList[item.slot] = slotList[item.slot] or { slot = item.slot, items = {} }
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

	local W, H = 640, 640
	local menuScale = 0.036
	local CX, CY = W * 0.5, H * 0.5
	local INNER_R, OUTER_R = 78, 185

	-- Safe pose (nil tracking used to crash open → open stuck true)
	local hmd = g_VR.tracking and g_VR.tracking.hmd
	local rh = g_VR.tracking and g_VR.tracking.pose_righthand
	local yaw = (hmd and hmd.ang and hmd.ang.yaw) or 0
	local tmpAng = Angle(0, yaw - 90, 55)
	local handPos = (rh and rh.pos) or (hmd and hmd.pos) or Vector()
	local handAng = (rh and rh.ang) or Angle(0, yaw, 0)
	local worldPos = handPos + handAng:Forward() * 9 + tmpAng:Right() * -5 + tmpAng:Forward() * -4
	local origin = g_VR.origin or Vector()
	local originAng = g_VR.originAngle or Angle()
	local pos, ang = WorldToLocal(worldPos, tmpAng, origin, originAng)

	local function paintMenu(values)
		pcall(function()
			VRUtilMenuRenderStart("weaponmenu")
			surface.SetDrawColor(12, 6, 10, 250)
			surface.DrawRect(0, 0, W, H)

			-- rings (rect-based, no DrawPoly dependency)
			surface.SetDrawColor(22, 10, 16, 240)
			surface.DrawRect(CX - OUTER_R - 20, CY - OUTER_R - 20, (OUTER_R + 20) * 2, (OUTER_R + 20) * 2)
			surface.SetDrawColor(196, 30, 58, 255)
			surface.DrawOutlinedRect(CX - OUTER_R - 20, CY - OUTER_R - 20, (OUTER_R + 20) * 2, (OUTER_R + 20) * 2)

			surface.SetDrawColor(18, 8, 12, 250)
			surface.DrawRect(CX - INNER_R, CY - INNER_R, INNER_R * 2, INNER_R * 2)
			surface.SetDrawColor(values.innerClick and 255 or 196, values.innerClick and 70 or 30, values.innerClick and 100 or 58, 255)
			surface.DrawOutlinedRect(CX - 10, CY - 10, 20, 20)

			if #slots > 0 then
				local sliceAngle = 360 / #slots
				for i, slot in ipairs(slots) do
					local sa, ea = (i - 1) * sliceAngle, i * sliceAngle
					local col = values.hoveredSlot == i and Color(120, 25, 45, 250) or Color(50, 12, 22, 230)
					draw.NoTexture()
					drawSlice(CX, CY, INNER_R, INNER_R + 26, sa, ea, 32, col)
					local mid = (sa + ea) / 2
					local lx = CX + math.cos(math.rad(mid)) * (INNER_R + 13)
					local ly = CY + math.sin(math.rad(mid)) * (INNER_R + 13)
					local tcol = values.hoveredSlot == i and Color(255, 70, 100) or Color(200, 150, 165)
					draw.SimpleText(slotNames[slot.slot] or "?", F_SMALL, lx, ly, tcol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
			end

			if chosenSlot and slots[chosenSlot] then
				local sel = slots[chosenSlot]
				local itemCount = #sel.items
				local arc = math.min(100, itemCount * 22)
				local startAng = (chosenSlot - 1) * 360 / math.max(1, #slots) - arc / 2
				local iconR = OUTER_R * 0.88
				for i, item in ipairs(sel.items) do
					local a = startAng + (itemCount == 1 and 0 or (i - 1) * arc / math.max(1, itemCount - 1))
					local rad = math.rad(a)
					local rx = CX + math.cos(rad) * iconR
					local ry = CY + math.sin(rad) * iconR
					local hovered = values.hoveredItem == i
					if hovered then
						surface.SetDrawColor(255, 70, 100, 255)
						surface.DrawOutlinedRect(rx - ICON_SIZE * 0.55, ry - ICON_SIZE * 0.55, ICON_SIZE * 1.1, ICON_SIZE * 1.1)
					end
					local mat = RenderWeaponToMaterial(item.class)
					if mat then DrawIconLayered(rx, ry, ICON_SIZE, mat, hovered) end
				end
			end

			local name = "CUBE · arms"
			if chosenSlot and values.hoveredItem >= 1 and slots[chosenSlot] and slots[chosenSlot].items[values.hoveredItem] then
				name = slots[chosenSlot].items[values.hoveredItem].label
			elseif values.hoveredSlot >= 1 and slots[values.hoveredSlot] then
				name = slotNames[slots[values.hoveredSlot].slot] or name
			elseif values.innerClick then
				name = "empty hands"
			end
			draw.SimpleText(name, F_LABEL, CX, CY - 4, Color(255, 240, 244), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

			local function ds(x, ww, label, val, col)
				surface.SetDrawColor(55, 14, 24, 250)
				surface.DrawRect(x, 16, ww, 52)
				surface.SetDrawColor(196, 30, 58, 200)
				surface.DrawOutlinedRect(x, 16, ww, 52)
				draw.SimpleText(label, F_SMALL, x + 12, 24, Color(200, 150, 165))
				draw.SimpleText(tostring(val), F_LABEL, x + ww - 12, 40, col or color_white, TEXT_ALIGN_RIGHT)
			end
			local ammoText = string.format("%d / %d", values.clip or 0, values.total or 0)
			ds(24, 140, "HEALTH", values.health or 0, (values.health or 0) > 19 and Color(90, 220, 150) or Color(255, 70, 100))
			ds(180, 120, "SUIT", values.suit or 0, Color(255, 200, 100))
			ds(316, 150, "AMMO", ammoText, color_white)
			ds(480, 90, "ALT", values.alt or 0, Color(200, 150, 165))
			draw.SimpleText("point · release to select", F_SMALL, CX, H - 24, Color(200, 150, 165), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			VRUtilMenuRenderEnd()
		end)
	end

	local okOpen = pcall(function()
		VRUtilMenuOpen("weaponmenu", W, H, nil, false, pos, ang, menuScale, true, function()
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
	end)

	if not okOpen or not (g_VR.menus and g_VR.menus.weaponmenu) then
		open = false
		return
	end
	g_VR.menus.weaponmenu.scale = menuScale
	g_VR.menus.weaponmenu.cubeMenu = true

	-- Paint immediately so RT is never invisible transparent
	paintMenu({
		hoveredSlot = -1, hoveredItem = -1, innerClick = false,
		health = ply:Health(), suit = ply:Armor(),
		clip = 0, total = 0, alt = 0,
	})

	hook.Add("PreRender", "vrutil_hook_renderweaponselect", function()
		if not open then return end
		if not g_VR.menus or not g_VR.menus.weaponmenu then
			open = false
			hook.Remove("PreRender", "vrutil_hook_renderweaponselect")
			return
		end
		g_VR.menus.weaponmenu.scale = menuScale

		local values = { hoveredSlot = -1, hoveredItem = -1, innerClick = false }
		local p = LocalPlayer()
		if IsValid(p) then
			values.health, values.suit = p:Health(), p:Armor()
			values.clip, values.total, values.alt = GetWeaponAmmo(p:GetActiveWeapon(), p)
		else
			values.health, values.suit, values.clip, values.total, values.alt = 0, 0, 0, 0, 0
		end

		-- Only ray-test when focused; still paint always
		if g_VR.menuFocus == "weaponmenu" then
			local dx = (g_VR.menuCursorX or 0) - CX
			local dy = (g_VR.menuCursorY or 0) - CY
			local dist = math.sqrt(dx * dx + dy * dy)
			local angDeg = math.deg(math.atan2(dy, dx))
			if angDeg < 0 then angDeg = angDeg + 360 end
			local SLOT_MIN, SLOT_MAX = 50, INNER_R + 28
			if #slots > 0 and dist > SLOT_MIN and dist < SLOT_MAX then
				local idx = math.floor(angDeg / (360 / #slots)) + 1
				if idx >= 1 and idx <= #slots then
					values.hoveredSlot = idx
					chosenSlot = idx
				end
			end
			values.innerClick = dist <= INNER_R
			innerClick = values.innerClick
			if chosenSlot and slots[chosenSlot] then
				local sel = slots[chosenSlot]
				local itemCount = #sel.items
				local arc = math.min(100, itemCount * 22)
				local startAngle = (chosenSlot - 1) * 360 / math.max(1, #slots) - arc / 2
				local iconR = OUTER_R * 0.88
				local hoverR2 = (ICON_SIZE * 0.9) ^ 2
				for i = 1, itemCount do
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

		prev.hoveredSlot = values.hoveredSlot
		prev.hoveredItem = values.hoveredItem
		prev.health, prev.suit = values.health, values.suit
		prev.clip, prev.total, prev.alt = values.clip, values.total, values.alt
		paintMenu(values)
	end)
end

function VRUtilWeaponMenuClose()
	open = false
	hook.Remove("PreRender", "vrutil_hook_renderweaponselect")
	if isfunction(VRUtilMenuClose) then
		VRUtilMenuClose("weaponmenu")
	end
end

concommand.Add("vrmod_weaponmenu", function()
	if g_VR and g_VR.active then VRUtilWeaponMenuOpen() end
end)

hook.Add("VRMod_Exit", "vrmod_weaponmenu_exit", function()
	open = false
	hook.Remove("PreRender", "vrutil_hook_renderweaponselect")
end)