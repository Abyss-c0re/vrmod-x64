-- When a hand hull may be traced again.
-- Jump still traces (vertical speed or a just-pressed jump). A second call
-- in the same frame must not trace that hull again. Climb grip and
-- floor/ceiling rejection stay in the caller — this helper does not see them.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

--- Hand sample movement below this (units) can reuse the last hull.
function vrmod.utils.HandRetrace_MoveUnits()
	return 1.5
end

--- |player velocity.z| at or above this is a jump / fast fall, not a bob.
--- Default jump power is 200; walk bob stays under this.
function vrmod.utils.HandRetrace_VertUnits()
	return 120
end

--- How many frames a cached hull may be reused. One, then trace again.
function vrmod.utils.HandRetrace_ReuseFrames()
	return 1
end

--- Wrist / gun rotation (degrees) that counts as a new pose even if the
--- sample point barely moved. Nil ang_deg ignores rotation.
function vrmod.utils.HandRetrace_AngDegrees()
	return 4
end

--- Pure: true = trace, false = reuse the last hull result.
--- opts:
---   moved        number  units the pose sample moved since the cached trace
---   vert_speed   number  player velocity.z (sign ignored). nil = unknown
---   frame_age    number  frames since the cached trace. 0 = already this frame
---   jump_pressed bool    IN_JUMP / boolean_jump just pressed
---   same_frame   bool    this hull was already traced this frame
---   has_cache    bool    a previous hull result exists
---   ang_deg      number  optional pose angle change since the cache
function vrmod.utils.HandRetrace_Should(opts)
	opts = type(opts) == "table" and opts or {}
	local has = opts.has_cache and true or false
	if opts.same_frame and has then
		return false
	end
	if not has then
		return true
	end
	local age = tonumber(opts.frame_age)
	if age == nil then
		return true
	end
	if age < 0 then
		return true
	end
	if age == 0 then
		return false
	end
	if age > vrmod.utils.HandRetrace_ReuseFrames() then
		return true
	end
	if opts.jump_pressed then
		return true
	end
	if opts.vert_speed == nil then
		return true
	end
	local vz = tonumber(opts.vert_speed)
	if vz == nil then
		return true
	end
	if vz < 0 then
		vz = -vz
	end
	if vz >= vrmod.utils.HandRetrace_VertUnits() then
		return true
	end
	local ang = tonumber(opts.ang_deg)
	if ang ~= nil then
		if ang < 0 then
			ang = -ang
		end
		if ang >= vrmod.utils.HandRetrace_AngDegrees() then
			return true
		end
	end
	local moved = tonumber(opts.moved)
	if moved == nil then
		return true
	end
	if moved < 0 then
		moved = -moved
	end
	if moved >= vrmod.utils.HandRetrace_MoveUnits() then
		return true
	end
	return false
end
