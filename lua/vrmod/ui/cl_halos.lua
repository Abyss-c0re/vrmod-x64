-- VR halo.Add for pickup outlines (stereo SBS-safe).
--
-- Pickup does: halo.Add(sharedTable, Color(...), ...) then later table.Empty(sharedTable).
-- We MUST copy entity refs on Add — storing the table pointer means Empty wipes the
-- queue before draw (halos vanish after pick/drop / next frame).
--
-- Draw: one soft tinted pass (ignoreZ). No multi-pass additive (that blew out to white).

if SERVER then return end

local mat_white = Material("models/debug/debugwhite")
local modelFlags = bit.bor(STUDIO_RENDER, STUDIO_SKIP_DECALS or 0)

local list = {}
local installed = false
local stockAdd
local RenderEnt = NULL
-- One flush per eye per stereo frame (opaque + translucent both fire)
local flushedEye = { left = -1, right = -1 }

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

local function CopyEnts(entities)
	local out = {}
	local n = 0
	for _, ent in pairs(entities) do
		if IsValid(ent) then
			n = n + 1
			out[n] = ent
		end
	end
	return out, n
end

local function DrawEnts(ents)
	for i = 1, #ents do
		local ent = ents[i]
		if not IsValid(ent) or ent:GetNoDraw() then continue end
		RenderEnt = ent
		if ent.SetupBones then pcall(function() ent:SetupBones() end) end
		ent:DrawModel(modelFlags)
	end
	RenderEnt = NULL
end

--- Single soft coloured pass — keeps orange/cyan, not nuclear white.
local function DrawEntry(entry)
	if not entry or not entry.Ents or #entry.Ents < 1 then return end

	local col = entry.Color or color_white
	local r = (col.r or 255) / 255
	local g = (col.g or 255) / 255
	local b = (col.b or 255) / 255
	-- Cap intensity so additive-looking props don't clip to white
	local strength = 0.42
	local ignoreZ = entry.IgnoreZ
	if ignoreZ == nil then ignoreZ = true end

	render.SuppressEngineLighting(true)
	cam.IgnoreZ(ignoreZ)
	render.MaterialOverride(mat_white)
	render.SetColorModulation(r, g, b)
	render.SetBlend(strength)

	cam.Start3D()
	DrawEnts(entry.Ents)
	cam.End3D()

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

	local sf = g_VR.stereoFrame or 0
	if flushedEye[eye] == sf then
		-- Already drew this eye; drop any late adds so shared tables can't poison us
		ClearList()
		return
	end
	if #list < 1 then return end

	flushedEye[eye] = sf
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

	-- Capture true stock Add once (never chain our own wrapper)
	if not stockAdd then
		stockAdd = halo.Add
	end
	ClearList()

	function halo.Add(entities, color, blurx, blury, passes, add, ignorez)
		if not (g_VR and g_VR.active) then
			if stockAdd then
				return stockAdd(entities, color, blurx, blury, passes, add, ignorez)
			end
			return
		end
		if not istable(entities) then return end

		-- COPY entities — pickup reuses/Empties the same tables every frame
		local entsCopy, n = CopyEnts(entities)
		if n < 1 then return end

		list[#list + 1] = {
			Ents = entsCopy,
			Color = color and Color(color.r, color.g, color.b, color.a or 255) or Color(255, 255, 255),
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

	-- After pickup's vrmod_draw_pickup_halo (zzz_ sorts later)
	hook.Add("PostDrawOpaqueRenderables", "zzz_vrmod_halos", function(depth, sky)
		if depth or sky then return end
		FlushHalos()
	end)

	hook.Add("PostDrawTranslucentRenderables", "zzz_vrmod_halos", function(depth, sky)
		if depth or sky then return end
		if #list < 1 then return end
		FlushHalos()
	end)

	hook.Add("VRMod_PostRender", "vrmod_halos_clear", function()
		ClearList()
		flushedEye.left = -1
		flushedEye.right = -1
		ResetState()
	end)

	installed = true
	if vrmod.logger then
		vrmod.logger.Info("[halo] Pickup glows: copy-on-add, single soft pass")
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
	end
	-- Keep stockAdd so re-enter VR doesn't chain wrappers if require fails
	local savedStock = stockAdd
	stockAdd = nil

	package.loaded["halo"] = nil
	local ok = pcall(require, "halo")
	if not ok and savedStock then
		halo.Add = savedStock
		hook.Add("PostDrawEffects", "RenderHalos", function()
			hook.Run("PreDrawHalos")
		end)
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
