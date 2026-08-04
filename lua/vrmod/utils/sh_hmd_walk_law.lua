-- G41: HMD walk backlog inventory (pure, offline-tested).
-- Catalog of partial gaps that still need headset proof (offline green ≠ HMD OK).
-- Cube way: one living inventory; dump labels for operators; never claim smoke from pure alone.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

--- Frozen catalog of manual HMD walks (gap id → § walk → pure helper → runtime snapshot key).
--- status is always "open" here until a human marks done in GLOGIC_GAPS (pure law does not close walks).
function vrmod.utils.HmdWalk_Catalog()
	return {
		{ id = "G05", pri = "P0", section = "0.1", pure = "StereoLoad_HmdExpect", snap = "_stereoLoadHmdExpect", theme = "stereo load dual-hold" },
		{ id = "G12", pri = "P1", section = "0.2", pure = "CubeAmbient_HmdVolumeExpect", snap = nil, theme = "handoff ambient volume taste" },
		{ id = "G13", pri = "P1", section = "0.3", pure = "CubeReclaim_HmdExpect", snap = nil, theme = "return-to-Cube reclaim" },
		{ id = "G03", pri = "P0", section = "0.4", pure = "StagePack_HmdExpect", snap = "_cubeStagePackHmdExpect", theme = "STAGE height pack apply" },
		{ id = "G14", pri = "P1", section = "0.5", pure = "Glide_HmdExpect", snap = "_glideHmdExpect", theme = "Glide stick steer" },
		{ id = "G04", pri = "P0", section = "0.6", pure = "WarmAttach_HmdExpect", snap = "_cubeWarmHmdExpect", theme = "warm attach / cold Start" },
		{ id = "G15", pri = "P1", section = "0.7", pure = "HudLaw_HmdExpect", snap = "_hudLawHmdExpect", theme = "HUD additive / no black slab" },
		{ id = "G16", pri = "P1", section = "0.8", pure = "LaserLaw_HmdExpect", snap = "_laserLawHmdExpect", theme = "laser + primary hand UI" },
		{ id = "G17", pri = "P1", section = "0.9", pure = "MatQueueLaw_HmdExpect", snap = "_matQueueLawHmdExpect", theme = "mat_queue pin never 2" },
		{ id = "G18", pri = "P1", section = "0.10", pure = "WindowChrome_HmdExpect", snap = nil, theme = "framed desktop chrome" },
		{ id = "G19", pri = "P1", section = "0.11", pure = "SubmitLaw_HmdExpect", snap = "_submitLawHmdExpect", theme = "submit dual OUT only" },
		{ id = "G25", pri = "P1", section = "0.12", pure = "PoseSoT_HmdExpect", snap = "_poseSoTHmdExpect", theme = "pose single path" },
		{ id = "G26", pri = "P1", section = "0.13", pure = "MenuLaw_HmdExpect", snap = "_menuLawHmdExpect", theme = "QM menu thrash / VRClimb" },
		{ id = "G27", pri = "P1", section = "0.14", pure = "EngineBlacklist_HmdExpect", snap = "_engineBlacklistHmdExpect", theme = "engine blacklist never-call" },
		{ id = "G28", pri = "P0", section = "0.15", pure = "CubeHandoffTimeout_HmdExpect", snap = nil, theme = "soft handoff timeouts" },
		{ id = "G29", pri = "P0", section = "0.16", pure = "CubeSs_HmdExpect", snap = nil, theme = "SS cold-start cap" },
		{ id = "G30", pri = "P0", section = "0.17", pure = "CubeFov_HmdExpect", snap = nil, theme = "FOV archive write-when-touched" },
		{ id = "G31", pri = "P1", section = "0.18", pure = "BindingsLaw_HmdExpect", snap = "_bindingsLawHmdExpect", theme = "action-manifest self-heal" },
		{ id = "G32", pri = "P1", section = "0.19", pure = "StereoSelfTest_HmdExpect", snap = "_stereoSelfTestHmdExpect", theme = "ShareTexture / HMD self-test" },
		{ id = "G33", pri = "P1", section = "0.20", pure = "SwapEyesLaw_HmdExpect", snap = "_swapEyesLawHmdExpect", theme = "swap-eyes content-only" },
		{ id = "G34", pri = "P1", section = "0.21", pure = "FlyAwayLaw_HmdExpect", snap = "_flyAwayLawHmdExpect", theme = "fly-away origin snap" },
		{ id = "G35", pri = "P1", section = "0.22", pure = "ViewScaleLaw_HmdExpect", snap = "_viewScaleLawHmdExpect", theme = "viewscale fisheye comfort" },
		{ id = "G36", pri = "P1", section = "0.23", pure = "FovZLaw_HmdExpect", snap = "_fovZLawHmdExpect", theme = "FOV/Z soft-refresh" },
		{ id = "G37", pri = "P1", section = "0.24", pure = "HandBulletLaw_HmdExpect", snap = "_handBulletLawHmdExpect", theme = "hand vs bullet filter" },
		{ id = "G38", pri = "P1", section = "0.25", pure = "WorldModelLaw_HmdExpect", snap = "_worldModelLawHmdExpect", theme = "worldmodel single path" },
		{ id = "G39", pri = "P1", section = "0.26", pure = "InitLaw_HmdExpect", snap = "_initLawHmdExpect", theme = "VR_Init human surface" },
		{ id = "G40", pri = "P0", section = "0.27", pure = "BorderLaw_HmdExpect", snap = "_borderLawHmdExpect", theme = "Vision border fill" },
		{ id = "G41", pri = "P1", section = "0.28", pure = "HmdWalk_HmdExpect", snap = "_hmdWalkLawHmdExpect", theme = "HMD walk inventory dump" },
		{ id = "G42", pri = "P1", section = "0.29", pure = "HandStuckLaw_HmdExpect", snap = "_handStuckLawHmdExpect", theme = "hands stuck unstick" },
		{ id = "G43", pri = "P1", section = "0.30", pure = "NestedRtLaw_HmdExpect", snap = "_nestedRtLawHmdExpect", theme = "menu-open nested RT crash" },
		{ id = "G44", pri = "P1", section = "0.31", pure = "GrabEndLaw_HmdExpect", snap = "_grabEndLawHmdExpect", theme = "grab_end / drop cooldown" },
		{ id = "G45", pri = "P1", section = "0.32", pure = "LaserLaw_Decide", snap = "_laserLawHmdExpect", theme = "primary-hand left SoT" },
		{ id = "G46", pri = "P0", section = "0.33", pure = "DesktopMirror_HmdExpect", snap = "_desktopMirrorHmdExpect", theme = "desktop vs HMD RT isolation" },
		{ id = "G47", pri = "P0", section = "0.34", pure = "FalsePerEyeLaw_HmdExpect", snap = "_falsePerEyeHmdExpect", theme = "false per-eye FBO guard" },
	}
