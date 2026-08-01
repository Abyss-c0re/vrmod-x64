-- Stereo-safe halo.Add for VR dual-eye SBS.
--
-- Stock halo.Clear's the full scene RT and DrawScreenQuad's ScrWxScrH — that
-- wipes the other eye and breaks scissor. Old VRMod wrapper only drew when
-- EyePos == g_VR.view.origin (never true per-eye).
--
-- This version:
--   • Owns halo.Add list while VR is active
--   • Draws on PostDrawTranslucentRenderables when stereoEye is left|right only
--     (never nil — radar/HUD captures must not consume or clear the list)
--   • Silhouette + blur in a private RT; never Clear the stereo scene
--   • Composites into the current eye viewport only
--   • Restores stock halo on VR exit via require("halo")

if SERVER then return end

local mat_Add = Material("pp/add")
local mat_Sub = Material("pp/sub")
local mat_white = Material("models/debug/debugwhite")

local rt_Halo
local rt_W, rt_H = 0, 0

local modelFlags = bit.bor(STUDIO_RENDER, STUDIO_SKIP_DECALS or 0)
local RenderEnt = NULL
local installed = false
local stockAdd
local list = {}

local function EnsureRT(w, h)
	w = math.max(64, math.floor(w))
	h = math.max(64, math.floor(h))
	if rt_Halo and rt_W == w and rt_H == h then return end
	rt_W, rt_H = w, h
	rt_Halo = GetRenderTarget("vrmod_halo_eye_" .. w .. "x" .. h, w, h, false)
end

local function ResetState()
	pcall(function()
		render.SetStencilEnable(false)
		render.SetStencilTestMask(0)
		render.SetStencilWriteMask(0)
		render.SetStencilReferenceValue(0)
		render.SuppressEngineLighting(false)
		render.SetBlend(1)
		render.SetColorModulation(1, 1, 1)
		render.MaterialOverride(nil)
		if render.OverrideDepthEnable then render.OverrideDepthEnable(false, false) end
		if render.OverrideBlend then render.OverrideBlend(false) end
		if render.DepthRange then render.DepthRange(0, 1) end
		cam.IgnoreZ(false)
	end)
end

local function ClearList()
	for i = #list, 1, -1 do
		list[i] = nil
	end
end

local function EyeOriginAngles()
	local origin = EyePos()
	local angles = EyeAngles()
	if g_VR then
		if g_VR.stereoEye == "right" and g_VR.eyePosRight then
			origin = g_VR.eyePosRight
		elseif g_VR.eyePosLeft then
			origin = g_VR.eyePosLeft
		end
		if g_VR.view and g_VR.view.angles then
			angles = g_VR.view.angles
		end
	end
	return origin, angles
end

local function EyeFovZ()
	local fov, znear, zfar = 90, 1, 32768
	if g_VR and g_VR.view then
		fov = g_VR.view.fov or fov
		znear = g_VR.view.znear or znear
		zfar = g_VR.view.zfar or zfar
		if zfar < 256 then zfar = 32768 end
	end
	return fov, znear, zfar
end

local function DrawEnts(ents)
	for _, ent in pairs(ents) do
		if not IsValid(ent) or ent:GetNoDraw() then continue end
		RenderEnt = ent
		ent:DrawModel(modelFlags)
	end
	RenderEnt = NULL
end

--- Soft outline: private silhouette (no scene clear) + stencil composite in eye rect.
local function RenderEntry(entry)
	if not entry or not entry.Ents then return end

	local vx, vy, vw, vh = 0, 0, ScrW(), ScrH()
	if render.GetViewPort then
		vx, vy, vw, vh = render.GetViewPort()
	end
	if vw < 8 or vh < 8 then return end

	EnsureRT(vw, vh)

	local additive = entry.Additive
	if additive == nil then additive = true end
	local ignoreZ = entry.IgnoreZ and true or false
	local blurX = math.max(1, entry.BlurX or 2)
	local blurY = math.max(1, entry.BlurY or 2)
	local passes = math.max(0, entry.DrawPasses or 1)
	local col = entry.Color or color_white
	local cr = (col.r or 255) / 255
	local cg = (col.g or 255) / 255
	local cb = (col.b or 255) / 255
	local origin, angles = EyeOriginAngles()
	local fov, znear, zfar = EyeFovZ()

	-- 1) Flat coloured models → private RT
	render.PushRenderTarget(rt_Halo)
	render.Clear(0, 0, 0, 255, true, true)
	cam.Start3D(origin, angles, fov, 0, 0, vw, vh, znear, zfar)
	render.SuppressEngineLighting(true)
	cam.IgnoreZ(ignoreZ)
	render.MaterialOverride(mat_white)
	render.SetColorModulation(cr, cg, cb)
	DrawEnts(entry.Ents)
	render.SetColorModulation(1, 1, 1)
	render.MaterialOverride(nil)
	cam.IgnoreZ(false)
	render.SuppressEngineLighting(false)
	cam.End3D()
	render.PopRenderTarget()

	-- 2) Soften (custom RTs support BlurRenderTarget in modern GMod)
	pcall(render.BlurRenderTarget, rt_Halo, blurX, blurY, 1)

	-- 3) Stencil entity masks on the live eye (colour off)
	render.ClearStencil()
	render.SetStencilEnable(true)
	render.SetStencilWriteMask(1)
	render.SetStencilTestMask(1)
	render.SetStencilReferenceValue(1)
	render.SetStencilCompareFunction(STENCIL_ALWAYS)
	render.SetStencilPassOperation(STENCIL_REPLACE)
	render.SetStencilFailOperation(STENCIL_KEEP)
	render.SetStencilZFailOperation(STENCIL_KEEP)
	render.SuppressEngineLighting(true)
	cam.IgnoreZ(ignoreZ)
	render.SetBlend(0)

	cam.Start3D()
	DrawEnts(entry.Ents)
	cam.End3D()

	render.SetBlend(1)
	cam.IgnoreZ(false)
	render.SuppressEngineLighting(false)

	-- 4) Blur where stencil != body → outline ring (eye rect only)
	render.SetStencilCompareFunction(STENCIL_NOTEQUAL)
	render.SetStencilPassOperation(STENCIL_KEEP)

	if additive then
		mat_Add:SetTexture("$basetexture", rt_Halo)
		render.SetMaterial(mat_Add)
	else
		mat_Sub:SetTexture("$basetexture", rt_Halo)
		render.SetMaterial(mat_Sub)
	end

	for _ = 0, passes do
		if render.DrawScreenQuadEx then
			render.DrawScreenQuadEx(vx, vy, vw, vh)
		else
			render.DrawScreenQuad()
		end
	end

	ResetState()
