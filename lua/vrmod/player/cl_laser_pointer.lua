if SERVER then return end

-- =============================================================================
-- Weapon laser pointer — stereo-stable, attached to stock + VR guns
--
-- Laser start/dir freeze once per stereoFrame (both eyes share one segment).
-- Stock weapons: always slave gun pose first, then muzzle from gun matrix
-- (not a free-floating hand ray that looks "detached").
-- =============================================================================

local laserColor = Color(255, 0, 0, 255)
local LaserMaterial = Material("cable/red")
do
	local matData = {
		["$basetexture"] = "color/white",
		["$additive"] = "1",
		["$vertexcolor"] = "1",
		["$vertexalpha"] = "1",
		["$nocull"] = "1",
		["$ignorez"] = "0",
	}
	local ok, customMat = pcall(CreateMaterial, "CustomLaserMaterial", "UnlitGeneric", matData)
	if ok and customMat then LaserMaterial = customMat end
end

local GlowSprite = Material("sprites/glow04_noz")

local function UpdateLaserColor(colorString)
	if not colorString or colorString == "" then return end
	local r, g, b, a = string.match(tostring(colorString), "(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
	if not (r and g and b and a) then return end
	laserColor = Color(tonumber(r), tonumber(g), tonumber(b), tonumber(a))
end

vrmod.ApplyLaserColor = UpdateLaserColor
vrmod.GetLaserColor = function()
	return Color(laserColor.r, laserColor.g, laserColor.b, laserColor.a)
end

vrmod.AddCallbackedConvar("vrmod_laser_color", nil, "255,0,0,255", nil, "", nil, nil, nil, function(newValue)
	UpdateLaserColor(newValue)
end)

local snap = {
	frame = -1,
	startPos = nil,
	hitPos = nil,
	hit = false,
	hitNormal = nil,
}

local function HandPose()
	-- Prefer stereo-frozen right hand (same both eyes)
	local sp = g_VR and g_VR.stereoPose
	local sf = g_VR and g_VR.stereoFrame or 0
	if sp and sp.frame == sf and sp.hasRight then
		return { pos = sp.rightPos, ang = sp.rightAng }
	end
	local hand = g_VR and g_VR.tracking and g_VR.tracking.pose_righthand
	if hand and hand.pos and hand.ang then return hand end
	return nil
end

local function IsArcVRWeapon(class)
	if not class then return false end
	class = string.lower(class)
	return class:StartWith("arcticvr") or class:find("avrmag_", 1, true) ~= nil
end

--- Muzzle + aim for laser — always from gun pose after UpdateViewModel.
local function ResolveMuzzle()
	local hand = HandPose()
	if not hand then return nil, nil end

	local wep = LocalPlayer():GetActiveWeapon()
	local class = IsValid(wep) and wep:GetClass() or ""
	local vmi = g_VR.currentvmi or (g_VR.viewModelInfo and g_VR.viewModelInfo[class]) or {}
	local sf = g_VR.stereoFrame or 0
	local gunPos, gunAng

	-- Prefer stereo-frozen weapon snap (foregrip guided aim / PreStereo freeze).
	-- Do not re-solve from raw RH — that undoes two-hand aim mid-draw.
	if g_VR._weaponSnapFrame == sf and g_VR._weaponSnapPos and g_VR._weaponSnapAng then
		gunPos, gunAng = g_VR._weaponSnapPos, g_VR._weaponSnapAng
		g_VR.viewModelPos = gunPos
		g_VR.viewModelAng = gunAng
	else
		-- Force stock/VR gun onto hand SoT before reading attachments
		if vrmod.utils and vrmod.utils.UpdateViewModelPos then
			pcall(vrmod.utils.UpdateViewModelPos, hand.pos, hand.ang, true)
		elseif vrmod.utils and vrmod.utils.UpdateViewModel then
			pcall(vrmod.utils.UpdateViewModel)
		end
		gunPos = g_VR.viewModelPos
		gunAng = g_VR.viewModelAng
	end
	if not gunPos or not gunAng then
		gunPos, gunAng = hand.pos, hand.ang
	end

	local muz = g_VR.viewModelMuzzle
	local startPos, dir

	-- Prefer attachment position if it sits near the gun origin (not world-stale)
	local attOk = muz and muz.Pos and gunPos and muz.Pos:DistToSqr(gunPos) < (80 * 80)
	if attOk then
		startPos = muz.Pos
	else
		-- Stock tip: slightly ahead of posed gun
		startPos = gunPos + gunAng:Forward() * 12
	end

	-- Aim direction: gun matrix (or hand if wrongMuzzleAng / broken att)
	if vmi.wrongMuzzleAng then
		dir = hand.ang:Forward()
	elseif attOk and muz.Ang and IsArcVRWeapon(class) then
		-- ArcVR: trust attachment angles more often
		dir = muz.Ang:Forward()
		local back = hand.pos - startPos
		if back:LengthSqr() > 4 and dir:Dot(back:GetNormalized()) > 0.5 then
			dir = gunAng:Forward()
		end
	else
		-- Stock weapons: gun pose forward = laser dir (attachment ang is often wrong)
		dir = gunAng:Forward()
	end

	if not startPos or not dir then return nil, nil end
	-- Final attach check: start must be near hand/gun (no free-floating beam)
	if startPos:DistToSqr(hand.pos) > (120 * 120) then
		startPos = gunPos + gunAng:Forward() * 10
		dir = gunAng:Forward()
	end
	return startPos, dir
end

local function EnsureSnap()
	local sf = g_VR.stereoFrame or FrameNumber() or 0
	if snap.frame == sf and snap.startPos and snap.hitPos then
		return true
	end

	local startPos, dir = ResolveMuzzle()
	if not startPos or not dir then
		snap.frame = sf
		snap.startPos, snap.hitPos = nil, nil
		return false
	end

	local tr = util.TraceLine({
		start = startPos,
		endpos = startPos + dir * 10000,
		filter = function(ent)
			if ent == LocalPlayer() then return false end
			if ent == g_VR.viewModel or ent == g_VR.worldModelVM then return false end
			if ent == g_VR.heldEntityLeft or ent == g_VR.heldEntityRight then return false end
			return true
		end,
		mask = MASK_SHOT,
	})

	snap.frame = sf
	snap.startPos = Vector(startPos)
	snap.hitPos = Vector(tr.HitPos)
	snap.hit = tr.Hit and true or false
	snap.hitNormal = tr.Hit and Vector(tr.HitNormal) or nil
	return true
end

local function getFlickerWidth()
	local t = (g_VR.stereoFrame or 0) * 0.15
	return 0.05 + math.abs(math.sin(t)) * 0.04
end

local function drawLaser(depth, sky)
	if depth or sky then return end
	if not g_VR or not g_VR.active then return end
	if g_VR.menuFocus then return end
	if not g_VR.stereoEye then return end

	local wep = LocalPlayer():GetActiveWeapon()
	if not IsValid(wep) then return end
	local info = g_VR.viewModelInfo and g_VR.viewModelInfo[wep:GetClass()]
	if info and info.noLaser then return end

	if not EnsureSnap() then return end
	local startPos, hitPos = snap.startPos, snap.hitPos
	if not startPos or not hitPos then return end

	render.SetMaterial(LaserMaterial)
	render.DrawBeam(startPos, hitPos, getFlickerWidth(), 0, 1, laserColor)
	render.SetMaterial(GlowSprite)
	render.DrawSprite(startPos, 1.2, 1.2, laserColor)
	if snap.hit and snap.hitNormal then
		local c = Color(laserColor.r, laserColor.g, laserColor.b, math.min(255, laserColor.a + 40))
		render.DrawSprite(hitPos + snap.hitNormal, 8, 8, c)
	end
end

local function setLaserEnabled(enabled)
	if enabled then
		hook.Add("PostDrawTranslucentRenderables", "vr_laserpointer", drawLaser)
	else
		hook.Remove("PostDrawTranslucentRenderables", "vr_laserpointer")
	end
	RunConsoleCommand("vrmod_laserpointer", enabled and "1" or "0")
end

concommand.Add("vrmod_togglelaserpointer", function()
	local enabled = GetConVar("vrmod_laserpointer"):GetBool()
	setLaserEnabled(not enabled)
end)

-- Snap after tracking + viewmodel pose (PreStereo is after ApplyPoseModifiers in frame)
hook.Add("VRMod_PreStereo", "vrmod_laser_snap", function()
	if not g_VR or not g_VR.active then return end
	local cv = GetConVar("vrmod_laserpointer")
	if not cv or not cv:GetBool() then return end
	if g_VR.menuFocus then return end
	EnsureSnap()
end)

hook.Add("VRMod_Start", "laserOn", function()
	timer.Simple(0.1, function()
		if GetConVar("vrmod_laserpointer"):GetBool() then setLaserEnabled(true) end
		local c = GetConVar("vrmod_laser_color")
		if c then UpdateLaserColor(c:GetString()) end
	end)
end)

hook.Add("VRMod_Exit", "laserOff", function()
	hook.Remove("PostDrawTranslucentRenderables", "vr_laserpointer")
	hook.Remove("VRMod_PreStereo", "vrmod_laser_snap")
	snap.frame = -1
end)
