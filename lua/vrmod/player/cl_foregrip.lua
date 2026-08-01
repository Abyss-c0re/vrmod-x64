if SERVER then return end
-- =============================================================================
-- Foregrip (two-hand weapon aim) — stereo-stable, logic-complete
--
-- Frame order (cl_vrmod PerformRenderViews):
--   stereoFrame++ → stereoPose freeze (raw hands) → VRMod_PreStereo
--     → foregrip Solve once → write gun snap
--   left eye / right eye: only stamp frozen gun + left-hand attach
--
-- Ownership:
--   cl_input calls vrmod.TryForegripGrab before world prop pickup (like menu grab).
--   VRMod_Input hook remains as a fallback if default input is reordered.
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

local cv_dist = CreateClientConVar("vrmod_foregrip_distance", "24", true, FCVAR_ARCHIVE,
	"Max hand distance to start two-hand grip (stock/non-VR)", 4, 48)
local cv_blend = CreateClientConVar("vrmod_foregrip_blend", "0.45", true, FCVAR_ARCHIVE,
	"Aim blend toward support hand (0–1)", 0, 1)
local cv_release = CreateClientConVar("vrmod_foregrip_release", "1.5", true, FCVAR_ARCHIVE,
	"Release multiplier × max(weapon reach, start distance)", 1.05, 3)

--- Archived client.vdf may still hold old "12" — never start tighter than this floor.
local function StartMaxDist()
	return math.max(cv_dist:GetFloat(), 20)
end

local state = {
	gripping = false,
	offsetPos = Vector(0, 0, 0),
	offsetAng = Angle(0, 0, 0),
	wep = NULL,
	class = nil,
	weaponBox = nil,
	boxTries = 0,
	frame = -1,
	bonesFrame = -1,
	gunPos = Vector(0, 0, 0),
	gunAng = Angle(0, 0, 0),
	leftPos = Vector(0, 0, 0),
	leftAng = Angle(0, 0, 0),
	startDist = 12,
}

local function ClearGrip(reason)
	state.gripping = false
	state.frame = -1
	state.bonesFrame = -1
	state.wep = NULL
	state.class = nil
	state.weaponBox = nil
	state.boxTries = 0
	g_VR.foregripActive = false
	if reason and vrmod.logger then
		vrmod.logger.Debug("[foregrip] clear: %s", tostring(reason))
	end
end

local function IsValidForegripWeapon(wep)
	if not IsValid(wep) then return false end
	-- ArcVR has its own foregrip (AVR_GunTracking + GripForegrip)
	if wep.ArcticVR or wep.ArcticVRNade then return false end
	local class = string.lower(wep:GetClass() or "")
	if class == "" or class == "weapon_vrmod_empty" then return false end
	if class:find("weapon_fists", 1, true) then return false end
	if class:StartWith("arcticvr") or class:StartWith("avrmag_") then return false end
	-- Prefer IsValidWep but allow stock guns with a real ViewModel path
	if vrmod.utils and vrmod.utils.IsValidWep and vrmod.utils.IsValidWep(wep) then
		return true
	end
	local vm = wep.ViewModel or ""
	if vm == "" and wep.GetWeaponViewModel then
		local ok, v = pcall(wep.GetWeaponViewModel, wep)
		if ok then vm = v or "" end
	end
	if vm ~= "" and vm ~= "models/weapons/c_arms.mdl" then return true end
	return false
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
	-- Ephemeral only if nothing else owns currentvmi
	if not g_VR.currentvmi then
		g_VR.currentvmi = { offsetPos = Vector(0, 0, 0), offsetAng = Angle(0, 0, 0) }
	else
		if not g_VR.currentvmi.offsetPos then g_VR.currentvmi.offsetPos = Vector(0, 0, 0) end
		if not g_VR.currentvmi.offsetAng then g_VR.currentvmi.offsetAng = Angle(0, 0, 0) end
	end
	return g_VR.currentvmi
end

local function SoftReach(reach)
	-- DEFAULT_REACH is ~5 (melee hand proxy). Too small for two-hand release vs start=12.
	local def = (vrmod and vrmod.DEFAULT_REACH) or 5
	if not reach or reach <= def + 0.01 then
		return math.max(20, cv_dist:GetFloat())
	end
	return reach
end

local function RefreshWeaponBox(ply, wep)
	if not (vrmod.utils and vrmod.utils.GetWeaponMeleeParams) then return end
	local radius, reach, mins, maxs = vrmod.utils.GetWeaponMeleeParams(wep, ply, "right")
	if not radius then return end
	state.weaponBox = {
		mins = mins or Vector(-8, -8, -8),
		maxs = maxs or Vector(8, 8, 8),
		reach = SoftReach(reach),
		radius = radius,
	}
