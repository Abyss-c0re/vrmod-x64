if SERVER then return end

-- =============================================================================
-- VR HUD — one plate, vitals only (no loose copy of the desktop HUD)
--
-- Capture: PaintVitals only by default.
--   vrmod_hud_engine 1 also runs RenderHUD (optional; often empty / noisy in VR).
-- Draw: ONE path — PostDrawTranslucent while g_VR.stereoEye is set.
--   (No VRUtilRenderMenuSystem wrap — that doubled the plate with menus.)
-- Theme: Settings → Theme colors on HEALTH/ARMOR/AMMO text.
-- Optional aim crosshair: projects weapon/hand aim onto the plate (not HMD center).
-- mat_queue untouched.
-- =============================================================================

local vrScrH = CreateClientConVar("vrmod_ScrH_hud", "0", true, FCVAR_ARCHIVE)
local vrScrW = CreateClientConVar("vrmod_ScrW_hud", "0", true, FCVAR_ARCHIVE)
local cv_engine = CreateClientConVar("vrmod_hud_engine", "0", true, FCVAR_ARCHIVE,
	"1 = also capture engine RenderHUD (can look like a second loose HUD panel)")
local cv_crosshair = CreateClientConVar("vrmod_hud_crosshair", "0", true, FCVAR_ARCHIVE,
	"1 = optional aim reticle on HUD plate (weapon muzzle / aim API, not HMD center)")
local cv_crosshair_src = CreateClientConVar("vrmod_hud_crosshair_src", "muzzle", true, FCVAR_ARCHIVE,
	"Aim source: muzzle | hand | auto (muzzle then hand; never HMD)")

local function HudRes()
	local w = vrScrW:GetInt()
	local h = vrScrH:GetInt()
	if w < 64 then w = math.max(ScrW(), 1280) end
	if h < 64 then h = math.max(ScrH(), 720) end
	w = math.Clamp(math.floor(w / 32) * 32, 640, 1920)
	h = math.Clamp(math.floor(h / 32) * 32, 480, 1080)
	return w, h
end

