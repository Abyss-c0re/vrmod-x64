-- Look target: the solid the player is looking at, and the exact point on it.
-- Pure selection takes a trace description so tests do not need the engine.
-- LookTarget_Query is the GMod trace along vrmod.GetEyeGaze.
-- Pickup may call this later. This file does not grab anything.
--
-- Range uses the same inches rule as hand pickup: slider * 12 * boost.
-- Boost is 5 for important items, 3 for NPCs, 1 otherwise (FindPickupTarget).
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

local RANGE_MAX = 32

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function coords(p)
	if type(p) ~= "table" then return nil end
	local x, y, z = tonumber(p.x), tonumber(p.y), tonumber(p.z)
	if not finite(x) or not finite(y) or not finite(z) then return nil end
	return x, y, z
end

local function pack(x, y, z)
	return { x = x, y = y, z = z }
end

function vrmod.utils.LookTarget_DefaultRange()
	return 12
end

--- Slider units, same family as vrmod_pickup_range. Non-finite → default.
--- 0 is a real value (nothing is in range). Above 32 clamps.
function vrmod.utils.LookTarget_ClampRange(v)
	v = tonumber(v)
	if not finite(v) then return vrmod.utils.LookTarget_DefaultRange() end
	if v < 0 then return 0 end
	if v > RANGE_MAX then return RANGE_MAX end
	return v
end

--- important beats npc, matching FindPickupTarget.
function vrmod.utils.LookTarget_Boost(important, npc)
	if important then return 5 end
	if npc then return 3 end
	return 1
end

function vrmod.utils.LookTarget_MaxDistance(range, boost)
	range = vrmod.utils.LookTarget_ClampRange(range)
	boost = tonumber(boost) or 1
	if not finite(boost) or boost < 1 then boost = 1 end
	if range <= 0 then return 0 end
	return range * 12 * boost
end

function vrmod.utils.LookTarget_Within(dist, range, boost)
	dist = tonumber(dist)
	if not finite(dist) or dist < 0 then return false end
	return dist <= vrmod.utils.LookTarget_MaxDistance(range, boost) + 1e-3
end

function vrmod.utils.LookTarget_Distance(a, b)
	local ax, ay, az = coords(a)
	local bx, by, bz = coords(b)
	if not ax or not bx then return nil end
	local dx, dy, dz = ax - bx, ay - by, az - bz
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- What the gaze ray hit.
--- opts.hit, hit_sky, ent (opaque or nil), pos, origin, dir, max_dist (source units).
--- Returns ent or nil, position {x,y,z} or nil, reason.
--- The position is a new table. Reasons: entity, world, sky, miss, past_range,
--- range, no_origin, no_dir, no_pos.
function vrmod.utils.LookTarget_Select(opts)
	opts = type(opts) == "table" and opts or {}
	local maxDist = tonumber(opts.max_dist)
	if not finite(maxDist) or maxDist <= 0 then
		return nil, nil, "range"
	end
	local ox, oy, oz = coords(opts.origin)
	if not ox then return nil, nil, "no_origin" end
	local dx, dy, dz = coords(opts.dir)
	if not dx then return nil, nil, "no_dir" end
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	if len < 1e-8 then return nil, nil, "no_dir" end
	dx, dy, dz = dx / len, dy / len, dz / len

	if opts.hit_sky then
		local px, py, pz = coords(opts.pos)
		return nil, px and pack(px, py, pz) or nil, "sky"
	end

	if not opts.hit then
		return nil, pack(ox + dx * maxDist, oy + dy * maxDist, oz + dz * maxDist), "miss"
	end

	local px, py, pz = coords(opts.pos)
	if not px then return nil, nil, "no_pos" end
	local dist = math.sqrt((px - ox) ^ 2 + (py - oy) ^ 2 + (pz - oz) ^ 2)
	if dist > maxDist + 0.05 then
		return nil, pack(px, py, pz), "past_range"
	end
	if opts.ent == nil or opts.ent == false then
		return nil, pack(px, py, pz), "world"
	end
	return opts.ent, pack(px, py, pz), "entity"
end

local function isWorld(ent)
	if ent == nil or ent == false then return true end
	if type(ent) ~= "table" then return false end
	if ent.IsWorld and ent:IsWorld() then return true end
	return false
end

--- Trace along the player's gaze. Returns the entity, a Vector hit point, and a reason.
--- World and sky are not objects: the entity is nil and the point is still returned
--- when the trace has one. A miss returns the point at max_dist along the look.
function vrmod.utils.LookTarget_Query(ply, maxDist)
	maxDist = tonumber(maxDist)
	if not finite(maxDist) or maxDist <= 0 then return nil, nil, "range" end
	if not isfunction(vrmod.GetEyeGaze) then return nil, nil, "no_api" end
	if ply ~= nil and isfunction(IsValid) and not IsValid(ply) then return nil, nil, "no_player" end
	local pos, ang = vrmod.GetEyeGaze(ply)
	if not pos or not ang or not isfunction(ang.Forward) then return nil, nil, "no_gaze" end
	local dir = ang:Forward()
	if not dir then return nil, nil, "no_dir" end
	if not util or not isfunction(util.TraceLine) then return nil, nil, "no_trace" end

	local filter = function(ent)
		if not isfunction(IsValid) or not IsValid(ent) then return false end
		if ent == ply then return false end
		if isWorld(ent) then return true end
		if g_VR then
			if ent == g_VR.heldEntityLeft or ent == g_VR.heldEntityRight then return false end
			if ent == g_VR.viewModel or ent == g_VR.worldModelVM then return false end
		end
		if vrmod.utils.HitFilter then
			return vrmod.utils.HitFilter(ent, ply) and true or false
		end
		return true
	end

	local ok, tr = pcall(util.TraceLine, {
		start = pos,
		endpos = pos + dir * maxDist,
		filter = filter,
		mask = MASK_SHOT,
	})
	if not ok or type(tr) ~= "table" then return nil, nil, "no_trace" end

	local ent = tr.Entity
	if not isfunction(IsValid) or not IsValid(ent) or ent == ply or isWorld(ent) then
		ent = nil
	end
	local hitPos = tr.HitPos
	local posTab = nil
	if hitPos and finite(tonumber(hitPos.x)) and finite(tonumber(hitPos.y)) and finite(tonumber(hitPos.z)) then
		posTab = { x = hitPos.x, y = hitPos.y, z = hitPos.z }
	end
	local chosen, look, reason = vrmod.utils.LookTarget_Select({
		hit = tr.Hit and true or false,
		hit_sky = tr.HitSky and true or false,
		ent = ent,
		pos = posTab,
		origin = { x = pos.x, y = pos.y, z = pos.z },
		dir = { x = dir.x, y = dir.y, z = dir.z },
		max_dist = maxDist,
	})
	local vec = nil
	if look and isfunction(Vector) then
		vec = Vector(look.x, look.y, look.z)
	end
	return chosen, vec, reason
end
