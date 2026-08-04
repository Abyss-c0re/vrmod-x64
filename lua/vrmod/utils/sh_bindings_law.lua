-- G31: action-manifest / bindings self-heal law (pure, offline-tested).
-- Watchlist W6 / pain soft-care: force-rewrite DATA bindings each start is intentional;
-- on SetActionManifest fail: retry once after rewrite; honest toast — never silent death.
-- VR must continue without bindings (never abort start). Do not skip toast path.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

--- Relative path under garrysmod/data/ (module resolves DATA root).
function vrmod.utils.BindingsLaw_ManifestRelPath()
	return "vrmod/vrmod_action_manifest.txt"
end

function vrmod.utils.BindingsLaw_DataDir()
	return "vrmod"
end

--- Cube law: always force-rewrite DATA bindings on VR start (self-heal corrupt / stale).
function vrmod.utils.BindingsLaw_ForceRewriteOnStart()
	return true
end

--- One retry after force rewrite on first SetActionManifest failure.
function vrmod.utils.BindingsLaw_MaxSetAttempts()
	return 2
end

function vrmod.utils.BindingsLaw_ShouldRetryAfterFail(attemptIndex)
	attemptIndex = tonumber(attemptIndex) or 0
	return attemptIndex < vrmod.utils.BindingsLaw_MaxSetAttempts()
end

--- Never abort VR start when bindings fail (product continues without input actions).
function vrmod.utils.BindingsLaw_AbortVrOnFail()
	return false
end

--- Fail path must toast (honest error; no silent death).
function vrmod.utils.BindingsLaw_RequireToastOnFail()
	return true
end

function vrmod.utils.BindingsLaw_ToastSeconds()
	return 8
end

function vrmod.utils.BindingsLaw_ToastMessage()
	return "Controller bindings failed — reinstall VRMod module; ensure data/vrmod/vrmod_action_manifest.txt exists. Restart VR runtime if needed."
end

function vrmod.utils.BindingsLaw_ErrorOverlayText()
	return "Bindings failed — check console / reinstall module"
end

function vrmod.utils.BindingsLaw_OverlayClearSeconds()
	return 12
end

--- Pure decision after setup attempts.
--- opts:
---   force_rewrite bool|nil     did product rewrite before first set (default true)
---   first_ok bool              first SetActionManifest ok
---   retry_ok bool|nil          second attempt ok (if first failed)
---   has_file bool|nil          DATA file exists after rewrite
---   toast_shown bool|nil       product did show toast on fail
function vrmod.utils.BindingsLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local force = opts.force_rewrite
	if force == nil then force = true end
	local firstOk = opts.first_ok and true or false
	local retryOk = opts.retry_ok and true or false
	local hasFile = opts.has_file and true or false
	local toastShown = opts.toast_shown
	local ok = firstOk or retryOk
	local d = {
		valid = true,
		force_rewrite = force and true or false,
		first_ok = firstOk,
		retry_ok = retryOk,
		ok = ok,
		has_file = hasFile,
		toast_shown = toastShown == true,
		abort_vr = false, -- law: never
		should_toast = not ok,
		require_toast = vrmod.utils.BindingsLaw_RequireToastOnFail(),
		risk = "none", -- none | missing_file | set_fail | silent_fail | no_rewrite
		reason = "ok",
		path_ok = true,
	}
	if not force then
		d.risk = "no_rewrite"
		d.reason = "skipped_force_rewrite"
		d.path_ok = false
	elseif ok then
		d.risk = "none"
		d.reason = firstOk and "set_ok_first" or "set_ok_after_retry"
		d.path_ok = true
	elseif not hasFile then
		d.risk = "missing_file"
		d.reason = "manifest_missing_after_rewrite"
		d.path_ok = false
	else
		d.risk = "set_fail"
		d.reason = "set_action_manifest_failed"
		d.path_ok = false
	end
	-- Silent death: fail without toast when toast is required
	if not ok and d.require_toast and toastShown == false then
		d.risk = "silent_fail"
		d.reason = "fail_without_toast"
		d.path_ok = false
	end
	d.abort_vr = vrmod.utils.BindingsLaw_AbortVrOnFail()
	return d
end

function vrmod.utils.BindingsLaw_StatusLabel(decision)
	if type(decision) ~= "table" then return "BIND · IDLE" end
	if decision.risk == "silent_fail" then return "BIND · SILENT FAIL" end
	if decision.risk == "no_rewrite" then return "BIND · NO REWRITE" end
	if decision.risk == "missing_file" then return "BIND · MISSING FILE" end
	if decision.risk == "set_fail" then return "BIND · SET FAIL" end
	if decision.ok and decision.retry_ok and not decision.first_ok then return "BIND · RETRY OK" end
	if decision.ok then return "BIND · OK" end
	return "BIND · HOLD"
end

--- Pure observer contract (offline ≠ HMD / SteamVR walk proof).
function vrmod.utils.BindingsLaw_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_toast_on_fail = true,
		expect_vr_continues = true,
		checklist = "G31 · IDLE · no bindings decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if decision.risk == "silent_fail" then
		e.verdict = "expect_silent_fail"
		e.expect_toast_on_fail = false
		e.checklist = "G31 · SILENT · fail without toast (forbidden)"
		e.pass_line = "Must toast on SetActionManifest fail"
		e.fail_line = "Silent death / no Crimson toast"
		return e
	end
	if decision.ok then
		e.verdict = "expect_ok"
		e.checklist = "G31 · OK · force rewrite + SetActionManifest · " .. tostring(decision.reason)
		e.pass_line = "Controllers live after start; no bindings toast"
		e.fail_line = "Manifest set fails or inputs dead with silent log only"
		return e
	end
	e.verdict = "expect_fail_honest"
	e.checklist = "G31 · FAIL HONEST · toast + continue VR · " .. tostring(decision.reason)
	e.pass_line = "Toast + overlay; VR session still up without actions"
	e.fail_line = "Abort VR start or silent fail"
	return e
end

function vrmod.utils.BindingsLaw_IsSilentFailRisk(decision)
	if type(decision) ~= "table" then return true end
	return decision.risk == "silent_fail" or (not decision.ok and decision.toast_shown == false)
end
