if SERVER then return end
-- =============================================================================
-- Stock / non-VR two-hand foregrip (vrmod-x64)
--
-- MINIMAL reliable path (gVRMod + proven x64):
--   START: left grip + hands within GRIP_DISTANCE + stock weapon
--   HOLD:  guided RH → gun = RH+VMI → LH offset on that gun matrix
--   RELEASE: left grip up only (input), not flaky distance on first frames
--
-- No menuGrabActive hard block. No mid-gun radial gates.
-- ArcVR: arcticvr_base only.
-- =============================================================================

local function BlockOld()
	for _, pair in ipairs({
		{ "VRMod_Input", "Foregrip" },
		{ "VRMod_PreRender", "ForegripTransform" },
		{ "VRMod_Exit", "ForegripExit" },
		{ "VRMod_PreStereo", "vrmod_foregrip" },
		{ "VRMod_PreRender", "vrmod_foregrip" },
		{ "VRMod_PreStereo", "0_vrmod_foregrip" },
		{ "VRMod_PreRender", "0_vrmod_foregrip" },
		{ "VRMod_PreStereo", "1_vrmod_weapon_pose_freeze" },
		{ "VRMod_PreStereo", "vrmod_weapon_pose_freeze" },
		{ "VRMod_Input", "vrmod_foregrip" },
		{ "VRMod_PreRender", "vrmod_foregrip_x64" },
	}) do
		local t = hook.GetTable()[pair[1]]
		if t and t[pair[2]] then hook.Remove(pair[1], pair[2]) end
	end
end
BlockOld()
timer.Simple(0.5, BlockOld)
timer.Simple(2, BlockOld)

-- Generous start (was 12/20 — too easy to miss). Override: vrmod_stock_foregrip_distance
local cv_dist = CreateClientConVar("vrmod_stock_foregrip_distance", "40", true, FCVAR_ARCHIVE,
	"Max hand-hand distance to START stock foregrip", 8, 80)
local cv_blend = CreateClientConVar("vrmod_stock_foregrip_blend", "0.4", true, FCVAR_ARCHIVE,
	"Aim blend toward support hand 0–1", 0, 1)
local cv_release = CreateClientConVar("vrmod_stock_foregrip_release", "2.0", true, FCVAR_ARCHIVE,
	"Release if hands > startDist × this", 1.2, 4)

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
	heldSince = 0,
}

local function ClearGrip()
	state.gripping = false
	state.frame = -1
	state.bonesFrame = -1
	state.wep = NULL
	state.class = nil
	state.heldSince = 0
	g_VR._leftHandSnapFrame = -1
	local aw = IsValid(LocalPlayer()) and LocalPlayer():GetActiveWeapon() or NULL
	if not (IsValid(aw) and aw.ArcticVR and aw.ForegripGrabbed) then
		g_VR.foregripActive = false
	end
end

local function IsStockWep(wep)
	if not IsValid(wep) then return false end
	if wep.ArcticVR or wep.ArcticVRNade then return false end
	local class = string.lower(tostring(wep:GetClass() or ""))
	if class == "" or class == "weapon_vrmod_empty" then return false end
	if class:find("weapon_fists", 1, true) then return false end
	if class:find("arcticvr", 1, true) then return false end
	if class:StartWith("avrmag_") then return false end
	return true
end

local function EnsureVMI(wep)
	-- Always produce a VMI so stock SWEP without viewModelInfo still grips
	local class = IsValid(wep) and wep:GetClass() or nil
	if class and g_VR.viewModelInfo and g_VR.viewModelInfo[class] then
		local e = g_VR.viewModelInfo[class]
		e.offsetPos = e.offsetPos or Vector(0, 0, 0)
		e.offsetAng = e.offsetAng or Angle(0, 0, 0)
		g_VR.currentvmi = e
		return e
	end
	if g_VR.currentvmi and g_VR.currentvmi.offsetPos and g_VR.currentvmi.offsetAng then
		return g_VR.currentvmi
	end
	g_VR.currentvmi = {
		offsetPos = Vector(0, 0, 0),
		offsetAng = Angle(0, 0, 0),
	}
	return g_VR.currentvmi
end

local function Hands()
	local L = g_VR.tracking and g_VR.tracking.pose_lefthand
	local R = g_VR.tracking and g_VR.tracking.pose_righthand
	if not (L and R and L.pos and R.pos and L.ang and R.ang) then return nil end
	-- Prefer stereo freeze when ready (same both eyes)
	local sp = g_VR.stereoPose
	local sf = g_VR.stereoFrame or 0
	if sp and sp.frame == sf and sp.hasLeft and sp.hasRight and sp.leftPos and sp.rightPos then
		return sp.leftPos, sp.leftAng, sp.rightPos, sp.rightAng
	end
	return L.pos, L.ang, R.pos, R.ang
