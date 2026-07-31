-- =============================================================================
-- vrmod.iknet — Reusable IK network (Cube single frame schema)
--
-- One energy path for:
--   VR player net (sh_network) · avatar twin · NPC mimic · braincube training
--
-- Schema matches buildClientFrame / lerpedFrame:
--   characterYaw, hmd/hands (+ optional waist/feet), finger1..10
--
-- Relative frames (FrameToRelative on feet+yaw) retarget to any NPC stand.
-- Braincube: FrameToBits / FrameToFeatures → algocube Digit + NeuralPayload.
-- =============================================================================

vrmod = vrmod or {}
vrmod.iknet = vrmod.iknet or {}
local N = vrmod.iknet

N.SCHEMA = 1
N.PARTS = { "hmd", "lefthand", "righthand", "waist", "leftfoot", "rightfoot" }

--- Pack frame to plain tables (JSON-safe numbers only).
function N.Pack(frame)
	if not frame then return nil end
	local t = {
		schema = N.SCHEMA,
		ts = frame.ts or 0,
		characterYaw = frame.characterYaw or 0,
	}
	for i = 1, 10 do
		t["finger" .. i] = tonumber(frame["finger" .. i]) or 0
	end
	local function packPose(prefix)
		local p, a = frame[prefix .. "Pos"], frame[prefix .. "Ang"]
		if not p or not a then return end
		t[prefix .. "Pos"] = { p.x, p.y, p.z }
		t[prefix .. "Ang"] = { a.p, a.y, a.r }
	end
	for _, part in ipairs(N.PARTS) do
		packPose(part)
	end
	return t
end

--- Unpack packed table → Vector/Angle frame.
function N.Unpack(t)
	if not t then return nil end
	local frame = {
		ts = t.ts or 0,
		characterYaw = t.characterYaw or 0,
	}
	for i = 1, 10 do
		frame["finger" .. i] = tonumber(t["finger" .. i]) or 0
	end
	local function unpackPose(prefix)
		local pv, av = t[prefix .. "Pos"], t[prefix .. "Ang"]
		if not pv or not av then return end
		frame[prefix .. "Pos"] = Vector(pv[1] or pv.x or 0, pv[2] or pv.y or 0, pv[3] or pv.z or 0)
		frame[prefix .. "Ang"] = Angle(av[1] or av.p or 0, av[2] or av.y or 0, av[3] or av.r or 0)
	end
	for _, part in ipairs(N.PARTS) do
		unpackPose(part)
	end
	return frame
end

--- Ring buffer of packed relative frames (training / playback).
function N.NewBuffer(capacity)
	return {
		cap = math.max(8, tonumber(capacity) or 600), -- ~10s @ 60Hz
		frames = {},
		n = 0,
		i = 0, -- write cursor
	}
end

function N.BufferPush(buf, frame, relative)
	if not buf or not frame then return end
	local packed = N.Pack(frame)
	if not packed then return end
	packed.rel = relative and true or false
	buf.i = (buf.i % buf.cap) + 1
	buf.frames[buf.i] = packed
	if buf.n < buf.cap then buf.n = buf.n + 1 end
end

