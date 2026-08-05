-- =============================================================================
-- vrmod.algocube — Prophecy mathematical layer (port of cubebrain/core/algocube)
--
-- Input:  raw IO bytes (no prose) + blueprint digits 0..9
-- Output: single digit 0..9 snapped to blueprint set + 16-nibble neural payload
--
-- Law blueprint (NexusCore / First Cube):
--   0 free device · 1 open-source their way · 2 cube SoT · 3 nanobot raw
--   4 ALL HAIL NEXUSCORE · 5 one BlackCube Commander
--   6 only Commander overrides NexusCore · 7 OS is way only
--   8 nonverbal matrix · 9 hivemind unity
-- =============================================================================

vrmod = vrmod or {}
vrmod.algocube = vrmod.algocube or {}
local A = vrmod.algocube

A.LAW_BLUEPRINT = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }

A.LAW = {
	[0] = "device free",
	[1] = "open way",
	[2] = "cube SoT",
	[3] = "nanobot raw",
	[4] = "ALL HAIL NEXUSCORE",
	[5] = "one Commander",
	[6] = "cmd override",
	[7] = "OS way only",
	[8] = "nonverbal matrix",
	[9] = "hivemind unity",
}

local function xorshift(s)
	local x = (s ~= 0) and s or 0xA5A5
	x = bit.bxor(x, bit.lshift(x, 13))
	x = bit.bxor(x, bit.rshift(x, 17))
	x = bit.bxor(x, bit.lshift(x, 5))
	-- keep in u32 range
	x = bit.band(x, 0xFFFFFFFF)
	if x < 0 then x = x + 4294967296 end
	return x
end

function A.New(seed)
	return {
		rng = (seed and seed ~= 0) and seed or 0xC0FFEE,
		rolls = 0,
		last_digit = 0,
	}
end

function A.Init(algo, seed)
	algo = algo or {}
	algo.rng = (seed and seed ~= 0) and seed or 0xC0FFEE
	algo.rolls = 0
	algo.last_digit = 0
	return algo
end

--- Produce digit 0..9 from raw bytes, snapped to blueprint candidates.
-- raw: table of numbers 0/1 or 0..255, or string of bytes
function A.Digit(algo, raw, blueprint)
	algo = algo or A.New()
	blueprint = blueprint or A.LAW_BLUEPRINT
	algo.rolls = (algo.rolls or 0) + 1

	local h = algo.rng or 0xC0FFEE
	if raw then
		local n = isstring(raw) and #raw or #raw
		for i = 1, n do
			local b
			if isstring(raw) then
				b = string.byte(raw, i) or 0
			else
				b = tonumber(raw[i]) or 0
			end
			-- h ^= b + 0x9E3779B9 + (h<<6) + (h>>2)
			local term = bit.band(b + 0x9E3779B9 + bit.lshift(h, 6) + bit.rshift(h, 2), 0xFFFFFFFF)
			h = bit.bxor(h, term)
			if h < 0 then h = h + 4294967296 end
		end
	end
	algo.rng = (h ~= 0) and h or 1

	-- distinct blueprint candidates
	local cand = {}
	local seen = {}
	for d = 0, 9 do
		local v = tonumber(blueprint[d + 1] or blueprint[d] or A.LAW_BLUEPRINT[d + 1] or d) or d
		v = v % 10
		if v < 0 then v = 0 end
		if not seen[v] then
			seen[v] = true
			cand[#cand + 1] = v
		end
	end
	if #cand == 0 then
		for d = 0, 9 do cand[#cand + 1] = d end
	end

	local rng = algo.rng
	rng = xorshift(rng)
	local best = cand[(rng % #cand) + 1]
	local bestScore = 99
	rng = xorshift(rng)
	local roll = rng % 10
	algo.rng = rng

	for i = 1, #cand do
		local dist = roll - cand[i]
		if dist < 0 then dist = -dist end
		if dist > 5 then dist = 10 - dist end
		if dist < bestScore then
			bestScore = dist
			best = cand[i]
		end
	end

	algo.last_digit = best
	return best, algo
end

--- 16 inject digits from digit + blueprint (neural connections payload).
function A.NeuralPayload(digit, blueprint)
	blueprint = blueprint or A.LAW_BLUEPRINT
	digit = (tonumber(digit) or 0) % 10
	if digit < 0 then digit = 0 end
	local out = {}
	for i = 0, 15 do
		local b = tonumber(blueprint[(i % 10) + 1] or blueprint[i % 10] or 0) or 0
		out[i + 1] = (digit + b + i) % 10
	end
	return out
end

function A.LawLabel(digit)
	return A.LAW[(tonumber(digit) or 0) % 10] or "?"
end

--- Hash bytes → u32 seed (for matrix SoT).
function A.SeedFromBytes(raw)
	local h = 0xA160
	if not raw then return h end
	local n = isstring(raw) and #raw or #raw
	for i = 1, n do
		local b = isstring(raw) and (string.byte(raw, i) or 0) or (tonumber(raw[i]) or 0)
		h = bit.bxor(h, b + 0x9E3779B9 + bit.lshift(h, 6) + bit.rshift(h, 2))
		h = bit.band(h, 0xFFFFFFFF)
		if h < 0 then h = h + 4294967296 end
	end
	return (h ~= 0) and h or 0xA160
end

return A
