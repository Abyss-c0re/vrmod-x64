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
	if not isfunction(vrmod.GetEyeGaze) then return nil, nil, "no_api" end
	local pos, ang = vrmod.GetEyeGaze(ply)
	if not pos or not ang or not isfunction(ang.Forward) then return nil, nil, "no_gaze" end
	return vrmod.utils.LookTarget_QueryPose(ply, pos, ang, maxDist)
end

--- Same trace as LookTarget_Query, from an explicit pose. Used when gaze has no sample.
function vrmod.utils.LookTarget_QueryPose(ply, pos, ang, maxDist)
	maxDist = tonumber(maxDist)
	if not finite(maxDist) or maxDist <= 0 then return nil, nil, "range" end
	if ply ~= nil and isfunction(IsValid) and not IsValid(ply) then return nil, nil, "no_player" end
	if not pos or not ang or not isfunction(ang.Forward) then return nil, nil, "no_gaze" end
	local dir = ang:Forward()
	if not dir then return nil, nil, "no_dir" end
	if not util or not isfunction(util.TraceLine) then return nil, nil, "no_trace" end

	-- Same polarity as the laser: true = hit, false = skip.
	-- Invalid ents return true so a nil callback does not abort the ray.
	local filter = function(ent)
		if not isfunction(IsValid) or not IsValid(ent) then return true end
		if ent == ply then return false end
		if isWorld(ent) then return true end
		local held = false
		local viewmodel = false
		if g_VR then
			held = ent == g_VR.heldEntityLeft or ent == g_VR.heldEntityRight
			viewmodel = ent == g_VR.viewModel or ent == g_VR.worldModelVM
		end
		local isWep = ent.IsWeapon and ent:IsWeapon() or false
		local ownerSelf = false
		if isWep and ply ~= nil and ent.GetOwner then
			ownerSelf = ent:GetOwner() == ply
		end
		local isMag = vrmod.utils.IsMagazine and vrmod.utils.IsMagazine(ent) or false
		-- Hand HitFilter skips every weapon so the gun mesh does not block the
		-- hand. A dropped gun is a gaze target. The equipped gun is not.
		local filterHit = true
		if not isWep and not isMag and vrmod.utils.HitFilter then
			filterHit = vrmod.utils.HitFilter(ent, ply) and true or false
		end
		if vrmod.utils.LookTarget_GazeHits then
			return vrmod.utils.LookTarget_GazeHits({
				is_player = ent == ply,
				is_held = held,
				is_viewmodel = viewmodel,
				is_weapon = isWep,
				owner_is_self = ownerSelf,
				is_magazine = isMag,
				hit_filter = filterHit,
			})
		end
		if ent == ply or held or viewmodel then return false end
		if isWep then return not ownerSelf end
		if isMag then return true end
		return filterHit
	end

	local lead = vrmod.utils.LookTarget_EyeLead()
	local function traceFrom(startPos)
		local ok, tr = pcall(util.TraceLine, {
			start = startPos,
			endpos = pos + dir * maxDist,
			filter = filter,
			mask = MASK_SHOT,
		})
		if not ok or type(tr) ~= "table" then return nil end
		return tr
	end

	-- Eyes sit inside the head hull. A ray from the gaze origin hits the
	-- player and stops. Step forward, and step again if that sample is us.
	local tr = traceFrom(pos + dir * lead)
	if tr and (tr.StartSolid or tr.Entity == ply) then
		tr = traceFrom(pos + dir * (lead * 3))
	end
	if not tr then return nil, nil, "no_trace" end

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
--- This is not the pickup gate. Controllers rest in front of the head, so a
--- raw hand-vs-HMD test is true for almost every prop in view.
function vrmod.utils.LookTarget_HandCloserThanHmd(handDist, hmdDist)
	handDist = tonumber(handDist)
	hmdDist = tonumber(hmdDist)
	if not finite(handDist) or not finite(hmdDist) then return false end
	return handDist < hmdDist
end

--- Inches to step the look ray out of the head hull before tracing.
function vrmod.utils.LookTarget_EyeLead()
	return 8
end

--- Inches. A dropped gun this close to the gaze ray wins over the fat prop the ray hit.
function vrmod.utils.LookTarget_FocusRadius()
	return 12
end

