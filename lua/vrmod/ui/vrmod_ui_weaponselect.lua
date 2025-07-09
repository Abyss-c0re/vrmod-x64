-- VRMod Weapon Menu UI with Spawnmenu Icons via ContentIcon Cache
if SERVER then return end
local ICON_SIZE = 44
local iconMaterials = {}
local DEFAULT_ICON = Material("icon32/hand_point_090.png") -- fallback icon
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
	local model = wepDef and wepDef.WorldModel or MODEL_OVERRIDES[className]
	if not model then return DEFAULT_ICON end
	util.PrecacheModel(model)
	local rtName = "vrmod_rt_" .. className
	local rt = GetRenderTarget(rtName, ICON_SIZE, ICON_SIZE)
	if not rt then return DEFAULT_ICON end
	local panel = vgui.Create("DModelPanel")
	if not IsValid(panel) then return DEFAULT_ICON end
	panel:SetSize(ICON_SIZE, ICON_SIZE)
	panel:SetModel(model)
	panel:SetFOV(90)
	panel:SetAmbientLight(Color(255, 255, 0)) -- bright yellow ambient light
	panel:SetDirectionalLight(BOX_TOP, Color(255, 255, 255))
	panel:SetDirectionalLight(BOX_FRONT, Color(255, 255, 255))
	panel:SetDirectionalLight(BOX_BOTTOM, Color(255, 255, 255))
	panel:SetDirectionalLight(BOX_BACK, Color(255, 255, 255))
	panel:Hide()
	local ent = panel.Entity
	if not IsValid(ent) then
		panel:Remove()
		return DEFAULT_ICON
	end

	local mins, maxs = ent:GetRenderBounds()
	local center = (mins + maxs) * 0.5
	local size = maxs - mins
	local camPos = center + Vector(size:Length() * 0.4, size:Length() * 0.4, size:Length() * 0.4)
	render.PushRenderTarget(rt)
	cam.Start3D(camPos, (center - camPos):Angle(), 45, 0, 0, ICON_SIZE, ICON_SIZE)
	render.Clear(0, 0, 0, 0, true, true) -- clear with transparent black
	render.OverrideDepthEnable(true, false)
	ent:SetMaterial("models/wireframe") -- keep wireframe for visibility
	ent:DrawModel()
	--ent:SetMaterial("")
	render.OverrideDepthEnable(false)
	cam.End3D()
	render.PopRenderTarget()
	panel:Remove()
	local mat = CreateMaterial("vrmod_icon_mat_" .. className, "UnlitGeneric", {
		["$basetexture"] = rt:GetName(),
		["$color"] = "[1 1 0]",
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
		-- Update stats & hover indices (unchanged) …
		local values = {
			hoveredSlot = -1,
			hoveredItem = -1
		}

		values.health, values.suit = ply:Health(), ply:Armor()
		local aw = ply:GetActiveWeapon()
		if IsValid(aw) then
			values.clip, values.total, values.alt = aw:Clip1(), ply:GetAmmoCount(aw:GetPrimaryAmmoType()), ply:GetAmmoCount(aw:GetSecondaryAmmoType())
		else
			values.clip, values.total, values.alt = 0, 0, 0
		end

		local cx, cy = 256, 256
		local dx, dy = g_VR.menuCursorX - cx, g_VR.menuCursorY - cy
		local dist = math.sqrt(dx * dx + dy * dy)
		local angDeg = math.deg(math.atan2(dy, dx))
		if angDeg < 0 then angDeg = angDeg + 360 end
		local innerR, outerR = 50, 120
		-- Determine hoveredSlot
		if dist > 40 and dist < innerR + 20 then
			local seg = 360 / #slots
			local idx = math.floor(angDeg / seg) + 1
			if idx >= 1 and idx <= #slots then
				values.hoveredSlot = idx
				chosenSlot = idx
			end
		end

		-- Determine hoveredItem (petal) if a slot is chosen
		if chosenSlot then
			local sel = slots[chosenSlot]
			local n = #sel.items
			local totalArc = math.min(90, n * 20)
			local startAng = (chosenSlot - 1) * 360 / #slots - totalArc / 2
			for i, item in ipairs(sel.items) do
				local a = startAng + (n == 1 and 0 or (i - 1) * totalArc / (n - 1))
				local rad = math.rad(a)
				local rx, ry = cx + math.cos(rad) * outerR, cy + math.sin(rad) * outerR
				if math.sqrt((g_VR.menuCursorX - rx) ^ 2 + (g_VR.menuCursorY - ry) ^ 2) < 24 then values.hoveredItem = i end
			end
		end

		-- Only redraw on change
		local changed = false
		for k, v in pairs(values) do
			if prev[k] ~= v then
				changed = true
				break
			end
		end

		if not changed then return end
		prev = values
		VRUtilMenuRenderStart("weaponmenu")
		-- Draw outer & inner rings
		surface.SetDrawColor(0, 0, 0, 200)
		do
			local bg = {}
			for i = 0, 32 do
				local a = math.rad(i / 32 * 360)
				bg[#bg + 1] = {
					x = cx + math.cos(a) * (outerR + 20),
					y = cy + math.sin(a) * (outerR + 20)
				}
			end

			surface.DrawPoly(bg)
		end

		surface.SetDrawColor(0, 0, 0, 230)
		do
			local bg = {}
			for i = 0, 64 do
				local a = math.rad(i / 64 * 360)
				bg[#bg + 1] = {
					x = cx + math.cos(a) * innerR,
					y = cy + math.sin(a) * innerR
				}
			end

			surface.DrawPoly(bg)
		end

		-- Draw slot slices
		local sliceAngle = 360 / #slots
		for i, slot in ipairs(slots) do
			local startAng = (i - 1) * sliceAngle
			local endAng = i * sliceAngle
			local col = values.hoveredSlot == i and Color(255, 255, 0, 100) or Color(0, 0, 0, 150)
			drawSlice(cx, cy, innerR, innerR + 20, startAng, endAng, 64, col)
			-- label in the middle of the slice
			local midAng = (startAng + endAng) * 0.5
			local rad = math.rad(midAng)
			local lx, ly = cx + math.cos(rad) * (innerR + 10), cy + math.sin(rad) * (innerR + 10)
			local textCol = values.hoveredSlot == i and Color(255, 255, 0) or Color(255, 145, 0)
			draw.SimpleText(slotNames[slot.slot], "vrmod_font_mid", lx, ly, textCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		-- Draw petals/items if slot chosen (unchanged) …
		if chosenSlot then
			local sel = slots[chosenSlot]
			for i, item in ipairs(sel.items) do
				local mat = RenderWeaponToMaterial(item.class)
				local n = #sel.items
				local totalArc = math.min(90, n * 20)
				local startAng = (chosenSlot - 1) * 360 / #slots - totalArc / 2
				local a = startAng + (n == 1 and 0 or (i - 1) * totalArc / (n - 1))
				local rad = math.rad(a)
				local rx, ry = cx + math.cos(rad) * outerR, cy + math.sin(rad) * outerR
				-- petal highlight
				if values.hoveredItem == i then
					surface.SetDrawColor(255, 255, 255, 100)
					surface.DrawPoly{
						{
							x = rx - 20,
							y = ry - 20
						},
						{
							x = rx + 20,
							y = ry - 20
						},
						{
							x = rx + 20,
							y = ry + 20
						},
						{
							x = rx - 20,
							y = ry + 20
						},
					}
				end

				-- icon
				DrawIconLayered(rx, ry, ICON_SIZE, mat, 10, 0, 0)
			end
		end

		-- Center name & stats (unchanged) …
		local name = "Select Slot"
		if chosenSlot and prev.hoveredItem >= 1 then name = slots[chosenSlot].items[prev.hoveredItem].label end
		draw.SimpleText(name, "vrmod_font_normal", cx, cy, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		local function ds(x, w, label, val, col)
			draw.RoundedBox(6, x, 20, w, 45, Color(0, 0, 0, 128))
			draw.SimpleText(label, "vrmod_font_small", x + 10, 50, col)
			draw.SimpleText(val, "vrmod_font_mid", x + w - 10, 55, col, TEXT_ALIGN_RIGHT)
		end

		local ammoText = string.format("%d / %d", prev.clip, prev.total)
		local ammoColor = Color(255, prev.clip == 0 and prev.total == 0 and 0 or 250, 0, 255)
		ds(20, 120, "HEALTH", prev.health, Color(255, prev.health > 19 and 250 or 0, 0, 255))
		ds(160, 110, "SUIT", prev.suit, Color(255, 250, 0))
		ds(290, 130, "AMMO", ammoText, ammoColor)
		ds(440, 70, "ALT", prev.alt, Color(255, 250, 0))
		VRUtilMenuRenderEnd()
	end)
end

function VRUtilWeaponMenuClose()
	VRUtilMenuClose("weaponmenu")
end