-- Eye gaze on the player net frame.
-- Same idea as FBT: the bytes exist only while the sample is on.
-- Off: the tick matches a build that has never heard of eye tracking.
-- On: 5 bytes after the waist block — magic 0xE1, then pitch and yaw as
-- uint16, both HMD-relative. They are not world poses, so a relative-frame
-- conversion must copy the integers and must not WorldToLocal them again.
--
-- Pitch is clamped to [-89, 89]. Yaw is wrapped to [-180, 180].
-- The uint16 span is 65536 steps across 360 degrees (~0.0055 deg).
-- 0 degrees lands on the exact center step. +180 and -180 alias.
--
-- A reader that stops after the waist bool never sees the tail.
-- A new reader treats fewer than 5 leftover bytes as "no eye".
-- A missing server allow-convar means allow. A present 0 means strip.
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

local PITCH_LIMIT = 89
local YAW_STEPS = 65536
local AXIS_MAX = 65535

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function flagOn(v)
	return v == true or v == 1 or v == "1"
end

local function asUint16(n)
	if not finite(n) then return nil end
	local u = math.floor(n + 0.5)
	if u < 0 or u > AXIS_MAX then return nil end
	return u
end

local function encodeAxis(degrees)
	local shifted = degrees + 180
	if shifted < 0 then shifted = 0 end
	if shifted > 360 then shifted = 360 end
	local u = math.floor(shifted / 360 * YAW_STEPS + 0.5)
	if u < 0 then u = 0 end
	if u > AXIS_MAX then u = AXIS_MAX end
	return u
end

local function decodeAxis(u)
	return (u / YAW_STEPS) * 360 - 180
end

function vrmod.utils.EyeFrame_Magic()
	return 225
end

function vrmod.utils.EyeFrame_TailBits()
	return 40
end

function vrmod.utils.EyeFrame_TailBytes()
	return 5
end

--- Previous vrutil_net_tick cap. Full-body plus this tail can pass it.
function vrmod.utils.EyeFrame_LegacyTickMaxBits()
	return 1200
end

--- New server cap. Covers muzzle + full body + the 40-bit eye tail.
function vrmod.utils.EyeFrame_NetTickMaxBits()
	return 2048
end

--- nil (convar not on this server) allows. false / 0 / "0" denies.
function vrmod.utils.EyeFrame_ServerAllowed(value)
	if value == nil then return true end
	if value == false or value == 0 or value == "0" then return false end
	return true
end

--- opts.server_allow nil means allow. Client must be on. Pose must exist.
--- Non-finite pitch/yaw, or opts.finite == false, refuses with "nan".
--- Returns ok, reason. reason is "server", "client", "no_pose", "nan", or "send".
function vrmod.utils.EyeFrame_ShouldSend(opts)
	opts = opts or {}
	if not vrmod.utils.EyeFrame_ServerAllowed(opts.server_allow) then
		return false, "server"
	end
	if not flagOn(opts.client_enabled) then
		return false, "client"
	end
	if not opts.has_pose then
		return false, "no_pose"
	end
	if opts.finite == false then
		return false, "nan"
	end
	local pitch = tonumber(opts.pitch)
	local yaw = tonumber(opts.yaw)
	if not finite(pitch) or not finite(yaw) then
		return false, "nan"
	end
	return true, "send"
end

--- HMD-relative degrees → uint16 pair. nil if either value is not finite.
function vrmod.utils.EyeFrame_PackLocal(pitch, yaw)
	pitch = tonumber(pitch)
	yaw = tonumber(yaw)
	if not finite(pitch) or not finite(yaw) then return nil, nil end
	if pitch > PITCH_LIMIT then pitch = PITCH_LIMIT end
	if pitch < -PITCH_LIMIT then pitch = -PITCH_LIMIT end
	yaw = math.NormalizeAngle(yaw)
	return encodeAxis(pitch), encodeAxis(yaw)
end

--- uint16 pair → degrees. nil if either word is not a uint16.
--- Pitch is clamped again so a hostile word cannot leave [-89, 89].
function vrmod.utils.EyeFrame_UnpackLocal(pitchU, yawU)
	pitchU = asUint16(pitchU)
	yawU = asUint16(yawU)
	if not pitchU or not yawU then return nil, nil end
	local pitch = decodeAxis(pitchU)
	local yaw = decodeAxis(yawU)
	if pitch > PITCH_LIMIT then pitch = PITCH_LIMIT end
	if pitch < -PITCH_LIMIT then pitch = -PITCH_LIMIT end
	return pitch, yaw
end

