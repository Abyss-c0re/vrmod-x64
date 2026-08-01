-- Stereo-safe halo rendering for VR dual-eye SBS.
--
-- Stock halo (includes/modules/halo.lua) is mono-frame:
--   Copy scene → Clear FULL scene RT → silhouette → blur → DrawScreenQuad
-- Under VR that Clear wipes the other eye half of the shared SBS RT, and
-- full-screen quads ignore the eye scissor → flicker / missing outlines / decal
-- side-effects from dirty stencil state.
--
-- While g_VR.active:
--   • Own halo.Add list
--   • Replace PostDrawEffects "RenderHalos"
--   • Silhouette + blur in private RTs (never Clear the stereo scene)
--   • Stencil entities on the scene with colour writes off
--   • Composite blur into the current eye viewport only (DrawScreenQuadEx)
--   • Reset stencil / depth / blend after each entry
-- Each eye re-fills the list (PostDrawOpaque / PreDrawHalos), so both eyes outline.

if SERVER then return end

local mat_Add = Material("pp/add")
local mat_Sub = Material("pp/sub")

local rt_Color
local rt_Blur
local rt_W, rt_H = 0, 0

local modelFlags = bit.bor(STUDIO_RENDER, STUDIO_SKIP_DECALS or 0)
local RenderEnt = NULL
local installed = false
local stockAdd
local list = {}

local function EnsureRTs(needW, needH)
	needW = math.max(64, math.floor(needW or 512))
	needH = math.max(64, math.floor(needH or 512))
	if rt_Color and rt_W == needW and rt_H == needH then return end
	rt_W, rt_H = needW, needH
	local tag = tostring(needW) .. "x" .. tostring(needH)
	rt_Color = GetRenderTarget("vrmod_halo_color_" .. tag, needW, needH, false)
	rt_Blur = GetRenderTarget("vrmod_halo_blur_" .. tag, needW, needH, false)
end

local function ResetDrawState()
	render.SetStencilEnable(false)
	render.SetStencilTestMask(0)
	render.SetStencilWriteMask(0)
	render.SetStencilReferenceValue(0)
	render.SuppressEngineLighting(false)
	render.SetBlend(1)
	if render.OverrideDepthEnable then render.OverrideDepthEnable(false, false) end
	if render.OverrideBlend then render.OverrideBlend(false) end
	if render.OverrideColorWriteEnable then render.OverrideColorWriteEnable(false) end
	if render.DepthRange then render.DepthRange(0, 1) end
	pcall(cam.IgnoreZ, false)
end

local function EyeCam(w, h)
	local origin = EyePos()
	local angles = EyeAngles()
	local fov = 90
	local znear, zfar = 1, 32768
	if g_VR and g_VR.view then
		fov = g_VR.view.fov or fov
		znear = g_VR.view.znear or znear
		zfar = g_VR.view.zfar or zfar
		if zfar < 256 then zfar = 32768 end
		if g_VR.view.angles then angles = g_VR.view.angles end
	end
	if g_VR then
		if g_VR.stereoEye == "right" and g_VR.eyePosRight then
			origin = g_VR.eyePosRight
		elseif g_VR.eyePosLeft then
			origin = g_VR.eyePosLeft
		end
	end
	cam.Start3D(origin, angles, fov, 0, 0, w, h, znear, zfar)
end

local function DrawEnts(ents)
	for _, ent in pairs(ents) do
		if not IsValid(ent) or ent:GetNoDraw() then continue end
		RenderEnt = ent
		ent:DrawModel(modelFlags)
	end
	RenderEnt = NULL
end

