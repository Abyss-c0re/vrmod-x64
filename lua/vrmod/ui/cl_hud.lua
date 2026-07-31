if SERVER then return end

-- =============================================================================
-- VR HUD — project vitals (HP / armor / ammo). No center crosshair in VR.
--
-- Mesh-only empty plate = capture failed. render.RenderHUD often no-ops inside
-- nested stereo RTs. Law:
--   1) PushRT → SetViewPort → Start2D → clear → paint essentials ALWAYS
--   2) Also try RenderHUD + HUDPaint (sandbox / SWEP chrome when engine allows)
--   3) Draw via VRUtilRenderMenuSystem wrap + stereoEye backup
--   4) Translucent mat: painted pixels opaque; empty alpha 0 = no black slab
-- mat_queue_mode: untouched
-- =============================================================================

local vrScrH = CreateClientConVar("vrmod_ScrH_hud", "0", true, FCVAR_ARCHIVE)
local vrScrW = CreateClientConVar("vrmod_ScrW_hud", "0", true, FCVAR_ARCHIVE)

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
local mat = CreateMaterial("vrmod_hud_mesh_paint_v1", "UnlitGeneric", {
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
local origMenuSystem = nil
local wrapped = false
local hudBound = false
local captureN = 0
local _, convarValues = vrmod.GetConvars()

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

--- Crimson Cube vitals (no center crosshair — VR aims with hands/laser)
local function PaintVitals(w, h)
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	-- World HUD stays neutral; Theme skins menus only
	local outline = Color(0, 0, 0, 220)
	local fontV = (vrmod.cube and vrmod.cube.Font and vrmod.cube.Font("CubeHuge")) or "DermaLarge"
	local fontL = (vrmod.cube and vrmod.cube.Font and vrmod.cube.Font("CubeSmall")) or "DermaDefaultBold"

	local hp = math.max(0, math.floor(ply:Health() or 0))
	local arm = math.max(0, math.floor(ply:Armor() or 0))
	local hpCol = hp <= 25 and Color(255, 50, 50, 255) or Color(255, 220, 60, 255)

	draw.SimpleTextOutlined(tostring(hp), fontV, 36, h - 52, hpCol,
		TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 2, outline)
	draw.SimpleTextOutlined("HEALTH", fontL, 36, h - 28, T.muted or Color(200, 150, 165, 230),
		TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 1, outline)

	if arm > 0 then
		draw.SimpleTextOutlined(tostring(arm), fontV, 170, h - 52, Color(90, 170, 255, 255),
			TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 2, outline)
		draw.SimpleTextOutlined("ARMOR", fontL, 170, h - 28, Color(170, 200, 255, 255),
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
			draw.SimpleTextOutlined(line, fontV, w - 36, h - 52, color_white,
				TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM, 2, outline)
			draw.SimpleTextOutlined("AMMO", fontL, w - 36, h - 28, Color(220, 220, 220, 255),
				TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM, 1, outline)
		end
	end
end

local function CaptureHudRT(w, h)
	render.PushRenderTarget(rt)
	render.OverrideAlphaWriteEnable(true, true)

	-- Transparent wipe (no black slab). Painted text uses a=255 so it shows.
	render.Clear(0, 0, 0, 0, true, true)

	local oldX, oldY, oldW, oldH = 0, 0, ScrW(), ScrH()
	if render.GetViewPort then
		oldX, oldY, oldW, oldH = render.GetViewPort()
	end
	render.SetViewPort(0, 0, w, h)

	cam.Start2D()

	-- Optional dim plate for readability
	local bgA = math.Clamp(CVFloat("vrmod_hudtestalpha", 0), 0, 255)
	if bgA > 0 then
		surface.SetDrawColor(0, 0, 0, bgA)
		surface.DrawRect(0, 0, w, h)
	end

	g_VR._renderingHudRT = true
	-- Engine / SWEP HUD when it works
	pcall(render.RenderHUD, 0, 0, w, h)
	pcall(function() hook.Run("HUDPaint") end)
	-- Always project vitals (user-visible guarantee)
	pcall(PaintVitals, w, h)
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
	hook.Remove("PostDrawTranslucentRenderables", "vrmod_hud_draw")
	hook.Remove("HUDShouldDraw", "vrmod_hud")
	if wrapped and origMenuSystem then
		VRUtilRenderMenuSystem = origMenuSystem
		wrapped = false
	end
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

	local scale = CVFloat("vrmod_hudscale", 0.05)
	-- Do NOT multiply global UI scale into HUD plate (that shrank readable vitals)
	scale = math.Clamp(scale, 0.02, 0.12)
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
		hook.Add("HUDShouldDraw", "vrmod_hud", function(name)
			if blacklist[name] then return false end
		end)
	end

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

		pcall(CaptureHudRT, rtW, rtH)
		captureN = captureN + 1

		mtx:Identity()
		mtx:Translate(g_VR.tracking.hmd.pos + g_VR.tracking.hmd.ang:Forward() * CVFloat("vrmod_huddistance", 60))
		mtx:Rotate(g_VR.tracking.hmd.ang)
		g_VR._hudDrawnEye = nil

		hook.Call("VRMod_PostRenderHUD", nil, eye)
	end)

	-- Path A: each stereo eye (cl_vrmod calls this)
	if isfunction(VRUtilRenderMenuSystem) then
		if not wrapped then
			origMenuSystem = VRUtilRenderMenuSystem
			wrapped = true
		end
		local base = origMenuSystem
		VRUtilRenderMenuSystem = function()
			pcall(function()
				DrawHudMesh()
				if g_VR then g_VR._hudDrawnEye = g_VR.stereoEye end
			end)
			if base then base() end
		end
	end

	-- Path B: backup
	hook.Add("PostDrawTranslucentRenderables", "vrmod_hud_draw", function(depth, sky)
		if depth or sky then return end
		if not g_VR or not g_VR.active or not g_VR.stereoEye then return end
		if g_VR._hudDrawnEye == g_VR.stereoEye then return end
		pcall(DrawHudMesh)
	end, 100)

	hudBound = true
	if vrmod.logger then
		vrmod.logger.Info("[vrmod_hud] bound vitals paint rt=%dx%d", rtW, rtH)
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
vrmod.AddCallbackedConvar("vrmod_hudtestalpha", nil, "0", FCVAR_ARCHIVE, "Dim plate 0-255 (0=transparent)", nil, nil, tonumber)

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
	origMenuSystem = nil
end)

concommand.Add("vrmod_hud_status", function()
	vrmod.logger.Info(
		"[vrmod_hud] bound=%s captures=%s rt=%sx%s mesh=%s mat=%s dist=%.0f",
		hudBound, captureN, rtW, rtH,
		hudMesh and "ok" or "nil",
		mat and (mat:IsError() and "ERR" or "ok") or "nil",
		CVFloat("vrmod_huddistance", 60)
	)
end)

concommand.Add("vrmod_hud_rebind", function()
	RunConsoleCommand("vrmod_hud", "1")
	local c = GetConVar("vrmod_hud")
	if c then pcall(function() c:SetInt(1) end) end
	Bind()
	vrmod.logger.Info("[vrmod_hud] rebound — vitals always painted")
end)

concommand.Add("vrmod_hud_on", function()
	RunConsoleCommand("vrmod_hud", "1")
	local c = GetConVar("vrmod_hud")
	if c then pcall(function() c:SetInt(1) end) end
	Bind()
end)