end

--- Release distance must never be tighter than the distance that allowed start.
local function ReleaseMaxDist()
	local reach = (state.weaponBox and state.weaponBox.reach) or SoftReach(nil)
	local mult = math.Clamp(cv_release:GetFloat(), 1.05, 3)
	local fromReach = reach * mult
	local fromStart = (state.startDist or cv_dist:GetFloat()) * mult
	return math.max(fromReach, fromStart, cv_dist:GetFloat() * mult)
end

local function GetGuidedWeaponPose(rightPos, rightAng, leftPos, leftAng, box)
	local blend = math.Clamp(cv_blend:GetFloat(), 0, 1)
	if blend <= 0 then return rightPos, rightAng end
	local toLeft = leftPos - rightPos
	local dist = toLeft:Length()
	local reach = SoftReach(box and box.reach)
	local maxDist = math.max(reach * 1.55, ReleaseMaxDist())
	if dist > maxDist or dist < 0.05 then return rightPos, rightAng end
	local minDist = 4.5
	if box and box.mins then
		minDist = math.max(math.abs(box.mins.y or 0), math.abs(box.mins.x or 0) * 0.5, 4.5)
	end
	if dist < minDist then return rightPos, rightAng end
	local targetAng = toLeft:GetNormalized():Angle()
	local newAng = LerpAngle(blend, rightAng, targetAng)
	newAng.r = rightAng.r -- keep roll from RH for stability
	return rightPos, newAng
end

--- Raw hands for this stereo frame (never guided).
local function StereoHands()
	local sp = g_VR.stereoPose
	local sf = g_VR.stereoFrame or 0
	if sp and sp.frame == sf and sp.hasLeft and sp.hasRight then
		return sp.leftPos, sp.leftAng, sp.rightPos, sp.rightAng
	end
	local L = g_VR.tracking and g_VR.tracking.pose_lefthand
	local R = g_VR.tracking and g_VR.tracking.pose_righthand
	if not (L and R and L.pos and R.pos and L.ang and R.ang) then return nil end
	return L.pos, L.ang, R.pos, R.ang
end

local function GripStillHeld()
	-- Edge-detect can miss release; require continuous left grip when input is known.
	local inp = g_VR and g_VR.input
	if not inp then return state.gripping end
	local v = inp.boolean_left_pickup
	if v == false then return false end
	if v == nil then return state.gripping end
	return v and true or false
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

local function CanStartGripContext()
	if not g_VR or not g_VR.active then return false end
	-- Only block while actively grabbing/resizing a panel — laser hover (menuFocus) must not kill grip
	if g_VR.menuGrabActive or g_VR.menuResizeActive then return false end
	if g_VR.avatarSteerTwin then return false end
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:Alive() then return false end
	return true
end

