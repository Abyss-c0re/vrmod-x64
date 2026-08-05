-- G13: Return-to-Cube reverse handoff protocol (pure format/parse — offline-tested).
-- GMod writes garrysmod/data/vrmod/cube_return.txt on VR exit after Cube launch.
-- Cube shell reclaim (re-open OpenXR) is NOT implemented yet — marker is the contract.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

local VALID = {
	vr_exit = true,
	xr_released = true,
	cube_claim = true, -- reserved for Cube shell
	panel_live = true, -- reserved when Cube reclaims
}

--- Normalize reverse phase token.
function vrmod.utils.CubeReturn_NormalizePhase(raw)
	local s = string.lower(tostring(raw or ""):gsub("^%s+", ""):gsub("%s+$", ""))
	if VALID[s] then return s end
	if s == "" then return "vr_exit" end
	return s
end

--- Normalize intent: vr_exit | temp_return | resume
function vrmod.utils.CubeReturn_NormalizeIntent(raw)
	local s = string.lower(tostring(raw or ""):gsub("^%s+", ""):gsub("%s+$", ""))
	if s == "temp_return" or s == "temporary" or s == "launcher" then
		return "temp_return"
	end
	if s == "resume" then return "resume" end
	if s == "vr_exit" or s == "exit" or s == "" then return "vr_exit" end
	return s
end

--- Pure format body for cube_return.txt
--- opts: map, source, ts, intent (vr_exit | temp_return | resume)
function vrmod.utils.CubeReturn_Format(phase, opts)
	opts = type(opts) == "table" and opts or {}
	phase = vrmod.utils.CubeReturn_NormalizePhase(phase)
	local ts = tonumber(opts.ts) or 0
	local map = tostring(opts.map or "")
	local source = tostring(opts.source or "vrmod")
	local intent = vrmod.utils.CubeReturn_NormalizeIntent(opts.intent or "vr_exit")
	return table.concat({
		"v=1",
		"phase=" .. phase,
		"map=" .. map,
		"source=" .. source,
		"intent=" .. intent,
		"ts=" .. tostring(ts),
	}, "\n") .. "\n"
end

--- Pure parse. Returns table or nil if invalid.
function vrmod.utils.CubeReturn_Parse(body)
	if type(body) ~= "string" or body == "" then return nil end
	local out = {
		version = 1,
		phase = "vr_exit",
		map = "",
		source = "vrmod",
		intent = "vr_exit",
		ts = 0,
		valid = false,
	}
	local gotPhase = false
	for line in string.gmatch(body, "[^\r\n]+") do
		line = line:gsub("^%s+", ""):gsub("%s+$", "")
		if line ~= "" and line:sub(1, 1) ~= "#" then
			local k, v = line:match("^([^=]+)=(.*)$")
			if k then
				k = k:gsub("^%s+", ""):gsub("%s+$", "")
				v = v:gsub("^%s+", ""):gsub("%s+$", "")
				if k == "v" or k == "version" then
					out.version = tonumber(v) or 1
				elseif k == "phase" then
					out.phase = vrmod.utils.CubeReturn_NormalizePhase(v)
					gotPhase = true
				elseif k == "map" then
					out.map = v
				elseif k == "source" then
					out.source = v ~= "" and v or "vrmod"
				elseif k == "intent" then
					out.intent = vrmod.utils.CubeReturn_NormalizeIntent(v)
				elseif k == "ts" then
					out.ts = tonumber(v) or 0
				end
			end
		end
	end
	out.valid = gotPhase
	if not out.valid then return nil end
	return out
end

function vrmod.utils.CubeReturn_PhaseLabel(phase)
	phase = vrmod.utils.CubeReturn_NormalizePhase(phase)
	if phase == "vr_exit" then return "VR EXIT" end
	if phase == "xr_released" then return "XR RELEASED" end
	if phase == "cube_claim" then return "CUBE CLAIM" end
	if phase == "panel_live" then return "PANEL LIVE" end
	return string.upper(phase)
end

--- True when this VR session should write a return marker (Cube product path only).
function vrmod.utils.CubeReturn_ShouldNotifyCube(isOpenxrLaunch, wasVrActive)
	return (isOpenxrLaunch and true or false) and (wasVrActive and true or false)
end

--- Human detail for reverse panel / Cube reclaim UI.
function vrmod.utils.CubeReturn_DetailForPhase(phase, intent)
	phase = vrmod.utils.CubeReturn_NormalizePhase(phase)
	intent = vrmod.utils.CubeReturn_NormalizeIntent(intent)
	if intent == "temp_return" then
		if phase == "xr_released" or phase == "vr_exit" then
			return "GMod kept · temporary return · START resumes VR"
		end
	end
	if phase == "vr_exit" then
		return "GMod left VR · Cube shell should reclaim panel"
	end
	if phase == "xr_released" then
		return "OpenXR free · Cube launcher reclaim"
	end
	if phase == "cube_claim" then
		return "Cube claiming OpenXR…"
	end
	if phase == "panel_live" then
		return "Cube panel live · reverse handoff complete"
	end
	return "return-to-Cube protocol"
end

--- True when GMod should spawn CubeUI after releasing XR.
function vrmod.utils.CubeReturn_ShouldRelaunchCube(isOpenxrLaunch, wasVrActive)
	return vrmod.utils.CubeReturn_ShouldNotifyCube(isOpenxrLaunch, wasVrActive)
end
