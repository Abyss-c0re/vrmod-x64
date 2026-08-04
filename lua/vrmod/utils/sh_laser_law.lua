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

--- Pure HMD observer expect for laser UI.
--- opts: vr_active, laser_on, has_primary_pose, menu_focus, primary_hand
function vrmod.utils.LaserLaw_HmdExpect(opts)
	opts = type(opts) == "table" and opts or {}
	local e = {
		verdict = "idle",
		expect_primary_only = true,
		checklist = "G16 · IDLE · VR inactive",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if not opts.vr_active then return e end
	local hand = tostring(opts.primary_hand or "right")
	if not opts.laser_on then
		e.verdict = "expect_laser_off"
		e.checklist = "G16 · LASER OFF · enable for UI"
		e.pass_line = "Menus may need laserpointer 1 for hit"
		e.fail_line = "Forced dual lasers without enable"
		return e
	end
	if not opts.has_primary_pose then
		e.verdict = "expect_no_pose"
		e.checklist = "G16 · NO POSE · primary hand tracking invalid"
		e.pass_line = "Honest no-cursor when tracking lost"
		e.fail_line = "Ghost cursor / dual-hand free-for-all"
		return e
	end
	if opts.menu_focus then
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

function vrmod.utils.LaserLaw_StatusLabel(expect)
	if type(expect) ~= "table" then return "LASER · IDLE" end
	if expect.verdict == "expect_focus" then return "LASER · FOCUS" end
	if expect.verdict == "expect_aim" then return "LASER · AIM" end
	if expect.verdict == "expect_laser_off" then return "LASER · OFF" end
	if expect.verdict == "expect_no_pose" then return "LASER · NO POSE" end
	return "LASER · IDLE"
end