--- Solve two-hand pose ONCE per stereo frame.
local function SolveForegripFrame()
	if not state.gripping then return false end

	if not GripStillHeld() then
		ClearGrip("grip released")
		return false
	end

	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:Alive() then
		ClearGrip("dead")
		return false
	end

	local wep = IsValid(state.wep) and state.wep or ply:GetActiveWeapon() or NULL
	if not IsValidForegripWeapon(wep) then
		ClearGrip("invalid weapon")
		return false
	end
	if state.class and wep:GetClass() ~= state.class then
		ClearGrip("weapon switched")
		return false
	end

	-- Menu / panel grab wins
	if g_VR.menuGrabActive or g_VR.menuResizeActive then
		ClearGrip("menu grab")
		return false
	end

	local vmi = EnsureVMI(wep)
	local sf = g_VR.stereoFrame or 0
	if state.frame == sf then
		-- Already solved this frame — re-publish snaps + re-stamp LH
		PublishWeaponSnap(sf, state.gunPos, state.gunAng)
		if vrmod.SetLeftHandPose then
			vrmod.SetLeftHandPose(state.leftPos, state.leftAng, 0)
		end
		return true
	end

	local lpos, lang, rpos, rang = StereoHands()
	if not lpos or not rpos then
		ClearGrip("no hands")
		return false
	end

	-- Lazy weapon box
	if not state.weaponBox and state.boxTries < 8 then
		state.boxTries = state.boxTries + 1
		RefreshWeaponBox(ply, wep)
	end

	local maxDist = ReleaseMaxDist()
	if lpos:Distance(rpos) > maxDist then
		ClearGrip("hands too far")
		return false
	end

	local guidedPos, guidedAng = GetGuidedWeaponPose(rpos, rang, lpos, lang, state.weaponBox)

	-- Pose gun from guided RH without mutating tracking SoT
	-- (UpdateViewModelPos override=true uses these hands and does not stomp)
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

	-- Left hand on foregrip (mutates tracking LH for this frame's draw)
	if vrmod.SetLeftHandPose then
		vrmod.SetLeftHandPose(state.leftPos, state.leftAng, 0)
	elseif g_VR.tracking and g_VR.tracking.pose_lefthand then
		local L = g_VR.tracking.pose_lefthand
		if L.pos.Set then L.pos:Set(state.leftPos) else L.pos = state.leftPos end
		if L.ang.Set then L.ang:Set(state.leftAng) else L.ang = state.leftAng end
	end
	-- Keep stereoPose left in sync for systems that read freeze after us
	local sp = g_VR.stereoPose
	if sp and sp.frame == sf then
		if not sp.leftPos then sp.leftPos = Vector() end
		if not sp.leftAng then sp.leftAng = Angle() end
		sp.leftPos:Set(state.leftPos)
		sp.leftAng:Set(state.leftAng)
		sp.hasLeft = true
	end

	return true
end

--- Per-eye: stamp frozen gun only.
local function ApplyFrozenGunDraw()
	if not state.gripping or not state.gunPos then return end
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
	-- Re-apply LH attach each eye so nothing overwrites between eyes
	if vrmod.SetLeftHandPose then
		vrmod.SetLeftHandPose(state.leftPos, state.leftAng, 0)
	end
end

local function TryStartGrip()
	if not CanStartGripContext() then return false end
	if state.gripping then return true end

	-- Live hands at input time (stereoPose is last eye pair)
	local L = g_VR.tracking and g_VR.tracking.pose_lefthand
	local R = g_VR.tracking and g_VR.tracking.pose_righthand
	local lpos, lang, rpos, rang
	if L and R and L.pos and R.pos and L.ang and R.ang then
		lpos, lang, rpos, rang = L.pos, L.ang, R.pos, R.ang
	else
		lpos, lang, rpos, rang = StereoHands()
	end
	if not lpos or not rpos then return false end

	local wep = LocalPlayer():GetActiveWeapon()
	if not IsValidForegripWeapon(wep) then return false end

	local dist = lpos:Distance(rpos)
	local maxStart = StartMaxDist()
	if dist > maxStart then
		-- Long guns: allow LH near gun body even if hands are farther apart
		local vmi = EnsureVMI(wep)
		local gunPos, gunAng = g_VR.viewModelPos, g_VR.viewModelAng
		if not gunPos or not gunAng then
			gunPos, gunAng = LocalToWorld(vmi.offsetPos or Vector(), vmi.offsetAng or Angle(), rpos, rang)
		end
		local fore = gunPos + gunAng:Forward() * 10
		if lpos:DistToSqr(fore) > (maxStart * maxStart) then
			return false
		end
	end

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
	state.boxTries = 0
	state.weaponBox = nil
	state.startDist = math.max(dist, 6)
	RefreshWeaponBox(LocalPlayer(), wep)
	g_VR.foregripActive = true
	return true
end

--- Called from default input before entity pickup. Returns true if grip was consumed.
function vrmod.TryForegripGrab(pressed)
	if not g_VR or not g_VR.active then return false end
	if not pressed then
		if state.gripping then
			ClearGrip("input release")
			return true -- consumed release (do not also drop a prop we never grabbed)
		end
		return false
	end
	if state.gripping then
		return true -- already owning left grip
	end
	return TryStartGrip()
end

function vrmod.IsForegripActive()
	return state.gripping and true or false
end

hook.Add("VRMod_Input", "vrmod_foregrip", function(action, pressed)
	if not g_VR or not g_VR.active then return end
	if action ~= "boolean_left_pickup" then return end
	-- Fallback if cl_input did not claim first (hook order / disabled default input)
	vrmod.TryForegripGrab(pressed)
end)

-- Public: ArcVR keeps its own foregrip; this module is stock/non-VR only.
function vrmod.HasUniversalForegrip()
	return false
end

-- Before either eye: solve grip + freeze gun
hook.Add("VRMod_PreStereo", "vrmod_foregrip", function()
	if not g_VR or not g_VR.active then return end
	if state.gripping then
		SolveForegripFrame()
	end
end)

-- Each eye: stamp same frozen gun
hook.Add("VRMod_PreRender", "vrmod_foregrip", function()
	if state.gripping then
		ApplyFrozenGunDraw()
	end
end)

-- Non-grip weapon freeze (stock stereo) when not two-handing
hook.Add("VRMod_PreStereo", "vrmod_weapon_pose_freeze", function()
	if not g_VR or not g_VR.active then return end
	if state.gripping then return end
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