--- true = the gaze ray hits this entity. false = skip it.
--- Dropped weapons and magazines are targets. The weapon in the player's
--- hands is not. opts: is_player, is_held, is_viewmodel, is_weapon,
--- owner_is_self, is_magazine, hit_filter (false = some other filter skipped it).
function vrmod.utils.LookTarget_GazeHits(opts)
	opts = type(opts) == "table" and opts or {}
	local function on(v)
		return v == true or v == 1 or v == "1"
	end
	if on(opts.is_player) or on(opts.is_held) or on(opts.is_viewmodel) then return false end
	if on(opts.is_weapon) then
		if on(opts.owner_is_self) then return false end
		return true
	end
	if on(opts.is_magazine) then return true end
	if opts.hit_filter == false or opts.hit_filter == 0 or opts.hit_filter == "0" then return false end
	return true
end

--- Choose the entity under the gaze when a thin weapon sits against a fat prop.
--- The ray can hit the prop and miss the gun. An important candidate within
--- the focus radius, and not buried behind the hit, replaces that prop.
--- opts.hit_ent, hit_along, radius, candidates = { ent, along, radial, important }.
--- Returns ent, reason ("focus_important"|"focus"|"hit"|"none").
function vrmod.utils.LookTarget_Prefer(opts)
	opts = type(opts) == "table" and opts or {}
	local radius = tonumber(opts.radius)
	if not radius or radius ~= radius or radius < 0 then
		radius = vrmod.utils.LookTarget_FocusRadius()
	end
	local hitAlong = tonumber(opts.hit_along)
	local best, bestRadial, bestAlong, bestImportant = nil, math.huge, math.huge, false
	local list = opts.candidates
	if type(list) == "table" then
		for i = 1, #list do
			local c = list[i]
			if type(c) == "table" and c.ent ~= nil and c.ent ~= false then
				local radial = tonumber(c.radial)
				local along = tonumber(c.along)
				if radial and along and radial == radial and along == along and radial >= 0 and along >= 0 and radial <= radius then
					local buried = hitAlong and along > hitAlong + radius
					if not buried then
						local important = c.important == true or c.important == 1 or c.important == "1"
						local better = false
						if best == nil then
							better = true
						elseif important and not bestImportant then
							better = true
						elseif important == bestImportant then
							if radial < bestRadial - 0.5 or (math.abs(radial - bestRadial) <= 0.5 and along < bestAlong) then
								better = true
							end
						end
						if better then
							best = c.ent
							bestRadial = radial
							bestAlong = along
							bestImportant = important
						end
					end
				end
			end
		end
	end
	if best ~= nil then
		return best, bestImportant and "focus_important" or "focus"
	end
	if opts.hit_ent ~= nil and opts.hit_ent ~= false then
		return opts.hit_ent, "hit"
	end
	return nil, "none"
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

--- Inches. A hand this close to a surface is touching it.
--- The old 18-unit "close" sphere is a search bubble, not contact.
--- A controller held in front of the body sits inside that bubble and was
--- stealing the gaze target on the right hand.
function vrmod.utils.LookTarget_TouchDistance()
	return 6
end

function vrmod.utils.LookTarget_IsTouch(dist, touchDist)
	dist = tonumber(dist)
	touchDist = tonumber(touchDist)
	if not finite(touchDist) or touchDist < 0 then
		touchDist = vrmod.utils.LookTarget_TouchDistance()
	end
	if not finite(dist) then return false end
	return dist <= touchDist
end

--- 0 / "hand" → hand proximity. 1 / "eye" → eye gazing. Anything else is hand.
function vrmod.utils.LookTarget_SourceMode(v)
	if v == "eye" or v == 1 or v == "1" or v == true then return "eye" end
	return "hand"
end

--- Which entity a grip should grab.
--- mode "eye" uses eye_ent while a gaze sample exists.
--- No sample (eye_sensor false) falls back to hand_ent.
--- touch_ent wins over both. That is the only override, and it is this hand
--- actually touching a prop, not merely being nearer than the head.
--- Returns { source = "touch"|"hand"|"eye"|"none", reason, ent }.
function vrmod.utils.LookTarget_ChoosePickup(opts)
	opts = type(opts) == "table" and opts or {}
	local function present(v)
		if v == nil or v == false then return nil end
		return v
	end
	local touchEnt = present(opts.touch_ent)
	if touchEnt ~= nil then
		return { source = "touch", reason = "touch", ent = touchEnt }
	end

	local mode = opts.mode
	if mode == nil and (opts.eye_enabled == true or opts.eye_enabled == 1 or opts.eye_enabled == "1") then
		mode = "eye"
	end
	mode = vrmod.utils.LookTarget_SourceMode(mode)

	local handEnt = present(opts.hand_ent)
	local eyeEnt = present(opts.eye_ent)
	local sensor = opts.eye_sensor
	if sensor == nil then sensor = true end
	if sensor == false or sensor == 0 or sensor == "0" then sensor = false else sensor = true end

	if mode == "eye" then
		if not sensor then
			if handEnt ~= nil then
				return { source = "hand", reason = "eye_fallback", ent = handEnt }
			end
			return { source = "none", reason = "eye_fallback", ent = nil }
		end
		if eyeEnt ~= nil then
			return { source = "eye", reason = "eye", ent = eyeEnt }
		end
		return { source = "none", reason = "eye", ent = nil }
	end

	if handEnt ~= nil then
		return { source = "hand", reason = "hand", ent = handEnt }
	end
	return { source = "none", reason = "none", ent = nil }