local function eyePair(frame)
	if type(frame) ~= "table" then return nil, nil end
	local p = asUint16(frame.eyePitchU)
	local y = asUint16(frame.eyeYawU)
	if not p or not y then return nil, nil end
	return p, y
end

--- Both directions. Eye off on only one side is not equal, so releasing
--- gaze still produces a tick. Both off is equal. Both on compares the uints.
function vrmod.utils.EyeFrame_FieldsEqual(a, b)
	local ap, ay = eyePair(a)
	local bp, by = eyePair(b)
	local aOn = ap ~= nil
	local bOn = bp ~= nil
	if aOn ~= bOn then return false end
	if not aOn then return true end
	return ap == bp and ay == by
end

function vrmod.utils.EyeFrame_CopyFields(dst, src)
	if type(dst) ~= "table" then return dst end
	local p, y = eyePair(src)
	if not p then
		dst.eyePitchU = nil
		dst.eyeYawU = nil
	else
		dst.eyePitchU = p
		dst.eyeYawU = y
	end
	return dst
end

function vrmod.utils.EyeFrame_Clear(frame)
	if type(frame) ~= "table" then return frame end
	frame.eyePitchU = nil
	frame.eyeYawU = nil
	return frame
end

--- Returns bits written (0 or 40). Does not write a partial tail.
function vrmod.utils.EyeFrame_WriteTail(writeUInt, frame)
	if type(writeUInt) ~= "function" then return 0 end
	local p, y = eyePair(frame)
	if not p then return 0 end
	writeUInt(vrmod.utils.EyeFrame_Magic(), 8)
	writeUInt(p, 16)
	writeUInt(y, 16)
	return vrmod.utils.EyeFrame_TailBits()
end

--- bytesLeft is net.BytesLeft() (whole leftover bytes).
--- Under 5 bytes: read nothing (old tick, or a short pad).
--- Magic mismatch: that one byte was consumed, nothing after it is.
--- Match: returns { eyePitchU, eyeYawU }.
function vrmod.utils.EyeFrame_ReadTail(bytesLeft, readUInt)
	if type(readUInt) ~= "function" then return nil end
	bytesLeft = tonumber(bytesLeft) or 0
	if bytesLeft < vrmod.utils.EyeFrame_TailBytes() then return nil end
	local magic = readUInt(8)
	if magic ~= vrmod.utils.EyeFrame_Magic() then return nil end
	local p = asUint16(readUInt(16))
	local y = asUint16(readUInt(16))
	if not p or not y then return nil end
	return { eyePitchU = p, eyeYawU = y }
end

-- Source AngleMatrix + ConcatTransforms(world, local) + MatrixAngles.
-- In the game, LocalToWorld is used when the engine provides it.
local DEG = math.pi / 180
local RAD2DEG = 180 / math.pi

local function sincos(deg)
	local r = deg * DEG
	return math.sin(r), math.cos(r)
end

local function angleMatrix(pitch, yaw, roll)
	local sy, cy = sincos(yaw)
	local sp, cp = sincos(pitch)
	local sr, cr = sincos(roll)
	local crcy, crsy = cr * cy, cr * sy
	local srcy, srsy = sr * cy, sr * sy
	return {
		{ cp * cy, sp * srcy - crsy, sp * crcy + srsy },
		{ cp * sy, sp * srsy + crcy, sp * crsy - srcy },
		{ -sp, sr * cp, cr * cp },
	}
end