end

function vrmod.utils.HmdWalk_Count()
	return #vrmod.utils.HmdWalk_Catalog()
end

function vrmod.utils.HmdWalk_FindById(id)
	id = tostring(id or "")
	for _, row in ipairs(vrmod.utils.HmdWalk_Catalog()) do
		if row.id == id then return row end
	end
	return nil
end

function vrmod.utils.HmdWalk_PriorityIsP0(row)
	return type(row) == "table" and row.pri == "P0"
end

function vrmod.utils.HmdWalk_CountP0()
	local n = 0
	for _, row in ipairs(vrmod.utils.HmdWalk_Catalog()) do
		if vrmod.utils.HmdWalk_PriorityIsP0(row) then n = n + 1 end
	end
	return n
end

--- Prefer G05 then G12 when picking next operator walk (product feel).
function vrmod.utils.HmdWalk_PreferredNextIds()
	return { "G05", "G12", "G40", "G28", "G04" }
end

function vrmod.utils.HmdWalk_FormatLine(row)
	if type(row) ~= "table" then return "HMD · ?" end
	local snap = row.snap and ("snap=" .. tostring(row.snap)) or "snap=—"
	return string.format(
		"%s [%s] §%s · %s · pure=%s · %s",
		tostring(row.id),
		tostring(row.pri),
		tostring(row.section),
		tostring(row.theme),
		tostring(row.pure),
		snap
	)
end

