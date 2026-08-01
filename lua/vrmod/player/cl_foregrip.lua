if SERVER then return end
-- =============================================================================
-- Foregrip (two-hand weapon aim) — stereo-stable
--
-- BUG was: VRMod_PreRender runs per eye. UpdateViewModelPos wrote guided pose
-- into tracking.pose_righthand, then the second eye guided again on top of that
-- → different gun matrix L vs R (double vision while gripping).
--
-- Fix: solve once on VRMod_PreStereo from frozen stereoPose hands; eyes only draw.
-- =============================================================================

local function BlockOldForegripAddon()
	local blocked = false
	if hook.GetTable()["VRMod_Input"] and hook.GetTable()["VRMod_Input"]["Foregrip"] then
		hook.Remove("VRMod_Input", "Foregrip")
		blocked = true
	end
	if hook.GetTable()["VRMod_PreRender"] and hook.GetTable()["VRMod_PreRender"]["ForegripTransform"] then
		hook.Remove("VRMod_PreRender", "ForegripTransform")
		blocked = true
	end
	if hook.GetTable()["VRMod_Exit"] and hook.GetTable()["VRMod_Exit"]["ForegripExit"] then
		hook.Remove("VRMod_Exit", "ForegripExit")
		blocked = true
	end
	if concommand.GetTable and concommand.GetTable()["vrmod_foregrip_test"] then
		concommand.Remove("vrmod_foregrip_test")
	end
	if blocked and vrmod.logger then
		vrmod.logger.Warn("Delete Universal ForeGrip addon, vrmod now has a proper implementation")
	end
end

BlockOldForegripAddon()
timer.Simple(0.5, BlockOldForegripAddon)
timer.Simple(2, BlockOldForegripAddon)

local GRIP_DISTANCE = 12
local GUIDE_BLEND = 0.45

local state = {
	gripping = false,
	offsetPos = Vector(),
	offsetAng = Angle(),
	lastWep = nil,
	weaponBox = nil,
	-- Frozen draw pose for this stereo frame
	frame = -1,
	gunPos = nil,
	gunAng = nil,
	leftPos = nil,
	leftAng = nil,
}

local function GetCachedWeaponParams(wep, ply, side)
	local radius, reach, mins, maxs, angles = vrmod.utils.GetWeaponMeleeParams(wep, ply, side)
	if radius == vrmod.DEFAULT_RADIUS and reach == vrmod.DEFAULT_REACH then return nil end
	return radius, reach, mins, maxs, angles
end

local function UpdateWeaponCollisionShape(ply, wep)
	timer.Simple(0.1, function()
		if not IsValid(ply) or not vrmod.IsPlayerInVR(ply) then return end
		local radius, reach, mins, maxs, angles = GetCachedWeaponParams(wep, ply, "right")
		if radius and mins and maxs and angles and radius ~= vrmod.DEFAULT_RADIUS then
			timer.Simple(0, function()
				if not IsValid(ply) or not vrmod.IsPlayerInVR(ply) then return end
				state.weaponBox = {
					mins = mins or Vector(-10, -10, -10),
					maxs = maxs or Vector(10, 10, 10),
					reach = reach or 20,
				}
			end)
		end
	end)
end

local function IsValidForegripWeapon(wep)
	if not IsValid(wep) then return false end
	local class = wep:GetClass():lower()
	return not (string.find(class, "weapon_fists") or string.find(class, "arcticvr_") or class == "weapon_vrmod_empty")
end

local function GetGuidedWeaponPose(rightPos, rightAng, leftPos, leftAng, box)
	if GUIDE_BLEND <= 0 then return rightPos, rightAng end
	local toLeft = leftPos - rightPos
	local dist = toLeft:Length()
	local maxDist = box and box.reach and box.reach * 1.55 or 26
	if dist > maxDist then return rightPos, rightAng end
	local minDist = box and box.mins and math.max(math.abs(box.mins.y), 4.5) or 5.5
	if dist < minDist then return rightPos, rightAng end
	local targetAng = toLeft:GetNormalized():Angle()
	local newAng = LerpAngle(GUIDE_BLEND, rightAng, targetAng)
	newAng.r = rightAng.r
	return rightPos, newAng
