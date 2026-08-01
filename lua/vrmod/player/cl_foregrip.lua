if SERVER then return end
-- =============================================================================
-- Stock / non-VR two-hand foregrip — port of gVRMod working implementation
-- (gVRMod/addon/gvrmod/lua/vrmod/player/cl_foregrip.lua)
--
-- Start: LH grip + hands within GRIP_DISTANCE + stock weapon + VMI
-- Hold:  guide RH aim from LH → write RH tracking → UpdateViewModelPos
--        → LH = fixed offset on g_VR.viewModelPos/Ang (matches drawn mesh)
--
-- x64: EnsureVMI (stock often has no preconfigured currentvmi)
--      stereo weapon snap for dual-eye freeze (does not change start rules)
-- ArcVR skipped (arcticvr_base owns those).
-- =============================================================================

local function BlockOldForegripAddon()
	for _, pair in ipairs({
		{ "VRMod_Input", "Foregrip" },
		{ "VRMod_PreRender", "ForegripTransform" },
		{ "VRMod_Exit", "ForegripExit" },
		{ "VRMod_PreStereo", "vrmod_foregrip" },
		{ "VRMod_PreRender", "vrmod_foregrip" },
		{ "VRMod_PreStereo", "0_vrmod_foregrip" },
		{ "VRMod_PreRender", "0_vrmod_foregrip" },
		{ "VRMod_PreStereo", "1_vrmod_weapon_pose_freeze" },
		{ "VRMod_Input", "vrmod_foregrip" },
	}) do
		local t = hook.GetTable()[pair[1]]
		if t and t[pair[2]] then hook.Remove(pair[1], pair[2]) end
	end
	if concommand.GetTable and concommand.GetTable()["vrmod_foregrip_test"] then
		concommand.Remove("vrmod_foregrip_test")
	end
end
BlockOldForegripAddon()
timer.Simple(0.5, BlockOldForegripAddon)
timer.Simple(2, BlockOldForegripAddon)
timer.Simple(10, BlockOldForegripAddon)

-- ===================== CONFIG (gVRMod) =====================
local GRIP_DISTANCE = 12 -- Units to start grip (hand proximity)
local GUIDE_BLEND = 0.45

-- ===================== STATE =====================
local state = {
	gripping = false,
	offsetPos = Vector(),
	offsetAng = Angle(),
	lastWep = nil,
	weaponBox = nil,
	frame = -1,
	bonesFrame = -1,
	gunPos = Vector(0, 0, 0),
	gunAng = Angle(0, 0, 0),
}

local function ClearGrip()
	state.gripping = false
	state.frame = -1
	state.bonesFrame = -1
	state.lastWep = nil
	state.weaponBox = nil
	g_VR._leftHandSnapFrame = -1
	local aw = IsValid(LocalPlayer()) and LocalPlayer():GetActiveWeapon() or NULL
	if not (IsValid(aw) and aw.ArcticVR and aw.ForegripGrabbed) then
		g_VR.foregripActive = false
	end
end

-- gVRMod weapon filter (+ skip ArcVR entities)
local function IsValidForegripWeapon(wep)
	if not IsValid(wep) then return false end
	if wep.ArcticVR or wep.ArcticVRNade then return false end
	local class = wep:GetClass():lower()
	if class == "weapon_vrmod_empty" then return false end
	if string.find(class, "weapon_fists", 1, true) then return false end
	if string.find(class, "arcticvr_", 1, true) then return false end
	if string.StartWith(class, "avrmag_") then return false end
	return true
end

--- Always set g_VR.currentvmi (gVRMod assumes it; stock often has none)
local function EnsureVMI(wep)
	if g_VR.currentvmi and g_VR.currentvmi.offsetPos and g_VR.currentvmi.offsetAng then
		return g_VR.currentvmi
	end
	local class = IsValid(wep) and wep:GetClass() or nil
	if class and g_VR.viewModelInfo and g_VR.viewModelInfo[class] then
		local e = g_VR.viewModelInfo[class]
		e.offsetPos = e.offsetPos or Vector(0, 0, 0)
		e.offsetAng = e.offsetAng or Angle(0, 0, 0)
		g_VR.currentvmi = e
		return e
	end
	g_VR.currentvmi = g_VR.currentvmi or {}
	g_VR.currentvmi.offsetPos = g_VR.currentvmi.offsetPos or Vector(0, 0, 0)
	g_VR.currentvmi.offsetAng = g_VR.currentvmi.offsetAng or Angle(0, 0, 0)
	return g_VR.currentvmi
