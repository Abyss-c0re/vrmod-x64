-- Dual native modules (both may live in garrysmod/lua/bin at once):
--   OpenVR  → require("vrmod")    → gmcl_vrmod_linux64.dll / gmcl_vrmod_win64.dll
--   OpenXR  → require("vrmod_xr") → gmcl_vrmod_xr_linux64.dll / gmcl_vrmod_xr_win64.dll
--
-- Law: never break OpenVR. Feature policy is selected AFTER a successful require.

vrmod = vrmod or {}
g_VR = g_VR or {}

local BACKEND_NONE = "none"
local BACKEND_OPENVR = "openvr"
local BACKEND_OPENXR = "openxr"

local DEFAULT_POLICY = {
	backend = BACKEND_NONE,
	moduleVersion = 0,
	requireName = nil,
	moduleFile = nil,
	matQueueMin = 0,
	matQueueMax = 1,
	matQueueDefault = 1,
	matQueuePinEveryFrame = true,
	matQueueRestoreOnExit = true,
	requiredModule = 20,
	latestModule = 23,
	moduleDownload = "https://github.com/Abyss-c0re/vrmod-module-master/releases",
	supportsEyeSizeArgs = false,
	supportsKnownSubmitSize = false,
	supportsSubmitGate = false,
	supportsOpenXRBindings = false,
	supportsRTTextureFlip = false,
	label = "no module",
}

local OPENXR_POLICY = {
	backend = BACKEND_OPENXR,
	moduleVersion = 0,
	requireName = "vrmod_xr",
	moduleFile = nil,
	matQueueMin = 0,
	matQueueMax = 2, -- allowed if user set it; we never force or write mat_queue_mode
	matQueueDefault = 1,
	matQueuePinEveryFrame = false,
	matQueueRestoreOnExit = false,
	requiredModule = 20,
	latestModule = 44,
	moduleDownload = "https://github.com/Abyss-c0re/gVRMod/releases",
	supportsEyeSizeArgs = true,
	supportsKnownSubmitSize = true,
	supportsSubmitGate = true,
	supportsOpenXRBindings = true,
	supportsRTTextureFlip = true,
	label = "OpenXR (gVRMod / vrmod_xr)",
}

local OPENVR_POLICY = {
	backend = BACKEND_OPENVR,
	moduleVersion = 0,
	requireName = "vrmod",
	moduleFile = nil,
	matQueueMin = 0,
	matQueueMax = 1,
	matQueueDefault = 1,
	matQueuePinEveryFrame = true,
	matQueueRestoreOnExit = true,
	requiredModule = 20,
	latestModule = 23,
	moduleDownload = "https://github.com/Abyss-c0re/vrmod-module-master/releases",
	supportsEyeSizeArgs = true,
	supportsKnownSubmitSize = false,
	supportsSubmitGate = false,
	supportsOpenXRBindings = false,
	supportsRTTextureFlip = false,
	label = "OpenVR (SteamVR / module-master)",
}

local policy = table.Copy(DEFAULT_POLICY)
local loadError = nil

local function platformModuleFiles()
	if system.IsLinux() then
		return {
			xr = "lua/bin/gmcl_vrmod_xr_linux64.dll",
			openvr = "lua/bin/gmcl_vrmod_linux64.dll",
		}
	end
	if system.IsWindows() then
		local xr = "lua/bin/gmcl_vrmod_xr_win64.dll"
		local ovr = "lua/bin/gmcl_vrmod_win64.dll"
		if not file.Exists(ovr, "GAME") and file.Exists("lua/bin/gmcl_vrmod_win32.dll", "GAME") then
			ovr = "lua/bin/gmcl_vrmod_win32.dll"
		end
		if not file.Exists(xr, "GAME") and file.Exists("lua/bin/gmcl_vrmod_xr_win32.dll", "GAME") then
			xr = "lua/bin/gmcl_vrmod_xr_win32.dll"
		end
		return { xr = xr, openvr = ovr }
	end
	return { xr = nil, openvr = nil }
end

--- Prefer auto | openxr | openvr (convar vrmod_prefer_backend).
local function PreferBackend()
	local cv = GetConVar and GetConVar("vrmod_prefer_backend")
	local s = cv and string.lower(tostring(cv:GetString() or "auto")) or "auto"
	if s == "openxr" or s == "xr" then return BACKEND_OPENXR end
	if s == "openvr" or s == "ovr" or s == "steamvr" then return BACKEND_OPENVR end
	return "auto"
end

