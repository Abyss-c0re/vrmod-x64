if SERVER then return end
-- =============================================================================
-- Cube VR Weapon Settings — per-weapon hold pose / laser / muzzle / world model
--
-- True VR menu: hand-attached 3D2D surface, laser + trigger hit boxes.
-- Edits g_VR.viewModelInfo[class] live and persists data/vrmod/vrmod_weapons_config.json
-- Desktop users keep Derma via vrmod_weaponconfig → CreateWeaponConfigGUI.
-- =============================================================================

vrmod = vrmod or {}

local UID = "weapon_settings"
local open = false
local buttons = {}
local statusMsg = ""
local statusUntil = 0
local stepFine = false -- false = coarse 1.0 / 5°, true = fine 0.1 / 1°
local W, H = 520, 620
local livePos, liveAng, liveScale = Vector(2.5, 3, 4), Angle(0, -90, 55), 0.026
local HEADER, PAD = 52, 12

local function Theme()
	if vrmod.cube and vrmod.cube.ThemeLive then
		local T = vrmod.cube.ThemeLive()
		if not T.rowOn then T.rowOn = T.rowHot or T.btnHover end
		return T
	end
	return {
		bg = Color(12, 6, 10, 250),
		header = Color(196, 30, 58, 255),
		headerDim = Color(70, 14, 24, 255),
		row = Color(40, 14, 20, 245),
		rowHot = Color(95, 24, 38, 255),
		rowOn = Color(120, 30, 48, 255),
		text = Color(255, 240, 244, 255),
		muted = Color(200, 150, 165, 230),
		hot = Color(255, 70, 100, 255),
		ok = Color(90, 220, 150, 255),
		off = Color(70, 20, 30, 255),
		btn = Color(55, 14, 24, 250),
		btnHover = Color(100, 22, 38, 255),
	}
end

local function Font(name)
	if vrmod.cube and vrmod.cube.Font then return vrmod.cube.Font(name) end
	-- Offline fallback when cube fonts not loaded
	if name == "title" or name == "CubeTitle" then return "DermaLarge" end
	if name == "label" or name == "CubeLabel" then return "DermaDefaultBold" end
	if name == "small" or name == "CubeSmall" then return "DermaDefault" end
	return "DermaDefault"
end

local function WristHand()
	return (vrmod.GetSecondaryHand and vrmod.GetSecondaryHand()) or "left"
end

local function WristPose()
	local wrist = WristHand()
	if isfunction(VRUtilHandMenuPose) then
		return VRUtilHandMenuPose(W, H, 0.026, Vector(2.5, 3.5, 4), Angle(0, -90, 55), wrist)
	end
	return Vector(2.5, 3, 4), Angle(0, -90, 55), 0.026
end

local function ActiveClass()
	local wep = LocalPlayer():GetActiveWeapon()
	if IsValid(wep) then return wep:GetClass() end
	return nil
end

local function Entry()
	local class = ActiveClass()
	if not class then return nil, nil end
	if vrmod.EnsureWeaponViewModelEntry then
		return class, vrmod.EnsureWeaponViewModelEntry(class)
	end
	g_VR.viewModelInfo = g_VR.viewModelInfo or {}
	g_VR.viewModelInfo[class] = g_VR.viewModelInfo[class] or {
		offsetPos = Vector(),
		offsetAng = Angle(),
	}
	return class, g_VR.viewModelInfo[class]
end

local function LiveApply(class)
	if vrmod.ApplyWeaponViewModelLive then
		vrmod.ApplyWeaponViewModelLive(class)
	end
end

local function SaveAll()
	if vrmod.SaveWeaponViewModelConfig then
		vrmod.SaveWeaponViewModelConfig()
	end
end

local function SetStatus(msg, sec)
	statusMsg = tostring(msg or "")
	statusUntil = CurTime() + (sec or 2)
end

local function PosStep()
	return stepFine and 0.25 or 1.0
end

local function AngStep()
	return stepFine and 1 or 5
end

