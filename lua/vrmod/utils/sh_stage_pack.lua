-- G03: Cube STAGE / cal continuity pack — pure parse + hint (offline-tested).
-- Launcher writes garrysmod/data/vrmod/cube_stage_pack.txt; GMod may read after claim.
-- Law: do not auto-apply head/origin/scale from this pack without a careful, tested path.
-- This module only parses + builds toast copy. No convar / origin mutation.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

local function trim(s)
	s = tostring(s or "")
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Normalize ref space token (STAGE | LOCAL | VIEW | other upper).
function vrmod.utils.StagePack_NormalizeSpace(raw)
	local s = string.upper(trim(raw))
	if s == "STAGE" or s == "LOCAL" or s == "VIEW" then return s end
	if s == "" then return "LOCAL" end
	return s
end

--- True when pack is usable for space preference (STAGE or LOCAL). head_ok optional.
function vrmod.utils.StagePack_IsUsable(pack)
	if type(pack) ~= "table" or not pack.valid then return false end
	local sp = vrmod.utils.StagePack_NormalizeSpace(pack.ref_space)
	return sp == "STAGE" or sp == "LOCAL"
end

--- Parse key=value body from cube_stage_pack.txt. Pure — no file I/O.
--- Returns snapshot table or nil if invalid.
function vrmod.utils.StagePack_Parse(body)
	if type(body) ~= "string" or body == "" then return nil end
	local out = {
		version = 1,
		ref_space = "LOCAL",
		head_x = 0,
		head_y = 0,
		head_z = 0,
		head_ok = false,
		viewscale = 1,
		scalefactor = 1,
		supersample = 1,
		map = "",
		source = "cube_webui",
		ts = 0,
		valid = false,
	}
	local gotSpace = false
	for line in string.gmatch(body, "[^\r\n]+") do
		line = trim(line)
		if line ~= "" and line:sub(1, 1) ~= "#" and line:sub(1, 1) ~= ";" then
			local k, v = line:match("^([^=]+)=(.*)$")
			if k then
				k = trim(k)
				v = trim(v)
				if k == "v" or k == "version" then
					out.version = tonumber(v) or 1
				elseif k == "ref_space" or k == "space" then
					out.ref_space = vrmod.utils.StagePack_NormalizeSpace(v)
					gotSpace = out.ref_space ~= ""
				elseif k == "head_x_m" or k == "head_x" then
					out.head_x = tonumber(v) or 0
				elseif k == "head_y_m" or k == "head_y" then
					out.head_y = tonumber(v) or 0
				elseif k == "head_z_m" or k == "head_z" then
					out.head_z = tonumber(v) or 0
				elseif k == "head_ok" then
					out.head_ok = (v == "1" or v == "true")
				elseif k == "viewscale" then
					out.viewscale = tonumber(v) or 1
				elseif k == "scalefactor" then
					out.scalefactor = tonumber(v) or 1
				elseif k == "supersample" then
					out.supersample = tonumber(v) or 1
				elseif k == "map" then
					out.map = v
				elseif k == "source" then
					out.source = (v ~= "" and v) or "cube_webui"
				elseif k == "ts" then
					out.ts = tonumber(v) or 0
				end
			end
		end
	end
	if (out.version or 0) <= 0 then out.version = 1 end
	-- Clamp scales (match launcher sanity)
	if out.viewscale < 0.05 then out.viewscale = 1 end
	if out.viewscale > 4 then out.viewscale = 4 end
	if out.scalefactor < 0.05 then out.scalefactor = 1 end
	if out.scalefactor > 4 then out.scalefactor = 4 end
	if out.supersample < 0.5 then out.supersample = 0.5 end
	if out.supersample > 3 then out.supersample = 3 end
	-- Extreme head Y → clear head_ok (space pack still valid)
	if out.head_ok and (out.head_y < 0.2 or out.head_y > 2.8) then
		out.head_ok = false
	end
	out.valid = gotSpace
	if not out.valid then return nil end
	return out
end

