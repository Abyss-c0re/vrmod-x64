-- Stereo-correct Glide vehicle lights for VR (no Glide source edits).
--
-- Glide queues headlight ProjectedTextures once per Think and light sprites
-- once per frame. VR renders two eyes via dual RenderView, so:
--   1) ProjectedTexture:Update must run before EACH eye (like the VR flashlight)
--   2) Light sprites are drawn in PreDrawEffects then cleared — second eye is empty
--
-- We re-Update projected headlights on VRMod_PreRender (per eye) and re-queue
-- sprites for the right eye from a frame buffer filled by wrapping DrawLightSprite.

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

--- Re-apply world pose and Update() every eye so the headlight cone exists in both views.
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

			-- Keep transform in sync with the vehicle (Glide only updates when shouldThinkNow)
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

	-- Copy so later Think mutations cannot corrupt the stereo re-queue
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

local spriteColorScratch = Color(255, 255, 255, 255)

local function RequeueSpritesForEye()
	if spriteBufferCount < 1 or not origDrawLightSprite then return end

	for i = 1, spriteBufferCount do
		local s = spriteBuffer[i]
		spriteColorScratch.r = s.r
		spriteColorScratch.g = s.g
		spriteColorScratch.b = s.b
		spriteColorScratch.a = s.a
		-- Call original only so we do not re-buffer
		origDrawLightSprite(s.pos, s.dir, s.size, spriteColorScratch, s.material)
	end
end

function vrmod.utils.PatchGlideLights()
	if patched then return true end
	if not Glide or not isfunction(Glide.DrawLightSprite) then return false end

	origDrawLightSprite = Glide.DrawLightSprite

	function Glide.DrawLightSprite(pos, dir, size, color, material)
		if g_VR.active and pos then
			BufferSprite(pos, dir, size, color, material)
		end
		return origDrawLightSprite(pos, dir, size, color, material)
	end

	-- Prefer VR eye pose for new callers of GetLocalViewLocation.
	-- Some Glide files cache the function in a local at load time; those still
	-- see correct EyePos() during each stereo RenderView.
	if isfunction(Glide.GetLocalViewLocation) then
		local origView = Glide.GetLocalViewLocation
		function Glide.GetLocalViewLocation()
			if g_VR.active and g_VR.view and g_VR.view.origin then
				return g_VR.view.origin, g_VR.view.angles
			end
			return origView()
		end
	end

	hook.Add("VRMod_PreRender", "vrmod_glide_lights", function(eye)
		if not g_VR.active then return end

		if eye == "right" then
			-- Glide.DrawSprites already cleared its queue after the left eye;
			-- re-fill so PreDrawEffects on the right eye draws the same glows.
			RequeueSpritesForEye()
		end

		UpdateProjectedHeadlights()
	end)

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
		vrmod.logger.Debug("[Glide] Stereo light rendering patched for VR")
	end
	return true
end

local function TryPatch()
	if patched then
		hook.Remove("Think", "vrmod_glide_lights_wait")
		return
	end
	if vrmod.utils.PatchGlideLights() then
		hook.Remove("Think", "vrmod_glide_lights_wait")
	end
end

hook.Add("InitPostEntity", "vrmod_glide_lights_init", TryPatch)
hook.Add("VRMod_Start", "vrmod_glide_lights_start", TryPatch)

if not vrmod.utils.PatchGlideLights() then
	hook.Add("Think", "vrmod_glide_lights_wait", TryPatch)
end