local function NudgePos(axis, sign)
	local class, d = Entry()
	if not class or not d then
		SetStatus("No weapon", 1.5)
		return
	end
	d.offsetPos = d.offsetPos or Vector()
	local p = d.offsetPos
	local s = PosStep() * (sign or 1)
	if axis == "x" then p.x = p.x + s
	elseif axis == "y" then p.y = p.y + s
	else p.z = p.z + s end
	d.offsetPos = Vector(p.x, p.y, p.z)
	if vrmod.SetViewModelOffsetForWeaponClass then
		vrmod.SetViewModelOffsetForWeaponClass(class, d.offsetPos, d.offsetAng or Angle())
	end
	LiveApply(class)
end

local function NudgeAng(axis, sign)
	local class, d = Entry()
	if not class or not d then
		SetStatus("No weapon", 1.5)
		return
	end
	d.offsetAng = d.offsetAng or Angle()
	local a = d.offsetAng
	local s = AngStep() * (sign or 1)
	if axis == "p" then a.p = a.p + s
	elseif axis == "y" then a.y = a.y + s
	else a.r = a.r + s end
	d.offsetAng = Angle(a.p, a.y, a.r)
	if vrmod.SetViewModelOffsetForWeaponClass then
		vrmod.SetViewModelOffsetForWeaponClass(class, d.offsetPos or Vector(), d.offsetAng)
	end
	LiveApply(class)
end

local function ToggleFlag(key, api)
	local class, d = Entry()
	if not class or not d then
		SetStatus("No weapon", 1.5)
		return
	end
	d[key] = not d[key]
	if api then api(class, d[key]) end
	LiveApply(class)
	SaveAll()
	SetStatus((d[key] and "ON" or "OFF") .. " " .. key, 1.2)
end

local function ResetThisWeapon()
	local class = ActiveClass()
	if not class then return end
	g_VR.viewModelInfo[class] = {
		offsetPos = Vector(0, 0, 0),
		offsetAng = Angle(0, 0, 0),
		wrongMuzzleAng = false,
		noLaser = false,
		useWorldModel = false,
	}
	if vrmod.SetViewModelOffsetForWeaponClass then
		vrmod.SetViewModelOffsetForWeaponClass(class, Vector(), Angle())
	end
	if vrmod.SetViewModelFixMuzzle then vrmod.SetViewModelFixMuzzle(class, false) end
	if vrmod.SetViewModelNoLaser then vrmod.SetViewModelNoLaser(class, false) end
	if vrmod.SetViewModelUseWorldModel then vrmod.SetViewModelUseWorldModel(class, false) end
	LiveApply(class)
	SaveAll()
	SetStatus("Reset " .. class, 2)
end

local function CaptureFromHand()
	-- Zero offsets so gun sits at hand pose (good base for non-VR weapons)
	local class, d = Entry()
	if not class or not d then return end
	d.offsetPos = Vector(0, 0, 0)
	d.offsetAng = Angle(0, 0, 0)
	if vrmod.SetViewModelOffsetForWeaponClass then
		vrmod.SetViewModelOffsetForWeaponClass(class, d.offsetPos, d.offsetAng)
	end
	LiveApply(class)
	SaveAll()
	SetStatus("Hand base (0,0,0)", 1.5)
end

------------------------------------------------------------------------
-- Hit UI
------------------------------------------------------------------------
local function hit(bx, by, bw, bh, mx, my)
	return mx >= bx and mx <= bx + bw and my >= by and my <= by + bh
end

