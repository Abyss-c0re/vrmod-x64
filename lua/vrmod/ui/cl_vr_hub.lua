if SERVER then return end
-- =============================================================================
-- Cube Launcher Hub — freefloat Cube chrome in front of HMD (the actual experience)
--
-- Not desktop GameUI. Not empty construct + laser.
-- Opens unpaused on every launcher/VR start; billboards in front of the headset
-- until the player grabs it. Quick menu: "Launcher".
-- =============================================================================

vrmod = vrmod or {}
g_VR = g_VR or {}

local UID = "vr_hub"
local open = false
local buttons = {}
local statusMsg, statusUntil = "", 0
local followHmd = true -- until user grabs (freeFloat grab)

-- Large cinema panel — readable in HMD
local W, H = 640, 720
local livePos, liveAng, liveScale = Vector(0, 0, 0), Angle(0, 0, 90), 0.042
local HEADER, PAD, ROW_H = 88, 20, 56

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

--- World-space pose → origin-local for VRUtilMenuOpen (same as panel2vr)
local function HmdBillboardPose(distance, heightOffset)
	distance = distance or 30
	heightOffset = heightOffset or -4
	if not (g_VR and g_VR.tracking and g_VR.tracking.hmd and g_VR.tracking.hmd.pos) then
		return Vector(20, 0, 56), Angle(0, 180, 90)
	end
	local hmd = g_VR.tracking.hmd
	local yawOnly = Angle(0, hmd.ang.yaw, 0)
	local pos = hmd.pos + yawOnly:Forward() * distance + Vector(0, 0, heightOffset)
	-- 3D2D: face player (same convention as panel2vr.ComputeFloatPose)
	local ang = Angle(0, yawOnly.yaw + 180, 90)
	if g_VR.origin and g_VR.originAngle then
		pos, ang = WorldToLocal(pos, ang, g_VR.origin, g_VR.originAngle)
	end
	return pos, ang
end

local function SetStatus(msg, sec)
	statusMsg = tostring(msg or "")
	statusUntil = CurTime() + (sec or 2.5)
end

local function MenuItems()
	local map = game.GetMap and game.GetMap() or "?"
	return {
		{ id = "newgame", label = "NEW GAME", hint = "Maps · gamemode · players · settings" },
		{ id = "settings", label = "VR SETTINGS", hint = "Comfort · render · locomotion · UI" },
		{ id = "bindings", label = "BINDINGS", hint = "OpenXR rebind · chords" },
		{ id = "resume", label = "RESUME", hint = "Close launcher · stay in VR · " .. map },
		{ id = "disconnect", label = "DISCONNECT", hint = "Leave map / server" },
		{ id = "quit", label = "QUIT", hint = "Exit Garry's Mod" },
	}
end

local function rebuildButtons()
	buttons = {}
	buttons[#buttons + 1] = { x = W - 56, y = 16, w = 40, h = 40, kind = "close" }
	local y0 = HEADER + 16
	for i, item in ipairs(MenuItems()) do
		local y = y0 + (i - 1) * (ROW_H + 10)
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
		elseif vrmod.OpenNewGame then
			if vrmod.VRUnpauseWorld then vrmod.VRUnpauseWorld() end
			vrmod.OpenNewGame()
		elseif isfunction(VRUtilCreateMapBrowserWindow) then
			if vrmod.VRUnpauseWorld then vrmod.VRUnpauseWorld() end
			VRUtilCreateMapBrowserWindow()
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
	end)
end

