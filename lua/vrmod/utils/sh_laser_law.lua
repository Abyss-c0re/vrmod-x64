-- G16: laser + menu primary-click sacred law (pure, offline-tested).
-- Cube UI: laser + trigger click is sacred and must stay responsive.
-- Law:
--   one primary hand SoT (never dual free-for-all lasers)
--   primary trigger → menu LMB; secondary → RMB/close
--   focus solve once per stereo frame (first eye), not thrash every eye
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

--- Primary hand from convar int: 0=right, 1=left.
function vrmod.utils.LaserLaw_PrimaryHandFromInt(v)
	v = tonumber(v) or 0
	return (v == 1) and "left" or "right"
end

function vrmod.utils.LaserLaw_SecondaryHand(primary)
	primary = tostring(primary or "right")
	return (primary == "left") and "right" or "left"
end

--- Pure primary-click action match (menu LMB).
function vrmod.utils.LaserLaw_IsMenuPrimaryClick(action, primaryHand)
	action = tostring(action or "")
	if action == "boolean_car_mouse_left" then return true end
	primaryHand = tostring(primaryHand or "right")
	if primaryHand == "left" then
		return action == "boolean_left_primaryfire"
	end
	return action == "boolean_primaryfire"
end

--- Pure secondary / cancel / RMB.
function vrmod.utils.LaserLaw_IsMenuSecondaryClick(action)
	action = tostring(action or "")
	return action == "boolean_secondaryfire"
		or action == "boolean_left_secondaryfire"
		or action == "boolean_car_mouse_right"
end

function vrmod.utils.LaserLaw_IsMenuCloseAction(action)
	return vrmod.utils.LaserLaw_IsMenuSecondaryClick(action)
		or tostring(action or "") == "boolean_chat"
end

--- Quick menu attach mode from int: 0=left 1=right 2=float.
function vrmod.utils.LaserLaw_QmAttachModeFromInt(v)
	v = tonumber(v) or 0
	if v == 1 then return "right" end
	if v == 2 then return "float" end
	return "left"
end

--- True when this stereo eye must re-solve laser focus (first eye / resize / miss).
--- opts: stereo_eye string|nil, focus_frame, stereo_frame, resize_active, scale_changed
function vrmod.utils.LaserLaw_ShouldSolveFocus(opts)
	opts = type(opts) == "table" and opts or {}
	if opts.resize_active then return true end
	if opts.scale_changed then return true end
	local sf = tonumber(opts.stereo_frame) or 0
	local ff = tonumber(opts.focus_frame)
	if ff == nil or ff ~= sf then return true end
	local eye = opts.stereo_eye
	if eye == "left" or eye == nil then return true end
	return false
end

--- G45: laser ray allowed only from primary hand (never dual free-for-all).
function vrmod.utils.LaserLaw_AllowLaserFromHand(handName, primaryHand)
	handName = tostring(handName or "")
	primaryHand = tostring(primaryHand or "right")
	if handName ~= "left" and handName ~= "right" then return false end
	return handName == primaryHand
end

--- Wrong-hand primary fire steals menu LMB when primary is the other hand.
--- e.g. primary=left but action=boolean_primaryfire (right trigger) → steal.
function vrmod.utils.LaserLaw_IsWrongHandPrimaryClick(action, primaryHand)
	action = tostring(action or "")
	primaryHand = tostring(primaryHand or "right")
	if action == "boolean_car_mouse_left" then return false end -- neutral path
	if primaryHand == "left" then
		-- Right fire must not steal left-primary LMB
		return action == "boolean_primaryfire"
	end
	-- primary right: left fire is wrong-hand
	return action == "boolean_left_primaryfire"
end

--- Pure decision snapshot (G16 + G45 primary-left ship bar).
--- opts: vr_active, laser_on, has_primary_pose, menu_focus, primary_hand|primary_hand_int,
---       laser_hand, click_action, dual_laser
function vrmod.utils.LaserLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local primary = opts.primary_hand
	if primary == nil and opts.primary_hand_int ~= nil then
		primary = vrmod.utils.LaserLaw_PrimaryHandFromInt(opts.primary_hand_int)
	end
	primary = tostring(primary or "right")
	if primary ~= "left" and primary ~= "right" then primary = "right" end
	local secondary = vrmod.utils.LaserLaw_SecondaryHand(primary)
	local laserHand = opts.laser_hand and tostring(opts.laser_hand) or primary
	local allowLaser = vrmod.utils.LaserLaw_AllowLaserFromHand(laserHand, primary)
	local steal = false
	if opts.click_action then
		steal = vrmod.utils.LaserLaw_IsWrongHandPrimaryClick(opts.click_action, primary)
	end
	local d = {
		valid = true,
		primary_hand = primary,
		secondary_hand = secondary,
		laser_hand = laserHand,
		allow_laser = allowLaser,
		click_steal = steal,
		menu_primary_click = opts.click_action
			and vrmod.utils.LaserLaw_IsMenuPrimaryClick(opts.click_action, primary)
			or false,
		dual_laser = opts.dual_laser and true or false,
		vr_active = opts.vr_active and true or false,
		laser_on = opts.laser_on and true or false,
		has_primary_pose = opts.has_primary_pose and true or false,
		menu_focus = opts.menu_focus and true or false,
		risk = "none", -- none | off | no_pose | dual | steal | idle
		reason = "ok",
		path_ok = true,
	}
	if not d.vr_active then
		d.risk = "idle"
		d.reason = "vr_inactive"
		d.path_ok = true
	elseif d.dual_laser or not allowLaser then
		d.risk = "dual"
		d.reason = not allowLaser and "laser_wrong_hand" or "dual_laser_forbidden"
		d.path_ok = false
	elseif steal then
		d.risk = "steal"
		d.reason = "wrong_hand_primary_click"
		d.path_ok = false
	elseif not d.laser_on then
		d.risk = "off"
		d.reason = "laser_off"
		d.path_ok = true
	elseif not d.has_primary_pose then
		d.risk = "no_pose"
		d.reason = "primary_pose_missing"
		d.path_ok = false
	elseif d.menu_focus then
		d.reason = "focus_primary_" .. primary
		d.path_ok = true
	else
		d.reason = "aim_primary_" .. primary
		d.path_ok = true
	end
	return d
