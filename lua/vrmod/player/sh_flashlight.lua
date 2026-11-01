if CLIENT then
	local _, convarValues = vrmod.AddCallbackedConvar("vrmod_flashlight_attachment", nil, "0", nil, nil, 0, 2, function(val)
		return math.floor(tonumber(val) or 0)
	end)
	vrmod.AddCallbackedConvar("vrmod_flashlight_aim", nil, "0", FCVAR_ARCHIVE, "0 right, 1 left, 2 hmd, 3 eye tracking", 0, 3, function(val)
		local n = math.floor(tonumber(val) or 0)
		if n < 0 or n > 3 then return 0 end
		return n
	end)
	vrmod.AddCallbackedConvar("vrmod_flashlight_eye_fallback", nil, "0", FCVAR_ARCHIVE, "Hand used when flashlight aim is eye tracking but gaze is off. 0 right, 1 left", 0, 1, function(val)
		local n = math.floor(tonumber(val) or 0)
		if n ~= 1 then return 0 end
		return n
	end)
	-- One-time copy of the old 0..2 attachment into the aim convar.
	-- CreateConVar will not widen an existing max, so aim is a new convar.
	local migName = "vrmod_flashlight_aim_migrated"
	local mig = GetConVar(migName)
	if not mig then
		mig = CreateConVar(migName, "0", FCVAR_ARCHIVE or 128, "Copied vrmod_flashlight_attachment into vrmod_flashlight_aim once")
	end
	if mig and not mig:GetBool() then
		local old = math.floor(tonumber(convarValues.vrmod_flashlight_attachment) or 0)
		if old >= 1 and old <= 2 then
			convarValues.vrmod_flashlight_aim = old
			local aimCv = GetConVar("vrmod_flashlight_aim")
			if aimCv and aimCv.SetInt then pcall(function() aimCv:SetInt(old) end) end
			RunConsoleCommand("vrmod_flashlight_aim", tostring(old))
		end
		if mig.SetInt then pcall(function() mig:SetInt(1) end) end
		RunConsoleCommand(migName, "1")
	end

	local function currentAim()
		local aim = convarValues.vrmod_flashlight_aim
		if aim == nil then aim = convarValues.vrmod_flashlight_attachment or 0 end
		local fallback = convarValues.vrmod_flashlight_eye_fallback
		if fallback == nil then fallback = 0 end
		return aim, fallback
	end

	local function trackingPose(key)
		local t = g_VR.tracking and g_VR.tracking[key]
		if not t or not t.pos or not t.ang then return nil, nil end
		return t.pos, t.ang
	end

	local function poseForSource(source)
		if source == "eye" then
			if vrmod.GetEyeGaze then return vrmod.GetEyeGaze(LocalPlayer()) end
			return nil, nil
		end
		if source == "left" then return trackingPose("pose_lefthand") end
		if source == "hmd" then return trackingPose("hmd") end
		local pos, ang = trackingPose("pose_righthand")
		local muzzle = g_VR.viewModelMuzzle
		if muzzle and muzzle.Pos and muzzle.Ang then
			pos = muzzle.Pos
			if not (g_VR.currentvmi and g_VR.currentvmi.wrongMuzzleAng) then ang = muzzle.Ang end
		end
		return pos, ang
	end

	local function decideAim()
		local aim, fallback = currentAim()
		local enabled = vrmod.EyeTrackingEnabled and vrmod.EyeTrackingEnabled() or false
		local allowed = true
		if vrmod.EyeTrackingAllowed then allowed = vrmod.EyeTrackingAllowed() end
		local et = g_VR.eyeTracking
		local active = et and et.active and et.pos and et.ang
		if not vrmod.utils.FlashlightAim_Decide then
			return { source = "right", used_fallback = false, reason = "aim" }
		end
		return vrmod.utils.FlashlightAim_Decide({
			aim = aim,
			fallback = fallback,
			eye_enabled = enabled and allowed,
			eye_active = active and true or false,
		})
	end

	local flashlight = nil
	net.Receive("vrmod_flashlight", function()
		local enabled = net.ReadBool()
		if not flashlight and enabled then
			surface.PlaySound("items/flashlight1.wav")
			flashlight = ProjectedTexture()
			flashlight:SetTexture("effects/flashlight001")
			flashlight:SetFOV(GetConVar("r_flashlightfov"):GetFloat())
			flashlight:SetFarZ(GetConVar("r_flashlightfar"):GetFloat())
			-- Update on each stereo eye — one Update is consumed by one RenderView.
			hook.Add("VRMod_PreRender", "flashlight", function(eye)
				if eye ~= "left" and eye ~= "right" then return end
				if not g_VR.threePoints then return end
				local decision = decideAim()
				local pos, ang = poseForSource(decision.source)
				if decision.source == "eye" and (not pos or not ang) then
					local _, fallback = currentAim()
					decision = vrmod.utils.FlashlightAim_Decide({
						aim = 3,
						fallback = fallback,
						eye_enabled = false,
						eye_active = false,
					})
					pos, ang = poseForSource(decision.source)
				end
				if not pos or not ang then return end
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