--- Short toast / log line for continuity awareness. No mutation advice.
--- Returns string or nil if pack not usable.
function vrmod.utils.StagePack_ToastHint(pack)
	if not vrmod.utils.StagePack_IsUsable(pack) then return nil end
	local sp = vrmod.utils.StagePack_NormalizeSpace(pack.ref_space)
	if pack.head_ok and tonumber(pack.head_y) then
		return string.format("Cube pack · %s · head Y %.2fm · height apply deferred",
			sp, tonumber(pack.head_y))
	end
	return string.format("Cube pack · %s · height apply deferred", sp)
end

--- G03 apply gate (pure) — decide if height/origin from pack could ever be applied.
--- Law: default allow_apply=false so product never auto-jumps; this only classifies.
---
--- pack: StagePack_Parse result
--- opts:
---   measured_head_y_m  number|nil  live HMD Y in tracking meters (OpenXR Y-up)
---   allow_apply        bool        master switch (default false)
---   close_m            number      already-close band (default 0.05)
---   max_delta_m        number      reject jumps larger than this (default 0.35)
---
--- Returns decision table:
---   action  "none" | "hint_only" | "apply_scale" | "apply_seated"
---   reason  stable code string
---   safe    bool — within band for a future careful apply
---   delta_y number|nil
function vrmod.utils.StagePack_ApplyDecision(pack, opts)
	opts = type(opts) == "table" and opts or {}
	local allow = opts.allow_apply and true or false
	local closeM = tonumber(opts.close_m) or 0.05
	local maxD = tonumber(opts.max_delta_m) or 0.35
	if closeM < 0.01 then closeM = 0.05 end
	if maxD < closeM then maxD = 0.35 end

	local dec = {
		action = "none",
		reason = "unusable",
		safe = false,
		delta_y = nil,
		allow_apply = allow,
	}

	if not vrmod.utils.StagePack_IsUsable(pack) then
		return dec
	end
	if not pack.head_ok then
		dec.reason = "no_head"
		return dec
	end

	local packY = tonumber(pack.head_y)
	if not packY then
		dec.reason = "no_head"
		return dec
	end

	local measured = tonumber(opts.measured_head_y_m)
	if not measured then
		-- Space pack known; height needs live HMD before any apply
		dec.action = "hint_only"
		dec.reason = "no_measured"
		dec.safe = false
		return dec
	end

	local delta = measured - packY
	dec.delta_y = delta
	local ad = math.abs(delta)
	if ad <= closeM then
		dec.action = "none"
		dec.reason = "already_close"
		dec.safe = true
		return dec
	end
	if ad > maxD then
		dec.action = "none"
		dec.reason = "too_far"
		dec.safe = false
		return dec
	end

	-- Eligible band: only apply when master switch on (product keeps it off)
	dec.safe = true
	if allow then
		-- Prefer scale path over seated origin rewrite (less dual-truth risk)
		dec.action = "apply_scale"
		dec.reason = "eligible"
	else
		dec.action = "hint_only"
		dec.reason = "eligible_deferred"
	end
	return dec
end

--- Toast line from ApplyDecision (pure). Nil if nothing useful to say.
function vrmod.utils.StagePack_ApplyToast(decision)
	if type(decision) ~= "table" then return nil end
	local r = tostring(decision.reason or "")
	if r == "already_close" then
		return "Cube pack · height already close · no apply"
	end
	if r == "too_far" then
		return "Cube pack · height delta too large · no auto-apply"
	end
	if r == "no_head" then
		return "Cube pack · space only · no head sample"
	end
	if r == "no_measured" then
		return "Cube pack · wait for HMD pose before height apply"
	end
	if r == "eligible_deferred" then
		local d = tonumber(decision.delta_y)
		if d then
			return string.format("Cube pack · ΔY %.2fm · apply deferred (safe band)", d)
		end
		return "Cube pack · apply deferred (safe band)"
	end
	if r == "eligible" and decision.action == "apply_scale" then
		return "Cube pack · scale apply allowed"
	end
	if r == "unusable" then
		return nil
	end
	return nil
end
