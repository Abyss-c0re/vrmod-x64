if SERVER then return end
-- =============================================================================
-- Foregrip (two-hand weapon aim) — stereo-stable, logic-complete
--
-- Frame order (cl_vrmod PerformRenderViews):
--   stereoFrame++ → stereoPose freeze (raw hands) → VRMod_PreStereo
--     → foregrip Solve once → write gun snap
--   left eye / right eye: only stamp frozen gun + left-hand attach
--
-- Gaps fixed:
--   • Don't guide twice per eye / don't leave guided RH in tracking
--   • Require grip held every frame (missed release = stuck grip)
--   • Weapon death / switch / empty hands ends grip
--   • currentvmi optional (stock weapons get ephemeral VMI)
--   • Weapon box computed immediately + retry (not broken double-timer)
--   • Block world prop pickup while foregripping
--   • Publish g_VR._weaponSnap* so draw path matches both eyes
--   • Menu / panel grab wins over foregrip
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

local cv_dist = CreateClientConVar("vrmod_foregrip_distance", "12", true, FCVAR_ARCHIVE,
	"Max hand distance to start two-hand grip", 4, 40)
local cv_blend = CreateClientConVar("vrmod_foregrip_blend", "0.45", true, FCVAR_ARCHIVE,
	"Aim blend toward support hand (0–1)", 0, 1)
local cv_release = CreateClientConVar("vrmod_foregrip_release", "1.35", true, FCVAR_ARCHIVE,
	"Release multiplier × weapon reach", 1.05, 3)

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
	local class = string.lower(wep:GetClass() or "")
	if class == "" or class == "weapon_vrmod_empty" then return false end
	if class:find("weapon_fists", 1, true) then return false end
	if class:StartWith("arcticvr") or class:StartWith("avrmag_") then return false end
	-- Must be able to pose a viewmodel
	if vrmod.utils and vrmod.utils.IsValidWep and not vrmod.utils.IsValidWep(wep) then
		return false
	end
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
	g_VR.currentvmi = { offsetPos = Vector(0, 0, 0), offsetAng = Angle(0, 0, 0) }
	return g_VR.currentvmi
end

local function RefreshWeaponBox(ply, wep)
	if not (vrmod.utils and vrmod.utils.GetWeaponMeleeParams) then return end
	local radius, reach, mins, maxs = vrmod.utils.GetWeaponMeleeParams(wep, ply, "right")
	if not radius then return end
	-- Accept defaults as a soft box so release distance still works
	state.weaponBox = {
		mins = mins or Vector(-8, -8, -8),
		maxs = maxs or Vector(8, 8, 8),
		reach = reach or 20,
		radius = radius,
	}
end

local function GetGuidedWeaponPose(rightPos, rightAng, leftPos, leftAng, box)
	local blend = math.Clamp(cv_blend:GetFloat(), 0, 1)
	if blend <= 0 then return rightPos, rightAng end
	local toLeft = leftPos - rightPos
	local dist = toLeft:Length()
	local reach = (box and box.reach) or 20
	local maxDist = reach * 1.55
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
	-- Edge-detect can miss release; require continuous left grip
	if g_VR.input and g_VR.input.boolean_left_pickup == false then
		return false
	end
	-- If input table missing this frame, keep previous grip state
	if g_VR.input and g_VR.input.boolean_left_pickup == nil then
		return state.gripping
	end
	return g_VR.input.boolean_left_pickup and true or false
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

--- Solve two-hand pose ONCE per stereo frame.
local function SolveForegripFrame()
	if not state.gripping then return false end

	if not GripStillHeld() then
		ClearGrip("grip released")
		return false
	end

	local ply = LocalPlayer()
	local wep = IsValid(state.wep) and state.wep or (IsValid(ply) and ply:GetActiveWeapon()) or NULL
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
	if state.frame == sf and state.gunPos then
		-- Already solved this frame — re-publish snaps
		PublishWeaponSnap(sf, state.gunPos, state.gunAng)
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

	local reach = (state.weaponBox and state.weaponBox.reach) or 20
	local maxDist = reach * math.Clamp(cv_release:GetFloat(), 1.05, 3)
	if lpos:Distance(rpos) > maxDist then
		ClearGrip("hands too far")
		return false
	end

	local guidedPos, guidedAng = GetGuidedWeaponPose(rpos, rang, lpos, lang, state.weaponBox)

	-- Pose gun from guided RH without permanently corrupting tracking SoT
	local R = g_VR.tracking and g_VR.tracking.pose_righthand
	local savedPos, savedAng
	if R and R.pos and R.ang then
		savedPos = Vector(R.pos)
		savedAng = Angle(R.ang.p, R.ang.y, R.ang.r)
		if R.pos.Set then R.pos:Set(guidedPos) else R.pos = guidedPos end
		if R.ang.Set then R.ang:Set(guidedAng) else R.ang = guidedAng end
	end
	if vrmod.utils and vrmod.utils.UpdateViewModelPos then
		pcall(vrmod.utils.UpdateViewModelPos, guidedPos, guidedAng, true)
	end
	if R and savedPos and savedAng then
		if R.pos.Set then R.pos:Set(savedPos) else R.pos = savedPos end
		if R.ang.Set then R.ang:Set(savedAng) else R.ang = savedAng end
	end

	local gunPos = g_VR.viewModelPos
	local gunAng = g_VR.viewModelAng
	if not gunPos or not gunAng then
		-- Fallback: hand + VMI offset
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
	if g_VR.menuFocus or g_VR.menuGrabActive or g_VR.menuResizeActive then return false end
	if g_VR.avatarSteerTwin then return false end
	local lpos, lang, rpos, rang = StereoHands()
	if not lpos then
		local L = g_VR.tracking and g_VR.tracking.pose_lefthand
		local R = g_VR.tracking and g_VR.tracking.pose_righthand
		if not (L and R and L.pos and R.pos) then return false end
		lpos, lang, rpos, rang = L.pos, L.ang, R.pos, R.ang
	end
	local wep = LocalPlayer():GetActiveWeapon()
	if not IsValidForegripWeapon(wep) then return false end
	local dist = lpos:Distance(rpos)
	if dist > cv_dist:GetFloat() then return false end

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
	RefreshWeaponBox(LocalPlayer(), wep)
	g_VR.foregripActive = true
	return true
end

hook.Add("VRMod_Input", "vrmod_foregrip", function(action, pressed)
	if not g_VR or not g_VR.active then return end
	if action ~= "boolean_left_pickup" then return end

	if not pressed then
		if state.gripping then ClearGrip("input release") end
		return
	end

	-- Pressed: try start (menu grab may already have consumed — TryMenuGrab runs in other hooks)
	if g_VR.menuFocus or g_VR.menuGrabActive then return end
	TryStartGrip()
end)

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

-- Public query for input/pickup
function vrmod.IsForegripActive()
	return state.gripping and true or false
end
