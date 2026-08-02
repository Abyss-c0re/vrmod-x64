if SERVER then return end
-- =============================================================================
-- OpenXR native launcher handshake
--
-- gvrmod_launcher.sh writes garrysmod/data/vrmod/openxr_launch.txt before boot.
-- We force menu-first / hub + autostart and start VR without waiting for
-- +exec, CreateMove, player model, or "cursor not visible".
-- =============================================================================

vrmod = vrmod or {}
g_VR = g_VR or {}

local MARKER = "vrmod/openxr_launch.txt"
local applied = false
local startAttempts = 0
local MAX_START_ATTEMPTS = 40 -- ~20s @ 0.5s

local function log(fmt, ...)
	local msg = string.format(fmt, ...)
	print("[gVRMod][openxr-launch] " .. msg)
	if vrmod.logger then vrmod.logger.Info("[openxr-launch] " .. msg) end
end

local function parseMarker(raw)
	local t = {}
	for line in string.gmatch(raw or "", "[^\r\n]+") do
		local k, v = string.match(line, "^([%w_]+)%s*=%s*(.-)%s*$")
		if k then t[k] = v end
	end
	return t
end

local function setBoolCvar(name, val)
	local c = GetConVar(name)
	if c then
		pcall(function() c:SetBool(val and true or false) end)
		return
	end
	-- Create if missing (early boot before sh_startup)
	if not GetConVar(name) then
		CreateClientConVar(name, val and "1" or "0", true, FCVAR_ARCHIVE)
	end
	c = GetConVar(name)
	if c then pcall(function() c:SetBool(val and true or false) end) end
end

local function setStrCvar(name, val)
	local c = GetConVar(name)
	if c then
		pcall(function() c:SetString(tostring(val)) end)
		return
	end
	if not GetConVar(name) then
		CreateClientConVar(name, tostring(val), true, FCVAR_ARCHIVE)
	end
	c = GetConVar(name)
	if c then pcall(function() c:SetString(tostring(val)) end) end
end

--- Apply launch marker → convars. Returns true if this session is launcher-driven.
function vrmod.ApplyOpenXRLaunchMarker()
	if not file.Exists(MARKER, "DATA") then return false end
	local raw = file.Read(MARKER, "DATA") or ""
	local t = parseMarker(raw)
	if not t.mode and not t.autostart then return false end

	local mode = t.mode or "menu"
	local wantAuto = (t.autostart == "1" or t.autostart == "true")
	local wantMenu = (mode == "menu") or (t.menu_vr == "1")
	local wantHub = (mode == "hub") or (t.hub == "1")

	setStrCvar("vrmod_prefer_backend", t.prefer_backend or "openxr")
	setBoolCvar("vrmod_autostart", wantAuto)
	setBoolCvar("vrmod_menu_vr", wantMenu and not wantHub)
	setBoolCvar("vrmod_hub", wantHub)
	setBoolCvar("vrmod_require_window_focus", false)

	-- Consume marker so a normal Steam launch next time is clean
	pcall(function() file.Delete(MARKER) end)
	-- Keep a breadcrumb for debugging
	pcall(function()
		file.Write("vrmod/openxr_launch_last.txt",
			string.format("applied=%s mode=%s auto=%s\n", os.date("%Y-%m-%d %H:%M:%S"), mode, tostring(wantAuto)))
	end)

	applied = true
	g_VR._openxrLaunch = {
		mode = mode,
		autostart = wantAuto,
		menu = wantMenu,
		hub = wantHub,
		bg_map = t.bg_map or "gm_construct",
		map_mode = t.map_mode or "background",
		ts = tonumber(t.ts) or 0,
	}
	log("marker applied mode=%s autostart=%s menu_vr=%s hub=%s bg=%s/%s",
		mode, tostring(wantAuto), tostring(wantMenu), tostring(wantHub),
		tostring(t.map_mode or "background"), tostring(t.bg_map or "gm_construct"))
	return true
end

function vrmod.IsOpenXRLaunchSession()
	return applied or (g_VR and g_VR._openxrLaunch ~= nil)
end

local function forceStartVR()
	if g_VR and g_VR.active then return true end
	if not isfunction(VRUtilClientStart) then
		log("VRUtilClientStart missing (module not loaded?)")
		return false
	end
	startAttempts = startAttempts + 1
	log("force VRUtilClientStart attempt %d", startAttempts)
	local ok, err = pcall(VRUtilClientStart)
	if not ok then
		log("start error: %s", tostring(err))
		return false
	end
	return g_VR and g_VR.active
