if SERVER then return end

-- =============================================================================
-- VR HUD — one plate, vitals only (no loose copy of the desktop HUD)
--
-- Capture: PaintVitals only by default.
--   vrmod_hud_engine 1 also runs RenderHUD (optional; often empty / noisy in VR).
-- Draw: ONE path — PostDrawTranslucent while g_VR.stereoEye is set.
--   (No VRUtilRenderMenuSystem wrap — that doubled the plate with menus.)
-- Theme: Settings → Theme colors on HEALTH/ARMOR/AMMO text.
-- Optional aim crosshair: projects weapon/hand aim onto the plate (not HMD center).
-- mat_queue untouched.
-- =============================================================================

local vrScrH = CreateClientConVar("vrmod_ScrH_hud", "0", true, FCVAR_ARCHIVE)
local vrScrW = CreateClientConVar("vrmod_ScrW_hud", "0", true, FCVAR_ARCHIVE)
local cv_engine = CreateClientConVar("vrmod_hud_engine", "0", true, FCVAR_ARCHIVE,
	"1 = also capture engine RenderHUD (can look like a second loose HUD panel)")
local cv_crosshair = CreateClientConVar("vrmod_hud_crosshair", "0", true, FCVAR_ARCHIVE,
	"1 = optional aim reticle on HUD plate (weapon muzzle / aim API, not HMD center)")
local cv_crosshair_src = CreateClientConVar("vrmod_hud_crosshair_src", "muzzle", true, FCVAR_ARCHIVE,
	"Aim source: muzzle | hand | auto (muzzle then hand; never HMD)")
local cv_radar = CreateClientConVar("vrmod_hud_radar", "0", true, FCVAR_ARCHIVE,
	"1 = CS:GO-style mini radar + player blips on HUD plate", 0, 1)
local cv_radar_3d = CreateClientConVar("vrmod_hud_radar_3d", "0", true, FCVAR_ARCHIVE,
	"1 = 3D top-down world photo under radar (extra RenderView; optional)", 0, 1)
local cv_radar_buildings = CreateClientConVar("vrmod_hud_radar_buildings", "1", true, FCVAR_ARCHIVE,
	"1 = show map buildings/terrain height on radar (brush traces, safe)", 0, 1)
local cv_radar_range = CreateClientConVar("vrmod_hud_radar_range", "1500", true, FCVAR_ARCHIVE,
	"Radar world range (Source units)", 400, 4000)
local cv_radar_size = CreateClientConVar("vrmod_hud_radar_size", "200", true, FCVAR_ARCHIVE,
	"Radar diameter on HUD plate (px)", 120, 320)
-- Depth band (Source units relative to feet) — underground vs surface filtering
local cv_radar_depth_up = CreateClientConVar("vrmod_hud_radar_depth_up", "192", true, FCVAR_ARCHIVE,
	"Radar sample height above feet (buildings in this band)", 48, 512)
local cv_radar_depth_down = CreateClientConVar("vrmod_hud_radar_depth_down", "72", true, FCVAR_ARCHIVE,
	"Radar sample depth below feet", 16, 256)
local cv_radar_build_min = CreateClientConVar("vrmod_hud_radar_build_min", "40", true, FCVAR_ARCHIVE,
	"Min elev above feet to draw as building (ignore floors)", 8, 128)
local cv_radar_build_max = CreateClientConVar("vrmod_hud_radar_build_max", "192", true, FCVAR_ARCHIVE,
	"Max elev above feet for buildings (hides higher floors/surface)", 64, 512)
local cv_radar_player_depth = CreateClientConVar("vrmod_hud_radar_player_depth", "256", true, FCVAR_ARCHIVE,
	"Max vertical distance for other player blips", 64, 1024)
-- Quality tiers (Cube: amortize work; never 2k traces in one stereo frame)
local cv_radar_quality = CreateClientConVar("vrmod_hud_radar_quality", "1", true, FCVAR_ARCHIVE,
	"Building map quality: 0=low 1=med 2=high (grid + traces/frame)", 0, 2)
local cv_radar_budget = CreateClientConVar("vrmod_hud_radar_budget", "48", true, FCVAR_ARCHIVE,
	"Max building TraceLines per PreStereoCapture tick", 8, 128)
local cv_radar_3d_interval = CreateClientConVar("vrmod_hud_radar_3d_interval", "30", true, FCVAR_ARCHIVE,
	"Frames between 3D radar ortho captures", 10, 120)

local RADAR_RT_SZ = 256
local radarRT = GetRenderTarget("vrmod_hud_radar_3d", RADAR_RT_SZ, RADAR_RT_SZ, false)
local radarMat = CreateMaterial("vrmod_hud_radar_mat_v1", "UnlitGeneric", {
	["$basetexture"] = radarRT:GetName(),
	["$translucent"] = 1,
	["$vertexalpha"] = 1,
	["$vertexcolor"] = 1,
	["$nolod"] = 1,
})
if radarMat and not radarMat:IsError() then
	radarMat:SetTexture("$basetexture", radarRT)
end

-- =============================================================================
-- Building heightmap — time-sliced (modern amortize-across-frames)
--
-- Old path: 44×44 = 1936 TraceLine in ONE frame → hard hitch.
-- New path: progressive fill with budget; double-buffer so paint never blanks;
-- center-first spiral priority (interesting cells first); disc-skip corners.
-- =============================================================================
local QUALITY_RES = { [0] = 24, [1] = 32, [2] = 40 }

local bmap = {
	frame = -999,
	origin = Vector(0, 0, 0),
	range = 0,
	res = 32,
	-- Display buffer (always paint this)
	cells = {},
	-- Fill buffer (job writes here, swap on complete)
	cellsNext = {},
	playerZ = 0,
	wx0 = 0, wy0 = 0, step = 1,
	ready = false,
	-- Progressive job
	job = nil,
}

-- Reused TraceLine table (no alloc per cell)
local trReuse = {
	mask = MASK_SOLID_BRUSHONLY,
	collisiongroup = COLLISION_GROUP_WORLD,
	filter = NULL,
	start = Vector(),
	endpos = Vector(),
}
local vStart = trReuse.start
local vEnd = trReuse.endpos

