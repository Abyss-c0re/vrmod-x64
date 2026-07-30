if SERVER then return end
-- Height helpers + legacy entry. Full Cube Avatar UI lives in cl_avatar_menu.lua.
-- Scrub any leftover hooks from older heightmenu UI (they crash VRUtilMenuRenderStart).
hook.Remove("VRMod_Input", "vrmodheightmenuinput")
hook.Remove("PreRender", "vrmodheightmenuplace")

local convars = vrmod.GetConvars()

local function AutoScale()
	if not g_VR.tracking or not g_VR.tracking.hmd then return end
	local eyeH = g_VR.tracking.hmd.pos.z - g_VR.origin.z
	if eyeH < 8 then eyeH = 66.8 end
	g_VR.scale = 66.8 / (eyeH / math.max(g_VR.scale, 0.01))
	convars.vrmod_scale:SetFloat(g_VR.scale)
end

function vrmod.AutoScaleHeight()
	if not g_VR or not g_VR.tracking or not g_VR.tracking.hmd then return false end
	AutoScale()
	return true, g_VR.scale
end

function vrmod.AutoSeatedOffset()
	if not g_VR or not g_VR.origin then return false end
	local hmd = (g_VR.rawTracking and g_VR.rawTracking.hmd) or (g_VR.tracking and g_VR.tracking.hmd)
	if not hmd or not hmd.pos then return false end
	local offset = 66.8 - (hmd.pos.z - g_VR.origin.z)
	convars.vrmod_seatedoffset:SetFloat(offset)
	convars.vrmod_seated:SetBool(true)
	return true, offset
end

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
	if not convars.vrmod_heightmenu:GetBool() then return end
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
