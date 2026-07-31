if SERVER then return end

-- =============================================================================
-- VR HUD — proven path (restore 01581db / 9390b81), hardened for settings toggle
--
-- Paint: UnlitGeneric $translucent (NOT additive — additive hid the HUD)
-- Clear: black + hudtestalpha each frame (stops ghost pile without killing paint)
-- Draw: wrap VRUtilRenderMenuSystem + PostDrawTranslucent backup
-- Toggle: ConVar:SetInt + RefreshHUD (RunConsoleCommand alone is unreliable)
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

local rtW = math.max(64, vrScrW:GetInt())
local rtH = math.max(64, vrScrH:GetInt())
local rt = GetRenderTarget("vrmod_hud", rtW, rtH, false)
-- Unique material name so we never stick with a poisoned $additive cache
local mat = CreateMaterial("vrmod_hud_mesh_v2", "UnlitGeneric", {
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
	render.DepthRange(0, 0.01)
	hudMesh:Draw()
	render.DepthRange(0, 1)
	cam.PopModelMatrix()
end

local function Unbind()
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

	-- Resize RT if convars changed
	local w = math.max(64, vrScrW:GetInt())
	local h = math.max(64, vrScrH:GetInt())
	if w ~= rtW or h ~= rtH then
		rtW, rtH = w, h
		rt = GetRenderTarget("vrmod_hud", rtW, rtH, false)
		if mat and not mat:IsError() then
			mat:SetTexture("$basetexture", rt)
		end
	end

	local scale = CVFloat("vrmod_hudscale", 0.05)
	local curve = CVFloat("vrmod_hudcurve", 60)
	local meshName = tostring(scale) .. "_" .. tostring(curve) .. "_" .. w .. "x" .. h

	local build = Matrix()
	build:Translate(Vector(0, 0, h * scale / 2))
	build:Rotate(Angle(0, -90, -90))
	hudMeshes[meshName] = hudMeshes[meshName]
		or CurvedPlane(w * scale, h * scale, 10, curve, build)
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

	-- Capture HUD into RT once per stereo frame (left eye)
	hook.Add("VRMod_PreRender", "hud", function(eye)
		if eye == "right" then return end
		if not g_VR.active or not CVBool("vrmod_hud", true) then return end
		if not g_VR.tracking or not g_VR.tracking.hmd then return end

		hook.Call("VRMod_PreRenderHUD", nil, eye)

		local rw, rh = math.max(64, vrScrW:GetInt()), math.max(64, vrScrH:GetInt())
		render.PushRenderTarget(rt)
		render.OverrideAlphaWriteEnable(true, true)
		-- Classic clear: RGB black, alpha from hudtestalpha (0 = transparent plate)
		local bgA = math.Clamp(CVFloat("vrmod_hudtestalpha", 0), 0, 255)
		render.Clear(0, 0, 0, bgA, true, true)
		g_VR._renderingHudRT = true
		render.RenderHUD(0, 0, rw, rh)
		g_VR._renderingHudRT = false
		hook.Call("VRMod_PostRenderHUD", nil, eye)
		render.OverrideAlphaWriteEnable(false)
		render.PopRenderTarget()

		mtx:Identity()
		mtx:Translate(g_VR.tracking.hmd.pos + g_VR.tracking.hmd.ang:Forward() * CVFloat("vrmod_huddistance", 60))
		mtx:Rotate(g_VR.tracking.hmd.ang)
	end)

	-- Draw path A: wrap menu system (classic)
	if isfunction(VRUtilRenderMenuSystem) then
		if not wrapped then
			origMenuSystem = VRUtilRenderMenuSystem
			wrapped = true
		end
		local base = origMenuSystem
		VRUtilRenderMenuSystem = function()
			DrawHudMesh()
			if base then base() end
		end
	end

	-- Draw path B: direct translucent draw (works even if menu wrap lost)
	hook.Add("PostDrawTranslucentRenderables", "vrmod_hud_draw", function(depth, sky)
		if depth or sky then return end
		if not g_VR or not g_VR.active then return end
		-- Prefer stereo eyes; still draw for mono debug
		local ep = EyePos()
		if g_VR.eyePosLeft and g_VR.eyePosRight then
			if ep ~= g_VR.eyePosLeft and ep ~= g_VR.eyePosRight then
				return
			end
		end
		DrawHudMesh()
	end, -5)

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

hook.Add("VRMod_Start", "hud", function(ply)
	if ply ~= LocalPlayer() then return end
	timer.Simple(0, function()
		if g_VR and g_VR.active then Bind() end
	end)
	-- Late bind: menus / VRUtilRenderMenuSystem may finish after Start
	timer.Simple(0.5, function()
		if g_VR and g_VR.active and CVBool("vrmod_hud", true) then Bind() end
	end)
end)

hook.Add("VRMod_Exit", "hud", function(ply)
	if ply ~= LocalPlayer() then return end
	Unbind()
	origMenuSystem = nil
end)

concommand.Add("vrmod_hud_status", function()
	local c = GetConVar("vrmod_hud")
	print(string.format(
		"[vrmod_hud] cvar=%s bound=%s active=%s mat=%s mesh=%s scale=%.3f dist=%.1f",
		c and tostring(c:GetBool()) or "nil",
		tostring(hudBound),
		tostring(vrmod.IsHUDActive and vrmod.IsHUDActive()),
		mat and (mat:IsError() and "ERR" or "ok") or "nil",
		hudMesh and "ok" or "nil",
		CVFloat("vrmod_hudscale", 0.05),
		CVFloat("vrmod_huddistance", 60)
	))
end)

concommand.Add("vrmod_hud_rebind", function()
	Bind()
	print("[vrmod_hud] rebound")
end)