end

local function GetCachedWeaponParams(wep, ply, side)
	if not (vrmod.utils and vrmod.utils.GetWeaponMeleeParams) then return nil end
	local radius, reach, mins, maxs, angles = vrmod.utils.GetWeaponMeleeParams(wep, ply, side)
	if radius == vrmod.DEFAULT_RADIUS and reach == vrmod.DEFAULT_REACH then return nil end
	return radius, reach, mins, maxs, angles
end

local function UpdateWeaponCollisionShape(ply, wep)
	timer.Simple(0.1, function()
		if not IsValid(ply) or not (g_VR and g_VR.active) then return end
		local radius, reach, mins, maxs, angles = GetCachedWeaponParams(wep, ply, "right")
		if radius and mins and maxs and angles and radius ~= vrmod.DEFAULT_RADIUS then
			timer.Simple(0, function()
				if not IsValid(ply) or not (g_VR and g_VR.active) then return end
				state.weaponBox = {
					mins = mins or Vector(-10, -10, -10),
					maxs = maxs or Vector(10, 10, 10),
					reach = reach or 20,
				}
			end)
		end
	end)
end

-- gVRMod: write guided pose into tracking SoT, then lock gun to hand
local function UpdateViewModelPos(pos, ang, override)
	if not g_VR.active then return end
	if g_VR.tracking and g_VR.tracking.pose_righthand and pos and ang then
		local rh = g_VR.tracking.pose_righthand
		if rh.pos and rh.pos.Set then rh.pos:Set(pos) else rh.pos = Vector(pos) end
		if rh.ang and rh.ang.Set then rh.ang:Set(ang) else rh.ang = Angle(ang.p, ang.y, ang.r) end
	end
	if vrmod.utils and vrmod.utils.UpdateViewModelPos then
		vrmod.utils.UpdateViewModelPos(pos, ang, override == nil and true or override)
	end
end

-- Two-handed pose with real weapon collision box awareness (gVRMod)
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

local function PublishSnap(sf, gunPos, gunAng)
	if not gunPos or not gunAng then return end
	g_VR._weaponSnapFrame = sf
	if not g_VR._weaponSnapPos then g_VR._weaponSnapPos = Vector() end
	if not g_VR._weaponSnapAng then g_VR._weaponSnapAng = Angle() end
	g_VR._weaponSnapPos:Set(gunPos)
	g_VR._weaponSnapAng:Set(gunAng)
end

local function StampLeft(attachPos, attachAng, sf)
	g_VR._leftHandSnapFrame = sf or (g_VR.stereoFrame or 0)
	if not g_VR._leftHandSnapPos then g_VR._leftHandSnapPos = Vector() end
	if not g_VR._leftHandSnapAng then g_VR._leftHandSnapAng = Angle() end
	g_VR._leftHandSnapPos:Set(attachPos)
	g_VR._leftHandSnapAng:Set(attachAng)

	if isfunction(vrmod.SetLeftHandPose) then
		vrmod.SetLeftHandPose(attachPos, attachAng)
	else
		local L = g_VR.tracking and g_VR.tracking.pose_lefthand
		if L then
			if L.pos and L.pos.Set then L.pos:Set(attachPos) else L.pos = Vector(attachPos) end
			if L.ang and L.ang.Set then L.ang:Set(attachAng) else L.ang = Angle(attachAng.p, attachAng.y, attachAng.r) end
		end
	end

	local netData = g_VR.net and g_VR.net[LocalPlayer():SteamID()]
	if netData and netData.lerpedFrame then
		netData.lerpedFrame.lefthandPos = Vector(attachPos)
		netData.lerpedFrame.lefthandAng = Angle(attachAng.p, attachAng.y, attachAng.r)
	end

	-- FBT may have already frozen device LH this frame — force re-solve
	local ply = LocalPlayer()
	if IsValid(ply) and vrmod_fbt and vrmod_fbt.characterInfo then
		local info = vrmod_fbt.characterInfo[ply:SteamID()]
		if info then info.frameNumber = -1 end
	end
	if g_VR._charIkUpdated then g_VR._charIkUpdated = nil end
