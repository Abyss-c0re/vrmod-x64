-- G05: stereo policy during load / early handoff (pure, offline-tested).
-- Goal: avoid flat/mono load flash when safe; never force dual-eye under mat_queue≥2
-- (CThread crash law — pain point).
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

--- Pure loading detector from discrete engine-ish flags (no engine I/O).
--- opts:
---   is_in_game           bool|nil  IsInGame()
---   local_player_valid   bool|nil  IsValid(LocalPlayer())
---   map_name             string|nil game.GetMap()
---   map_changing         bool|nil  changelevel / mid-join
---   force_loading        bool|nil
--- Returns true when frame path should treat session as "loading".
function vrmod.utils.StereoLoad_IsLoading(opts)
	opts = type(opts) == "table" and opts or {}
	if opts.force_loading then return true end
	if opts.map_changing then return true end
	if opts.is_in_game == false then return true end
	if opts.local_player_valid == false then return true end
	local map = opts.map_name
	if type(map) == "string" then
		map = map:gsub("^%s+", ""):gsub("%s+$", "")
		if map == "" or map == "nil" then return true end
	end
	return false
end

--- Pure stereo-load policy from discrete flags (no engine I/O).
--- opts:
---   mat_queue_mode  (number, default 1)
---   vr_active       (bool)
---   loading         (bool) — map/menu boot, LocalPlayer not ready, etc.
---   openxr_should_render (bool|nil) — nil treated as true
---
--- Returns table:
---   dual_eye                 — both RealRenderView passes allowed
---   single_pass              — mq≥2 path (right half intentional clear)
---   keep_submit              — EndFrame/Submit while VR active
---   prefer_paint_while_load  — keep dual paint during load even if compositor skips
---   fill_black_stereo_pair   — prefer black stereo pair over mono void
---   loading                  — echoed loading flag used
function vrmod.utils.StereoLoadPolicy(opts)
	opts = type(opts) == "table" and opts or {}
	local mq = tonumber(opts.mat_queue_mode)
	if mq == nil then mq = 1 end
	local active = opts.vr_active and true or false
	local loading = opts.loading and true or false
	local oxr = opts.openxr_should_render
	if oxr == nil then oxr = true end
	oxr = oxr and true or false

	-- Pain point: never dual-eye under mat_queue 2 (Linux CThread)
	local dualEye = mq < 2
	local singlePass = not dualEye
	local keepSubmit = active
	-- During load: if dual-eye is legal, keep painting stereo so HMD is not flat/void
	local preferPaint = active and dualEye and (loading or not oxr)
	local fillBlack = active and (loading or not oxr or singlePass)

	return {
		dual_eye = dualEye,
		single_pass = singlePass,
		keep_submit = keepSubmit,
		prefer_paint_while_load = preferPaint,
		fill_black_stereo_pair = fillBlack,
		mat_queue_mode = mq,
		loading = loading,
	}
end

--- True when the frame path should still call dual-eye PerformRenderViews.
--- openxrShouldRender false alone must not drop stereo during load if dual-eye is legal.
function vrmod.utils.ShouldPaintStereoThisFrame(policy, openxrShouldRender)
	if type(policy) ~= "table" then return openxrShouldRender and true or false end
	if not policy.keep_submit then return false end
	if openxrShouldRender then return true end
	-- Compositor said no-render: still paint if load/handoff policy wants dual hold
	return policy.prefer_paint_while_load and true or false
end

--- Compact panel/log token (pure).
function vrmod.utils.StereoLoad_StatusLabel(policy)
	if type(policy) ~= "table" then return "STEREO · IDLE" end
	if policy.single_pass then
		return "STEREO · MQ2 SINGLE"
	end
	if policy.prefer_paint_while_load then
		return "STEREO · DUAL HOLD LOAD"
	end
	if policy.dual_eye and policy.keep_submit then
		return "STEREO · DUAL"
	end
	if not policy.keep_submit then
		return "STEREO · NO SUBMIT"
	end
	return "STEREO · HOLD"
end

