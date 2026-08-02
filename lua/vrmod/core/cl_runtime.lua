-- Dual-runtime detection for vrmod-x64 Lua.
-- One addon, two native modules (same gmcl_vrmod_*.dll slot):
--   OpenVR  = vrmod-module-master / workshop modules (no GetBackend)
--   OpenXR  = gVRMod modules (GetBackend()=="openxr", SetKnownSubmitSize, etc.)
--
-- Law: never break OpenVR. Feature policy is selected AFTER require("vrmod").

vrmod = vrmod or {}
g_VR = g_VR or {}

local BACKEND_NONE = "none"
local BACKEND_OPENVR = "openvr"
local BACKEND_OPENXR = "openxr"

-- Policy table used by cl_vrmod / settings / API.
local DEFAULT_POLICY = {
	backend = BACKEND_NONE,
	moduleVersion = 0,
	-- mat_queue
	matQueueMin = 0,
	matQueueMax = 1,
	matQueueDefault = 1,
	matQueuePinEveryFrame = true, -- OpenVR: re-assert 0/1
	matQueueRestoreOnExit = true, -- OpenVR: restore desktop value
	-- module version floors
	requiredModule = 20,
	latestModule = 23,
	moduleDownload = "https://github.com/Abyss-c0re/vrmod-module-master/releases",
	-- features
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
	matQueueMin = 0,
	matQueueMax = 2,
	matQueueDefault = 2,
	matQueuePinEveryFrame = false, -- never thrash workers
	matQueueRestoreOnExit = false, -- never 2→0 bounce
	requiredModule = 20,
	latestModule = 27,
	moduleDownload = "https://github.com/Abyss-c0re/gVRMod/releases",
	supportsEyeSizeArgs = true,
	supportsKnownSubmitSize = true,
	supportsSubmitGate = true,
	supportsOpenXRBindings = true,
	supportsRTTextureFlip = true,
	label = "OpenXR (gVRMod)",
}

local OPENVR_POLICY = {
	backend = BACKEND_OPENVR,
	moduleVersion = 0,
	matQueueMin = 0,
	matQueueMax = 1,
	matQueueDefault = 1,
	matQueuePinEveryFrame = true,
	matQueueRestoreOnExit = true,
	requiredModule = 20,
	latestModule = 23,
	moduleDownload = "https://github.com/Abyss-c0re/vrmod-module-master/releases",
	supportsEyeSizeArgs = true, -- v23+
	supportsKnownSubmitSize = false,
	supportsSubmitGate = false,
	supportsOpenXRBindings = false,
	supportsRTTextureFlip = false, -- may exist on some forks; not required
	label = "OpenVR (SteamVR / module-master)",
}

local policy = table.Copy(DEFAULT_POLICY)

local function copyPolicy(src, ver)
	local p = {}
	for k, v in pairs(src) do
		p[k] = v
	end
	p.moduleVersion = tonumber(ver) or 0
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

--- Detect which native module is loaded. Safe to call multiple times.
function vrmod.DetectBackend()
	local ver = 0
	if isfunction(VRMOD_GetVersion) then
		local ok, n = pcall(VRMOD_GetVersion)
		if ok then ver = tonumber(n) or 0 end
	end
	g_VR.moduleVersion = ver

	-- Explicit export (gVRMod v27+)
	if isfunction(VRMOD_GetBackend) then
		local ok, name = pcall(VRMOD_GetBackend)
		if ok and isstring(name) and string.lower(name) == "openxr" then
			policy = copyPolicy(OPENXR_POLICY, ver)
			g_VR.backend = BACKEND_OPENXR
			return policy
		end
	end

	-- Heuristic: OpenXR-only exports present on gVRMod (v24–v26 before GetBackend)
	local openxrHints = 0
	if isfunction(VRMOD_SetKnownSubmitSize) then openxrHints = openxrHints + 1 end
	if isfunction(VRMOD_SetSubmitEnabled) then openxrHints = openxrHints + 1 end
	if isfunction(VRMOD_GetControllerSources) then openxrHints = openxrHints + 1 end
	if isfunction(VRMOD_SetRTTextureFlip) then openxrHints = openxrHints + 1 end
	if ver >= 24 and openxrHints >= 1 then
		policy = copyPolicy(OPENXR_POLICY, ver)
		g_VR.backend = BACKEND_OPENXR
		return policy
	end

	if ver > 0 or isfunction(VRMOD_Init) then
		policy = copyPolicy(OPENVR_POLICY, ver)
		g_VR.backend = BACKEND_OPENVR
		return policy
	end

	policy = copyPolicy(DEFAULT_POLICY, 0)
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

--- Clamp wanted mat_queue to what the active module supports.
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
	return string.format("%s · module v%s · mat_queue max %s",
		tostring(p.label), tostring(p.moduleVersion), tostring(p.matQueueMax))
end

-- Concommand for smoke / support
concommand.Add("vrmod_backend", function()
	-- Re-detect in case module was hot-swapped (rare)
	if isfunction(VRMOD_GetVersion) then
		vrmod.DetectBackend()
	end
	print("[VRMod] " .. vrmod.DescribeBackend())
	print("[VRMod] backend=" .. tostring(vrmod.GetBackend())
		.. " eyeArgs=" .. tostring(policy.supportsEyeSizeArgs)
		.. " knownSize=" .. tostring(policy.supportsKnownSubmitSize)
		.. " submitGate=" .. tostring(policy.supportsSubmitGate))
end)
