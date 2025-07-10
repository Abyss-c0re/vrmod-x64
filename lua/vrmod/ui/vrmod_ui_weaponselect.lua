-- VRMod Weapon Menu UI with Spawnmenu Icons via ContentIcon Cache
if SERVER then return end
local ICON_SIZE = 44
local iconMaterials = {}
local DEFAULT_ICON = Material("icon32/hand_point_090.png")
local DEFAULT_MODEL = "models/dav0r/hoverball.mdl"
local MODEL_OVERRIDES = {
	weapon_physgun = "models/weapons/w_physics.mdl",
	weapon_physcannon = "models/weapons/w_physics.mdl",
}

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
local defFont = "vrmod_Trebuchet24"
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

function RenderWeaponToMaterial(className)
	if iconMaterials[className] then return iconMaterials[className] end
	local wepDef = weapons.GetStored(className)
	local worldMdl = wepDef and wepDef.WorldModel
	-- only accept it if it’s non‑nil *and* non‑empty
	local model = worldMdl and worldMdl ~= "" and worldMdl or MODEL_OVERRIDES[className] or DEFAULT_MODEL
	util.PrecacheModel(model)
	local rtName = "vrmod_rt_" .. className
	local rt = GetRenderTarget(rtName, ICON_SIZE, ICON_SIZE)
	if not rt then return DEFAULT_ICON end
	local ent = ClientsideModel(model, RENDER_GROUP_OPAQUE_ENTITY)
	if not IsValid(ent) then return DEFAULT_ICON end
	ent:SetNoDraw(true)
	local mins, maxs = ent:GetRenderBounds()
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
	local wireMat = CreateMaterial("vrmod_wireframe_yellow", "Wireframe", {
		["$basetexture"] = "models/debug/debugwhite",
		["$color"] = "[3 3 0]"
	})

	render.MaterialOverride(wireMat)
	ent:DrawModel()
	render.MaterialOverride(nil)
	render.SetColorModulation(1, 1, 1)
	render.SuppressEngineLighting(false)
	cam.End3D()
	render.PopRenderTarget()
	ent:Remove()
	local mat = CreateMaterial("vrmod_icon_mat_" .. className, "UnlitGeneric", {
		["$basetexture"] = rt:GetName(),
		["$color"] = "[10 10 0]",
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

local function DrawIconLayered(x, y, size, material, repeats, alphaStep, scaleStep)
	surface.SetMaterial(material)
	for i = 1, repeats do
		local scale = 1 + (i - 1) * scaleStep
		local alpha = 255 - (i - 1) * alphaStep
		surface.SetDrawColor(255, 255, 0, math.max(0, alpha))
		surface.DrawTexturedRect(x - (size * scale) / 2, y - (size * scale) / 2, size * scale, size * scale)
	end
end

-- Main menu open
local open = false
function VRUtilWeaponMenuOpen()
	if open then return end
	open = true
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
	local tmpAng = Angle(0, g_VR.tracking.hmd.ang.yaw - 90, 60)
	local pos, ang = WorldToLocal(g_VR.tracking.pose_righthand.pos + g_VR.tracking.pose_righthand.ang:Forward() * 7 + tmpAng:Right() * -3.68 + tmpAng:Forward() * -5.45, tmpAng, g_VR.origin, g_VR.originAngle)
	VRUtilMenuOpen("weaponmenu", 512, 512, nil, false, pos, ang, 0.025, true, function()
		hook.Remove("PreRender", "vrutil_hook_renderweaponselect")
		open = false
		local sel = slots[chosenSlot or prev.hoveredSlot]
		local chosen = sel and sel.items[prev.hoveredItem]
		if chosen and IsValid(chosen.wep) then input.SelectWeapon(chosen.wep) end
	end)

	hook.Add("PreRender", "vrutil_hook_renderweaponselect", function()
		if g_VR.menuFocus ~= "weaponmenu" then return end
		-- ─── Tunable parameters ───────────────────────────────────────
		local CX, CY = 256, 256 -- center of menu
		local INNER_R = 60 -- inner ring radius
		local OUTER_R = 140 -- outer ring radius
		local SLOT_MIN_DIST = 40 -- dist > this to hover a slot
		local SLOT_MAX_DIST = INNER_R + 20 -- dist < this to hover a slot
		local ICON_RADIUS_FACTOR = 0.9 -- iconR = OUTER_R * this
		local PETAL_HOVER_RADIUS = ICON_SIZE * 0.75 -- for center‑text update only
		local SLICE_SEGMENTS = 64 -- resolution of slice polygons
		-- ──────────────────────────────────────────────────────────────
		-- 1) Gather player stats
		local values = {
			hoveredSlot = -1,
			hoveredItem = -1
		}

		values.health, values.suit = ply:Health(), ply:Armor()
		do
			local aw = ply:GetActiveWeapon()
			if IsValid(aw) then
				values.clip, values.total, values.alt = aw:Clip1(), ply:GetAmmoCount(aw:GetPrimaryAmmoType()), ply:GetAmmoCount(aw:GetSecondaryAmmoType())
			else
				values.clip, values.total, values.alt = 0, 0, 0
			end
		end

		-- 2) Cursor polar coords
		local dx, dy = g_VR.menuCursorX - CX, g_VR.menuCursorY - CY
		local dist2 = dx * dx + dy * dy
		local dist = math.sqrt(dist2)
		local angDeg = math.deg(math.atan2(dy, dx))
		if angDeg < 0 then angDeg = angDeg + 360 end
		-- 3) Slot hover detection
		if dist > SLOT_MIN_DIST and dist < SLOT_MAX_DIST then
			local segSize = 360 / #slots
			local idx = math.floor(angDeg / segSize) + 1
			if idx >= 1 and idx <= #slots then
				values.hoveredSlot = idx
				chosenSlot = idx
			end
		end

		-- 4) Petal hover detection (for center‑text only)
		if chosenSlot then
			local sel = slots[chosenSlot]
			local itemCount = #sel.items
			local arc = math.min(90, itemCount * 20)
			local startAngle = (chosenSlot - 1) * 360 / #slots - arc / 2
			local iconR = OUTER_R * ICON_RADIUS_FACTOR
			local hoverR2 = PETAL_HOVER_RADIUS * PETAL_HOVER_RADIUS
			for i, item in ipairs(sel.items) do
				local a = startAngle + (itemCount == 1 and 0 or (i - 1) * arc / (itemCount - 1))
				local rad = math.rad(a)
				local rx = CX + math.cos(rad) * iconR
				local ry = CY + math.sin(rad) * iconR
				local ddx = g_VR.menuCursorX - rx
				local ddy = g_VR.menuCursorY - ry
				if ddx * ddx + ddy * ddy <= hoverR2 then
					values.hoveredItem = i
					break
				end
			end
		end

		-- 5) Only redraw on change
		local dirty = false
		for k, v in pairs(values) do
			if prev[k] ~= v then
				dirty = true
				break
			end
		end

		if not dirty then return end
		prev = values
		-- 6) Draw everything
		VRUtilMenuRenderStart("weaponmenu")
		-- Outer ring
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

		-- Inner ring
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

		-- Slots
		local sliceAngle = 360 / #slots
		for i, slot in ipairs(slots) do
			local sa, ea = (i - 1) * sliceAngle, i * sliceAngle
			local col = values.hoveredSlot == i and Color(0, 0, 0, 230) or Color(0, 0, 0, 200)
			drawSlice(CX, CY, INNER_R, INNER_R + 20, sa, ea, SLICE_SEGMENTS, col)
			local mid = (sa + ea) / 2
			local lx = CX + math.cos(math.rad(mid)) * (INNER_R + 10)
			local ly = CY + math.sin(math.rad(mid)) * (INNER_R + 10)
			local tcol = values.hoveredSlot == i and Color(255, 255, 255) or Color(255, 255, 0)
			draw.SimpleText(slotNames[slot.slot], "vrmod_font_mid", lx, ly, tcol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		-- Petal icons (no highlight)
		if chosenSlot then
			local sel = slots[chosenSlot]
			local itemCount = #sel.items
			local arc = math.min(90, itemCount * 20)
			local startAng = (chosenSlot - 1) * 360 / #slots - arc / 2
			local iconR = OUTER_R * ICON_RADIUS_FACTOR
			for i, item in ipairs(sel.items) do
				local a = startAng + (itemCount == 1 and 0 or (i - 1) * arc / (itemCount - 1))
				local rad = math.rad(a)
				local rx = CX + math.cos(rad) * iconR
				local ry = CY + math.sin(rad) * iconR
				local mat = RenderWeaponToMaterial(item.class)
				DrawIconLayered(rx, ry, ICON_SIZE, mat, 10, 0, 0.01)
			end
		end

		-- Center name & stats (text changes only)
		local name = "Select Slot"
		if chosenSlot and prev.hoveredItem >= 1 then
			name = slots[chosenSlot].items[prev.hoveredItem].label
		elseif values.hoveredSlot >= 1 then
			name = slotNames[slots[values.hoveredSlot].slot]
		end

		draw.SimpleText(name, "vrmod_font_normal", CX, CY, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		local function ds(x, w, label, val, col)
			draw.RoundedBox(6, x, 20, w, 45, Color(0, 0, 0, 128))
			draw.SimpleText(label, "vrmod_font_small", x + 10, 50, col)
			draw.SimpleText(val, "vrmod_font_mid", x + w - 10, 55, col, TEXT_ALIGN_RIGHT)
		end

		local ammoText = string.format("%d / %d", prev.clip, prev.total)
		local ammoCol = Color(255, prev.clip == 0 and prev.total == 0 and 0 or 250, 0, 255)
		ds(20, 120, "HEALTH", prev.health, Color(255, prev.health > 19 and 250 or 0, 0, 255))
		ds(160, 110, "SUIT", prev.suit, Color(255, 250, 0))
		ds(290, 130, "AMMO", ammoText, ammoCol)
		ds(440, 70, "ALT", prev.alt, Color(255, 250, 0))
		VRUtilMenuRenderEnd()
	end)
end

function VRUtilWeaponMenuClose()
	VRUtilMenuClose("weaponmenu")
end