--- Short toast/log line for G05 awareness (no mutation).
function vrmod.utils.StereoLoadToastHint(policy)
	if type(policy) ~= "table" then return nil end
	if policy.single_pass then
		return "Stereo load · single-pass (mat_queue 2) · both eyes from left (mono)"
	end
	if policy.prefer_paint_while_load then
		return "Stereo load · dual-eye hold through load"
	end
	if policy.dual_eye then
		return "Stereo load · dual-eye"
	end
	return nil
end

--- Pure one-shot toast gate: true only on rising edge of prefer_paint_while_load.
function vrmod.utils.StereoLoad_ShouldToast(policy, alreadyToasted)
	if alreadyToasted then return false end
	if type(policy) ~= "table" then return false end
	return policy.prefer_paint_while_load and true or false
end

-- ── G05 HMD load-flash expect (pure observer contract) ───────────────────────
-- Offline-tested checklist tokens for headset smoke. Never claims HMD passed.
-- flash_risk:
--   none              both eyes content expected (dual hold or dual idle)
--   mono_void         no submit / inactive — void risk
--   mq2_mono_both     single-pass law; both HMD eyes sample left half (not dual)
--   no_submit         VR not keeping submit

--- Pure HMD observer expectation from StereoLoadPolicy result.
--- Returns:
---   expect_both_eyes   bool  both eyes should show content (not flat mono void)
---   flash_risk         string none|mono_void|mq2_mono_both|no_submit
---   verdict            string expect_dual_hold|expect_dual|expect_mq2_single|expect_no_submit|idle
---   pass_line          string what PASS looks like in HMD
---   fail_line          string what FAIL looks like
---   checklist          string one-line smoke sheet row
function vrmod.utils.StereoLoad_HmdExpect(policy)
	local e = {
		expect_both_eyes = false,
		flash_risk = "mono_void",
		verdict = "idle",
		pass_line = "N/A",
		fail_line = "N/A",
		checklist = "G05 · idle · no VR frame policy",
	}
	if type(policy) ~= "table" then return e end

	if not policy.keep_submit then
		e.flash_risk = "no_submit"
		e.verdict = "expect_no_submit"
		e.expect_both_eyes = false
		e.pass_line = "No XR submit expected (VR inactive)"
		e.fail_line = "Unexpected stereo submit while keep_submit=false"
		e.checklist = "G05 · NO SUBMIT · skip load-flash check"
		return e
	end

	if policy.single_pass then
		-- Both eyes should show left content (submit UV mirror) — not one black eye
		e.flash_risk = "mq2_mono_both"
		e.verdict = "expect_mq2_single"
		e.expect_both_eyes = true
		e.pass_line = "Single-pass: both HMD eyes from left half (mat_queue 2 mono)"
		e.fail_line = "One eye black, or dual-paint under mq≥2 (forbidden crash path)"
		e.checklist = "G05 · MQ2 MONO BOTH · left UV for L+R · never second RenderView"
		return e
	end

	if policy.prefer_paint_while_load then
		e.flash_risk = "none"
		e.verdict = "expect_dual_hold"
		e.expect_both_eyes = true
		e.pass_line = "Both eyes stereo through load; may dim/black pair but not flat mono void"
		e.fail_line = "Flat mono, one eye missing, or long virgin black flash"
		e.checklist = "G05 · DUAL HOLD LOAD · both eyes content · toast ok once"
		return e
	end

	if policy.dual_eye then
		e.flash_risk = "none"
		e.verdict = "expect_dual"
		e.expect_both_eyes = true
		e.pass_line = "Both eyes clear stereo (live play)"
		e.fail_line = "Mono mirror only or eng-IN submit flash"
		e.checklist = "G05 · DUAL · both eyes clear"
		return e
	end

	e.flash_risk = "mono_void"
	e.verdict = "idle"
	e.expect_both_eyes = false
	e.pass_line = "Hold path without dual policy"
	e.fail_line = "Unexpected dual thrash"
	e.checklist = "G05 · HOLD · observe only"
	return e
end

--- True when HMD observer should treat current policy as load-flash risk (fail-prone).
function vrmod.utils.StereoLoad_FlashRiskIsBad(expect)
	if type(expect) ~= "table" then return true end
	local r = expect.flash_risk
	return r == "mono_void" or r == "no_submit"
end
