-- G25: pose energy path law (pure, offline-tested).
-- Pain point #4: dual-truth pose forks forbidden.
-- One path: WaitGetPoses → rawTracking → copy → g_VR.tracking → modifiers in place.
-- Public SoT for guns/UI/collisions: tracking (post-modifier).
-- rawTracking stays device purity; head vel/angvel sample from RAW device only once.
-- Never invent a second angvel/pose stream that competes with tracking.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

--- Ordered pipeline tokens (documentation + offline contract).
function vrmod.utils.PoseSoT_PipelineSteps()
	return {
		"wait_get_poses",
		"raw_tracking",
		"copy_to_tracking",
		"early_modifiers",
		"late_modifiers",
		"consumers_read_tracking",
	}
end

--- Public consumer SoT name (guns, laser, collisions, viewmodel).
function vrmod.utils.PoseSoT_PublicSource()
	return "tracking"
end

--- Device-pure stream name (never replace with a second public SoT).
function vrmod.utils.PoseSoT_RawSource()
	return "rawTracking"
end

--- Product must never maintain a second angular-velocity SoT fork.
function vrmod.utils.PoseSoT_AllowSecondAngvelSoT()
	return false
end

--- Product must never expose two competing public pose tables for the same limb.
function vrmod.utils.PoseSoT_AllowDualPublicPose()
	return false
end

--- Guns / viewmodel must read tracking (post-modifier), never raw-only fork.
function vrmod.utils.PoseSoT_GunReadsSource()
	return "tracking"
end

--- Head velocity sampling source (device raw before modifier thrash).
function vrmod.utils.PoseSoT_HeadVelSource()
	return "raw"
end

--- Normalize consumer read source string.
function vrmod.utils.PoseSoT_NormalizeSource(s)
	s = tostring(s or ""):lower()
	if s == "tracking" or s == "g_vr.tracking" or s == "public" then
		return "tracking"
	end
	if s == "raw" or s == "rawtracking" or s == "g_vr.rawtracking" or s == "device" then
		return "raw"
	end
	if s == "fork" or s == "dual" or s == "second" then
		return "fork"
	end
	return "unknown"
end

--- Pure decision snapshot.
--- opts:
---   has_raw bool|nil
---   has_tracking bool|nil
---   gun_reads string|nil          tracking|raw|fork
---   head_vel_from string|nil      raw|tracking|fork
---   second_angvel_sot bool|nil
---   modifiers_in_place bool|nil   late modifiers mutate tracking fields
---   dual_public bool|nil          two public pose tables for same limb
---   vr_active bool|nil
function vrmod.utils.PoseSoT_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local gun = vrmod.utils.PoseSoT_NormalizeSource(opts.gun_reads or vrmod.utils.PoseSoT_GunReadsSource())
	local head = vrmod.utils.PoseSoT_NormalizeSource(opts.head_vel_from or vrmod.utils.PoseSoT_HeadVelSource())
	local second = opts.second_angvel_sot and true or false
	local dualPub = opts.dual_public and true or false
	local modInPlace = opts.modifiers_in_place
	if modInPlace == nil then modInPlace = true end
	modInPlace = modInPlace and true or false
	local active = opts.vr_active
	if active == nil then active = true end
	active = active and true or false
	local hasRaw = opts.has_raw and true or false
	local hasTr = opts.has_tracking and true or false
	local d = {
		valid = true,
		vr_active = active,
		has_raw = hasRaw,
		has_tracking = hasTr,
		gun_reads = gun,
		head_vel_from = head,
		second_angvel_sot = second,
		dual_public = dualPub,
		modifiers_in_place = modInPlace,
		public_source = vrmod.utils.PoseSoT_PublicSource(),
		raw_source = vrmod.utils.PoseSoT_RawSource(),
		risk = "none", -- none | dual_public | second_angvel | gun_raw_fork | head_vel_fork | missing_sot
		reason = "ok",
		path_ok = true,
	}
	if not active then
		d.reason = "inactive"
		d.path_ok = true
		return d
	end
	if dualPub then
		d.risk = "dual_public"
		d.reason = "dual_public_pose_tables"
		d.path_ok = false
		return d
	end
	if second then
		d.risk = "second_angvel"
		d.reason = "second_angvel_sot_fork"
		d.path_ok = false
		return d
	end
	-- Guns must follow public tracking SoT (post-modifier / collisions), never raw-only fork.
	if gun == "fork" or gun == "raw" then
		d.risk = "gun_raw_fork"
		d.reason = gun == "fork" and "gun_reads_fork" or "gun_reads_raw_not_tracking"
		d.path_ok = false
		return d
	end
	if head == "fork" then
		d.risk = "head_vel_fork"
		d.reason = "head_vel_second_stream"
		d.path_ok = false
		return d
	end
	-- Head vel from tracking is softer risk (prefer raw) but not dual-truth if single stream
	if head == "tracking" then
		d.risk = "none"
		d.reason = "head_vel_from_tracking_soft"
		-- still path_ok; prefer raw in product
	end
	if not hasRaw and not hasTr then
		d.risk = "missing_sot"
		d.reason = "no_raw_no_tracking"
		d.path_ok = false
		return d
	end
	if hasTr and gun == "tracking" and not second and not dualPub then
		d.reason = modInPlace and "single_path_modifiers_in_place" or "single_path"
		d.path_ok = true
		d.risk = "none"
	end
	return d
end

function vrmod.utils.PoseSoT_StatusLabel(decision)
	if type(decision) ~= "table" then return "POSE · IDLE" end
	if not decision.vr_active then return "POSE · IDLE" end
	if decision.risk == "dual_public" then return "POSE · DUAL PUBLIC FORK" end
	if decision.risk == "second_angvel" then return "POSE · ANGVEL FORK" end
	if decision.risk == "gun_raw_fork" then return "POSE · GUN FORK" end
	if decision.risk == "head_vel_fork" then return "POSE · HEAD VEL FORK" end
	if decision.risk == "missing_sot" then return "POSE · MISSING" end
	if decision.path_ok then return "POSE · SINGLE PATH" end
	return "POSE · HOLD"
end

--- Pure HMD observer contract (offline ≠ headset proof).
function vrmod.utils.PoseSoT_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_single_path = true,
		checklist = "G25 · IDLE · no pose SoT decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if not decision.vr_active then return e end
	if not decision.path_ok then
		e.verdict = "expect_fork_fail"
		e.expect_single_path = false
		e.checklist = "G25 · FORK RISK · " .. tostring(decision.reason or decision.risk)
		e.pass_line = "Must not ship dual pose/angvel SoT"
		e.fail_line = "Hands/guns desync; jitter from competing streams"
		return e
	end
	e.verdict = "expect_single_path"
	e.expect_single_path = true
	e.checklist = string.format(
		"G25 · SINGLE PATH · public=%s · gun=%s · head_vel=%s",
		tostring(decision.public_source or "tracking"),
		tostring(decision.gun_reads or "tracking"),
		tostring(decision.head_vel_from or "raw")
	)
	e.pass_line = "One energy path; guns read tracking; raw stays device-pure"
	e.fail_line = "Second angvel/pose SoT or gun reading raw-only fork"
	return e
end

function vrmod.utils.PoseSoT_IsForkRisk(decision)
	if type(decision) ~= "table" then return true end
	return not decision.path_ok
end
