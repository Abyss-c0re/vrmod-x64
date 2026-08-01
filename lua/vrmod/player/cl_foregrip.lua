if SERVER then return end
-- =============================================================================
-- Stock / non-VR foregrip (two-hand aim) — stereo-stable
--
-- ArcVR TwoHanded weapons: arcticvr_base (GripForegrip + AVR_GunTracking).
-- This file only handles stock/non-VR SWEPs.
--
-- Grab: left grip while hands near each other (or LH near gun).
-- Hold: cleared on grip release input (not flaky continuous poll alone).
-- Pose: solve once on PreStereo from stereoPose; eyes only stamp snap.
-- =============================================================================

local function BlockOldForegripAddon()
	for _, pair in ipairs({
		{ "VRMod_Input", "Foregrip" },
		{ "VRMod_PreRender", "ForegripTransform" },
		{ "VRMod_Exit", "ForegripExit" },
	}) do
		local t = hook.GetTable()[pair[1]]
		if t and t[pair[2]] then hook.Remove(pair[1], pair[2]) end
	end
	if concommand.GetTable and concommand.GetTable()["vrmod_foregrip_test"] then
		concommand.Remove("vrmod_foregrip_test")
	end
end
BlockOldForegripAddon()
timer.Simple(1, BlockOldForegripAddon)

-- Fresh cvar names so old client.vdf "12" archive cannot keep start range tiny
local cv_dist = CreateClientConVar("vrmod_stock_foregrip_distance", "28", true, FCVAR_ARCHIVE,
	"Max hand distance to start stock two-hand grip", 8, 64)
local cv_blend = CreateClientConVar("vrmod_stock_foregrip_blend", "0.45", true, FCVAR_ARCHIVE,
	"Stock aim blend toward support hand (0–1)", 0, 1)
local cv_release = CreateClientConVar("vrmod_stock_foregrip_release", "1.6", true, FCVAR_ARCHIVE,
	"Release multiplier × start/hand distance", 1.1, 3)

local state = {
	gripping = false,
	offsetPos = Vector(0, 0, 0),
	offsetAng = Angle(0, 0, 0),
	wep = NULL,
	class = nil,
	frame = -1,
	bonesFrame = -1,
	gunPos = Vector(0, 0, 0),
	gunAng = Angle(0, 0, 0),
	leftPos = Vector(0, 0, 0),
	leftAng = Angle(0, 0, 0),
	startDist = 16,
}

local function ClearGrip(reason)
	local was = state.gripping
	state.gripping = false
	state.frame = -1
	state.bonesFrame = -1
	state.wep = NULL
	state.class = nil
	-- Do not clear g_VR.foregripActive if ArcVR still owns it
	local wep = IsValid(LocalPlayer()) and LocalPlayer():GetActiveWeapon() or NULL
	if not (IsValid(wep) and wep.ArcticVR and wep.ForegripGrabbed) then
		g_VR.foregripActive = false
	end
	if was and reason and vrmod.logger then
		vrmod.logger.Debug("[stock-foregrip] clear: %s", tostring(reason))
	end
end

local function IsStockForegripWeapon(wep)
	if not IsValid(wep) then return false end
	if wep.ArcticVR or wep.ArcticVRNade then return false end
	local class = string.lower(wep:GetClass() or "")
	if class == "" or class == "weapon_vrmod_empty" then return false end
	if class:find("weapon_fists", 1, true) then return false end
	if class:StartWith("arcticvr") or class:StartWith("avrmag_") then return false end
	return true
end

local function EnsureVMI(wep)
	if g_VR.currentvmi and g_VR.currentvmi.offsetPos and g_VR.currentvmi.offsetAng then
		return g_VR.currentvmi
	end
	local class = IsValid(wep) and wep:GetClass() or nil
	if class and g_VR.viewModelInfo and g_VR.viewModelInfo[class] then
		local e = g_VR.viewModelInfo[class]
		if not e.offsetPos then e.offsetPos = Vector(0, 0, 0) end
		if not e.offsetAng then e.offsetAng = Angle(0, 0, 0) end
		g_VR.currentvmi = e
		return e
	end
	if not g_VR.currentvmi then
		g_VR.currentvmi = { offsetPos = Vector(0, 0, 0), offsetAng = Angle(0, 0, 0) }
	else
		if not g_VR.currentvmi.offsetPos then g_VR.currentvmi.offsetPos = Vector(0, 0, 0) end
		if not g_VR.currentvmi.offsetAng then g_VR.currentvmi.offsetAng = Angle(0, 0, 0) end
	end
	return g_VR.currentvmi
end

local function LiveHands()
	local L = g_VR.tracking and g_VR.tracking.pose_lefthand
	local R = g_VR.tracking and g_VR.tracking.pose_righthand
	if not (L and R and L.pos and R.pos and L.ang and R.ang) then return nil end
	return L.pos, L.ang, R.pos, R.ang
end

