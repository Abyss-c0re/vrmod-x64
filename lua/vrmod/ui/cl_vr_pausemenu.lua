if SERVER then return end
-- =============================================================================
-- VR Pause Menu
--
-- ESC opens the Cube hub. Shift+ESC is the stock pause (sv_pausable stays 0
-- otherwise, so the engine never delivers the pause menu and Shift did nothing).
--
-- Quick Menu "Pause Menu" → Cube hub (Resume · New Game · Settings…).
-- Stock GameUI stays hidden unless Shift is holding the pause open.
-- =============================================================================

vrmod = vrmod or {}
g_VR = g_VR or {}

local function vrLive()
	return g_VR and g_VR.active
end

local function policyOpts()
	if vrmod.UnpausePolicyOpts then return vrmod.UnpausePolicyOpts() end
	return { quitting = g_VR and g_VR._quitting and true or false }
end

local function forceUnpause()
	local opts = policyOpts()
	local allow = true
	if vrmod.utils and vrmod.utils.MenuLaw_AllowForceUnpause then
		allow = vrmod.utils.MenuLaw_AllowForceUnpause(opts)
	elseif opts.quitting or opts.shift_down or opts.stock_pause then
		allow = false
	end
	if not allow then return end
	-- Kill any projection flag so HideGameUI is allowed
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
	if vrmod.GameUIProject and vrmod.GameUIProject.Unbind then
		pcall(vrmod.GameUIProject.Unbind)
	end
	if vrmod.GameUIProject and vrmod.GameUIProject.HideStockUI then
		pcall(vrmod.GameUIProject.HideStockUI)
	end
end

function vrmod.IsGameUIProjected()
	return false -- projection disabled (breaks pause)
end

function vrmod.CloseGameUIProjection()
	forceUnpause()
	timer.Remove("vrmod_gameui_project_unpause")
	timer.Remove("vrmod_gameui_project_rebind")
	if vrmod.VRUnpauseWorld then vrmod.VRUnpauseWorld() end
end

--- ESC / pause in VR: VirtualDisplay "pause" session → Cube hub (never stock GameUI).
function vrmod.OpenPauseMenuVR()
	if not vrLive() then
		if gui and gui.ActivateGameUI then pcall(gui.ActivateGameUI) end
		return false
	end

	forceUnpause()

	-- Toggle: if hub already open, close (Resume)
	if vrmod.VRHub_IsOpen and vrmod.VRHub_IsOpen() then
		if vrmod.VirtualDisplay and vrmod.VirtualDisplay.Close then
			pcall(vrmod.VirtualDisplay.Close, "pause")
		end
		if vrmod.VRHub_Close then vrmod.VRHub_Close() end
		forceUnpause()
		return false
	end

	-- One surface only (OpenSoleHub closes QM / stacked shells first)
	if vrmod.OpenSoleHub then
		vrmod.OpenSoleHub()
	elseif vrmod.VirtualDisplay and vrmod.VirtualDisplay.PresentPause then
		vrmod.VirtualDisplay.PresentPause({
			onClose = forceUnpause,
		})
	elseif vrmod.VRHub_Open then
		vrmod.VRHub_Open()
	elseif vrmod.VRHub_OpenWhenReady then
		vrmod.VRHub_OpenWhenReady()
	end

	-- Extra unpause after hub open (belt and suspenders)
	timer.Simple(0, forceUnpause)
	timer.Simple(0.1, forceUnpause)
	timer.Simple(0.3, forceUnpause)
	return true
end

--- ESC. fromPauseHook=true when the engine is already opening the menu.
--- Returns true when the stock menu must be blocked.
local function onEsc(fromPauseHook)
	if not vrLive() then return false end
	local opts = policyOpts()
	opts.vr_active = true
	local action = "hub"
	if vrmod.utils and vrmod.utils.MenuLaw_EscAction then
		action = vrmod.utils.MenuLaw_EscAction(opts)
	elseif opts.shift_down or opts.stock_pause then
		action = "stock"
	end
	if action == "stock" then
		g_VR._stockPause = true
		pcall(function() RunConsoleCommand("sv_pausable", "1") end)
		-- Shift was pressed so the engine can show the menu. If this key was
		-- swallowed while pausable was still 0, open it here. The pause hook
		-- means the engine is already doing that.
		if not fromPauseHook and g_VR._pauseHookFrame ~= FrameNumber() then
			local visible = gui and gui.IsGameUIVisible and gui.IsGameUIVisible()
			if not visible and gui and gui.ActivateGameUI then
				pcall(gui.ActivateGameUI)
			end
		end
		return false
	end
	if g_VR._escHandledFrame == FrameNumber() then return true end
	g_VR._escHandledFrame = FrameNumber()
	vrmod.OpenPauseMenuVR()
	return true
