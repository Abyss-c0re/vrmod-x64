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

local function Theme()
	if vrmod.cube and vrmod.cube.Theme then return vrmod.cube.Theme end
	return {
		bgGlass = Color(22, 10, 16, 230),
		crimson = Color(196, 30, 58, 255),
		crimsonHot = Color(255, 70, 100, 255),
		text = Color(255, 240, 244, 255),
		muted = Color(200, 150, 165, 230),
		warn = Color(255, 200, 100, 255),
	}
end

local function Font(name)
	if vrmod.cube and vrmod.cube.Font then return vrmod.cube.Font(name) end
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
	-- Glass plate (additive / translucent — not a black wall)
	local w, h = 220, 72
	local x, y = -w * 0.5, -h * 0.5
	surface.SetDrawColor(th.bgGlass or Color(22, 10, 16, 220))
	surface.DrawRect(x, y, w, h)
	-- Crimson accent bar (Cube energy)
	surface.SetDrawColor(th.crimson or Color(196, 30, 58, 255))
	surface.DrawRect(x, y, 8, h)
	surface.SetDrawColor(th.crimsonHot or Color(255, 70, 100, 255))
	surface.DrawOutlinedRect(x, y, w, h, 2)
	-- Pulse edge (time-based soft breath)
	local pulse = 0.55 + 0.45 * math.abs(math.sin(CurTime() * 2.2))
	local edge = Color(
		(th.crimsonHot and th.crimsonHot.r) or 255,
		(th.crimsonHot and th.crimsonHot.g) or 70,
		(th.crimsonHot and th.crimsonHot.b) or 100,
		math.floor(80 + 120 * pulse)
	)
	surface.SetDrawColor(edge)
	surface.DrawOutlinedRect(x + 2, y + 2, w - 4, h - 4, 1)

	draw.SimpleText(LABEL, Font("label"), 0, y + 18, th.warn or Color(255, 200, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(SUB, Font("small"), 0, y + 44, th.muted or Color(200, 150, 165), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
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