--- Ordered list oldest→newest (packed).
function N.BufferList(buf)
	if not buf or buf.n < 1 then return {} end
	local out = {}
	local start = buf.i - buf.n + 1
	for k = 0, buf.n - 1 do
		local idx = ((start + k - 1) % buf.cap) + 1
		out[#out + 1] = buf.frames[idx]
	end
	return out
end

function N.BufferClear(buf)
	if not buf then return end
	buf.frames = {}
	buf.n = 0
	buf.i = 0
end

------------------------------------------------------------------------
-- Braincube feature path (nonverbal)
------------------------------------------------------------------------

--- Flatten relative frame → feature vector (numbers for training / inject).
-- Layout: yaw, 10 fingers, then each present part pos(3)+ang(3) in PARTS order.
function N.FrameToFeatures(frame)
	if not frame then return {} end
	local f = {}
	f[#f + 1] = (frame.characterYaw or 0) / 180 -- ~[-1,1]
	for i = 1, 10 do
		f[#f + 1] = tonumber(frame["finger" .. i]) or 0
	end
	for _, part in ipairs(N.PARTS) do
		local p, a = frame[part .. "Pos"], frame[part .. "Ang"]
		if p and a then
			-- positions in units / 100 (local body scale)
			f[#f + 1] = p.x / 100
			f[#f + 1] = p.y / 100
			f[#f + 1] = p.z / 100
			f[#f + 1] = a.p / 180
			f[#f + 1] = a.y / 180
			f[#f + 1] = a.r / 180
		else
			for _ = 1, 6 do f[#f + 1] = 0 end
		end
	end
	return f
end

--- Quantize features → 0/1 bits (length power-of-2 friendly for SMX cells).
function N.FeaturesToBits(features, bitCount)
	bitCount = tonumber(bitCount) or 256
	local bits = {}
	local n = #features
	if n < 1 then
		for i = 1, bitCount do bits[i] = 0 end
		return bits
	end
	for i = 1, bitCount do
		local src = features[((i - 1) % n) + 1] or 0
		-- map signed-ish float → bit
		local v = src
		if v < 0 then v = -v end
		bits[i] = (v > 0.08) and 1 or 0
		-- mix sign energy
		if src < -0.08 then bits[i] = 1 - bits[i] end
	end
	return bits
end

function N.FrameToBits(frame, bitCount)
	return N.FeaturesToBits(N.FrameToFeatures(frame), bitCount)
end

--- Algocube decide from a relative pose frame (braincube training step).
-- returns digit, payload, seed, bits
function N.BrainDecide(frame, algo, blueprint)
	local bits = N.FrameToBits(frame, 256)
	local raw = bits -- table of 0/1
	local A = vrmod.algocube
	if not A then
		return 0, {}, 0, bits
	end
	algo = algo or A.New(A.SeedFromBytes(raw))
	local digit = A.Digit(algo, raw, blueprint)
	local payload = A.NeuralPayload(digit, blueprint)
	return digit, payload, algo.rng, bits
end

--- Export buffer as training plate (JSON-serializable).
function N.ExportPlate(buf, meta)
	meta = meta or {}
	local list = N.BufferList(buf)
	local samples = {}
	local algo = vrmod.algocube and vrmod.algocube.New(0x1C0DE) or nil
	for i, packed in ipairs(list) do
		local fr = N.Unpack(packed)
		local digit, payload, seed, bits = N.BrainDecide(fr, algo)
		samples[#samples + 1] = {
			i = i,
			ts = packed.ts,
			digit = digit,
			payload = payload,
			seed = seed,
			feat = N.FrameToFeatures(fr),
			-- compact bits as string of 0/1 for external braincube
			bits = table.concat(bits),
			frame = packed,
		}
	end
	return {
		schema = N.SCHEMA,
		kind = "vrmod.iknet.plate",
		ts = os.time and os.time() or 0,
		meta = meta,
		n = #samples,
		samples = samples,
	}
end

--- Lerp two frames (for playback smooth / net delay).
function N.LerpFrame(a, b, t)
	if not a then return b end
	if not b then return a end
	t = math.Clamp(tonumber(t) or 0, 0, 1)
	local out = { characterYaw = LerpAngle(t, Angle(0, a.characterYaw or 0, 0), Angle(0, b.characterYaw or 0, 0)).yaw }
	for i = 1, 10 do
		out["finger" .. i] = Lerp(t, tonumber(a["finger" .. i]) or 0, tonumber(b["finger" .. i]) or 0)
	end
	local function lerpPose(prefix)
		local ap, aa = a[prefix .. "Pos"], a[prefix .. "Ang"]
		local bp, ba = b[prefix .. "Pos"], b[prefix .. "Ang"]
		if ap and bp and aa and ba then
			out[prefix .. "Pos"] = LerpVector(t, ap, bp)
			out[prefix .. "Ang"] = LerpAngle(t, aa, ba)
		elseif bp then
			out[prefix .. "Pos"], out[prefix .. "Ang"] = bp, ba
		elseif ap then
			out[prefix .. "Pos"], out[prefix .. "Ang"] = ap, aa
		end
	end
	for _, part in ipairs(N.PARTS) do
		lerpPose(part)
	end
	return out
end

return N
