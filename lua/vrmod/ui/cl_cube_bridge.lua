if SERVER then return end
-- =============================================================================
-- Cube launcher bridge (G13 reverse handoff)
--
-- • Explicit "Cube Launcher" / temp return → exit VR → spawn CubeUI (GMod kept)
-- • Optional auto-relaunch only when intent was set (not noise after every Start)
-- • Stale relaunch scripts must NOT retry after a successful handoff (false "crash")
-- • One product surface: close hub/QM/other shells before return or sole hub open
--
-- SoT: docs/CUBE_LAUNCHER_BRIDGE.md
-- =============================================================================

vrmod = vrmod or {}
g_VR = g_VR or {}

local PATH_FILE = "vrmod/cube_launcher_path.txt"
local MARKER = "vrmod/openxr_launch.txt"
local RELAUNCH_REQ = "vrmod/cube_relaunch.req"
local RELAUNCH_SH = "/tmp/CubeUI_relaunch.sh"
local RELAUNCH_LOG = "/tmp/CubeUI_return.log"
local RELAUNCH_PID = "/tmp/CubeUI_relaunch.pid"

-- After XR shutdown, wait for runtime drain before first CubeUI attempt.
local SPAWN_DELAY_SEC = 2.5
-- Only retry *boot* failures (process dies in first few seconds).
local HOST_BOOT_RETRIES = 8
local HOST_BOOT_FAIL_MAX_SEC = 6

local function log(fmt, ...)
	local msg = string.format(fmt, ...)
	print("[gVRMod][cube-bridge] " .. msg)
	if vrmod.logger then vrmod.logger.Info("[cube-bridge] " .. msg) end
end

local function isCubeSession()
	if vrmod.IsOpenXRLaunchSession and vrmod.IsOpenXRLaunchSession() then return true end
	if vrmod.IsNativeCubeWrapper and vrmod.IsNativeCubeWrapper() then return true end
	if g_VR._openxrLaunch and g_VR._openxrLaunch.native_wrapper then return true end
	return false
end

local function shellQuote(s)
	return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function hostPopen(cmd)
	pcall(function()
		if io and io.popen then
			local f = io.popen(cmd)
			if f then f:close() end
		elseif os and os.execute then
			os.execute(cmd)
		end
	end)
end

--- Kill pending host relaunch loops (not GMod). Call when VR starts / handoff takes XR.
function vrmod.CubeBridge_CancelRelaunch(reason)
	g_VR._cubeReturnRelaunch = false
	g_VR._cubeBridgeSpawned = false
	g_VR._cubeReturnIntent = nil
	timer.Remove("vrmod_cube_bridge_spawn")
	-- Stop retry script; leave a healthy CubeUI alone if user opened it for real
	hostPopen(
		"if [ -f " .. RELAUNCH_PID .. " ]; then kill $(cat " .. RELAUNCH_PID .. ") 2>/dev/null; rm -f "
			.. RELAUNCH_PID .. "; fi; "
			.. "pkill -f 'CubeUI_relaunch.sh' 2>/dev/null; true"
	)
	pcall(function()
		if file.Exists(RELAUNCH_REQ, "DATA") then file.Delete(RELAUNCH_REQ) end
	end)
	log("cancel relaunch (%s)", tostring(reason or "?"))
end

--- Close every in-VR "pause / launcher" surface so only one can return later.
function vrmod.CloseAllPauseSurfaces()
	pcall(function()
		if vrmod.VirtualDisplay and vrmod.VirtualDisplay.CloseAll then
			vrmod.VirtualDisplay.CloseAll()
		end
	end)
	pcall(function()
		if vrmod.VRHub_Close then vrmod.VRHub_Close() end
	end)
	pcall(function()
		if g_VR and g_VR.menus then
			for _, uid in ipairs({
				"vr_hub", "miscmenu", "cube_settings", "avatar_menu",
				"cubeui_main", "heightmenu", "bindings_panel", "weapon_settings",
			}) do
				if g_VR.menus[uid] and isfunction(VRUtilMenuClose) then
					g_VR.menus[uid].closeFunc = nil
					pcall(VRUtilMenuClose, uid)
				end
			end
		end
	end)
	pcall(function()
		if vrmod.QuickMenu and vrmod.QuickMenu.Close then vrmod.QuickMenu.Close() end
	end)
