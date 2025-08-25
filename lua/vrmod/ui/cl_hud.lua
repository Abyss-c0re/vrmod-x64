if SERVER then return end
local vrScrH = CreateClientConVar("vrmod_ScrH_hud", ScrH(), true, FCVAR_ARCHIVE)
local vrScrW = CreateClientConVar("vrmod_ScrW_hud", ScrW(), true, FCVAR_ARCHIVE)
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
		verts[#verts + 1] = {
			pos = matrix * Vector(x1, 0, z1),
			u = fraction,
			v = 0
		}

		verts[#verts + 1] = {
			pos = matrix * Vector(x2, 0, z2),
			u = nextFraction,
			v = 0
		}

		verts[#verts + 1] = {
			pos = matrix * Vector(x2, h, z2),
			u = nextFraction,
			v = 1
		}

		verts[#verts + 1] = {
			pos = matrix * Vector(x2, h, z2),
			u = nextFraction,
			v = 1
		}

		verts[#verts + 1] = {
			pos = matrix * Vector(x1, h, z1),
			u = fraction,
			v = 1
		}

		verts[#verts + 1] = {
			pos = matrix * Vector(x1, 0, z1),
			u = fraction,
			v = 0
		}
	end

	mesh:BuildFromTriangles(verts)
	return mesh
end

local rt = GetRenderTarget("vrmod_hud", vrScrW:GetInt(), vrScrH:GetInt(), false)
local mat = Material("!vrmod_hud")
mat = not mat:IsError() and mat or CreateMaterial("vrmod_hud", "UnlitGeneric", {
	["$basetexture"] = rt:GetName(),
	["$translucent"] = 1
})

local hudMeshes = {}
local hudMesh = nil
local orig = nil
local convars, convarValues = vrmod.GetConvars()
local function RemoveHUD()
	hook.Remove("VRMod_PreRender", "hud")
	hook.Remove("HUDShouldDraw", "vrmod_hud")
	VRUtilRenderMenuSystem = orig or VRUtilRenderMenuSystem
end

local function AddHUD()
	RemoveHUD()
	if not g_VR.active or not convarValues.vrmod_hud then return end
	local mtx = Matrix()
	mtx:Translate(Vector(0, 0, vrScrH:GetInt() * convarValues.vrmod_hudscale / 2))
	mtx:Rotate(Angle(0, -90, -90))
	local meshName = convarValues.vrmod_hudscale .. "_" .. convarValues.vrmod_hudcurve
	hudMeshes[meshName] = hudMeshes[meshName] or CurvedPlane(vrScrW:GetInt() * convarValues.vrmod_hudscale, vrScrH:GetInt() * convarValues.vrmod_hudscale, 10, convarValues.vrmod_hudcurve, mtx)
	hudMesh = hudMeshes[meshName]
	local blacklist = {}
	for k, v in ipairs(string.Explode(",", convarValues.vrmod_hudblacklist)) do
		blacklist[v] = #v > 0 and true or blacklist[v]
	end

	if table.Count(blacklist) > 0 then hook.Add("HUDShouldDraw", "vrmod_hud", function(name) if blacklist[name] then return false end end) end
	hook.Add("VRMod_PreRender", "hud", function()
		if not g_VR.threePoints then return end
		render.PushRenderTarget(rt)
		render.OverrideAlphaWriteEnable(true, true)
		render.Clear(0, 0, 0, convarValues.vrmod_hudtestalpha, true, true)
		render.RenderHUD(0, 0, vrScrW:GetInt(), vrScrH:GetInt())
		render.OverrideAlphaWriteEnable(false)
		render.PopRenderTarget()
		mtx:Identity()
		mtx:Translate(g_VR.tracking.hmd.pos + g_VR.tracking.hmd.ang:Forward() * convarValues.vrmod_huddistance)
		mtx:Rotate(g_VR.tracking.hmd.ang)
	end)

	--todo dont hook menu system to draw on top of player lol
	orig = orig or VRUtilRenderMenuSystem
	VRUtilRenderMenuSystem = function()
		render.SetMaterial(mat)
		cam.PushModelMatrix(mtx)
		render.DepthRange(0, 0.01)
		hudMesh:Draw()
		render.DepthRange(0, 1)
		cam.PopModelMatrix()
		orig()
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