--- One halo entry: private silhouette, stencil on scene, composite into eye rect only.
local function StereoRenderEntry(entry)
	if not entry or not entry.Ents then return end

	local vx, vy, vw, vh = 0, 0, ScrW(), ScrH()
	if render.GetViewPort then
		vx, vy, vw, vh = render.GetViewPort()
	end
	if vw < 8 or vh < 8 then return end

	EnsureRTs(vw, vh)

	local additive = entry.Additive
	if additive == nil then additive = true end
	local ignoreZ = entry.IgnoreZ and true or false
	local blurX = entry.BlurX or 2
	local blurY = entry.BlurY or 2
	local passes = entry.DrawPasses or 1
	local col = entry.Color or color_white

	-- ── 1) Flat colour silhouette → private RT (scene untouched) ──────────
	render.PushRenderTarget(rt_Color)
	render.Clear(0, 0, 0, 255, true, true)
	render.ClearStencil()
	render.SetStencilEnable(true)
	render.SuppressEngineLighting(true)
	pcall(cam.IgnoreZ, ignoreZ)

	render.SetStencilWriteMask(1)
	render.SetStencilTestMask(1)
	render.SetStencilReferenceValue(1)
	render.SetStencilCompareFunction(STENCIL_ALWAYS)
	render.SetStencilPassOperation(STENCIL_REPLACE)
	render.SetStencilFailOperation(STENCIL_KEEP)
	render.SetStencilZFailOperation(STENCIL_KEEP)

	EyeCam(vw, vh)
	DrawEnts(entry.Ents)

	render.SetStencilCompareFunction(STENCIL_EQUAL)
	render.SetStencilPassOperation(STENCIL_KEEP)
	cam.Start2D()
	surface.SetDrawColor(col.r or 255, col.g or 255, col.b or 255, col.a or 255)
	surface.DrawRect(0, 0, vw, vh)
	cam.End2D()
	cam.End3D()

	pcall(cam.IgnoreZ, false)
	render.SuppressEngineLighting(false)
	render.SetStencilEnable(false)

	-- Copy colour RT → blur RT (must still be on a push that can Copy)
	render.CopyRenderTargetToTexture(rt_Blur)
	render.PopRenderTarget()
	render.BlurRenderTarget(rt_Blur, blurX, blurY, 1)

	-- ── 2) Stencil entity occupancy on SCENE (no colour write) ────────────
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
	pcall(cam.IgnoreZ, ignoreZ)
	render.SetBlend(0) -- stencil only — do not paint models onto the world

	cam.Start3D()
	DrawEnts(entry.Ents)
	cam.End3D()

	render.SetBlend(1)
	pcall(cam.IgnoreZ, false)
	render.SuppressEngineLighting(false)

	-- ── 3) Additive/subtractive blur where stencil != body (outline ring) ─
	render.SetStencilCompareFunction(STENCIL_NOTEQUAL)
	render.SetStencilPassOperation(STENCIL_KEEP)

	if additive then
		mat_Add:SetTexture("$basetexture", rt_Blur)
		render.SetMaterial(mat_Add)
	else
		mat_Sub:SetTexture("$basetexture", rt_Blur)
		render.SetMaterial(mat_Sub)
	end

	for _ = 0, passes do
		if render.DrawScreenQuadEx then
			render.DrawScreenQuadEx(vx, vy, vw, vh)
		else
			render.DrawScreenQuad()
		end
	end

	ResetDrawState()
end

local function ClearList()
	for i = #list, 1, -1 do
		list[i] = nil
	end
end

local function RenderHalosVR()
	if not g_VR or not g_VR.active then return end
	if not g_VR.stereoEye then return end

	hook.Run("PreDrawHalos")
	if #list < 1 then return end

	for i = 1, #list do
		local ok, err = pcall(StereoRenderEntry, list[i])
		if not ok and vrmod.logger then
			vrmod.logger.Debug("[halo] %s", tostring(err))
		end
	end
	ClearList()
	ResetDrawState()
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

	hook.Remove("PostDrawEffects", "RenderHalos")
	hook.Add("PostDrawEffects", "RenderHalos", RenderHalosVR)
	hook.Add("VRMod_PostRender", "vrmod_halos_clear", ClearList)

	installed = true
	if vrmod.logger then
		vrmod.logger.Debug("[halo] Stereo-safe renderer installed")
	end
end

local function Uninstall()
	if not installed then return end

	hook.Remove("PostDrawEffects", "RenderHalos")
	hook.Remove("VRMod_PostRender", "vrmod_halos_clear")
	ClearList()
	ResetDrawState()

	-- Reload stock halo module (restores private List + mono RenderHalos)
	package.loaded["halo"] = nil
	local ok = pcall(require, "halo")
	if not ok then
		-- Fallback: put back saved Add; mono outlines may be missing until reconnect
		if stockAdd then halo.Add = stockAdd end
		hook.Add("PostDrawEffects", "RenderHalos", function()
			hook.Run("PreDrawHalos")
		end)
	end

	installed = false
	stockAdd = nil
	if vrmod.logger then
		vrmod.logger.Debug("[halo] Stock renderer restored (ok=%s)", tostring(ok))
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

if g_VR and g_VR.active then
	timer.Simple(0, Install)
end
