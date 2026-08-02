if SERVER then return end
-- =============================================================================
-- VR Launcher Hub — Cube chrome main menu (HL2VR / stock New Game style)
--
-- Always exposes:
--   · New Game  → extended map browser (modes + maxplayers + server/settings)
--   · Settings  → VR Cube settings
--   · Bindings  → OpenXR rebind
--   · Resume / Disconnect / Quit
--
-- Opens when: vrmod_hub 1, openxr launch session, or menu-vr bind exhausted.
-- Manual: vrmod_hub / vrmod_hub_open
-- =============================================================================

vrmod = vrmod or {}
g_VR = g_VR or {}

local UID = "vr_hub"
local open = false
local buttons = {}
local statusMsg, statusUntil = "", 0

-- Freefloat cinema size (launcher worth showing)
local W, H = 520, 620
local livePos, liveAng, liveScale = Vector(0, 0, 48), Angle(0, 0, 90), 0.032
local HEADER, PAD, ROW_H = 72, 16, 50

local function Theme()
	if vrmod.cube and vrmod.cube.ThemeLive then return vrmod.cube.ThemeLive() end
	return {
		bg = Color(12, 6, 10, 250),
		header = Color(196, 30, 58, 255),
		headerDim = Color(80, 12, 24, 255),
		row = Color(40, 14, 20, 245),
		rowHot = Color(90, 22, 36, 255),
		text = Color(255, 240, 244, 255),
		muted = Color(200, 150, 165, 230),
		hot = Color(255, 70, 100, 255),
		ok = Color(90, 220, 150, 255),
	}
end

local function Font(key)
	if vrmod.cube and vrmod.cube.Font then return vrmod.cube.Font(key) or "DermaDefault" end
	if key == "CubeTitle" then return "DermaLarge" end
	return "DermaDefaultBold"
end

local function HubEnabled()
	local c = GetConVar("vrmod_hub")
	return c and c:GetBool()
end

local function LauncherSession()
	if vrmod.IsOpenXRLaunchSession and vrmod.IsOpenXRLaunchSession() then return true end
	local menu = GetConVar("vrmod_menu_vr")
	if menu and menu:GetBool() then return true end
	return HubEnabled()
end

local function FloatPose()
	if vrmod.panel2vr and vrmod.panel2vr.ComputeFloatPose then
		return vrmod.panel2vr.ComputeFloatPose(32, -2)
	end
	if g_VR and g_VR.tracking and g_VR.tracking.hmd then
		local hmd = g_VR.tracking.hmd
		local yaw = Angle(0, hmd.ang.yaw, 0)
		local pos = hmd.pos + yaw:Forward() * 32 + Vector(0, 0, -2)
		local ang = Angle(0, yaw.yaw + 180, 90)
		if g_VR.origin and g_VR.originAngle then
			pos, ang = WorldToLocal(pos, ang, g_VR.origin, g_VR.originAngle)
		end
		return pos, ang
	end
	return Vector(0, 0, 48), Angle(0, 0, 90)
end

local function SetStatus(msg, sec)
	statusMsg = tostring(msg or "")
	statusUntil = CurTime() + (sec or 2.5)
end

local function MenuItems()
	local gm = engine.ActiveGamemode and engine.ActiveGamemode() or "?"
	local map = game.GetMap and game.GetMap() or "?"
	return {
		{ id = "newgame", label = "New Game", hint = "Maps · gamemode · maxplayers · settings" },
		{ id = "settings", label = "VR Settings", hint = "Comfort, render, locomotion, UI" },
		{ id = "bindings", label = "Controller bindings", hint = "OpenXR rebind / chords" },
		{ id = "resume", label = "Resume", hint = "Close launcher, keep VR · " .. map },
		{ id = "disconnect", label = "Disconnect", hint = "Leave map / server" },
		{ id = "quit", label = "Quit Garry's Mod", hint = "Exit game" },
	}, gm, map
end