local function mulMat(a, b)
	local o = { {}, {}, {} }
	for i = 1, 3 do
		for j = 1, 3 do
			o[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
		end
	end
	return o
end

local function matrixAngles(m)
	local fx, fy, fz = m[1][1], m[2][1], m[3][1]
	local lx, ly = m[1][2], m[2][2]
	local lz, uz = m[3][2], m[3][3]
	local xy = math.sqrt(fx * fx + fy * fy)
	if xy > 0.001 then
		return math.atan2(-fz, xy) * RAD2DEG, math.atan2(fy, fx) * RAD2DEG, math.atan2(lz, uz) * RAD2DEG
	end
	return math.atan2(-fz, xy) * RAD2DEG, math.atan2(-lx, ly) * RAD2DEG, 0
end

local function composePure(hmdP, hmdY, hmdR, pitch, yaw)
	local world = angleMatrix(hmdP, hmdY, hmdR)
	local localM = angleMatrix(pitch, yaw, 0)
	return matrixAngles(mulMat(world, localM))
end

--- HMD-relative pitch/yaw (roll 0) onto an HMD angle. Returns pitch, yaw, roll.
function vrmod.utils.EyeFrame_ComposeAng(hmdP, hmdY, hmdR, pitch, yaw)
	pitch = tonumber(pitch)
	yaw = tonumber(yaw)
	if not finite(pitch) or not finite(yaw) then return nil, nil, nil end
	if hmdP == nil then hmdP = 0 end
	if hmdY == nil then hmdY = 0 end
	if hmdR == nil then hmdR = 0 end
	hmdP, hmdY, hmdR = tonumber(hmdP), tonumber(hmdY), tonumber(hmdR)
	if not finite(hmdP) or not finite(hmdY) or not finite(hmdR) then return nil, nil, nil end
	if isfunction(LocalToWorld) and isfunction(Angle) and isfunction(Vector) then
		local ok, _, ang = pcall(LocalToWorld, Vector(0, 0, 0), Angle(pitch, yaw, 0), Vector(0, 0, 0), Angle(hmdP, hmdY, hmdR))
		if ok and ang and finite(tonumber(ang.p)) and finite(tonumber(ang.y)) and finite(tonumber(ang.r)) then
			return ang.p, ang.y, ang.r
		end
	end
	local p, y, r = composePure(hmdP, hmdY, hmdR, pitch, yaw)
	if not finite(p) or not finite(y) or not finite(r) then return nil, nil, nil end
	return p, y, r
end

local function clearWorldEye(dst)
	dst.eyeActive = false
	dst.eyePos = nil
	dst.eyeAng = nil
	dst.eyePitch = nil
	dst.eyeYaw = nil
end

--- Compose onto dst.hmdPos / dst.hmdAng, or clear.
--- allowed == false strips even when the uints are present.
--- allowed nil allows (server convar missing).
--- A reused dst is cleared when this frame has no eye, so a stale gaze
--- cannot survive the next tick that shares the world-pose table.
function vrmod.utils.EyeFrame_FillWorld(dst, src, allowed)
	if type(dst) ~= "table" then return nil end
	if not vrmod.utils.EyeFrame_ServerAllowed(allowed) or not dst.hmdPos or not dst.hmdAng then
		clearWorldEye(dst)
		return dst
	end
	local pitch, yaw = vrmod.utils.EyeFrame_UnpackLocal(src and src.eyePitchU, src and src.eyeYawU)
	if not pitch then
		clearWorldEye(dst)
		return dst
	end
	local hp = dst.hmdAng.p or dst.hmdAng.pitch or 0
	local hy = dst.hmdAng.y or dst.hmdAng.yaw or 0
	local hr = dst.hmdAng.r or dst.hmdAng.roll or 0
	local p, y, r = vrmod.utils.EyeFrame_ComposeAng(hp, hy, hr, pitch, yaw)
	if not p then
		clearWorldEye(dst)
		return dst
	end
	local pos = dst.hmdPos
	dst.eyeActive = true
	dst.eyePitch = pitch
	dst.eyeYaw = yaw
	dst.eyePos = Vector(pos.x, pos.y, pos.z)
	dst.eyeAng = Angle(p, y, r)
	return dst
end

local AIM_SOURCE = {
	[0] = "right",
	[1] = "left",
	[2] = "hmd",
	[3] = "eye",
}

local function clampAim(v)
	v = tonumber(v)
	if not finite(v) then return 0 end
	v = math.floor(v)
	if v < 0 or v > 3 then return 0 end
	return v
end

local function clampFallback(v)
	v = tonumber(v)
	if not finite(v) then return 0 end
	v = math.floor(v)
	if v == 1 then return 1 end
	return 0
end

--- Flashlight aim.
--- aim: 0 right, 1 left, 2 hmd, 3 eye. Anything else is right.
--- fallback: 0 right, 1 left. Anything else is right.
--- Eye is used only when aim is 3 and eye_enabled and eye_active are on.
--- Otherwise aim 3 uses the fallback hand (eye off, or enabled with no sample).
function vrmod.utils.FlashlightAim_Decide(opts)
	opts = opts or {}
	local aim = clampAim(opts.aim)
	local fallback = clampFallback(opts.fallback)
	if aim ~= 3 then
		return {
			source = AIM_SOURCE[aim],
			aim = aim,
			used_fallback = false,
			reason = "aim",
		}
	end
	if flagOn(opts.eye_enabled) and flagOn(opts.eye_active) then
		return {
			source = "eye",
			aim = 3,
			used_fallback = false,
			reason = "eye",
		}
	end
	local reason = "eye_off"
	if flagOn(opts.eye_enabled) then reason = "eye_inactive" end
	return {
		source = AIM_SOURCE[fallback],
		aim = fallback,
		used_fallback = true,
		reason = reason,
	}
end