end

--- Fallback if stencil/blur path fails: ignoreZ solid tint (always visible).
local function RenderEntryFallback(entry)
	if not entry or not entry.Ents then return end
	local col = entry.Color or color_white
	local ignoreZ = entry.IgnoreZ and true or false

	render.SuppressEngineLighting(true)
	cam.IgnoreZ(ignoreZ)
	render.MaterialOverride(mat_white)
	render.SetColorModulation((col.r or 255) / 255, (col.g or 255) / 255, (col.b or 255) / 255)
	render.SetBlend(0.35)

	cam.Start3D()
	DrawEnts(entry.Ents)
	cam.End3D()

	render.SetBlend(1)
	render.SetColorModulation(1, 1, 1)
	render.MaterialOverride(nil)
	cam.IgnoreZ(false)
	render.SuppressEngineLighting(false)
	ResetState()
end

local function DrawHalosThisEye()
	if not g_VR or not g_VR.active then return end
	-- Real eyes only — never radar / HUD nested views
	local eye = g_VR.stereoEye
	if eye ~= "left" and eye ~= "right" then return end

	hook.Run("PreDrawHalos")
	if #list < 1 then return end

	for i = 1, #list do
		local entry = list[i]
		local ok = pcall(RenderEntry, entry)
		if not ok then
			pcall(RenderEntryFallback, entry)
		end
	end
	ClearList()
	ResetState()
end

local function Install()
	if installed then return end
	if not halo or not isfunction(halo.Add) then return end

	stockAdd = stockAdd or halo.Add
	ClearList()

	function halo.Add(entities, color, blurx, blury, passes, add, ignorez)
		if not g_VR or not g_VR.active then
			if stockAdd then
				return stockAdd(entities, color, blurx, blury, passes, add, ignorez)
			end
			return
		end
		if not istable(entities) or table.IsEmpty(entities) then return end
		if add == nil then add = true end
		if ignorez == nil then ignorez = false end
		list[#list + 1] = {
			Ents = entities,
			Color = color,
			BlurX = blurx or 2,
			BlurY = blury or 2,
			DrawPasses = passes or 1,
			Additive = add,
			IgnoreZ = ignorez,
		}
	end

	local stockRendered = halo.RenderedEntity
	function halo.RenderedEntity()
		if IsValid(RenderEnt) then return RenderEnt end
		if isfunction(stockRendered) then return stockRendered() end
		return NULL
	end

	-- Disable stock mono renderer (clears full SBS RT)
	hook.Remove("PostDrawEffects", "RenderHalos")

	-- Draw during the eye pass after opaque halo.Add (pickup uses PostDrawOpaque)
	hook.Add("PostDrawTranslucentRenderables", "vrmod_halos", function(depth, sky)
		if depth or sky then return end
		DrawHalosThisEye()
	end)

	-- Safety: also try PostDrawEffects if translucent was skipped
	hook.Add("PostDrawEffects", "RenderHalos", function()
		if not g_VR or not g_VR.active then return end
		if #list < 1 then return end
		DrawHalosThisEye()
	end)

	hook.Add("VRMod_PostRender", "vrmod_halos_clear", ClearList)

	installed = true
	if vrmod.logger then
		vrmod.logger.Debug("[halo] Stereo renderer installed (translucent + effects)")
	end
end

local function Uninstall()
	if not installed then return end

	hook.Remove("PostDrawTranslucentRenderables", "vrmod_halos")
	hook.Remove("PostDrawEffects", "RenderHalos")
	hook.Remove("VRMod_PostRender", "vrmod_halos_clear")
	ClearList()
	ResetState()

	if stockAdd then
		halo.Add = stockAdd
	end
	stockAdd = nil

	-- Restore stock PostDrawEffects RenderHalos + private List
	package.loaded["halo"] = nil
	local ok = pcall(require, "halo")
	if not ok then
		-- Minimal stock-compatible flush if require fails
		hook.Add("PostDrawEffects", "RenderHalos", function()
			hook.Run("PreDrawHalos")
		end)
	end

	installed = false
	if vrmod.logger then
		vrmod.logger.Debug("[halo] Stock restored (require_ok=%s)", tostring(ok))
	end
end

hook.Add("VRMod_Start", "vrmod_halos", function(ply)
	if ply and ply ~= LocalPlayer() then return end
	Install()
end)

hook.Add("VRMod_Exit", "vrmod_halos", function(ply)
	if ply and ply ~= LocalPlayer() then return end
	Uninstall()
end)

-- lua_refresh / already in VR
if g_VR and g_VR.active then
	timer.Simple(0, Install)
end
