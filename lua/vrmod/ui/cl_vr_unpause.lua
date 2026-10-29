if SERVER then return end
-- =============================================================================
-- VR pause policy (no stock GameUI while VR is live)
--
-- Cube hub is the VR pause. Shift+ESC opens the stock menu; do not hide it then.
-- Desktop ESC is untouched when VR is off.
-- =============================================================================

vrmod = vrmod or {}

local PREV_PAUSABLE = nil

local function vrLive()
	return g_VR and g_VR.active
end

--- Shared inputs for the unpause gate (quit, Shift, stock pause).
function vrmod.UnpausePolicyOpts()
	g_VR = g_VR or {}
	local shift = false
	if input and input.IsKeyDown then
		shift = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT) or false
	end
	return {
		quitting = g_VR._quitting and true or false,
		shift_down = shift and true or false,
		stock_pause = g_VR._stockPause and true or false,
	}
end

--- Quit Garry's Mod from a VR menu. QuitNoConfirm does not leave a dialog
--- for the unpause hook to dismiss.
function vrmod.RequestQuitGame()
	g_VR = g_VR or {}
	g_VR._quitting = true
	local cmd, arg = "gamemenucommand", "QuitNoConfirm"
	if vrmod.utils and vrmod.utils.MenuLaw_QuitArgs then
		cmd, arg = vrmod.utils.MenuLaw_QuitArgs()
	end
	pcall(function() RunConsoleCommand(cmd, arg) end)
	pcall(function() RunConsoleCommand("quit") end)
end

--- Always hide GameUI + unpause while VR is active.
function vrmod.VRUnpauseWorld()
	if not vrLive() then return end
	local allow = true
	local opts = vrmod.UnpausePolicyOpts and vrmod.UnpausePolicyOpts() or { quitting = g_VR._quitting }
	if vrmod.utils and vrmod.utils.MenuLaw_AllowForceUnpause then
		allow = vrmod.utils.MenuLaw_AllowForceUnpause(opts)
	elseif opts.quitting or opts.shift_down or opts.stock_pause then
		allow = false
	end
	if not allow then return end
	g_VR._gameUIProjected = false
	if gui and gui.HideGameUI then pcall(gui.HideGameUI) end
	pcall(function() RunConsoleCommand("unpause") end)
	pcall(function() RunConsoleCommand("sv_pausable", "0") end)
	local derma = false
	if g_VR.menuFocus and g_VR.menus and g_VR.menus[g_VR.menuFocus] then
		local m = g_VR.menus[g_VR.menuFocus]
		derma = m.panel and IsValid(m.panel) or false
	end
	local keepClick = vrmod.utils and vrmod.utils.MenuLaw_KeepScreenClicker
		and vrmod.utils.MenuLaw_KeepScreenClicker({ derma_focused = derma })
	if gui and gui.EnableScreenClicker and not keepClick then
		pcall(function() gui.EnableScreenClicker(false) end)
	end
end

--- Native Cube launcher surface (not a toggle — always open hub).
function vrmod.OpenLauncherUnpaused()
	if not vrLive() then return end
	vrmod.VRUnpauseWorld()
	-- Prefer direct hub open; OpenPauseMenuVR toggles and can close an open hub
	if vrmod.VRHub_IsOpen and vrmod.VRHub_IsOpen() then return end
	if vrmod.VRHub_Open then
		vrmod.VRHub_Open()
	elseif vrmod.VRHub_OpenWhenReady then
		vrmod.VRHub_OpenWhenReady()
	elseif vrmod.OpenPauseMenuVR then
		vrmod.OpenPauseMenuVR()
	end
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
