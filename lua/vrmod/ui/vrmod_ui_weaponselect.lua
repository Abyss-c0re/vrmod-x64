if SERVER then return end
surface.CreateFont(
	"vrmod_font_normal",
	{
		font = "Px IBM BIOS",
		extended = false,
		size = 16,
		weight = 0,
		blursize = 0,
		scanlines = 0,
		antialias = true,
	}
)


surface.CreateFont(
	"vrmod_font_mid",
	{
		font = "Px IBM BIOS",
		size = 13,
		weight = 600,
		antialias = true,
	}
)

surface.CreateFont(
	"vrmod_font_small",
	{
		font = "Px IBM BIOS",
		extended = false,
		size = 7,
		weight = 0,
		blursize = 0,
		scanlines = 0,
		antialias = true,
	}
)


local open = false
function VRUtilWeaponMenuOpen()
	if open then return end
	open = true
	--
	local items = {}

	for k, v in pairs(LocalPlayer():GetWeapons()) do
		local slot, slotPos = v:GetSlot(), v:GetSlotPos()
		local index = #items + 1
		for i = 1, #items do
			if items[i].slot > slot or items[i].slot == slot and items[i].slotPos > slotPos then
				index = i
				break
			end
		end

		table.insert(
			items,
			index,
			{
				title = v:GetPrintName(),
				label = v:GetPrintName(),
				font = "vrmod_font_small",
				wep = v,
				slot = slot,
				slotPos = slotPos
			}
		)
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
	local prevValues = {
		hoveredItem = -1,
		health = -1,
		suit = -1,
		clip = -1,
		total = -1,
		alt = -1
	}

	local ply = LocalPlayer()
	local renderCount = 0
	local _, convarValues = vrmod.GetConvars()
	local tmp = Angle(0, g_VR.tracking.hmd.ang.yaw - 90, 45) --Forward() = right, Right() = back, Up() = up (relative to panel, panel forward is looking at top of panel from middle of panel, up is normal)
	local pos, ang = WorldToLocal(g_VR.tracking.pose_righthand.pos + tmp:Forward() * -9 + tmp:Right() * -11 + tmp:Up() * -7, tmp, g_VR.origin, g_VR.originAngle)
	--uid, width, height, panel, attachment, pos, ang, scale, cursorEnabled, closeFunc
	local mode = convarValues.vrmod_attach_weaponmenu
	if mode == 1 then
		VRUtilMenuOpen(
			"weaponmenu",
			512,
			512,
			nil,
			1,
			Vector(4, 6, 15.5),
			Angle(0, -90, 60),
			0.03,
			true,
			function()
				hook.Remove("PreRender", "vrutil_hook_renderweaponselect")
				open = false
				if items[prevValues.hoveredItem] and IsValid(items[prevValues.hoveredItem].wep) then
					input.SelectWeapon(items[prevValues.hoveredItem].wep)
				end
			end
		)
		--
	elseif mode == 3 then
		--forw, left, up
		VRUtilMenuOpen(
			"weaponmenu",
			512,
			512,
			nil,
			3,
			Vector(35, 20, 10),
			Angle(0, -90, 90),
			0.03,
			true,
			function()
				hook.Remove("PreRender", "vrutil_hook_renderweaponselect")
				open = false
				if items[prevValues.hoveredItem] and IsValid(items[prevValues.hoveredItem].wep) then
					input.SelectWeapon(items[prevValues.hoveredItem].wep)
				end
			end
		)
	elseif mode == 2 then
		--forw, left, up
		VRUtilMenuOpen(
			"weaponmenu",
			512,
			512,
			nil,
			2,
			Vector(13, 6, 10.5),
			Angle(0, -90, 90),
			0.03,
			true,
			function()
				hook.Remove("PreRender", "vrutil_hook_renderweaponselect")
				open = false
				if items[prevValues.hoveredItem] and IsValid(items[prevValues.hoveredItem].wep) then
					input.SelectWeapon(items[prevValues.hoveredItem].wep)
				end
			end
		)

	else --
		VRUtilMenuOpen(
			"weaponmenu",
			512,
			512,
			nil,
			mode,
			pos,
			ang,
			0.03,
			true,
			function()
				hook.Remove("PreRender", "vrutil_hook_renderweaponselect")
				open = false
				if items[prevValues.hoveredItem] and IsValid(items[prevValues.hoveredItem].wep) then
					input.SelectWeapon(items[prevValues.hoveredItem].wep)
				end
			end
		)
	end

	hook.Add(
		"PreRender",
		"vrutil_hook_renderweaponselect",
		function()
			local values = {}
			values.hoveredItem = -1
			local hoveredSlot, hoveredSlotPos = -1, -1
			if g_VR.menuFocus == "weaponmenu" then
				hoveredSlot, hoveredSlotPos = math.floor(g_VR.menuCursorX / 86), math.floor((g_VR.menuCursorY - 114) / 57)
			end

			for i = 1, #items do
				if items[i].slot == hoveredSlot and items[i].actualSlotPos == hoveredSlotPos then
					values.hoveredItem = i
					break
				end
			end

			values.health, values.suit = ply:Health(), ply:Armor()
			values.clip, values.total, values.alt = 0, 0, 0
			local wep = ply:GetActiveWeapon()
			if IsValid(wep) then
				values.clip, values.total, values.alt = wep:Clip1(), ply:GetAmmoCount(wep:GetPrimaryAmmoType()), ply:GetAmmoCount(wep:GetSecondaryAmmoType())
			end

			local changes = false
			for k, v in pairs(values) do
				if v ~= prevValues[k] then
					changes = true
					break
				end
			end

			prevValues = values
			if not changes then return end
			VRUtilMenuRenderStart("weaponmenu")
			--debug rendercount
			--renderCount = renderCount + 1
			--draw.SimpleText( renderCount, "HudSelectionText", 0, 512, Color( 255, 250, 0, 255 ), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM )
			--health
			draw.RoundedBox(8, 0, 0, 145, 53, Color(0, 0, 0, 128))
			draw.SimpleText("HEALTH", "vrmod_font_small", 10, 45, Color(255, values.health > 19 and 250 or 0, 0, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
			draw.SimpleText(values.health, "vrmod_font_mid", 140, 50, Color(255, values.health > 19 and 250 or 0, 0, 255), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
			--suit
			draw.RoundedBox(8, 149, 0, 130, 53, Color(0, 0, 0, 128))
			draw.SimpleText("SUIT", "vrmod_font_small", 165, 45, Color(255, 250, 0, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
			draw.SimpleText(values.suit, "vrmod_font_mid", 270, 50, Color(255, 250, 0, 255), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
			--ammo
			draw.RoundedBox(8, 283, 0, 150, 53, Color(0, 0, 0, 128))
			draw.SimpleText("AMMO", "vrmod_font_small", 290, 45, Color(255, values.clip == 0 and 0 or 250, 0, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
			draw.SimpleText(values.clip, "vrmod_font_mid", 338, 50, Color(255, values.clip == 0 and 0 or 250, 0, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
			draw.SimpleText(values.total, "vrmod_font_mid", 429, 47, Color(255, values.clip == 0 and 0 or 250, 0, 255), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
			draw.RoundedBox(8, 437, 0, 75, 53, Color(0, 0, 0, 128))
			draw.SimpleText("ALT", "vrmod_font_small", 440, 45, Color(255, 250, 0, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
			draw.SimpleText(values.alt, "vrmod_font_mid", 512, 50, Color(255, 250, 0, 255), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
			--hovered item name
			draw.RoundedBox(8, 0, 57, 512, 53, Color(0, 0, 0, 128))
			draw.SimpleText(items[values.hoveredItem] and items[values.hoveredItem].title or "", "vrmod_font_mid", 256, 85, Color(255, 250, 0, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			--weapon list/buttons
			local buttonWidth, buttonHeight = 82, 53
			local gap = (512 - buttonWidth * 6) / 5
			for i = 1, #items do
				local x, y = items[i].slot, items[i].actualSlotPos
				draw.RoundedBox(8, x * (buttonWidth + gap), 114 + y * (buttonHeight + gap), buttonWidth, buttonHeight, Color(0, 0, 0, values.hoveredItem == i and 200 or 128))
				local explosion = string.Explode(" ", items[i].label, false)
				for j = 1, #explosion do
					draw.SimpleText(explosion[j], items[i].font, buttonWidth / 2 + x * (buttonWidth + gap), 114 + buttonHeight / 2 + y * (buttonHeight + gap) - (#explosion * 6 - 6 - (j - 1) * 12), Color(255, 250, 0, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
			end

			VRUtilMenuRenderEnd()
		end
	)
end

function VRUtilWeaponMenuClose()
	VRUtilMenuClose("weaponmenu")
end