end

--- Read frozen stereo hands (preferred) or live tracking.
local function StereoHands()
	local sp = g_VR.stereoPose
	local sf = g_VR.stereoFrame or 0
	if sp and sp.frame == sf and sp.hasLeft and sp.hasRight then
		return sp.leftPos, sp.leftAng, sp.rightPos, sp.rightAng
	end
	local L = g_VR.tracking and g_VR.tracking.pose_lefthand
	local R = g_VR.tracking and g_VR.tracking.pose_righthand
	if not (L and R and L.pos and R.pos) then return nil end
	return L.pos, L.ang, R.pos, R.ang
end

--- Solve two-hand pose ONCE for this stereo frame. Never re-run per eye.
local function SolveForegripFrame()
	if not state.gripping or not g_VR.currentvmi then
		state.gripping = false
		return false
	end
	local sf = g_VR.stereoFrame or 0
	if state.frame == sf and state.gunPos and state.gunAng then
		return true
	end

	local lpos, lang, rpos, rang = StereoHands()
	if not lpos or not rpos then
		state.gripping = false
		return false
	end

	local maxDist = state.weaponBox and state.weaponBox.reach and state.weaponBox.reach * 1.35 or 20
	if lpos:Distance(rpos) > maxDist then
		state.gripping = false
		return false
	end

	-- Guide from RAW stereo hands only (never from already-guided RH)
	local guidedPos, guidedAng = GetGuidedWeaponPose(rpos, rang, lpos, lang, state.weaponBox)

	-- Apply gun to hand-guided pose (override suppress)
	if vrmod.utils and vrmod.utils.UpdateViewModelPos then
		-- Temporarily write guided into tracking for UpdateViewModelPos readers,
		-- but restore tracking from stereoPose after so second eye isn't double-guided.
		local R = g_VR.tracking and g_VR.tracking.pose_righthand
		local savedPos, savedAng
		if R and R.pos and R.ang then
			savedPos = Vector(R.pos)
			savedAng = Angle(R.ang.p, R.ang.y, R.ang.r)
			R.pos:Set(guidedPos)
			R.ang:Set(guidedAng)
		end
		pcall(vrmod.utils.UpdateViewModelPos, guidedPos, guidedAng, true)
		if R and savedPos and savedAng then
			R.pos:Set(savedPos)
			R.ang:Set(savedAng)
		end
	end

	local gunPos = g_VR.viewModelPos
	local gunAng = g_VR.viewModelAng
	if not gunPos or not gunAng then
		state.gripping = false
		return false
	end

	local attachPos, attachAng = LocalToWorld(state.offsetPos, state.offsetAng, gunPos, gunAng)

	if not state.gunPos then state.gunPos = Vector() end
	if not state.gunAng then state.gunAng = Angle() end
	if not state.leftPos then state.leftPos = Vector() end
	if not state.leftAng then state.leftAng = Angle() end
	state.gunPos:Set(gunPos)
	state.gunAng:Set(gunAng)
	state.leftPos:Set(attachPos)
	state.leftAng:Set(attachAng)
	state.frame = sf

	-- Left hand visual attach (once)
	if vrmod.SetLeftHandPose then
		vrmod.SetLeftHandPose(state.leftPos, state.leftAng)
	end
	local netData = g_VR.net and g_VR.net[LocalPlayer():SteamID()]
	if netData and netData.lerpedFrame then
		netData.lerpedFrame.lefthandPos = state.leftPos
		netData.lerpedFrame.lefthandAng = state.leftAng
	end

	return true
end

