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