local function StereoHands()
	local sp = g_VR.stereoPose
	local sf = g_VR.stereoFrame or 0
	if sp and sp.frame == sf and sp.hasLeft and sp.hasRight then
		return sp.leftPos, sp.leftAng, sp.rightPos, sp.rightAng
	end
	return LiveHands()
end

local function ReleaseMaxDist()
	local mult = math.Clamp(cv_release:GetFloat(), 1.1, 3)
	return math.max(state.startDist * mult, cv_dist:GetFloat() * mult, 24)
end

local function GetGuidedWeaponPose(rightPos, rightAng, leftPos, leftAng)
	local blend = math.Clamp(cv_blend:GetFloat(), 0, 1)
	if blend <= 0 then return rightPos, rightAng end
	local toLeft = leftPos - rightPos
	local dist = toLeft:Length()
	if dist > ReleaseMaxDist() or dist < 0.05 then return rightPos, rightAng end
	if dist < 4 then return rightPos, rightAng end
	local targetAng = toLeft:GetNormalized():Angle()
	local newAng = LerpAngle(blend, rightAng, targetAng)
	newAng.r = rightAng.r
	return rightPos, newAng
end

local function PublishWeaponSnap(sf, gunPos, gunAng)
	g_VR._weaponSnapFrame = sf
	if not g_VR._weaponSnapPos then g_VR._weaponSnapPos = Vector() end
	if not g_VR._weaponSnapAng then g_VR._weaponSnapAng = Angle() end
	g_VR._weaponSnapPos:Set(gunPos)
	g_VR._weaponSnapAng:Set(gunAng)
	g_VR.viewModelPos = g_VR._weaponSnapPos
	g_VR.viewModelAng = g_VR._weaponSnapAng
end

local function StampLeft(sf)
	if vrmod.SetLeftHandPose then
		vrmod.SetLeftHandPose(state.leftPos, state.leftAng, 0)
	elseif g_VR.tracking and g_VR.tracking.pose_lefthand then
		local L = g_VR.tracking.pose_lefthand
		if L.pos.Set then L.pos:Set(state.leftPos) else L.pos = state.leftPos end
		if L.ang.Set then L.ang:Set(state.leftAng) else L.ang = state.leftAng end
	end
	local sp = g_VR.stereoPose
	if sp and sp.frame == sf then
		if not sp.leftPos then sp.leftPos = Vector() end
		if not sp.leftAng then sp.leftAng = Angle() end
		sp.leftPos:Set(state.leftPos)
		sp.leftAng:Set(state.leftAng)
		sp.hasLeft = true
	end
end

local function SolveForegripFrame()
	if not state.gripping then return false end

	-- Explicit release only when input reports false (nil keeps grip — avoids flaky poll)
	local inp = g_VR.input
	if inp and inp.boolean_left_pickup == false then
		ClearGrip("grip released")
		return false
	end

	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:Alive() then
		ClearGrip("dead")
		return false
	end

	local wep = IsValid(state.wep) and state.wep or ply:GetActiveWeapon() or NULL
	if not IsStockForegripWeapon(wep) then
		ClearGrip("invalid weapon")
		return false
	end
	if state.class and wep:GetClass() ~= state.class then
		ClearGrip("weapon switched")
		return false
	end
	if g_VR.menuGrabActive or g_VR.menuResizeActive then
		ClearGrip("menu grab")
		return false
	end

	local vmi = EnsureVMI(wep)
	local sf = g_VR.stereoFrame or 0
	if state.frame == sf then
		PublishWeaponSnap(sf, state.gunPos, state.gunAng)
		StampLeft(sf)
		return true
	end

	local lpos, lang, rpos, rang = StereoHands()
	if not lpos or not rpos then
		-- Don't clear on one bad frame
		return false
	end

	if lpos:Distance(rpos) > ReleaseMaxDist() then
		ClearGrip("hands too far")
		return false
	end

	local guidedPos, guidedAng = GetGuidedWeaponPose(rpos, rang, lpos, lang)
	if vrmod.utils and vrmod.utils.UpdateViewModelPos then
		pcall(vrmod.utils.UpdateViewModelPos, guidedPos, guidedAng, true)
	end

	local gunPos = g_VR.viewModelPos
	local gunAng = g_VR.viewModelAng
	if not gunPos or not gunAng then
		gunPos, gunAng = LocalToWorld(vmi.offsetPos or Vector(), vmi.offsetAng or Angle(), guidedPos, guidedAng)
		g_VR.viewModelPos = gunPos
		g_VR.viewModelAng = gunAng
	end

	local attachPos, attachAng = LocalToWorld(state.offsetPos, state.offsetAng, gunPos, gunAng)
	state.gunPos:Set(gunPos)
	state.gunAng:Set(gunAng)
	state.leftPos:Set(attachPos)
	state.leftAng:Set(attachAng)
	state.frame = sf
	state.bonesFrame = -1

	PublishWeaponSnap(sf, state.gunPos, state.gunAng)
	g_VR.foregripActive = true
	StampLeft(sf)
	return true
end