local function copyPolicy(src, ver, requireName, moduleFile)
	local p = {}
	for k, v in pairs(src) do
		p[k] = v
	end
	p.moduleVersion = tonumber(ver) or 0
	p.requireName = requireName
	p.moduleFile = moduleFile
	if p.backend == BACKEND_OPENVR then
		p.supportsEyeSizeArgs = p.moduleVersion >= 23
	elseif p.backend == BACKEND_OPENXR then
		p.supportsEyeSizeArgs = p.moduleVersion >= 23
		p.supportsKnownSubmitSize = isfunction(VRMOD_SetKnownSubmitSize)
		p.supportsSubmitGate = isfunction(VRMOD_SetSubmitEnabled)
		p.supportsOpenXRBindings = isfunction(VRMOD_GetControllerSources)
		p.supportsRTTextureFlip = isfunction(VRMOD_SetRTTextureFlip)
	end
	return p
end

local function bindExports()
	-- Module GMOD_MODULE_OPEN registers global table `vrmod` with C functions.
	if not istable(vrmod) then return end
	for k, v in pairs(vrmod) do
		if isfunction(v) then
			_G["VRMOD_" .. k] = v
		end
	end
end

local function tryRequire(name)
	local ok, err = pcall(function()
		require(name)
	end)
	return ok, err
end

--- Load one native module. Both binaries may be installed; only one is required.
--- Returns true on success.
function vrmod.LoadNativeModule()
	loadError = nil
	local files = platformModuleFiles()
	local prefer = PreferBackend()
	local haveXr = files.xr and file.Exists(files.xr, "GAME")
	local haveOvr = files.openvr and file.Exists(files.openvr, "GAME")

	local order = {}
	if prefer == BACKEND_OPENXR then
		if haveXr then table.insert(order, { "vrmod_xr", files.xr, BACKEND_OPENXR }) end
		if haveOvr then table.insert(order, { "vrmod", files.openvr, BACKEND_OPENVR }) end
	elseif prefer == BACKEND_OPENVR then
		if haveOvr then table.insert(order, { "vrmod", files.openvr, BACKEND_OPENVR }) end
		if haveXr then table.insert(order, { "vrmod_xr", files.xr, BACKEND_OPENXR }) end
	else
		-- auto: OpenXR first if present (dual install prefers XR when available)
		if haveXr then table.insert(order, { "vrmod_xr", files.xr, BACKEND_OPENXR }) end
		if haveOvr then table.insert(order, { "vrmod", files.openvr, BACKEND_OPENVR }) end
	end

	if #order == 0 then
		loadError = "No VR module binary found (need gmcl_vrmod_xr_* and/or gmcl_vrmod_*)."
		policy = table.Copy(DEFAULT_POLICY)
		g_VR.backend = BACKEND_NONE
		g_VR.moduleVersion = 0
		return false
	end

	local errors = {}
	for _, ent in ipairs(order) do
		local reqName, path, backend = ent[1], ent[2], ent[3]
		local ok, err = tryRequire(reqName)
		if ok then
			bindExports()
			local ver = 0
			if isfunction(VRMOD_GetVersion) then
				local vok, n = pcall(VRMOD_GetVersion)
				if vok then ver = tonumber(n) or 0 end
			end
			g_VR.moduleVersion = ver
			g_VR.moduleRequire = reqName
			g_VR.moduleFile = path

			-- Confirm backend (export / heuristics)
			local isXr = (backend == BACKEND_OPENXR)
			if isfunction(VRMOD_GetBackend) then
				local bok, name = pcall(VRMOD_GetBackend)
				if bok and isstring(name) and string.lower(name) == "openxr" then
					isXr = true
				elseif bok and isstring(name) and string.lower(name) == "openvr" then
					isXr = false
				end
			elseif backend == BACKEND_OPENVR then
				-- Safety: never treat a classic OpenVR binary as XR just by path
				isXr = isfunction(VRMOD_SetKnownSubmitSize) or isfunction(VRMOD_SetSubmitEnabled)
			end

			if isXr then
				policy = copyPolicy(OPENXR_POLICY, ver, reqName, path)
				g_VR.backend = BACKEND_OPENXR
			else
				policy = copyPolicy(OPENVR_POLICY, ver, reqName, path)
				g_VR.backend = BACKEND_OPENVR
			end

			if vrmod.logger then
				vrmod.logger.Info(
					"Loaded %s via require(%q) file=%s v%s",
					policy.label, reqName, tostring(path), tostring(ver)
				)
			end
			return true
		end
		table.insert(errors, string.format("%s (%s): %s", reqName, tostring(path), tostring(err)))
	end

	loadError = table.concat(errors, "\n")
	policy = table.Copy(DEFAULT_POLICY)
	g_VR.backend = BACKEND_NONE
	g_VR.moduleVersion = 0
	if vrmod.logger then
		vrmod.logger.Err("Failed to load any VR module:\n%s", loadError)
	end
	return false
