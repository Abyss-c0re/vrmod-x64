if SERVER then return end

-- =============================================================================
-- VR HUD — curved world overlay
--
-- Clear each frame to black (additive mat: black adds no light → no black slab).
-- Do NOT alpha-0 wipe with OverrideBlend (that killed RenderHUD paint / #349 over-fix).
-- Toggle: vrmod_hud via ConVar:SetBool → callback → AddHUD/RemoveHUD.
-- =============================================================================

local vrScrH = CreateClientConVar("vrmod_ScrH_hud", tostring(ScrH()), true, FCVAR_ARCHIVE)
local vrScrW = CreateClientConVar("vrmod_ScrW_hud", tostring(ScrW()), true, FCVAR_ARCHIVE)

local IMG_BGRA8888 = (IMAGE_FORMAT_BGRA8888 ~= nil and IMAGE_FORMAT_BGRA8888) or 12
local IMG_RGBA8888 = (IMAGE_FORMAT_RGBA8888 ~= nil and IMAGE_FORMAT_RGBA8888) or 0

local function CurvedPlane(w, h, segments, degrees, matrix)
	matrix = matrix or Matrix()
	degrees = math.rad(degrees)
	local mesh = Mesh()
	local verts = {}
	local startAng = (math.pi - degrees) / 2
	local segLen = 0.5 * math.tan(degrees / segments)
	local scale = w / math.max(segLen * segments, 0.001)
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
local menuSystemBeforeHud = nil
local hudActive = false
local _, convarValues = vrmod.GetConvars()

local function CVarFloat(name, default)
	local cv = GetConVar(name)
	if cv then return cv:GetFloat() end
	local v = convarValues and convarValues[name]
	if v ~= nil then return tonumber(v) or default end
	return default
end

local function CVarString(name, default)
	local cv = GetConVar(name)
	if cv then return cv:GetString() end
	local v = convarValues and convarValues[name]
	if v ~= nil then return tostring(v) end
	return default
end

local function HudWanted()
	local cv = GetConVar("vrmod_hud")
	if cv then return cv:GetBool() end
	return convarValues and convarValues.vrmod_hud and true or false
end

local function RemoveHUD()
	hook.Remove("VRMod_PreRender", "vrmod_hud_rt")
	hook.Remove("HUDShouldDraw", "vrmod_hud")
	if menuSystemBeforeHud and VRUtilRenderMenuSystem ~= menuSystemBeforeHud then
		-- Only unwrap if we still own the wrapper
		VRUtilRenderMenuSystem = menuSystemBeforeHud
	end
	hudActive = false
end

local function AddHUD()
	RemoveHUD()
	if not g_VR or not g_VR.active then return end
	if not HudWanted() then return end

	rt = CreateHudRT()
	mat = CreateHudMaterial(rt)
	if not mat or mat:IsError() then
		if vrmod.logger then vrmod.logger.Warn("VR HUD: material failed") end
		return
	end

	local scale = CVarFloat("vrmod_hudscale", 0.05)
	local curve = CVarFloat("vrmod_hudcurve", 60)
	local dist = CVarFloat("vrmod_huddistance", 60)
	local scrW = math.max(64, vrScrW:GetInt())
	local scrH = math.max(64, vrScrH:GetInt())

	local mtx = Matrix()
	mtx:Translate(Vector(0, 0, scrH * scale / 2))
	mtx:Rotate(Angle(0, -90, -90))
	local meshName = string.format("%.4f_%.2f_%d_%d", scale, curve, scrW, scrH)
	if not hudMeshes[meshName] then
		hudMeshes[meshName] = CurvedPlane(scrW * scale, scrH * scale, 10, curve, mtx)
	end
	hudMesh = hudMeshes[meshName]

	local blacklist = {}
	for _, v in ipairs(string.Explode(",", CVarString("vrmod_hudblacklist", ""))) do
		if #v > 0 then blacklist[v] = true end
	end
	if next(blacklist) then
		hook.Add("HUDShouldDraw", "vrmod_hud", function(name)
			if blacklist[name] then return false end
		end)
	end

	-- Rasterize once per stereo pair (left eye only)
	hook.Add("VRMod_PreRender", "vrmod_hud_rt", function(eye)
		if not g_VR.active then return end
		if eye == "right" then return end
		if not g_VR.tracking or not g_VR.tracking.hmd then return end
		if not HudWanted() then return end

		hook.Call("VRMod_PreRenderHUD", nil, eye)

		if mat and not mat:IsError() then
			mat:SetTexture("$basetexture", rt)
			mat:SetInt("$additive", 1)
		end

		local w, h = math.max(64, vrScrW:GetInt()), math.max(64, vrScrH:GetInt())
		render.PushRenderTarget(rt)
		render.OverrideAlphaWriteEnable(true, true)
		-- Proven clear: black plate + full alpha. Additive mat → black is invisible in world.
		-- Clears every frame so hitmarkers cannot pile (real fix for #349 ghosting).
		local bgA = math.Clamp(CVarFloat("vrmod_hudtestalpha", 0), 0, 255)
		render.Clear(0, 0, 0, bgA > 0 and 255 or 255, true, true)
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

		-- Place mesh in front of HMD for this frame's draw
		mtx:Identity()
		mtx:Translate(g_VR.tracking.hmd.pos + g_VR.tracking.hmd.ang:Forward() * CVarFloat("vrmod_huddistance", 60))
		mtx:Rotate(g_VR.tracking.hmd.ang)
	end)

	if not menuSystemBeforeHud then
		menuSystemBeforeHud = VRUtilRenderMenuSystem
	end
	local base = menuSystemBeforeHud
	VRUtilRenderMenuSystem = function()
		if hudMesh and mat and not mat:IsError() and g_VR.tracking and g_VR.tracking.hmd and HudWanted() then
			render.SetMaterial(mat)
			cam.PushModelMatrix(mtx)
			render.DepthRange(0, 0.01)
			hudMesh:Draw()
			render.DepthRange(0, 1)
			cam.PopModelMatrix()
		end
		if base then base() end
	end

	hudActive = true
end

local function toboolStrict(val)
	if val == true or val == 1 then return true end
	if val == false or val == 0 or val == nil then return false end
	local s = tostring(val):lower()
	if s == "0" or s == "false" or s == "no" or s == "" then return false end
	return true
end

vrmod.AddCallbackedConvar("vrmod_hud", nil, "1", FCVAR_ARCHIVE, "Draw VR world HUD", nil, nil, toboolStrict, function()
	AddHUD()
end)
vrmod.AddCallbackedConvar("vrmod_hudblacklist", nil, "", FCVAR_ARCHIVE, nil, nil, nil, nil, AddHUD)
vrmod.AddCallbackedConvar("vrmod_hudcurve", nil, "60", FCVAR_ARCHIVE, nil, nil, nil, tonumber, AddHUD)
vrmod.AddCallbackedConvar("vrmod_hudscale", nil, "0.05", FCVAR_ARCHIVE, nil, nil, nil, tonumber, AddHUD)
vrmod.AddCallbackedConvar("vrmod_huddistance", nil, "60", FCVAR_ARCHIVE, nil, nil, nil, tonumber)
vrmod.AddCallbackedConvar("vrmod_hudtestalpha", nil, "0", FCVAR_ARCHIVE, nil, nil, nil, tonumber)

function vrmod.RefreshHUD()
	AddHUD()
end

function vrmod.IsHUDActive()
	return hudActive and HudWanted()
end

hook.Add("VRMod_Start", "vrmod_hud", function(ply)
	if ply ~= LocalPlayer() then return end
	-- After tracking/UI ready
	timer.Simple(0, function()
		if g_VR and g_VR.active then AddHUD() end
	end)
end)

hook.Add("VRMod_Exit", "vrmod_hud", function(ply)
	if ply ~= LocalPlayer() then return end
	RemoveHUD()
	menuSystemBeforeHud = nil
end)
