if SERVER then return end
-- =============================================================================
-- VR Pause Menu — project stock GMod GameUI into a wrist panel
--
-- ESC in VR: suppress desktop freeze, ActivateGameUI, keep sim unpaused,
-- bind real menu (CEF/VGUI) via panel2vr hand dock + laser.
-- Fallback: Cube hub if panel not found.
--
-- Quick menu "Pause Menu" opens the same path. "New Game" is maps only.
-- =============================================================================

vrmod = vrmod or {}
g_VR = g_VR or {}

local projecting = false
local unpauseId = "vrmod_gameui_project_unpause"
local rebindId = "vrmod_gameui_project_rebind"

local function vrLive()
	return g_VR and g_VR.active
end

local function G()
	return vrmod.GameUIProject
end

function vrmod.IsGameUIProjected()
	return projecting and vrLive()
end

function vrmod.CloseGameUIProjection()
	projecting = false
	g_VR._gameUIProjected = false
	timer.Remove(unpauseId)
	timer.Remove(rebindId)
	if G() and G().Unbind then G().Unbind() end
	if G() and G().HideStockUI then G().HideStockUI() end
	if vrmod.VRUnpauseWorld then vrmod.VRUnpauseWorld() end
end

--- Open stock pause/main GameUI projected into VR hand panel (unpaused).
function vrmod.OpenPauseMenuVR()
	if not vrLive() then
		-- Desktop: normal pause
		if gui and gui.ActivateGameUI then pcall(gui.ActivateGameUI) end
		return false
	end

	-- Toggle off if already open
	if projecting and G() and G().IsBound and G().IsBound() then
		vrmod.CloseGameUIProjection()
		return false
	end

	projecting = true
	g_VR._gameUIProjected = true

	if vrmod.VRUnpauseWorld then vrmod.VRUnpauseWorld() end
	pcall(function() RunConsoleCommand("sv_pausable", "0") end)
	pcall(function() RunConsoleCommand("unpause") end)

	-- Close Cube hub if open (avoid stacking)
	if vrmod.VRHub_IsOpen and vrmod.VRHub_IsOpen() and vrmod.VRHub_Close then
		vrmod.VRHub_Close()
	end

	if G() and G().ActivateStockUI then
		G().ActivateStockUI()
	elseif gui and gui.ActivateGameUI then
		pcall(gui.ActivateGameUI)
	end

	local function tryBind()
		if not projecting or not vrLive() then return false end
		local panel, meta = G().FindPanel()
		if not IsValid(panel) then return false end
		local uid = G().BindPanel(panel, { uid = "p2v_gameui_pause", place = "hand" })
		if uid then
			if vrmod.Toast then
				vrmod.Toast("Pause menu in VR — laser + trigger", 3, "hint")
			end
			print(string.format("[gVRMod] GameUI projected score=%s name=%s",
				tostring(meta and meta.score), tostring(meta and meta.name)))
			return true
		end
		return false
	end

	-- Soft-unpause while projected (GameUI wants to freeze SP)
	timer.Create(unpauseId, 0.1, 0, function()
		if not projecting or not vrLive() then
			timer.Remove(unpauseId)
			return
		end
		pcall(function() RunConsoleCommand("unpause") end)
		if gui and gui.EnableScreenClicker then
			pcall(function() gui.EnableScreenClicker(false) end)
		end
		-- Keep bound panel dirty for CEF
		local uid = G().GetBoundUid and G().GetBoundUid()
		if uid and g_VR.menus and g_VR.menus[uid] then
			g_VR.menus[uid].dirty = true
			g_VR.menus[uid].alwaysRedraw = true
		end
	end)

	-- Retry bind — CEF/GameUI often appears a few frames late
	local n = 0
	if not tryBind() then
		timer.Create(rebindId, 0.25, 16, function()
			n = n + 1
			if not projecting or not vrLive() then
				timer.Remove(rebindId)
				return
			end
			if tryBind() or n >= 16 then
				timer.Remove(rebindId)
				if n >= 16 and not (G().IsBound and G().IsBound()) then
					-- Fallback Cube hub (Resume / Settings / Disconnect)
					projecting = false
					g_VR._gameUIProjected = false
					timer.Remove(unpauseId)
					if vrmod.VRHub_Open then
						vrmod.VRHub_Open()
						if vrmod.Toast then
							vrmod.Toast("Stock pause UI not found — Cube menu", 3, "hint")
						end
					end
				end
			end
		end)
	end

	return true
end

-- ESC: project GameUI into VR instead of desktop freeze
hook.Add("OnPauseMenuShow", "vrmod_pause_project", function()
	if not vrLive() then return end -- desktop: stock pause
	vrmod.OpenPauseMenuVR()
	return true
end)

hook.Add("VRMod_Exit", "vrmod_pause_project_exit", function()
	vrmod.CloseGameUIProjection()
end)

-- Secondary fire / menu close while projected → close projection
hook.Add("VRMod_Input", "vrmod_pause_project_close", function(action, pressed)
	if not pressed or not projecting then return end
	if not vrLive() then return end
	if vrmod.IsMenuCloseAction and vrmod.IsMenuCloseAction(action) then
		vrmod.CloseGameUIProjection()
	end
end)

concommand.Add("vrmod_pause_menu", function()
	if not vrLive() then
		print("[gVRMod] Start VR first")
		return
	end
	if projecting then
		vrmod.CloseGameUIProjection()
	else
		vrmod.OpenPauseMenuVR()
	end
end)

concommand.Add("vrmod_pause_menu_status", function()
	local p, m = nil, nil
	if G() and G().FindPanel then p, m = G().FindPanel() end
	print(string.format("[gVRMod] project=%s bound=%s panel=%s score=%s",
		tostring(projecting),
		tostring(G() and G().IsBound and G().IsBound()),
		IsValid(p) and (p:GetName() or "?") or "nil",
		tostring(m and m.score)))
end)