local function CurvedPlane(w, h, segments, degrees, matrix)
	matrix = matrix or Matrix()
	degrees = math.rad(degrees)
	local mesh = Mesh()
	local verts = {}
	local startAng = (math.pi - degrees) / 2
	local segLen = 0.5 * math.tan(degrees / math.max(segments, 1))
	local scale = w / math.max(segLen * segments, 0.001)
	local zoffset = math.sin(startAng) * 0.5 * scale
	local col = Color(255, 255, 255, 255)
	for i = 0, segments - 1 do
		local fraction = i / segments
		local nextFraction = (i + 1) / segments
		local ang1 = startAng + fraction * degrees
		local ang2 = startAng + nextFraction * degrees
		local x1 = math.cos(ang1) * -0.5 * scale
		local x2 = math.cos(ang2) * -0.5 * scale
		local z1 = math.sin(ang1) * 0.5 * scale - zoffset
		local z2 = math.sin(ang2) * 0.5 * scale - zoffset
		verts[#verts + 1] = { pos = matrix * Vector(x1, 0, z1), u = fraction, v = 0, color = col }
		verts[#verts + 1] = { pos = matrix * Vector(x2, 0, z2), u = nextFraction, v = 0, color = col }
		verts[#verts + 1] = { pos = matrix * Vector(x2, h, z2), u = nextFraction, v = 1, color = col }
		verts[#verts + 1] = { pos = matrix * Vector(x2, h, z2), u = nextFraction, v = 1, color = col }
		verts[#verts + 1] = { pos = matrix * Vector(x1, h, z1), u = fraction, v = 1, color = col }
		verts[#verts + 1] = { pos = matrix * Vector(x1, 0, z1), u = fraction, v = 0, color = col }
	end
	mesh:BuildFromTriangles(verts)
	return mesh
end

local rtW, rtH = HudRes()
local rt = GetRenderTarget("vrmod_hud_paint", rtW, rtH, false)
local mat = CreateMaterial("vrmod_hud_mesh_paint_v2", "UnlitGeneric", {
	["$basetexture"] = rt:GetName(),
	["$translucent"] = 1,
	["$vertexalpha"] = 1,
	["$vertexcolor"] = 1,
	["$nolod"] = 1,
	["$nocull"] = 1,
	["$ignorez"] = 1,
})
if mat and not mat:IsError() then
	mat:SetTexture("$basetexture", rt)
	mat:SetInt("$translucent", 1)
	mat:SetInt("$additive", 0)
end

local hudMeshes = {}
local hudMesh = nil
local mtx = Matrix()
local hudBound = false
local captureN = 0
local plateScale = 0.05 -- last bound plate scale (world units per RT pixel * scale)
local _, convarValues = vrmod.GetConvars()

------------------------------------------------------------------------
-- VR aim: muzzle / hand API — never HMD-center “desktop” aim
------------------------------------------------------------------------
local function GetVRAim()
	local src = string.lower(cv_crosshair_src:GetString() or "muzzle")
	if src == "" then src = "auto" end

	local function fromMuzzle()
		local m = g_VR.viewModelMuzzle
		if m and m.Pos and m.Ang then
			return m.Pos, m.Ang:Forward(), "muzzle"
		end
		return nil
	end

	local function fromHand()
		if vrmod.GetRightHandPose then
			local p, a = vrmod.GetRightHandPose()
			if p and a and p:LengthSqr() > 0 then
				return p, a:Forward(), "hand"
			end
		end
		local rh = g_VR.tracking and g_VR.tracking.pose_righthand
		if rh and rh.pos and rh.ang then
			return rh.pos, rh.ang:Forward(), "hand"
		end
		return nil
	end

	-- Vehicle: use patched GetAimVector (muzzle-aware), origin from hand if possible
	local ply = LocalPlayer()
	if IsValid(ply) and ply:InVehicle() then
		local dir = ply:GetAimVector()
		local origin = select(1, fromMuzzle()) or select(1, fromHand()) or ply:EyePos()
		if dir then return origin, dir, "vehicle" end
	end

	if src == "hand" then
		return fromHand()
	elseif src == "muzzle" then
		return fromMuzzle() or fromHand()
	end
	-- auto
	return fromMuzzle() or fromHand()
end

--- Project aim ray onto HUD plate → RT pixel (or nil if miss / off-plate).
local function AimToHudPixel(aimPos, aimDir, w, h, pScale)
	local hmd = g_VR.tracking and g_VR.tracking.hmd
	if not hmd or not hmd.pos or not hmd.ang or not aimPos or not aimDir then return nil end

	local dist = CVFloat("vrmod_huddistance", 60)
	local planePos = hmd.pos + hmd.ang:Forward() * dist
	-- Plate faces the HMD: normal points back toward player along -forward of HMD
	local planeN = hmd.ang:Forward()
	local denom = aimDir:Dot(planeN)
	if math.abs(denom) < 1e-5 then return nil end
	local t = (planePos - aimPos):Dot(planeN) / denom
	if t < 0.05 or t > 400 then return nil end
	local hit = aimPos + aimDir * t

	-- Plate local: X≈right, Y≈up (HMD frame at plane center)
	local rel = WorldToLocal(hit, Angle(), planePos, hmd.ang)
	local halfW = w * pScale * 0.5
	local halfH = h * pScale * 0.5
	if halfW < 0.01 or halfH < 0.01 then return nil end
	-- Mesh is centered with +Z offset of h*scale/2 in build space; HMD local z is up
	local u = 0.5 + (rel.y / (w * pScale))
	local v = 0.5 - (rel.z / (h * pScale))
	if u < -0.05 or u > 1.05 or v < -0.05 or v > 1.05 then return nil end
	u = math.Clamp(u, 0, 1)
	v = math.Clamp(v, 0, 1)
	return u * w, v * h, hit
end

local function PaintAimCrosshair(w, h, pScale)
	if not cv_crosshair:GetBool() then return end
	local aimPos, aimDir, src = GetVRAim()
	if not aimPos then return end

	local px, py = AimToHudPixel(aimPos, aimDir, w, h, pScale)
	if not px then return end

	local T = (vrmod.cube and vrmod.cube.ThemeLive and vrmod.cube.ThemeLive())
		or (vrmod.cube and vrmod.cube.Theme) or {}
	local col = T.crimsonHot or T.hot or Color(255, 70, 100, 255)
	local outline = T.outline or Color(0, 0, 0, 200)
	local s = 10
	-- outline
	surface.SetDrawColor(outline)
	surface.DrawRect(px - s - 1, py - 1, s * 2 + 2, 3)
	surface.DrawRect(px - 1, py - s - 1, 3, s * 2 + 2)
	-- core
	surface.SetDrawColor(col.r, col.g, col.b, 255)
	surface.DrawRect(px - s, py, s * 2, 1)
	surface.DrawRect(px, py - s, 1, s * 2)
	-- center dot
	surface.DrawRect(px - 1, py - 1, 3, 3)

	-- tiny source tag (debug-friendly, low alpha)
	local fontL = (vrmod.cube and vrmod.cube.Font and vrmod.cube.Font("CubeSmall")) or "DermaDefault"
	draw.SimpleText(src or "aim", fontL, px + 14, py - 2, Color(col.r, col.g, col.b, 120), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

local function CVBool(name, default)
	local c = GetConVar(name)
	if c then return c:GetBool() end
	if convarValues and convarValues[name] ~= nil then return convarValues[name] and true or false end
	return default
end

local function CVFloat(name, default)
	local c = GetConVar(name)
	if c then return c:GetFloat() end
	if convarValues and convarValues[name] ~= nil then return tonumber(convarValues[name]) or default end
	return default
end

local function CVString(name, default)
	local c = GetConVar(name)
	if c then return c:GetString() end
	if convarValues and convarValues[name] ~= nil then return tostring(convarValues[name]) end
	return default
end

--- Theme-matched vitals only (one layer — not a full desktop HUD clone)
local function PaintVitals(w, h)
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local T = (vrmod.cube and vrmod.cube.ThemeLive and vrmod.cube.ThemeLive())
		or (vrmod.cube and vrmod.cube.Theme)
		or {}
	local outline = T.outline or Color(0, 0, 0, 220)
	local fontV = (vrmod.cube and vrmod.cube.Font and vrmod.cube.Font("CubeHuge")) or "DermaLarge"
	local fontL = (vrmod.cube and vrmod.cube.Font and vrmod.cube.Font("CubeSmall")) or "DermaDefaultBold"
	local muted = T.muted or Color(200, 150, 165, 230)

	local hp = math.max(0, math.floor(ply:Health() or 0))
	local arm = math.max(0, math.floor(ply:Armor() or 0))
	local hpCol = hp <= 25
		and (T.healthLow or Color(255, 50, 50, 255))
		or (T.health or Color(255, 220, 60, 255))

	draw.SimpleTextOutlined(tostring(hp), fontV, 36, h - 52, hpCol,
		TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 2, outline)
	draw.SimpleTextOutlined("HEALTH", fontL, 36, h - 28, muted,
		TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 1, outline)

	if arm > 0 then
		draw.SimpleTextOutlined(tostring(arm), fontV, 170, h - 52, T.armor or Color(90, 170, 255, 255),
			TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 2, outline)
		draw.SimpleTextOutlined("ARMOR", fontL, 170, h - 28, muted,
			TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 1, outline)
	end

	local wep = ply:GetActiveWeapon()
	if IsValid(wep) then
		local clip = wep:Clip1()
		local ammo = -1
		local at = wep:GetPrimaryAmmoType()
		if isnumber(at) and at >= 0 then ammo = ply:GetAmmoCount(at) end
		local line
		if clip >= 0 and ammo >= 0 then
			line = string.format("%d  |  %d", clip, ammo)
		elseif clip >= 0 then
			line = tostring(clip)
		elseif ammo >= 0 then
			line = tostring(ammo)
		end
		if line then
			draw.SimpleTextOutlined(line, fontV, w - 36, h - 52, T.ammo or T.text or color_white,
				TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM, 2, outline)
			draw.SimpleTextOutlined("AMMO", fontL, w - 36, h - 28, muted,
				TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM, 1, outline)
		end
	end
end

local function CaptureHudRT(w, h, pScale)
	render.PushRenderTarget(rt)
	render.OverrideAlphaWriteEnable(true, true)
	render.Clear(0, 0, 0, 0, true, true)

	local oldX, oldY, oldW, oldH = 0, 0, ScrW(), ScrH()
	if render.GetViewPort then
		oldX, oldY, oldW, oldH = render.GetViewPort()
	end
	render.SetViewPort(0, 0, w, h)

	cam.Start2D()

	local bgA = math.Clamp(CVFloat("vrmod_hudtestalpha", 0), 0, 255)
	if bgA > 0 then
		surface.SetDrawColor(0, 0, 0, bgA)
		surface.DrawRect(0, 0, w, h)
	end

	g_VR._renderingHudRT = true
	-- Optional engine HUD only if explicitly enabled (avoids loose desktop HUD copy)
	if cv_engine:GetBool() then
		pcall(render.RenderHUD, 0, 0, w, h)
	end
	pcall(PaintVitals, w, h)
	-- Optional aim reticle: weapon muzzle / hand aim projected onto plate
	pcall(PaintAimCrosshair, w, h, pScale or plateScale)
	g_VR._renderingHudRT = false

	cam.End2D()

	render.SetViewPort(oldX, oldY, oldW, oldH)
	render.OverrideAlphaWriteEnable(false)
	render.PopRenderTarget()
end

local function DrawHudMesh()
	if not hudBound or not hudMesh or not mat or mat:IsError() then return end
	if not g_VR or not g_VR.active then return end
	if not g_VR.tracking or not g_VR.tracking.hmd then return end
	if not CVBool("vrmod_hud", true) then return end

	mat:SetTexture("$basetexture", rt)
	mat:SetInt("$translucent", 1)
	mat:SetInt("$additive", 0)
	render.SetMaterial(mat)
	cam.PushModelMatrix(mtx)
	render.DepthRange(0, 0.01)
	hudMesh:Draw()
	render.DepthRange(0, 1)
	cam.PopModelMatrix()
end

local function Unbind()
	hook.Remove("VRMod_PreRender", "vrmod_hud_capture")
	hook.Remove("VRMod_PreRender", "hud")
	hook.Remove("VRMod_PreRender", "vrmod_hud_rt")
	hook.Remove("PostDrawTranslucentRenderables", "vrmod_hud_draw")
	hook.Remove("HUDShouldDraw", "vrmod_hud")
	hook.Remove("HUDShouldDraw", "vrmod_hud_bl")
	-- No menu-system wrap anymore (single plate only)
	hudBound = false
end

local function Bind()
	Unbind()
	if not g_VR or not g_VR.active then return end
	if not CVBool("vrmod_hud", true) then return end

	if vrScrW:GetInt() < 64 then vrScrW:SetInt(math.max(ScrW(), 1280)) end
	if vrScrH:GetInt() < 64 then vrScrH:SetInt(math.max(ScrH(), 720)) end

	local w, h = HudRes()
	if w ~= rtW or h ~= rtH or not rt then
		rtW, rtH = w, h
		rt = GetRenderTarget("vrmod_hud_paint", rtW, rtH, false)
	end
	if mat and not mat:IsError() then
		mat:SetTexture("$basetexture", rt)
	end

	local scale = math.Clamp(CVFloat("vrmod_hudscale", 0.05), 0.02, 0.12)
	plateScale = scale
	local curve = CVFloat("vrmod_hudcurve", 60)
	local meshName = string.format("%.4f_%.1f_%d_%d", scale, curve, w, h)

	local build = Matrix()
	build:Translate(Vector(0, 0, h * scale / 2))
	build:Rotate(Angle(0, -90, -90))
	if not hudMeshes[meshName] then
		hudMeshes[meshName] = CurvedPlane(w * scale, h * scale, 10, curve, build)
	end
	hudMesh = hudMeshes[meshName]

	local blacklist = {}
	for _, v in ipairs(string.Explode(",", CVString("vrmod_hudblacklist", ""))) do
		if #v > 0 then blacklist[v] = true end
	end
	if next(blacklist) then
		hook.Add("HUDShouldDraw", "vrmod_hud_bl", function(name)
			if blacklist[name] then return false end
		end)
	end

	-- Capture once per frame (left eye)
	hook.Add("VRMod_PreRender", "vrmod_hud_capture", function(eye)
		if eye == "right" then return end
		if not g_VR.active or not CVBool("vrmod_hud", true) then return end
		if not g_VR.tracking or not g_VR.tracking.hmd then return end

		hook.Call("VRMod_PreRenderHUD", nil, eye)

		local rw, rh = HudRes()
		if rw ~= rtW or rh ~= rtH then
			rtW, rtH = rw, rh
			rt = GetRenderTarget("vrmod_hud_paint", rtW, rtH, false)
			if mat then mat:SetTexture("$basetexture", rt) end
		end

		pcall(CaptureHudRT, rtW, rtH, plateScale)
		captureN = captureN + 1

		mtx:Identity()
		mtx:Translate(g_VR.tracking.hmd.pos + g_VR.tracking.hmd.ang:Forward() * CVFloat("vrmod_huddistance", 60))
		mtx:Rotate(g_VR.tracking.hmd.ang)

		hook.Call("VRMod_PostRenderHUD", nil, eye)
	end)

	-- SINGLE draw path (both eyes) — no menu-system wrap (that stacked a second plate)
	hook.Add("PostDrawTranslucentRenderables", "vrmod_hud_draw", function(depth, sky)
		if depth or sky then return end
		if not g_VR or not g_VR.active or not g_VR.stereoEye then return end
		pcall(DrawHudMesh)
	end, 50)

	hudBound = true
	if vrmod.logger then
		vrmod.logger.Info("[vrmod_hud] single-plate vitals rt=%dx%d engine=%s", rtW, rtH, cv_engine:GetBool())
	end
end

local function toboolStrict(val)
	if val == true or val == 1 then return true end
	if val == false or val == 0 or val == nil then return false end
	local s = tostring(val):lower()
	if s == "0" or s == "false" or s == "no" or s == "" then return false end
	return true
end

vrmod.AddCallbackedConvar("vrmod_hud", nil, "1", FCVAR_ARCHIVE, "Draw VR world HUD", nil, nil, toboolStrict, function()
	Bind()
end)
vrmod.AddCallbackedConvar("vrmod_hudblacklist", nil, "", FCVAR_ARCHIVE, nil, nil, nil, nil, Bind)
vrmod.AddCallbackedConvar("vrmod_hudcurve", nil, "60", FCVAR_ARCHIVE, nil, nil, nil, tonumber, Bind)
vrmod.AddCallbackedConvar("vrmod_hudscale", nil, "0.05", FCVAR_ARCHIVE, nil, nil, nil, tonumber, Bind)
vrmod.AddCallbackedConvar("vrmod_huddistance", nil, "60", FCVAR_ARCHIVE, nil, nil, nil, tonumber)
vrmod.AddCallbackedConvar("vrmod_hudtestalpha", nil, "0", FCVAR_ARCHIVE, "Dim plate 0-255 (0=clear)", nil, nil, tonumber)

function vrmod.RefreshHUD()
	Bind()
end

function vrmod.IsHUDActive()
	return hudBound and CVBool("vrmod_hud", true)
end

hook.Add("VRMod_Start", "vrmod_hud", function(ply)
	if ply ~= LocalPlayer() then return end
	timer.Simple(0, function() if g_VR and g_VR.active then Bind() end end)
	timer.Simple(0.35, function() if g_VR and g_VR.active and CVBool("vrmod_hud", true) then Bind() end end)
end)

hook.Add("VRMod_Exit", "vrmod_hud", function(ply)
	if ply ~= LocalPlayer() then return end
	Unbind()
end)

concommand.Add("vrmod_hud_status", function()
	vrmod.logger.Info(
		"[vrmod_hud] bound=%s captures=%s rt=%sx%s engine=%s single_draw=1",
		hudBound, captureN, rtW, rtH, cv_engine:GetBool()
	)
end)

concommand.Add("vrmod_hud_rebind", function()
	RunConsoleCommand("vrmod_hud", "1")
	local c = GetConVar("vrmod_hud")
	if c then pcall(function() c:SetInt(1) end) end
	-- Force off engine HUD clone unless user wants it
	if not cv_engine:GetBool() then cv_engine:SetInt(0) end
	Bind()
	vrmod.logger.Info("[vrmod_hud] rebound — one plate, vitals only")
end)

concommand.Add("vrmod_hud_on", function()
	RunConsoleCommand("vrmod_hud", "1")
	local c = GetConVar("vrmod_hud")
	if c then pcall(function() c:SetInt(1) end) end
	Bind()
end)