end

function vrmod.GetModuleLoadError()
	return loadError
end

function vrmod.ListInstalledModules()
	local files = platformModuleFiles()
	return {
		openxr = files.xr and file.Exists(files.xr, "GAME") and files.xr or nil,
		openvr = files.openvr and file.Exists(files.openvr, "GAME") and files.openvr or nil,
	}
end

--- Detect / refresh policy from already-loaded exports (after LoadNativeModule).
function vrmod.DetectBackend()
	if not isfunction(VRMOD_GetVersion) and not isfunction(VRMOD_Init) then
		-- Not loaded yet
		if g_VR.backend == nil or g_VR.backend == BACKEND_NONE then
			policy = table.Copy(DEFAULT_POLICY)
			g_VR.backend = BACKEND_NONE
		end
		return policy
	end

	local ver = 0
	if isfunction(VRMOD_GetVersion) then
		local ok, n = pcall(VRMOD_GetVersion)
		if ok then ver = tonumber(n) or 0 end
	end
	g_VR.moduleVersion = ver

	if isfunction(VRMOD_GetBackend) then
		local ok, name = pcall(VRMOD_GetBackend)
		if ok and isstring(name) and string.lower(name) == "openxr" then
			policy = copyPolicy(OPENXR_POLICY, ver, g_VR.moduleRequire or "vrmod_xr", g_VR.moduleFile)
			g_VR.backend = BACKEND_OPENXR
			return policy
		end
	end

	local openxrHints = 0
	if isfunction(VRMOD_SetKnownSubmitSize) then openxrHints = openxrHints + 1 end
	if isfunction(VRMOD_SetSubmitEnabled) then openxrHints = openxrHints + 1 end
	if isfunction(VRMOD_GetControllerSources) then openxrHints = openxrHints + 1 end
	if isfunction(VRMOD_SetRTTextureFlip) then openxrHints = openxrHints + 1 end
	if (g_VR.moduleRequire == "vrmod_xr") or (ver >= 24 and openxrHints >= 1) then
		policy = copyPolicy(OPENXR_POLICY, ver, g_VR.moduleRequire or "vrmod_xr", g_VR.moduleFile)
		g_VR.backend = BACKEND_OPENXR
		return policy
	end

	if ver > 0 or isfunction(VRMOD_Init) then
		policy = copyPolicy(OPENVR_POLICY, ver, g_VR.moduleRequire or "vrmod", g_VR.moduleFile)
		g_VR.backend = BACKEND_OPENVR
		return policy
	end

	policy = copyPolicy(DEFAULT_POLICY, 0, nil, nil)
	g_VR.backend = BACKEND_NONE
	return policy
end

function vrmod.GetBackendPolicy()
	return policy
end

function vrmod.GetBackend()
	return policy.backend or g_VR.backend or BACKEND_NONE
end

function vrmod.IsOpenXR()
	return vrmod.GetBackend() == BACKEND_OPENXR
end

function vrmod.IsOpenVR()
	return vrmod.GetBackend() == BACKEND_OPENVR
end

function vrmod.ClampMatQueueMode(n)
	n = math.floor(tonumber(n) or policy.matQueueDefault or 1)
	local lo = policy.matQueueMin or 0
	local hi = policy.matQueueMax or 1
	if n < lo then n = lo end
	if n > hi then n = hi end
	return n
end

function vrmod.DescribeBackend()
	local p = policy
	local inst = vrmod.ListInstalledModules()
	return string.format(
		"%s · module v%s · require(%s) · installed XR=%s OVR=%s · mat_queue max %s",
		tostring(p.label),
		tostring(p.moduleVersion),
		tostring(p.requireName or "?"),
		inst.openxr and "yes" or "no",
		inst.openvr and "yes" or "no",
		tostring(p.matQueueMax)
	)
end

concommand.Add("vrmod_backend", function()
	if isfunction(VRMOD_GetVersion) then
		vrmod.DetectBackend()
	end
	print("[VRMod] " .. vrmod.DescribeBackend())
	local inst = vrmod.ListInstalledModules()
	print("[VRMod] files: openxr=" .. tostring(inst.openxr) .. " openvr=" .. tostring(inst.openvr))
	print("[VRMod] prefer=" .. PreferBackend()
		.. " backend=" .. tostring(vrmod.GetBackend())
		.. " eyeArgs=" .. tostring(policy.supportsEyeSizeArgs)
		.. " knownSize=" .. tostring(policy.supportsKnownSubmitSize)
		.. " submitGate=" .. tostring(policy.supportsSubmitGate))
	if loadError then
		print("[VRMod] last load error:\n" .. tostring(loadError))
	end
end)