end

local function Guide(rpos, rang, lpos, lang)
	local blend = math.Clamp(cv_blend:GetFloat(), 0, 1)
	if blend <= 0 then return rpos, rang end
	local toLeft = lpos - rpos
	local dist = toLeft:Length()
	if dist < 3 or dist > 80 then return rpos, rang end
	local target = toLeft:GetNormalized():Angle()
	local na = LerpAngle(blend, rang, target)
	na.r = rang.r
	return rpos, na
end

local function PublishSnap(sf, gunPos, gunAng)
	g_VR._weaponSnapFrame = sf
	if not g_VR._weaponSnapPos then g_VR._weaponSnapPos = Vector() end
	if not g_VR._weaponSnapAng then g_VR._weaponSnapAng = Angle() end
	g_VR._weaponSnapPos:Set(gunPos)
	g_VR._weaponSnapAng:Set(gunAng)
	g_VR.viewModelPos = Vector(gunPos.x, gunPos.y, gunPos.z)
	g_VR.viewModelAng = Angle(gunAng.p, gunAng.y, gunAng.r)
end

local function StampLeft(sf, p, a)
	g_VR._leftHandSnapFrame = sf
	if not g_VR._leftHandSnapPos then g_VR._leftHandSnapPos = Vector() end
	if not g_VR._leftHandSnapAng then g_VR._leftHandSnapAng = Angle() end
	g_VR._leftHandSnapPos:Set(p)
	g_VR._leftHandSnapAng:Set(a)

	if isfunction(vrmod.SetLeftHandPose) then
		vrmod.SetLeftHandPose(p, a, 0)
	else
		local L = g_VR.tracking and g_VR.tracking.pose_lefthand
		if L then
			if L.pos and L.pos.Set then L.pos:Set(p) else L.pos = Vector(p) end
			if L.ang and L.ang.Set then L.ang:Set(a) else L.ang = Angle(a.p, a.y, a.r) end
		end
	end

	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local nf = g_VR.net and g_VR.net[ply:SteamID()] and g_VR.net[ply:SteamID()].lerpedFrame
	if nf then
		nf.lefthandPos = Vector(p.x, p.y, p.z)
		nf.lefthandAng = Angle(a.p, a.y, a.r)
	end
	if vrmod_fbt and vrmod_fbt.characterInfo then
		local info = vrmod_fbt.characterInfo[ply:SteamID()]
		if info then info.frameNumber = -1 end
	end
	g_VR._charIkUpdated = nil
end

--- START grip (called from cl_input BEFORE menu grab / pickup)
local function TryStart()
	if not g_VR or not g_VR.active then return false end
	if state.gripping then return true end
	-- Never block on menu flags — only skip while corner-resizing a panel
	if g_VR.menuResizeActive then return false end

	local lpos, lang, rpos, rang = Hands()
	if not lpos then return false end

	local wep = LocalPlayer():GetActiveWeapon()
	if not IsStockWep(wep) then return false end

	local dist = lpos:Distance(rpos)
	local maxStart = math.Clamp(cv_dist:GetFloat(), 8, 80)
	if dist > maxStart then return false end

	local vmi = EnsureVMI(wep)
	local wepPos, wepAng = LocalToWorld(
		vmi.offsetPos or Vector(),
		vmi.offsetAng or Angle(),
		rpos, rang
	)
	state.offsetPos, state.offsetAng = WorldToLocal(lpos, lang, wepPos, wepAng)
	state.gripping = true
	state.wep = wep
	state.class = wep:GetClass()
	state.frame = -1
	state.bonesFrame = -1
	state.startDist = math.max(dist, 8)
	state.heldSince = CurTime()
	g_VR.foregripActive = true
	return true
end

function vrmod.TryForegripGrab(pressed)
	if not g_VR or not g_VR.active then return false end
	if pressed == false or pressed == nil then
		-- only release on explicit false (not nil)
		if pressed == false and state.gripping then
			ClearGrip()
			return true
		end
		return state.gripping
	end
	if state.gripping then return true end
	return TryStart()
end

function vrmod.IsForegripActive()
	return state.gripping == true
end

function vrmod.HasUniversalForegrip()
	return false
end

