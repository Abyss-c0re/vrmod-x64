if SERVER then return end

-- =============================================================================
-- VR HUD — Cube seamless Real ↔ GMod
-- Law: HUD is overlay energy on the Real. It must never occlude with a black plate.
-- Root: UnlitGeneric samples black RGB from the HUD RT as an opaque world mesh.
-- Fix: additive composite (black adds nothing) + alpha RT canvas + keep HUD ON.
-- mat_queue_mode: untouched (session law).
-- =============================================================================

local vrScrH = CreateClientConVar("vrmod_ScrH_hud", ScrH(), true, FCVAR_ARCHIVE)
local vrScrW = CreateClientConVar("vrmod_ScrW_hud", ScrW(), true, FCVAR_ARCHIVE)

-- Source IMAGE_FORMAT enum (do not rely on globals existing)
local IMG_BGRA8888 = (IMAGE_FORMAT_BGRA8888 ~= nil and IMAGE_FORMAT_BGRA8888) or 12
local IMG_RGBA8888 = (IMAGE_FORMAT_RGBA8888 ~= nil and IMAGE_FORMAT_RGBA8888) or 0

local function CurvedPlane(w, h, segments, degrees, matrix)
	matrix = matrix or Matrix()
	degrees = math.rad(degrees)
	local mesh = Mesh()
	local verts = {}
	local startAng = (math.pi - degrees) / 2
	local segLen = 0.5 * math.tan(degrees / segments)
	local scale = w / (segLen * segments)
	local zoffset = math.sin(startAng) * 0.5 * scale
	for i = 0, segments - 1 do
		local fraction = i / segments
		local nextFraction = (i + 1) / segments
		local ang1 = startAng + fraction * degrees
		local ang2 = startAng + nextFraction * degrees
		local x1 = math.cos(ang1) * -0.5 * scale
		local x2 = math.cos(ang2) * -0.5 * scale
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

local function CreateHudRT()
	local w = math.max(64, vrScrW:GetInt())
	local h = math.max(64, vrScrH:GetInt())
	if isfunction(GetRenderTargetEx) then
		local sizeMode = RT_SIZE_NO_CHANGE or RT_SIZE_DEFAULT or 0
		local depthMode = MATERIAL_RT_DEPTH_NONE or 0
		local texFlags = bit.bor(TEXTUREFLAGS_CLAMPS or 4, TEXTUREFLAGS_CLAMPT or 8)
		for _, fmt in ipairs({ IMG_BGRA8888, IMG_RGBA8888 }) do
			local ok, rtEx = pcall(GetRenderTargetEx, "vrmod_hud_rt", w, h, sizeMode, depthMode, texFlags, 0, fmt)
			if ok and rtEx then return rtEx end
		end
	end
	return GetRenderTarget("vrmod_hud", w, h, false)
end

local function CreateHudMaterial(rt)
	-- $additive: black RT pixels add ZERO light → no floating black slab.
	-- Colored/white HUD paint still composites onto the Real. HUD stays enabled.
	local mat = CreateMaterial("vrmod_hud_add", "UnlitGeneric", {
		["$basetexture"] = rt:GetName(),
		["$additive"] = 1,
		["$vertexcolor"] = 1,
		["$vertexalpha"] = 1,
		["$nolod"] = 1,
		["$nocull"] = 1,
		["$ignorez"] = 1,
	})
	if mat and not mat:IsError() then
		mat:SetTexture("$basetexture", rt)
		mat:SetInt("$additive", 1)
	end
	return mat
end

local rt = CreateHudRT()
local mat = CreateHudMaterial(rt)
local hudMeshes = {}
local hudMesh = nil
local orig = nil
local convars, convarValues = vrmod.GetConvars()

local function RemoveHUD()
	hook.Remove("VRMod_PreRender", "hud")
	hook.Remove("HUDShouldDraw", "vrmod_hud")
	if orig then
		VRUtilRenderMenuSystem = orig
	end
end

