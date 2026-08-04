-- G39: VR_Init error surface law (pure, offline-tested).
-- Watchlist W11: VR_Init 108 / 215, PSVR2 crash.
-- Cube way: surface codes as human Cube text; link module zip version.
-- Platform triage: log + lower SS + verify SteamVR/OpenXR — never silent crash.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

function vrmod.utils.InitLaw_ModuleZipUrl()
	return "https://github.com/Abyss-c0re/gVRMod/releases"
end

function vrmod.utils.InitLaw_MinModuleVersion()
	return 20
end

function vrmod.utils.InitLaw_CrispModuleVersion()
	return 23
end

--- Known legacy OpenVR / platform codes (W11) + OpenXR string cues.
local CODE_HUMAN = {
	[108] = "HMD not found (108) — start SteamVR/OpenXR runtime; check headset cable/power.",
	[215] = "VR runtime busy or interface failed (215) — close other VR apps; restart SteamVR; retry.",
	[100] = "VR init installation issue (100) — reinstall SteamVR / OpenXR runtime.",
	[105] = "VR interface not found (105) — update SteamVR and gVRMod module zip.",
	[200] = "VR driver failed (200) — update GPU drivers; verify HMD drivers.",
}

function vrmod.utils.InitLaw_KnownCodeMessage(code)
	code = tonumber(code)
	if not code then return nil end
	return CODE_HUMAN[code]
end

--- Extract first integer code from error blob (108, 215, XrResult ints, etc.).
function vrmod.utils.InitLaw_ParseCode(err)
	err = tostring(err or "")
	-- Prefer explicit "code 108" / "(108)" / "error 215"
	local c = err:match("[Cc]ode%s*[:=]?%s*(%d+)")
		or err:match("%((%-?%d+)%)")
		or err:match("[Ee]rror%s*[:=]?%s*(%d+)")
		or err:match("failed%s*%((%-?%d+)%)")
	if c then return tonumber(c) end
	-- Bare standalone known codes
	for code in pairs(CODE_HUMAN) do
		if err:find(tostring(code), 1, true) then return code end
	end
	return nil
end

function vrmod.utils.InitLaw_IsNoHmdHint(err)
	err = string.lower(tostring(err or ""))
	return err:find("hmd", 1, true) ~= nil
		or err:find("no headset", 1, true) ~= nil
		or err:find("form_factor", 1, true) ~= nil
		or err:find("not detected", 1, true) ~= nil
end

function vrmod.utils.InitLaw_IsRuntimeHint(err)
	err = string.lower(tostring(err or ""))
	return err:find("openxr", 1, true) ~= nil
		or err:find("openvr", 1, true) ~= nil
		or err:find("steamvr", 1, true) ~= nil
		or err:find("loader", 1, true) ~= nil
		or err:find("runtime", 1, true) ~= nil
end

function vrmod.utils.InitLaw_IsModuleHint(err)
	err = string.lower(tostring(err or ""))
	return err:find("module", 1, true) ~= nil
		or err:find("binary", 1, true) ~= nil
		or err:find("version", 1, true) ~= nil
end

