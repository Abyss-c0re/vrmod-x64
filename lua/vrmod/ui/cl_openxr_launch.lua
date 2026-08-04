if SERVER then return end
-- =============================================================================
-- OpenXR native launcher handshake
--
-- gvrmod_launcher.sh writes garrysmod/data/vrmod/openxr_launch.txt before boot.
-- Goal: HMD is primary — force OpenXR VR + Cube hub (native launcher UI).
-- Desktop window is only a tiny mirror. Never wait on GameUI / cursor.
-- =============================================================================

vrmod = vrmod or {}
g_VR = g_VR or {}

local MARKER = "vrmod/openxr_launch.txt"
local applied = false
local startAttempts = 0
local hubAttempts = 0
local MAX_START_ATTEMPTS = 60 -- ~30s @ 0.5s
local launchedUI = false

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

--- Apply launch marker → convars. Marker kept until VR is live (retry-safe).
function vrmod.ApplyOpenXRLaunchMarker()
	if not file.Exists(MARKER, "DATA") then return false end
	local raw = file.Read(MARKER, "DATA") or ""
	local t = parseMarker(raw)
	if not t.mode and not t.autostart then return false end

	-- Native Cube launcher is the product. "menu" still opens hub (not stock GameUI).
	local mode = t.mode or "hub"
	if mode == "menu" then mode = "hub" end
	local wantAuto = (t.autostart == "1" or t.autostart == "true" or t.autostart == nil)
	local wantHub = true

	setStrCvar("vrmod_prefer_backend", t.prefer_backend or "openxr")
	setBoolCvar("vrmod_autostart", wantAuto)
	setBoolCvar("vrmod_menu_vr", false) -- never chase stock MainMenu cinema
	setBoolCvar("vrmod_hub", true)
	setBoolCvar("vrmod_require_window_focus", false)
	setBoolCvar("vrmod_laserpointer", true)

	pcall(function()
		file.Write("vrmod/openxr_launch_last.txt",
			string.format("applied=%s mode=%s auto=%s\n", os.date("%Y-%m-%d %H:%M:%S"), mode, tostring(wantAuto)))
	end)

	local nativeWrapper = (t.native_wrapper == "1" or t.native_wrapper == "true")
	applied = true
	g_VR._openxrLaunch = {
		mode = mode,
		autostart = wantAuto,
		menu = false,
		hub = wantHub,
		bg_map = t.bg_map or "gm_construct",
		map_mode = t.map_mode or "full",
		native_wrapper = nativeWrapper,
		ts = tonumber(t.ts) or 0,
	}
	log("marker applied mode=%s autostart=%s native_wrapper=%s hub=1 (native Cube launcher)",
		mode, tostring(wantAuto), tostring(nativeWrapper))
	return true
end

local function consumeMarker()
	if file.Exists(MARKER, "DATA") then
		pcall(function() file.Delete(MARKER) end)
	end
end

function vrmod.IsOpenXRLaunchSession()
	return applied or (g_VR and g_VR._openxrLaunch ~= nil)
end

--- True when Start came from cube_webui / gvrmod_launcher (marker native_wrapper=1).
function vrmod.IsNativeWrapperLaunch()
	if g_VR and g_VR._openxrLaunch and g_VR._openxrLaunch.native_wrapper then
		return true
	end
	-- Marker may still be on disk before apply; treat as wrapper product path
	if file.Exists(MARKER, "DATA") then
		local raw = file.Read(MARKER, "DATA") or ""
		if string.find(raw, "native_wrapper=1", 1, true)
			or string.find(raw, "native_wrapper=true", 1, true) then
			return true
		end
	end
	return false
end

local function writeStatus(line)
	pcall(function()
		file.Write("vrmod/cube_launch_status.txt",
			string.format("%s | %s | active=%s attempts=%d\n",
				os.date("%H:%M:%S"), line,
				tostring(g_VR and g_VR.active), startAttempts))
	end)
end

--- Signal native cube_webui_launcher to release OpenXR (seamless handoff, no black gap).
local function writeHandoff(phase)
	pcall(function()
		file.Write("vrmod/cube_handoff.txt",
			string.format("phase=%s\nts=%d\n", tostring(phase), os.time()))
	end)
end

local handoffSignaled = false
local handoffDelayUntil = 0

