if SERVER then return end
-- =============================================================================
-- VR must never rely on Source GameUI / SP pause.
--
-- Activating the desktop main menu or ESC pause freezes the simulation in
-- singleplayer → tracking/input feel "dead". Launcher + hub + New Game are
-- pure VR surfaces (panel2vr / VRUtilMenuOpen) with world still running.
-- =============================================================================

vrmod = vrmod or {}

local function vrLive()
	return g_VR and g_VR.active
end

--- Hide GameUI and unpause world. Safe to call often.
function vrmod.VRUnpauseWorld()
	if not vrLive() then return end
	if gui and gui.HideGameUI then
		pcall(gui.HideGameUI)
	end
	-- SP: GameUI open freezes sim; force unpause if engine exposed it
	if gui and gui.IsGameUIVisible and gui.IsGameUIVisible() then
		pcall(gui.HideGameUI)
	end
	-- Best-effort; harmless if not paused
	pcall(function()
		RunConsoleCommand("unpause")
	end)
	pcall(function()
		RunConsoleCommand("sv_pausable", "0")
	end)
	-- Never leave desktop cursor capturing while in VR (breaks laser menus)
	if gui and gui.EnableScreenClicker and not (vgui and vgui.CursorVisible and vgui.CursorVisible() and not g_VR.active) then
		-- Only force off when VR menus own input (no desktop derma clicker needed)
		if not (vgui and vgui.GetHoveredPanel and IsValid(vgui.GetHoveredPanel()) and not (g_VR.menus and next(g_VR.menus))) then
			-- Keep clicker off for VR-only surfaces
		end
	end
	if gui and gui.EnableScreenClicker then
		-- VR laser path does not need screen clicker
		local anyDesktopPopup = false
		-- Prefer off always in VR for launcher flow
		pcall(function() gui.EnableScreenClicker(false) end)
	end
end

--- Open launcher hub without pausing the game.
function vrmod.OpenLauncherUnpaused()
	vrmod.VRUnpauseWorld()
	if vrmod.VRHub_Open then
		vrmod.VRHub_Open()
	end
	-- Unpause again after derma/open races
	timer.Simple(0.05, vrmod.VRUnpauseWorld)
	timer.Simple(0.25, vrmod.VRUnpauseWorld)
end

--- Open New Game (map/mode/settings) without GameUI pause.
function vrmod.OpenNewGameUnpaused()
	vrmod.VRUnpauseWorld()
	if vrmod.OpenNewGame then
		vrmod.OpenNewGame()
	elseif isfunction(VRUtilCreateMapBrowserWindow) then
		VRUtilCreateMapBrowserWindow()
	end
	timer.Simple(0.05, vrmod.VRUnpauseWorld)
	timer.Simple(0.25, vrmod.VRUnpauseWorld)
end

-- ESC / pause menu: swallow stock UI, open VR launcher instead
hook.Add("OnPauseMenuShow", "vrmod_no_sp_pause", function()
	if not vrLive() then return end
	vrmod.VRUnpauseWorld()
	timer.Simple(0, function()
		if not vrLive() then return end
		vrmod.VRUnpauseWorld()
		if vrmod.OpenLauncherUnpaused then
			vrmod.OpenLauncherUnpaused()
		elseif vrmod.VRHub_Open then
			vrmod.VRHub_Open()
		end
	end)
	return true -- prevent stock pause menu
end)

-- While VR is active, keep GameUI closed (it pauses SP)
hook.Add("Think", "vrmod_no_sp_pause_think", function()
	if not vrLive() then return end
	-- Throttle: every ~0.25s
	local t = CurTime()
	if (g_VR._unpauseCheck or 0) > t then return end
	g_VR._unpauseCheck = t + 0.25
	if gui and gui.IsGameUIVisible and gui.IsGameUIVisible() then
		vrmod.VRUnpauseWorld()
	end
end)

hook.Add("VRMod_Start", "vrmod_no_sp_pause_start", function(ply)
	if ply and IsValid(LocalPlayer()) and ply ~= LocalPlayer() then return end
	RunConsoleCommand("sv_pausable", "0")
	timer.Simple(0.1, vrmod.VRUnpauseWorld)
	timer.Simple(0.5, vrmod.VRUnpauseWorld)
	timer.Simple(1.0, vrmod.VRUnpauseWorld)
end)

concommand.Add("vrmod_unpause", function()
	vrmod.VRUnpauseWorld()
	print("[gVRMod] VRUnpauseWorld()")
end)
