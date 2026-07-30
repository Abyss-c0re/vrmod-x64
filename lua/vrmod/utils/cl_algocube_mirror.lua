-- =============================================================================
-- vrmod.algocube.mirror — Avatar Mirror Algocube (manifested into VRMod)
--
-- Source of truth: KDE Quest MetaCam State Matrix (2026-07-30)
--   host=quest_metacam · N=8 · bits_set=256 · pick=6 · blueprint 7645758194
--   sha256_cells=393b33589db01595fe13ab8420f437a8bd3cfe9fd625f264c9ad2fb873a8e0ee
--
-- Prophecy path (NexusCore):
--   IO matrix{0,1} → raw (no prose) → algocube digit 0..9 matching blueprint
--   → neural payload → inject into avatar twin policy (mirror law)
--
-- Digit → twin policy (law-bound):
--   0 free          idle twin
--   1 open way      CLONE (same laterality)
--   2 cube SoT      MIRROR true (L↔R + MapMirror)  ← default Cube SoT
--   3 nanobot raw   WORLD (raw space)
--   4 HAIL NEXUS    MIRROR + hide head
--   5 one Commander MIRROR + hide hands
--   6 cmd override  MIRROR LAW (matrix pick) + head dampen (giraffe fix)
--   7 OS way        MIRROR + FBT prefer
--   8 nonverbal     MIRROR, no markers
--   9 hivemind      MIRROR + trackers + laser pick
-- =============================================================================
if SERVER then return end

vrmod = vrmod or {}
vrmod.algocube = vrmod.algocube or {}
local A = vrmod.algocube
local M = {}
vrmod.algocube.mirror = M

-- KDE MetaCam State Matrix SoT (cells.bin 512 bytes of 0/1)
local CELLS_B64 =
	"AQEBAQEBAQEBAQEBAQEBAQEAAQEBAQEBAQEAAAABAQEAAAAAAAAAAQAAAAAAAAAAAQAAAAAAAAABAAAAAAAAAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQAAAAEBAQEAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAQEBAQEBAQEAAQEBAQEBAQEBAAEBAQEAAQEAAAABAQEBAAAAAAEBAAAAAAAAAQEAAAAAAAAAAAAAAAAAAAAAAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAAAAAQEBAQAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAQEAAAAAAQEBAQEAAAEBAQEBAQEAAQEBAQEBAQEBAQEAAAEBAQAAAAAAAAEBAAAAAAAAAQAAAAAAAQAAAAABAQEBAAAAAQEBAQEAAAABAQEBAQEBAAEBAQEBAQEBAQEAAAAAAQEAAAAAAAABAAEAAAAAAAEAAAAAAAEAAAAAAQEBAAAAAAEAAQEBAQEBAQEBAQEBAQABAQEBAQEBAAAAAAAAAQABAAAAAAEBAQAAAAAAAAEAAQAAAQEBAQAAAQEBAQEBAQEBAQEAAQABAQEBAAAAAAEBAAAAAAABAAAAAAAAAAAAAAAAAQAAAAEAAQEBAAEBAQE="

-- Blueprint digits from matrix density (io_matrix_blueprint)
M.BLUEPRINT = { 7, 6, 4, 5, 7, 5, 8, 1, 9, 4 }
M.PICK = 6 -- matrix pick — Commander override / true mirror law
M.ENERGY = 256
M.HOST = "quest_metacam"
M.SHA256_CELLS = "393b33589db01595fe13ab8420f437a8bd3cfe9fd625f264c9ad2fb873a8e0ee"
M.SOURCE = "kde_metacam_20260730_234340"

local cv_digit = CreateClientConVar("vrmod_avatar_algo_digit", "-1", true, FCVAR_ARCHIVE,
	"Avatar algocube digit 0-9, or -1 = use matrix pick / last roll")
local cv_auto = CreateClientConVar("vrmod_avatar_algo_auto", "0", true, FCVAR_ARCHIVE,
	"If 1, re-roll algocube from live tracking IO each open")
-- OFF by default — backend math only; never part of Avatar UI / open path
local cv_enabled = CreateClientConVar("vrmod_avatar_algo", "0", true, FCVAR_ARCHIVE,
	"Optional backend algocube (0=off). Not used by Avatar menu.")

local cells = nil -- array 1..512 of 0/1
local algo = nil
local last = {
	digit = M.PICK,
	payload = nil,
	policy = nil,
	rolls = 0,
}

local function decodeCells()
	if cells then return cells end
	cells = {}
	local raw
	if util and util.Base64Decode then
		raw = util.Base64Decode(CELLS_B64)
	end
	if raw and #raw >= 512 then
		for i = 1, 512 do
			cells[i] = (string.byte(raw, i) or 0) ~= 0 and 1 or 0
		end
	else
		-- fallback: all-zero then stamp blueprint energy pattern
		for i = 1, 512 do cells[i] = 0 end
		for i = 1, M.ENERGY do cells[((i - 1) % 512) + 1] = 1 end
	end
	return cells
end

