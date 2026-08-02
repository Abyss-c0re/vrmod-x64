if SERVER then return end
-- =============================================================================
-- VR pause policy
--
-- In VR + GameUI projected: keep sim unpaused (do NOT HideGameUI).
-- In VR + no projection: hide stray GameUI, unpause.
-- Desktop (no VR): never touch pause / sv_pausable.
-- On VR exit: restore sv_pausable.
-- =============================================================================

vrmod = vrmod or {}

local PREV_PAUSABLE = nil

local function vrLive()
	return g_VR and g_VR.active
end

local function projecting()
	return g_VR and g_VR._gameUIProjected
end

--- Soft-unpause. When projecting GameUI, do not HideGameUI.
function vrmod.VRUnpauseWorld()
	if not vrLive() then return end
	if not projecting() then
		if gui and gui.HideGameUI then
			pcall(gui.HideGameUI)
		end
	end
	pcall(function() RunConsoleCommand("unpause") end)
	if gui and gui.EnableScreenClicker then
		pcall(function() gui.EnableScreenClicker(false) end)
	end
end

--- Pause menu (stock GameUI in VR panel) — not New Game.
function vrmod.OpenLauncherUnpaused()
	if not vrLive() then return end
	if vrmod.OpenPauseMenuVR then
		vrmod.OpenPauseMenuVR()
		return
	end
	-- Fallback Cube hub
	vrmod.VRUnpauseWorld()
	if vrmod.VRHub_OpenWhenReady then
		vrmod.VRHub_OpenWhenReady()
	elseif vrmod.VRHub_Open then
		vrmod.VRHub_Open()
	end
end

--- New Game only (maps / mode / multiplayer) — separate from pause menu.
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
	end
end

-- OnPauseMenuShow owned by cl_vr_pausemenu.lua (project GameUI).
-- This Think only cleans stray GameUI when NOT intentionally projecting.
hook.Add("Think", "vrmod_no_sp_pause_think", function()
	if not vrLive() then return end
	if projecting() then
		-- Still unpause while projected
		local t = CurTime()
		if (g_VR._unpauseCheck or 0) > t then return end
		g_VR._unpauseCheck = t + 0.15
		pcall(function() RunConsoleCommand("unpause") end)
		return
	end
	local t = CurTime()
	if (g_VR._unpauseCheck or 0) > t then return end
	g_VR._unpauseCheck = t + 0.35
	if gui and gui.IsGameUIVisible and gui.IsGameUIVisible() then
		vrmod.VRUnpauseWorld()
	end
end)

hook.Add("VRMod_Start", "vrmod_no_sp_pause_start", function(ply)
	if ply and IsValid(LocalPlayer()) and ply ~= LocalPlayer() then return end
	local cv = GetConVar("sv_pausable")
	if cv then PREV_PAUSABLE = cv:GetString() end
	pcall(function() RunConsoleCommand("sv_pausable", "0") end)
	timer.Simple(0.1, function() if vrLive() then vrmod.VRUnpauseWorld() end end)
end)

hook.Add("VRMod_Exit", "vrmod_restore_pausable", function(ply)
	if ply and IsValid(LocalPlayer()) and ply ~= LocalPlayer() then return end
	if vrmod.CloseGameUIProjection then vrmod.CloseGameUIProjection() end
	if PREV_PAUSABLE ~= nil then
		pcall(function() RunConsoleCommand("sv_pausable", tostring(PREV_PAUSABLE)) end)
		PREV_PAUSABLE = nil
	else
		pcall(function() RunConsoleCommand("sv_pausable", "1") end)
	end
end)

concommand.Add("vrmod_unpause", function()
	vrmod.VRUnpauseWorld()
	print("[gVRMod] VRUnpauseWorld() active=" .. tostring(vrLive()) .. " project=" .. tostring(projecting()))
end)
