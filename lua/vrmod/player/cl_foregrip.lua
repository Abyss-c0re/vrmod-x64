if SERVER then return end
-- =============================================================================
-- Universal foregrip (two-hand weapon aim) — ArcVR + stock/non-VR SWEPs
--
-- VRMod owns grip state + stereo snap for every weapon:
--   • stock / non-VR: guided RH→LH aim on PreStereo
--   • ArcVR (TwoHanded): bone-zone grab, GripForegrip/UngripFinger state;
--     pose stays in AVR_GunTracking (recoil, pump, stock, attachments)
--
-- Frame order (cl_vrmod PerformRenderViews):
--   UpdateTracking → VRMod_Tracking (ArcVR gun track) → stereoPose freeze
--   → VRMod_PreStereo (snap publish / stock guide) → eyes draw only
--
-- Ownership: cl_input → TryForegripGrab before world prop pickup.
-- ArcVR defers its own left-grip foregrip branch when this module is present.
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

local cv_enable = CreateClientConVar("vrmod_foregrip_enabled", "1", true, FCVAR_ARCHIVE,
	"Universal two-hand foregrip for stock + ArcVR weapons", 0, 1)
local cv_dist = CreateClientConVar("vrmod_foregrip_distance", "22", true, FCVAR_ARCHIVE,
	"Max hand↔hand / hand↔foregrip distance to start two-hand grip", 4, 48)
local cv_blend = CreateClientConVar("vrmod_foregrip_blend", "0.45", true, FCVAR_ARCHIVE,
	"Stock aim blend toward support hand (0–1)", 0, 1)
local cv_release = CreateClientConVar("vrmod_foregrip_release", "1.5", true, FCVAR_ARCHIVE,
	"Release multiplier × max(weapon reach, start distance)", 1.05, 3)
local cv_arc_radius = CreateClientConVar("vrmod_foregrip_arcvr_radius", "14", true, FCVAR_ARCHIVE,
	"ArcVR world-space foregrip grab radius (units)", 6, 40)

local MODE_STOCK = "stock"
local MODE_ARCVR = "arcvr"

