if SERVER then return end
-- Height helpers + legacy entry. Full Cube Avatar UI lives in cl_avatar_menu.lua.
-- Scrub any leftover hooks from older heightmenu UI (they crash VRUtilMenuRenderStart).
-- Auto scale / seated: SoT is cl_seated.lua + SettingsSet* (never dual-write).
hook.Remove("VRMod_Input", "vrmodheightmenuinput")
hook.Remove("PreRender", "vrmodheightmenuplace")

local function writeScale(s)
	g_VR.scale = s
	if vrmod.SettingsSetFloat then
		vrmod.SettingsSetFloat("vrmod_scale", s)
	else
		local cv = GetConVar("vrmod_scale")
		if cv then cv:SetFloat(s) end
	end
end

local function AutoScale()
	local eyeH = vrmod.MeasureRawEyeHeight and vrmod.MeasureRawEyeHeight()
	if not eyeH then
		if not g_VR.tracking or not g_VR.tracking.hmd or not g_VR.origin then return end
		eyeH = g_VR.tracking.hmd.pos.z - g_VR.origin.z
	end
	if eyeH < 8 then eyeH = 66.8 end
	writeScale(66.8 / (eyeH / math.max(g_VR.scale or 32.7, 0.01)))
end

function vrmod.AutoScaleHeight()
	if not g_VR or not g_VR.origin then return false end
	AutoScale()
	return true, g_VR.scale
end

-- vrmod.AutoSeatedOffset defined once in cl_seated.lua

-- Legacy name → Cube Avatar customization (model, bodygroups, bones, height)
function VRUtilOpenHeightMenu()
	-- Never re-register old height UI hooks
	hook.Remove("VRMod_Input", "vrmodheightmenuinput")
	hook.Remove("PreRender", "vrmodheightmenuplace")
	if vrmod.AvatarMenu_Open then
		vrmod.AvatarMenu_Open()
	end
end

hook.Add("VRMod_Start", "vrmod_OpenHeightMenuOnStartup", function(ply)
	if ply ~= LocalPlayer() then return end
	if vrmod.Experience_ShouldRun and vrmod.Experience_ShouldRun() then return end
	local hm = GetConVar("vrmod_heightmenu")
	if not hm or not hm:GetBool() then return end
	timer.Create("vrmod_HeightMenuStartupWait", 1, 0, function()
		if g_VR.threePoints then
			timer.Remove("vrmod_HeightMenuStartupWait")
			VRUtilOpenHeightMenu()
		end
	end)
end)

hook.Add("VRMod_Exit", "vrmod_height_avatar_cleanup", function(ply)
	if ply ~= LocalPlayer() then return end
	if vrmod.AvatarMenu_Close then vrmod.AvatarMenu_Close() end
	if vrmod.avatar then
		vrmod.avatar.Close("avatar")
		vrmod.avatar.Close("height")
	end
end)
