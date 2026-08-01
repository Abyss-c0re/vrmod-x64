-- VR pickup / halo.Add outlines that actually show in dual-eye SBS.
--
-- Stock halo clears the full scene RT + full-screen quads → kills the other eye.
-- Fancy private-RT outline paths here went invisible. Pickup needs reliable
-- ignoreZ colour glows (orange left / cyan right), not a perfect bloom clone.
--
-- While VR active:
--   1) Intercept halo.Add → queue
--   2) After pickup's PostDrawOpaque (hook name sorts later), draw queue
--   3) Only when stereoEye is left|right
--   4) Simple ignoreZ + debugwhite + additive blend (always visible)
--   5) Soft multi-pass for a bit of "glow" without RTs
-- Restore stock halo module on VR exit.

if SERVER then return end

local mat_white = Material("models/debug/debugwhite")
local modelFlags = bit.bor(STUDIO_RENDER, STUDIO_SKIP_DECALS or 0)

local list = {}
local installed = false
local stockAdd
local RenderEnt = NULL

local function ClearList()
	for i = #list, 1, -1 do
		list[i] = nil
	end
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
		if render.OverrideBlend then render.OverrideBlend(false) end
		if render.OverrideDepthEnable then render.OverrideDepthEnable(false, false) end
		if render.DepthRange then render.DepthRange(0, 1) end
		cam.IgnoreZ(false)
	end)
end

local function DrawEnts(ents)
	for _, ent in pairs(ents) do
		if not IsValid(ent) or ent:GetNoDraw() then continue end
		RenderEnt = ent
		-- Bones can be stale mid-frame for phys props
		if ent.SetupBones then pcall(ent.SetupBones, ent) end
		ent:DrawModel(modelFlags)
	end
	RenderEnt = NULL
end

--- Always-visible pickup-style glow (no RT, no scene clear).
local function DrawEntry(entry)
	if not entry or not entry.Ents then return end

	local col = entry.Color or color_white
	local r = (col.r or 255) / 255
	local g = (col.g or 255) / 255
	local b = (col.b or 255) / 255
	local a = (col.a or 255) / 255
	local ignoreZ = entry.IgnoreZ
	if ignoreZ == nil then ignoreZ = true end -- pickup always wants this
	local passes = math.max(1, (entry.DrawPasses or 1) + 1)

	render.SuppressEngineLighting(true)
	cam.IgnoreZ(ignoreZ)
	render.MaterialOverride(mat_white)
	render.SetColorModulation(r, g, b)

	-- Additive so it reads as a "halo" over the prop, not a solid paint
	if render.OverrideBlend then
		render.OverrideBlend(
			true,
			BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD,
			BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD
		)
	end

	-- A few passes with slight alpha steps = soft glow without blur RT
	for p = 1, passes do
		local t = p / passes
		render.SetBlend(math.Clamp(0.25 + 0.35 * t, 0.2, 0.85) * a)
		cam.Start3D()
		DrawEnts(entry.Ents)
		cam.End3D()
	end

	if render.OverrideBlend then render.OverrideBlend(false) end
	render.SetBlend(1)
	render.SetColorModulation(1, 1, 1)
	render.MaterialOverride(nil)
	cam.IgnoreZ(false)
	render.SuppressEngineLighting(false)
end

local function FlushHalos()
	if not g_VR or not g_VR.active then return end
	local eye = g_VR.stereoEye
	if eye ~= "left" and eye ~= "right" then return end
	if #list < 1 then return end

	hook.Run("PreDrawHalos")

	for i = 1, #list do
		pcall(DrawEntry, list[i])
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
		if not (g_VR and g_VR.active) then
			if stockAdd then
				return stockAdd(entities, color, blurx, blury, passes, add, ignorez)
			end
			return
		end
		if not istable(entities) or table.IsEmpty(entities) then return end
		list[#list + 1] = {
			Ents = entities,
			Color = color,
			BlurX = blurx or 2,
			BlurY = blury or 2,
			DrawPasses = passes or 1,
			Additive = add ~= false,
			IgnoreZ = ignorez,
		}
	end

	local stockRendered = halo.RenderedEntity
	function halo.RenderedEntity()
		if IsValid(RenderEnt) then return RenderEnt end
		if isfunction(stockRendered) then return stockRendered() end
		return NULL
	end

	-- Stock mono renderer clears the SBS RT — must not run in VR
	hook.Remove("PostDrawEffects", "RenderHalos")

	-- Pickup adds on PostDrawOpaque "vrmod_draw_pickup_halo".
	-- Run after it (zzz_ sorts later) so the queue is filled this eye.
	hook.Add("PostDrawOpaqueRenderables", "zzz_vrmod_halos", function(depth, sky)
		if depth or sky then return end
		FlushHalos()
	end)

	-- Translucent props / late adds
	hook.Add("PostDrawTranslucentRenderables", "zzz_vrmod_halos", function(depth, sky)
		if depth or sky then return end
		if #list < 1 then return end
		FlushHalos()
	end)

	hook.Add("VRMod_PostRender", "vrmod_halos_clear", ClearList)

	installed = true
	if vrmod.logger then
		vrmod.logger.Info("[halo] Pickup glows installed (simple ignoreZ path)")
	end
end

local function Uninstall()
	if not installed then return end

	hook.Remove("PostDrawOpaqueRenderables", "zzz_vrmod_halos")
	hook.Remove("PostDrawTranslucentRenderables", "zzz_vrmod_halos")
	hook.Remove("VRMod_PostRender", "vrmod_halos_clear")
	hook.Remove("PostDrawEffects", "RenderHalos")
	ClearList()
	ResetState()

	if stockAdd then
		halo.Add = stockAdd
		stockAdd = nil
	end

	package.loaded["halo"] = nil
	local ok = pcall(require, "halo")
	if not ok and vrmod.logger then
		vrmod.logger.Warn("[halo] require('halo') failed on exit — reconnect if desktop halos missing")
	end

	installed = false
end

hook.Add("VRMod_Start", "vrmod_halos", function(ply)
	if ply and ply ~= LocalPlayer() then return end
	Install()
end)

hook.Add("VRMod_Exit", "vrmod_halos", function(ply)
	if ply and ply ~= LocalPlayer() then return end
	Uninstall()
end)

-- Ensure install even if Start already fired / lua_refresh mid-session
hook.Add("VRMod_PreRender", "vrmod_halos_ensure", function()
	if not g_VR or not g_VR.active then return end
	if installed then
		hook.Remove("VRMod_PreRender", "vrmod_halos_ensure")
		return
	end
	Install()
end)

if g_VR and g_VR.active then
	timer.Simple(0, Install)
end
