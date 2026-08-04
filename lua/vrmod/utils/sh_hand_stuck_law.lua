-- G42: hands-stuck unstick law (pure, offline-tested).
-- Ship bar / workshop: hands stuck together / hands tied.
-- Cube way: heal shared Vector/Angle identity; restore track from raw when
-- tracking collapsed but raw still separated. Skip while foregrip owns left.
-- Do not rewrite climb/wall coll here (pain points).
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

--- Tracking L/R DistToSqr below this ≈ glued (<2 units).
function vrmod.utils.HandStuckLaw_TrackCollapseThresholdSqr()
	return 4
end

--- Raw L/R DistToSqr above this ≈ controllers still separated (>6 units).
function vrmod.utils.HandStuckLaw_RawSeparatedThresholdSqr()
	return 36
end

--- Foregrip attach may sit near RH on short guns — never unstick then.
function vrmod.utils.HandStuckLaw_SkipUnstickWhenForegrip()
	return true
end

function vrmod.utils.HandStuckLaw_HealIdentityAlways()
	return true
end

function vrmod.utils.HandStuckLaw_PreferRawWhenCollapsed()
	return true
end

--- Pure: should clone/split shared pos/ang identity (userdata glue).
function vrmod.utils.HandStuckLaw_ShouldSplitIdentity(sameIdentity)
	if not vrmod.utils.HandStuckLaw_HealIdentityAlways() then return false end
	return sameIdentity and true or false
end

--- Pure: track collapsed + raw separated → restore track from raw.
--- opts: track_dist_sqr, raw_dist_sqr, foregrip_active
function vrmod.utils.HandStuckLaw_ShouldUnstickFromRaw(opts)
	opts = type(opts) == "table" and opts or {}
	if opts.foregrip_active and vrmod.utils.HandStuckLaw_SkipUnstickWhenForegrip() then
		return false
	end
	local track = tonumber(opts.track_dist_sqr)
	local raw = tonumber(opts.raw_dist_sqr)
	if track == nil or raw == nil then return false end
	return track < vrmod.utils.HandStuckLaw_TrackCollapseThresholdSqr()
		and raw > vrmod.utils.HandStuckLaw_RawSeparatedThresholdSqr()
end

function vrmod.utils.HandStuckLaw_DistSqr(ax, ay, az, bx, by, bz)
	ax, ay, az = tonumber(ax) or 0, tonumber(ay) or 0, tonumber(az) or 0
	bx, by, bz = tonumber(bx) or 0, tonumber(by) or 0, tonumber(bz) or 0
	local dx, dy, dz = ax - bx, ay - by, az - bz
	return dx * dx + dy * dy + dz * dz
end

--- Pure decision snapshot.
--- opts:
---   pos_identity_lr, ang_identity_lr, pos_identity_hl, pos_identity_hr (bool)
---   track_dist_sqr, raw_dist_sqr, foregrip_active
---   unstuck_applied, identity_healed (bool, post-heal observation)
function vrmod.utils.HandStuckLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local wantId = vrmod.utils.HandStuckLaw_ShouldSplitIdentity(
		opts.pos_identity_lr or opts.ang_identity_lr
			or opts.pos_identity_hl or opts.pos_identity_hr
			or opts.pos_identity_raw_lr or opts.ang_identity_raw_lr
	)
	local wantRaw = vrmod.utils.HandStuckLaw_ShouldUnstickFromRaw(opts)
	local d = {
		valid = true,
		heal_identity = wantId,
		unstick_from_raw = wantRaw,
		foregrip_active = opts.foregrip_active and true or false,
		track_dist_sqr = tonumber(opts.track_dist_sqr),
		raw_dist_sqr = tonumber(opts.raw_dist_sqr),
		identity_healed = opts.identity_healed == true,
		unstuck_applied = opts.unstuck_applied == true,
		risk = "none", -- none | identity_glue | collapse | stuck_residual | foregrip_hold
		reason = "ok",
		path_ok = true,
	}
	if d.foregrip_active and wantRaw == false and opts.track_dist_sqr
		and opts.track_dist_sqr < vrmod.utils.HandStuckLaw_TrackCollapseThresholdSqr()
	then
		d.risk = "foregrip_hold"
		d.reason = "foregrip_skip_unstick"
		d.path_ok = true -- intentional
	elseif wantId and wantRaw then
		d.risk = "collapse"
		d.reason = "identity_and_collapse"
		d.path_ok = true -- healable
	elseif wantId then
		d.risk = "identity_glue"
		d.reason = "shared_vector_identity"
		d.path_ok = true
	elseif wantRaw then
		d.risk = "collapse"
		d.reason = "track_collapsed_raw_separated"
		d.path_ok = true
	elseif opts.report_stuck and not opts.unstuck_applied and not opts.identity_healed then
		d.risk = "stuck_residual"
		d.reason = "hands_still_stuck"
		d.path_ok = false
	else
		d.reason = "hands_independent"
		d.path_ok = true
	end
	return d
end

function vrmod.utils.HandStuckLaw_StatusLabel(decision)
	if type(decision) ~= "table" then return "HANDS · IDLE" end
	if decision.risk == "stuck_residual" then return "HANDS · STUCK" end
	if decision.risk == "identity_glue" then return "HANDS · ID HEAL" end
	if decision.risk == "collapse" then return "HANDS · UNSTICK RAW" end
	if decision.risk == "foregrip_hold" then return "HANDS · FOREGREP HOLD" end
	if decision.path_ok then return "HANDS · OK" end
	return "HANDS · HOLD"
end

function vrmod.utils.HandStuckLaw_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_separated = true,
		checklist = "G42 · IDLE · no hands decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if decision.risk == "stuck_residual" then
		e.verdict = "expect_stuck"
		e.expect_separated = false
		e.checklist = "G42 · STUCK · L/R hands glued in tracking"
		e.pass_line = "Heal identity + restore from raw when separated"
		e.fail_line = "Hands tied / stuck together in HMD"
		return e
	end
	if decision.risk == "identity_glue" or decision.risk == "collapse" then
		e.verdict = "expect_heal"
		e.checklist = "G42 · HEAL · " .. tostring(decision.reason)
		e.pass_line = "One-frame heal; hands independent next poses"
		e.fail_line = "Identity/collapse residual after heal"
		return e
	end
	if decision.risk == "foregrip_hold" then
		e.verdict = "expect_foregrip"
		e.checklist = "G42 · FOREGREP · left near RH OK while grip active"
		e.pass_line = "Do not unstick during stock foregrip"
		e.fail_line = "False unstick fights foregrip attach"
		return e
	end
	e.verdict = "expect_ok"
	e.checklist = "G42 · OK · hands independent"
	e.pass_line = "L/R free; no glue; primary hand laser still works"
	e.fail_line = "Hands stuck together or tied mid-play"
	return e
end

function vrmod.utils.HandStuckLaw_IsStuckRisk(decision)
	if type(decision) ~= "table" then return false end
	return decision.risk == "stuck_residual"
		or decision.risk == "identity_glue"
		or decision.risk == "collapse"
end