local function BmapRes()
	local q = math.floor(math.Clamp(cv_radar_quality:GetInt(), 0, 2))
	return QUALITY_RES[q] or 32
end

local function BmapBudget()
	return math.floor(math.Clamp(cv_radar_budget:GetInt(), 8, 128))
end

local function HudRes()
	local w = vrScrW:GetInt()
	local h = vrScrH:GetInt()
	if w < 64 then w = math.max(ScrW(), 1280) end
	if h < 64 then h = math.max(ScrH(), 720) end
	w = math.Clamp(math.floor(w / 32) * 32, 640, 1920)
	h = math.Clamp(math.floor(h / 32) * 32, 480, 1080)
	return w, h
end

local function CurvedPlane(w, h, segments, degrees, matrix)
	matrix = matrix or Matrix()
	degrees = math.rad(degrees)
	local mesh = Mesh()
	local verts = {}
	local startAng = (math.pi - degrees) / 2
	local segLen = 0.5 * math.tan(degrees / math.max(segments, 1))
	local scale = w / math.max(segLen * segments, 0.001)
	local zoffset = math.sin(startAng) * 0.5 * scale
	local col = Color(255, 255, 255, 255)
	for i = 0, segments - 1 do
		local fraction = i / segments
		local nextFraction = (i + 1) / segments
		local ang1 = startAng + fraction * degrees
		local ang2 = startAng + nextFraction * degrees
		local x1 = math.cos(ang1) * -0.5 * scale
		local x2 = math.cos(ang2) * -0.5 * scale
		local z1 = math.sin(ang1) * 0.5 * scale - zoffset
		local z2 = math.sin(ang2) * 0.5 * scale - zoffset
		verts[#verts + 1] = { pos = matrix * Vector(x1, 0, z1), u = fraction, v = 0, color = col }
		verts[#verts + 1] = { pos = matrix * Vector(x2, 0, z2), u = nextFraction, v = 0, color = col }
		verts[#verts + 1] = { pos = matrix * Vector(x2, h, z2), u = nextFraction, v = 1, color = col }
		verts[#verts + 1] = { pos = matrix * Vector(x2, h, z2), u = nextFraction, v = 1, color = col }
		verts[#verts + 1] = { pos = matrix * Vector(x1, h, z1), u = fraction, v = 1, color = col }
		verts[#verts + 1] = { pos = matrix * Vector(x1, 0, z1), u = fraction, v = 0, color = col }
	end
	mesh:BuildFromTriangles(verts)
	return mesh
end

local rtW, rtH = HudRes()
local rt = GetRenderTarget("vrmod_hud_paint", rtW, rtH, false)
local mat = CreateMaterial("vrmod_hud_mesh_paint_v2", "UnlitGeneric", {
	["$basetexture"] = rt:GetName(),
	["$translucent"] = 1,
	["$vertexalpha"] = 1,
	["$vertexcolor"] = 1,
	["$nolod"] = 1,
	["$nocull"] = 1,
	["$ignorez"] = 1,
})
if mat and not mat:IsError() then
	mat:SetTexture("$basetexture", rt)
	mat:SetInt("$translucent", 1)
	mat:SetInt("$additive", 0)
end

local hudMeshes = {}
local hudMesh = nil
local mtx = Matrix()
local hudBound = false
local captureN = 0
local plateScale = 0.05 -- last bound plate scale (world units per RT pixel * scale)
local _, convarValues = vrmod.GetConvars()

------------------------------------------------------------------------
-- VR aim: muzzle / hand API — never HMD-center “desktop” aim
------------------------------------------------------------------------
local function GetVRAim()
	local src = string.lower(cv_crosshair_src:GetString() or "muzzle")
	if src == "" then src = "auto" end

	local function fromMuzzle()
		local m = g_VR.viewModelMuzzle
		if m and m.Pos and m.Ang then
			return m.Pos, m.Ang:Forward(), "muzzle"
		end
		return nil
	end

	local function fromHand()
		if vrmod.GetRightHandPose then
			local p, a = vrmod.GetRightHandPose()
			if p and a and p:LengthSqr() > 0 then
				return p, a:Forward(), "hand"
			end
		end
		local rh = g_VR.tracking and g_VR.tracking.pose_righthand
		if rh and rh.pos and rh.ang then
			return rh.pos, rh.ang:Forward(), "hand"
		end
		return nil
	end

	-- Vehicle: use patched GetAimVector (muzzle-aware), origin from hand if possible
	local ply = LocalPlayer()
	if IsValid(ply) and ply:InVehicle() then
		local dir = ply:GetAimVector()
		local origin = select(1, fromMuzzle()) or select(1, fromHand()) or ply:EyePos()
		if dir then return origin, dir, "vehicle" end
	end

	if src == "hand" then
		return fromHand()
	elseif src == "muzzle" then
		return fromMuzzle() or fromHand()
	end
	-- auto
	return fromMuzzle() or fromHand()
end

--- Project aim ray onto HUD plate → RT pixel (or nil if miss / off-plate).
local function AimToHudPixel(aimPos, aimDir, w, h, pScale)
	local hmd = g_VR.tracking and g_VR.tracking.hmd
	if not hmd or not hmd.pos or not hmd.ang or not aimPos or not aimDir then return nil end

	local dist = CVFloat("vrmod_huddistance", 60)
	local planePos = hmd.pos + hmd.ang:Forward() * dist
	-- Plate faces the HMD: normal points back toward player along -forward of HMD
	local planeN = hmd.ang:Forward()
	local denom = aimDir:Dot(planeN)
	if math.abs(denom) < 1e-5 then return nil end
	local t = (planePos - aimPos):Dot(planeN) / denom
	if t < 0.05 or t > 400 then return nil end
	local hit = aimPos + aimDir * t

	-- Plate local: X≈right, Y≈up (HMD frame at plane center)
	local rel = WorldToLocal(hit, Angle(), planePos, hmd.ang)
	local halfW = w * pScale * 0.5
	local halfH = h * pScale * 0.5
	if halfW < 0.01 or halfH < 0.01 then return nil end
	-- Mesh is centered with +Z offset of h*scale/2 in build space; HMD local z is up
	local u = 0.5 + (rel.y / (w * pScale))
	local v = 0.5 - (rel.z / (h * pScale))
	if u < -0.05 or u > 1.05 or v < -0.05 or v > 1.05 then return nil end
	u = math.Clamp(u, 0, 1)
	v = math.Clamp(v, 0, 1)
	return u * w, v * h, hit
end

local function PaintAimCrosshair(w, h, pScale)
	if not cv_crosshair:GetBool() then return end
	local aimPos, aimDir, src = GetVRAim()
	if not aimPos then return end

	local px, py = AimToHudPixel(aimPos, aimDir, w, h, pScale)
	if not px then return end

	local T = (vrmod.cube and vrmod.cube.ThemeLive and vrmod.cube.ThemeLive())
		or (vrmod.cube and vrmod.cube.Theme) or {}
	local col = T.crimsonHot or T.hot or Color(255, 70, 100, 255)
	local outline = T.outline or Color(0, 0, 0, 200)
	local s = 10
	-- outline
	surface.SetDrawColor(outline)
	surface.DrawRect(px - s - 1, py - 1, s * 2 + 2, 3)
	surface.DrawRect(px - 1, py - s - 1, 3, s * 2 + 2)
	-- core
	surface.SetDrawColor(col.r, col.g, col.b, 255)
	surface.DrawRect(px - s, py, s * 2, 1)
	surface.DrawRect(px, py - s, 1, s * 2)
	-- center dot
	surface.DrawRect(px - 1, py - 1, 3, 3)
end

local function CVBool(name, default)
	local c = GetConVar(name)
	if c then return c:GetBool() end
	if convarValues and convarValues[name] ~= nil then return convarValues[name] and true or false end
	return default
end

local function CVFloat(name, default)
	local c = GetConVar(name)
	if c then return c:GetFloat() end
	if convarValues and convarValues[name] ~= nil then return tonumber(convarValues[name]) or default end
	return default
end

local function CVString(name, default)
	local c = GetConVar(name)
	if c then return c:GetString() end
	if convarValues and convarValues[name] ~= nil then return tostring(convarValues[name]) end
	return default
end

--- Suit plate = player Armor only.
-- Do NOT use GetSuitPower / suit_power — that is AUX (flashlight/sprint), often 100 when armor is 0.
local function GetSuitEnergy(ply)
	if not IsValid(ply) then return 0 end
	return math.max(0, math.floor(ply:Armor() or 0))
end

------------------------------------------------------------------------
-- CS:GO-style mini radar (+ optional 3D top-down world)
------------------------------------------------------------------------
local function RadarYaw(ply)
	if g_VR and g_VR.characterYaw then return g_VR.characterYaw end
	local hmd = g_VR and g_VR.tracking and g_VR.tracking.hmd
	if hmd and hmd.ang then return hmd.ang.yaw end
	if IsValid(ply) then return ply:EyeAngles().yaw end
	return 0
end

local function WorldToRadar(localPos, yaw, range, radius)
	-- world delta → radar local (forward = up on map, yaw-aligned like CS)
	local c, s = math.cos(math.rad(-yaw)), math.sin(math.rad(-yaw))
	local rx = localPos.x * c - localPos.y * s
	local ry = localPos.x * s + localPos.y * c
	-- screen: +X right, +Y down; map forward = -Y
	local u = (rx / range) * radius
	local v = (-ry / range) * radius
	return u, v
end

------------------------------------------------------------------------
-- Building heightmap — depth-aware (player Z band only)
-- Convars: vrmod_hud_radar_depth_up/down, build_min/max, player_depth
------------------------------------------------------------------------
local function RadarDepthParams()
	local depthUp = math.Clamp(cv_radar_depth_up:GetFloat(), 48, 512)
	local depthDown = math.Clamp(cv_radar_depth_down:GetFloat(), 16, 256)
	local buildMin = math.Clamp(cv_radar_build_min:GetFloat(), 8, 128)
	local buildMax = math.Clamp(cv_radar_build_max:GetFloat(), 64, 512)
	if buildMax < buildMin + 16 then buildMax = buildMin + 16 end
	-- Sample band must cover structure window
	if depthUp < buildMax then depthUp = buildMax end
	local playerDepth = math.Clamp(cv_radar_player_depth:GetFloat(), 64, 1024)
	return depthUp, depthDown, buildMin, buildMax, playerDepth
end

local function InvalidateBuildingMap()
	bmap.ready = false
	bmap.frame = -999
	bmap.job = nil
end

-- Resample when depth / quality cvars change
for _, name in ipairs({
	"vrmod_hud_radar_depth_up",
	"vrmod_hud_radar_depth_down",
	"vrmod_hud_radar_build_min",
	"vrmod_hud_radar_build_max",
	"vrmod_hud_radar_buildings",
	"vrmod_hud_radar_range",
	"vrmod_hud_radar_quality",
}) do
	cvars.AddChangeCallback(name, function()
		InvalidateBuildingMap()
	end, "vrmod_radar_depth_" .. name)
end

--- Spiral order from center (priority fill — near-player cells first).
local function BuildSpiralOrder(res)
	local order = {}
	local n = res * res
	local visited = {}
	local function push(ix, iy)
		if ix < 0 or iy < 0 or ix >= res or iy >= res then return end
		local k = iy * res + ix
		if visited[k] then return end
		visited[k] = true
		order[#order + 1] = k
	end
	local cx = math.floor((res - 1) * 0.5)
	local cy = math.floor((res - 1) * 0.5)
	local x, y = cx, cy
	push(x, y)
	local leg = 1
	local dx, dy = 1, 0
	while #order < n do
		for _ = 1, 2 do
			for _ = 1, leg do
				x, y = x + dx, y + dy
				push(x, y)
				if #order >= n then return order end
			end
			dx, dy = -dy, dx -- turn left
		end
		leg = leg + 1
	end
	return order
end

local spiralCache = {}
local function SpiralOrder(res)
	if not spiralCache[res] then spiralCache[res] = BuildSpiralOrder(res) end
	return spiralCache[res]
end

--- Start / continue amortized heightfield job. Budget traces per call.
local function SampleBuildingMap(ply, range)
	if not cv_radar_buildings:GetBool() then
		bmap.job = nil
		return
	end
	if not IsValid(ply) then return end
	range = math.Clamp(range or 1500, 400, 4000)
	local depthUp, depthDown, buildMin, buildMax = RadarDepthParams()
	local origin = ply:GetPos()
	local fn = FrameNumber and FrameNumber() or 0
	local res = BmapRes()
	local job = bmap.job

	-- Restart job if parameters diverged mid-fill
	if job then
		if math.abs((job.range or 0) - range) > 64
			or math.abs(origin.z - (job.playerZ or origin.z)) > 48
			or job.res ~= res then
			job = nil
			bmap.job = nil
		end
	end

	-- Idle: only start a new pass when dirty / stale
	if not job then
		local moved = origin:DistToSqr(bmap.origin) > (160 * 160)
		local rangeChanged = math.abs((bmap.range or 0) - range) > 64
		local depthChanged = math.abs(origin.z - (bmap.playerZ or origin.z)) > 48
		local stale = (fn - (bmap.frame or 0)) > 90
		if bmap.ready and not moved and not rangeChanged and not depthChanged and not stale then
			bmap.playerZ = origin.z
			return
		end

		local step = (range * 2) / res
		local ox = math.floor(origin.x / step + 0.5) * step
		local oy = math.floor(origin.y / step + 0.5) * step
		local wx0 = ox - range + step * 0.5
		local wy0 = oy - range + step * 0.5
		local cellsNext = bmap.cellsNext
		local n = res * res
		for i = 1, n do cellsNext[i] = false end
		job = {
			res = res,
			range = range,
			step = step,
			wx0 = wx0,
			wy0 = wy0,
			ox = ox, oy = oy,
			playerZ = origin.z,
			bandTop = origin.z + depthUp,
			bandBot = origin.z - depthDown,
			buildMin = buildMin,
			buildMax = buildMax,
			order = SpiralOrder(res),
			cursor = 1,
			cellsNext = cellsNext,
			halfRes = res * 0.5,
		}
		bmap.job = job
	end

	trReuse.filter = ply
	local bandTop, bandBot = job.bandTop, job.bandBot
	local jBuildMin, jBuildMax = job.buildMin, job.buildMax
	local playerZ = job.playerZ
	local step, wx0, wy0 = job.step, job.wx0, job.wy0
	local resJ = job.res
	local halfRes = job.halfRes
	local halfRes2 = (halfRes + 0.75) * (halfRes + 0.75)
	local cellsNext = job.cellsNext
	local order = job.order
	local budget = BmapBudget()
	local cursor = job.cursor
	local n = #order

	while budget > 0 and cursor <= n do
		local cell = order[cursor]
		cursor = cursor + 1
		local ix = cell % resJ
		local iy = math.floor(cell / resJ)
		local cdx = (ix + 0.5) - halfRes
		local cdy = (iy + 0.5) - halfRes
		local idx = iy * resJ + ix + 1
		if (cdx * cdx + cdy * cdy) > halfRes2 then
			cellsNext[idx] = false
		else
			local wx = wx0 + ix * step
			local wy = wy0 + iy * step
			vStart.x, vStart.y, vStart.z = wx, wy, bandTop
			vEnd.x, vEnd.y, vEnd.z = wx, wy, bandBot
			local hit = util.TraceLine(trReuse)
			budget = budget - 1
			if hit.Hit and not hit.HitSky then
				local z = hit.HitPos.z
				local elev = z - playerZ
				if elev >= jBuildMin and elev <= jBuildMax then
					cellsNext[idx] = z
				else
					cellsNext[idx] = false
				end
			else
				cellsNext[idx] = false
			end
		end
	end
	job.cursor = cursor

	if cursor > n then
		-- Swap buffers (O(1) pointer swap) — keep last good map until then
		bmap.cells, bmap.cellsNext = job.cellsNext, bmap.cells
		bmap.frame = fn
		bmap.origin.x, bmap.origin.y, bmap.origin.z = job.ox, job.oy, job.playerZ
		bmap.playerZ = job.playerZ
		bmap.range = job.range
		bmap.res = job.res
		bmap.wx0, bmap.wy0, bmap.step = job.wx0, job.wy0, job.step
		bmap.buildMin, bmap.buildMax = job.buildMin, job.buildMax
		bmap.ready = true
		bmap.job = nil
	else
		bmap.playerZ = origin.z
	end
end

local function PaintBuildingMap(cx, cy, radius, yaw, range, origin)
	if not cv_radar_buildings:GetBool() then return end
	if not bmap.ready or not bmap.cells or not bmap.step or bmap.step <= 0 then return end
	local _, _, buildMin, buildMax = RadarDepthParams()
	local res = bmap.res or BmapRes()
	local step = bmap.step
	local wx0, wy0 = bmap.wx0, bmap.wy0
	local playerZ = origin.z
	local cellPx = math.max(2, math.floor((radius * 2 / res) + 0.5))
	local half = cellPx * 0.5
	local maxR = math.max(0, radius - half * 1.42 - 2)
	local maxR2 = maxR * maxR
	local cells = bmap.cells
	local refX, refY = origin.x, origin.y
	local tallSpan = math.max(1, buildMax - buildMin)
	-- Precompute yaw rotation (avoid Vector alloc per cell)
	local c, s = math.cos(math.rad(-yaw)), math.sin(math.rad(-yaw))
	local invRange = radius / math.max(range, 1)

	draw.NoTexture()

	for iy = 0, res - 1 do
		local wy = wy0 + iy * step - refY
		for ix = 0, res - 1 do
			local z = cells[iy * res + ix + 1]
			if z == false or z == nil then continue end
			local elev = z - playerZ
			if elev < buildMin or elev > buildMax then continue end

			local wx = wx0 + ix * step - refX
			local rx = wx * c - wy * s
			local ry = wx * s + wy * c
			local u = rx * invRange
			local v = (-ry) * invRange
			if (u * u + v * v) > maxR2 then continue end

			local t = math.Clamp((elev - buildMin) / tallSpan, 0, 1)
			surface.SetDrawColor(70 + t * 90, 85 + t * 70, 100 + t * 80, 200)
			surface.DrawRect(cx + u - half, cy + v - half, cellPx, cellPx)
		end
	end
end

-- Guard: never nest RenderView while stereo SBS RT is active (map-wide flicker).
-- Also restore fog / clip state — short radar zfar used to leak into eye views
-- and clip the whole world (player “render distance” collapse).
-- 3D capture state — dirty only when view actually changed
local radar3d = {
	frame = -999,
	origin = Vector(0, 0, 0),
	yaw = 0,
	range = 0,
}

local function CaptureRadar3D(ply, range)
	if not cv_radar_3d:GetBool() or not radarRT then return false end
	if not IsValid(ply) then return false end
	if g_VR and g_VR.stereoEye then return false end
	if g_VR and g_VR._renderingHudRT then return false end

	local pos = ply:GetPos()
	local yaw = RadarYaw(ply)
	local fn = FrameNumber and FrameNumber() or 0
	local interval = math.floor(math.Clamp(cv_radar_3d_interval:GetInt(), 10, 120))
	local moved = pos:DistToSqr(radar3d.origin) > (96 * 96)
	local yawChanged = math.abs(math.AngleDifference(yaw, radar3d.yaw)) > 8
	local rangeChanged = math.abs((radar3d.range or 0) - range) > 64
	local stale = (fn - (radar3d.frame or 0)) >= interval
	if not moved and not yawChanged and not rangeChanged and not stale then
		return true -- keep last photo
	end

	-- Higher camera so building roofs read clearly
	local height = math.Clamp(range * 1.1, 600, 3200)

	-- Snapshot fog so ortho capture cannot leave short fog end on the frame
	local fogMode, fogStart, fogEnd, fogMax, fr, fg, fb
	if render.GetFogMode then fogMode = render.GetFogMode() end
	if render.GetFogDistances then
		local a, b = render.GetFogDistances()
		fogStart, fogEnd = a, b
	end
	if render.GetFogColor then
		fr, fg, fb = render.GetFogColor()
	end
	if render.GetFogMaxDensity then fogMax = render.GetFogMaxDensity() end

	g_VR._radarCapturing = true
	render.PushRenderTarget(radarRT)
	render.Clear(8, 4, 6, 220, true, true)
	local ok = pcall(function()
		-- Kill fog for this pass so distant roofs stay visible
		if render.FogMode then render.FogMode(MATERIAL_FOG_NONE or 0) end
		if render.FogMaxDensity then render.FogMaxDensity(0) end
		-- Prefer engine RealRenderView if present (avoid portal wrappers)
		local rv = (isfunction(render.RealRenderView) and render.RealRenderView) or render.RenderView
		rv({
			origin = pos + Vector(0, 0, height),
			angles = Angle(90, yaw, 0),
			x = 0, y = 0, w = RADAR_RT_SZ, h = RADAR_RT_SZ,
			aspectratio = 1,
			fov = 90,
			drawhud = false,
			drawmonitors = false,
			drawviewmodel = false,
			dopostprocess = false,
			bloomtone = false,
			ortho = true,
			ortholeft = -range,
			orthoright = range,
			orthotop = -range,
			orthobottom = range,
			znear = 8,
			zfar = height + range * 2.5,
		})
	end)
	render.PopRenderTarget()
	g_VR._radarCapturing = false

	-- Undo fog / density pollution from the short ortho pass
	pcall(function()
		if fogMode ~= nil and render.FogMode then render.FogMode(fogMode) end
		if fogStart ~= nil and render.FogStart then render.FogStart(fogStart) end
		if fogEnd ~= nil and render.FogEnd then render.FogEnd(fogEnd) end
		if fogMax ~= nil and render.FogMaxDensity then render.FogMaxDensity(fogMax) end
		if fr and render.FogColor then render.FogColor(fr, fg, fb) end
		if render.OverrideDepthEnable then render.OverrideDepthEnable(false, false) end
		if render.SetScissorRect then render.SetScissorRect(0, 0, 0, 0, false) end
		if render.DepthRange then render.DepthRange(0, 1) end
	end)

	if ok then
		radar3d.frame = fn
		radar3d.origin.x, radar3d.origin.y, radar3d.origin.z = pos.x, pos.y, pos.z
		radar3d.yaw = yaw
		radar3d.range = range
	end
	return ok
end

local function PaintRadar(w, h, T)
	if not cv_radar:GetBool() then return end
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local size = math.Clamp(cv_radar_size:GetInt(), 120, 320)
	local radius = size * 0.5 - 4
	local cx = w - size * 0.5 - 20
	local cy = size * 0.5 + 20
	local range = math.Clamp(cv_radar_range:GetFloat(), 400, 4000)
	local yaw = RadarYaw(ply)
	local origin = ply:GetPos()
	local cr = T.crimson or Color(196, 30, 58)
	local bg = T.bgGlass or T.bg or Color(12, 6, 10, 230)
	local muted = T.muted or Color(200, 150, 165)

	-- Optional 3D world backdrop (top-down ortho)
	local has3d = false
	if cv_radar_3d:GetBool() then
		-- Caller must leave 2D; CaptureRadar3D handles RT swap if invoked outside 2D.
		-- Here we only blit last frame if mat is ready — capture runs in CaptureHudRT.
		has3d = radarMat and not radarMat:IsError()
	end

	-- Circular plate (dark — buildings are slate blocks, not a pink flood)
	surface.SetDrawColor(bg.r, bg.g, bg.b, 235)
	draw.NoTexture()
	local segs = 48
	local platePoly = {}
	for i = 0, segs do
		local a = math.rad(i / segs * 360)
		platePoly[#platePoly + 1] = {
			x = cx + math.cos(a) * (radius + 4),
			y = cy + math.sin(a) * (radius + 4),
		}
	end
	surface.DrawPoly(platePoly)

	-- No stencil / color-write overrides (they leaked → flicker & full-red plate)

	if has3d then
		surface.SetMaterial(radarMat)
		surface.SetDrawColor(255, 255, 255, 140)
		-- Inscribed square (diagonal = diameter) so texture stays inside circle
		local half = radius / math.sqrt(2)
		surface.DrawTexturedRect(cx - half, cy - half, half * 2, half * 2)
		draw.NoTexture()
	end

	if cv_radar_buildings:GetBool() then
		pcall(PaintBuildingMap, cx, cy, radius, yaw, range, origin)
	end

	-- Grid rings + cross (CS-style)
	surface.SetDrawColor(cr.r, cr.g, cr.b, 90)
	for ring = 1, 3 do
		local rr = radius * (ring / 3)
		local prevx, prevy
		for i = 0, segs do
			local a = math.rad(i / segs * 360)
			local x, y = cx + math.cos(a) * rr, cy + math.sin(a) * rr
			if prevx then surface.DrawLine(prevx, prevy, x, y) end
			prevx, prevy = x, y
		end
	end
	surface.SetDrawColor(cr.r, cr.g, cr.b, 120)
	surface.DrawLine(cx - radius, cy, cx + radius, cy)
	surface.DrawLine(cx, cy - radius, cx, cy + radius)

	-- Outer ring
	surface.SetDrawColor(cr.r, cr.g, cr.b, 220)
	local prevx, prevy
	for i = 0, segs do
		local a = math.rad(i / segs * 360)
		local x, y = cx + math.cos(a) * (radius + 3), cy + math.sin(a) * (radius + 3)
		if prevx then surface.DrawLine(prevx, prevy, x, y) end
		prevx, prevy = x, y
	end

	-- Local player triangle (always center, facing up = look dir)
	local tri = {
		{ x = cx, y = cy - 9 },
		{ x = cx - 7, y = cy + 7 },
		{ x = cx + 7, y = cy + 7 },
	}
	surface.SetDrawColor(T.crimsonHot or Color(255, 80, 110))
	surface.DrawPoly(tri)
	surface.SetDrawColor(255, 255, 255, 200)
	surface.DrawLine(tri[1].x, tri[1].y, tri[2].x, tri[2].y)
	surface.DrawLine(tri[2].x, tri[2].y, tri[3].x, tri[3].y)
	surface.DrawLine(tri[3].x, tri[3].y, tri[1].x, tri[1].y)

	-- Player radar blips (same depth band — hide surface players when underground)
	local myTeam = ply:Team()
	local _, _, _, _, plyDepthMax = RadarDepthParams()
	for _, p in ipairs(player.GetAll()) do
		if not IsValid(p) or p == ply then continue end
		if not p:Alive() then continue end
		local ppos = p:GetPos()
		local dz = ppos.z - origin.z
		if math.abs(dz) > plyDepthMax then continue end
		local delta = ppos - origin
		local dist = delta:Length2D()
		if dist > range then continue end
		local u, v = WorldToRadar(delta, yaw, range, radius)
		local bx, by = cx + u, cy + v
		local d2 = u * u + v * v
		if d2 > radius * radius then
			local s = radius / math.sqrt(d2)
			bx, by = cx + u * s, cy + v * s
		end
		local same = (p:Team() == myTeam)
		local col = same and Color(100, 200, 255, 255) or Color(255, 90, 90, 255)
		-- height cue within band: above = ring, below = darker
		local r = 5
		if dz > 48 then
			surface.SetDrawColor(col.r, col.g, col.b, 255)
			surface.DrawOutlinedRect(bx - r - 1, by - r - 1, (r + 1) * 2, (r + 1) * 2, 2)
		elseif dz < -48 then
			surface.SetDrawColor(col.r * 0.55, col.g * 0.55, col.b * 0.55, 255)
			surface.DrawRect(bx - r, by - r, r * 2, r * 2)
		else
			surface.SetDrawColor(col.r, col.g, col.b, 255)
			surface.DrawRect(bx - r, by - r, r * 2, r * 2)
		end
	end

	local fontS = (vrmod.cube and vrmod.cube.Font and vrmod.cube.Font("CubeSmall")) or "DermaDefault"
	draw.SimpleText("RADAR", fontS, cx, cy + radius + 10, muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end

--- Theme-matched vitals only (one layer — not a full desktop HUD clone)
local function PaintVitals(w, h)
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local T = (vrmod.cube and vrmod.cube.ThemeLive and vrmod.cube.ThemeLive())
		or (vrmod.cube and vrmod.cube.Theme)
		or {}
	local M = (vrmod.cube and vrmod.cube.Metrics and vrmod.cube.Metrics()) or { hudScale = 1, pad = 16 }
	local hudS = M.hudScale or 1
	local outline = T.outline or Color(0, 0, 0, 220)
	-- Density-scaled fonts (RefreshFonts already sizes CubeHuge/Label)
	local fontV = (vrmod.cube and vrmod.cube.Font and vrmod.cube.Font("CubeHuge")) or "DermaLarge"
	local fontL = (vrmod.cube and vrmod.cube.Font and vrmod.cube.Font("CubeSmall")) or "DermaDefaultBold"
	local muted = T.muted or Color(200, 150, 165, 230)
	local baseY = h - math.floor(48 * hudS)
	local labelY = h - math.floor(24 * hudS)
	local xHp = math.floor(32 * hudS)
	local xSuit = math.floor(160 * hudS)
	local xAm = w - math.floor(32 * hudS)

	local hp = math.max(0, math.floor(ply:Health() or 0))
	local suit = GetSuitEnergy(ply)
	-- Vitals share accent: ammo matches health (not white-vs-crimson mismatch)
	local colHealth = T.health or T.crimsonHot or T.crimson or Color(255, 80, 110, 255)
	local colLow = T.healthLow or Color(255, 45, 70, 255)
	local colSuit = T.armor or T.muted or Color(200, 150, 165, 255)
	local colAmmo = T.ammo or T.health or T.crimsonHot or colHealth
	local hpCol = hp <= 25 and colLow or colHealth
	local suitCol = suit <= 0 and muted or colSuit

	draw.SimpleTextOutlined(tostring(hp), fontV, xHp, baseY, hpCol,
		TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 2, outline)
	draw.SimpleTextOutlined("HEALTH", fontL, xHp, labelY, muted,
		TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 1, outline)

	-- Armor only (hide when 0 — no fake AUX 100)
	if suit > 0 then
		draw.SimpleTextOutlined(tostring(suit), fontV, xSuit, baseY, suitCol,
			TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 2, outline)
		draw.SimpleTextOutlined("SUIT", fontL, xSuit, labelY, muted,
			TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 1, outline)
	end

	local wep = ply:GetActiveWeapon()
	if IsValid(wep) then
		local clip, ammo = -1, -1
		if vrmod.utils and vrmod.utils.GetWeaponAmmoDisplay then
			clip, ammo = vrmod.utils.GetWeaponAmmoDisplay(wep, ply)
		else
			clip = wep.Clip1 and (wep:Clip1() or -1) or -1
			local at = wep.GetPrimaryAmmoType and wep:GetPrimaryAmmoType() or -1
			if isnumber(at) and at >= 0 then ammo = ply:GetAmmoCount(at) or 0 end
		end
		local line
		if clip >= 0 and ammo >= 0 then
			line = string.format("%d  |  %d", clip, ammo)
		elseif clip >= 0 then
			line = tostring(clip)
		elseif ammo >= 0 then
			line = tostring(ammo)
		end
		if line then
			draw.SimpleTextOutlined(line, fontV, xAm, baseY, colAmmo,
				TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM, 2, outline)
			draw.SimpleTextOutlined("AMMO", fontL, xAm, labelY, muted,
				TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM, 1, outline)
		end
	end

	pcall(PaintRadar, w, h, T)
end

local function CaptureHudRT(w, h, pScale)
	render.PushRenderTarget(rt)
	render.OverrideAlphaWriteEnable(true, true)
	render.Clear(0, 0, 0, 0, true, true)

	local oldX, oldY, oldW, oldH = 0, 0, ScrW(), ScrH()
	if render.GetViewPort then
		oldX, oldY, oldW, oldH = render.GetViewPort()
	end
	render.SetViewPort(0, 0, w, h)

	cam.Start2D()

	local bgA = math.Clamp(CVFloat("vrmod_hudtestalpha", 0), 0, 255)
	if bgA > 0 then
		surface.SetDrawColor(0, 0, 0, bgA)
		surface.DrawRect(0, 0, w, h)
	end

	g_VR._renderingHudRT = true
	-- Optional engine HUD only if explicitly enabled (avoids loose desktop HUD copy)
	if cv_engine:GetBool() then
		pcall(render.RenderHUD, 0, 0, w, h)
	end

	-- Radar 3D is captured on VRMod_PreStereoCapture (no nested RenderView here).
	-- PaintVitals / blips run every stereo frame for realtime HUD.

	pcall(PaintVitals, w, h)
	-- Optional aim reticle: weapon muzzle / hand aim projected onto plate
	pcall(PaintAimCrosshair, w, h, pScale or plateScale)
	g_VR._renderingHudRT = false

	cam.End2D()

	render.SetViewPort(oldX, oldY, oldW, oldH)
	render.OverrideAlphaWriteEnable(false)
	render.PopRenderTarget()
end

local function DrawHudMesh()
	if not hudBound or not hudMesh or not mat or mat:IsError() then return end
	if not g_VR or not g_VR.active then return end
	if not g_VR.tracking or not g_VR.tracking.hmd then return end
	if not CVBool("vrmod_hud", true) then return end

	mat:SetTexture("$basetexture", rt)
	mat:SetInt("$translucent", 1)
	mat:SetInt("$additive", 0)
	render.SetMaterial(mat)
	cam.PushModelMatrix(mtx)
	render.DepthRange(0, 0.01)
	hudMesh:Draw()
	render.DepthRange(0, 1)
	cam.PopModelMatrix()
end

-- If an ancient bind ever stashed a wrap, restore via this upvalue only.
-- NEVER index VRUtilRenderMenuSystem as a table (it is a function → Lua error).
local menuSystemBase = nil

local function Unbind()
	hook.Remove("VRMod_PreStereoCapture", "vrmod_radar_3d")
	hook.Remove("VRMod_PreStereoCapture", "vrmod_radar_world")
	hook.Remove("VRMod_PreStereo", "vrmod_hud_capture")
	hook.Remove("VRMod_PreRender", "vrmod_hud_capture")
	hook.Remove("VRMod_PreRender", "hud")
	hook.Remove("VRMod_PreRender", "vrmod_hud_rt")
	hook.Remove("PostDrawTranslucentRenderables", "vrmod_hud_draw")
	hook.Remove("HUDShouldDraw", "vrmod_hud")
	hook.Remove("HUDShouldDraw", "vrmod_hud_bl")
	-- Safe unwrap: only restore if we own a base function reference
	if isfunction(menuSystemBase) and isfunction(VRUtilRenderMenuSystem) then
		VRUtilRenderMenuSystem = menuSystemBase
	end
	menuSystemBase = nil
	hudBound = false
end

local function Bind()
	Unbind()
	if not g_VR or not g_VR.active then return end
	if not CVBool("vrmod_hud", true) then return end

	if vrScrW:GetInt() < 64 then vrScrW:SetInt(math.max(ScrW(), 1280)) end
	if vrScrH:GetInt() < 64 then vrScrH:SetInt(math.max(ScrH(), 720)) end

	local w, h = HudRes()
	if w ~= rtW or h ~= rtH or not rt then
		rtW, rtH = w, h
		rt = GetRenderTarget("vrmod_hud_paint", rtW, rtH, false)
	end
	if mat and not mat:IsError() then
		mat:SetTexture("$basetexture", rt)
	end

	local scale = math.Clamp(CVFloat("vrmod_hudscale", 0.05), 0.02, 0.12)
	plateScale = scale
	local curve = CVFloat("vrmod_hudcurve", 60)
	local meshName = string.format("%.4f_%.1f_%d_%d", scale, curve, w, h)

	local build = Matrix()
	build:Translate(Vector(0, 0, h * scale / 2))
	build:Rotate(Angle(0, -90, -90))
	if not hudMeshes[meshName] then
		hudMeshes[meshName] = CurvedPlane(w * scale, h * scale, 10, curve, build)
	end
	hudMesh = hudMeshes[meshName]

	local blacklist = {}
	for _, v in ipairs(string.Explode(",", CVString("vrmod_hudblacklist", ""))) do
		if #v > 0 then blacklist[v] = true end
	end
	if next(blacklist) then
		hook.Add("HUDShouldDraw", "vrmod_hud_bl", function(name)
			if blacklist[name] then return false end
		end)
	end

	-- Radar world data BEFORE stereo RT is pushed (see cl_vrmod).
	-- Buildings: time-sliced TraceLine budget. 3D: dirty + interval (never every frame).
	hook.Add("VRMod_PreStereoCapture", "vrmod_radar_world", function()
		if not g_VR or not g_VR.active then return end
		if not cv_radar:GetBool() then return end
		local ply = LocalPlayer()
		if not IsValid(ply) then return end
		local range = math.Clamp(cv_radar_range:GetFloat(), 400, 4000)
		if cv_radar_buildings:GetBool() then
			pcall(SampleBuildingMap, ply, range)
		end
		if cv_radar_3d:GetBool() then
			pcall(CaptureRadar3D, ply, range)
		end
	end)

	-- Capture HUD RT once per stereo frame BEFORE stereo RT push (Cube: no nested RT under g_VR.rt).
	-- Pose freeze still on PreStereo so it shares the same hand/HMD snap as menus.
	hook.Add("VRMod_PreStereoCapture", "vrmod_hud_capture", function()
		if not g_VR.active or not CVBool("vrmod_hud", true) then return end
		if not g_VR.tracking or not g_VR.tracking.hmd then return end

		hook.Call("VRMod_PreRenderHUD", nil)

		local rw, rh = HudRes()
		if rw ~= rtW or rh ~= rtH then
			rtW, rtH = rw, rh
			rt = GetRenderTarget("vrmod_hud_paint", rtW, rtH, false)
			if mat then mat:SetTexture("$basetexture", rt) end
		end

		pcall(CaptureHudRT, rtW, rtH, plateScale)
		captureN = captureN + 1

		hook.Call("VRMod_PostRenderHUD", nil)
	end)

	-- Freeze plate pose once for both eyes (after stereoPose hands are frozen)
	hook.Add("VRMod_PreStereo", "vrmod_hud_pose", function()
		if not g_VR.active or not CVBool("vrmod_hud", true) then return end
		if not g_VR.tracking or not g_VR.tracking.hmd then return end
		mtx:Identity()
		mtx:Translate(g_VR.tracking.hmd.pos + g_VR.tracking.hmd.ang:Forward() * CVFloat("vrmod_huddistance", 60))
		mtx:Rotate(g_VR.tracking.hmd.ang)
	end)

	-- SINGLE draw path (both eyes) — same RT + same mtx every eye
	hook.Add("PostDrawTranslucentRenderables", "vrmod_hud_draw", function(depth, sky)
		if depth or sky then return end
		if not g_VR or not g_VR.active or not g_VR.stereoEye then return end
		if g_VR._radarCapturing then return end
		pcall(DrawHudMesh)
	end, 50)

	hudBound = true
	if vrmod.logger then
		vrmod.logger.Info("[vrmod_hud] single-plate vitals rt=%dx%d engine=%s", rtW, rtH, cv_engine:GetBool())
	end
end

local function toboolStrict(val)
	if val == true or val == 1 then return true end
	if val == false or val == 0 or val == nil then return false end
	local s = tostring(val):lower()
	if s == "0" or s == "false" or s == "no" or s == "" then return false end
	return true
end

vrmod.AddCallbackedConvar("vrmod_hud", nil, "1", FCVAR_ARCHIVE, "Draw VR world HUD", nil, nil, toboolStrict, function()
	Bind()
end)
vrmod.AddCallbackedConvar("vrmod_hudblacklist", nil, "", FCVAR_ARCHIVE, nil, nil, nil, nil, Bind)
vrmod.AddCallbackedConvar("vrmod_hudcurve", nil, "60", FCVAR_ARCHIVE, nil, nil, nil, tonumber, Bind)
vrmod.AddCallbackedConvar("vrmod_hudscale", nil, "0.05", FCVAR_ARCHIVE, nil, nil, nil, tonumber, Bind)
vrmod.AddCallbackedConvar("vrmod_huddistance", nil, "60", FCVAR_ARCHIVE, nil, nil, nil, tonumber)
vrmod.AddCallbackedConvar("vrmod_hudtestalpha", nil, "0", FCVAR_ARCHIVE, "Dim plate 0-255 (0=clear)", nil, nil, tonumber)

function vrmod.RefreshHUD()
	Bind()
end

function vrmod.IsHUDActive()
	return hudBound and CVBool("vrmod_hud", true)
end

hook.Add("VRMod_Start", "vrmod_hud", function(ply)
	if ply ~= LocalPlayer() then return end
	timer.Simple(0, function() if g_VR and g_VR.active then Bind() end end)
	timer.Simple(0.35, function() if g_VR and g_VR.active and CVBool("vrmod_hud", true) then Bind() end end)
end)

hook.Add("VRMod_Exit", "vrmod_hud", function(ply)
	if ply ~= LocalPlayer() then return end
	Unbind()
end)

concommand.Add("vrmod_hud_status", function()
	vrmod.logger.Info(
		"[vrmod_hud] bound=%s captures=%s rt=%sx%s engine=%s single_draw=1",
		hudBound, captureN, rtW, rtH, cv_engine:GetBool()
	)
end)

concommand.Add("vrmod_hud_rebind", function()
	RunConsoleCommand("vrmod_hud", "1")
	local c = GetConVar("vrmod_hud")
	if c then pcall(function() c:SetInt(1) end) end
	-- Force off engine HUD clone unless user wants it
	if not cv_engine:GetBool() then cv_engine:SetInt(0) end
	Bind()
	vrmod.logger.Info("[vrmod_hud] rebound — one plate, vitals only")
end)

concommand.Add("vrmod_hud_on", function()
	RunConsoleCommand("vrmod_hud", "1")
	local c = GetConVar("vrmod_hud")
	if c then pcall(function() c:SetInt(1) end) end
	Bind()
end)
