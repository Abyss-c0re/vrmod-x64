-- G05: stereo policy during load / early handoff (pure, offline-tested).
-- Goal: avoid flat/mono load flash when safe; never force dual-eye under mat_queue≥2
-- (CThread crash law — pain point).
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

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

--- Short toast/log line for G05 awareness (no mutation).
function vrmod.utils.StereoLoadToastHint(policy)
	if type(policy) ~= "table" then return nil end
	if policy.single_pass then
		return "Stereo load · single-pass (mat_queue 2) · right eye clear by law"
	end
	if policy.prefer_paint_while_load then
		return "Stereo load · dual-eye hold through load"
	end
	if policy.dual_eye then
		return "Stereo load · dual-eye"
	end
	return nil
end