end

--- Pure HMD observer expect for laser UI.
--- Accepts raw opts (legacy G16) or a Decide() table.
function vrmod.utils.LaserLaw_HmdExpect(opts)
	opts = type(opts) == "table" and opts or {}
	-- If already a decision, use it; else build from opts.
	local decision = opts.valid and opts.primary_hand and opts.risk and opts or nil
	if not decision and (opts.vr_active ~= nil or opts.primary_hand or opts.primary_hand_int) then
		decision = vrmod.utils.LaserLaw_Decide(opts)
	end
	local e = {
		verdict = "idle",
		expect_primary_only = true,
		checklist = "G16 · IDLE · VR inactive",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if not decision or not decision.vr_active then return e end
	local hand = tostring(decision.primary_hand or "right")
	if decision.risk == "dual" then
		e.verdict = "expect_dual_fail"
		e.expect_primary_only = false
		e.checklist = "G45 · DUAL · laser not primary-only"
		e.pass_line = "Laser only from " .. hand
		e.fail_line = "Dual free-for-all lasers / wrong-hand ray"
		return e
	end
	if decision.risk == "steal" then
		e.verdict = "expect_steal"
		e.checklist = string.format("G45 · STEAL · primary=%s · wrong-hand click", hand)
		e.pass_line = hand == "left"
			and "Left trigger = LMB; right fire does not steal"
			or "Right trigger = LMB; left fire does not steal"
		e.fail_line = "Right still steals click when vrmod_primary_hand 1"
		return e
	end
	if not decision.laser_on or decision.risk == "off" then
		e.verdict = "expect_laser_off"
		e.checklist = "G16 · LASER OFF · enable for UI"
		e.pass_line = "Menus may need laserpointer 1 for hit"
		e.fail_line = "Forced dual lasers without enable"
		return e
	end
	if decision.risk == "no_pose" or not decision.has_primary_pose then
		e.verdict = "expect_no_pose"
		e.checklist = "G16 · NO POSE · primary hand tracking invalid"
		e.pass_line = "Honest no-cursor when tracking lost"
		e.fail_line = "Ghost cursor / dual-hand free-for-all"
		return e
	end
	if decision.menu_focus then
		e.verdict = "expect_focus"
		e.checklist = string.format("G16 · FOCUS · primary=%s · trigger=click", hand)
		e.pass_line = "Hover stable; primary trigger clicks once; no thrash"
		e.fail_line = "Miss clicks, dual laser, or grab_end storms"
		return e
	end
	e.verdict = "expect_aim"
	e.checklist = string.format("G16 · AIM · primary=%s · no panel hit", hand)
	e.pass_line = "Laser visible; panels only when ray hits"
	e.fail_line = "Laser from both hands / stuck focus"
	return e
end

function vrmod.utils.LaserLaw_StatusLabel(expectOrDecision)
	if type(expectOrDecision) ~= "table" then return "LASER · IDLE" end
	-- Decision path (G45)
	if expectOrDecision.risk then
		if expectOrDecision.risk == "dual" then return "LASER · DUAL FAIL" end
		if expectOrDecision.risk == "steal" then return "LASER · STEAL" end
		if expectOrDecision.risk == "off" then return "LASER · OFF" end
		if expectOrDecision.risk == "no_pose" then return "LASER · NO POSE" end
		if expectOrDecision.risk == "idle" then return "LASER · IDLE" end
		if expectOrDecision.menu_focus then return "LASER · FOCUS" end
		if expectOrDecision.path_ok then return "LASER · AIM" end
		return "LASER · HOLD"
	end
	-- HmdExpect path (G16)
	if expectOrDecision.verdict == "expect_focus" then return "LASER · FOCUS" end
	if expectOrDecision.verdict == "expect_aim" then return "LASER · AIM" end
	if expectOrDecision.verdict == "expect_laser_off" then return "LASER · OFF" end
	if expectOrDecision.verdict == "expect_no_pose" then return "LASER · NO POSE" end
	if expectOrDecision.verdict == "expect_steal" then return "LASER · STEAL" end
	if expectOrDecision.verdict == "expect_dual_fail" then return "LASER · DUAL FAIL" end
	return "LASER · IDLE"
end

function vrmod.utils.LaserLaw_IsStealRisk(decision)
	if type(decision) ~= "table" then return false end
	return decision.risk == "steal" or decision.risk == "dual"
end