local function rebuildButtons()
	buttons = {}
	buttons[#buttons + 1] = { x = W - 52, y = 12, w = 40, h = 36, kind = "close" }
	local y0 = HEADER + 12
	for i, item in ipairs(MenuItems()) do
		local y = y0 + (i - 1) * (ROW_H + 8)
		buttons[#buttons + 1] = {
			x = PAD, y = y, w = W - PAD * 2, h = ROW_H,
			kind = "item", id = item.id, item = item,
		}
	end
end

local function openNewGame()
	timer.Simple(0.05, function()
		if vrmod.OpenNewGameUnpaused then
			vrmod.OpenNewGameUnpaused()
		elseif isfunction(vrmod.OpenNewGame) then
			if vrmod.VRUnpauseWorld then vrmod.VRUnpauseWorld() end
			vrmod.OpenNewGame()
		elseif isfunction(VRUtilCreateMapBrowserWindow) then
			if vrmod.VRUnpauseWorld then vrmod.VRUnpauseWorld() end
			VRUtilCreateMapBrowserWindow()
		else
			RunConsoleCommand("vrmod_newgame")
		end
	end)
end

local function openSettings()
	timer.Simple(0.05, function()
		if vrmod.VRUnpauseWorld then vrmod.VRUnpauseWorld() end
		if vrmod.CubeSettings_Open then
			vrmod.CubeSettings_Open()
		elseif vrmod.Settings_Open then
			vrmod.Settings_Open()
		end
		timer.Simple(0.1, function()
			if vrmod.VRUnpauseWorld then vrmod.VRUnpauseWorld() end
		end)
	end)
end

local function paint()
	if not open or not (g_VR and g_VR.menus and g_VR.menus[UID]) then return end
	if isfunction(VRUtilMenuRenderStart) then VRUtilMenuRenderStart(UID) end
	g_VR.menus[UID].dirty = true

	local T = Theme()
	local focused = g_VR.menuFocus == UID
	local mx, my = g_VR.menuCursorX or -1, g_VR.menuCursorY or -1
	rebuildButtons()

	local _, map = select(2, MenuItems())
	if vrmod.cube and vrmod.cube.DrawChrome then
		vrmod.cube.DrawChrome(0, 0, W, H, "gVRMod", {
			subtitle = "Launcher · " .. (game.GetMap and game.GetMap() or "?"),
			headerH = HEADER,
		})
	else
		surface.SetDrawColor(T.bg)
		surface.DrawRect(0, 0, W, H)
		surface.SetDrawColor(T.headerDim)
		surface.DrawRect(0, 0, W, HEADER)
		surface.SetDrawColor(T.header)
		surface.DrawRect(0, HEADER - 4, W, 4)
		draw.SimpleText("gVRMod", Font("CubeTitle"), PAD, 14, T.header, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		draw.SimpleText("Launcher", Font("CubeSmall") or "DermaDefault", PAD, 42, T.muted)
	end

	local closeHot = focused and mx >= W - 52 and mx <= W - 12 and my >= 12 and my <= 48
	surface.SetDrawColor(closeHot and T.hot or T.header)
	surface.DrawRect(W - 52, 12, 40, 36)
	draw.SimpleText("X", "DermaLarge", W - 32, 30, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	for _, btn in ipairs(buttons) do
		if btn.kind == "item" then
			local hot = focused and mx >= btn.x and mx <= btn.x + btn.w and my >= btn.y and my <= btn.y + btn.h
			surface.SetDrawColor(hot and T.rowHot or T.row)
			surface.DrawRect(btn.x, btn.y, btn.w, btn.h)
			if hot then
				surface.SetDrawColor(T.hot)
				surface.DrawRect(btn.x, btn.y, 6, btn.h)
			end
			-- Highlight primary launcher actions
			if btn.id == "newgame" or btn.id == "settings" then
				surface.SetDrawColor(T.header.r, T.header.g, T.header.b, hot and 255 or 180)
				surface.DrawRect(btn.x + btn.w - 6, btn.y, 6, btn.h)
			end
			draw.SimpleText(btn.item.label, Font("CubeLabel") or "DermaDefaultBold",
				btn.x + 18, btn.y + 14, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(btn.item.hint or "", "DermaDefault",
				btn.x + 18, btn.y + 34, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end

	local gm = engine.ActiveGamemode and engine.ActiveGamemode() or "?"
	draw.SimpleText(string.format("%s · %s", game.GetMap() or "?", gm), "DermaDefault",
		PAD, H - 36, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	if statusMsg ~= "" and CurTime() < statusUntil then
		draw.SimpleText(statusMsg, Font("CubeLabel") or "DermaDefaultBold",
			W - PAD, H - 36, T.ok, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
	end

	if focused and mx >= 0 and my >= 0 then
		surface.SetDrawColor(T.hot)
		surface.DrawRect(mx - 2, my - 14, 4, 28)
		surface.DrawRect(mx - 14, my - 2, 28, 4)
	end

	if isfunction(VRUtilMenuRenderEnd) then VRUtilMenuRenderEnd() end
end

local function activateAt(mx, my)
	for _, btn in ipairs(buttons) do
		if mx >= btn.x and mx <= btn.x + btn.w and my >= btn.y and my <= btn.y + btn.h then
			if btn.kind == "close" then
				vrmod.VRHub_Close()
				return
			elseif btn.kind == "item" then
				local id = btn.id
				if id == "resume" then
					vrmod.VRHub_Close()
				elseif id == "newgame" then
					-- Keep hub open behind; freefloat New Game in front
					openNewGame()
					SetStatus("New Game…", 2)
				elseif id == "settings" then
					openSettings()
					SetStatus("Settings…", 2)
				elseif id == "bindings" then
					timer.Simple(0.05, function()
						if vrmod.BindingsPanel_Open then vrmod.BindingsPanel_Open()
						else RunConsoleCommand("vrmod_controller_bindings") end
					end)
				elseif id == "disconnect" then
					RunConsoleCommand("disconnect")
					SetStatus("Disconnecting…", 2)
				elseif id == "quit" then
					RunConsoleCommand("gamemenucommand", "quit")
					RunConsoleCommand("quit")
				end
				return
			end
		end
	end
end

function vrmod.VRHub_Close()
	if not open then
		if isfunction(VRUtilMenuClose) and g_VR and g_VR.menus and g_VR.menus[UID] then
			g_VR.menus[UID].closeFunc = nil
			VRUtilMenuClose(UID)
		end
		return
	end
	open = false
	hook.Remove("PreRender", "vr_hub_paint")
	hook.Remove("VRMod_Input", "vr_hub_input")
	hook.Remove("VRMod_Exit", "vr_hub_exit")
	if g_VR and g_VR.menus and g_VR.menus[UID] then
		g_VR.menus[UID].closeFunc = nil
	end
	if isfunction(VRUtilMenuClose) then VRUtilMenuClose(UID) end
end

function vrmod.VRHub_IsOpen()
	return open
end

function vrmod.VRHub_Open()
	if not (g_VR and g_VR.active) then
		SetStatus("Start VR first", 2)
		print("[gVRMod] Start VR first")
		return
	end
	-- Never pause world for hub (SP GameUI freezes tracking/input)
	if vrmod.VRUnpauseWorld then vrmod.VRUnpauseWorld() end
	if open and g_VR.menus and g_VR.menus[UID] then
		g_VR.menus[UID].dirty = true
		return
	end
	if not isfunction(VRUtilMenuOpen) then return end

	if g_VR.menus then
		for _, uid in ipairs({ "miscmenu", "heightmenu" }) do
			if g_VR.menus[uid] and isfunction(VRUtilMenuClose) then
				g_VR.menus[uid].closeFunc = nil
				VRUtilMenuClose(uid)
			end
		end
	end

	open = true
	livePos, liveAng = FloatPose()
	liveScale = 0.032
	-- Free-float cinema (not wrist) for launcher presence
	VRUtilMenuOpen(UID, W, H, nil, false, livePos, liveAng, liveScale, true, function()
		open = false
		hook.Remove("PreRender", "vr_hub_paint")
		hook.Remove("VRMod_Input", "vr_hub_input")
	end)

	if not (g_VR.menus and g_VR.menus[UID]) then
		open = false
		return
	end

	local sm = g_VR.menus[UID]
	sm.cubeMenu = true
	sm.grabbable = true
	sm.resizable = true
	sm.freeFloat = true
	sm.attachment = false
	sm.persistOpen = true

	paint()
	hook.Add("PreRender", "vr_hub_paint", function()
		if not open then
			hook.Remove("PreRender", "vr_hub_paint")
			return
		end
		if not (g_VR.menus and g_VR.menus[UID]) then
			open = false
			return
		end
		paint()
	end)

	hook.Add("VRMod_Input", "vr_hub_input", function(action, pressed)
		if not open or not pressed then return end
		if g_VR.menuFocus ~= UID then return end
		if not (vrmod.IsMenuPrimaryClick and vrmod.IsMenuPrimaryClick(action)) then return end
		activateAt(g_VR.menuCursorX or 0, g_VR.menuCursorY or 0)
	end)

	hook.Add("VRMod_Exit", "vr_hub_exit", function()
		vrmod.VRHub_Close()
	end)
end

-- Auto-open launcher after VR when hub or openxr launch session
hook.Add("VRMod_Start", "vrmod_vr_hub", function(ply)
	if ply and IsValid(LocalPlayer()) and ply ~= LocalPlayer() then return end
	-- Prefer hub whenever launcher session (menu_vr / openxr marker / hub cvar)
	local force = HubEnabled() or (vrmod.IsOpenXRLaunchSession and vrmod.IsOpenXRLaunchSession())
	if not force then return end
	timer.Simple(1.0, function()
		if not (g_VR and g_VR.active) then return end
		if vrmod.Experience_ShouldRun and vrmod.Experience_ShouldRun() then return end
		-- If freefloat MainMenu bound successfully, still open hub as secondary? 
		-- User wants settings + map selector in launcher → always open hub for launch sessions.
		vrmod.VRHub_Open()
	end)
end)

concommand.Add("vrmod_hub", function()
	if g_VR and g_VR.active then
		if open then vrmod.VRHub_Close() else vrmod.VRHub_Open() end
	else
		print("[gVRMod] Start VR first (or use launcher with auto-start)")
	end
end)

concommand.Add("vrmod_hub_open", function()
	vrmod.VRHub_Open()
end)

concommand.Add("vrmod_launcher", function()
	if not (g_VR and g_VR.active) then
		if isfunction(VRUtilClientStart) then pcall(VRUtilClientStart) end
		timer.Simple(1.5, function()
			if g_VR and g_VR.active then vrmod.VRHub_Open() end
		end)
		return
	end
	vrmod.VRHub_Open()
end)
