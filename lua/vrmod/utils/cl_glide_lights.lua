-- Stereo-correct Glide vehicle lights for VR (no Glide source edits).
--
-- Glide mono path: DrawLightSprite → queue → PreDrawEffects draw+wipe.
-- That queue dies after the first eye / pass under dual RenderView.
--
-- VR path:
--   • Buffer sprites while g_VR.active (never feed Glide's mono queue)
--   • Snapshot once per stereo pair (PreStereo)
--   • Draw exactly once per eye (guard) — additive light_glow stacks into
--     "nuclear suns" if PostDrawTranslucent / PreDrawEffects multi-fire
--   • Size falloff like Glide (view · light dir) using live EyeAngles
--   • Normal depth (no DepthRange punch-through); mild bias only <50u from bulb
--   • ProjectedTextures: leave entirely to Glide Think (no Update around eyes)

if SERVER then return end

g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

local patched = false
local spriteBuffer = {}
local spriteBufferCount = 0
local snapCount = 0
local snapFrame = -1
local drawnLeftFrame = -1
local drawnRightFrame = -1
local origDrawLightSprite
local spriteColorScratch = Color(255, 255, 255, 255)
local DEFAULT_MAT

local Max = math.max
local Clamp = math.Clamp
local SetMaterial = render.SetMaterial
local DrawSprite = render.DrawSprite
local DepthRange = render.DepthRange

local function ClearSpriteBuffer()
	for i = 1, spriteBufferCount do
		spriteBuffer[i] = nil
	end
	spriteBufferCount = 0
	snapCount = 0
	snapFrame = -1
end

local function BufferSprite(pos, dir, size, color, material)
	if not pos then return end
	-- Hard cap: runaway Think / multi-queue must not explode into suns
	if spriteBufferCount >= 64 then return end

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
	-- Glide defaults are ~20–30 world units; reject absurd sizes
	local sz = size or 30
	if sz > 80 then sz = 80 end
	if sz < 1 then sz = 1 end
	slot.size = sz
	if color then
		slot.r, slot.g, slot.b, slot.a = color.r, color.g, color.b, color.a or 255
	else
		slot.r, slot.g, slot.b, slot.a = 255, 255, 255, 255
	end
	slot.material = material
end

--- Freeze the list for both eyes (Think already filled the buffer).
local function SnapshotForStereo()
	local sf = g_VR.stereoFrame or 0
	if snapFrame == sf then return end
	snapFrame = sf
	snapCount = spriteBufferCount
	drawnLeftFrame = -1
	drawnRightFrame = -1
end

local function DrawSpritesOnceThisEye()
	if not g_VR or not g_VR.active then return end
	local sf = g_VR.stereoFrame or 0
	if snapFrame ~= sf then
		SnapshotForStereo()
	end

	local eye = g_VR.stereoEye
	if eye == "right" then
		if drawnRightFrame == sf then return end
		drawnRightFrame = sf
	else
		-- left or nil → treat as left (first of pair)
		if drawnLeftFrame == sf then return end
		drawnLeftFrame = sf
	end

	local n = snapCount
	if n < 1 then return end

	if not DEFAULT_MAT then
		DEFAULT_MAT = Material("glide/effects/light_glow")
	end

	local eyePos = EyePos()
	local viewDir = -EyeAngles():Forward()

	for i = 1, n do
		local s = spriteBuffer[i]
		if not s or not s.pos then continue end

		local size = s.size or 30
		if s.hasDir and s.dir then
			-- Same falloff as Glide.DrawSprites
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

		-- Mild near bias so the bulb glow sits on the housing, not through the bumper.
		-- Glide used min 0.999 always within ~447u (punch-through). We only bias <50u.
		local d2 = eyePos:DistToSqr(s.pos)
		local biased = false
		if d2 < 2500 then
			DepthRange(0.0, Clamp(d2 / 200000, 0.9995, 1.0))
			biased = true
		end

		DrawSprite(s.pos, size, size, spriteColorScratch)

		if biased then
			DepthRange(0.0, 1.0)
		end
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

	-- Snapshot after tracking/Think, before either eye draws
	hook.Add("VRMod_PreStereo", "vrmod_glide_lights_snap", function()
		if not g_VR or not g_VR.active then return end
		SnapshotForStereo()
	end)

	-- Prefer PreDrawEffects (Glide's home) — main colour pass only, once per eye.
	hook.Add("PreDrawEffects", "vrmod_glide_lights_draw", function(bDepth, bSkybox, b3DSkybox)
		if not g_VR or not g_VR.active then return end
		if bDepth or bSkybox or b3DSkybox then return end
		DrawSpritesOnceThisEye()
	end)

	-- Fallback if a view never hits PreDrawEffects (rare)
	hook.Add("PostDrawTranslucentRenderables", "vrmod_glide_lights_draw_fallback", function(bDepth, bSkybox)
		if not g_VR or not g_VR.active then return end
		if bDepth or bSkybox then return end
		DrawSpritesOnceThisEye()
	end)

	hook.Add("VRMod_PostRender", "vrmod_glide_lights", function()
		if not g_VR or not g_VR.active then return end
		ClearSpriteBuffer()
	end)

	hook.Add("VRMod_Exit", "vrmod_glide_lights_cleanup", function(ply)
		if ply and ply ~= LocalPlayer() then return end
		ClearSpriteBuffer()
		drawnLeftFrame = -1
		drawnRightFrame = -1
	end)

	patched = true
	if vrmod.logger then
		vrmod.logger.Debug("[Glide] Stereo lights: once/eye draw, size falloff, no multi-pass stack")
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
