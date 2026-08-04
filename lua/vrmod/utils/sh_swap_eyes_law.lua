-- G33: swap-eyes content-only law (pure, offline-tested).
-- Watchlist W4: eyes inverted / seeing double — single bool, no second pose stream.
-- Law: vrmod_swap_eyes swaps SBS half *content* only; IPD/FOV/pose truth unchanged.
-- Never fork dual eye poses or invert tracking to "fix" stereo.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

function vrmod.utils.SwapEyesLaw_CubeDefault()
	return false
end

--- Parse convar / UI value → bool. 0/false/"0"/"false"/nil → false.
function vrmod.utils.SwapEyesLaw_FromAny(v)
	if v == true or v == 1 then return true end
	if v == false or v == 0 or v == nil then return false end
	local s = string.lower(tostring(v))
	if s == "1" or s == "true" or s == "yes" or s == "on" then return true end
	return false
end

--- Dual pose fork forbidden: swap must not invent second tracking SoT.
function vrmod.utils.SwapEyesLaw_AllowDualPoseFork()
	return false
end

--- IPD / FOV / eye positions stay as computed; only SBS write X swaps.
function vrmod.utils.SwapEyesLaw_PreserveIpdFov()
	return true
end

--- Pure SBS half origins for left/right *logical* eyes into the RT.
--- leftX/rightX are pixel offsets into the SBS RT (half width each).
function vrmod.utils.SwapEyesLaw_ResolveSbsHalves(rtHalfW, swap)
	rtHalfW = tonumber(rtHalfW) or 0
	if rtHalfW < 0 then rtHalfW = 0 end
	swap = vrmod.utils.SwapEyesLaw_FromAny(swap)
	if swap then
		return rtHalfW, 0
	end
	return 0, rtHalfW
end

--- Which physical half receives logical left content: "left" | "right".
function vrmod.utils.SwapEyesLaw_LogicalLeftHalf(swap)
	return vrmod.utils.SwapEyesLaw_FromAny(swap) and "right" or "left"
end

function vrmod.utils.SwapEyesLaw_LogicalRightHalf(swap)
	return vrmod.utils.SwapEyesLaw_FromAny(swap) and "left" or "right"
end

--- Pure decision snapshot.
--- opts:
---   swap bool|any
---   rt_half_w number|nil
---   dual_pose_fork bool|nil   product tried second pose stream (forbidden)
---   ipd_mutated bool|nil      product flipped IPD with swap (forbidden)
---   fov_swapped bool|nil      product swapped FOV numbers with swap (allowed? law says FOV truth unchanged for each eye — fovL stays left eye FOV)
function vrmod.utils.SwapEyesLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local swap = vrmod.utils.SwapEyesLaw_FromAny(opts.swap)
	local half = tonumber(opts.rt_half_w) or 0
	local leftX, rightX = vrmod.utils.SwapEyesLaw_ResolveSbsHalves(half, swap)
	local d = {
		valid = true,
		swap = swap,
		left_x = leftX,
		right_x = rightX,
		logical_left_half = vrmod.utils.SwapEyesLaw_LogicalLeftHalf(swap),
		logical_right_half = vrmod.utils.SwapEyesLaw_LogicalRightHalf(swap),
		preserve_ipd_fov = vrmod.utils.SwapEyesLaw_PreserveIpdFov(),
		dual_pose_forbidden = not vrmod.utils.SwapEyesLaw_AllowDualPoseFork(),
		risk = "none", -- none | dual_pose | ipd_mutated | fov_fork
		reason = "ok",
		path_ok = true,
	}
	if opts.dual_pose_fork then
		d.risk = "dual_pose"
		d.reason = "second_pose_stream_forbidden"
		d.path_ok = false
	elseif opts.ipd_mutated then
		d.risk = "ipd_mutated"
		d.reason = "ipd_must_stay_with_tracking"
		d.path_ok = false
	elseif opts.fov_swapped then
		-- Swapping FOV numbers between eyes with content swap is a soft risk (asymmetric HMDs)
		d.risk = "fov_fork"
		d.reason = "fov_truth_must_stay_per_eye"
		d.path_ok = false
	else
		d.reason = swap and "content_swap_sbs_only" or "natural_sbs"
		d.path_ok = true
	end
	return d
end

function vrmod.utils.SwapEyesLaw_StatusLabel(decision)
	if type(decision) ~= "table" then return "EYE · IDLE" end
	if decision.risk == "dual_pose" then return "EYE · DUAL POSE FORBID" end
	if decision.risk == "ipd_mutated" then return "EYE · IPD FORBID" end
	if decision.risk == "fov_fork" then return "EYE · FOV FORK" end
	if decision.swap then return "EYE · SWAP CONTENT" end
	return "EYE · NATURAL"
end

function vrmod.utils.SwapEyesLaw_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_content_only = true,
		checklist = "G33 · IDLE · no swap-eyes decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if not decision.path_ok then
		e.verdict = "expect_fork_fail"
		e.expect_content_only = false
		e.checklist = "G33 · FAIL · " .. tostring(decision.reason)
		e.pass_line = "SBS content swap only; IPD/FOV/pose single path"
		e.fail_line = "Dual pose / IPD flip / FOV fork with swap"
		return e
	end
	if decision.swap then
		e.verdict = "expect_swap"
		e.checklist = "G33 · SWAP · content L↔R halves · IPD/FOV truth held"
		e.pass_line = "Inverted stereo fixed; no tracking thrash"
		e.fail_line = "Still crossed or world depth wrong after swap"
		return e
	end
	e.verdict = "expect_natural"
	e.checklist = "G33 · NATURAL · left half = left content · default"
	e.pass_line = "No crossed stereo at default 0"
	e.fail_line = "Seeing double / inverted without user toggle"
	return e
end

function vrmod.utils.SwapEyesLaw_IsForkRisk(decision)
	if type(decision) ~= "table" then return true end
	return not decision.path_ok
end
