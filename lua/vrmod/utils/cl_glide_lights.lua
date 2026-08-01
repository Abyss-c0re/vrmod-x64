-- Stereo-correct Glide vehicle lights for VR (no Glide source edits).
--
-- Glide mono-frame quirks:
--   DrawLightSprite → queue → PreDrawEffects draws once and wipes
--   ProjectedTexture:Update once per frame
--   Sprite size scales by view dir (L/R eyes differ → flicker)
--
-- VR path:
--   Wrap DrawLightSprite → live buffer while VR active
--   PreStereo: force UpdateLights → freeze buffer (keep last if empty)
--            + ProjectedTexture:Update once
--   PreRender(eye): inject freeze into Glide queue (size pre-resolved, no dir)
--   PostRender: clear live only

if SERVER then return end

g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

local patched = false
local origDrawLightSprite

local live = {}
local liveCount = 0
local freeze = {}
local freezeCount = 0
local freezeFrame = -1
local projFrame = -1

local spriteColorScratch = Color(255, 255, 255, 255)

local function LocalGlideVehicle()
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply.GlideGetVehicle then return nil end
	local veh = ply:GlideGetVehicle()
	if IsValid(veh) and veh.IsGlideVehicle then return veh end
	return nil
end

local function ClearLive()
	for i = 1, liveCount do live[i] = nil end
	liveCount = 0
end

local function BufferLive(pos, dir, size, color, material)
	if not pos then return end
	liveCount = liveCount + 1
	local slot = live[liveCount]
	if not slot then
		slot = { pos = Vector(), dir = Vector() }
		live[liveCount] = slot
	end
	slot.pos:Set(pos)
	if dir then
		slot.hasDir = true
		slot.dir:Set(dir)
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

--- Ask the vehicle to re-emit sprites into our live buffer (Think may not have run yet).
local function ForceVehicleLightSprites(ent)
	if not IsValid(ent) then return end
	local tab = ent:GetTable()
	if not tab then return end
	-- Ensure shouldThinkNow so projected light pose path runs
	tab.shouldThinkNow = true
	if isfunction(tab.UpdateLights) then
		pcall(tab.UpdateLights, ent, tab)
	elseif isfunction(ent.UpdateLights) then
		pcall(ent.UpdateLights, ent, tab)
	end
end

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
				light:SetAngles(ent:LocalToWorldAngles(data.angles or Angle(10, 0, 0)))
			end
		end
		light:Update()
	end
end

--- Copy live → freeze. If live empty, keep previous freeze (never blank lights).
local function FreezeSpritesForStereo()
	local sf = g_VR.stereoFrame or 0
	if freezeFrame == sf and freezeCount > 0 then return end

	local ent = LocalGlideVehicle()
	-- Always refresh live from the vehicle this stereo frame
	ClearLive()
	if IsValid(ent) then
		ForceVehicleLightSprites(ent)
	end

	if liveCount < 1 then
		-- Keep last freeze so we don't go dark mid-blink / lag
		freezeFrame = sf
		return
	end

	-- Rebuild freeze from live
	for i = 1, freezeCount do freeze[i] = nil end
	freezeCount = 0
	freezeFrame = sf

	local eyePos, eyeAng
	if Glide and isfunction(Glide.GetLocalViewLocation) then
		eyePos, eyeAng = Glide.GetLocalViewLocation()
	end
	if (not eyePos or not eyeAng) and g_VR.tracking and g_VR.tracking.hmd then
		eyePos = g_VR.tracking.hmd.pos
		eyeAng = g_VR.tracking.hmd.ang
	end
	local viewDir = eyeAng and (-eyeAng:Forward()) or nil

	for i = 1, liveCount do
		local s = live[i]
		if not s or not s.pos then continue end
		freezeCount = freezeCount + 1
		local f = freeze[freezeCount]
		if not f then
			f = { pos = Vector() }
			freeze[freezeCount] = f
		end
		f.pos:Set(s.pos)
		local size = s.size or 30
		if s.hasDir and viewDir and s.dir then
			local dot = viewDir:Dot(s.dir)
			dot = (dot - 0.5) * 2
			size = size * math.max(0, dot)
		end
		-- Floor so lights never vanish from grazing angles in VR
		if size < (s.size or 30) * 0.25 then
			size = (s.size or 30) * 0.25
		end
		f.size = size
		f.r, f.g, f.b, f.a = s.r, s.g, s.b, s.a
		f.material = s.material
	end
end

local function InjectFrozenSprites()
	if freezeCount < 1 or not origDrawLightSprite then return end
	for i = 1, freezeCount do
		local s = freeze[i]
		if not s or not s.pos then continue end
		local size = s.size or 30
		if size < 0.01 then continue end
		spriteColorScratch.r = s.r
		spriteColorScratch.g = s.g
		spriteColorScratch.b = s.b
		spriteColorScratch.a = s.a
		-- dir nil: PreDrawEffects won't re-scale per eye
		origDrawLightSprite(s.pos, nil, size, spriteColorScratch, s.material)
	end
end

function vrmod.utils.PatchGlideLights()
	if patched then return true end
	if not Glide or not isfunction(Glide.DrawLightSprite) then return false end

	origDrawLightSprite = Glide.DrawLightSprite

	function Glide.DrawLightSprite(pos, dir, size, color, material)
		if g_VR and g_VR.active and pos then
			BufferLive(pos, dir, size, color, material)
			return
		end
		return origDrawLightSprite(pos, dir, size, color, material)
	end

	hook.Add("VRMod_PreStereo", "vrmod_glide_lights_freeze", function()
		if not g_VR or not g_VR.active then return end
		FreezeSpritesForStereo()
		UpdateProjectedHeadlightsOnce()
	end)

	hook.Add("VRMod_PreRender", "vrmod_glide_lights", function(_eye)
		if not g_VR or not g_VR.active then return end
		local sf = g_VR.stereoFrame or 0
		if freezeFrame ~= sf then
			FreezeSpritesForStereo()
			UpdateProjectedHeadlightsOnce()
		end
		InjectFrozenSprites()
	end)

	hook.Add("VRMod_PostRender", "vrmod_glide_lights", function()
		if not g_VR or not g_VR.active then return end
		ClearLive()
	end)

	hook.Add("VRMod_Exit", "vrmod_glide_lights_cleanup", function(ply)
		if ply and ply ~= LocalPlayer() then return end
		ClearLive()
		for i = 1, freezeCount do freeze[i] = nil end
		freezeCount = 0
		freezeFrame = -1
		projFrame = -1
	end)

	patched = true
	if vrmod.logger then
		vrmod.logger.Debug("[Glide] Stereo lights: force UpdateLights + freeze/inject")
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
