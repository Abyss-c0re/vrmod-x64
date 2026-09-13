-- Stereo-correct sandbox lights (lamps / gmod_light / env_projectedtexture).
-- Source ProjectedTexture + DynamicLight are consumed by one RenderView;
-- refresh immediately before each stereo eye so the left eye is not dark.
if SERVER then return end

g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

local PT_FIELDS = {
	"flashlight", "Flashlight", "projectedTexture", "ProjectedTexture",
	"lamp", "Light", "m_pFlashlight", "texture",
}

local LIGHT_CLASSES = {
	"gmod_lamp",
	"gmod_light",
	"env_projectedtexture",
	"light_dynamic",
}

local cachedLights = {}
local cachedLightsFrame = -1

local function LightEntities()
	local sf = (g_VR and g_VR.stereoFrame) or -1
	if cachedLightsFrame == sf and sf >= 0 then
		return cachedLights
	end
	cachedLightsFrame = sf
	local n = 0
	for c = 1, #LIGHT_CLASSES do
		local list = ents.FindByClass(LIGHT_CLASSES[c])
		if istable(list) then
			for i = 1, #list do
				n = n + 1
				cachedLights[n] = list[i]
			end
		end
	end
	for i = n + 1, #cachedLights do
		cachedLights[i] = nil
	end
	return cachedLights
end

local function UpdateProjected(pt)
	if not pt or not isfunction(pt.Update) then return end
	pcall(pt.Update, pt)
end

local function RefreshEntityLight(ent)
	if not IsValid(ent) then return end
	if isfunction(ent.UpdateLight) then
		pcall(ent.UpdateLight, ent)
	else
		for i = 1, #PT_FIELDS do
			local pt = ent[PT_FIELDS[i]]
			if pt and isfunction(pt.Update) then
				UpdateProjected(pt)
			end
		end
	end
	-- PT Update lights the world; Think/DrawSprite is what makes the
	-- fixture look on. Skipping Think left lamps/headlights looking off.
	if isfunction(ent.Think) then
		pcall(ent.Think, ent)
	end
end

function vrmod.utils.RefreshStereoLights(eye)
	local law = vrmod.utils.StereoLightLaw_Decide
	if isfunction(law) then
		local d = law({
			eye = eye,
			vr_active = g_VR and g_VR.active and true or false,
		})
		if not d or not d.refresh then return false end
	elseif eye ~= "left" and eye ~= "right" then
		return false
	end
	if not g_VR or not g_VR.active then return false end

	local list = LightEntities()
	for i = 1, #list do
		RefreshEntityLight(list[i])
	end
	-- Glide headlights are ProjectedTexture objects on the vehicle, not
	-- env_projectedtexture ents — sandbox FindByClass never sees them.
	if vrmod.utils.UpdateGlideHeadlights then
		pcall(vrmod.utils.UpdateGlideHeadlights)
	end
	return true
end

hook.Add("VRMod_PreRender", "vrmod_stereo_lights", function(eye)
	vrmod.utils.RefreshStereoLights(eye)
end)

hook.Add("VRMod_Exit", "vrmod_stereo_lights", function(ply)
	if ply and ply ~= LocalPlayer() then return end
end)