end

-- ESC: Cube hub. Shift+ESC: stock pause (do not swallow it).
hook.Add("OnPauseMenuShow", "vrmod_pause_project", function()
	if not vrLive() then return end
	g_VR._pauseHookFrame = FrameNumber()
	if onEsc(true) then return true end
end)

hook.Add("PlayerButtonDown", "vrmod_esc_pause", function(ply, btn)
	if not vrLive() then return end
	if ply ~= LocalPlayer() then return end
	if btn == KEY_LSHIFT or btn == KEY_RSHIFT then
		-- Arm pausable before ESC so this hold is not ignored.
		g_VR._shiftWasDown = true
		pcall(function() RunConsoleCommand("sv_pausable", "1") end)
		return
	end
	if btn ~= KEY_ESCAPE then return end
	onEsc(false)
end)

-- While VR is live: hide GameUI unless Shift or a stock pause is holding it.
hook.Add("Think", "vrmod_force_no_gameui", function()
	if not vrLive() then return end
	local opts = policyOpts()
	local shift = opts.shift_down and true or false
	if shift and not g_VR._shiftWasDown then
		pcall(function() RunConsoleCommand("sv_pausable", "1") end)
	end
	if (not shift) and g_VR._shiftWasDown and not g_VR._stockPause then
		pcall(function() RunConsoleCommand("sv_pausable", "0") end)
	end
	g_VR._shiftWasDown = shift
	if g_VR._stockPause and gui and gui.IsGameUIVisible and not gui.IsGameUIVisible() then
		g_VR._stockPause = false
		opts.stock_pause = false
		if not shift then
			pcall(function() RunConsoleCommand("sv_pausable", "0") end)
		end
	end
	if vrmod.utils and vrmod.utils.MenuLaw_AllowForceUnpause
		and not vrmod.utils.MenuLaw_AllowForceUnpause(opts) then
		return
	end
	local t = CurTime()
	if (g_VR._forceUnpauseT or 0) > t then return end
	g_VR._forceUnpauseT = t + 0.2
	if gui and gui.IsGameUIVisible and gui.IsGameUIVisible() then
		forceUnpause()
	else
		pcall(function() RunConsoleCommand("unpause") end)
	end
end)

hook.Add("VRMod_Exit", "vrmod_pause_project_exit", function()
	forceUnpause()
	timer.Remove("vrmod_gameui_project_unpause")
	timer.Remove("vrmod_gameui_project_rebind")
end)

hook.Add("VRMod_Input", "vrmod_pause_project_close", function(action, pressed)
	if not pressed or not vrLive() then return end
	-- Secondary: close hub if open
	if vrmod.IsMenuCloseAction and vrmod.IsMenuCloseAction(action) then
		if vrmod.VRHub_IsOpen and vrmod.VRHub_IsOpen() and vrmod.VRHub_Close then
			vrmod.VRHub_Close()
			forceUnpause()
		end
	end
end)

concommand.Add("vrmod_pause_menu", function()
	if not vrLive() then
		print("[gVRMod] Start VR first (desktop: use ESC)")
		return
	end
	vrmod.OpenPauseMenuVR()
end)

concommand.Add("vrmod_force_unpause", function()
	forceUnpause()
	if vrmod.VRHub_Close then vrmod.VRHub_Close() end
	print("[gVRMod] force unpause + close hub")
end)

concommand.Add("vrmod_pause_menu_status", function()
	print(string.format("[gVRMod] vr=%s gameui=%s hub=%s",
		tostring(vrLive()),
		tostring(gui and gui.IsGameUIVisible and gui.IsGameUIVisible()),
		tostring(vrmod.VRHub_IsOpen and vrmod.VRHub_IsOpen())))
end)