local function AddHUD()
	RemoveHUD()
	if not g_VR.active or not convarValues.vrmod_hud then return end

	rt = CreateHudRT()
	mat = CreateHudMaterial(rt)
	if not mat or mat:IsError() then return end

	local mtx = Matrix()
	mtx:Translate(Vector(0, 0, vrScrH:GetInt() * convarValues.vrmod_hudscale / 2))
	mtx:Rotate(Angle(0, -90, -90))
	local meshName = tostring(convarValues.vrmod_hudscale) .. "_" .. tostring(convarValues.vrmod_hudcurve)
	hudMeshes[meshName] = hudMeshes[meshName]
		or CurvedPlane(vrScrW:GetInt() * convarValues.vrmod_hudscale, vrScrH:GetInt() * convarValues.vrmod_hudscale, 10, convarValues.vrmod_hudcurve, mtx)
	hudMesh = hudMeshes[meshName]

	local blacklist = {}
	for _, v in ipairs(string.Explode(",", convarValues.vrmod_hudblacklist or "")) do
		if #v > 0 then blacklist[v] = true end
	end
	if next(blacklist) then
		hook.Add("HUDShouldDraw", "vrmod_hud", function(name)
			if blacklist[name] then return false end
		end)
	end

	hook.Add("VRMod_PreRender", "hud", function(eye)
		if not g_VR.threePoints then return end
		if eye == "right" then return end
		if not g_VR.tracking or not g_VR.tracking.hmd then return end

		hook.Call("VRMod_PreRenderHUD", nil, eye)

		mat:SetTexture("$basetexture", rt)

		local w, h = vrScrW:GetInt(), vrScrH:GetInt()
		render.PushRenderTarget(rt)
		render.OverrideAlphaWriteEnable(true, true)
		-- Black clear: with $additive this is "no light", not an occluder of the Real
		render.Clear(0, 0, 0, 255, true, true)

		-- Optional dim plate (additive grey). Default 0 = pure transparent overlay.
		local bgA = math.Clamp(tonumber(convarValues.vrmod_hudtestalpha) or 0, 0, 255)
		if bgA > 0 then
			cam.Start2D()
			local g = math.floor(bgA * 0.35)
			surface.SetDrawColor(g, g, g, 255)
			surface.DrawRect(0, 0, w, h)
			cam.End2D()
		end

		g_VR._renderingHudRT = true
		render.RenderHUD(0, 0, w, h)
		g_VR._renderingHudRT = false

		hook.Call("VRMod_PostRenderHUD", nil, eye)
		render.OverrideAlphaWriteEnable(false)
		render.PopRenderTarget()

		mtx:Identity()
		mtx:Translate(g_VR.tracking.hmd.pos + g_VR.tracking.hmd.ang:Forward() * convarValues.vrmod_huddistance)
		mtx:Rotate(g_VR.tracking.hmd.ang)
	end)

	orig = orig or VRUtilRenderMenuSystem
	VRUtilRenderMenuSystem = function()
		if hudMesh and mat and not mat:IsError() and g_VR.tracking and g_VR.tracking.hmd then
			render.SetMaterial(mat)
			cam.PushModelMatrix(mtx)
			render.DepthRange(0, 0.01)
			hudMesh:Draw()
			render.DepthRange(0, 1)
			cam.PopModelMatrix()
		end
		if orig then orig() end
	end
end

vrmod.AddCallbackedConvar("vrmod_hud", nil, 1, nil, nil, nil, nil, tobool, AddHUD)
vrmod.AddCallbackedConvar("vrmod_hudblacklist", nil, "", nil, nil, nil, nil, nil, AddHUD)
vrmod.AddCallbackedConvar("vrmod_hudcurve", nil, "60", nil, nil, nil, nil, tonumber, AddHUD)
vrmod.AddCallbackedConvar("vrmod_hudscale", nil, "0.05", nil, nil, nil, nil, tonumber, AddHUD)
vrmod.AddCallbackedConvar("vrmod_huddistance", nil, "60", nil, nil, nil, nil, tonumber)
vrmod.AddCallbackedConvar("vrmod_hudtestalpha", nil, "0", nil, nil, nil, nil, tonumber)

hook.Add("VRMod_Start", "hud", function(ply)
	if ply ~= LocalPlayer() then return end
	AddHUD()
end)

hook.Add("VRMod_Exit", "hud", function(ply)
	if ply ~= LocalPlayer() then return end
	RemoveHUD()
end)