local function forceStartVR()
	if g_VR and g_VR.active then
		writeHandoff("vr_active")
		return true
	end
	-- Ensure module is loaded (openxr_launch can run before core finishes require)
	if not isfunction(VRUtilClientStart) then
		if vrmod.LoadNativeModule then pcall(vrmod.LoadNativeModule) end
	end
	if not isfunction(VRUtilClientStart) then
		log("VRUtilClientStart missing (module not loaded yet)")
		writeStatus("wait_module")
		writeHandoff("wait_module")
		return false
	end

	-- Ask native launcher to drop OpenXR first (only one session). Wait ~1.2s once.
	if not handoffSignaled then
		handoffSignaled = true
		-- Native orderly release needs room for xrRequestExitSession + STOPPING (research-3 race)
		handoffDelayUntil = CurTime() + 2.5
		writeHandoff("take_xr")
		writeStatus("take_xr_signaled")
		log("signaled cube_webui take_xr — waiting for native to release session (2.5s)")
		return false
	end
	if CurTime() < handoffDelayUntil then
		writeStatus("wait_native_release")
		return false
	end

	startAttempts = startAttempts + 1
	log("force VRUtilClientStart attempt %d", startAttempts)
	writeStatus("start_attempt_" .. tostring(startAttempts))
	writeHandoff("starting_xr")
	-- Always force — loading screen has cursor; normal vrmod_start waits forever
	if isfunction(RunConsoleCommand) then
		pcall(RunConsoleCommand, "vrmod_start", "force")
	end
	local ok, err = pcall(VRUtilClientStart)
	if not ok then
		log("start error: %s", tostring(err))
		writeStatus("error_" .. tostring(err))
		return false
	end
	if g_VR and g_VR.active then
		writeStatus("vr_active")
		writeHandoff("vr_active")
		pcall(function() file.Write("vrmod/cube_ready.txt", "ready=1\n") end)
		return true
	end
	writeStatus("start_returned_inactive")
	return false
end

--- Native VR launcher UI (Cube hub) — automatic product surface.
-- Never stock GameUI. Never requires a concommand.
-- Do NOT call OpenPauseMenuVR (toggle can close an already-open hub).
local function openNativeLauncherUI()
	if not (g_VR and g_VR.active) then return false end
	if vrmod.VRUnpauseWorld then pcall(vrmod.VRUnpauseWorld) end

	if vrmod.VRHub_IsOpen and vrmod.VRHub_IsOpen() then
		launchedUI = true
		return true
	end

	-- Direct open only (no pause-menu toggle path)
	if vrmod.VRHub_Open then
		pcall(vrmod.VRHub_Open)
	elseif vrmod.VRHub_OpenWhenReady then
		pcall(vrmod.VRHub_OpenWhenReady)
	end

	if vrmod.VRHub_IsOpen and vrmod.VRHub_IsOpen() then
		launchedUI = true
		log("Cube hub open — native VR launcher")
		return true
	end

	hubAttempts = hubAttempts + 1
	if hubAttempts <= 12 then
		log("hub not open yet (try %d)", hubAttempts)
	end
	return false
end

