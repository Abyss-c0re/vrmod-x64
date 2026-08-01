-- Stereo-correct Glide vehicle lights for VR (no Glide source edits).
--
-- Glide is mono-frame:
--   DrawLightSprite → queue → PreDrawEffects draws + wipes (DepthRange hack)
--   ProjectedTexture:Update in vehicle Think
--
-- VR problems with feeding that path:
--   1) Queue wiped after first eye / depth pass → flicker
--   2) DepthRange(0, max(0.999, …)) punches sprites through body panels
--   3) GetLocalViewLocation is HMD-cyclopean (audio wrap) → wrong depth bias
--   4) ProjectedTexture:Update on left PreRender flashes left eye only
--
-- Cube path: buffer sprites while VR, draw them ourselves both eyes with real
-- depth (no punch-through). Leave ProjectedTextures to Glide Think — do not
-- Update() around stereo eyes.

if SERVER then return end

g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

local patched = false
local spriteBuffer = {}
local spriteBufferCount = 0
local drawCount = 0 -- frozen for this stereo pair
local drawFrame = -1
local origDrawLightSprite
local spriteColorScratch = Color(255, 255, 255, 255)
local DEFAULT_MAT

local Max = math.max
local SetMaterial = render.SetMaterial
local DrawSprite = render.DrawSprite

local function ClearSpriteBuffer()
	for i = 1, spriteBufferCount do
		spriteBuffer[i] = nil
	end
	spriteBufferCount = 0
	drawCount = 0
	drawFrame = -1
end

local function BufferSprite(pos, dir, size, color, material)
	if not pos then return end
	spriteBufferCount = spriteBufferCount + 1
	local slot = spriteBuffer[spriteBufferCount]
	if not slot then
		slot = {
			pos = Vector(),
			dir = Vector(),
			hasDir = false,
		}
		spriteBuffer[spriteBufferCount] = slot
	end
	if not slot.pos then slot.pos = Vector() end
	slot.pos:Set(pos)
	if dir then
		if not slot.dir then slot.dir = Vector() end
		slot.dir:Set(dir)
		slot.hasDir = true
	else
		slot.hasDir = false
	end
	slot.size = size or 30
	if color then
		slot.r, slot.g, slot.b, slot.a = color.r, color.g, color.b, color.a or 255
	else
		slot.r, slot.g, slot.b, slot.a = 255, 255, 255, 255
	end
	slot.material = material
end

--- Freeze sprite list for the whole stereo pair (both eyes draw the same set).
local function EnsureDrawCount()
	local sf = g_VR.stereoFrame or 0
	if drawFrame ~= sf then
		drawFrame = sf
		drawCount = spriteBufferCount
	end
end

--- Draw buffered sprites for the current eye. Real depth — no Glide DepthRange.
local function DrawSpritesForEye()
	EnsureDrawCount()
	local n = drawCount
	if n < 1 then return end

	if not DEFAULT_MAT then
		DEFAULT_MAT = Material("glide/effects/light_glow")
	end

	-- Live eye for this RenderView (not HMD cache / cyclopean view).
	local viewDir = -EyeAngles():Forward()

	for i = 1, n do
		local s = spriteBuffer[i]
		if not s or not s.pos then continue end

		local size = s.size or 30
		if s.hasDir and s.dir then
			-- Same falloff math as Glide, but with this eye's forward.
			local dot = viewDir:Dot(s.dir)
			dot = (dot - 0.5) * 2
			size = size * Max(0, dot)
		end
		if size < 0.5 then continue end

		spriteColorScratch.r = s.r
		spriteColorScratch.g = s.g
		spriteColorScratch.b = s.b
		spriteColorScratch.a = s.a

		SetMaterial(s.material or DEFAULT_MAT)
		-- No DepthRange: sprites respect body panels / bumper (fixes see-through).
		DrawSprite(s.pos, size, size, spriteColorScratch)
	end
end

function vrmod.utils.PatchGlideLights()
	if patched then return true end
	if not Glide or not isfunction(Glide.DrawLightSprite) then return false end

	origDrawLightSprite = Glide.DrawLightSprite

	-- Capture only. Never feed Glide's mono PreDrawEffects queue while VR.
	function Glide.DrawLightSprite(pos, dir, size, color, material)
		if g_VR and g_VR.active and pos then
			BufferSprite(pos, dir, size, color, material)
			return
		end
		return origDrawLightSprite(pos, dir, size, color, material)
	end

	-- Draw after translucent world so vehicle body is already in the depth buffer.
	hook.Add("PostDrawTranslucentRenderables", "vrmod_glide_lights_draw", function(bDepth, bSkybox)
		if not g_VR or not g_VR.active then return end
		if bDepth or bSkybox then return end
		DrawSpritesForEye()
	end)

	hook.Add("VRMod_PostRender", "vrmod_glide_lights", function()
		if not g_VR or not g_VR.active then return end
		ClearSpriteBuffer()
	end)

	hook.Add("VRMod_Exit", "vrmod_glide_lights_cleanup", function(ply)
		if ply and ply ~= LocalPlayer() then return end
		ClearSpriteBuffer()
	end)

	patched = true
	if vrmod.logger then
		vrmod.logger.Debug("[Glide] Stereo lights: own draw both eyes, no DepthRange, no PT touch")
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