local function ensureAlgo()
	if algo then return algo end
	local c = decodeCells()
	local seed = A.SeedFromBytes and A.SeedFromBytes(c) or 0xA160
	-- mix pick into seed so SoT pick is structural
	seed = bit.bxor(seed, M.PICK * 0x10001)
	algo = A.New(seed)
	return algo
end

--- Policy table for a digit (pure data — applied by avatar session).
function M.PolicyFor(digit)
	digit = (tonumber(digit) or M.PICK) % 10
	if digit < 0 then digit = M.PICK end

	local p = {
		digit = digit,
		law = A.LawLabel and A.LawLabel(digit) or tostring(digit),
		mode = "facing", -- facing | clone | world
		idleOnly = false,
		mirrorLR = true,
		hideHead = false,
		hideHands = false,
		headDampen = false, -- giraffe fix
		preferFBT = false,
		showTrackers = false,
		showHandTrackers = false,
		laserPickBones = true,
		label = "MIRROR",
	}

	if digit == 0 then
		p.idleOnly = true
		p.mirrorLR = false
		p.label = "IDLE"
	elseif digit == 1 then
		p.mode = "clone"
		p.mirrorLR = false
		p.label = "CLONE"
	elseif digit == 2 then
		p.mode = "facing"
		p.mirrorLR = true
		p.label = "MIRROR SoT"
	elseif digit == 3 then
		p.mode = "world"
		p.mirrorLR = false
		p.label = "WORLD"
	elseif digit == 4 then
		p.mode = "facing"
		p.hideHead = true
		p.label = "MIRROR−HEAD"
	elseif digit == 5 then
		p.mode = "facing"
		p.hideHands = true
		p.label = "MIRROR−HANDS"
	elseif digit == 6 then
		-- Matrix pick / Commander override: true mirror + giraffe dampen
		p.mode = "facing"
		p.mirrorLR = true
		p.headDampen = true
		p.label = "MIRROR LAW"
	elseif digit == 7 then
		p.mode = "facing"
		p.preferFBT = true
		p.label = "MIRROR FBT"
	elseif digit == 8 then
		p.mode = "facing"
		p.laserPickBones = false
		p.showTrackers = false
		p.showHandTrackers = false
		p.label = "MIRROR ∅"
	elseif digit == 9 then
		p.mode = "facing"
		p.showTrackers = true
		p.showHandTrackers = true
		p.laserPickBones = true
		p.headDampen = true
		p.label = "MIRROR UNITY"
	end

	return p
end