end

--- Sole product hub (one open, others closed).
function vrmod.OpenSoleHub()
	if not (g_VR and g_VR.active) then return false end
	vrmod.CloseAllPauseSurfaces()
	if vrmod.VRUnpauseWorld then pcall(vrmod.VRUnpauseWorld) end
	if vrmod.VRHub_Open then
		pcall(vrmod.VRHub_Open)
		return vrmod.VRHub_IsOpen and vrmod.VRHub_IsOpen()
	end
	return false
end

function vrmod.CubeBridge_RememberBin(path)
	path = tostring(path or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if path == "" then return false end
	file.CreateDir("vrmod")
	file.Write(PATH_FILE, path .. "\n")
	g_VR._cubeLauncherBin = path
	return true
end

function vrmod.CubeBridge_ResolveBin()
	if g_VR._cubeLauncherBin and g_VR._cubeLauncherBin ~= "" then
		return g_VR._cubeLauncherBin
	end
	if file.Exists(PATH_FILE, "DATA") then
		local p = (file.Read(PATH_FILE, "DATA") or ""):gsub("%s+$", "")
		if p ~= "" then
			g_VR._cubeLauncherBin = p
			return p
		end
	end
	if file.Exists(MARKER, "DATA") then
		local raw = file.Read(MARKER, "DATA") or ""
		local bin = string.match(raw, "cube_bin=([^\r\n]+)")
		if bin and bin ~= "" then
			bin = bin:gsub("^%s+", ""):gsub("%s+$", "")
			vrmod.CubeBridge_RememberBin(bin)
			return bin
		end
	end
	local env = os.getenv and (os.getenv("GVRMOD_CUBE_BIN") or os.getenv("CUBEUI_BIN"))
	if env and env ~= "" then
		vrmod.CubeBridge_RememberBin(env)
		return env
	end
	local home = os.getenv and os.getenv("HOME") or ""
	return home .. "/Dev/GMod/gVRMod/install/native/CubeUI"
end

--- Spawn CubeUI once with boot-only retries (not handoff-exit retries).
function vrmod.CubeBridge_SpawnLauncher(reason)
	-- If GMod VR is live again, never fight it
	if g_VR and g_VR.active then
		log("skip spawn — VR active again")
		return false
	end

	local bin = vrmod.CubeBridge_ResolveBin()
	if not bin or bin == "" then
		log("no CubeUI path")
		if vrmod.Toast then
			vrmod.Toast("Cube path unknown · launch gVRMod Cube from desktop", 6, "warn")
		end
		return false
	end

	file.CreateDir("vrmod")
	file.Write(RELAUNCH_REQ, table.concat({
		"reason=" .. tostring(reason or "unknown"),
		"bin=" .. bin,
		"ts=" .. tostring(os.time and os.time() or 0),
	}, "\n") .. "\n")

	-- Cancel any previous retry loop first
	vrmod.CubeBridge_CancelRelaunch("respawn")

	local display = (os.getenv and os.getenv("DISPLAY")) or ":0"
	local xrJson = (os.getenv and os.getenv("XR_RUNTIME_JSON")) or ""
	local xdg = (os.getenv and os.getenv("XDG_RUNTIME_DIR")) or ""
	local qbin = shellQuote(bin)
	local reasonSafe = (tostring(reason or "?"):gsub("[^%w%._%-]", "_"))

	-- Boot-only retry: if CubeUI lives longer than HOST_BOOT_FAIL_MAX_SEC, treat
	-- later exit as normal handoff (Start Game) — NOT a crash. Do not restart.
	local shBody = table.concat({
		"#!/bin/bash",
		"echo $$ > " .. RELAUNCH_PID,
		"log=" .. RELAUNCH_LOG,
		"bin=" .. qbin,
		"max_boot=" .. tostring(HOST_BOOT_FAIL_MAX_SEC),
		"echo \"[cube-bridge] spawn begin $(date -Iseconds) reason=" .. reasonSafe .. "\" >>\"$log\"",
		"export DISPLAY=" .. shellQuote(display),
		"export XDG_RUNTIME_DIR=" .. shellQuote(xdg),
		xrJson ~= "" and ("export XR_RUNTIME_JSON=" .. shellQuote(xrJson)) or "true",
		"unset LD_LIBRARY_PATH",
		"for i in $(seq 1 " .. tostring(HOST_BOOT_RETRIES) .. "); do",
		"  if pgrep -x CubeUI >/dev/null 2>&1; then",
		"    echo \"[cube-bridge] CubeUI already running — ok\" >>\"$log\"",
		"    rm -f " .. RELAUNCH_PID,
		"    exit 0",
		"  fi",
		"  echo \"[cube-bridge] boot attempt $i/" .. tostring(HOST_BOOT_RETRIES) .. "\" >>\"$log\"",
		"  t0=$(date +%s)",
		"  \"$bin\" >>\"$log\" 2>&1",
		"  rc=$?",
		"  t1=$(date +%s)",
		"  lived=$((t1 - t0))",
		"  echo \"[cube-bridge] exit rc=$rc lived=${lived}s\" >>\"$log\"",
		"  # Lived long enough → normal handoff/quit, not crash. Stop retries.",
		"  if [ \"$lived\" -ge \"$max_boot\" ]; then",
		"    echo \"[cube-bridge] normal exit after ${lived}s (handoff/quit) — not a crash\" >>\"$log\"",
		"    rm -f " .. RELAUNCH_PID,
		"    exit 0",
		"  fi",
		"  # rc==0 quick exit also ok (instant handoff edge)",
		"  if [ $rc -eq 0 ]; then",
		"    echo \"[cube-bridge] clean exit — stop\" >>\"$log\"",
		"    rm -f " .. RELAUNCH_PID,
		"    exit 0",
		"  fi",
		"  echo \"[cube-bridge] boot failure — retry in 1s\" >>\"$log\"",
		"  sleep 1",
		"done",
		"echo \"[cube-bridge] boot failed after retries — desktop: scripts/CubeUI.sh\" >>\"$log\"",
		"rm -f " .. RELAUNCH_PID,
		"exit 1",
		"",
	}, "\n")

	local writeCmd = "cat > " .. RELAUNCH_SH .. " <<'CUBEEOF'\n" .. shBody .. "CUBEEOF\nchmod +x "
		.. RELAUNCH_SH .. "\nsetsid bash " .. RELAUNCH_SH .. " </dev/null >/dev/null 2>&1 &"

	local ok = false
	pcall(function()
		if io and io.popen then
			local f = io.popen(writeCmd)
			if f then f:close(); ok = true end
		end
	end)
	if not ok then
		pcall(function()
			if os and os.execute then
				local r = os.execute(writeCmd)
				ok = (r == 0 or r == true)
			end
		end)
	end

	log("spawn CubeUI scheduled ok=%s reason=%s bin=%s", tostring(ok), tostring(reason or "?"), bin)
	if ok and vrmod.Toast then
		vrmod.Toast("Opening Cube launcher…", 3, "hint")
	elseif not ok and vrmod.Toast then
		vrmod.Toast("Could not spawn CubeUI · desktop gVRMod Cube · /tmp/CubeUI_return.log", 6, "warn")
	end
	return ok
end

local function writeReturn(phase, intent, source)
	if not (vrmod.utils and vrmod.utils.CubeReturn_Format) then return end
	local map = ""
	pcall(function()
		if game and game.GetMap then map = tostring(game.GetMap() or "") end
	end)
	file.CreateDir("vrmod")
	file.Write("vrmod/cube_return.txt", vrmod.utils.CubeReturn_Format(phase, {
		map = map,
		source = source or "vrmod",
		intent = intent or "vr_exit",
		ts = os.time and os.time() or 0,
	}))
end

local function scheduleSpawn(intent)
	if g_VR._cubeBridgeSpawned then return end
	if g_VR and g_VR.active then return end
	g_VR._cubeBridgeSpawned = true
	timer.Remove("vrmod_cube_bridge_spawn")
	log("schedule CubeUI spawn in %.1fs intent=%s", SPAWN_DELAY_SEC, tostring(intent))
	timer.Create("vrmod_cube_bridge_spawn", SPAWN_DELAY_SEC, 1, function()
		g_VR._cubeBridgeSpawned = false
		if g_VR and g_VR.active then
			log("abort spawn — VR became active")
			return
		end
		if vrmod.CubeBridge_SpawnLauncher then
			vrmod.CubeBridge_SpawnLauncher(intent)
		end
	end)
end

--- Temporary return to Cube shell (GMod process kept).
function vrmod.ReturnToCubeLauncher(opts)
	opts = type(opts) == "table" and opts or {}
	local intent = opts.intent or "temp_return"
	local source = opts.source or "quick_menu"
	log("ReturnToCubeLauncher intent=%s source=%s active=%s",
		tostring(intent), tostring(source), tostring(g_VR and g_VR.active))

	-- One surface only: tear down QM / hub / settings before leaving VR
	vrmod.CloseAllPauseSurfaces()

	writeReturn("vr_exit", intent, source)
	g_VR._cubeReturnPendingRelease = true
	g_VR._cubeReturnRelaunch = true
	g_VR._cubeReturnIntent = intent

	if g_VR and g_VR.active then
		if isfunction(VRUtilClientExit) then
			VRUtilClientExit()
		else
			RunConsoleCommand("vrmod_exit")
		end
	else
		writeReturn("xr_released", intent, source)
		scheduleSpawn(intent)
	end
	return true
end

concommand.Add("vrmod_return_to_launcher", function()
	vrmod.ReturnToCubeLauncher({ intent = "temp_return", source = "console" })
end)

concommand.Add("vrmod_cube_launcher", function()
	vrmod.ReturnToCubeLauncher({ intent = "temp_return", source = "console" })
end)

-- Only auto-spawn CubeUI when we *asked* for return (temp_return / explicit relaunch).
-- Do NOT treat every Cube-session VR exit as "crash → respawn" (Start Game handoff is fine).
hook.Add("VRMod_Exit", "vrmod_cube_bridge_exit", function(ply)
	if ply and IsValid(ply) and ply ~= LocalPlayer() then return end
	if not g_VR._cubeReturnRelaunch then return end
	if g_VR._cubeBridgeSpawned then return end
	local intent = g_VR._cubeReturnIntent or "temp_return"
	g_VR._cubeReturnRelaunch = nil
	g_VR._cubeReturnIntent = nil
	writeReturn("xr_released", intent, "vrmod_exit")
	scheduleSpawn(intent)
end)

-- VR live again → kill any host relaunch fighting for XR
hook.Add("VRMod_Start", "vrmod_cube_bridge_start", function(ply)
	if ply and IsValid(ply) and ply ~= LocalPlayer() then return end
	vrmod.CubeBridge_CancelRelaunch("vrmod_start")
end)

hook.Add("Think", "vrmod_cube_bridge_remember_path", function()
	hook.Remove("Think", "vrmod_cube_bridge_remember_path")
	timer.Simple(0.5, function()
		if file.Exists(MARKER, "DATA") then
			local raw = file.Read(MARKER, "DATA") or ""
			local bin = string.match(raw, "cube_bin=([^\r\n]+)")
			if bin then vrmod.CubeBridge_RememberBin(bin) end
		end
	end)
end)

-- Resume poll: Cube wrote warm_attach while we sit without VR
local lastWarmTs = 0
timer.Create("vrmod_cube_resume_poll", 1.0, 0, function()
	if not g_VR or g_VR.active then return end
	if not file.Exists(MARKER, "DATA") then return end
	local raw = file.Read(MARKER, "DATA") or ""
	if not string.find(raw, "warm_attach=1", 1, true) then return end
	if not string.find(raw, "autostart=1", 1, true) then return end
	local ts = tonumber(string.match(raw, "ts=(%d+)")) or 0
	if ts <= 0 or ts == lastWarmTs then return end
	local now = os.time and os.time() or 0
	if now > 0 and ts < now - 120 then return end
	lastWarmTs = ts
	-- Cancel any CubeUI relaunch so we don't steal XR mid-resume
	vrmod.CubeBridge_CancelRelaunch("warm_attach_resume")
	log("warm_attach marker → force VR start (resume from Cube)")
	if vrmod.Toast then
		vrmod.Toast("Cube RESUME · starting VR…", 3, "hint")
	end
	pcall(function()
		vrmod.ApplyOpenXRLaunchMarker()
	end)
	pcall(function()
		RunConsoleCommand("vrmod_start", "force")
	end)
end)
