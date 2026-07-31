if SERVER then return end

-- =============================================================================
-- VR HUD
-- Capture: VRMod_PreRender left eye → RT
-- Draw: PostDrawTranslucent while g_VR.stereoEye is set (inside each eye RenderView)
-- Material: translucent UnlitGeneric (additive made HUD invisible)
-- =============================================================================

local vrScrH = CreateClientConVar("vrmod_ScrH_hud", tostring(ScrH()), true, FCVAR_ARCHIVE)
local vrScrW = CreateClientConVar("vrmod_ScrW_hud", tostring(ScrW()), true, FCVAR_ARCHIVE)

local function CurvedPlane(w, h, segments, degrees, matrix)
	matrix = matrix or Matrix()
	degrees = math.rad(degrees)
	local mesh = Mesh()
	local verts = {}
	local startAng = (math.pi - degrees) / 2
	local segLen = 0.5 * math.tan(degrees / math.max(segments, 1))
	local scale = w / math.max(segLen * segments, 0.001)
	local zoffset = math.sin(startAng) * 0.5 * scale
	for i = 0, segments - 1 do
		local fraction = i / segments
		local nextFraction = (i + 1) / segments
		local ang1 = startAng + fraction * degrees
		local ang2 = startAng + nextFraction * degrees
		local x1, x2 = math.cos(ang1) * -0.5 * scale, math.cos(ang2) * -0.5 * scale
		local z1 = math.sin(ang1) * 0.5 * scale - zoffset
		local z2 = math.sin(ang2) * 0.5 * scale - zoffset
		verts[#verts + 1] = { pos = matrix * Vector(x1, 0, z1), u = fraction, v = 0 }
		verts[#verts + 1] = { pos = matrix * Vector(x2, 0, z2), u = nextFraction, v = 0 }
		verts[#verts + 1] = { pos = matrix * Vector(x2, h, z2), u = nextFraction, v = 1 }
		verts[#verts + 1] = { pos = matrix * Vector(x2, h, z2), u = nextFraction, v = 1 }
		verts[#verts + 1] = { pos = matrix * Vector(x1, h, z1), u = fraction, v = 1 }
		verts[#verts + 1] = { pos = matrix * Vector(x1, 0, z1), u = fraction, v = 0 }
	end
	mesh:BuildFromTriangles(verts)
	return mesh
end

local rtW = math.max(64, vrScrW:GetInt())
local rtH = math.max(64, vrScrH:GetInt())
local rt = GetRenderTarget("vrmod_hud", rtW, rtH, false)
local mat = CreateMaterial("vrmod_hud_mesh_v3", "UnlitGeneric", {
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

local function DrawHudMesh()
	if not hudBound or not hudMesh or not mat or mat:IsError() then return end
	if not g_VR or not g_VR.active then return end
	if not g_VR.tracking or not g_VR.tracking.hmd then return end
	if not CVBool("vrmod_hud", true) then return end

	mat:SetTexture("$basetexture", rt)
	render.SetMaterial(mat)
	cam.PushModelMatrix(mtx)
	render.DepthRange(0, 0.001)
	hudMesh:Draw()
	render.DepthRange(0, 1)
	cam.PopModelMatrix()
end

local function Unbind()
	hook.Remove("VRMod_PreRender", "vrmod_hud_capture")
	hook.Remove("PostDrawTranslucentRenderables", "vrmod_hud_draw")
	hook.Remove("HUDShouldDraw", "vrmod_hud_bl")
	hudBound = false
end

local function Bind()
	Unbind()
	if not g_VR or not g_VR.active then return end
	if not CVBool("vrmod_hud", true) then return end

	local w = math.max(64, vrScrW:GetInt())
	local h = math.max(64, vrScrH:GetInt())
	if w ~= rtW or h ~= rtH then
		rtW, rtH = w, h
		rt = GetRenderTarget("vrmod_hud", rtW, rtH, false)
		if mat and not mat:IsError() then mat:SetTexture("$basetexture", rt) end
	end

	local scale = CVFloat("vrmod_hudscale", 0.05)
	local uiS = (vrmod.GetUIScale and vrmod.GetUIScale()) or 1
	scale = scale * uiS
	local curve = CVFloat("vrmod_hudcurve", 60)
	local meshName = string.format("%.5f_%.2f_%d_%d", scale, curve, w, h)

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

	-- Capture HUD pixels once per frame (left eye only)
	hook.Add("VRMod_PreRender", "vrmod_hud_capture", function(eye)
		if eye == "right" then return end
		if not g_VR.active or not CVBool("vrmod_hud", true) then return end
		if not g_VR.tracking or not g_VR.tracking.hmd then return end

		hook.Call("VRMod_PreRenderHUD", nil, eye)

		local rw, rh = math.max(64, vrScrW:GetInt()), math.max(64, vrScrH:GetInt())
		render.PushRenderTarget(rt)
		render.OverrideAlphaWriteEnable(true, true)
		local bgA = math.Clamp(CVFloat("vrmod_hudtestalpha", 0), 0, 255)
		render.Clear(0, 0, 0, bgA, true, true)
		g_VR._renderingHudRT = true
		render.RenderHUD(0, 0, rw, rh)
		g_VR._renderingHudRT = false
		hook.Call("VRMod_PostRenderHUD", nil, eye)
		render.OverrideAlphaWriteEnable(false)
		render.PopRenderTarget()

		-- HMD-relative placement for this frame
		mtx:Identity()
		mtx:Translate(g_VR.tracking.hmd.pos + g_VR.tracking.hmd.ang:Forward() * CVFloat("vrmod_huddistance", 60))
		mtx:Rotate(g_VR.tracking.hmd.ang)
	end)

	-- Draw inside each eye's RenderView (stereoEye is set by cl_vrmod during SafeRenderView)
	hook.Add("PostDrawTranslucentRenderables", "vrmod_hud_draw", function(depth, sky)
		if depth or sky then return end
		if not g_VR or not g_VR.active then return end
		-- Only while rendering a VR stereo eye into g_VR.rt
		if not g_VR.stereoEye then return end
		DrawHudMesh()
	end)

	hudBound = true
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
vrmod.AddCallbackedConvar("vrmod_hudtestalpha", nil, "0", FCVAR_ARCHIVE, nil, nil, nil, tonumber)

function vrmod.RefreshHUD()
	Bind()
end

function vrmod.IsHUDActive()
	return hudBound and CVBool("vrmod_hud", true)
end

hook.Add("VRMod_Start", "vrmod_hud", function(ply)
	if ply ~= LocalPlayer() then return end
	-- Force HUD on at session start if cvar missing/off from broken toggles
	local c = GetConVar("vrmod_hud")
	if c and not c:GetBool() then
		-- leave user off choice alone
	end
	timer.Simple(0, function() if g_VR and g_VR.active then Bind() end end)
	timer.Simple(0.25, function() if g_VR and g_VR.active and CVBool("vrmod_hud", true) then Bind() end end)
	timer.Simple(1.0, function() if g_VR and g_VR.active and CVBool("vrmod_hud", true) then Bind() end end)
end)

hook.Add("VRMod_Exit", "vrmod_hud", function(ply)
	if ply ~= LocalPlayer() then return end
	Unbind()
end)

concommand.Add("vrmod_hud_status", function()
	local c = GetConVar("vrmod_hud")
	print(string.format(
		"[vrmod_hud] cvar=%s bound=%s stereoEye=%s mesh=%s mat=%s scale=%.3f dist=%.1f",
		c and tostring(c:GetBool()) or "nil",
		tostring(hudBound),
		tostring(g_VR and g_VR.stereoEye),
		hudMesh and "ok" or "nil",
		mat and (mat:IsError() and "ERR" or "ok") or "nil",
		CVFloat("vrmod_hudscale", 0.05),
		CVFloat("vrmod_huddistance", 60)
	))
end)

concommand.Add("vrmod_hud_rebind", function()
	RunConsoleCommand("vrmod_hud", "1")
	Bind()
	print("[vrmod_hud] forced on + rebound")
end)

concommand.Add("vrmod_hud_on", function()
	RunConsoleCommand("vrmod_hud", "1")
	local c = GetConVar("vrmod_hud")
	if c then pcall(function() c:SetInt(1) end) end
	Bind()
end)
