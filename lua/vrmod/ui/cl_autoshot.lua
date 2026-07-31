-- =============================================================================
-- VRMod auto-screenshot helper (local client)
--   vrmod_autoshot 1          — jpeg every interval while VR active
--   vrmod_autoshot_now        — one shot immediately
--   vrmod_autoshot_interval N  — seconds (default 3)
-- Engine saves to garrysmod/screenshots/*.jpg
-- =============================================================================
if SERVER then return end

local cv_on = CreateClientConVar("vrmod_autoshot", "0", false, FCVAR_NONE,
	"1 = auto jpeg while VR active (agent vision loop)", 0, 1)
local cv_iv = CreateClientConVar("vrmod_autoshot_interval", "3", true, FCVAR_ARCHIVE,
	"Seconds between auto screenshots", 1, 30)

local nextShot = 0
local shotN = 0

local function DoShot(tag)
	tag = tag or "vrmod"
	-- Source jpeg command writes garrysmod/screenshots/<map>NNNN.jpg
	RunConsoleCommand("jpeg")
	shotN = shotN + 1
	if vrmod.logger then
		vrmod.logger.Info("[autoshot] jpeg #%d %s", shotN, tostring(tag))
	end
	-- Also dump twin status for agent logs
	local s = vrmod.avatar and vrmod.avatar.Get and (vrmod.avatar.Get("avatar") or vrmod.avatar.Get("default"))
	if s and s.active then
		local snap = g_VR.avatarPoseSnap
		local n = snap and snap.bones and #snap.bones or 0
		local age = snap and snap.frame and (FrameNumber() - snap.frame) or -1
		if vrmod.logger then
			vrmod.logger.Info("[autoshot] twin mode=%s dist=%.0f yaw=%.0f snapBones=%d age=%d targets=%s",
				tostring(s.mode), tonumber(s.distance) or 0, tonumber(s.freeYaw) or (s.standAng and s.standAng.yaw) or 0,
				n, age, s.targets and next(s.targets) and "yes" or "no")
		end
	end
end

concommand.Add("vrmod_autoshot_now", function()
	DoShot("manual")
end)

hook.Add("Think", "vrmod_autoshot", function()
	if not cv_on:GetBool() then return end
	if not g_VR or not g_VR.active then return end
	local now = SysTime()
	if now < nextShot then return end
	local iv = cv_iv:GetFloat()
	if iv ~= iv or iv < 1 then iv = 3 end
	nextShot = now + iv
	DoShot("auto")
end)

hook.Add("VRMod_Exit", "vrmod_autoshot", function()
	nextShot = 0
end)
