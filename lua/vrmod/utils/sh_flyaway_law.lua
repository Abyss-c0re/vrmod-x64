-- G34: fly-away / dead-input law (pure, offline-tested).
-- Watchlist W12: flying away on start / inputs dead.
-- Cube way: origin/seated offset + action sets.
-- Law:
--   default action set /actions/main (or /actions/driving in vehicle) before first input
--   if |vertical head vel| insane early after start → snap origin to player feet (once)
--   never dual-origin thrash every frame; one-shot snap only
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

function vrmod.utils.FlyAwayLaw_ActionSetMain()
	return "/actions/main"
end

function vrmod.utils.FlyAwayLaw_ActionSetDriving()
	return "/actions/driving"
end

function vrmod.utils.FlyAwayLaw_ActionSetBase()
	return "/actions/base"
end

--- Pure: which gameplay action set for start / seat.
function vrmod.utils.FlyAwayLaw_ResolveActionSet(inVehicle)
	if inVehicle then
		return vrmod.utils.FlyAwayLaw_ActionSetDriving()
	end
	return vrmod.utils.FlyAwayLaw_ActionSetMain()
end

--- Source units/sec: vertical component beyond this is "insane" (fly-away).
function vrmod.utils.FlyAwayLaw_InsaneVerticalVel()
	return 1500
end

--- Horizontal magnitude beyond this also counts as fly-away (optional band).
function vrmod.utils.FlyAwayLaw_InsaneHorizontalVel()
	return 2500
end

--- Window after VR start (seconds) where snap is allowed.
function vrmod.utils.FlyAwayLaw_StartWindowSec()
	return 3.0
end

--- Pure: abs(vel_z) over threshold?
function vrmod.utils.FlyAwayLaw_IsInsaneVertical(velZ)
	velZ = tonumber(velZ) or 0
	local lim = vrmod.utils.FlyAwayLaw_InsaneVerticalVel()
	if velZ < 0 then velZ = -velZ end
	return velZ > lim
end

function vrmod.utils.FlyAwayLaw_IsInsaneHorizontal(velX, velY)
	velX = tonumber(velX) or 0
	velY = tonumber(velY) or 0
	local mag = math.sqrt(velX * velX + velY * velY)
	return mag > vrmod.utils.FlyAwayLaw_InsaneHorizontalVel()
end

--- Pure: should one-shot snap origin?
--- opts: elapsed_sec, already_snapped, vel_z, vel_x, vel_y, has_player_pos
function vrmod.utils.FlyAwayLaw_ShouldSnapOrigin(opts)
	opts = type(opts) == "table" and opts or {}
	if opts.already_snapped then return false end
	if not opts.has_player_pos then return false end
	local t = tonumber(opts.elapsed_sec) or 0
	if t < 0 then t = 0 end
	if t > vrmod.utils.FlyAwayLaw_StartWindowSec() then return false end
	if vrmod.utils.FlyAwayLaw_IsInsaneVertical(opts.vel_z) then return true end
	if vrmod.utils.FlyAwayLaw_IsInsaneHorizontal(opts.vel_x, opts.vel_y) then return true end
	return false
end

--- Pure decision snapshot.
--- opts:
---   in_vehicle bool
---   action_set string|nil        currently active gameplay set
---   elapsed_sec number|nil
---   already_snapped bool|nil
---   vel_z, vel_x, vel_y number|nil
---   has_player_pos bool|nil
---   origin_set_to_feet bool|nil  SetupNetworkAndOrigin ran
function vrmod.utils.FlyAwayLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local want = vrmod.utils.FlyAwayLaw_ResolveActionSet(opts.in_vehicle and true or false)
	local active = opts.action_set and tostring(opts.action_set) or ""
	local shouldSnap = vrmod.utils.FlyAwayLaw_ShouldSnapOrigin({
		elapsed_sec = opts.elapsed_sec,
		already_snapped = opts.already_snapped,
		vel_z = opts.vel_z,
		vel_x = opts.vel_x,
		vel_y = opts.vel_y,
		has_player_pos = opts.has_player_pos,
	})
	local d = {
		valid = true,
		want_action_set = want,
		active_action_set = active,
		action_set_ok = (active == "" or active == want or active == vrmod.utils.FlyAwayLaw_ActionSetBase()),
		should_snap = shouldSnap,
		origin_set_to_feet = opts.origin_set_to_feet and true or false,
		risk = "none", -- none | dead_input | fly_away | no_origin | action_mismatch
		reason = "ok",
		path_ok = true,
	}
	if not d.origin_set_to_feet and opts.require_origin ~= false then
		-- soft when origin not yet set (still booting)
		if opts.origin_set_to_feet == false then
			d.risk = "no_origin"
			d.reason = "origin_not_feet"
			d.path_ok = false
		end
	end
	if shouldSnap then
		d.risk = "fly_away"
		d.reason = "insane_head_velocity_snap"
		d.path_ok = false -- until snap applied
	elseif active ~= "" and active ~= want and active ~= vrmod.utils.FlyAwayLaw_ActionSetBase() then
		d.risk = "action_mismatch"
		d.reason = "gameplay_action_set_wrong"
		d.action_set_ok = false
		d.path_ok = false
	elseif active == "" and opts.expect_action_set then
		d.risk = "dead_input"
		d.reason = "no_action_set_before_input"
		d.path_ok = false
	else
		d.reason = "origin_action_ok"
		d.path_ok = true
	end
	return d
end

function vrmod.utils.FlyAwayLaw_StatusLabel(decision)
	if type(decision) ~= "table" then return "FLY · IDLE" end
	if decision.risk == "fly_away" then return "FLY · SNAP ORIGIN" end
	if decision.risk == "dead_input" then return "FLY · DEAD INPUT" end
	if decision.risk == "action_mismatch" then return "FLY · ACTION MISMATCH" end
	if decision.risk == "no_origin" then return "FLY · NO ORIGIN" end
	if decision.path_ok then return "FLY · OK" end
	return "FLY · HOLD"
end

function vrmod.utils.FlyAwayLaw_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_stable_origin = true,
		expect_main_actions = true,
		checklist = "G34 · IDLE · no fly-away decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if decision.risk == "fly_away" then
		e.verdict = "expect_snap"
		e.expect_stable_origin = false
		e.checklist = "G34 · SNAP · insane head vel → origin to feet once"
		e.pass_line = "One snap; world stops flying; no every-frame thrash"
		e.fail_line = "Keep flying / origin thrash / never snap"
		return e
	end
	if decision.risk == "dead_input" or decision.risk == "action_mismatch" then
		e.verdict = "expect_dead_input"
		e.expect_main_actions = false
		e.checklist = "G34 · INPUT · " .. tostring(decision.reason)
		e.pass_line = "/actions/main (or driving) before first input frame"
		e.fail_line = "Controllers dead until rebind / restart"
		return e
	end
	if not decision.path_ok then
		e.verdict = "expect_origin_fail"
		e.checklist = "G34 · FAIL · " .. tostring(decision.reason)
		e.pass_line = "Origin at player feet on start"
		e.fail_line = "Spawn in sky / wrong floor"
		return e
	end
	e.verdict = "expect_ok"
	e.checklist = "G34 · OK · feet origin + " .. tostring(decision.want_action_set)
	e.pass_line = "Stable standing; stick/laser work first frames"
	e.fail_line = "Fly away or dead inputs on start"
	return e
end

function vrmod.utils.FlyAwayLaw_IsFlyAwayRisk(decision)
	if type(decision) ~= "table" then return true end
	return decision.risk == "fly_away" or decision.should_snap
end