local state = {
	gripping = false,
	mode = MODE_STOCK,
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

local function NotifyArcVRUngrip(wep)
	wep = wep or state.wep
	if IsValid(wep) and wep.ArcticVR and wep.ForegripGrabbed and isfunction(wep.UngripForegrip) then
		pcall(wep.UngripForegrip, wep)
	elseif IsValid(wep) and wep.ArcticVR then
		wep.ForegripGrabbed = false
	end
end

local function NotifyArcVRGrip(wep)
	if IsValid(wep) and wep.ArcticVR and isfunction(wep.GripForegrip) then
		pcall(wep.GripForegrip, wep)
	elseif IsValid(wep) and wep.ArcticVR then
		wep.ForegripGrabbed = true
	end
end

local function ClearGrip(reason)
	if state.gripping and state.mode == MODE_ARCVR then
		NotifyArcVRUngrip(state.wep)
	end
	state.gripping = false
	state.mode = MODE_STOCK
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

local function IsArcVRWeapon(wep)
	return IsValid(wep) and wep.ArcticVR and not wep.ArcticVRNade
end

local function IsValidForegripWeapon(wep)
	if not IsValid(wep) then return false end
	local class = string.lower(wep:GetClass() or "")
	if class == "" or class == "weapon_vrmod_empty" then return false end
	if class:find("weapon_fists", 1, true) then return false end
	if class:StartWith("avrmag_") then return false end
	if wep.ArcticVRNade then return false end

	-- ArcVR two-handers (pose backend stays in ArcVR gun tracking)
	if IsArcVRWeapon(wep) then
		return wep.TwoHanded and true or false
	end

	-- Stock / non-VR (unknown arctic* without .ArcticVR flag stays out)
	if class:StartWith("arcticvr") then return false end
	-- Prefer IsValidWep, but don't hard-fail stock guns with odd VM paths
	if vrmod.utils and vrmod.utils.IsValidWep then
		if vrmod.utils.IsValidWep(wep) then return true end
		local vm = wep.ViewModel or (wep.GetWeaponViewModel and wep:GetWeaponViewModel()) or ""
		if vm ~= "" and vm ~= "models/weapons/c_arms.mdl" then return true end
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
	if not g_VR.currentvmi then
		g_VR.currentvmi = { offsetPos = Vector(0, 0, 0), offsetAng = Angle(0, 0, 0) }
	else
		if not g_VR.currentvmi.offsetPos then g_VR.currentvmi.offsetPos = Vector(0, 0, 0) end
		if not g_VR.currentvmi.offsetAng then g_VR.currentvmi.offsetAng = Angle(0, 0, 0) end
	end
	return g_VR.currentvmi
end

local function SoftReach(reach)
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

local function ReleaseMaxDist()
	local reach = (state.weaponBox and state.weaponBox.reach) or SoftReach(nil)
	local mult = math.Clamp(cv_release:GetFloat(), 1.05, 3)
	local fromReach = reach * mult
	local fromStart = (state.startDist or cv_dist:GetFloat()) * mult
	-- ArcVR foregrips sit farther out — give them more slack
	if state.mode == MODE_ARCVR then
		fromReach = math.max(fromReach, 28 * mult)
	end
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
	newAng.r = rightAng.r
	return rightPos, newAng
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

local function LiveHands()
	local L = g_VR.tracking and g_VR.tracking.pose_lefthand
	local R = g_VR.tracking and g_VR.tracking.pose_righthand
	if not (L and R and L.pos and R.pos and L.ang and R.ang) then return nil end
	return L.pos, L.ang, R.pos, R.ang
end

local function GripStillHeld()
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

local function StampLeftHand(sf)
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

local function CanStartGripContext()
	if not cv_enable:GetBool() then return false end
	if not g_VR or not g_VR.active then return false end
	if g_VR.menuFocus or g_VR.menuGrabActive or g_VR.menuResizeActive then return false end
	if g_VR.avatarSteerTwin then return false end
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply:Alive() then return false end
	if ply:InVehicle() then return false end
	return true
end

--- World-space ArcVR foregrip point. Offset is applied in RH/gun axes (matches ArcVR track).
local function ArcVRForegripWorldPos(wep, rpos, rang)
	local off = wep.ForegripOffset
	if not isvector(off) then off = Vector(12, -2, 0) end

	-- Hand-local (most reliable at input time — same basis AVR_GunTracking uses pre-aim)
	if rpos and rang then
		local p = Vector(rpos)
		p = p + rang:Forward() * off.x + rang:Right() * off.y + rang:Up() * off.z
		return p
	end
	local gunPos, gunAng = g_VR.viewModelPos, g_VR.viewModelAng
	if gunPos and gunAng then
		return gunPos + gunAng:Forward() * off.x + gunAng:Right() * off.y + gunAng:Up() * off.z
	end
	local vm = g_VR.viewModel
	if IsValid(vm) then
		local a = vm:GetAngles()
		return vm:GetPos() + a:Forward() * off.x + a:Right() * off.y + a:Up() * off.z
	end
	return nil
end

--- ArcVR: hand in foregrip — world offset (primary) + bone OBB when available.
local function ArcVRHandInForegrip(wep, lpos, rpos, rang)
	if not IsValid(wep) or not wep.TwoHanded then return false end
	if wep.SlideGrabbed or wep.BeltGrabbed or wep.DustCoverGrabbed then return false end
	if wep.ForegripOnPivot and wep.ChamberOpen then return false end
	if not lpos then
		local L = g_VR.tracking and g_VR.tracking.pose_lefthand
		lpos = L and L.pos
	end
	if not lpos then return false end

	local rad = math.max(cv_arc_radius:GetFloat(), 8)
	local fgWorld = ArcVRForegripWorldPos(wep, rpos, rang)
	if fgWorld and lpos:DistToSqr(fgWorld) <= (rad * rad) then
		return true
	end

	-- Bone OBB (needs SetupBones; often fails mid-input — only bonus path)
	local mag = 1
	local cv = GetConVar("arcticvr_grip_magnification")
	if cv then mag = math.max(cv:GetFloat(), 0.25) end
	local mins = wep.ForegripMins or Vector(-4, -3, -4)
	local maxs = wep.ForegripMaxs or Vector(4, 3, 4)
	if isvector(mins) then mins = Vector(mins.x * mag, mins.y * mag, mins.z * mag) end
	if isvector(maxs) then maxs = Vector(maxs.x * mag, maxs.y * mag, maxs.z * mag) end

	local bone = wep.BoneIndices and wep.BoneIndices.foregrip
	if bone ~= nil and isfunction(wep.LeftHandInMaxs) then
		local vm = g_VR.viewModel
		if IsValid(vm) then pcall(vm.SetupBones, vm) end
		local ok, hit = pcall(wep.LeftHandInMaxs, wep, bone, mins, maxs)
		if ok and hit then return true end
	end

	return false
end

--- ArcVR backend: pose already solved on VRMod_Tracking; freeze snap + LH for both eyes.
local function SolveArcVRFrame(sf, lpos, lang, rpos)
	local maxDist = ReleaseMaxDist()
	if lpos:Distance(rpos) > maxDist then
		ClearGrip("hands too far")
		return false
	end

	-- Prefer gun matrix ArcVR just wrote; fall back to VM entity
	local gunPos = g_VR.viewModelPos
	local gunAng = g_VR.viewModelAng
	if not gunPos or not gunAng then
		local vm = g_VR.viewModel
		if IsValid(vm) then
			gunPos, gunAng = vm:GetPos(), vm:GetAngles()
		else
			return false
		end
	end

	-- LH already placed by AVR_GunTracking; use live/stereo left
	local L = g_VR.tracking and g_VR.tracking.pose_lefthand
	local leftPos = (L and L.pos) or lpos
	local leftAng = (L and L.ang) or lang

	state.gunPos:Set(gunPos)
	state.gunAng:Set(gunAng)
	state.leftPos:Set(leftPos)
	state.leftAng:Set(leftAng)
	state.frame = sf
	state.bonesFrame = -1

	PublishWeaponSnap(sf, state.gunPos, state.gunAng)
	g_VR.foregripActive = true
	StampLeftHand(sf)
	-- Keep SWEP flag in sync if something cleared it
	local wep = state.wep
	if IsValid(wep) and wep.ArcticVR and not wep.ForegripGrabbed then
		NotifyArcVRGrip(wep)
	end
	return true
end

--- Stock backend: guide aim from frozen stereo hands once per frame.
local function SolveStockFrame(sf, lpos, lang, rpos, rang, wep, vmi)
	local ply = LocalPlayer()
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
	StampLeftHand(sf)
	return true
end

local function SolveForegripFrame()
	if not state.gripping then return false end
	if not cv_enable:GetBool() then
		ClearGrip("disabled")
		return false
	end

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
	if g_VR.menuGrabActive or g_VR.menuResizeActive then
		ClearGrip("menu grab")
		return false
	end

	local sf = g_VR.stereoFrame or 0
	if state.frame == sf then
		PublishWeaponSnap(sf, state.gunPos, state.gunAng)
		StampLeftHand(sf)
		return true
	end

	local lpos, lang, rpos, rang = StereoHands()
	if not lpos or not rpos then
		ClearGrip("no hands")
		return false
	end

	if state.mode == MODE_ARCVR then
		return SolveArcVRFrame(sf, lpos, lang, rpos)
	end

	local vmi = EnsureVMI(wep)
	return SolveStockFrame(sf, lpos, lang, rpos, rang, wep, vmi)
end

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
	StampLeftHand(sf)
end

local function TryStartGrip()
	if not CanStartGripContext() then return false end
	if state.gripping then return true end

	-- Prefer live tracking at input time (stereoPose is last frame's freeze)
	local lpos, lang, rpos, rang = LiveHands()
	if not lpos then
		lpos, lang, rpos, rang = StereoHands()
	end
	if not lpos or not rpos then return false end

	local wep = LocalPlayer():GetActiveWeapon()
	if not IsValidForegripWeapon(wep) then return false end

	local mode = MODE_STOCK
	local dist = lpos:Distance(rpos)
	local maxStart = cv_dist:GetFloat()

	if IsArcVRWeapon(wep) then
		mode = MODE_ARCVR
		if not ArcVRHandInForegrip(wep, lpos, rpos, rang) then return false end
	else
		-- Stock: hand-to-hand OR left hand near estimated gun fore (long guns)
		local nearHands = dist <= maxStart
		local vmi = EnsureVMI(wep)
		local gunPos = g_VR.viewModelPos
		local gunAng = g_VR.viewModelAng
		if not gunPos or not gunAng then
			gunPos, gunAng = LocalToWorld(vmi.offsetPos or Vector(), vmi.offsetAng or Angle(), rpos, rang)
		end
		-- Soft “fore” point ~ halfway along typical rifle
		local fore = gunPos + gunAng:Forward() * math.min(math.max(dist * 0.5, 6), 16)
		local nearFore = lpos:DistToSqr(fore) <= (maxStart * maxStart)
		if not nearHands and not nearFore then return false end
	end

	local vmi = EnsureVMI(wep)
	local wepWorldPos, wepWorldAng = LocalToWorld(
		vmi.offsetPos or Vector(),
		vmi.offsetAng or Angle(),
		rpos, rang
	)
	state.offsetPos, state.offsetAng = WorldToLocal(lpos, lang, wepWorldPos, wepWorldAng)
	state.gripping = true
	state.mode = mode
	state.wep = wep
	state.class = wep:GetClass()
	state.frame = -1
	state.bonesFrame = -1
	state.boxTries = 0
	state.weaponBox = nil
	state.startDist = math.max(dist, 6)
	if mode == MODE_STOCK then
		RefreshWeaponBox(LocalPlayer(), wep)
	else
		local off = wep.ForegripOffset
		local reach = (isvector(off) and off:Length()) or 18
		state.weaponBox = {
			mins = wep.ForegripMins or Vector(-4, -4, -4),
			maxs = wep.ForegripMaxs or Vector(4, 4, 4),
			reach = math.max(reach, 18),
			radius = 4,
		}
		NotifyArcVRGrip(wep)
	end
	g_VR.foregripActive = true
	return true
end

--- ArcVR / UI: true while this module owns two-hand grip input.
function vrmod.HasUniversalForegrip()
	return cv_enable:GetBool()
end

--- opts.fromArcVR: called after ArcVR slide/mag priority (preferred for ArcVR).
--- Also allows start from default input so grip works if ArcVR hook order differs.
function vrmod.TryForegripGrab(pressed, opts)
	if not g_VR or not g_VR.active then return false end
	if not cv_enable:GetBool() then return false end
	opts = opts or {}
	if not pressed then
		if state.gripping then
			ClearGrip("input release")
			return true
		end
		return false
	end
	if state.gripping then
		return true
	end
	return TryStartGrip()
end

function vrmod.IsForegripActive()
	return state.gripping and true or false
end

function vrmod.GetForegripMode()
	return state.gripping and state.mode or nil
end

hook.Add("VRMod_Input", "vrmod_foregrip", function(action, pressed)
	if not g_VR or not g_VR.active then return end
	if action ~= "boolean_left_pickup" then return end
	vrmod.TryForegripGrab(pressed)
end)

hook.Add("VRMod_PreStereo", "vrmod_foregrip", function()
	if not g_VR or not g_VR.active then return end
	if state.gripping then
		SolveForegripFrame()
	end
end)

hook.Add("VRMod_PreRender", "vrmod_foregrip", function()
	if state.gripping then
		ApplyFrozenGunDraw()
	end
end)

-- Non-grip weapon freeze when not two-handing (stock + ArcVR one-hand pose already in tracking)
hook.Add("VRMod_PreStereo", "vrmod_weapon_pose_freeze", function()
	if not g_VR or not g_VR.active then return end
	if state.gripping then return end
	if vrmod.utils and vrmod.utils.UpdateViewModelPos then
		local sp = g_VR.stereoPose
		local sf = g_VR.stereoFrame or 0
		-- ArcVR sets suppressViewModelUpdates and already posed on Tracking —
		-- only re-apply when not suppressed, or publish existing matrix.
		if vrmod.suppressViewModelUpdates then
			if g_VR.viewModelPos and g_VR.viewModelAng then
				PublishWeaponSnap(sf, g_VR.viewModelPos, g_VR.viewModelAng)
			end
			return
		end
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
