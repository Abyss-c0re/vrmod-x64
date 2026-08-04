-- Pure Glide vehicle input SoT helpers (G14 / Cube W3).
-- Offline-testable — no Glide addon / net / engine required.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

--- Is this seat index the driver? seat 0/API-not-ready → treat as driver (recheck later).
function vrmod.utils.GlideSeatIsDriver(seatIndex)
	local seat = tonumber(seatIndex) or 0
	return seat == 1 or seat < 1
end

--- Prefer thumbstick steer; only use wheel when stick is near idle.
--- Returns steer value and source "stick" | "wheel".
function vrmod.utils.GlidePreferStickSteer(stickX, wheelSteer, stickDeadzone, wheelMin)
	stickX = tonumber(stickX) or 0
	wheelSteer = tonumber(wheelSteer) or 0
	stickDeadzone = tonumber(stickDeadzone) or 0.05
	wheelMin = tonumber(wheelMin) or 0.02
	if math.abs(stickX) >= stickDeadzone then
		return stickX, "stick"
	end
	if math.abs(wheelSteer) > wheelMin then
		return wheelSteer, "wheel"
	end
	return stickX, "stick"
end

-- ── G14 HMD Glide smoke expect (pure observer contract) ─────────────────────
-- Offline tokens for vehicle input feel. Never claims HMD/Glide session passed.

--- Human label for steer source token.
function vrmod.utils.GlideSteerSourceLabel(src)
	src = string.lower(tostring(src or "stick"))
	if src == "wheel" then return "WHEEL ASSIST" end
	return "STICK SoT"
end

--- Compact status label for log/HUD (pure).
function vrmod.utils.Glide_StatusLabel(expect)
	if type(expect) ~= "table" then return "GLIDE · IDLE" end
	if expect.verdict == "expect_driver_stick" then return "GLIDE · DRIVER · STICK" end
	if expect.verdict == "expect_driver_wheel" then return "GLIDE · DRIVER · WHEEL" end
	if expect.verdict == "expect_passenger" then return "GLIDE · PASSENGER" end
	if expect.verdict == "expect_unbound" then return "GLIDE · UNBOUND" end
	if expect.verdict == "expect_non_glide" then return "GLIDE · STOCK VEHICLE" end
	return "GLIDE · IDLE"
end

--- Pure HMD observer expectation for Glide enter / drive.
--- opts:
---   in_vehicle       bool
---   is_glide         bool
---   is_driver        bool  GlideSeatIsDriver(seat)
---   steer_source     string stick|wheel (from PreferStickSteer)
---   has_steer_action bool  vector2_steer present in g_VR.input
---   throttle         number|nil optional
--- Returns verdict / checklist / pass_line / fail_line / expect_stick_sot
function vrmod.utils.Glide_HmdExpect(opts)
	opts = type(opts) == "table" and opts or {}
	local e = {
		verdict = "idle",
		expect_stick_sot = true,
		steer_source = "stick",
		checklist = "G14 · IDLE · not in vehicle",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if not opts.in_vehicle then return e end

	if not opts.is_glide then
		e.verdict = "expect_non_glide"
		e.checklist = "G14 · STOCK · non-Glide vehicle path"
		e.pass_line = "Stock vehicle grip path; Glide SoT N/A"
		e.fail_line = "Broken enter/exit thrash"
		return e
	end

	if not opts.is_driver then
		e.verdict = "expect_passenger"
		e.expect_stick_sot = false
		e.checklist = "G14 · PASSENGER · no drive input"
		e.pass_line = "Passenger seat silent on drive nets"
		e.fail_line = "Passenger sends drive / steals driver input"
		return e
	end

	if opts.has_steer_action == false then
		e.verdict = "expect_unbound"
		e.checklist = "G14 · UNBOUND · /actions/driving missing"
		e.pass_line = "Error toast about rebind; car dead is honest"
		e.fail_line = "Silent dead car with no toast"
		return e
	end

	local src = string.lower(tostring(opts.steer_source or "stick"))
	e.steer_source = (src == "wheel") and "wheel" or "stick"
	if e.steer_source == "wheel" then
		e.verdict = "expect_driver_wheel"
		e.checklist = "G14 · DRIVER · wheel assist (stick idle)"
		e.pass_line = "Wheel only while stick near deadzone; stick reclaim instant"
		e.fail_line = "Wheel fights stick / dual steer SoT"
	else
		e.verdict = "expect_driver_stick"
		e.checklist = "G14 · DRIVER · stick SoT"
		e.pass_line = "Thumbstick steers; throttle/brake live; lights stereo OK"
		e.fail_line = "No steer, stick ignored, or mouse-fly thrash"
	end
	return e
end

--- One-shot enter toast gate (pure).
function vrmod.utils.Glide_ShouldToastEnter(expect, alreadyToasted)
	if alreadyToasted then return false end
	if type(expect) ~= "table" then return false end
	return expect.verdict == "expect_driver_stick"
		or expect.verdict == "expect_driver_wheel"
		or expect.verdict == "expect_unbound"
end

--- Enter toast copy from expect (pure).
function vrmod.utils.Glide_EnterToast(expect)
	if type(expect) ~= "table" then return nil end
	if expect.verdict == "expect_unbound" then
		return "Glide inputs unbound — rebind /actions/driving or reinstall module"
	end
	if expect.verdict == "expect_driver_stick" or expect.verdict == "expect_driver_wheel" then
		return "Glide seat — use thumbstick; wheel is optional"
	end
	return nil
end
