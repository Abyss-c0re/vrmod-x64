if SERVER then return end
-- =============================================================================
-- Stock / non-VR two-hand foregrip (vrmod-x64)
--
-- Behavior matches gVRMod / World-Line style:
--   start: left grip + hands within GRIP_DISTANCE + stock weapon
--   gun  = guided RH + VMI  (via UpdateViewModelPos — same path as draw)
--   LH   = fixed offset on g_VR.viewModelPos/Ang (must match mesh)
--
-- x64 additions (do not change the gun/hand matrix math):
--   solve once per stereo frame from stereoPose; both eyes only re-stamp
--   EnsureVMI so unconfigured stock SWEPs still grip
-- ArcVR weapons are handled by arcticvr_base (skip here).
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

-- gVRMod defaults (reliable stock start — do not gate on mid-gun radial)
local GRIP_DISTANCE = 20
local GUIDE_BLEND = 0.45
local RELEASE_MULT = 1.35

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

--- Same gun matrix math as vrmod.utils.UpdateViewModel (LocalToWorld vs useWorldModel).
local function GunWorldFromHand(handPos, handAng, vmi)
	vmi = vmi or g_VR.currentvmi
	if not handPos or not handAng or not vmi then return nil, nil end
	if vmi.useWorldModel then
		local off = vmi.offsetPos or Vector()
		local oang = vmi.offsetAng or Angle()
		local pos = handPos + handAng:Forward() * off.x + handAng:Right() * off.y + handAng:Up() * off.z
		local ang = Angle(handAng.p, handAng.y, handAng.r)
		ang:RotateAroundAxis(ang:Right(), oang.p or 0)
		ang:RotateAroundAxis(ang:Up(), oang.y or 0)
		ang:RotateAroundAxis(ang:Forward(), oang.r or 0)
		return pos, ang
	end
	return LocalToWorld(
		vmi.offsetPos or Vector(),
		vmi.offsetAng or Angle(),
		handPos, handAng
	)
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

-- gVRMod two-hand aim (same constants / structure)
local function GetGuidedWeaponPose(rightPos, rightAng, leftPos, leftAng, box)
	if GUIDE_BLEND <= 0 then return rightPos, rightAng end
	local toLeft = leftPos - rightPos
	local dist = toLeft:Length()
	local maxDist = (box and box.reach and box.reach * 1.55) or 26
	maxDist = math.max(maxDist, state.startDist * RELEASE_MULT, 26)
	if dist > maxDist or dist < 0.05 then return rightPos, rightAng end
	local minDist = 5.5
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
	g_VR.viewModelPos = Vector(gunPos)
	g_VR.viewModelAng = Angle(gunAng.p, gunAng.y, gunAng.r)
end

local function StampLeftStable(sf)
	local p = state.leftPos
	local a = state.leftAng
	if not p or not a then return end

	g_VR._leftHandSnapFrame = sf
	if not g_VR._leftHandSnapPos then g_VR._leftHandSnapPos = Vector() end
	if not g_VR._leftHandSnapAng then g_VR._leftHandSnapAng = Angle() end
	g_VR._leftHandSnapPos:Set(p)
	g_VR._leftHandSnapAng:Set(a)

	-- Official API when present (gVRMod path)
	if isfunction(vrmod.SetLeftHandPose) then
		pcall(vrmod.SetLeftHandPose, p, a)
	end

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
		nf.lefthandPos = Vector(p.x, p.y, p.z)
		nf.lefthandAng = Angle(a.p, a.y, a.r)
	end

	if vrmod_fbt and vrmod_fbt.characterInfo then
		local info = vrmod_fbt.characterInfo[ply:SteamID()]
		if info then info.frameNumber = -1 end
	end
	if g_VR._charIkUpdated then
		g_VR._charIkUpdated = nil
	end
end

local function ReassertLeftSnap(sf)
	if g_VR._leftHandSnapFrame ~= sf or not g_VR._leftHandSnapPos then return end
	local p, a = g_VR._leftHandSnapPos, g_VR._leftHandSnapAng
	if isfunction(vrmod.SetLeftHandPose) then
		pcall(vrmod.SetLeftHandPose, p, a)
	end
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

--- Core gVRMod solve: UpdateViewModelPos → LH offset on actual viewModelPos/Ang
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
		return false
	end

	-- gVRMod release: box reach or default 20
	local maxDist = 20
	if state.weaponBox and state.weaponBox.reach then
		maxDist = state.weaponBox.reach * RELEASE_MULT
	end
	maxDist = math.max(maxDist, state.startDist * RELEASE_MULT, 20)
	if lpos:Distance(rpos) > maxDist then
		ClearGrip()
		return false
	end

	local guidedPos, guidedAng = GetGuidedWeaponPose(rpos, rang, lpos, lang, state.weaponBox)

	-- Draw path = official viewmodel pipeline (collision / useWorldModel / SetupBones)
	if vrmod.utils and vrmod.utils.UpdateViewModelPos then
		pcall(vrmod.utils.UpdateViewModelPos, guidedPos, guidedAng, true)
	else
		local gp, ga = GunWorldFromHand(guidedPos, guidedAng, vmi)
		if gp then
			g_VR.viewModelPos = gp
			g_VR.viewModelAng = ga
		end
	end

	-- Mesh SoT after UpdateViewModel — never a parallel LocalToWorld that can diverge
	local gunPos = g_VR.viewModelPos
	local gunAng = g_VR.viewModelAng
	if not gunPos or not gunAng then
		gunPos, gunAng = GunWorldFromHand(guidedPos, guidedAng, vmi)
	end
	if not gunPos or not gunAng then return false end

	-- LH glued to the matrix we actually draw (gVRMod: LocalToWorld offset on viewModel*)
	local attachPos, attachAng = LocalToWorld(state.offsetPos, state.offsetAng, gunPos, gunAng)

	state.gunPos:Set(gunPos)
	state.gunAng:Set(gunAng)
	state.leftPos:Set(attachPos)
	state.leftAng:Set(attachAng)
	state.frame = sf
	state.bonesFrame = -1

	PublishSnap(sf, state.gunPos, state.gunAng)
	g_VR.foregripActive = true
	StampLeftStable(sf)
	return true
end

local function ApplyFrozenGunDraw()
	if not state.gripping then return end
	local sf = g_VR.stereoFrame or 0
	if state.frame ~= sf then return end

	PublishSnap(sf, state.gunPos, state.gunAng)

	local vm = g_VR.viewModel
	if not IsValid(vm) then
		local ply = LocalPlayer()
		if IsValid(ply) then vm = ply:GetViewModel() end
		if IsValid(vm) then g_VR.viewModel = vm end
	end
	if IsValid(vm) then
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
	end
	ReassertLeftSnap(sf)
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

	-- gVRMod: hands close + stock wep only (EnsureVMI so missing currentvmi still works)
	local vmi = EnsureVMI(wep)
	local wepWorldPos, wepWorldAng = GunWorldFromHand(R.pos, R.ang, vmi)
	if not wepWorldPos or not wepWorldAng then return false end

	-- Offset against the *same* matrix the mesh will use (fixes grip ≠ viewmodel)
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

hook.Add("VRMod_Input", "vrmod_foregrip", function(action, pressed)
	if not g_VR or not g_VR.active then return end
	if action ~= "boolean_left_pickup" then return end
	if g_VR.menuGrabActive or g_VR.menuResizeActive then
		if not pressed and state.gripping then ClearGrip() end
		return
	end
	vrmod.TryForegripGrab(pressed)
end)

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
