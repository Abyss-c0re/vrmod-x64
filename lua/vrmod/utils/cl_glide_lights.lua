-- Stereo-correct Glide vehicle lights for VR (no Glide source edits).
--
-- Keep the simple path that actually draws lights:
--   DrawLightSprite while VR → buffer
--   PreRender each eye → re-queue into Glide for PreDrawEffects
--
-- Left-eye flicker fixes (minimal):
--   1) ProjectedTexture:Update only once per stereo pair (before left eye)
--   2) Inject sprites with dir=nil so PreDrawEffects does not re-scale size
--      differently for L/R view rays
--   3) Snapshot buffer count for the stereo pair so mid-frame appends do not
--      desync the two eyes

if SERVER then return end

g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

local patched = false
local spriteBuffer = {}
local spriteBufferCount = 0
local injectCount = 0 -- frozen for this stereo pair
local injectFrame = -1
local projFrame = -1
local origDrawLightSprite
local spriteColorScratch = Color(255, 255, 255, 255)

local function LocalGlideVehicle()
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply.GlideGetVehicle then return nil end
	local veh = ply:GlideGetVehicle()
	if IsValid(veh) and veh.IsGlideVehicle then return veh end
	return nil
end

--- Once per stereo frame — dual Update is a common L-eye ProjectedTexture flicker.
local function UpdateProjectedHeadlightsOnce()
	local sf = g_VR.stereoFrame or 0
	if projFrame == sf then return end
	projFrame = sf

	local ent = LocalGlideVehicle()
	if not IsValid(ent) then return end

	local lights = ent.activeHeadlights
	if not istable(lights) then return end

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

local function ClearSpriteBuffer()
	for i = 1, spriteBufferCount do
		spriteBuffer[i] = nil
	end
	spriteBufferCount = 0
	injectCount = 0
	injectFrame = -1
end

local function BufferSprite(pos, dir, size, color, material)
	if not pos then return end
	spriteBufferCount = spriteBufferCount + 1
	local slot = spriteBuffer[spriteBufferCount]
	if not slot then
		slot = { pos = Vector() }
		spriteBuffer[spriteBufferCount] = slot
	end
	if not slot.pos then slot.pos = Vector() end
	slot.pos:Set(pos)
	-- Store dir only for optional future use; inject never passes it (stereo-stable size)
	slot.size = size or 30
	if color then
		slot.r, slot.g, slot.b, slot.a = color.r, color.g, color.b, color.a or 255
	else
		slot.r, slot.g, slot.b, slot.a = 255, 255, 255, 255
	end
	slot.material = material
end

--- Snapshot how many sprites both eyes will draw this pair.
local function EnsureInjectCount()
	local sf = g_VR.stereoFrame or 0
	if injectFrame ~= sf then
		injectFrame = sf
		injectCount = spriteBufferCount
	end
end

--- Feed Glide's mono queue for this eye. dir=nil → no per-eye size falloff.
local function InjectSpritesForEye()
	if not origDrawLightSprite then return end
	EnsureInjectCount()
	local n = injectCount
	if n < 1 then return end

	for i = 1, n do
		local s = spriteBuffer[i]
		if not s or not s.pos then continue end
		spriteColorScratch.r = s.r
		spriteColorScratch.g = s.g
		spriteColorScratch.b = s.b
		spriteColorScratch.a = s.a
		origDrawLightSprite(s.pos, nil, s.size or 30, spriteColorScratch, s.material)
	end
end

function vrmod.utils.PatchGlideLights()
	if patched then return true end
	if not Glide or not isfunction(Glide.DrawLightSprite) then return false end

	origDrawLightSprite = Glide.DrawLightSprite

	function Glide.DrawLightSprite(pos, dir, size, color, material)
		if g_VR and g_VR.active and pos then
			BufferSprite(pos, dir, size, color, material)
			return
		end
		return origDrawLightSprite(pos, dir, size, color, material)
	end

	hook.Add("VRMod_PreRender", "vrmod_glide_lights", function(eye)
		if not g_VR or not g_VR.active then return end
		-- Projected lights: only before left eye (first of the pair)
		if eye ~= "right" then
			UpdateProjectedHeadlightsOnce()
		end
		InjectSpritesForEye()
	end)

	hook.Add("VRMod_PostRender", "vrmod_glide_lights", function()
		if not g_VR or not g_VR.active then return end
		ClearSpriteBuffer()
		projFrame = -1
	end)

	hook.Add("VRMod_Exit", "vrmod_glide_lights_cleanup", function(ply)
		if ply and ply ~= LocalPlayer() then return end
		ClearSpriteBuffer()
		projFrame = -1
	end)

	patched = true
	if vrmod.logger then
		vrmod.logger.Debug("[Glide] Stereo lights: inject both eyes, PT update once")
	end
	return true
end

local function TryPatch()
	if patched then return end
	vrmod.utils.PatchGlideLights()
end

hook.Add("InitPostEntity", "vrmod_glide_lights_init", TryPatch)
hook.Add("VRMod_Start", "vrmod_glide_lights_start", TryPatch)
hook.Add("VRMod_PreRender", "vrmod_glide_lights_ensure", function()
	if patched then
		hook.Remove("VRMod_PreRender", "vrmod_glide_lights_ensure")
		return
	end
	TryPatch()
end)

TryPatch()