--- Per-eye: only re-stamp frozen gun matrix (no re-guide).
local function ApplyFrozenGunDraw()
	if not state.gripping then return end
	local sf = g_VR.stereoFrame or 0
	if state.frame ~= sf or not state.gunPos then return end
	local vm = g_VR.viewModel
	if not IsValid(vm) then return end
	-- Keep draw path on the same matrix both eyes
	g_VR.viewModelPos = state.gunPos
	g_VR.viewModelAng = state.gunAng
	vm:SetPos(state.gunPos)
	vm:SetAngles(state.gunAng)
	-- SetupBones only on first eye of the frame
	if state.bonesFrame ~= sf then
		vm:SetupBones()
		state.bonesFrame = sf
		-- Refresh muzzle from frozen gun for laser
		if vrmod.utils and vrmod.utils.UpdateViewModel then
			-- UpdateViewModel would re-pose from hand — only refresh muzzle attachment
			local muz = vm:GetAttachment(1)
			if muz and muz.Pos then
				g_VR.viewModelMuzzle = muz
			else
				g_VR.viewModelMuzzle = {
					Pos = state.gunPos + state.gunAng:Forward() * 14,
					Ang = Angle(state.gunAng.p, state.gunAng.y, state.gunAng.r),
				}
			end
		end
	end
end

hook.Add("VRMod_Input", "vrmod_foregrip", function(action, pressed)
	if not g_VR.active or not g_VR.tracking or not g_VR.tracking.pose_lefthand or not g_VR.tracking.pose_righthand then return end
	if action ~= "boolean_left_pickup" then return end
	-- Don't steal grip when laser is on a menu
	if g_VR.menuFocus or g_VR.menuGrabActive then
		if not pressed then state.gripping = false end
		return
	end
	local left = g_VR.tracking.pose_lefthand
	local right = g_VR.tracking.pose_righthand
	local wep = LocalPlayer():GetActiveWeapon()
	if pressed and left.pos:Distance(right.pos) <= GRIP_DISTANCE and IsValidForegripWeapon(wep) and g_VR.currentvmi then
		state.gripping = true
		state.lastWep = wep
		state.weaponBox = nil
		state.frame = -1
		if IsValid(wep) then UpdateWeaponCollisionShape(LocalPlayer(), wep) end
		local wepWorldPos, wepWorldAng = LocalToWorld(
			g_VR.currentvmi.offsetPos or Vector(),
			g_VR.currentvmi.offsetAng or Angle(),
			right.pos, right.ang
		)
		state.offsetPos, state.offsetAng = WorldToLocal(left.pos, left.ang, wepWorldPos, wepWorldAng)
	else
		state.gripping = false
		state.frame = -1
	end
end)

-- Solve once before either eye
hook.Add("VRMod_PreStereo", "vrmod_foregrip", function()
	if not g_VR.active then return end
	if state.gripping then
		SolveForegripFrame()
	end
end)

-- Per eye: only apply frozen gun (no second guide solve)
hook.Add("VRMod_PreRender", "vrmod_foregrip", function()
	if state.gripping then
		ApplyFrozenGunDraw()
	end
end)

hook.Add("VRMod_Exit", "vrmod_foregrip", function()
	state.gripping = false
	state.frame = -1
end)

hook.Add("PlayerSwitchWeapon", "vrmod_foregrip", function(ply)
	if ply == LocalPlayer() then
		state.gripping = false
		state.frame = -1
	end
end)

-- Also freeze bare viewmodel SetupBones when not foregripping (stock double-vision)
hook.Add("VRMod_PreStereo", "vrmod_weapon_pose_freeze", function()
	if not g_VR or not g_VR.active then return end
	if state.gripping then return end -- foregrip owns freeze
	if vrmod.utils and vrmod.utils.UpdateViewModelPos then
		local sp = g_VR.stereoPose
		local sf = g_VR.stereoFrame or 0
		if sp and sp.frame == sf and sp.hasRight then
			pcall(vrmod.utils.UpdateViewModelPos, sp.rightPos, sp.rightAng, true)
		else
			pcall(vrmod.utils.UpdateViewModelPos)
		end
	end
	-- Snapshot gun world matrix for both eyes
	if g_VR.viewModelPos and g_VR.viewModelAng then
		g_VR._weaponSnapFrame = g_VR.stereoFrame
		if not g_VR._weaponSnapPos then g_VR._weaponSnapPos = Vector() end
		if not g_VR._weaponSnapAng then g_VR._weaponSnapAng = Angle() end
		g_VR._weaponSnapPos:Set(g_VR.viewModelPos)
		g_VR._weaponSnapAng:Set(g_VR.viewModelAng)
	end
end)
