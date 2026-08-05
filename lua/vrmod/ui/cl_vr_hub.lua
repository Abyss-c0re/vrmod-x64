if SERVER then return end
-- =============================================================================
-- Cube Native VR Launcher (product shell)
--
-- Opened automatically by OpenXR wrapper (openxr_launch marker + vrmod_hub).
-- Wrist-docked Cube chrome: Resume · New Game · Settings · Bindings · Quit.
-- Unpaused world. Laser + trigger. Desktop window is only a mirror.
-- =============================================================================

vrmod = vrmod or {}
g_VR = g_VR or {}

local UID = "vr_hub"
local open = false
local buttons = {}
local statusMsg, statusUntil = "", 0

-- Extra row for Video Calibration on the free-floating / wrist hub
local W, H = 560, 740
local livePos, liveAng, liveScale = Vector(4, 5, 6), Angle(0, -90, 55), 0.028
local HEADER, PAD, ROW_H = 80, 18, 54

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

local function WristHand()
	return (vrmod.GetSecondaryHand and vrmod.GetSecondaryHand()) or "left"
end

local function WristPose()
	local wrist = WristHand()
	if isfunction(VRUtilHandMenuPose) then
		return VRUtilHandMenuPose(W, H, 0.028, Vector(4, 5, 6), Angle(0, -90, 55), wrist)
	end
	return Vector(4, 5, 6), Angle(0, -90, 55), 0.028
end

local function SetStatus(msg, sec)
	statusMsg = tostring(msg or "")
	statusUntil = CurTime() + (sec or 2.5)
	if g_VR and g_VR.menus and g_VR.menus[UID] then
		g_VR.menus[UID].dirty = true
	end
end

local function MenuItems()
	local map = game.GetMap and game.GetMap() or "?"
	-- Cube pause / startup hub (when stock GameUI projection fails)
	-- Order: play (resume · new game) → config (settings · video cal · bindings) → leave.
	return {
		{ id = "resume", label = "RESUME", hint = "Close menu · stay in VR · " .. map },
		{ id = "newgame", label = "NEW GAME", hint = "Maps · gamemode · multiplayer" },
		{ id = "settings", label = "VR SETTINGS", hint = "Comfort · render · locomotion · UI" },
		{ id = "video_cal", label = "VIDEO CALIBRATION", hint = "Scale · V/H · IPD · FOV · lens" },
		{ id = "bindings", label = "BINDINGS", hint = "OpenXR rebind · chords" },
		{ id = "disconnect", label = "DISCONNECT", hint = "Leave map / server" },
		{ id = "quit", label = "QUIT", hint = "Exit Garry's Mod" },
	}
end

