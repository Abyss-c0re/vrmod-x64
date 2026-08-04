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
