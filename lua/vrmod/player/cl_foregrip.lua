if SERVER then return end
-- =============================================================================
-- Stock / non-VR two-hand foregrip — stereo-stable
--
-- ArcVR weapons are handled by arcticvr_base (skip here).
--
-- Start: left grip + hands within distance (no currentvmi hard-gate).
-- Solve once on VRMod_PreStereo from stereoPose hands; eyes only stamp.
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
timer.Simple(0.5, BlockOldForegripAddon)
timer.Simple(2, BlockOldForegripAddon)

-- Hardcoded start range (not archived cvar — old client.vdf "12" killed long grips)
local GRIP_DISTANCE = 20
local GUIDE_BLEND = 0.45
local RELEASE_MULT = 1.5

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
	startDist = 12,
}

local function ClearGrip()
	state.gripping = false
	state.frame = -1
	state.bonesFrame = -1
	state.wep = NULL
	state.class = nil
	state.weaponBox = nil
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
		if vrmod.SetLeftHandPose then
			vrmod.SetLeftHandPose(state.leftPos, state.leftAng, 0)
		end
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

	local guidedPos, guidedAng = GetGuidedWeaponPose(rpos, rang, lpos, lang, state.weaponBox)

	-- Write guided hands into tracking for any reader, then restore (stereo-safe)
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
		gunPos, gunAng = LocalToWorld(vmi.offsetPos or Vector(), vmi.offsetAng or Angle(), guidedPos, guidedAng)
	end

	local attachPos, attachAng = LocalToWorld(state.offsetPos, state.offsetAng, gunPos, gunAng)
	state.gunPos:Set(gunPos)
	state.gunAng:Set(gunAng)
	state.leftPos:Set(attachPos)
	state.leftAng:Set(attachAng)
	state.frame = sf
	state.bonesFrame = -1

	PublishSnap(sf, state.gunPos, state.gunAng)
	g_VR.foregripActive = true

	if vrmod.SetLeftHandPose then
		vrmod.SetLeftHandPose(state.leftPos, state.leftAng, 0)
	end
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
	if vrmod.SetLeftHandPose then
		vrmod.SetLeftHandPose(state.leftPos, state.leftAng, 0)
	end
end

local function TryStartGrip()
	if not g_VR or not g_VR.active then return false end
	if state.gripping then return true end
	if g_VR.menuGrabActive or g_VR.menuResizeActive then return false end

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
	if g_VR.menuGrabActive or g_VR.menuResizeActive then
		if not pressed and state.gripping then ClearGrip() end
		return
	end
	vrmod.TryForegripGrab(pressed)
end)

hook.Add("VRMod_PreStereo", "vrmod_foregrip", function()
	if not g_VR or not g_VR.active then return end
	if state.gripping then SolveForegripFrame() end
end)

hook.Add("VRMod_PreRender", "vrmod_foregrip", function()
	if state.gripping then ApplyFrozenGunDraw() end
end)

-- Non-grip stock freeze (both eyes same matrix). Never re-solve ArcVR.
hook.Add("VRMod_PreStereo", "vrmod_weapon_pose_freeze", function()
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
