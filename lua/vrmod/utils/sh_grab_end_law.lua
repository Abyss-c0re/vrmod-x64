-- G44: grab-end / drop-cooldown law (pure, offline-tested).
-- Cube standard: no grab_end storms / left-trigger silence regressions.
-- Cube way:
--   short per-hand drop cooldown after VRMod_Drop (default 0.1s)
--   ignore re-grab storms while cooldown active
--   primary-hand left must not steal secondary/grab semantics
--   never rewrite climb grip path here (pain points)
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

function vrmod.utils.GrabEndLaw_CooldownSeconds()
	return 0.1
end

function vrmod.utils.GrabEndLaw_RequirePerHandCooldown()
	return true
end

function vrmod.utils.GrabEndLaw_AllowClimbRewrite()
	return false -- pain: climbing systems hard-no
end

function vrmod.utils.GrabEndLaw_NormalizeHand(hand)
	local s = string.lower(tostring(hand or ""))
	if s == "left" or s == "l" or s == "1" then return "left" end
	if s == "right" or s == "r" or s == "2" then return "right" end
	if s == true or s == "true" then return "left" end -- bLeft=true convention
	return "right"
end

--- Pure: should drop start cooldown on this hand?
function vrmod.utils.GrabEndLaw_ShouldStartCooldown(opts)
	opts = type(opts) == "table" and opts or {}
	if opts.ignored_prop then return false end
	if opts.ent_valid == false then return false end
	return true
end

--- Pure: may this hand start a new pickup/grab now?
--- opts: cooldown_active, now, last_drop_time, cooldown_s
function vrmod.utils.GrabEndLaw_AllowPickup(opts)
	opts = type(opts) == "table" and opts or {}
	if opts.cooldown_active then return false end
	local now = tonumber(opts.now)
	local last = tonumber(opts.last_drop_time)
	local cd = tonumber(opts.cooldown_s) or vrmod.utils.GrabEndLaw_CooldownSeconds()
	if now and last and cd and (now - last) < cd then
		return false
	end
	return true
end

--- Storm: many drop events in a tiny window (same or both hands).
function vrmod.utils.GrabEndLaw_IsStorm(opts)
	opts = type(opts) == "table" and opts or {}
	local n = tonumber(opts.drop_events) or 0
	local window = tonumber(opts.window_s) or 0.05
	local thr = tonumber(opts.storm_threshold) or 3
	if window <= 0 then return n >= thr end
	-- density proxy: events in short window
	return n >= thr
end

--- Primary left: menu primary is left fire; grab pickup stays grip (not left trigger silence).
function vrmod.utils.GrabEndLaw_PrimaryLeftPreservesPickup(primaryHand)
	primaryHand = tostring(primaryHand or "right")
	-- When primary is left, menu LMB uses boolean_left_primaryfire; pickup remains grip.
	return primaryHand == "left" or primaryHand == "right"
end

function vrmod.utils.GrabEndLaw_MenuClickIsNotPickup(action, primaryHand)
	action = tostring(action or "")
	primaryHand = tostring(primaryHand or "right")
	if primaryHand == "left" then
		-- left primary fire is menu click, not pickup storm source
		return action == "boolean_left_primaryfire"
	end
	return action == "boolean_primaryfire"
end

--- Pure decision.
--- opts: hand, cooldown_active, drop_events, window_s, primary_hand,
---       allow_pickup, ent_valid, ignored_prop, climb_rewrite
function vrmod.utils.GrabEndLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local hand = vrmod.utils.GrabEndLaw_NormalizeHand(opts.hand or opts.b_left)
	local allow = opts.allow_pickup
	if allow == nil then
		allow = vrmod.utils.GrabEndLaw_AllowPickup(opts)
	end
	local storm = vrmod.utils.GrabEndLaw_IsStorm(opts)
	local d = {
		valid = true,
		hand = hand,
		cooldown_s = vrmod.utils.GrabEndLaw_CooldownSeconds(),
		allow_pickup = allow and true or false,
		cooldown_active = opts.cooldown_active and true or false,
		storm = storm,
		primary_hand = tostring(opts.primary_hand or "right"),
		risk = "none", -- none | cooldown | storm | climb_forbidden | silence
		reason = "ok",
		path_ok = true,
	}
	if opts.climb_rewrite and not vrmod.utils.GrabEndLaw_AllowClimbRewrite() then
		d.risk = "climb_forbidden"
		d.reason = "climb_rewrite_forbidden"
		d.path_ok = false
	elseif storm then
		d.risk = "storm"
		d.reason = "grab_end_storm"
		d.path_ok = false
	elseif not allow then
		d.risk = "cooldown"
		d.reason = "drop_cooldown_active"
		d.path_ok = true -- intentional gate
	elseif opts.left_trigger_silent and d.primary_hand == "left" then
		d.risk = "silence"
		d.reason = "left_trigger_silence"
		d.path_ok = false
	else
		d.reason = "grab_end_ok"
		d.path_ok = true
	end
	return d
end

function vrmod.utils.GrabEndLaw_StatusLabel(decision)
	if type(decision) ~= "table" then return "GRAB · IDLE" end
	if decision.risk == "storm" then return "GRAB · STORM" end
	if decision.risk == "cooldown" then return "GRAB · COOLDOWN" end
	if decision.risk == "climb_forbidden" then return "GRAB · CLIMB NO" end
	if decision.risk == "silence" then return "GRAB · SILENCE" end
	if decision.path_ok then return "GRAB · OK" end
	return "GRAB · HOLD"
end

function vrmod.utils.GrabEndLaw_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_clean_drop = true,
		checklist = "G44 · IDLE · no grab decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if decision.risk == "storm" then
		e.verdict = "expect_storm"
		e.expect_clean_drop = false
		e.checklist = "G44 · STORM · rapid grab_end / drop thrash"
		e.pass_line = "0.1s per-hand cooldown after drop; ignore re-grab storms"
		e.fail_line = "grab_end spam / pickup flicker"
		return e
	end
	if decision.risk == "silence" then
		e.verdict = "expect_silence"
		e.checklist = "G44 · SILENCE · left trigger dead with primary=left"
		e.pass_line = "Menu LMB on left primary; grip still pickups"
		e.fail_line = "Left trigger silence / no laser click"
		return e
	end
	if decision.risk == "cooldown" then
		e.verdict = "expect_cooldown"
		e.checklist = "G44 · COOLDOWN · hand=" .. tostring(decision.hand)
		e.pass_line = "Short post-drop gate; then grab again"
		e.fail_line = "Permanent lockout or zero cooldown storms"
		return e
	end
	if decision.risk == "climb_forbidden" then
		e.verdict = "expect_climb_no"
		e.checklist = "G44 · CLIMB NO · do not thrash climb grip"
		e.pass_line = "Grab-end law only; climb untouched"
		e.fail_line = "Climb rewrite under grab-end polish"
		return e
	end
	e.verdict = "expect_ok"
	e.checklist = string.format(
		"G44 · OK · hand=%s · primary=%s",
		tostring(decision.hand),
		tostring(decision.primary_hand)
	)
	e.pass_line = "Clean drop; no storm; primary-left click works"
	e.fail_line = "grab_end storms or left-trigger silence"
	return e
end

function vrmod.utils.GrabEndLaw_IsStormRisk(decision)
	if type(decision) ~= "table" then return false end
	return decision.risk == "storm"
end
