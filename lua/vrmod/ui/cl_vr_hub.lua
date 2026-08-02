if SERVER then return end
-- =============================================================================
-- VR Hub — full main-menu style shell in VR (not stock Source MainMenu VGUI).
-- Stock GMod main menu is pre-map VGUI and cannot be reliably stereo'd.
-- This hub is the intentional replacement for "menu fully in VR" (HL2VR-like UX).
--
-- Opens when: vrmod_hub 1 and VR active (launcher sets this).
-- Auto-starts VR via existing vrmod_autostart (also set by launcher).
-- =============================================================================

vrmod = vrmod or {}
g_VR = g_VR or {}

local UID = "vr_hub"
local open = false
local buttons = {}
local statusMsg, statusUntil = "", 0

local W, H = 560, 640
local livePos, liveAng, liveScale = Vector(4, 3, 6), Angle(0, -90, 55), 0.028
local HEADER, PAD, ROW_H, FOOTER = 72, 16, 52, 56

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

local function WristHand()
	return (vrmod.GetSecondaryHand and vrmod.GetSecondaryHand()) or "left"
end

local function WristPose()
	local wrist = WristHand()
	if isfunction(VRUtilHandMenuPose) then
		return VRUtilHandMenuPose(W, H, 0.028, Vector(4, 3.5, 6), Angle(0, -90, 55), wrist)
	end
	return Vector(4, 3, 6), Angle(0, -90, 55), 0.028
end

local function SetStatus(msg, sec)
	statusMsg = tostring(msg or "")
	statusUntil = CurTime() + (sec or 2.5)
end

local function MenuItems()
	return {
		{ id = "resume", label = "Resume world", hint = "Close hub, keep VR" },
		{ id = "maps", label = "Play map…", hint = "Map browser" },
		{ id = "settings", label = "Settings", hint = "VR settings" },
		{ id = "bindings", label = "Controller bindings", hint = "OpenXR rebind" },
		{ id = "disconnect", label = "Disconnect", hint = "Leave server / map" },
		{ id = "quit", label = "Quit Garry's Mod", hint = "Exit game" },
	}
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

local function paint()
	if not open or not (g_VR and g_VR.menus and g_VR.menus[UID]) then return end
	if isfunction(VRUtilMenuRenderStart) then VRUtilMenuRenderStart(UID) end
	g_VR.menus[UID].dirty = true

	local T = Theme()
	local focused = g_VR.menuFocus == UID
	local mx, my = g_VR.menuCursorX or -1, g_VR.menuCursorY or -1
	rebuildButtons()

	if vrmod.cube and vrmod.cube.DrawChrome then
		vrmod.cube.DrawChrome(0, 0, W, H, "gVRMod", {
			subtitle = "VR hub · main menu replacement",
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
		draw.SimpleText("VR hub · main menu replacement", Font("CubeSmall") or "DermaDefault", PAD, 42, T.muted)
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
			draw.SimpleText(btn.item.label, Font("CubeLabel") or "DermaDefaultBold",
				btn.x + 18, btn.y + 16, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(btn.item.hint or "", "DermaDefault",
				btn.x + 18, btn.y + 36, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end

	local map = game.GetMap() or "?"
	draw.SimpleText("map: " .. map, "DermaDefault", PAD, H - 36, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	if statusMsg ~= "" and CurTime() < statusUntil then
		draw.SimpleText(statusMsg, Font("CubeLabel") or "DermaDefaultBold", W - PAD, H - 36, T.ok, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
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
				elseif id == "maps" then
					vrmod.VRHub_Close()
					timer.Simple(0.1, function()
						if isfunction(VRUtilCreateMapBrowserWindow) then
							VRUtilCreateMapBrowserWindow()
						else
							RunConsoleCommand("vrmod", "mapbrowser")
						end
					end)
				elseif id == "settings" then
					vrmod.VRHub_Close()
					timer.Simple(0.1, function()
						if vrmod.Settings_Open then vrmod.Settings_Open()
						elseif vrmod.CubeSettings_Open then vrmod.CubeSettings_Open()
						end
					end)
				elseif id == "bindings" then
					vrmod.VRHub_Close()
					timer.Simple(0.1, function()
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
		return
	end
	if open and g_VR.menus and g_VR.menus[UID] then
		g_VR.menus[UID].dirty = true
		return
	end
	if not isfunction(VRUtilMenuOpen) then return end

	-- Close competing shells
	if g_VR.menus then
		for _, uid in ipairs({ "miscmenu", "cube_settings", "heightmenu", "bindings_panel", "actions_panel" }) do
			if g_VR.menus[uid] and isfunction(VRUtilMenuClose) then
				g_VR.menus[uid].closeFunc = nil
				VRUtilMenuClose(uid)
			end
		end
	end

	open = true
	livePos, liveAng, liveScale = WristPose()
	VRUtilMenuOpen(UID, W, H, nil, true, livePos, liveAng, liveScale, true, function()
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
	if vrmod.MenuApplyHandAnchor then
		vrmod.MenuApplyHandAnchor(sm, liveScale, livePos, liveAng, WristHand())
	end

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
		if vrmod.MenuApplyHandAnchor and not g_VR.menus[UID].freeFloat then
			vrmod.MenuApplyHandAnchor(g_VR.menus[UID], liveScale, livePos, liveAng, WristHand())
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

-- Open hub after VR starts when hub mode is on
hook.Add("VRMod_Start", "vrmod_vr_hub", function(ply)
	if ply and ply ~= LocalPlayer() then return end
	if not HubEnabled() then return end
	timer.Simple(1.2, function()
		if not HubEnabled() then return end
		if not (g_VR and g_VR.active) then return end
		-- Don't fight experience onboarding on first run
		if vrmod.Experience_ShouldRun and vrmod.Experience_ShouldRun() then return end
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
