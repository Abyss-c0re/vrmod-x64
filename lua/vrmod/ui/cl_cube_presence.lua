-- =============================================================================
-- Cube presence — multiplayer desktop-focus indicator
-- Law: additive light over the Real (never a black wall for the unfocused player).
-- When a VR player alt-tabs / loses desktop window focus, others see a crimson chip
-- above their HMD — same energy language as LASER LOCK / Cube labels.
-- =============================================================================
if SERVER then return end

vrmod = vrmod or {}
g_VR = g_VR or {}

local cv_enabled = CreateClientConVar(
	"vrmod_presence_chip",
	"1",
	true,
	FCVAR_ARCHIVE,
	"1 = show DESKTOP chip above unfocused VR players (Cube multiplayer presence)",
	0,
	1
)

local LABEL = "DESKTOP"
local SUB = "window unfocused"

local accentMat = Material("vrmod/tpbeam", "smooth noclamp")

local function Theme()
	if vrmod.cube and vrmod.cube.ThemeLive then return vrmod.cube.ThemeLive() end
	if vrmod.cube and vrmod.cube.Theme then return vrmod.cube.Theme end
	return {
		bgGlass = Color(22, 10, 16, 230),
		crimson = Color(196, 30, 58, 255),
		crimsonHot = Color(255, 70, 100, 255),
		header = Color(196, 30, 58, 255),
		hot = Color(255, 70, 100, 255),
		text = Color(255, 240, 244, 255),
		muted = Color(200, 150, 165, 230),
		warn = Color(255, 200, 100, 255),
	}
end

local function Font(name)
	if vrmod.cube and vrmod.cube.Font then
		if name == "title" or name == "huge" then return vrmod.cube.Font("CubeTitle") or "DermaLarge" end
		if name == "label" then return vrmod.cube.Font("CubeLabel") or "DermaDefaultBold" end
		if name == "small" then return vrmod.cube.Font("CubeSmall") or "DermaDefault" end
		return vrmod.cube.Font(name) or "DermaDefault"
	end
	if name == "title" or name == "huge" then return "DermaLarge" end
	if name == "label" then return "DermaDefaultBold" end
	return "DermaDefault"
end

--- World position for the chip: above remote HMD, or player eyes as fallback.
local function PresenceAnchor(ply, tab)
	local fr = tab and tab.lerpedFrame
	if fr and fr.hmdPos then
		local up = fr.hmdAng and fr.hmdAng:Up() or Vector(0, 0, 1)
		return fr.hmdPos + up * 8 + Vector(0, 0, 6)
	end
	if IsValid(ply) then
		local eyes = ply:EyePos()
		return eyes + Vector(0, 0, 14)
	end
	return nil
end

local function DrawChipAt(pos, ang)
	local th = Theme()
	local scale = 0.045
	cam.Start3D2D(pos, ang, scale)
	local w, h = 240, 78
	local x, y = -w * 0.5, -h * 0.5

	-- Soft beam wash (shared vrmod-x64 material)
	if accentMat and not accentMat:IsError() then
		surface.SetMaterial(accentMat)
		surface.SetDrawColor(196, 30, 58, 70)
		surface.DrawTexturedRectRotated(0, 0, w + 40, h + 24, CurTime() * 12)
	end

	surface.SetDrawColor(th.bgGlass or Color(22, 10, 16, 220))
	surface.DrawRect(x, y, w, h)
	surface.SetDrawColor(th.header or th.crimson or Color(196, 30, 58, 255))
	surface.DrawRect(x, y, 10, h)
	surface.SetDrawColor(th.hot or th.crimsonHot or Color(255, 70, 100, 255))
	surface.DrawOutlinedRect(x, y, w, h, 2)

	local pulse = 0.55 + 0.45 * math.abs(math.sin(CurTime() * 2.2))
	local edge = Color(255, 70, 100, math.floor(70 + 130 * pulse))
	surface.SetDrawColor(edge)
	surface.DrawOutlinedRect(x + 2, y + 2, w - 4, h - 4, 1)

	draw.SimpleText(LABEL, Font("label"), 6, y + 20, th.warn or Color(255, 200, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(SUB, Font("small"), 6, y + 48, th.muted or Color(200, 150, 165), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	cam.End3D2D()
end

--- Billboard angle facing local view (HMD or desktop eye).
local function BillboardAng(pos)
	local eye = EyePos()
	local dir = (eye - pos)
	dir.z = 0
	if dir:LengthSqr() < 1 then dir = EyeAngles():Forward() * -1 end
	dir:Normalize()
	local ang = dir:Angle()
	ang:RotateAroundAxis(ang:Right(), 90)
	ang:RotateAroundAxis(ang:Up(), -90)
	return ang
end

hook.Add("PostDrawTranslucentRenderables", "vrmod_cube_presence", function(depth, skybox)
	if depth or skybox then return end
	if not cv_enabled:GetBool() then return end
	if not g_VR or not g_VR.net then return end
	-- Don't nest under stereo RT / radar capture
	if g_VR._radarCapturing or g_VR._renderingHudRT then return end

	local lp = LocalPlayer()
	for steamid, tab in pairs(g_VR.net) do
		if not tab or not tab.desktopUnfocused then continue end
		local ply = player.GetBySteamID(steamid)
		if not IsValid(ply) or ply == lp then continue end
		local pos = PresenceAnchor(ply, tab)
		if not pos then continue end
		-- Distance cull (keep cheap)
		if EyePos():DistToSqr(pos) > (900 * 900) then continue end
		DrawChipAt(pos, BillboardAng(pos))
	end
end)

-- Settings catalog entry is optional; convar alone is enough.
vrmod.presence = vrmod.presence or {}
function vrmod.presence.IsRemoteUnfocused(ply)
	if not IsValid(ply) or not g_VR or not g_VR.net then return false end
	local tab = g_VR.net[ply:SteamID()]
	return tab and tab.desktopUnfocused and true or false
end