local function rebuildButtons()
	buttons = {}
	local y = HEADER + 8
	local class, d = Entry()
	local T = Theme()

	-- Close
	buttons[#buttons + 1] = {
		id = "close", x = W - 48, y = 8, w = 40, h = 36,
		label = "X", action = function() vrmod.WeaponSettings_Close() end,
	}

	-- Step fine/coarse
	buttons[#buttons + 1] = {
		id = "step", x = PAD, y = y, w = 140, h = 36,
		label = stepFine and "Step: FINE" or "Step: COARSE",
		toggle = true, on = stepFine,
		action = function()
			stepFine = not stepFine
			SetStatus(stepFine and "Fine 0.25u / 1°" or "Coarse 1u / 5°", 1)
		end,
	}
	buttons[#buttons + 1] = {
		id = "save", x = PAD + 150, y = y, w = 100, h = 36,
		label = "SAVE", action = function()
			SaveAll()
			SetStatus("Saved", 1.5)
		end,
	}
	buttons[#buttons + 1] = {
		id = "reset", x = PAD + 260, y = y, w = 100, h = 36,
		label = "RESET", action = ResetThisWeapon,
	}
	buttons[#buttons + 1] = {
		id = "hand0", x = PAD + 370, y = y, w = 130, h = 36,
		label = "HAND BASE", action = CaptureFromHand,
	}

	y = y + 48
	-- Position rows
	local axes = {
		{ key = "x", label = "POS X (fwd)", get = function()
			local _, e = Entry()
			return e and e.offsetPos and e.offsetPos.x or 0
		end, nudge = function(s) NudgePos("x", s) end },
		{ key = "y", label = "POS Y (right)", get = function()
			local _, e = Entry()
			return e and e.offsetPos and e.offsetPos.y or 0
		end, nudge = function(s) NudgePos("y", s) end },
		{ key = "z", label = "POS Z (up)", get = function()
			local _, e = Entry()
			return e and e.offsetPos and e.offsetPos.z or 0
		end, nudge = function(s) NudgePos("z", s) end },
		{ key = "p", label = "ANG PITCH", get = function()
			local _, e = Entry()
			return e and e.offsetAng and e.offsetAng.p or 0
		end, nudge = function(s) NudgeAng("p", s) end },
		{ key = "a", label = "ANG YAW", get = function()
			local _, e = Entry()
			return e and e.offsetAng and e.offsetAng.y or 0
		end, nudge = function(s) NudgeAng("y", s) end },
		{ key = "r", label = "ANG ROLL", get = function()
			local _, e = Entry()
			return e and e.offsetAng and e.offsetAng.r or 0
		end, nudge = function(s) NudgeAng("r", s) end },
	}

	for _, ax in ipairs(axes) do
		buttons[#buttons + 1] = {
			id = "m" .. ax.key, x = PAD, y = y, w = 56, h = 40,
			label = "−", action = function() ax.nudge(-1) end,
		}
		buttons[#buttons + 1] = {
			id = "p" .. ax.key, x = W - PAD - 56, y = y, w = 56, h = 40,
			label = "+", action = function() ax.nudge(1) end,
		}
		ax._y = y
		ax._row = true
		y = y + 46
	end
	-- stash for paint value display
	buttons._axes = axes

	y = y + 8
	local tw = math.floor((W - PAD * 2 - 16) / 3)
	local toggles = {
		{ id = "laser", label = "LASER", get = function()
			local _, e = Entry()
			return e and not e.noLaser
		end, action = function()
			ToggleFlag("noLaser", vrmod.SetViewModelNoLaser)
		end },
		{ id = "muzzle", label = "FIX MUZ", get = function()
			local _, e = Entry()
			return e and e.wrongMuzzleAng
		end, action = function()
			ToggleFlag("wrongMuzzleAng", vrmod.SetViewModelFixMuzzle)
		end },
		{ id = "world", label = "WORLD MD", get = function()
			local _, e = Entry()
			return e and e.useWorldModel
		end, action = function()
			ToggleFlag("useWorldModel", vrmod.SetViewModelUseWorldModel)
		end },
	}
	for i, tg in ipairs(toggles) do
		local x = PAD + (i - 1) * (tw + 8)
		buttons[#buttons + 1] = {
			id = tg.id, x = x, y = y, w = tw, h = 44,
			label = tg.label, toggle = true, getOn = tg.get, action = tg.action,
		}
	end
end

