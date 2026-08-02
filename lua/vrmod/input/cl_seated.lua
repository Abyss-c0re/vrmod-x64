if SERVER then return end
local _, convarValues = vrmod.GetConvars()
local seatedOffset, crouchOffset = Vector(), Vector()
-- Exposed so locomotion can force IN_DUCK while button-crouched (see issue #10)
g_VR = g_VR or {}
g_VR.crouchOffsetZ = 0

local function SeatedEnabled()
	-- convarValues.vrmod_seated is bool via tobool — never treat the ConVar object as truthy
	local v = convarValues and convarValues.vrmod_seated
	if v == true or v == 1 then return true end
	if isbool(v) then return v end
	local cv = GetConVar("vrmod_seated")
	return cv and cv:GetBool() or false
end

local function SeatedOffsetZ()
	if not SeatedEnabled() then return 0 end
	local o = convarValues and convarValues.vrmod_seatedoffset
	if o == nil then
		local cv = GetConVar("vrmod_seatedoffset")
		o = cv and cv:GetFloat() or 0
	end
	return tonumber(o) or 0
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
		-- Re-read live so settings/toggles apply without restart
		local z = SeatedOffsetZ() + crouchOffset.z
		g_VR.crouchOffsetZ = crouchOffset.z
		if z ~= 0 then
			ApplyZOffsetToTracking(z)
		end
	end)
end

vrmod.AddCallbackedConvar("vrmod_seatedoffset", nil, "0", nil, nil, nil, nil, tonumber, function(val) updateOffsetHook() end)
vrmod.AddCallbackedConvar("vrmod_seated", nil, "0", nil, nil, nil, nil, tobool, function(val) updateOffsetHook() end)

hook.Add("VRMod_Start", "seatedmode", function(ply)
	if ply ~= LocalPlayer() then return end
	updateOffsetHook()
end)

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