--- Build human toast (short) + overlay (longer) from init failure.
--- opts: err, code, module_version, backend
function vrmod.utils.InitLaw_Humanize(opts)
	opts = type(opts) == "table" and opts or {}
	local err = tostring(opts.err or opts.error or "")
	local code = opts.code or vrmod.utils.InitLaw_ParseCode(err)
	local modV = tonumber(opts.module_version) or 0
	local backend = tostring(opts.backend or "openxr")
	local known = code and vrmod.utils.InitLaw_KnownCodeMessage(code) or nil
	local lines = {}
	if known then
		lines[#lines + 1] = known
	elseif err ~= "" and err ~= "VRMOD_Init returned false" then
		-- First line of thrown error (before log path noise)
		local first = err:match("([^\n]+)") or err
		if #first > 120 then first = first:sub(1, 117) .. "..." end
		lines[#lines + 1] = first
	else
		lines[#lines + 1] = "VR_Init failed — is OpenXR/SteamVR running with HMD awake?"
	end
	if code then
		lines[#lines + 1] = "Code: " .. tostring(code)
	end
	lines[#lines + 1] = "Module: v" .. tostring(modV) .. " · backend " .. backend
	if modV > 0 and modV < vrmod.utils.InitLaw_MinModuleVersion() then
		lines[#lines + 1] = "Module too old — install zip: " .. vrmod.utils.InitLaw_ModuleZipUrl()
	else
		lines[#lines + 1] = "Module zip: " .. vrmod.utils.InitLaw_ModuleZipUrl()
	end
	if vrmod.utils.InitLaw_IsNoHmdHint(err) or (code == 108) then
		lines[#lines + 1] = "Tip: put on HMD; start SteamVR/OpenXR; check cable."
	elseif vrmod.utils.InitLaw_IsRuntimeHint(err) or (code == 215) then
		lines[#lines + 1] = "Tip: restart SteamVR; close other VR apps; lower supersample after start."
	else
		lines[#lines + 1] = "Tip: restart runtime; verify module binary; see vrmod_debug.log."
	end
	local overlay = table.concat(lines, "\n")
	local toast = known or lines[1]
	if code and not known then
		toast = "VR_Init failed (code " .. tostring(code) .. ") — runtime / HMD?"
	elseif not known then
		toast = "VR_Init failed — OpenXR/SteamVR running? Module v" .. tostring(modV)
	end
	return {
		code = code,
		toast = toast,
		overlay = overlay,
		module_version = modV,
		backend = backend,
		module_url = vrmod.utils.InitLaw_ModuleZipUrl(),
	}
end

function vrmod.utils.InitLaw_ToastSeconds()
	return 10
end

function vrmod.utils.InitLaw_RequireToastOnFail()
	return true
end

function vrmod.utils.InitLaw_SilentFailForbidden()
	return true
end

--- Pure decision after init attempt.
--- opts: ok, err, code, module_version, backend, toast_shown
function vrmod.utils.InitLaw_Decide(opts)
	opts = type(opts) == "table" and opts or {}
	local ok = opts.ok and true or false
	local human = vrmod.utils.InitLaw_Humanize(opts)
	local d = {
		valid = true,
		ok = ok,
		code = human.code,
		toast = human.toast,
		overlay = human.overlay,
		module_version = human.module_version,
		backend = human.backend,
		toast_shown = opts.toast_shown == true,
		require_toast = vrmod.utils.InitLaw_RequireToastOnFail(),
		risk = "none", -- none | silent_fail | init_fail | module_old
		reason = "ok",
		path_ok = ok,
	}
	if ok then
		d.reason = "init_ok"
		d.path_ok = true
	elseif opts.toast_shown == false and d.require_toast then
		d.risk = "silent_fail"
		d.reason = "init_fail_no_toast"
		d.path_ok = false
	else
		d.risk = "init_fail"
		d.reason = human.code and ("init_code_" .. tostring(human.code)) or "init_failed"
		d.path_ok = false
		if human.module_version > 0 and human.module_version < vrmod.utils.InitLaw_MinModuleVersion() then
			d.risk = "module_old"
		end
	end
	return d
end

function vrmod.utils.InitLaw_StatusLabel(decision)
	if type(decision) ~= "table" then return "INIT · IDLE" end
	if decision.ok then return "INIT · OK" end
	if decision.risk == "silent_fail" then return "INIT · SILENT FAIL" end
	if decision.risk == "module_old" then return "INIT · MODULE OLD" end
	if decision.code then return "INIT · FAIL " .. tostring(decision.code) end
	return "INIT · FAIL"
end

function vrmod.utils.InitLaw_HmdExpect(decision)
	local e = {
		verdict = "idle",
		expect_human_toast = true,
		checklist = "G39 · IDLE · no init decision",
		pass_line = "N/A",
		fail_line = "N/A",
	}
	if type(decision) ~= "table" or not decision.valid then return e end
	if decision.ok then
		e.verdict = "expect_ok"
		e.checklist = "G39 · OK · VR_Init / OpenXR session path"
		e.pass_line = "Session starts; both eyes; no silent death"
		e.fail_line = "Crash without toast / code"
		return e
	end
	if decision.risk == "silent_fail" then
		e.verdict = "expect_silent_fail"
		e.expect_human_toast = false
		e.checklist = "G39 · SILENT · init fail without toast (forbidden)"
		e.pass_line = "Must toast human text + module link"
		e.fail_line = "Silent crash / empty error"
		return e
	end
	e.verdict = "expect_fail_honest"
	e.checklist = "G39 · FAIL HONEST · code=" .. tostring(decision.code or "?")
	e.pass_line = "Cube toast names code; module zip linked; triage tips"
	e.fail_line = "Opaque 'failed' or hard crash only"
	return e
end

function vrmod.utils.InitLaw_IsSilentFailRisk(decision)
	if type(decision) ~= "table" then return true end
	return decision.risk == "silent_fail"
end
