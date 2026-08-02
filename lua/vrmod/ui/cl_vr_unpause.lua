if SERVER then return end
-- =============================================================================
-- VR pause policy (no stock GameUI while VR is live)
--
-- ActivateGameUI freezes SP; soft unpause cannot clear it reliably.
-- Pause UI in VR = Cube hub only. Desktop ESC untouched when not in VR.
-- =============================================================================

vrmod = vrmod or {}

local PREV_PAUSABLE = nil

local function vrLive()
	return g_VR and g_VR.active
end

--- Always hide GameUI + unpause while VR is active.
function vrmod.VRUnpauseWorld()
	if not vrLive() then return end
	g_VR._gameUIProjected = false
	if gui and gui.HideGameUI then pcall(gui.HideGameUI) end
	pcall(function() RunConsoleCommand("unpause") end)
	pcall(function() RunConsoleCommand("sv_pausable", "0") end)
	if gui and gui.EnableScreenClicker then
		pcall(function() gui.EnableScreenClicker(false) end)
	end
end

--- Pause menu path → Cube hub (see cl_vr_pausemenu).
function vrmod.OpenLauncherUnpaused()
	if not vrLive() then return end
	if vrmod.OpenPauseMenuVR then
		vrmod.OpenPauseMenuVR()
		return
	end
	vrmod.VRUnpauseWorld()
	if vrmod.VRHub_Open then vrmod.VRHub_Open() end
end

function vrmod.OpenNewGameUnpaused()
	if vrLive() then vrmod.VRUnpauseWorld() end
	if vrmod.VRNewGame_Open then
		vrmod.VRNewGame_Open()
	elseif vrmod.OpenNewGame then
		vrmod.OpenNewGame()
	end
	if vrLive() then
		timer.Simple(0.05, function() if vrLive() then vrmod.VRUnpauseWorld() end end)
	end
end

-- Do not register OnPauseMenuShow here — cl_vr_pausemenu owns ESC.

hook.Add("VRMod_Start", "vrmod_no_sp_pause_start", function(ply)
	if ply and IsValid(LocalPlayer()) and ply ~= LocalPlayer() then return end
	local cv = GetConVar("sv_pausable")
	if cv then PREV_PAUSABLE = cv:GetString() end
	pcall(function() RunConsoleCommand("sv_pausable", "0") end)
	timer.Simple(0.1, function() if vrLive() then vrmod.VRUnpauseWorld() end end)
	timer.Simple(0.5, function() if vrLive() then vrmod.VRUnpauseWorld() end end)
end)

hook.Add("VRMod_Exit", "vrmod_restore_pausable", function(ply)
	if ply and IsValid(LocalPlayer()) and ply ~= LocalPlayer() then return end
	if vrmod.CloseGameUIProjection then vrmod.CloseGameUIProjection() end
	g_VR._gameUIProjected = false
	if PREV_PAUSABLE ~= nil then
		pcall(function() RunConsoleCommand("sv_pausable", tostring(PREV_PAUSABLE)) end)
		PREV_PAUSABLE = nil
	else
		pcall(function() RunConsoleCommand("sv_pausable", "1") end)
	end
end)

concommand.Add("vrmod_unpause", function()
	vrmod.VRUnpauseWorld()
	print("[gVRMod] VRUnpauseWorld()")
end)
