-- Per-frame budget for Source engine traces (util.TraceLine / TraceHull / enginetrace).
-- The BSP walk stays on the main thread. A worker may only score, hash, and cache.
-- TraceBudget_Admit says how many queued traces may run this frame; the rest wait.
-- This file does not call the engine and is not wired into wall collision.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

-- Whole non-negative count, or nil when the input must not schedule a trace.
local function whole_count(v)
	if type(v) ~= "number" then return nil end
	if v ~= v then return nil end
	if v < 0 or v == math.huge then return nil end
	if math.floor(v) ~= v then return nil end
	return v
end

function vrmod.utils.TraceBudget_MaxPerFrame()
	return 8
end

--- How many engine traces to run now, and how many to leave queued.
--- Returns run, defer. run is 0 when any input is negative or not a whole number.
--- A bad requested count defers nothing. A bad used or max defers the whole request.
--- When used and max are valid, used+run <= max (run is 0 if used is already over max).
function vrmod.utils.TraceBudget_Admit(used, requested, max)
	local req = whole_count(requested)
	if req == nil then
		return 0, 0
	end
	local u = whole_count(used)
	local m = whole_count(max)
	if u == nil or m == nil then
		return 0, req
	end
	local remain = m - u
	if remain < 0 then remain = 0 end
	local run = req
	if run > remain then run = remain end
	return run, req - run
end