local function rebuildButtons()
	buttons = {}
	buttons[#buttons + 1] = { x = W - 52, y = 14, w = 38, h = 38, kind = "close" }
	local y0 = HEADER + 14
	for i, item in ipairs(MenuItems()) do
		local y = y0 + (i - 1) * (ROW_H + 8)
		buttons[#buttons + 1] = {
			x = PAD, y = y, w = W - PAD * 2, h = ROW_H,
			kind = "item", id = item.id, item = item,
		}
	end
end

local function openNewGame()
	-- Close hub first so New Game owns laser focus (stacked hand panels = un-closeable UX)
	vrmod.VRHub_Close()
	timer.Simple(0.05, function()
		if vrmod.OpenNewGameUnpaused then
			vrmod.OpenNewGameUnpaused()
		elseif vrmod.OpenNewGame then
			if vrmod.VRUnpauseWorld then vrmod.VRUnpauseWorld() end
			vrmod.OpenNewGame()
		elseif isfunction(VRUtilCreateMapBrowserWindow) then
			VRUtilCreateMapBrowserWindow()
		end
	end)
end

local function openSettings()
	vrmod.VRHub_Close()
	timer.Simple(0.05, function()
		if vrmod.VRUnpauseWorld then vrmod.VRUnpauseWorld() end
		if vrmod.CubeSettings_Open then
			vrmod.CubeSettings_Open()
		elseif vrmod.Settings_Open then
			vrmod.Settings_Open()
		end
	end)
end

local function openVideoCal()
	-- Close hub so cal 3D overlay + input own the session immediately
	vrmod.VRHub_Close()
	timer.Simple(0.05, function()
		if vrmod.VRUnpauseWorld then vrmod.VRUnpauseWorld() end
		if vrmod.BorderCal_Start then
			vrmod.BorderCal_Start()
		else
			RunConsoleCommand("vrmod_border_calibrate")
		end
	end)
end

local function paintInner()
	local T = Theme()
	local focused = g_VR.menuFocus == UID
	local mx, my = g_VR.menuCursorX or -1, g_VR.menuCursorY or -1
	rebuildButtons()

	if vrmod.cube and vrmod.cube.DrawChrome then
		vrmod.cube.DrawChrome(0, 0, W, H, "gVRMod", {
			subtitle = "PAUSE · CUBE FALLBACK",
			headerH = HEADER,
		})
	else
		local bg = T.bg or Color(12, 6, 10, 250)
		surface.SetDrawColor(bg.r, bg.g, bg.b, bg.a or 250)
		surface.DrawRect(0, 0, W, H)
	end

	local closeHot = focused and mx >= W - 52 and mx <= W - 14 and my >= 14 and my <= 52
	local hc = closeHot and (T.hot or Color(255, 70, 100)) or (T.header or Color(196, 30, 58))
	surface.SetDrawColor(hc.r, hc.g, hc.b, hc.a or 255)
	surface.DrawRect(W - 52, 14, 38, 38)
	draw.SimpleText("X", "DermaLarge", W - 33, 33, T.text or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	for _, btn in ipairs(buttons) do
		if btn.kind == "item" then
			local isHot = focused and mx >= btn.x and mx <= btn.x + btn.w and my >= btn.y and my <= btn.y + btn.h
			local primary = (btn.id == "newgame" or btn.id == "settings" or btn.id == "video_cal")
			if vrmod.cube and vrmod.cube.DrawSlot then
				vrmod.cube.DrawSlot(btn.x, btn.y, btn.w, btn.h, nil, isHot, primary, true)
			else
				local rc = isHot and (T.rowHot or Color(90, 22, 36)) or (T.row or Color(40, 14, 20))
				surface.SetDrawColor(rc.r, rc.g, rc.b, rc.a or 255)
				surface.DrawRect(btn.x, btn.y, btn.w, btn.h)
			end
			draw.SimpleText(btn.item.label, Font("CubeLabel") or "DermaDefaultBold",
				btn.x + 18, btn.y + 14, T.text or color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(btn.item.hint or "", "DermaDefault",
				btn.x + 18, btn.y + 36, T.muted or Color(200, 150, 165), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end

	local gm = engine.ActiveGamemode and engine.ActiveGamemode() or "?"
	local map = game.GetMap and game.GetMap() or "?"
	draw.SimpleText(string.format("%s  ·  %s", map, gm), "DermaDefault",
		PAD, H - 36, T.muted or Color(200, 150, 165), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	if statusMsg ~= "" and CurTime() < statusUntil then
		draw.SimpleText(statusMsg, Font("CubeLabel") or "DermaDefaultBold",
			W - PAD, H - 36, T.ok or Color(90, 220, 150), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
	end

	if focused and mx >= 0 and my >= 0 then
		local hotc = T.hot or Color(255, 70, 100)
		surface.SetDrawColor(hotc.r, hotc.g, hotc.b, 255)
		surface.DrawRect(mx - 2, my - 14, 4, 28)
		surface.DrawRect(mx - 14, my - 2, 28, 4)
	end
end

local function paint(force)
	if not open or not (g_VR and g_VR.menus and g_VR.menus[UID]) then return end
	local m = g_VR.menus[UID]
	m.alwaysRedraw = false
	m.paintInterval = 0
	m.paintIntervalFocused = 0 -- cursor quantize dirties via MenuShouldRepaint
	if isfunction(vrmod.NativeMenuPaint) then
		vrmod.NativeMenuPaint(UID, paintInner, force)
		return
	end
	-- Fallback without helper
	if not force and m.dirty ~= true then return end
	if not isfunction(VRUtilMenuRenderStart) or not VRUtilMenuRenderStart(UID) then return end
	pcall(paintInner)
	if isfunction(VRUtilMenuRenderEnd) then pcall(VRUtilMenuRenderEnd) end
end

local function dirty()
	if g_VR and g_VR.menus and g_VR.menus[UID] then
		g_VR.menus[UID].dirty = true
	end
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
				elseif id == "video_cal" then
					openVideoCal()
					SetStatus("Video calibration…", 2)
				elseif id == "newgame" then
					openNewGame()
					SetStatus("New Game…", 2)
				elseif id == "settings" then
					openSettings()
					SetStatus("Settings…", 2)
				elseif id == "bindings" then
					timer.Simple(0.05, function()
						if vrmod.VRUnpauseWorld then vrmod.VRUnpauseWorld() end
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
	open = false
	hook.Remove("PreRender", "vr_hub_paint")
	hook.Remove("VRMod_Input", "vr_hub_input")
	hook.Remove("VRMod_Exit", "vr_hub_exit")
	if g_VR and g_VR.menus and g_VR.menus[UID] then
		local m = g_VR.menus[UID]
		m.closeFunc = nil
		m.persistOpen = false
		m.keepAlive = false
	end
	if isfunction(VRUtilMenuClose) then pcall(VRUtilMenuClose, UID) end
end

function vrmod.VRHub_IsOpen()
	return open
end

function vrmod.VRHub_Open()
	if not (g_VR and g_VR.active) then
		print("[gVRMod] Start VR first")
		return
	end
	if vrmod.VRUnpauseWorld then vrmod.VRUnpauseWorld() end

	-- Never restore a bad free-float layout for hub
	pcall(function()
		if file.Exists("vrmod/panel_layouts.json", "DATA") then
			local t = util.JSONToTable(file.Read("vrmod/panel_layouts.json", "DATA") or "{}") or {}
			if t[UID] then
				t[UID] = nil
				file.Write("vrmod/panel_layouts.json", util.TableToJSON(t, true))
			end
		end
	end)

	if open and g_VR.menus and g_VR.menus[UID] then
		dirty()
		paint(true)
		return
	end
	if not isfunction(VRUtilMenuOpen) then
		print("[gVRMod] VRUtilMenuOpen missing")
		return
	end

	-- Sole hub: close QM / other shells so we never stack two "pause" UIs
	if g_VR.menus then
		for _, uid in ipairs({
			"miscmenu", "heightmenu", "cube_settings", "avatar_menu",
			"cubeui_main", "bindings_panel", "weapon_settings",
		}) do
			if g_VR.menus[uid] and isfunction(VRUtilMenuClose) then
				g_VR.menus[uid].closeFunc = nil
				pcall(VRUtilMenuClose, uid)
			end
		end
	end
	pcall(function()
		if vrmod.VirtualDisplay and vrmod.VirtualDisplay.Close then
			vrmod.VirtualDisplay.Close("pause")
			vrmod.VirtualDisplay.Close("launcher")
		end
	end)

	open = true
	livePos, liveAng, liveScale = WristPose()
	local wrist = WristHand()

	-- attachment=true → left/secondary hand (Cube standard)
	VRUtilMenuOpen(UID, W, H, nil, true, livePos, liveAng, liveScale, true, function()
		open = false
		hook.Remove("PreRender", "vr_hub_paint")
		hook.Remove("VRMod_Input", "vr_hub_input")
	end)

	if not (g_VR.menus and g_VR.menus[UID]) then
		open = false
		print("[gVRMod] hub RT failed")
		return
	end

	local sm = g_VR.menus[UID]
	sm.cubeMenu = true
	sm.grabbable = true
	sm.resizable = true
	sm.attachment = true
	sm.freeFloat = false
	sm.attachHand = wrist
	-- Allow close; do not fight VRUtilMenuClose
	sm.persistOpen = false
	sm.keepAlive = false
	sm.alwaysRedraw = false
	sm.paintInterval = 0
	sm.paintIntervalFocused = 0
	sm.pos = livePos
	sm.ang = liveAng
	sm.scale = liveScale
	sm.baseScale = liveScale

	-- Anchor ONCE at open — continuous re-dock glued every panel to the hand and ruined UX
	if vrmod.MenuApplyHandAnchor then
		vrmod.MenuApplyHandAnchor(sm, liveScale, livePos, liveAng, wrist)
	end

	pcall(function() RunConsoleCommand("vrmod_laserpointer", "1") end)
	if vrmod.Toast then
		vrmod.Toast("Cube Pause — wrist dock · grip to free-move · X to close", 4, "hint")
	end
	print("[gVRMod] Cube launcher on " .. tostring(wrist) .. " hand")

	paint(true)
	hook.Add("PreRender", "vr_hub_paint", function()
		if not open then
			hook.Remove("PreRender", "vr_hub_paint")
			return
		end
		if not (g_VR.menus and g_VR.menus[UID]) then
			open = false
			return
		end
		-- No periodic MenuApplyHandAnchor (was yanking free-float back to wrist)
		paint(false)
	end)

	hook.Add("VRMod_Input", "vr_hub_input", function(action, pressed)
		if not open or not pressed then return end
		if g_VR.menuFocus ~= UID then return end
		if vrmod.IsMenuCloseAction and vrmod.IsMenuCloseAction(action) then
			vrmod.VRHub_Close()
			return
		end
		if not (vrmod.IsMenuPrimaryClick and vrmod.IsMenuPrimaryClick(action)) then return end
		activateAt(g_VR.menuCursorX or 0, g_VR.menuCursorY or 0)
		dirty()
	end)

	hook.Add("VRMod_Exit", "vr_hub_exit", function()
		vrmod.VRHub_Close()
	end)
end

function vrmod.VRHub_OpenWhenReady()
	local n = 0
	timer.Create("vrmod_hub_ready", 0.35, 20, function()
		n = n + 1
		if not (g_VR and g_VR.active) then return end
		if open and g_VR.menus and g_VR.menus[UID] then
			timer.Remove("vrmod_hub_ready")
			return
		end
		-- Need hand pose for wrist dock
		local hasHand = g_VR.tracking and (
			(g_VR.tracking.pose_lefthand and g_VR.tracking.pose_lefthand.pos)
			or (g_VR.tracking.pose_righthand and g_VR.tracking.pose_righthand.pos)
			or g_VR.threePoints
		)
		if hasHand or n >= 4 then
			vrmod.VRHub_Open()
		end
		if open then timer.Remove("vrmod_hub_ready") end
	end)
end

hook.Add("VRMod_Start", "vrmod_vr_hub", function(ply)
	if ply and IsValid(LocalPlayer()) and ply ~= LocalPlayer() then return end
	if not LauncherSession() then return end
	-- Automatic product surface — no concommand
	timer.Simple(0.35, function()
		if not (g_VR and g_VR.active) then return end
		if vrmod.VRUnpauseWorld then pcall(vrmod.VRUnpauseWorld) end
		if not open and vrmod.VRHub_Open then vrmod.VRHub_Open() end
	end)
	timer.Simple(1.2, function()
		if g_VR and g_VR.active and not open then
			if vrmod.VRHub_OpenWhenReady then vrmod.VRHub_OpenWhenReady()
			elseif vrmod.VRHub_Open then vrmod.VRHub_Open() end
		end
	end)
	timer.Simple(2.5, function()
		if g_VR and g_VR.active and not open then
			if vrmod.VRHub_Open then vrmod.VRHub_Open() end
		end
	end)
end)

concommand.Add("vrmod_hub", function()
	if g_VR and g_VR.active then
		if open then vrmod.VRHub_Close() else vrmod.VRHub_Open() end
	else
		print("[gVRMod] Start VR first")
	end
end)

concommand.Add("vrmod_hub_open", function()
	if vrmod.OpenLauncherUnpaused then vrmod.OpenLauncherUnpaused()
	else vrmod.VRHub_Open() end
end)

concommand.Add("vrmod_launcher", function()
	if not (g_VR and g_VR.active) then
		if isfunction(VRUtilClientStart) then pcall(VRUtilClientStart) end
		timer.Simple(1.5, function()
			if g_VR and g_VR.active then
				if vrmod.OpenLauncherUnpaused then vrmod.OpenLauncherUnpaused()
				else vrmod.VRHub_OpenWhenReady() end
			end
		end)
		return
	end
	if vrmod.OpenLauncherUnpaused then vrmod.OpenLauncherUnpaused()
	else vrmod.VRHub_Open() end
end)
