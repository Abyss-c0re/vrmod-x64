if SERVER then return end
-- =============================================================================
-- VR Pause Menu
--
-- NEVER ActivateGameUI in VR — it freezes singleplayer and soft-unpause cannot
-- reliably clear it (user stuck paused, ESC re-opens forever).
--
-- ESC / Quick Menu "Pause Menu" → Cube hub (Resume · New Game · Settings…).
-- Stock GameUI is always hidden while VR is live.
-- =============================================================================

vrmod = vrmod or {}
g_VR = g_VR or {}

local function vrLive()
	return g_VR and g_VR.active
end

local function forceUnpause()
	-- Kill any projection flag so HideGameUI is allowed
	g_VR._gameUIProjected = false
	if gui and gui.HideGameUI then pcall(gui.HideGameUI) end
	pcall(function() RunConsoleCommand("unpause") end)
	pcall(function() RunConsoleCommand("sv_pausable", "0") end)
	if gui and gui.EnableScreenClicker then
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

	-- Shared pipeline with launcher (module virtual monitor + hub present)
	if vrmod.VirtualDisplay and vrmod.VirtualDisplay.PresentPause then
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

-- ESC: Cube pause hub; block stock menu entirely in VR
hook.Add("OnPauseMenuShow", "vrmod_pause_project", function()
	if not vrLive() then return end
	forceUnpause()
	timer.Simple(0, function()
		if not vrLive() then return end
		forceUnpause()
		vrmod.OpenPauseMenuVR()
	end)
	return true
end)

-- While VR is live: never leave GameUI up (it re-pauses every frame)
hook.Add("Think", "vrmod_force_no_gameui", function()
	if not vrLive() then return end
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