-- G03: read Cube shell STAGE pack (continuity data only — never auto-apply height/origin).
local stagePackNotified = false
local function noteStagePackOnce()
	if stagePackNotified then return end
	stagePackNotified = true
	if not (vrmod.utils and vrmod.utils.StagePack_Parse) then return end
	local raw
	pcall(function()
		if file and file.Exists and file.Exists("vrmod/cube_stage_pack.txt", "DATA") then
			raw = file.Read("vrmod/cube_stage_pack.txt", "DATA")
		end
	end)
	if not raw or raw == "" then
		log("no cube_stage_pack.txt (cold start without Cube shell pack)")
		return
	end
	local pack = vrmod.utils.StagePack_Parse(raw)
	if not pack or not vrmod.utils.StagePack_IsUsable(pack) then
		log("stage pack present but unusable")
		return
	end
	g_VR._cubeStagePack = pack
	-- G03 apply gate + plan + careful executor (default OFF; opt-in convar/file)
	local measuredY
	pcall(function()
		local hmd = g_VR.tracking and g_VR.tracking.hmd
		-- tracking poses are Source units; pack is meters — skip measured if we can't convert safely
		if hmd and hmd.pos and g_VR.scale and g_VR.scale > 1 then
			measuredY = hmd.pos.z / g_VR.scale
		end
	end)
	-- Opt-in only: vrmod_stage_apply 1 or DATA/vrmod/stage_apply_enable.txt
	local allowApply = false
	if vrmod.utils.StagePack_AllowApplyFromFlags then
		local conOn, fileOn = false, false
		pcall(function()
			if not GetConVar("vrmod_stage_apply") then
				CreateClientConVar("vrmod_stage_apply", "0", true, FCVAR_ARCHIVE,
					"G03 careful Cube stage height apply (0=off)")
			end
			local c = GetConVar("vrmod_stage_apply")
			if c then conOn = c:GetBool() end
		end)
		pcall(function()
			if file and file.Exists and file.Exists("vrmod/stage_apply_enable.txt", "DATA") then
				fileOn = true
			end
		end)
		allowApply = vrmod.utils.StagePack_AllowApplyFromFlags({
			convar_on = conOn,
			file_enable = fileOn,
		})
	end
	local decision = vrmod.utils.StagePack_ApplyDecision(pack, {
		measured_head_y_m = measuredY,
		allow_apply = allowApply,
	})
	g_VR._cubeStagePackApply = decision
	local curSeat = 0
	pcall(function()
		local cv = GetConVar and GetConVar("vrmod_seatedoffset")
		if cv then curSeat = cv:GetFloat() end
	end)
	local plan = (vrmod.utils.StagePack_ComputeApplyPlan and vrmod.utils.StagePack_ComputeApplyPlan(pack, decision, {
		world_scale = (g_VR.scale and g_VR.scale > 1) and g_VR.scale or 40,
		current_seatedoffset = curSeat,
		allow_apply = allowApply,
	})) or nil
	g_VR._cubeStagePackPlan = plan
	local muts = (plan and vrmod.utils.StagePack_MutationsFromPlan and vrmod.utils.StagePack_MutationsFromPlan(plan)) or {}
	g_VR._cubeStagePackMutations = muts
	-- Careful executor: only when plan armed + allow (mutations non-empty)
	local execRes
	if vrmod.utils.StagePack_ShouldExecutePlan
		and vrmod.utils.StagePack_ShouldExecutePlan(plan, allowApply)
		and #muts > 0
		and vrmod.utils.StagePack_ExecuteMutations then
		execRes = vrmod.utils.StagePack_ExecuteMutations(muts, function(name, val)
			local cv = GetConVar(name)
			if not cv then return false, "missing_" .. tostring(name) end
			local ok = pcall(function() cv:SetFloat(tonumber(val) or 0) end)
			if not ok then return false, "set_fail_" .. tostring(name) end
			-- Keep seated hook in sync if present
			if name == "vrmod_seatedoffset" and vrmod.UpdateSeatedOffset then
				pcall(vrmod.UpdateSeatedOffset)
			end
			return true
		end)
		g_VR._cubeStagePackExec = execRes
		log("stage pack execute applied=%s ok=%s allow=%s",
			tostring(execRes and execRes.applied), tostring(execRes and execRes.ok), tostring(allowApply))
	end
	local hint = (execRes and vrmod.utils.StagePack_ExecuteToast and vrmod.utils.StagePack_ExecuteToast(execRes, plan))
		or (plan and vrmod.utils.StagePack_PlanToast and vrmod.utils.StagePack_PlanToast(plan))
		or (vrmod.utils.StagePack_ApplyToast and vrmod.utils.StagePack_ApplyToast(decision))
		or vrmod.utils.StagePack_ToastHint(pack)
	local expect = (vrmod.utils.StagePack_HmdExpect
		and vrmod.utils.StagePack_HmdExpect(decision, plan, execRes)) or nil
	g_VR._cubeStagePackHmdExpect = expect
	if expect and expect.checklist then
		log("G03 HMD %s", tostring(expect.checklist))
	end
	log("stage pack ok space=%s head_ok=%s y=%s apply=%s reason=%s plan=%s muts=%d allow=%s",
		tostring(pack.ref_space), tostring(pack.head_ok), tostring(pack.head_y),
		tostring(decision and decision.action), tostring(decision and decision.reason),
		tostring(plan and plan.method), #muts, tostring(allowApply))
	if hint and vrmod.Toast then
		vrmod.Toast(hint, 4, "hint")
	end
end

-- G04: read cube_warm.txt map-attach intent; careful changelevel opt-in only.
local warmAttachNotified = false
local function noteWarmAttachOnce()
	if warmAttachNotified then return end
	warmAttachNotified = true
	if not (vrmod.utils and vrmod.utils.WarmAttach_Parse) then return end
	local raw
	pcall(function()
		if file and file.Exists and file.Exists("vrmod/cube_warm.txt", "DATA") then
			raw = file.Read("vrmod/cube_warm.txt", "DATA")
		end
	end)
	if not raw or raw == "" then
		log("no cube_warm.txt (cold-only Start or cleared)")
		return
	end
	local req = vrmod.utils.WarmAttach_Parse(raw)
	if not req then
		log("cube_warm present but unusable")
		return
	end
	local curMap = ""
	pcall(function()
		if game and game.GetMap then curMap = tostring(game.GetMap() or "") end
	end)
	-- Opt-in only: vrmod_warm_changelevel 1 or DATA/vrmod/warm_changelevel_enable.txt
	local allowChg = false
	if vrmod.utils.WarmAttach_AllowChangelevelFromFlags then
		local conOn, fileOn = false, false
		pcall(function()
			if not GetConVar("vrmod_warm_changelevel") then
				CreateClientConVar("vrmod_warm_changelevel", "0", true, FCVAR_ARCHIVE,
					"G04 careful warm-map changelevel (0=off)")
			end
			local c = GetConVar("vrmod_warm_changelevel")
			if c then conOn = c:GetBool() end
		end)
		pcall(function()
			if file and file.Exists and file.Exists("vrmod/warm_changelevel_enable.txt", "DATA") then
				fileOn = true
			end
		end)
		allowChg = vrmod.utils.WarmAttach_AllowChangelevelFromFlags({
			convar_on = conOn,
			file_enable = fileOn,
		})
	end
	local decision = vrmod.utils.WarmAttach_Decide(req, {
		current_map = curMap,
		allow_changelevel = allowChg, -- default false; opt-in above
	})
	g_VR._cubeWarmRequest = req
	g_VR._cubeWarmAttach = decision
	local plan = (vrmod.utils.WarmAttach_ChangelevelPlan
		and vrmod.utils.WarmAttach_ChangelevelPlan(decision)) or nil
	g_VR._cubeWarmChangelevelPlan = plan
	-- Careful executor: only when plan armed + allow (never default path)
	local execRes
	if plan
		and vrmod.utils.WarmAttach_ShouldExecuteChangelevel
		and vrmod.utils.WarmAttach_ShouldExecuteChangelevel(plan, allowChg)
		and vrmod.utils.WarmAttach_ExecuteChangelevel then
		execRes = vrmod.utils.WarmAttach_ExecuteChangelevel(plan, function(map)
			local ok = pcall(function()
				RunConsoleCommand("changelevel", tostring(map))
			end)
			if not ok then return false, "rcc_fail" end
			return true
		end)
		g_VR._cubeWarmChangelevelExec = execRes
		log("warm changelevel applied=%s ok=%s map=%s allow=%s",
			tostring(execRes and execRes.applied), tostring(execRes and execRes.ok),
			tostring(execRes and execRes.map), tostring(allowChg))
	end
	log("warm attach action=%s reason=%s want=%s cur=%s allow_chg=%s plan=%s",
		tostring(decision.action), tostring(decision.reason),
		tostring(decision.request_map), tostring(decision.current_map),
		tostring(allowChg), tostring(plan and plan.method))
	local hint = (execRes and vrmod.utils.WarmAttach_ExecuteToast
			and vrmod.utils.WarmAttach_ExecuteToast(execRes, plan))
		or (vrmod.utils.WarmAttach_Toast and vrmod.utils.WarmAttach_Toast(decision))
	if hint and vrmod.Toast then
		vrmod.Toast(hint, 4, "hint")
	end
end

local function afterVRLive()
	log("VR active map=%s — opening native Cube launcher", tostring(game.GetMap and game.GetMap() or "?"))
	consumeMarker()
	pcall(function() RunConsoleCommand("vrmod_laserpointer", "1") end)
	if vrmod.VRUnpauseWorld then pcall(vrmod.VRUnpauseWorld) end
	noteStagePackOnce()
	noteWarmAttachOnce()

	-- Immediate + retries (hand poses / menus load slightly after active)
	openNativeLauncherUI()
	timer.Simple(0.3, openNativeLauncherUI)
	timer.Simple(0.8, openNativeLauncherUI)
	timer.Simple(1.5, function()
		if not openNativeLauncherUI() then
			-- Last resort: New Game float surface
			if vrmod.VRNewGame_Open then
				pcall(vrmod.VRNewGame_Open)
				log("fallback VRNewGame_Open")
			end
		end
		if vrmod.Toast then
			vrmod.Toast("Cube VR Launcher — New Game · Settings · look at wrist / float panel", 6, "hint")
		end
	end)
	timer.Simple(3.0, openNativeLauncherUI)
end

local function bootFromLaunch()
	local had = vrmod.ApplyOpenXRLaunchMarker()
	if not had and not vrmod.IsOpenXRLaunchSession() then
		local auto = GetConVar("vrmod_autostart")
		local hub = GetConVar("vrmod_hub")
		local menu = GetConVar("vrmod_menu_vr")
		if not ((auto and auto:GetBool()) and ((hub and hub:GetBool()) or (menu and menu:GetBool()))) then
			return
		end
		applied = true
		g_VR._openxrLaunch = g_VR._openxrLaunch or {
			mode = "cfg",
			autostart = true,
			hub = true,
			menu = false,
			-- cfg path is always the native Cube product wrapper
			native_wrapper = true,
		}
		setBoolCvar("vrmod_hub", true)
		setBoolCvar("vrmod_menu_vr", false)
		log("boot from cfg convars (no marker) → native hub")
	end

	if not (g_VR._openxrLaunch and g_VR._openxrLaunch.autostart) then
		local auto = GetConVar("vrmod_autostart")
		if not (auto and auto:GetBool()) then return end
	end

	-- Force openxr backend preference every boot for launcher sessions
	setStrCvar("vrmod_prefer_backend", "openxr")
	writeHandoff("boot")
	writeStatus("boot")

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
				vrmod.Toast("OpenXR VR start failed — WiVRn + headset?", 8, "error")
			end
			return
		end
		-- Always try — do not wait for player model (that left users on desktop only)
		forceStartVR()
	end)