local function paint()
	if not open or not isfunction(VRUtilMenuRenderStart) then return end
	if not (g_VR.menus and g_VR.menus[UID]) then return end

	local m = g_VR.menus[UID]
	if vrmod.MenuApplyHandAnchor then
		vrmod.MenuApplyHandAnchor(m, liveScale, livePos, liveAng, WristHand())
	elseif not m.freeFloat and not m.grabHand then
		if not m.scaleLocked then m.scale = liveScale end
		m.pos, m.ang = livePos, liveAng
		m.cubeMenu, m.attachment, m.attachHand = true, true, WristHand()
	end

	rebuildButtons()
	local T = Theme()
	local mx = g_VR.menuCursorX or -1
	local my = g_VR.menuCursorY or -1
	local focused = g_VR.menuFocus == UID
	local class = ActiveClass() or "(no weapon)"
	local _, d = Entry()

	if VRUtilMenuRenderStart(UID) == false then return end

	-- Chrome
	if vrmod.cube and vrmod.cube.DrawChrome then
		vrmod.cube.DrawChrome(0, 0, W, H, "WEAPON VR", { close = false })
	else
		surface.SetDrawColor(T.bg)
		surface.DrawRect(0, 0, W, H)
		surface.SetDrawColor(T.headerDim)
		surface.DrawRect(0, 0, W, HEADER)
		surface.SetDrawColor(T.header)
		surface.DrawRect(0, HEADER - 3, W, 3)
		draw.SimpleText("WEAPON VR", Font("title"), PAD, 14, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	end

	draw.SimpleText(class, Font("label") or "DermaDefault", PAD, HEADER - 18, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

	-- Axis value labels (center of nudge rows)
	if buttons._axes then
		for _, ax in ipairs(buttons._axes) do
			local val = ax.get()
			local y = ax._y
			surface.SetDrawColor(T.row or T.btn)
			surface.DrawRect(PAD + 64, y, W - PAD * 2 - 128, 40)
			draw.SimpleText(ax.label, "DermaDefault", W * 0.5, y + 8, T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			draw.SimpleText(string.format("%.2f", val), Font("label") or "DermaDefaultBold", W * 0.5, y + 22, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		end
	end

	-- Buttons
	for _, b in ipairs(buttons) do
		if not b.x then continue end
		local hovered = focused and hit(b.x, b.y, b.w, b.h, mx, my)
		local on = b.getOn and b.getOn() or b.on
		if vrmod.cube and vrmod.cube.DrawSlot then
			vrmod.cube.DrawSlot(b.x, b.y, b.w, b.h, b.label, hovered, on, true)
		else
			local col = hovered and (T.btnHover or T.rowHot) or (on and (T.rowOn or T.ok) or (T.btn or T.row))
			if b.id == "close" then col = hovered and T.hot or (T.header or col) end
			surface.SetDrawColor(col)
			surface.DrawRect(b.x, b.y, b.w, b.h)
			draw.SimpleText(b.label, "DermaDefaultBold", b.x + b.w * 0.5, b.y + b.h * 0.5, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end

	-- Footer
	local fy = H - 36
	surface.SetDrawColor(T.headerDim or T.row)
	surface.DrawRect(0, fy, W, 36)
	local foot = "trigger: select · grip: move panel · corner: scale"
	if statusUntil > CurTime() and statusMsg ~= "" then
		foot = statusMsg
	elseif d then
		foot = string.format("pos %s  ang %s", tostring(d.offsetPos), tostring(d.offsetAng))
	end
	draw.SimpleText(foot, "DermaDefault", PAD, fy + 10, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

	-- Laser cursor
	if focused and mx >= 0 and my >= 0 then
		surface.SetDrawColor(T.hot or Color(255, 80, 110))
		surface.DrawRect(mx - 2, my - 14, 4, 28)
		surface.DrawRect(mx - 14, my - 2, 28, 4)
	end

	if isfunction(VRUtilMenuRenderEnd) then VRUtilMenuRenderEnd() end
end

------------------------------------------------------------------------
-- Open / close
------------------------------------------------------------------------
function vrmod.WeaponSettings_IsOpen()
	return open
end

function vrmod.WeaponSettings_Close()
	if not open then return end
	open = false
	SaveAll()
	hook.Remove("PreRender", "weapon_settings_paint")
	hook.Remove("VRMod_Input", "weapon_settings_input")
	hook.Remove("VRMod_Exit", "weapon_settings_exit")
	hook.Remove("VRMod_OpenQuickMenu", "weapon_settings_qm")
	if g_VR and g_VR.menus and g_VR.menus[UID] then
		g_VR.menus[UID].closeFunc = nil
	end
	if isfunction(VRUtilMenuClose) then VRUtilMenuClose(UID) end
end

function vrmod.WeaponSettings_Open()
	if not (g_VR and g_VR.active) then
		if vrmod.logger then vrmod.logger.Warn("[WeaponSettings] not in VR") end
		return
	end
	if open then
		vrmod.WeaponSettings_Close()
		return
	end
	if not isfunction(VRUtilMenuOpen) then return end

	-- Close competing hand menus
	if g_VR.menus then
		for _, uid in ipairs({ "miscmenu", "cube_settings", "avatar_menu", "cubeui_main", "heightmenu" }) do
			if g_VR.menus[uid] and isfunction(VRUtilMenuClose) then
				g_VR.menus[uid].closeFunc = nil
				VRUtilMenuClose(uid)
			end
		end
	end

	local class = ActiveClass()
	if class and vrmod.EnsureWeaponViewModelEntry then
		vrmod.EnsureWeaponViewModelEntry(class)
	end

	open = true
	stepFine = false
	livePos, liveAng, liveScale = WristPose()
	SetStatus("Editing: " .. (class or "?"), 2)

	VRUtilMenuOpen(UID, W, H, nil, true, livePos, liveAng, liveScale, true, function()
		open = false
		SaveAll()
		hook.Remove("PreRender", "weapon_settings_paint")
		hook.Remove("VRMod_Input", "weapon_settings_input")
		hook.Remove("VRMod_OpenQuickMenu", "weapon_settings_qm")
	end)

	if not (g_VR.menus and g_VR.menus[UID] and g_VR.menus[UID].rt) then
		open = false
		return
	end

	local sm = g_VR.menus[UID]
	sm.cubeMenu = true
	sm.grabbable = true
	sm.resizable = true
	if vrmod.MenuApplyHandAnchor then
		vrmod.MenuApplyHandAnchor(sm, liveScale, livePos, liveAng, WristHand())
	else
		if not sm.scaleLocked then sm.scale = liveScale end
		sm.pos, sm.ang = livePos, liveAng
		sm.attachment = true
		sm.attachHand = WristHand()
	end

	paint()

	hook.Add("PreRender", "weapon_settings_paint", function()
		if not open then
			hook.Remove("PreRender", "weapon_settings_paint")
			return
		end
		if not (g_VR.menus and g_VR.menus[UID] and g_VR.menus[UID].rt) then
			open = false
			return
		end
		-- Refresh entry if player switched weapons while menu open
		local c = ActiveClass()
		if c and vrmod.EnsureWeaponViewModelEntry then
			vrmod.EnsureWeaponViewModelEntry(c)
		end
		if vrmod.MenuApplyHandAnchor then
			vrmod.MenuApplyHandAnchor(g_VR.menus[UID], liveScale, livePos, liveAng, WristHand())
		elseif not g_VR.menus[UID].freeFloat and not g_VR.menus[UID].grabHand then
			local wm = g_VR.menus[UID]
			if not wm.scaleLocked then wm.scale = liveScale end
			wm.pos, wm.ang = livePos, liveAng
			wm.attachment = true
			wm.attachHand = WristHand()
			wm.cubeMenu = true
		end
		paint()
	end)

	hook.Add("VRMod_Input", "weapon_settings_input", function(action, pressed)
		if not open then return end
		if pressed and (
			action == "boolean_secondaryfire"
			or action == "boolean_chat"
			or action == "boolean_use"
			or action == "boolean_changeweapon"
		) then
			vrmod.WeaponSettings_Close()
			return
		end
		if not pressed then return end
		if not (vrmod.IsMenuPrimaryClick and vrmod.IsMenuPrimaryClick(action)) then return end

		local cx, cy = g_VR.menuCursorX, g_VR.menuCursorY
		if not (g_VR.menuFocus == UID or (g_VR.menus and g_VR.menus[UID])) then return end
		if not cx or not cy then return end

		for _, b in ipairs(buttons) do
			if b.x and hit(b.x, b.y, b.w, b.h, cx, cy) and b.action then
				b.action()
				if open then paint() end
				return
			end
		end
	end)

	hook.Add("VRMod_Exit", "weapon_settings_exit", function()
		vrmod.WeaponSettings_Close()
	end)

	-- Stay open with QM (like spawn); do not auto-close
	hook.Add("VRMod_OpenQuickMenu", "weapon_settings_qm", function()
		-- keep open
	end)
end

concommand.Add("vrmod_weapon_settings", function()
	if g_VR and g_VR.active then
		vrmod.WeaponSettings_Open()
	else
		RunConsoleCommand("vrmod_weaponconfig")
	end
end)
