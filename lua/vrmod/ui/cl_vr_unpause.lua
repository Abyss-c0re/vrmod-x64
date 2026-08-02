if SERVER then return end
-- =============================================================================
-- VR pause policy
--
-- In VR: stock GameUI / ESC freezes SP and kills tracking — suppress + unpause.
-- Desktop (no VR): never touch pause menu or sv_pausable.
-- On VR exit: restore pausable so desktop ESC works again.
-- =============================================================================

vrmod = vrmod or {}

local PREV_PAUSABLE = nil

local function vrLive()
	return g_VR and g_VR.active
end

--- Hide GameUI and unpause world. Only while VR is active.
function vrmod.VRUnpauseWorld()
	if not vrLive() then return end
	if gui and gui.HideGameUI then
		pcall(gui.HideGameUI)
	end
	pcall(function() RunConsoleCommand("unpause") end)
	if gui and gui.EnableScreenClicker then
		pcall(function() gui.EnableScreenClicker(false) end)
	end
end

--- Open launcher hub without pausing the game (VR only).
function vrmod.OpenLauncherUnpaused()
	if not vrLive() then
		if vrmod.VRHub_Open then vrmod.VRHub_Open() end
		return
	end
	vrmod.VRUnpauseWorld()
	if vrmod.VRHub_OpenWhenReady then
		vrmod.VRHub_OpenWhenReady()
	elseif vrmod.VRHub_Open then
		vrmod.VRHub_Open()
	end
	timer.Simple(0.05, function() if vrLive() then vrmod.VRUnpauseWorld() end end)
	timer.Simple(0.25, function() if vrLive() then vrmod.VRUnpauseWorld() end end)
	timer.Simple(1.0, function()
		if not vrLive() then return end
		vrmod.VRUnpauseWorld()
		if vrmod.VRHub_IsOpen and not vrmod.VRHub_IsOpen() and vrmod.VRHub_Open then
			vrmod.VRHub_Open()
		end
	end)
end

--- Open New Game (Cube hand RT) without GameUI pause.
function vrmod.OpenNewGameUnpaused()
	if vrLive() then vrmod.VRUnpauseWorld() end
	if vrmod.VRNewGame_Open then
		vrmod.VRNewGame_Open()
	elseif vrmod.OpenNewGame then
		vrmod.OpenNewGame()
	elseif isfunction(VRUtilCreateMapBrowserWindow) then
		VRUtilCreateMapBrowserWindow()
	end
	if vrLive() then
		timer.Simple(0.05, function() if vrLive() then vrmod.VRUnpauseWorld() end end)
		timer.Simple(0.25, function() if vrLive() then vrmod.VRUnpauseWorld() end end)
	end
end

-- ESC only while VR is live — never block desktop pause outside VR
hook.Add("OnPauseMenuShow", "vrmod_no_sp_pause", function()
	if not vrLive() then return end -- desktop: allow stock pause
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
	return true -- suppress stock pause only in VR
end)

-- While VR is active, keep GameUI closed (it pauses SP)
hook.Add("Think", "vrmod_no_sp_pause_think", function()
	if not vrLive() then return end
	local t = CurTime()
	if (g_VR._unpauseCheck or 0) > t then return end
	g_VR._unpauseCheck = t + 0.35
	if gui and gui.IsGameUIVisible and gui.IsGameUIVisible() then
		vrmod.VRUnpauseWorld()
	end
end)

hook.Add("VRMod_Start", "vrmod_no_sp_pause_start", function(ply)
	if ply and IsValid(LocalPlayer()) and ply ~= LocalPlayer() then return end
	-- Remember desktop pausable; force off only for VR session
	local cv = GetConVar("sv_pausable")
	if cv then
		PREV_PAUSABLE = cv:GetString()
	end
	pcall(function() RunConsoleCommand("sv_pausable", "0") end)
	timer.Simple(0.1, function() if vrLive() then vrmod.VRUnpauseWorld() end end)
	timer.Simple(0.5, function() if vrLive() then vrmod.VRUnpauseWorld() end end)
end)

hook.Add("VRMod_Exit", "vrmod_restore_pausable", function(ply)
	if ply and IsValid(LocalPlayer()) and ply ~= LocalPlayer() then return end
	-- Restore desktop pause menu capability
	if PREV_PAUSABLE ~= nil then
		pcall(function() RunConsoleCommand("sv_pausable", tostring(PREV_PAUSABLE)) end)
		PREV_PAUSABLE = nil
	else
		pcall(function() RunConsoleCommand("sv_pausable", "1") end)
	end
	hook.Remove("Think", "vrmod_no_sp_pause_think")
	-- re-add Think for next VR session (hook still registered permanently; ok)
end)

concommand.Add("vrmod_unpause", function()
	vrmod.VRUnpauseWorld()
	print("[gVRMod] VRUnpauseWorld() active=" .. tostring(vrLive()))
end)