local function ApplyFrozenGunDraw()
	if not state.gripping then return end
	local sf = g_VR.stereoFrame or 0
	if state.frame ~= sf then return end
	local vm = g_VR.viewModel
	if not IsValid(vm) then
		local ply = LocalPlayer()
		if IsValid(ply) then vm = ply:GetViewModel() end
	end
	if not IsValid(vm) then return end

	PublishWeaponSnap(sf, state.gunPos, state.gunAng)
	vm:SetPos(state.gunPos)
	vm:SetAngles(state.gunAng)
	if state.bonesFrame ~= sf then
		vm:SetupBones()
		state.bonesFrame = sf
		local muz = vm:GetAttachment(1)
		if muz and muz.Pos and muz.Pos:DistToSqr(state.gunPos) < (100 * 100) then
			g_VR.viewModelMuzzle = muz
		else
			g_VR.viewModelMuzzle = {
				Pos = state.gunPos + state.gunAng:Forward() * 14,
				Ang = Angle(state.gunAng.p, state.gunAng.y, state.gunAng.r),
			}
		end
	end
	StampLeft(sf)
end

local function TryStartGrip()
	if not g_VR or not g_VR.active then return false end
	if state.gripping then return true end
	if g_VR.menuGrabActive or g_VR.menuResizeActive then return false end
	if g_VR.avatarSteerTwin then return false end

	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:Alive() then return false end

	local lpos, lang, rpos, rang = LiveHands()
	if not lpos then return false end

	local wep = ply:GetActiveWeapon()
	if not IsStockForegripWeapon(wep) then return false end

	local dist = lpos:Distance(rpos)
	local maxStart = math.max(cv_dist:GetFloat(), 20)

	-- Hands close OR left hand near right hand / gun forward
	local near = dist <= maxStart
	if not near then
		local vmi = EnsureVMI(wep)
		local gunPos, gunAng = g_VR.viewModelPos, g_VR.viewModelAng
		if not gunPos or not gunAng then
			gunPos, gunAng = LocalToWorld(vmi.offsetPos or Vector(), vmi.offsetAng or Angle(), rpos, rang)
		end
		local fore = gunPos + gunAng:Forward() * 12
		near = lpos:DistToSqr(fore) <= (maxStart * maxStart)
			or lpos:DistToSqr(rpos) <= (maxStart * maxStart)
	end
	if not near then return false end

	local vmi = EnsureVMI(wep)
	local wepWorldPos, wepWorldAng = LocalToWorld(
		vmi.offsetPos or Vector(),
		vmi.offsetAng or Angle(),
		rpos, rang
	)
	state.offsetPos, state.offsetAng = WorldToLocal(lpos, lang, wepWorldPos, wepWorldAng)
	state.gripping = true
	state.wep = wep
	state.class = wep:GetClass()
	state.frame = -1
	state.bonesFrame = -1
	state.startDist = math.max(dist, 8)
	g_VR.foregripActive = true
	if vrmod.logger then
		vrmod.logger.Debug("[stock-foregrip] start dist=%.1f class=%s", dist, state.class or "?")
	end
	return true
end

function vrmod.TryForegripGrab(pressed)
	if not g_VR or not g_VR.active then return false end
	if not pressed then
		if state.gripping then
			ClearGrip("input release")
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

hook.Add("VRMod_Input", "vrmod_foregrip", function(action, pressed)
	if not g_VR or not g_VR.active then return end
	if action ~= "boolean_left_pickup" then return end
	vrmod.TryForegripGrab(pressed)
end)

hook.Add("VRMod_PreStereo", "vrmod_foregrip", function()
	if not g_VR or not g_VR.active then return end
	if state.gripping then SolveForegripFrame() end
end)

hook.Add("VRMod_PreRender", "vrmod_foregrip", function()
	if state.gripping then ApplyFrozenGunDraw() end
end)

-- Freeze gun matrix both eyes when NOT stock-foregripping.
-- ArcVR sets suppressViewModelUpdates — only publish existing pose (do not re-solve from RH).
hook.Add("VRMod_PreStereo", "vrmod_weapon_pose_freeze", function()
	if not g_VR or not g_VR.active then return end
	if state.gripping then return end

	if vrmod.suppressViewModelUpdates then
		if g_VR.viewModelPos and g_VR.viewModelAng then
			PublishWeaponSnap(g_VR.stereoFrame or 0, g_VR.viewModelPos, g_VR.viewModelAng)
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
		PublishWeaponSnap(g_VR.stereoFrame or 0, g_VR.viewModelPos, g_VR.viewModelAng)
	end
end)

hook.Add("VRMod_Exit", "vrmod_foregrip", function() ClearGrip("vr exit") end)
hook.Add("PlayerSwitchWeapon", "vrmod_foregrip", function(ply)
	if ply == LocalPlayer() and state.gripping then ClearGrip("switch weapon") end
end)
hook.Add("PlayerDeath", "vrmod_foregrip", function(ply)
	if ply == LocalPlayer() then ClearGrip("death") end
end)
