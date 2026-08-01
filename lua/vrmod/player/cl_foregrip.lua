if SERVER then return end
-- =============================================================================
-- Stock / non-VR two-hand foregrip — stereo-stable
--
-- ArcVR weapons are handled by arcticvr_base (skip here).
--
-- Start: left grip + hands within distance (no currentvmi hard-gate).
-- Solve once on VRMod_PreStereo from stereoPose hands; eyes only stamp.
--
-- SoT while gripping:
--   smooth RH → mild guide (device LH aim only) → gun = RH+VMI → LH = grip offset on gun
-- Gun mesh and left hand ALWAYS share that gun matrix (no unguided attach / guided mesh split).
-- =============================================================================

local function BlockOldForegripAddon()
	for _, pair in ipairs({
		{ "VRMod_Input", "Foregrip" },
		{ "VRMod_PreRender", "ForegripTransform" },
		{ "VRMod_Exit", "ForegripExit" },
		-- Prior hook names (lua_refresh would double-register otherwise)
		{ "VRMod_PreStereo", "vrmod_foregrip" },
		{ "VRMod_PreRender", "vrmod_foregrip" },
		{ "VRMod_PreStereo", "vrmod_weapon_pose_freeze" },
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

-- Hardcoded start range (not archived cvar — old client.vdf "12" killed long grips)
local GRIP_DISTANCE = 20
-- Mild two-hand aim. Must share the SAME gun matrix as LH attach (never unguided-vs-guided split).
local GUIDE_BLEND = 0.12
local RELEASE_MULT = 1.5
-- RH low-pass (parent of gun+attach) kills controller micro-noise on FBT arm
local RH_SMOOTH = 0.16
-- Deadzone on final gun matrix (hand is derived from gun — one SoT)
local GUN_POS_EPS_SQR = 0.04 -- 0.2u
local GUN_ANG_EPS = 0.35

local state = {
	gripping = false,
	offsetPos = Vector(0, 0, 0),
	offsetAng = Angle(0, 0, 0),
	wep = NULL,
	class = nil,
	weaponBox = nil,
	frame = -1,
	bonesFrame = -1,
	gunPos = Vector(0, 0, 0),
	gunAng = Angle(0, 0, 0),
	leftPos = Vector(0, 0, 0),
	leftAng = Angle(0, 0, 0),
	smoothRPos = Vector(0, 0, 0),
	smoothRAng = Angle(0, 0, 0),
	hasSmoothR = false,
	startDist = 12,
}

local function ClearGrip()
	state.gripping = false
	state.frame = -1
	state.bonesFrame = -1
	state.wep = NULL
	state.class = nil
	state.weaponBox = nil
	state.hasSmoothR = false
	g_VR._leftHandSnapFrame = -1
	local aw = IsValid(LocalPlayer()) and LocalPlayer():GetActiveWeapon() or NULL
	if not (IsValid(aw) and aw.ArcticVR and aw.ForegripGrabbed) then
		g_VR.foregripActive = false
	end
end

local function IsStockForegripWeapon(wep)
	if not IsValid(wep) then return false end
	if wep.ArcticVR or wep.ArcticVRNade then return false end
	local class = string.lower(wep:GetClass() or "")
	if class == "" or class == "weapon_vrmod_empty" then return false end
	if class:find("weapon_fists", 1, true) then return false end
	if class:find("arcticvr", 1, true) or class:StartWith("avrmag_") then return false end
	return true
end

--- Always return a usable VMI (ephemeral zero-offset for unconfigured stock guns).
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

local function RefreshWeaponBox(wep)
	state.weaponBox = nil
	if not (vrmod.utils and vrmod.utils.GetWeaponMeleeParams) then return end
	local ply = LocalPlayer()
	local radius, reach, mins, maxs = vrmod.utils.GetWeaponMeleeParams(wep, ply, "right")
	if not radius then return end
	local def = vrmod.DEFAULT_REACH or 5
	if not reach or reach <= def + 0.01 then reach = 22 end
	state.weaponBox = {
		mins = mins or Vector(-8, -8, -8),
		maxs = maxs or Vector(8, 8, 8),
		reach = reach,
	}
end

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

local function GetGuidedWeaponPose(rightPos, rightAng, leftPos, leftAng, box)
	if GUIDE_BLEND <= 0 then return rightPos, rightAng end
	local toLeft = leftPos - rightPos
	local dist = toLeft:Length()
	local maxDist = (box and box.reach and box.reach * 1.55) or 32
	maxDist = math.max(maxDist, state.startDist * RELEASE_MULT, 28)
	if dist > maxDist or dist < 0.05 then return rightPos, rightAng end
	local minDist = 4.5
	if box and box.mins then
		minDist = math.max(math.abs(box.mins.y or 0), 4.5)
	end
	if dist < minDist then return rightPos, rightAng end
	local targetAng = toLeft:GetNormalized():Angle()
	local newAng = LerpAngle(GUIDE_BLEND, rightAng, targetAng)
	newAng.r = rightAng.r
	return rightPos, newAng
end

local function PublishSnap(sf, gunPos, gunAng)
	g_VR._weaponSnapFrame = sf
	if not g_VR._weaponSnapPos then g_VR._weaponSnapPos = Vector() end
	if not g_VR._weaponSnapAng then g_VR._weaponSnapAng = Angle() end
	g_VR._weaponSnapPos:Set(gunPos)
	g_VR._weaponSnapAng:Set(gunAng)
	-- Assign copies into draw SoT (do not alias same userdata for later overwrites)
	g_VR.viewModelPos = Vector(gunPos)
	g_VR.viewModelAng = Angle(gunAng.p, gunAng.y, gunAng.r)
end

--- Stereo-stable left hand for FBT / avatar IK / body draw.
--- Writes COPIES into tracking + lerpedFrame (never alias state vectors into them).
--- Forces FBT bone solve to re-run if it already used device hands this FrameNumber.
local function StampLeftStable(sf)
	local p = state.leftPos
	local a = state.leftAng
	if not p or not a then return end

	g_VR._leftHandSnapFrame = sf
	if not g_VR._leftHandSnapPos then g_VR._leftHandSnapPos = Vector() end
	if not g_VR._leftHandSnapAng then g_VR._leftHandSnapAng = Angle() end
	g_VR._leftHandSnapPos:Set(p)
	g_VR._leftHandSnapAng:Set(a)

	local L = g_VR.tracking and g_VR.tracking.pose_lefthand
	if L and L.pos and L.ang then
		if L.pos.Set then L.pos:Set(p) else L.pos = Vector(p) end
		if L.ang.Set then L.ang:Set(a) else L.ang = Angle(a.p, a.y, a.r) end
	end

	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local tab = g_VR.net and g_VR.net[ply:SteamID()]
	local nf = tab and tab.lerpedFrame
	if nf then
		-- Fresh vectors — SetLeftHandPose used to alias state.leftPos into net frame
		nf.lefthandPos = Vector(p.x, p.y, p.z)
		nf.lefthandAng = Angle(a.p, a.y, a.r)
	end

	-- FBT freezes once per FrameNumber; if it already ran with device LH, re-solve
	if vrmod_fbt and vrmod_fbt.characterInfo then
		local info = vrmod_fbt.characterInfo[ply:SteamID()]
		if info then info.frameNumber = -1 end
	end

	-- Non-FBT character IK: allow one more UpdateIK this frame with attach hands
	if g_VR._charIkUpdated then
		g_VR._charIkUpdated = nil
	end
end

--- Per-eye: only re-assert frozen LH (same matrix both eyes; no recompute).
local function ReassertLeftSnap(sf)
	if g_VR._leftHandSnapFrame ~= sf or not g_VR._leftHandSnapPos then return end
	local p, a = g_VR._leftHandSnapPos, g_VR._leftHandSnapAng
	local L = g_VR.tracking and g_VR.tracking.pose_lefthand
	if L and L.pos and L.ang then
		if L.pos.Set then L.pos:Set(p) else L.pos = Vector(p) end
		if L.ang.Set then L.ang:Set(a) else L.ang = Angle(a.p, a.y, a.r) end
	end
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local nf = g_VR.net and g_VR.net[ply:SteamID()] and g_VR.net[ply:SteamID()].lerpedFrame
	if nf and nf.lefthandPos and nf.lefthandPos.Set then
		nf.lefthandPos:Set(p)
		if nf.lefthandAng and nf.lefthandAng.Set then nf.lefthandAng:Set(a) end
	elseif nf then
		nf.lefthandPos = Vector(p.x, p.y, p.z)
		nf.lefthandAng = Angle(a.p, a.y, a.r)
	end
end

local function SolveForegripFrame()
	if not state.gripping then return false end

	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:Alive() then
		ClearGrip()
		return false
	end

	local wep = IsValid(state.wep) and state.wep or ply:GetActiveWeapon()
	if not IsStockForegripWeapon(wep) then
		ClearGrip()
		return false
	end
	if state.class and wep:GetClass() ~= state.class then
		ClearGrip()
		return false
	end

	local vmi = EnsureVMI(wep)
	local sf = g_VR.stereoFrame or 0
	if state.frame == sf then
		PublishSnap(sf, state.gunPos, state.gunAng)
		ReassertLeftSnap(sf)
		return true
	end

	local lpos, lang, rpos, rang = StereoHands()
	if not lpos or not rpos then
		return false -- keep grip one frame if tracking glitch
	end

	local maxDist = state.startDist * RELEASE_MULT
	if state.weaponBox and state.weaponBox.reach then
		maxDist = math.max(maxDist, state.weaponBox.reach * RELEASE_MULT)
	end
	maxDist = math.max(maxDist, 28)
	if lpos:Distance(rpos) > maxDist then
		ClearGrip()
		return false
	end

	-- One SoT: smoothed RH → (optional mild guide) → gun = RH+VMI → LH = offset on gun.
	-- Prior split (attach on unguided, mesh on guided) left the hand floating while the gun moved.
	if not state.hasSmoothR then
		state.smoothRPos:Set(rpos)
		state.smoothRAng:Set(rang)
		state.hasSmoothR = true
	else
		state.smoothRPos = LerpVector(RH_SMOOTH, state.smoothRPos, rpos)
		state.smoothRAng = LerpAngle(RH_SMOOTH, state.smoothRAng, rang)
	end

	-- Guide uses device LH direction only (from frozen stereoPose — not tracking attach).
	-- Same parent for mesh and hand; no unguided/guided fork.
	local handPos, handAng = GetGuidedWeaponPose(
		state.smoothRPos, state.smoothRAng, lpos, lang, state.weaponBox
	)
	local gunPos, gunAng = LocalToWorld(
		vmi.offsetPos or Vector(),
		vmi.offsetAng or Angle(),
		handPos, handAng
	)

	-- Deadzone the GUN (hand is re-derived from it — keeps glue + kills micro-shake)
	if state.frame >= 0 then
		local dpos = gunPos:DistToSqr(state.gunPos)
		local dang = (
			math.abs(math.AngleDifference(gunAng.p, state.gunAng.p))
			+ math.abs(math.AngleDifference(gunAng.y, state.gunAng.y))
			+ math.abs(math.AngleDifference(gunAng.r, state.gunAng.r))
		)
		if dpos < GUN_POS_EPS_SQR and dang < GUN_ANG_EPS then
			gunPos = Vector(state.gunPos.x, state.gunPos.y, state.gunPos.z)
			gunAng = Angle(state.gunAng.p, state.gunAng.y, state.gunAng.r)
		end
	end

	-- LH glued to the matrix we actually draw
	local attachPos, attachAng = LocalToWorld(state.offsetPos, state.offsetAng, gunPos, gunAng)

	state.gunPos:Set(gunPos)
	state.gunAng:Set(gunAng)
	state.leftPos:Set(attachPos)
	state.leftAng:Set(attachAng)
	state.frame = sf
	state.bonesFrame = -1

	-- Write gun SoT without mutating tracking RH (body RH stays device/smooth)
	g_VR.viewModelPos = Vector(gunPos.x, gunPos.y, gunPos.z)
	g_VR.viewModelAng = Angle(gunAng.p, gunAng.y, gunAng.r)
	local vm = g_VR.viewModel
	if not IsValid(vm) then
		local lp = LocalPlayer()
		if IsValid(lp) then vm = lp:GetViewModel() end
		if IsValid(vm) then g_VR.viewModel = vm end
	end
	if IsValid(vm) then
		vm:SetPos(state.gunPos)
		vm:SetAngles(state.gunAng)
	end

	PublishSnap(sf, state.gunPos, state.gunAng)
	g_VR.foregripActive = true
	StampLeftStable(sf)
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
		if IsValid(vm) then g_VR.viewModel = vm end
	end
	if not IsValid(vm) then return end

	PublishSnap(sf, state.gunPos, state.gunAng)
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
	-- Same frozen LH both eyes (FBT/avatar read tracking + lerpedFrame)
	ReassertLeftSnap(sf)
end

local function TryStartGrip()
	if not g_VR or not g_VR.active then return false end
	if state.gripping then return true end
	-- Only block while UI is actually holding a focused panel (stuck menuGrabActive must not kill FG)
	if g_VR.menuResizeActive then return false end
	if g_VR.menuGrabActive and g_VR.menuFocus then return false end

	local L = g_VR.tracking and g_VR.tracking.pose_lefthand
	local R = g_VR.tracking and g_VR.tracking.pose_righthand
	if not (L and R and L.pos and R.pos and L.ang and R.ang) then return false end

	local wep = LocalPlayer():GetActiveWeapon()
	if not IsStockForegripWeapon(wep) then return false end

	local dist = L.pos:Distance(R.pos)
	if dist > GRIP_DISTANCE then return false end

	-- Always ensure VMI — stock guns often have no preconfigured entry
	local vmi = EnsureVMI(wep)
	local wepWorldPos, wepWorldAng = LocalToWorld(
		vmi.offsetPos or Vector(),
		vmi.offsetAng or Angle(),
		R.pos, R.ang
	)
	state.offsetPos, state.offsetAng = WorldToLocal(L.pos, L.ang, wepWorldPos, wepWorldAng)
	state.gripping = true
	state.wep = wep
	state.class = wep:GetClass()
	state.frame = -1
	state.bonesFrame = -1
	state.startDist = math.max(dist, 6)
	state.weaponBox = nil
	state.smoothRPos:Set(R.pos)
	state.smoothRAng:Set(R.ang)
	state.hasSmoothR = true
	RefreshWeaponBox(wep)
	g_VR.foregripActive = true
	return true
end

--- cl_input calls this before prop pickup.
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

-- Direct input path (works even if cl_input order changes)
hook.Add("VRMod_Input", "vrmod_foregrip", function(action, pressed)
	if not g_VR or not g_VR.active then return end
	if action ~= "boolean_left_pickup" then return end
	if g_VR.menuResizeActive or (g_VR.menuGrabActive and g_VR.menuFocus) then
		if not pressed and state.gripping then ClearGrip() end
		return
	end
	vrmod.TryForegripGrab(pressed)
end)

-- Name sorts before twin_force_ik / avatar pose so LH snap is ready for FBT body
hook.Add("VRMod_PreStereo", "0_vrmod_foregrip", function()
	if not g_VR or not g_VR.active then return end
	if state.gripping then SolveForegripFrame() end
end)

hook.Add("VRMod_PreRender", "0_vrmod_foregrip", function()
	if state.gripping then ApplyFrozenGunDraw() end
end)

-- Non-grip stock freeze (both eyes same matrix). Never re-solve ArcVR.
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
	if ply == LocalPlayer() and state.gripping then ClearGrip() end
end)
hook.Add("PlayerDeath", "vrmod_foregrip", function(ply)
	if ply == LocalPlayer() then ClearGrip() end
end)