end

--- gVRMod start rules: hands close + stock wep + VMI
local function TryStartGrip()
	if not g_VR or not g_VR.active then return false end
	if state.gripping then return true end
	-- Only block when UI is actively holding a panel with this grip
	if g_VR.menuResizeActive then return false end
	if g_VR.menuGrabActive then return false end

	local left = g_VR.tracking and g_VR.tracking.pose_lefthand
	local right = g_VR.tracking and g_VR.tracking.pose_righthand
	if not (left and right and left.pos and right.pos and left.ang and right.ang) then return false end

	local wep = LocalPlayer():GetActiveWeapon()
	if not IsValidForegripWeapon(wep) then return false end
	if left.pos:Distance(right.pos) > GRIP_DISTANCE then return false end

	local vmi = EnsureVMI(wep)
	if not vmi then return false end

	state.gripping = true
	state.lastWep = wep
	state.weaponBox = nil
	state.frame = -1
	state.bonesFrame = -1
	UpdateWeaponCollisionShape(LocalPlayer(), wep)

	-- Offset vs RH+VMI LocalToWorld (gVRMod exact)
	local wepWorldPos, wepWorldAng = LocalToWorld(
		vmi.offsetPos or Vector(),
		vmi.offsetAng or Angle(),
		right.pos, right.ang
	)
	state.offsetPos, state.offsetAng = WorldToLocal(left.pos, left.ang, wepWorldPos, wepWorldAng)
	g_VR.foregripActive = true
	return true
end

function vrmod.TryForegripGrab(pressed)
	if not g_VR or not g_VR.active then return false end
	if not pressed then
		if state.gripping then
			ClearGrip()
			return true
		end
		return false
	end
	if state.gripping then return true end
	return TryStartGrip()
end

function vrmod.IsForegripActive()
	return state.gripping and true or false
end

function vrmod.HasUniversalForegrip()
	return false
end

-- ===================== HOOKS (gVRMod order + names) =====================
-- Own input path so grip works even if cl_input order changes.
-- cl_input also calls TryForegripGrab first (before menu grab).
hook.Add("VRMod_Input", "vrmod_foregrip", function(action, pressed)
	if not g_VR.active then return end
	if not g_VR.tracking or not g_VR.tracking.pose_lefthand or not g_VR.tracking.pose_righthand then return end
	if action ~= "boolean_left_pickup" then return end
	if g_VR.menuResizeActive then
		if not pressed and state.gripping then ClearGrip() end
		return
	end
	-- Don't fight active panel free-grab, but never require menuFocus
	if g_VR.menuGrabActive and not state.gripping then return end

	vrmod.TryForegripGrab(pressed)
end)

