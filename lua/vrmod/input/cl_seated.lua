if SERVER then return end
-- =============================================================================
-- Seated / crouch origin Z — single SoT: vrmod_seated + vrmod_seatedoffset
-- All UIs (Cube settings, Avatar, stage pack) must write via vrmod.SettingsSet*
-- or vrmod.AutoSeatedOffset so cache + hooks stay coherent.
-- =============================================================================
local _, convarValues = vrmod.GetConvars()
local seatedOffset, crouchOffset = Vector(), Vector()
-- Exposed so locomotion can force IN_DUCK while button-crouched
g_VR = g_VR or {}
g_VR.crouchOffsetZ = 0

local function LiveBool(name)
	local cv = GetConVar(name)
	if cv then return cv:GetBool() end
	local v = convarValues and convarValues[name]
	if v == true or v == 1 then return true end
	if v == false or v == 0 then return false end
	return false
end

local function LiveFloat(name, default)
	local cv = GetConVar(name)
	if cv then return cv:GetFloat() end
	local o = convarValues and convarValues[name]
	if o ~= nil then return tonumber(o) or default or 0 end
	return default or 0
end

local function SeatedEnabled()
	return LiveBool("vrmod_seated")
end

local function SeatedOffsetZ()
	if not SeatedEnabled() then return 0 end
	return LiveFloat("vrmod_seatedoffset", 0)
end

--- Apply Z offset to every tracked pose (HMD, hands, feet, OpenXR eyes).
--- Camera uses eye_left/eye_right when present — missing them left the body high and the view low.
local function ApplyZOffsetToTracking(dz)
	if not g_VR.tracking or dz == 0 then return end
	local add = Vector(0, 0, dz)
	for name, pose in pairs(g_VR.tracking) do
		if istable(pose) and pose.pos then
			pose.pos = pose.pos + add
		end
	end
end

local function updateOffsetHook()
	seatedOffset.z = SeatedOffsetZ()
	g_VR.crouchOffsetZ = crouchOffset.z
	local totalZ = seatedOffset.z + crouchOffset.z
	if totalZ == 0 then
		hook.Remove("VRMod_Tracking", "seatedmode")
		return
	end

	hook.Add("VRMod_Tracking", "seatedmode", function()
		-- Re-read live SoT every frame (settings/avatar toggles apply without restart)
		local z = SeatedOffsetZ() + crouchOffset.z
		g_VR.crouchOffsetZ = crouchOffset.z
		if z ~= 0 then
			ApplyZOffsetToTracking(z)
		end
	end)
end

-- Public: stage pack / UI force rebind after external SetFloat
function vrmod.UpdateSeatedOffset()
	updateOffsetHook()
end

vrmod.AddCallbackedConvar("vrmod_seatedoffset", nil, "0", FCVAR_ARCHIVE,
	"Seated origin Z offset (Source units). Shared by Settings + Avatar.", -80, 80, tonumber,
	function() updateOffsetHook() end)
vrmod.AddCallbackedConvar("vrmod_seated", nil, "0", FCVAR_ARCHIVE,
	"Enable seated origin offset", nil, nil, tobool,
	function() updateOffsetHook() end)

-- Belt: any SettingChanged for seated cvars rebinds (covers cache-only Notify paths)
hook.Add("VRMod_SettingChanged", "vrmod_seated_sot", function(name)
	if name == "vrmod_seated" or name == "vrmod_seatedoffset" then
		updateOffsetHook()
	end
end)

hook.Add("VRMod_Start", "seatedmode", function(ply)
	if ply ~= LocalPlayer() then return end
	updateOffsetHook()
end)

hook.Add("VRMod_Exit", "seatedmode", function(ply)
	if ply ~= LocalPlayer() then return end
	hook.Remove("VRMod_Tracking", "seatedmode")
	crouchOffset.z = 0
	g_VR.crouchOffsetZ = 0
end)

--- Measure raw HMD height (never post-seated tracking — that double-counts).
function vrmod.MeasureRawEyeHeight()
	if not g_VR or not g_VR.origin then return nil end
	local hmd = (g_VR.rawTracking and g_VR.rawTracking.hmd)
		or nil
	-- Fall back only if raw missing (early frames); subtract current seated so we don't nest
	if not hmd or not hmd.pos then
		hmd = g_VR.tracking and g_VR.tracking.hmd
		if not hmd or not hmd.pos then return nil end
		local z = hmd.pos.z - g_VR.origin.z
		-- tracking already has seated applied — peel it back for measurement
		z = z - SeatedOffsetZ()
		return z
	end
	return hmd.pos.z - g_VR.origin.z
end

--- Single AutoSeatedOffset SoT used by Avatar, Settings action, heightadjust.
function vrmod.AutoSeatedOffset()
	local measured = vrmod.MeasureRawEyeHeight()
	if not measured then return false end
	local ref = 66.8
	local cvh = GetConVar("vrmod_charactereyeheight")
	if cvh then ref = cvh:GetFloat() end
	local offset
	if vrmod.utils and vrmod.utils.AutoSeatedOffset then
		offset = vrmod.utils.AutoSeatedOffset(measured, ref)
	else
		offset = ref - measured
	end
	offset = math.Clamp(tonumber(offset) or 0, -80, 80)
	if vrmod.SettingsSetFloat then
		vrmod.SettingsSetFloat("vrmod_seatedoffset", offset)
	else
		local cv = GetConVar("vrmod_seatedoffset")
		if cv then cv:SetFloat(offset) end
	end
	if vrmod.SettingsSetBool then
		vrmod.SettingsSetBool("vrmod_seated", true)
	else
		local cv = GetConVar("vrmod_seated")
		if cv then cv:SetBool(true) end
	end
	updateOffsetHook()
	if vrmod.Toast then
		vrmod.Toast(string.format("Seated offset → %.1f", offset), 3, "hint")
	end
	return true, offset
end

local crouchTarget = 0
hook.Add("VRMod_Input", "crouching", function(action, pressed)
	if action == "boolean_crouch" and pressed then
		local hmdZ = 0
		if g_VR.tracking and g_VR.tracking.hmd and g_VR.tracking.hmd.pos and g_VR.origin then
			hmdZ = g_VR.tracking.hmd.pos.z - g_VR.origin.z
		end
		crouchTarget = crouchTarget == 0 and math.min(0, 38 - hmdZ) or 0 --vrmod default crouch threshold is 40
		local speed = (crouchTarget == 0 and 36 or -36) * 1 / LocalPlayer():GetDuckSpeed() --eye pos difference between standing and crouched gmod player is 36 units, this distance is travelled in GetDuckSpeed seconds
		hook.Add("PreRender", "vrmod_crouch", function()
			crouchOffset.z = crouchOffset.z + speed * FrameTime()
			g_VR.crouchOffsetZ = crouchOffset.z
			if crouchOffset.z > 0 or crouchTarget < 0 and crouchOffset.z < crouchTarget then
				crouchOffset.z = crouchTarget
				g_VR.crouchOffsetZ = crouchOffset.z
				hook.Remove("PreRender", "vrmod_crouch")
				updateOffsetHook()
			end
		end)

		crouchOffset.z = crouchOffset.z + 0.01
		g_VR.crouchOffsetZ = crouchOffset.z
		updateOffsetHook()
	end
end)