end

local function bootFromLaunch()
	-- Always try marker first (every client load)
	local had = vrmod.ApplyOpenXRLaunchMarker()
	if not had and not vrmod.IsOpenXRLaunchSession() then
		-- Also honor convars if cfg already set them
		local auto = GetConVar("vrmod_autostart")
		local menu = GetConVar("vrmod_menu_vr")
		local hub = GetConVar("vrmod_hub")
		if not ((auto and auto:GetBool()) and ((menu and menu:GetBool()) or (hub and hub:GetBool()))) then
			return
		end
		applied = true
		g_VR._openxrLaunch = g_VR._openxrLaunch or { mode = "cfg", autostart = true }
		log("boot from cfg convars (no marker)")
	end

	if not (g_VR._openxrLaunch and g_VR._openxrLaunch.autostart) then
		local auto = GetConVar("vrmod_autostart")
		if not (auto and auto:GetBool()) then return end
	end

	local function afterVRLive()
		log("VR active map=%s", tostring(game.GetMap and game.GetMap() or "?"))
		-- Launcher: always open hub (New Game + Settings). Also try freefloat GameUI.
		timer.Simple(0.5, function()
			if not (g_VR and g_VR.active) then return end
			if gui and gui.ActivateGameUI then pcall(gui.ActivateGameUI) end
			if isfunction(vrmod.BindMainMenuToVR) then
				pcall(vrmod.BindMainMenuToVR)
			end
			-- Hub has New Game (extended map/mode/settings) + VR Settings — primary launcher UI
			if vrmod.VRHub_Open then
				timer.Simple(0.4, function()
					if g_VR and g_VR.active and vrmod.VRHub_Open then
						pcall(vrmod.VRHub_Open)
					end
				end)
			end
		end)
	end

	timer.Create("vrmod_openxr_launch_start", 0.5, 0, function()
		if g_VR and g_VR.active then
			timer.Remove("vrmod_openxr_launch_start")
			afterVRLive()
			return
		end
		if startAttempts >= MAX_START_ATTEMPTS then
			timer.Remove("vrmod_openxr_launch_start")
			log("gave up after %d attempts — check WiVRn / HMD / vrmod_debug.log", startAttempts)
			if vrmod.Toast then
				vrmod.Toast("OpenXR VR start failed — WiVRn + headset connected?", 8, "error")
			end
			return
		end
		-- Prefer start once LocalPlayer exists (bg map / full map). Still try early.
		local ply = LocalPlayer()
		if IsValid(ply) then
			local pm = ply.GetModel and ply:GetModel() or nil
			if pm and pm ~= "" and pm ~= "models/player.mdl" then
				forceStartVR()
				return
			end
		end
		-- Early / menu-only attempt every other tick
		if startAttempts % 2 == 0 then
			forceStartVR()
		else
			startAttempts = startAttempts + 1
		end
	end)
end

-- Earliest reliable client tick
hook.Add("Think", "vrmod_openxr_launch_boot", function()
	hook.Remove("Think", "vrmod_openxr_launch_boot")
	timer.Simple(0.2, bootFromLaunch)
end)

-- map_background gm_construct (or full map): world is ready → force VR
hook.Add("InitPostEntity", "vrmod_openxr_launch_map", function()
	if file.Exists(MARKER, "DATA") then
		vrmod.ApplyOpenXRLaunchMarker()
	end
	local want = vrmod.IsOpenXRLaunchSession()
		or (GetConVar("vrmod_autostart") and GetConVar("vrmod_autostart"):GetBool())
	if not want then return end
	log("InitPostEntity map=%s — force VR (bg/full world ready)", tostring(game.GetMap and game.GetMap() or "?"))
	timer.Simple(0.8, function()
		if g_VR and g_VR.active then return end
		forceStartVR()
	end)
	timer.Simple(2.0, function()
		if g_VR and g_VR.active then return end
		forceStartVR()
	end)
end)

concommand.Add("vrmod_openxr_launch_status", function()
	print(string.format("[gVRMod] launchSession=%s applied=%s active=%s attempts=%d marker=%s",
		tostring(vrmod.IsOpenXRLaunchSession()),
		tostring(applied),
		tostring(g_VR and g_VR.active),
		startAttempts,
		tostring(file.Exists(MARKER, "DATA"))))
	if g_VR and g_VR._openxrLaunch then
		PrintTable(g_VR._openxrLaunch)
	end
end)