-- gVRMod solves on PreRender with live tracking. We do the same, once per stereo frame.
local function SolveAndApply()
	if not state.gripping then return end
	if not g_VR.currentvmi then
		if IsValid(state.lastWep) then EnsureVMI(state.lastWep) end
		if not g_VR.currentvmi then
			ClearGrip()
			return
		end
	end

	local left = g_VR.tracking and g_VR.tracking.pose_lefthand
	local right = g_VR.tracking and g_VR.tracking.pose_righthand
	if not left or not right or not left.pos or not right.pos then
		ClearGrip()
		return
	end

	-- Box-aware safety release (gVRMod)
	local maxDist = state.weaponBox and state.weaponBox.reach and state.weaponBox.reach * 1.35 or 20
	if left.pos:Distance(right.pos) > maxDist then
		ClearGrip()
		return
	end

	local sf = g_VR.stereoFrame or 0
	if state.frame == sf and state.gunPos then
		-- Second eye / re-entry: reassert frozen gun + LH
		if g_VR.viewModelPos and g_VR.viewModelAng then
			g_VR.viewModelPos = Vector(state.gunPos)
			g_VR.viewModelAng = Angle(state.gunAng.p, state.gunAng.y, state.gunAng.r)
		end
		local vm = g_VR.viewModel
		if IsValid(vm) then
			vm:SetPos(state.gunPos)
			vm:SetAngles(state.gunAng)
		end
		PublishSnap(sf, state.gunPos, state.gunAng)
		if g_VR._leftHandSnapPos and g_VR._leftHandSnapAng then
			StampLeft(g_VR._leftHandSnapPos, g_VR._leftHandSnapAng, sf)
		end
		return
	end

	local guidedPos, guidedAng = GetGuidedWeaponPose(
		right.pos, right.ang, left.pos, left.ang, state.weaponBox
	)
	-- gVRMod: tracking RH = guided, then official viewmodel update
	UpdateViewModelPos(guidedPos, guidedAng, true)

	local gunPos = g_VR.viewModelPos
	local gunAng = g_VR.viewModelAng
	if not gunPos or not gunAng then
		ClearGrip()
		return
	end

	-- Attach left hand to weapon (gVRMod)
	local attachPos, attachAng = LocalToWorld(state.offsetPos, state.offsetAng, gunPos, gunAng)

	state.gunPos:Set(gunPos)
	state.gunAng:Set(gunAng)
	state.frame = sf
	state.bonesFrame = -1
	g_VR.foregripActive = true

	PublishSnap(sf, gunPos, gunAng)
	StampLeft(attachPos, attachAng, sf)

	local vm = g_VR.viewModel
	if not IsValid(vm) then
		local ply = LocalPlayer()
		if IsValid(ply) then
			vm = ply:GetViewModel()
			if IsValid(vm) then g_VR.viewModel = vm end
		end
	end
	if IsValid(vm) then
		vm:SetPos(gunPos)
		vm:SetAngles(gunAng)
		vm:SetupBones()
		state.bonesFrame = sf
		local muz = vm:GetAttachment(1)
		if muz and muz.Pos then
			g_VR.viewModelMuzzle = muz
		else
			g_VR.viewModelMuzzle = {
				Pos = gunPos + gunAng:Forward() * 14,
				Ang = Angle(gunAng.p, gunAng.y, gunAng.r),
			}
		end
	end
end

-- Prefer PreStereo so LH snap is ready before FBT/body; PreRender reasserts
hook.Add("VRMod_PreStereo", "0_vrmod_foregrip", function()
	if not g_VR or not g_VR.active then return end
	if state.gripping then SolveAndApply() end
end)

hook.Add("VRMod_PreRender", "vrmod_foregrip", function()
	if not g_VR or not g_VR.active then return end
	if state.gripping then SolveAndApply() end
end)

-- Non-grip stock freeze both eyes
hook.Add("VRMod_PreStereo", "1_vrmod_weapon_pose_freeze", function()
	if not g_VR or not g_VR.active then return end
	if state.gripping then return end
	if vrmod.suppressViewModelUpdates then
		if g_VR.viewModelPos and g_VR.viewModelAng then
			PublishSnap(g_VR.stereoFrame or 0, g_VR.viewModelPos, g_VR.viewModelAng)
		end
		return
	end
	if vrmod.utils and vrmod.utils.UpdateViewModelPos then
		local sp = g_VR.stereoPose
		local sf = g_VR.stereoFrame or 0
		if sp and sp.frame == sf and sp.hasRight then
			pcall(vrmod.utils.UpdateViewModelPos, sp.rightPos, sp.rightAng, true)
		else
			pcall(vrmod.utils.UpdateViewModelPos)
		end
	end
	if g_VR.viewModelPos and g_VR.viewModelAng then
		PublishSnap(g_VR.stereoFrame or 0, g_VR.viewModelPos, g_VR.viewModelAng)
	end
end)

hook.Add("VRMod_Exit", "vrmod_foregrip", function() ClearGrip() end)
hook.Add("PlayerSwitchWeapon", "vrmod_foregrip", function(ply)
	if ply == LocalPlayer() then ClearGrip() end
end)
hook.Add("PlayerDeath", "vrmod_foregrip", function(ply)
	if ply == LocalPlayer() then ClearGrip() end
end)