function vrmod.utils.HmdWalk_FormatReport(rows)
	rows = type(rows) == "table" and rows or vrmod.utils.HmdWalk_Catalog()
	local lines = {
		"G41 HMD walk inventory — offline pure ≠ headset OK",
		"Walks open (catalog): " .. tostring(#rows),
	}
	for _, row in ipairs(rows) do
		lines[#lines + 1] = vrmod.utils.HmdWalk_FormatLine(row)
	end
	local pref = vrmod.utils.HmdWalk_PreferredNextIds()
	lines[#lines + 1] = "Prefer next: " .. table.concat(pref, ", ")
	return table.concat(lines, "\n")
end

--- Collect live snapshot labels from a g_VR-like table (pure: no engine calls).
--- g: table with optional _*HmdExpect entries (each may be table with checklist/verdict or string).
function vrmod.utils.HmdWalk_CollectLive(g)
	g = type(g) == "table" and g or {}
	local out = {}
	for _, row in ipairs(vrmod.utils.HmdWalk_Catalog()) do
		if row.snap then
			local v = g[row.snap]
			local label = nil
			if type(v) == "table" then
				label = v.checklist or v.verdict or v.pass_line
			elseif type(v) == "string" and v ~= "" then
				label = v
			end
			if label then
				out[#out + 1] = {
					id = row.id,
					snap = row.snap,
					label = tostring(label),
					present = true,
				}
			else
				out[#out + 1] = {
					id = row.id,
					snap = row.snap,
					label = nil,
					present = false,
				}
			end
		end
	end
	return out
end

function vrmod.utils.HmdWalk_FormatLive(liveRows)
	liveRows = type(liveRows) == "table" and liveRows or {}
	local lines = { "G41 live HmdExpect snapshots:" }
	local n = 0
	for _, r in ipairs(liveRows) do
		if r.present then
			n = n + 1
			lines[#lines + 1] = string.format("  %s · %s", tostring(r.id), tostring(r.label))
		end
	end
	if n == 0 then
		lines[#lines + 1] = "  (none present — start VR / exercise path first)"
	end
	return table.concat(lines, "\n")
end

function vrmod.utils.HmdWalk_NeverClaimFromOfflineAlone()
	return true
end

--- Pure decision: inventory health for operators (not a pass/fail of headset).
function vrmod.utils.HmdWalk_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local cat = vrmod.utils.HmdWalk_Catalog()
	local live = vrmod.utils.HmdWalk_CollectLive(opts.g or opts.g_VR)
	local live_n = 0
	for _, r in ipairs(live) do
		if r.present then live_n = live_n + 1 end
	end
	local d = {
		valid = true,
		catalog_n = #cat,
		p0_n = vrmod.utils.HmdWalk_CountP0(),
		live_n = live_n,
		prefer_next = vrmod.utils.HmdWalk_PreferredNextIds(),
		never_offline_smoke = vrmod.utils.HmdWalk_NeverClaimFromOfflineAlone(),
		risk = "none", -- none | empty_catalog | offline_claim
		reason = "inventory_ok",
		path_ok = true,
	}
	if d.catalog_n == 0 then
		d.risk = "empty_catalog"
		d.reason = "no_walk_rows"
		d.path_ok = false
	elseif opts.claimed_hmd_ok_from_offline then
		d.risk = "offline_claim"
		d.reason = "forbidden_offline_smoke_claim"
		d.path_ok = false
	end
	return d
end

function vrmod.utils.HmdWalk_StatusLabel(decision)
	if type(decision) ~= "table" then return "HMDWALK · IDLE" end
	if decision.risk == "empty_catalog" then return "HMDWALK · EMPTY" end
	if decision.risk == "offline_claim" then return "HMDWALK · FORBIDDEN CLAIM" end
	return string.format(
		"HMDWALK · %d open · %d live",
		tonumber(decision.catalog_n) or 0,
		tonumber(decision.live_n) or 0
	)
end

function vrmod.utils.HmdWalk_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_manual = true,
		checklist = "G41 · IDLE · no inventory decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if decision.risk == "offline_claim" then
		e.verdict = "expect_forbidden"
		e.expect_manual = true
		e.checklist = "G41 · FORBIDDEN · offline green claimed as HMD smoke"
		e.pass_line = "Only claim after real headset walk of preferred rows"
		e.fail_line = "PR/status says HMD OK from pure tests alone"
		return e
	end
	if decision.risk == "empty_catalog" then
		e.verdict = "expect_empty"
		e.checklist = "G41 · EMPTY · inventory missing"
		e.pass_line = "Restore HmdWalk_Catalog rows"
		e.fail_line = "No walk backlog guidance"
		return e
	end
	e.verdict = "expect_manual_walks"
	local pref = decision.prefer_next or vrmod.utils.HmdWalk_PreferredNextIds()
	e.checklist = "G41 · MANUAL · prefer " .. table.concat(pref, "/")
	e.pass_line = "Walk G05 load-flash + G12 ambient first; dump live snaps"
	e.fail_line = "Ship Ideal VR claim without any HMD walk"
	return e
end