--- Sample live VR tracking as IO bits (no prose) — prophecy hot path.
function M.SampleTrackingRaw()
	local bits = {}
	local tr = g_VR and g_VR.tracking
	if not tr then
		-- fall back to matrix cells
		local c = decodeCells()
		for i = 1, math.min(64, #c) do bits[i] = c[i] end
		return bits
	end

	local function pushPose(pose, n)
		if not pose or not pose.pos then
			for _ = 1, n do bits[#bits + 1] = 0 end
			return
		end
		local p, a = pose.pos, pose.ang or Angle()
		-- coarse quantized signs / thresholds (IO only)
		bits[#bits + 1] = p.x >= 0 and 1 or 0
		bits[#bits + 1] = p.y >= 0 and 1 or 0
		bits[#bits + 1] = p.z >= (g_VR.origin and g_VR.origin.z or 0) + 40 and 1 or 0
		bits[#bits + 1] = (a.p or 0) >= 0 and 1 or 0
		bits[#bits + 1] = (a.y or 0) >= 0 and 1 or 0
		bits[#bits + 1] = (a.r or 0) >= 0 and 1 or 0
		while n and #bits % n ~= 0 do bits[#bits + 1] = 0 end
	end

	pushPose(tr.hmd, 6)
	pushPose(tr.pose_lefthand, 6)
	pushPose(tr.pose_righthand, 6)
	pushPose(tr.pose_waist, 6)
	pushPose(tr.pose_leftfoot, 6)
	pushPose(tr.pose_rightfoot, 6)

	-- XOR-mix with matrix slice so SoT energy never leaves the roll
	local c = decodeCells()
	local out = {}
	for i = 1, 64 do
		local a = bits[i] or 0
		local b = c[i] or 0
		out[i] = bit.bxor(a, b) ~= 0 and 1 or 0
	end
	return out
end

--- Roll algocube: matrix blueprint + live IO → digit + payload + policy.
function M.Roll(opts)
	opts = opts or {}
	ensureAlgo()

	local forced = opts.digit
	if forced == nil then
		local cv = cv_digit:GetInt()
		if cv >= 0 and cv <= 9 then forced = cv end
	end

	local digit
	if forced ~= nil then
		digit = tonumber(forced) % 10
		algo.last_digit = digit
	else
		local raw = opts.raw or M.SampleTrackingRaw()
		-- prepend matrix energy bits so roll always tastes the KDE SoT
		local c = decodeCells()
		local mix = {}
		for i = 1, 32 do mix[i] = c[i] or 0 end
		for i = 1, #raw do mix[32 + i] = raw[i] end
		digit = A.Digit(algo, mix, M.BLUEPRINT)
	end

	local payload = A.NeuralPayload(digit, M.BLUEPRINT)
	local policy = M.PolicyFor(digit)
	last.digit = digit
	last.payload = payload
	last.policy = policy
	last.rolls = algo.rolls or (last.rolls + 1)

	if vrmod.logger then
		vrmod.logger.Info(
			"[AlgoCube/Mirror] digit=%d · %s · law=%s · rolls=%d",
			digit, policy.label, policy.law, last.rolls
		)
	end

	return digit, policy, payload
end

function M.GetLast()
	return last.digit, last.policy, last.payload, last.rolls
end

function M.GetCells()
	return decodeCells()
end

function M.Enabled()
	return cv_enabled:GetBool()
end

function M.Auto()
	return cv_auto:GetBool()
end

function M.ForcedDigit()
	local d = cv_digit:GetInt()
	if d >= 0 and d <= 9 then return d end
	return nil
end

function M.SetDigit(d)
	d = math.Clamp(math.floor(tonumber(d) or M.PICK), 0, 9)
	cv_digit:SetInt(d)
	return M.Roll({ digit = d })
end

function M.ClearForced()
	cv_digit:SetInt(-1)
end

--- Apply policy table onto an avatar Session (vrmod.avatar).
function M.ApplyToSession(session, policy)
	if not session or not policy then return false end
	policy = policy or last.policy or M.PolicyFor(last.digit or M.PICK)

	session.algoDigit = policy.digit
	session.algoPolicy = policy
	session.algoPayload = last.payload
	session.headDampen = policy.headDampen and true or false

	if session.SetMode then
		session:SetMode(policy.mode)
	else
		session.mode = policy.mode
	end

	if policy.idleOnly then
		session.idleOnly = true
	else
		session.idleOnly = false
	end

	if policy.hideHead ~= nil then session.hideHead = policy.hideHead end
	if policy.hideHands ~= nil then session.hideHands = policy.hideHands end
	if policy.laserPickBones ~= nil then session.laserPickBones = policy.laserPickBones end
	if policy.showHandTrackers ~= nil then session.showHandTrackers = policy.showHandTrackers end
	if policy.showTrackers then session.showTrackers = true end

	if policy.preferFBT then
		session.forceFBT = nil -- allow auto-detect
		if session.follow then
			session.follow.waist = true
			session.follow.feet = true
		end
	end

	-- L↔R always implied by mode facing via _isMirrorMode; store flag for diagnostics
	session.mirrorLR = policy.mirrorLR

	if session._applyHideBones then
		pcall(function() session:_applyHideBones() end)
	end

	return true
end

--- Open twin under algocube law (roll + OpenHeightCal + apply).
function M.Manifest(menuUid)
	if not vrmod.avatar or not vrmod.avatar.OpenHeightCal then return nil end

	local digit, policy = M.Roll()
	-- Prefer matrix pick when first manifest and no forced digit / auto off
	if not M.ForcedDigit() and not M.Auto() then
		digit, policy = M.Roll({ digit = M.PICK })
	elseif M.Auto() then
		digit, policy = M.Roll() -- live IO
	end

	local s = vrmod.avatar.OpenHeightCal(menuUid)
	if s then
		M.ApplyToSession(s, policy)
	end
	return s, digit, policy
end

-- Concommands for Commander / debug
concommand.Add("vrmod_avatar_algo_roll", function()
	local d, p = M.Roll()
	local s = vrmod.avatar and vrmod.avatar.Get and vrmod.avatar.Get("avatar")
	if s then M.ApplyToSession(s, p) end
	print(string.format("[AlgoCube/Mirror] roll digit=%d %s (%s)", d, p.label, p.law))
end)

concommand.Add("vrmod_avatar_algo_status", function()
	local d, p, payload, rolls = M.GetLast()
	p = p or M.PolicyFor(d or M.PICK)
	print(string.format(
		"[AlgoCube/Mirror] host=%s pick=%d energy=%d digit=%d rolls=%d label=%s law=%s mode=%s dampen=%s",
		M.HOST, M.PICK, M.ENERGY, d or -1, rolls or 0, p.label, p.law, p.mode, tostring(p.headDampen)
	))
	if payload then
		print("[AlgoCube/Mirror] payload=" .. table.concat(payload, ""))
	end
	print("[AlgoCube/Mirror] blueprint=" .. table.concat(M.BLUEPRINT, ""))
	print("[AlgoCube/Mirror] sha256_cells=" .. M.SHA256_CELLS)
end)

concommand.Add("vrmod_avatar_algo_pick", function(_, _, args)
	local d = tonumber(args[1] or M.PICK) or M.PICK
	local dig, p = M.SetDigit(d)
	local s = vrmod.avatar and vrmod.avatar.Get and vrmod.avatar.Get("avatar")
	if s then M.ApplyToSession(s, p) end
	print(string.format("[AlgoCube/Mirror] forced digit=%d %s", dig, p.label))
end)

return M