local function Solve()
	if not state.gripping then return end

	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:Alive() then
		ClearGrip()
		return
	end

	local wep = IsValid(state.wep) and state.wep or ply:GetActiveWeapon()
	if not IsStockWep(wep) then
		ClearGrip()
		return
	end
	if state.class and wep:GetClass() ~= state.class then
		ClearGrip()
		return
	end

	local sf = g_VR.stereoFrame or 0
	-- Same stereo frame: reassert only
	if state.frame == sf then
		PublishSnap(sf, state.gunPos, state.gunAng)
		StampLeft(sf, state.leftPos, state.leftAng)
		local vm = g_VR.viewModel
		if IsValid(vm) then
			vm:SetPos(state.gunPos)
			vm:SetAngles(state.gunAng)
		end
		return
	end

	local lpos, lang, rpos, rang = Hands()
	if not lpos then
		-- tracking glitch: keep grip, don't clear
		return
	end

	-- Grace period: don't release for 0.25s after grab (hands settle)
	local grace = (CurTime() - (state.heldSince or 0)) < 0.25
	if not grace then
		local rel = math.Clamp(cv_release:GetFloat(), 1.2, 4)
		local maxD = math.max(state.startDist * rel, cv_dist:GetFloat() * rel, 36)
		if lpos:Distance(rpos) > maxD then
			ClearGrip()
			return
		end
	end

	local vmi = EnsureVMI(wep)
	local handPos, handAng = Guide(rpos, rang, lpos, lang)
	local gunPos, gunAng = LocalToWorld(
		vmi.offsetPos or Vector(),
		vmi.offsetAng or Angle(),
		handPos, handAng
	)
	local attachPos, attachAng = LocalToWorld(state.offsetPos, state.offsetAng, gunPos, gunAng)

	state.gunPos:Set(gunPos)
	state.gunAng:Set(gunAng)
	state.leftPos:Set(attachPos)
	state.leftAng:Set(attachAng)
	state.frame = sf
	state.bonesFrame = -1
	g_VR.foregripActive = true

	PublishSnap(sf, gunPos, gunAng)
	StampLeft(sf, attachPos, attachAng)

	local vm = g_VR.viewModel
	if not IsValid(vm) then
		vm = ply:GetViewModel()
		if IsValid(vm) then g_VR.viewModel = vm end
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

-- Input: ONLY path for release/start from this file (cl_input also calls TryForegripGrab first)
hook.Add("VRMod_Input", "vrmod_foregrip", function(action, pressed)
	if not g_VR or not g_VR.active then return end
	if action ~= "boolean_left_pickup" then return end
	vrmod.TryForegripGrab(pressed and true or false)
end)

hook.Add("VRMod_PreStereo", "0_vrmod_foregrip", function()
	if g_VR and g_VR.active and state.gripping then Solve() end
end)

hook.Add("VRMod_PreRender", "0_vrmod_foregrip", function()
	if not state.gripping then return end
	local sf = g_VR.stereoFrame or 0
	if state.frame ~= sf then Solve() end
	if state.frame ~= sf then return end
	PublishSnap(sf, state.gunPos, state.gunAng)
	StampLeft(sf, state.leftPos, state.leftAng)
	local vm = g_VR.viewModel
	if IsValid(vm) then
		vm:SetPos(state.gunPos)
		vm:SetAngles(state.gunAng)
	end
end)

-- Stock non-grip freeze (both eyes)
hook.Add("VRMod_PreStereo", "1_vrmod_weapon_pose_freeze", function()
	if not g_VR or not g_VR.active or state.gripping then return end
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

hook.Add("VRMod_Exit", "vrmod_foregrip", ClearGrip)
hook.Add("PlayerSwitchWeapon", "vrmod_foregrip", function(ply)
	if ply == LocalPlayer() and state.gripping then ClearGrip() end
end)
hook.Add("PlayerDeath", "vrmod_foregrip", function(ply)
	if ply == LocalPlayer() then ClearGrip() end
end)

concommand.Add("vrmod_stock_foregrip_debug", function()
	local L = g_VR and g_VR.tracking and g_VR.tracking.pose_lefthand
	local R = g_VR and g_VR.tracking and g_VR.tracking.pose_righthand
	local wep = IsValid(LocalPlayer()) and LocalPlayer():GetActiveWeapon() or NULL
	local dist = (L and R and L.pos and R.pos) and L.pos:Distance(R.pos) or -1
	print(string.format(
		"[stock-foregrip] gripping=%s dist=%.1f maxStart=%.1f wep=%s stock=%s active=%s vmi=%s",
		tostring(state.gripping),
		dist,
		cv_dist:GetFloat(),
		IsValid(wep) and wep:GetClass() or "nil",
		tostring(IsStockWep(wep)),
		tostring(g_VR and g_VR.foregripActive),
		tostring(g_VR and g_VR.currentvmi ~= nil)
	))
end)
