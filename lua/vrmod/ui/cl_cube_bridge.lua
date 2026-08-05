if SERVER then return end
-- =============================================================================
-- Cube launcher bridge (G13 reverse handoff product path)
--
-- • On VR exit after Cube session → write cube_return + spawn CubeUI again
-- • Quick menu "Cube Launcher" → temporary return (GMod stays, VR off, shell back)
-- • Poll warm_attach markers so RESUME from Cube can re-enter VR without Steam
--
-- SoT note: docs/CUBE_LAUNCHER_BRIDGE.md + state/polish_loop/GLOGIC_GAPS.md G13
-- =============================================================================

vrmod = vrmod or {}
g_VR = g_VR or {}

local PATH_FILE = "vrmod/cube_launcher_path.txt"
local MARKER = "vrmod/openxr_launch.txt"

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

--- Remember Cube binary path (from openxr_launch marker or manual).
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
	-- openxr_launch.txt may carry cube_bin= from CubeUI spawn
	if file.Exists(MARKER, "DATA") then
		local raw = file.Read(MARKER, "DATA") or ""
		local bin = string.match(raw, "cube_bin=([^\r\n]+)")
		if bin and bin ~= "" then
			bin = bin:gsub("^%s+", ""):gsub("%s+$", "")
			vrmod.CubeBridge_RememberBin(bin)
			return bin
		end
	end
	-- Env / common monorepo install
	local env = os.getenv and (os.getenv("GVRMOD_CUBE_BIN") or os.getenv("CUBEUI_BIN"))
	if env and env ~= "" then
		vrmod.CubeBridge_RememberBin(env)
		return env
	end
	local home = os.getenv and os.getenv("HOME") or ""
	local candidates = {
		home .. "/Dev/GMod/gVRMod/install/native/CubeUI",
		home .. "/.local/share/gvrmod/CubeUI",
		"/usr/local/bin/CubeUI",
	}
	for _, p in ipairs(candidates) do
		-- Can't always stat from Lua; try spawn path and let shell fail soft
		if p and p ~= "" then
			return p
		end
	end
	return nil
end

--- Spawn CubeUI detached (Linux). Safe after VRMOD_Shutdown so XR is free.
function vrmod.CubeBridge_SpawnLauncher(reason)
	local bin = vrmod.CubeBridge_ResolveBin()
	if not bin then
		log("no CubeUI path — set cube_bin in openxr_launch or GVRMOD_CUBE_BIN")
		if vrmod.Toast then
			vrmod.Toast("Cube path unknown · launch gVRMod Cube from desktop", 6, "warn")
		end
		return false
	end
	-- Quote path; run via nohup so GMod doesn't wait
	local q = "'" .. bin:gsub("'", "'\\''") .. "'"
	local cmd = "env -u LD_LIBRARY_PATH nohup " .. q .. " >/tmp/CubeUI_return.log 2>&1 &"
	local ok = false
	pcall(function()
		if io and io.popen then
			local f = io.popen(cmd)
			if f then
				f:close()
				ok = true
			end
		end
	end)
	if not ok then
		pcall(function()
			if os and os.execute then
				ok = (os.execute(cmd) == 0 or os.execute(cmd) == true)
			end
		end)
	end
	log("spawn CubeUI ok=%s reason=%s bin=%s", tostring(ok), tostring(reason or "?"), bin)
	if ok and vrmod.Toast then
		vrmod.Toast("Opening Cube launcher…", 3, "hint")
	elseif not ok and vrmod.Toast then
		vrmod.Toast("Could not spawn CubeUI · check /tmp/CubeUI_return.log", 5, "warn")
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

--- Temporary return to Cube shell (GMod process kept). Exits VR then spawns launcher.
function vrmod.ReturnToCubeLauncher(opts)
	opts = type(opts) == "table" and opts or {}
	local intent = opts.intent or "temp_return"
	local source = opts.source or "quick_menu"
	log("ReturnToCubeLauncher intent=%s source=%s active=%s",
		tostring(intent), tostring(source), tostring(g_VR and g_VR.active))

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
		-- Already out of VR — still free XR if any, then spawn
		writeReturn("xr_released", intent, source)
		timer.Simple(0.4, function()
			vrmod.CubeBridge_SpawnLauncher(intent)
		end)
	end
	return true
end

concommand.Add("vrmod_return_to_launcher", function()
	vrmod.ReturnToCubeLauncher({ intent = "temp_return", source = "console" })
end)

concommand.Add("vrmod_cube_launcher", function()
	vrmod.ReturnToCubeLauncher({ intent = "temp_return", source = "console" })
end)

-- Net VRMod_Exit may fire without VRUtilClientExit path — still spawn once
hook.Add("VRMod_Exit", "vrmod_cube_bridge_exit", function(ply)
	if ply and IsValid(ply) and ply ~= LocalPlayer() then return end
	if g_VR._cubeBridgeSpawned then return end -- already scheduled from ClientExit
	local want = g_VR._cubeReturnRelaunch
		or (isCubeSession() and vrmod.utils and vrmod.utils.CubeReturn_ShouldRelaunchCube
			and vrmod.utils.CubeReturn_ShouldRelaunchCube(true, true))
	if not want then return end
	local intent = g_VR._cubeReturnIntent or "vr_exit"
	g_VR._cubeReturnRelaunch = nil
	g_VR._cubeReturnIntent = nil
	writeReturn("xr_released", intent, "vrmod_exit")
	g_VR._cubeBridgeSpawned = true
	timer.Simple(0.75, function()
		g_VR._cubeBridgeSpawned = nil
		if vrmod.CubeBridge_SpawnLauncher then
			vrmod.CubeBridge_SpawnLauncher(intent)
		end
	end)
end)

-- Capture cube_bin when launch marker applied
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

-- Resume poll: Cube wrote warm_attach while we sit on desktop without VR
local lastWarmTs = 0
timer.Create("vrmod_cube_resume_poll", 1.0, 0, function()
	if not g_VR or g_VR.active then return end
	if not file.Exists(MARKER, "DATA") then return end
	local raw = file.Read(MARKER, "DATA") or ""
	if not string.find(raw, "warm_attach=1", 1, true) then return end
	if not string.find(raw, "autostart=1", 1, true) then return end
	local ts = tonumber(string.match(raw, "ts=(%d+)")) or 0
	if ts <= 0 or ts == lastWarmTs then return end
	-- Only react to fresh markers (not stale from last boot)
	local now = os.time and os.time() or 0
	if now > 0 and ts < now - 120 then return end -- older than 2 min
	lastWarmTs = ts
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
