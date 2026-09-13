-- After ArcVR AVR_GunTracking: keep grip position, restore device wrist.
-- ForegripAngle is gun-space (often 0,-90,-90) and twists ValveBiped L_Hand / floating hands.
if SERVER then return end

g_VR = g_VR or {}
vrmod = vrmod or {}

local function RestoreDeviceWrist()
	if not g_VR or not g_VR.active then return end
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local wep = ply:GetActiveWeapon()
	local grabbed = IsValid(wep) and wep.ArcticVR and wep.ForegripGrabbed
	local d
	if vrmod.utils and vrmod.utils.ArcVrWristLaw_Decide then
		d = vrmod.utils.ArcVrWristLaw_Decide({
			vr_active = true,
			arcvr = IsValid(wep) and wep.ArcticVR and true or false,
			foregrip_grabbed = grabbed and true or false,
		})
		if not d or not d.restore_device_ang then return end
	elseif not grabbed then
		return
	end

	local L = g_VR.tracking and g_VR.tracking.pose_lefthand
	local rawL = g_VR.rawTracking and g_VR.rawTracking.pose_lefthand
	if not (L and L.ang and rawL and rawL.ang) then return end
	if L.ang.Set then
		L.ang:Set(rawL.ang)
	else
		L.ang = Angle(rawL.ang.p, rawL.ang.y, rawL.ang.r)
	end
end

-- After VRMod_Tracking (ArcVR writes here) and collisions — before net / character / hands.
hook.Add("VRMod_TrackingModified", "vrmod_arcvr_wrist", RestoreDeviceWrist)
