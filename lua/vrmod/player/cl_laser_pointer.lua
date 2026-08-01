if SERVER then return end

-- =============================================================================
-- Weapon laser pointer — stereo-stable for VR + non-VR weapons
--
-- Desync causes (fixed):
--   • PostDrawTranslucent runs twice (L/R eyes) with live GetAttachment → different rays
--   • Non-VR viewmodels often have bad/missing attachment #1 after hand pose
--   • Skybox / depth passes re-drew the beam
--
-- SoT: freeze start+hit once per g_VR.stereoFrame; both eyes draw the same segment.
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

-- Once-per-stereo-frame freeze (shared L/R)
local snap = {
	frame = -1,
	startPos = nil,
	hitPos = nil,
	hit = false,
	hitNormal = nil,
}

local function HandPose()
	local hand = g_VR and g_VR.tracking and g_VR.tracking.pose_righthand
	if hand and hand.pos and hand.ang then return hand end
	return nil
end

--- Resolve muzzle for VR and non-VR weapons.
--- Prefer viewModel attachment when it is near the right hand; else hand ray.
local function ResolveMuzzle()
	local hand = HandPose()
	if not hand then return nil, nil end

	-- Refresh bones / attachment from current gun pose when possible
	if vrmod.utils and vrmod.utils.UpdateViewModel then
		pcall(vrmod.utils.UpdateViewModel)
	end

	local muzzle = g_VR.viewModelMuzzle
	local vmi = g_VR.currentvmi
	local useAtt = muzzle and muzzle.Pos and muzzle.Ang

	-- Non-VR / broken attachments: reject if muzzle is far from hand (desync source)
	if useAtt then
		local d2 = muzzle.Pos:DistToSqr(hand.pos)
		if d2 > (120 * 120) then
			useAtt = false
		end
	end

	local startPos, dir
	if useAtt then
		startPos = muzzle.Pos
		if vmi and vmi.wrongMuzzleAng then
			dir = hand.ang:Forward()
		else
			dir = muzzle.Ang:Forward()
			-- If attachment forward is nonsense (points back into hand), fall back to hand
			local toHand = hand.pos - startPos
			if toHand:LengthSqr() > 1 and dir:Dot(toHand:GetNormalized()) > 0.55 then
				dir = hand.ang:Forward()
			end
		end
	else
		-- Hand-forward fallback (stable for bare tools / bad c_ models)
		local off = (vmi and vmi.offsetPos) or Vector(4, 0, 0)
		startPos = hand.pos
			+ hand.ang:Forward() * (off.x ~= 0 and math.abs(off.x) * 0.25 + 3 or 4)
			+ hand.ang:Right() * (off.y or 0) * 0.1
			+ hand.ang:Up() * (off.z or 0) * 0.1
		dir = hand.ang:Forward()
	end

	if not startPos or not dir then return nil, nil end
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

	local endPos = startPos + dir * 10000
	local tr = util.TraceLine({
		start = startPos,
		endpos = endPos,
		filter = LocalPlayer(),
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
	-- Use stereoFrame so L/R share the same width (no per-eye sin desync)
	local t = (g_VR.stereoFrame or 0) * 0.15 + CurTime() * 40
	return 0.05 + math.abs(math.sin(t)) * 0.05
end

local function drawLaser(depth, sky)
	if depth or sky then return end
	if not g_VR or not g_VR.active then return end
	if g_VR.menuFocus then return end
	-- Only during stereo eye passes (same freeze both eyes)
	if not g_VR.stereoEye then return end

	local wep = LocalPlayer():GetActiveWeapon()
	if not IsValid(wep) then return end
	local info = g_VR.viewModelInfo and g_VR.viewModelInfo[wep:GetClass()]
	if info and info.noLaser then return end

	if not EnsureSnap() then return end
	local startPos, hitPos = snap.startPos, snap.hitPos
	if not startPos or not hitPos then return end

	local function ScaleAlpha(col, scale)
		return Color(col.r, col.g, col.b, math.Clamp(col.a * scale, 0, 255))
	end

	render.SetMaterial(LaserMaterial)
	render.DrawBeam(startPos, hitPos, getFlickerWidth(), 0, 1, laserColor)
	render.SetMaterial(GlowSprite)
	render.DrawSprite(startPos, 1, 1, laserColor)
	if snap.hit and snap.hitNormal then
		render.DrawSprite(hitPos + snap.hitNormal * 1, 8, 8, ScaleAlpha(laserColor, 1.2))
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

-- Snapshot early so both eyes share the same ray (even if draw order varies)
hook.Add("VRMod_PreStereo", "vrmod_laser_snap", function()
	if not g_VR or not g_VR.active then return end
	if not GetConVar("vrmod_laserpointer") or not GetConVar("vrmod_laserpointer"):GetBool() then return end
	if g_VR.menuFocus then return end
	EnsureSnap()
end)

hook.Add("VRMod_Start", "laserOn", function()
	timer.Simple(0.1, function()
		if GetConVar("vrmod_laserpointer"):GetBool() then setLaserEnabled(true) end
		local laserColorConvar = GetConVar("vrmod_laser_color")
		if laserColorConvar then UpdateLaserColor(laserColorConvar:GetString()) end
	end)
end)

hook.Add("VRMod_Exit", "laserOff", function()
	hook.Remove("PostDrawTranslucentRenderables", "vr_laserpointer")
	hook.Remove("VRMod_PreStereo", "vrmod_laser_snap")
	snap.frame = -1
end)
