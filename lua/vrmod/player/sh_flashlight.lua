if CLIENT then
	local convars, convarValues = vrmod.AddCallbackedConvar("vrmod_flashlight_attachment", nil, "0", nil, nil, 0, 2, function(val) return math.floor(tonumber(val) or 0) end)
	local attachments = {"pose_righthand", "pose_lefthand", "hmd",}
	local flashlight = nil
	net.Receive("vrmod_flashlight", function()
		local enabled = net.ReadBool()
		if not flashlight and enabled then
			surface.PlaySound("items/flashlight1.wav")
			flashlight = ProjectedTexture()
			flashlight:SetTexture("effects/flashlight001")
			flashlight:SetFOV(GetConVar("r_flashlightfov"):GetFloat())
			flashlight:SetFarZ(GetConVar("r_flashlightfar"):GetFloat())
			hook.Add("VRMod_PreRender", "flashlight", function()
				if not g_VR.threePoints then return end
				local pos = g_VR.tracking[attachments[convarValues.vrmod_flashlight_attachment + 1]].pos
				local ang = g_VR.tracking[attachments[convarValues.vrmod_flashlight_attachment + 1]].ang
				if convarValues.vrmod_flashlight_attachment == 0 and g_VR.viewModelMuzzle then
					pos = g_VR.viewModelMuzzle.Pos
					if not (g_VR.currentvmi and g_VR.currentvmi.wrongMuzzleAng) then ang = g_VR.viewModelMuzzle.Ang end
				end

				flashlight:SetPos(pos + ang:Forward() * 10)
				flashlight:SetAngles(ang)
				flashlight:Update()
			end)
		elseif flashlight then
			surface.PlaySound("items/flashlight1.wav")
			hook.Remove("VRMod_PreRender", "flashlight")
			flashlight:Remove()
			flashlight = nil
		end
	end)

	hook.Add("VRMod_Exit", "flashlight", function(ply, steamid)
		if ply == LocalPlayer() and flashlight then
			hook.Remove("VRMod_PreRender", "flashlight")
			flashlight:Remove()
			flashlight = nil
		end
	end)
elseif SERVER then
	util.AddNetworkString("vrmod_flashlight")
	local skip = false
	hook.Add("PlayerSwitchFlashlight", "vrmod_flashlight", function(ply, enabled)
		if skip then return end
		if g_VR[ply:SteamID()] then
			skip = true
			local res = hook.Run("PlayerSwitchFlashlight", ply, enabled)
			skip = false
			if res == false then return end
			net.Start("vrmod_flashlight")
			net.WriteBool(ply.m_bFlashlight ~= false and enabled)
			net.Send(ply)
			if enabled then
				return false --don't turn on the default flashlight cus we're using a custom one for vr
			end
		end
	end)
end