end

local function flagOn(v)
	return v == true or v == 1 or v == "1"
end

--- Map geometry is not a prop. Gaze and the hand share this.
--- opts.class (lowercase), is_world, solid_bsp, move_vphysics.
--- prop_static, doors, brushes, and a frozen prop_dynamic are map parts.
--- prop_physics stays a pickup even when the mapper froze it.
function vrmod.utils.PickupFilter_IsMapSolid(opts)
	opts = type(opts) == "table" and opts or {}
	if flagOn(opts.is_world) or flagOn(opts.solid_bsp) then return true end
	local class = type(opts.class) == "string" and opts.class:lower() or ""
	if class == "" then return false end
	if class == "worldspawn" or class == "prop_static" then return true end
	if class:sub(1, 5) == "func_" then return true end
	if class:sub(1, 9) == "prop_door" then return true end
	if class == "prop_dynamic" or class == "prop_dynamic_override" then
		return not flagOn(opts.move_vphysics)
	end
	return false
end

--- The seat, the hull it is parented to, a child of that hull, or g_VR.vehicle.current.
--- The occupied check is not only ply:GetVehicle(). Glide's seat is a pod; the mesh
--- the player looks at is the parent hull.
function vrmod.utils.PickupFilter_IsDriven(opts)
	opts = type(opts) == "table" and opts or {}
	if not flagOn(opts.in_vehicle) then return false end
	if flagOn(opts.is_seat) or flagOn(opts.is_seat_parent) or flagOn(opts.is_hull_child) or flagOn(opts.is_current) then
		return true
	end
	return false
end

--- Weight cap shared by hand and gaze.
--- limit 1 (the default) caps a KNOWN mass. A vehicle with no mass, or a
--- zero mass, counts as over the limit: that is the hull the client cannot weigh.
--- A normal prop with no client physics object stays selectable. Requiring a
--- client phys object blanked every prop, including one the hand was touching.
--- realm "server" still rejects a missing physics object, which is the old grab check.
function vrmod.utils.PickupFilter_MassOK(opts)
	opts = type(opts) == "table" and opts or {}
	local limit = tonumber(opts.limit)
	if limit == nil then limit = 1 end
	local server = opts.realm == "server"
	local vehicle = flagOn(opts.is_vehicle)
	if limit ~= 1 then
		if server and opts.has_phys == false then return false end
		return true
	end
	local mass = tonumber(opts.mass)
	local weight = tonumber(opts.weight)
	if weight == nil then weight = 150 end
	local known = opts.has_phys == true and mass ~= nil and mass == mass and mass > 0
	if vehicle then
		if not known or opts.move_vphysics == false then return false end
		return mass <= weight
	end
	if not known then
		if server then return false end
		return true
	end
	if server and opts.move_vphysics == false then return false end
	return mass <= weight
end

--- Hand and gaze share this. Driven vehicle loses even to a whitelist.
--- NPC mode and the whitelist still skip the mass cap, matching the server.
function vrmod.utils.PickupFilter_Allow(opts)
	opts = type(opts) == "table" and opts or {}
	if flagOn(opts.self_ent) then return false end
	if vrmod.utils.PickupFilter_IsDriven(opts) then return false end
	if flagOn(opts.is_npc) and tonumber(opts.npc_mode) == 1 then return true end
	if flagOn(opts.whitelisted) then return true end
	if flagOn(opts.blacklisted) then return false end
	return vrmod.utils.PickupFilter_MassOK(opts)
end

--- One outline when both hands share a target. Two passes on one model
--- wash orange then cyan into white, which read as a second confirmation.
--- mode: "one" | "both" | "left" | "right" | "none"
function vrmod.utils.PickupHalo_Plan(leftEnt, rightEnt)
	local hasL = leftEnt ~= nil and leftEnt ~= false
	local hasR = rightEnt ~= nil and rightEnt ~= false
	if hasL and hasR and leftEnt == rightEnt then
		return { mode = "one", shared = true }
	end
	if hasL and hasR then
		return { mode = "both", shared = false }
	end
	if hasL then return { mode = "left", shared = false } end
	if hasR then return { mode = "right", shared = false } end
	return { mode = "none", shared = false }
end
