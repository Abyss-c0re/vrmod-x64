if SERVER then return end
local _, convarValues = vrmod.GetConvars()
local seatedOffset, crouchOffset = Vector(), Vector()
local function updateOffsetHook()
	seatedOffset.z = convarValues.vrmod_seated and convarValues.vrmod_seatedoffset or 0
	if seatedOffset.z == 0 and crouchOffset.z == 0 then
		hook.Remove("VRMod_Tracking", "seatedmode")
		return
	end

	hook.Add("VRMod_Tracking", "seatedmode", function()
		g_VR.tracking.hmd.pos = g_VR.tracking.hmd.pos + seatedOffset + crouchOffset
		g_VR.tracking.pose_lefthand.pos = g_VR.tracking.pose_lefthand.pos + seatedOffset + crouchOffset
		g_VR.tracking.pose_righthand.pos = g_VR.tracking.pose_righthand.pos + seatedOffset + crouchOffset
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
		crouchTarget = crouchTarget == 0 and math.min(0, 38 - (g_VR.tracking.hmd.pos.z - g_VR.origin.z)) or 0 --vrmod default crouch threshold is 40
		local speed = (crouchTarget == 0 and 36 or -36) * 1 / LocalPlayer():GetDuckSpeed() --eye pos difference between standing and crouched gmod player is 36 units, this distance is travelled in GetDuckSpeed seconds
		hook.Add("PreRender", "vrmod_crouch", function()
			crouchOffset.z = crouchOffset.z + speed * FrameTime()
			if crouchOffset.z > 0 or crouchTarget < 0 and crouchOffset.z < crouchTarget then
				crouchOffset.z = crouchTarget
				hook.Remove("PreRender", "vrmod_crouch")
				updateOffsetHook()
			end
		end)

		crouchOffset.z = crouchOffset.z + 0.01
		updateOffsetHook()
	end
end)