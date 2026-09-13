-- Stereo-correct Glide vehicle lights for VR (no Glide source edits).
--
-- Glide mono path: DrawLightSprite → queue → PreDrawEffects draws + wipes.
-- Dual RenderView needs the queue refilled for each eye.
--
-- Reliability rules (learned the hard way):
--   • NEVER draw/inject when g_VR.stereoEye is nil (radar PreStereoCapture
--     would consume the once-per-eye token)
--   • Inject into Glide's stock queue on VRMod_PreRender(left|right)
--   • Keep last sprites across PostRender — Glide emits during Draw, AFTER
--     left PreRender. Snapshotting count=0 then wiping the buffer = no lights
--   • Do not gate inject/PT on LocalGlideVehicle() — wrap already swallowed
--     every DrawLightSprite while VR is active
--   • ProjectedTexture:Update on each stereo eye for every Glide vehicle

if SERVER then return end

g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

local patched = false
local spriteBuffer = {}
local spriteBufferCount = 0
local allowReplace = true
local origDrawLightSprite
local spriteColorScratch = Color(255, 255, 255, 255)

local function IsGlideEnt(ent)
	if not IsValid(ent) then return false end
	if ent.IsGlideVehicle then return true end
	local cls = ent.GetClass and ent:GetClass() or ""
	return isstring(cls) and string.StartWith(cls, "glide_")
end

local function AddGlide(list, seen, ent)
	if not IsGlideEnt(ent) or seen[ent] then return end
	-- Seats parent to the vehicle
	if not ent.IsGlideVehicle and IsValid(ent:GetParent()) and ent:GetParent().IsGlideVehicle then
		ent = ent:GetParent()
		if seen[ent] then return end
	end
	seen[ent] = true
	list[#list + 1] = ent
end

local function GlideVehicles()
	local list, seen = {}, {}
	local ply = LocalPlayer()
	if IsValid(ply) then
		if ply.GlideGetVehicle then
			AddGlide(list, seen, ply:GlideGetVehicle())
		end
		if ply.GetNWEntity then
			AddGlide(list, seen, ply:GetNWEntity("GlideVehicle"))
		end
		if ply.GetVehicle then
			AddGlide(list, seen, ply:GetVehicle())
		end
	end
	if g_VR.vehicle and IsValid(g_VR.vehicle.current) then
		AddGlide(list, seen, g_VR.vehicle.current)
	end
	local found = ents.FindByClass("glide_*")
	if istable(found) then
		for i = 1, #found do
			AddGlide(list, seen, found[i])
		end
	end
	return list
end

local function UpdateProjectedOn(ent)
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
		if isfunction(light.Update) then
			pcall(light.Update, light)
		end
	end
end

function vrmod.utils.UpdateGlideHeadlights()
	local vehs = GlideVehicles()
	for i = 1, #vehs do
		UpdateProjectedOn(vehs[i])
	end
	return #vehs
end

local function BufferSprite(pos, dir, size, color, material)
	if not pos then return end
	-- Replace only after both eyes have injected the previous pair.
	-- Never start a new fill on Think/radar (that wiped coronas before left inject).
	if allowReplace then
		spriteBufferCount = 0
		allowReplace = false
	end
	if spriteBufferCount >= 128 then return end

	spriteBufferCount = spriteBufferCount + 1
	local slot = spriteBuffer[spriteBufferCount]
	if not slot then
		slot = { pos = Vector(), dir = Vector(), hasDir = false }
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

--- Refill Glide's mono queue for the upcoming eye PreDrawEffects.
-- Use whatever sprites we have (this pair or the last pair). Never lock 0.
local function InjectSpritesForEye()
	if not origDrawLightSprite then return end
	local n = spriteBufferCount
	if n < 1 then return end

	for i = 1, n do
		local s = spriteBuffer[i]
		if not s or not s.pos then continue end
		spriteColorScratch.r = s.r
		spriteColorScratch.g = s.g
		spriteColorScratch.b = s.b
		spriteColorScratch.a = s.a
		local dir = (s.hasDir and s.dir) or nil
		origDrawLightSprite(s.pos, dir, s.size or 30, spriteColorScratch, s.material)
	end
end

function vrmod.utils.PatchGlideLights()
	if patched then return true end
	if not Glide or not isfunction(Glide.DrawLightSprite) then return false end

	origDrawLightSprite = Glide.DrawLightSprite

	function Glide.DrawLightSprite(pos, dir, size, color, material)
		if g_VR and g_VR.active and pos then
			-- Always buffer (Think + Draw). Never orig() here — that would
			-- consume the once-per-eye queue on radar / nil-eye frames.
			BufferSprite(pos, dir, size, color, material)
			return
		end
		return origDrawLightSprite(pos, dir, size, color, material)
	end

	hook.Add("VRMod_PreRender", "vrmod_glide_lights_pt", function(eye)
		if not g_VR or not g_VR.active then return end
		if eye ~= "left" and eye ~= "right" then return end
		vrmod.utils.UpdateGlideHeadlights()
	end)

	hook.Add("VRMod_PreRender", "vrmod_glide_lights", function(eye)
		if not g_VR or not g_VR.active then return end
		if eye ~= "left" and eye ~= "right" then return end
		InjectSpritesForEye()
		if eye == "right" then
			allowReplace = true
		end
	end)

	hook.Add("VRMod_Exit", "vrmod_glide_lights_cleanup", function(ply)
		if ply and ply ~= LocalPlayer() then return end
		spriteBufferCount = 0
		allowReplace = true
	end)

	patched = true
	if vrmod.logger then
		vrmod.logger.Debug("[Glide] Lights: inject last sprites + PT all vehicles, both eyes")
	end
	return true
end

local function TryPatch()
	if patched then return end
	vrmod.utils.PatchGlideLights()
end

hook.Add("InitPostEntity", "vrmod_glide_lights_init", TryPatch)
hook.Add("VRMod_Start", "vrmod_glide_lights_start", TryPatch)
hook.Add("VRMod_PreRender", "vrmod_glide_lights_ensure", function(eye)
	if patched then
		hook.Remove("VRMod_PreRender", "vrmod_glide_lights_ensure")
		return
	end
	TryPatch()
end)

TryPatch()
