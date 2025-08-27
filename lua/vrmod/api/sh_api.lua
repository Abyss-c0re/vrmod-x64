local addonVersion = 200
if system.IsLinux() then
	requiredModuleVersion = 23
else
	requiredModuleVersion = 21
end

g_VR = g_VR or {}
vrmod = vrmod or {}
local convars, convarValues = {}, {}
function vrmod.AddCallbackedConvar(cvarName, valueName, defaultValue, flags, helptext, min, max, conversionFunc, callbackFunc)
	valueName = valueName or cvarName
	flags = flags or FCVAR_ARCHIVE
	conversionFunc = conversionFunc or function(val) return val end
	-- Prevent re-creating existing convar
	local cv = GetConVar(cvarName)
	if not cv then cv = CreateConVar(cvarName, defaultValue, flags, helptext, min, max) end
	convars[cvarName] = cv
	convarValues[valueName] = conversionFunc(cv:GetString())
	-- Set up dynamic callback
	cvars.AddChangeCallback(cvarName, function(_, _, new)
		convarValues[valueName] = conversionFunc(new)
		if callbackFunc then callbackFunc(convarValues[valueName]) end
	end, "vrmod")
	return convars, convarValues
end

function vrmod.GetConvars()
	return convars, convarValues
end

function vrmod.GetVersion()
	return addonVersion
end

hook.Add("PlayerDisconnected", "VRMod_CleanCache", function(ply) vrmod.HandVelocityCache[ply:SteamID()] = nil end)
local hookTranslations = {
	VRUtilEventTracking = "VRMod_Tracking",
	VRUtilEventInput = "VRMod_Input",
	VRUtilEventPreRender = "VRMod_PreRender",
	VRUtilEventPreRenderRight = "VRMod_PreRenderRight",
	VRUtilEventPostRender = "VRMod_PostRender",
	VRUtilStart = "VRMod_Start",
	VRUtilExit = "VRMod_Exit",
	VRUtilEventPickup = "VRMod_Pickup",
	VRUtilEventDrop = "VRMod_Drop",
	VRUtilAllowDefaultAction = "VRMod_AllowDefaultAction"
}

local hooks = hook.GetTable()
for k, v in pairs(hooks) do
	local translation = hookTranslations[k]
	if translation then
		hooks[translation] = hooks[translation] or {}
		for k2, v2 in pairs(v) do
			hooks[translation][k2] = v2
		end

		hooks[k] = nil
	end
end

local orig = hook.Add
hook.Add = function(...)
	local args = {...}
	args[1] = hookTranslations[args[1]] or args[1]
	orig(unpack(args))
end

local orig = hook.Remove
hook.Remove = function(...)
	local args = {...}
	args[1] = hookTranslations[args[1]] or args[1]
	orig(unpack(args))
end