local function paint()
	if not open or not (g_VR and g_VR.menus and g_VR.menus[UID]) then return end
	if isfunction(VRUtilMenuRenderStart) then VRUtilMenuRenderStart(UID) end
	g_VR.menus[UID].dirty = true
	g_VR.menus[UID].alwaysRedraw = true
	g_VR.menus[UID].paintInterval = 0

	local T = Theme()
	local focused = g_VR.menuFocus == UID
	local mx, my = g_VR.menuCursorX or -1, g_VR.menuCursorY or -1
	rebuildButtons()

	-- Full Cube chrome plate
	if vrmod.cube and vrmod.cube.DrawChrome then
		vrmod.cube.DrawChrome(0, 0, W, H, "gVRMod", {
			subtitle = "CUBE EXPERIENCE · LAUNCHER",
			headerH = HEADER,
		})
	else
		surface.SetDrawColor(T.bg)
		surface.DrawRect(0, 0, W, H)
		surface.SetDrawColor(T.headerDim)
		surface.DrawRect(0, 0, W, HEADER)
		surface.SetDrawColor(T.header)
		surface.DrawRect(0, 0, W, 6)
		surface.DrawRect(0, HEADER - 4, W, 4)
		draw.SimpleText("gVRMod", Font("CubeTitle"), PAD, 18, T.header, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		draw.SimpleText("CUBE EXPERIENCE · LAUNCHER", "DermaDefault", PAD, 52, T.muted)
	end

	-- Crimson side rail
	surface.SetDrawColor(T.header)
	surface.DrawRect(0, HEADER, 4, H - HEADER)

	local closeHot = focused and mx >= W - 56 and mx <= W - 16 and my >= 16 and my <= 56
	surface.SetDrawColor(closeHot and T.hot or T.header)
	surface.DrawRect(W - 56, 16, 40, 40)
	draw.SimpleText("X", "DermaLarge", W - 36, 36, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	for _, btn in ipairs(buttons) do
		if btn.kind == "item" then
			local hot = focused and mx >= btn.x and mx <= btn.x + btn.w and my >= btn.y and my <= btn.y + btn.h
			local primary = (btn.id == "newgame" or btn.id == "settings")
			if vrmod.cube and vrmod.cube.DrawSlot then
				vrmod.cube.DrawSlot(btn.x, btn.y, btn.w, btn.h, nil, hot, primary, true)
			else
				surface.SetDrawColor(hot and T.rowHot or T.row)
				surface.DrawRect(btn.x, btn.y, btn.w, btn.h)
			end
			if hot or primary then
				surface.SetDrawColor(T.header)
				surface.DrawRect(btn.x, btn.y, 6, btn.h)
			end
			draw.SimpleText(btn.item.label, Font("CubeLabel") or "DermaDefaultBold",
				btn.x + 20, btn.y + 16, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(btn.item.hint or "", "DermaDefault",
				btn.x + 20, btn.y + 38, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end

	local gm = engine.ActiveGamemode and engine.ActiveGamemode() or "?"
	local map = game.GetMap and game.GetMap() or "?"
	draw.SimpleText(string.format("%s  ·  %s", map, gm), "DermaDefault",
		PAD, H - 40, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	if statusMsg ~= "" and CurTime() < statusUntil then
		draw.SimpleText(statusMsg, Font("CubeLabel") or "DermaDefaultBold",
			W - PAD, H - 40, T.ok, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
	end

	-- Laser cursor crosshair when focused
	if focused and mx >= 0 and my >= 0 then
		surface.SetDrawColor(T.hot)
		surface.DrawRect(mx - 2, my - 16, 4, 32)
		surface.SetDrawColor(T.hot)
		surface.DrawRect(mx - 16, my - 2, 32, 4)
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
	if not open then
		if isfunction(VRUtilMenuClose) and g_VR and g_VR.menus and g_VR.menus[UID] then
			g_VR.menus[UID].closeFunc = nil
			VRUtilMenuClose(UID)
		end
		return
	end
	open = false
	followHmd = true
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
		print("[gVRMod] Start VR first")
		return
	end
	if vrmod.VRUnpauseWorld then vrmod.VRUnpauseWorld() end

	-- Drop saved layout for hub — bad free-float poses park it out of view
	if isfunction(vrmod.ClearMenuFloatPose) then
		pcall(vrmod.ClearMenuFloatPose, UID)
	elseif isfunction(vrmod.SaveMenuLayout) then
		-- force wipe via layouts if available
		pcall(function()
			if file.Exists("vrmod/panel_layouts.json", "DATA") then
				local raw = file.Read("vrmod/panel_layouts.json", "DATA") or "{}"
				local t = util.JSONToTable(raw) or {}
				t[UID] = nil
				file.Write("vrmod/panel_layouts.json", util.TableToJSON(t, true))
			end
		end)
	end

	if open and g_VR.menus and g_VR.menus[UID] then
		followHmd = true
		g_VR.menus[UID].dirty = true
		return
	end
	if not isfunction(VRUtilMenuOpen) then
		print("[gVRMod] VRUtilMenuOpen missing")
		return
	end

	-- Close competing system shells only
	if g_VR.menus then
		for _, uid in ipairs({ "miscmenu", "heightmenu" }) do
			if g_VR.menus[uid] and isfunction(VRUtilMenuClose) then
				g_VR.menus[uid].closeFunc = nil
				VRUtilMenuClose(uid)
			end
		end
	end

	open = true
	followHmd = true
	livePos, liveAng = HmdBillboardPose(30, -4)
	liveScale = 0.042

	VRUtilMenuOpen(UID, W, H, nil, false, livePos, liveAng, liveScale, true, function()
		open = false
		followHmd = true
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
	sm.freeFloat = true
	sm.attachment = false
	sm.persistOpen = true
	sm.keepAlive = true
	sm.alwaysRedraw = true
	sm.paintInterval = 0
	sm.paintIntervalFocused = 0
	-- Don't re-apply a dead layout next frame
	sm.pos = livePos
	sm.ang = liveAng
	sm.scale = liveScale
	sm.baseScale = liveScale

	-- Laser on for menu use
	pcall(function() RunConsoleCommand("vrmod_laserpointer", "1") end)

	if vrmod.Toast then
		vrmod.Toast("Cube Launcher — laser + trigger", 4, "hint")
	end
	print("[gVRMod] Cube launcher open (freefloat cinema)")

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
		local m = g_VR.menus[UID]
		-- Follow HMD until grabbed (grabHand set) so panel is always in view
		if followHmd and not m.grabHand then
			local p, a = HmdBillboardPose(30, -4)
			m.pos = p
			m.ang = a
			m.freeFloat = true
			m.attachment = false
			livePos, liveAng = p, a
		elseif m.grabHand then
			followHmd = false -- user took ownership
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

--- Force open with retries (tracking may be late first frames)
function vrmod.VRHub_OpenWhenReady()
	local n = 0
	timer.Create("vrmod_hub_ready", 0.4, 15, function()
		n = n + 1
		if not (g_VR and g_VR.active) then return end
		if open and g_VR.menus and g_VR.menus[UID] then
			timer.Remove("vrmod_hub_ready")
			return
		end
		if g_VR.threePoints or (g_VR.tracking and g_VR.tracking.hmd) or n >= 3 then
			vrmod.VRHub_Open()
		end
		if open then timer.Remove("vrmod_hub_ready") end
	end)
end

-- Always open Cube launcher when VR starts from launcher path
hook.Add("VRMod_Start", "vrmod_vr_hub", function(ply)
	if ply and IsValid(LocalPlayer()) and ply ~= LocalPlayer() then return end
	local force = LauncherSession()
	if not force then return end
	-- Do NOT wait on Experience_ShouldRun — launcher IS the Cube face.
	-- Onboarding can stack; hub must still appear.
	timer.Simple(0.6, function()
		if not (g_VR and g_VR.active) then return end
		if vrmod.OpenLauncherUnpaused then
			vrmod.OpenLauncherUnpaused()
		else
			vrmod.VRHub_OpenWhenReady()
		end
	end)
	timer.Simple(2.0, function()
		if g_VR and g_VR.active and not open then
			vrmod.VRHub_OpenWhenReady()
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
	if vrmod.OpenLauncherUnpaused then
		vrmod.OpenLauncherUnpaused()
	else
		vrmod.VRHub_Open()
	end
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
