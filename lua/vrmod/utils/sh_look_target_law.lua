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

--- Matches the close sphere in FindPickupTarget (bestDist <= 18).
--- A hand result inside this radius is never replaced by gaze.
function vrmod.utils.LookTarget_CloseRadius()
	return 18
end

--- True only when the hand is strictly closer to the object than the HMD position.
--- Missing or non-finite distances are not "closer".
function vrmod.utils.LookTarget_HandCloserThanHmd(handDist, hmdDist)
	handDist = tonumber(handDist)
	hmdDist = tonumber(hmdDist)
	if not finite(handDist) or not finite(hmdDist) then return false end
	return handDist < hmdDist
end

--- Same weapon exceptions as FindPickupTarget.
--- A dropped gun of the class you are holding is not a second copy.
--- The right hand does not take a weapon while a weapon is already out.
function vrmod.utils.LookTarget_AllowHeldWeapon(isWeapon, sameClass, leftHand, holdingWeapon)
	local function on(v)
		return v == true or v == 1 or v == "1"
	end
	if not on(isWeapon) then return true end
	if on(sameClass) then return false end
	if not on(leftHand) and on(holdingWeapon) then return false end
	return true
end

--- Which entity a grip should grab.
--- Close-hand results stay. Gaze is the choice only while this hand is not
--- closer to the looked-at object than the HMD position is.
--- opts.hand_ent, hand_dist, eye_ent, eye_enabled, hand_to_eye, hmd_to_eye, close_radius.
--- Returns { source = "hand"|"eye"|"none", reason, ent }.
function vrmod.utils.LookTarget_ChoosePickup(opts)
	opts = type(opts) == "table" and opts or {}
	local closeR = tonumber(opts.close_radius)
	if not finite(closeR) or closeR < 0 then
		closeR = vrmod.utils.LookTarget_CloseRadius()
	end
	local handEnt = opts.hand_ent
	if handEnt == false then handEnt = nil end
	local eyeEnt = opts.eye_ent
	if eyeEnt == false then eyeEnt = nil end
	local handDist = tonumber(opts.hand_dist)
	local eyeOn = opts.eye_enabled == true or opts.eye_enabled == 1 or opts.eye_enabled == "1"

	-- Unknown distance: keep the hand result so a near grab is not replaced.
	if handEnt ~= nil and not finite(handDist) then
		return { source = "hand", reason = "hand_unmeasured", ent = handEnt }
	end
	if handEnt ~= nil and handDist <= closeR then
		return { source = "hand", reason = "close_hand", ent = handEnt }
	end

	if eyeOn and eyeEnt ~= nil then
		if vrmod.utils.LookTarget_HandCloserThanHmd(opts.hand_to_eye, opts.hmd_to_eye) then
			if handEnt ~= nil then
				return { source = "hand", reason = "hand_closer", ent = handEnt }
			end
			return { source = "none", reason = "hand_closer", ent = nil }
		end
		return { source = "eye", reason = "eye", ent = eyeEnt }
	end

	if handEnt ~= nil then
		return { source = "hand", reason = "hand", ent = handEnt }
	end
	return { source = "none", reason = "none", ent = nil }
end