end

hook.Add("Think", "vrmod_openxr_launch_boot", function()
	hook.Remove("Think", "vrmod_openxr_launch_boot")
	-- Marker first (before other systems gate start)
	vrmod.ApplyOpenXRLaunchMarker()
	timer.Simple(0.15, bootFromLaunch)
end)

hook.Add("InitPostEntity", "vrmod_openxr_launch_map", function()
	if file.Exists(MARKER, "DATA") then
		vrmod.ApplyOpenXRLaunchMarker()
	end
	local want = vrmod.IsOpenXRLaunchSession()
		or (GetConVar("vrmod_autostart") and GetConVar("vrmod_autostart"):GetBool())
	if not want then return end
	-- G01: status-file phase for Cube seamless panel (map loaded before take_xr)
	local mapName = tostring(game.GetMap and game.GetMap() or "?")
	writeHandoff("map_ready")
	writeStatus("map_ready_" .. mapName)
	log("InitPostEntity map=%s — force VR", mapName)
	timer.Simple(0.5, function()
		if not (g_VR and g_VR.active) then forceStartVR() end
	end)
	timer.Simple(1.5, function()
		if not (g_VR and g_VR.active) then forceStartVR() end
	end)
	timer.Simple(2.5, function()
		if g_VR and g_VR.active then
			openNativeLauncherUI()
		else
			forceStartVR()
		end
	end)
end)

hook.Add("VRMod_Start", "vrmod_openxr_launch_ui", function(ply)
	if ply and IsValid(LocalPlayer()) and ply ~= LocalPlayer() then return end
	if not vrmod.IsOpenXRLaunchSession() then
		local auto = GetConVar("vrmod_autostart")
		local hub = GetConVar("vrmod_hub")
		if not ((auto and auto:GetBool()) and (hub and hub:GetBool())) then
			return
		end
	end
	timer.Simple(0.2, afterVRLive)
end)

-- Debug only — product path never requires typing these
concommand.Add("vrmod_openxr_launch_status", function()
	print(string.format("[gVRMod] launchSession=%s applied=%s active=%s attempts=%d hubUI=%s marker=%s",
		tostring(vrmod.IsOpenXRLaunchSession()),
		tostring(applied),
		tostring(g_VR and g_VR.active),
		startAttempts,
		tostring(launchedUI or (vrmod.VRHub_IsOpen and vrmod.VRHub_IsOpen())),
		tostring(file.Exists(MARKER, "DATA"))))
	if g_VR and g_VR._openxrLaunch then
		PrintTable(g_VR._openxrLaunch)
	end
end)
