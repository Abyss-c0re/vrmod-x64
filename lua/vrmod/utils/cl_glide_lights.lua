-- Stereo-correct Glide vehicle lights for VR (no Glide source edits).
--
-- Driven entirely by VR rendering hooks (VRMod_PreRender / VRMod_PostRender),
-- same pattern as the player flashlight ProjectedTexture.
--
-- Glide is mono-frame: ProjectedTexture:Update once, and light sprites are
-- queued then wiped in PreDrawEffects after the first eye. Dual RenderView
-- needs both refreshed before every eye.

if SERVER then return end

g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

local patched = false
local spriteBuffer = {}
local spriteBufferCount = 0
local origDrawLightSprite
local glideVehCache = {}
local nextVehCacheTime = 0
local VEH_CACHE_INTERVAL = 0.25
local spriteColorScratch = Color(255, 255, 255, 255)

local function RefreshGlideVehicleCache()
	local now = CurTime()
	if now < nextVehCacheTime then return glideVehCache end
	nextVehCacheTime = now + VEH_CACHE_INTERVAL

	local list = {}
	local n = 0
	for _, ent in ipairs(ents.GetAll()) do
		if IsValid(ent) and ent.IsGlideVehicle then
			n = n + 1
			list[n] = ent
		end
	end

	glideVehCache = list
	return list
end

--- Pose + Update every projected headlight before this eye's RenderView.
local function UpdateProjectedHeadlights()
	local vehicles = RefreshGlideVehicleCache()
	for i = 1, #vehicles do
		local ent = vehicles[i]
		if not IsValid(ent) then continue end

		local lights = ent.activeHeadlights
		if not istable(lights) then continue end

		local headlights = ent.Headlights
		for index, light in pairs(lights) do
			if not IsValid(light) then continue end

			if istable(headlights) and headlights[index] then
				local data = headlights[index]
				if data.offset then
					light:SetPos(ent:LocalToWorld(data.offset))
				end
				if data.angles then
					light:SetAngles(ent:LocalToWorldAngles(data.angles))
				end
			end

			light:Update()
		end
	end
end

local function ClearSpriteBuffer()
	for i = 1, spriteBufferCount do
		spriteBuffer[i] = nil
	end
	spriteBufferCount = 0
end

local function BufferSprite(pos, dir, size, color, material)
	spriteBufferCount = spriteBufferCount + 1
	local slot = spriteBuffer[spriteBufferCount]
	if not slot then
		slot = {}
		spriteBuffer[spriteBufferCount] = slot
	end

	slot.pos = slot.pos or Vector()
	slot.pos:Set(pos)
	if dir then
		slot.dir = slot.dir or Vector()
		slot.dir:Set(dir)
	else
		slot.dir = nil
	end

	slot.size = size
	if color then
		slot.r, slot.g, slot.b, slot.a = color.r, color.g, color.b, color.a
	else
		slot.r, slot.g, slot.b, slot.a = 255, 255, 255, 255
	end
	slot.material = material
end

--- Feed Glide's sprite queue for the upcoming eye (PreDrawEffects consumes it).
local function InjectSpritesForEye()
	if spriteBufferCount < 1 or not origDrawLightSprite then return end

	for i = 1, spriteBufferCount do
		local s = spriteBuffer[i]
		spriteColorScratch.r = s.r
		spriteColorScratch.g = s.g
		spriteColorScratch.b = s.b
		spriteColorScratch.a = s.a
		origDrawLightSprite(s.pos, s.dir, s.size, spriteColorScratch, s.material)
	end
end

function vrmod.utils.PatchGlideLights()
	if patched then return true end
	if not Glide or not isfunction(Glide.DrawLightSprite) then return false end

	origDrawLightSprite = Glide.DrawLightSprite

	-- While VR is active: capture sprites only. Injection happens on VRMod_PreRender
	-- for each eye so we never depend on a single mono-frame queue.
	function Glide.DrawLightSprite(pos, dir, size, color, material)
		if g_VR.active and pos then
			BufferSprite(pos, dir, size, color, material)
			return
		end
		return origDrawLightSprite(pos, dir, size, color, material)
	end

	if isfunction(Glide.GetLocalViewLocation) then
		local origView = Glide.GetLocalViewLocation
		function Glide.GetLocalViewLocation()
			if g_VR.active and g_VR.view and g_VR.view.origin then
				return g_VR.view.origin, g_VR.view.angles
			end
			return origView()
		end
	end

	-- Per-eye, immediately before render.RenderView (see cl_vrmod PerformRenderViews)
	hook.Add("VRMod_PreRender", "vrmod_glide_lights", function(_eye)
		if not g_VR.active then return end

		InjectSpritesForEye()
		UpdateProjectedHeadlights()
	end)

	-- End of stereo pair: drop this frame's sprite copies
	hook.Add("VRMod_PostRender", "vrmod_glide_lights", function()
		if not g_VR.active then return end
		ClearSpriteBuffer()
	end)

	hook.Add("VRMod_Exit", "vrmod_glide_lights_cleanup", function(ply)
		if ply and ply ~= LocalPlayer() then return end
		ClearSpriteBuffer()
	end)

	patched = true
	if vrmod.logger then
		vrmod.logger.Debug("[Glide] Stereo light rendering hooked to VRMod_PreRender")
	end
	return true
end

local function TryPatch()
	if patched then return end
	vrmod.utils.PatchGlideLights()
end

hook.Add("InitPostEntity", "vrmod_glide_lights_init", TryPatch)
hook.Add("VRMod_Start", "vrmod_glide_lights_start", TryPatch)
-- Late Glide load: attempt once per stereo frame until the wrap sticks
hook.Add("VRMod_PreRender", "vrmod_glide_lights_ensure", function()
	if patched then
		hook.Remove("VRMod_PreRender", "vrmod_glide_lights_ensure")
		return
	end
	TryPatch()
end)

TryPatch()
