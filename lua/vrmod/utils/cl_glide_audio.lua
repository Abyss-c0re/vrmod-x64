-- VRMod-scope Glide *audio* overrides (do not edit Glide addon files).
--
-- Why engines go silent in VR ("all electric"):
--   Glide ProcessEngineStreams uses GetLocalViewLocation() for distance fade.
--   That is cached from EyePos via PreDrawEffects — often wrong/stale under VR
--   RenderScene. Volume = 1 - dist/fadeDist → 0 when "camera" is far from car.
--   Also base_glide_car resets stream.firstPerson from desktop FP flag every tick.
--
-- Cube: one quiet path — wrap view location to HMD, force FP stream, retry rebind.

if SERVER then return end

g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

local viewWrapped = false
local muteSaved = nil
local rebindOk = false
local nextStreamNudge = 0
local nextRebindTry = 0
local origGetLocalViewLocation = nil

local function HmdLocation()
	if not (g_VR and g_VR.active) then return nil end
	local hmd = g_VR.tracking and g_VR.tracking.hmd
	if hmd and hmd.pos and hmd.ang then
		return hmd.pos, hmd.ang
	end
	if g_VR.view and g_VR.view.origin and g_VR.view.angles then
		return g_VR.view.origin, g_VR.view.angles
	end
	local ply = LocalPlayer()
	if IsValid(ply) then
		return ply:EyePos(), ply:EyeAngles()
	end
	return nil
end

local function WrapGetLocalViewLocation()
	if not Glide or not isfunction(Glide.GetLocalViewLocation) then return false end
	if viewWrapped then return true end
	origGetLocalViewLocation = Glide.GetLocalViewLocation
	function Glide.GetLocalViewLocation()
		if g_VR and g_VR.active then
			local pos, ang = HmdLocation()
			if pos and ang then return pos, ang end
		end
		if origGetLocalViewLocation then
			return origGetLocalViewLocation()
		end
		return Vector(), Angle()
	end
	viewWrapped = true
	return true
end

local function RebindAudioUpvalue(fn)
	if not isfunction(fn) or not debug or not debug.getupvalue or not debug.setupvalue then
		return false
	end
	local i = 1
	while true do
		local name, val = debug.getupvalue(fn, i)
		if not name then break end
		if name == "GetLocalViewLocation" then
			-- Point stream Think at the live Glide.GetLocalViewLocation (our wrap)
			debug.setupvalue(fn, i, function()
				return Glide.GetLocalViewLocation()
			end)
			return true
		end
		i = i + 1
	end
	return false
end

--- Retry until Glide stream Think is rebound (addon may load after VRMod).
local function TryRebindStreamThink()
	if rebindOk or not Glide then return rebindOk end
	local now = CurTime()
	if now < nextRebindTry then return rebindOk end
	nextRebindTry = now + 1

	WrapGetLocalViewLocation()
	local thinks = hook.GetTable()["Think"] or {}
	local okAny = false
	for _, name in ipairs({ "Glide.ProcessEngineStreams", "Glide.WebAudio.Think" }) do
		if isfunction(thinks[name]) and RebindAudioUpvalue(thinks[name]) then
			okAny = true
		end
	end
	if Glide.WebAudio and isfunction(Glide.WebAudio.Think) then
		if RebindAudioUpvalue(Glide.WebAudio.Think) then okAny = true end
	end
	-- If hooks not present yet, keep retrying; if present and rebound, done
	if okAny or (thinks["Glide.ProcessEngineStreams"] == nil and thinks["Glide.WebAudio.Think"] == nil and Glide.GetLocalViewLocation) then
		-- Table wrap alone often enough if Think uses global; prefer okAny
		if okAny or viewWrapped then
			rebindOk = okAny or viewWrapped
		end
	end
	return rebindOk
end

local function SetMuteLoseFocus(vrOn)
	local cv = GetConVar("snd_mute_losefocus")
	if not cv then return end
	if vrOn then
		if muteSaved == nil then muteSaved = cv:GetString() end
		pcall(function()
			cv:SetString("0")
		end)
	elseif muteSaved ~= nil then
		local v = muteSaved
		muteSaved = nil
		pcall(function()
			cv:SetString(v)
		end)
	end
end

--- Keep engine stream audible: FP mode + listener at HMD (Glide car resets firstPerson each tick).
local function StreamNearEarsThink()
	if not g_VR or not g_VR.active then return end
	TryRebindStreamThink()

	local now = CurTime()
	if now < nextStreamNudge then return end
	nextStreamNudge = now + 0.03 -- ~33 Hz — after vehicle cl_init resets firstPerson

	local ply = LocalPlayer()
	if not IsValid(ply) or not ply.GlideGetVehicle then return end
	local veh = ply:GlideGetVehicle()
	if not IsValid(veh) or not veh.IsGlideVehicle then return end

	local stream = veh.stream
	if not stream then return end

	-- Glide base_glide_car sets this from desktop FP camera every tick → force VR
	stream.firstPerson = true

	local pos, ang = HmdLocation()
	if not pos then return end

	if stream.isWebAudio then
		stream.position = pos + ang:Forward() * 8
	else
		-- Classic IGModAudioChannel path still distance-fades even in FP.
		-- Keep fadeDist generous so HMD micro-offset never zeros volume.
		if not stream._vrmodFadeSaved then
			stream._vrmodFadeSaved = stream.fadeDist or 3500
		end
		stream.fadeDist = math.max(stream._vrmodFadeSaved or 3500, 8000)
	end

	-- Nudge volume multiplier out of silent ramp if stuck
	if isnumber(stream.volumeMultiplier) and stream.volumeMultiplier < 0.15 then
		stream.volumeMultiplier = 0.5
	end
end

function vrmod.utils.PatchGlideAudio()
	if not Glide then return false end
	rebindOk = false -- allow rebind after Glide hot-reload
	nextRebindTry = 0
	WrapGetLocalViewLocation()
	TryRebindStreamThink()
	if g_VR and g_VR.active then
		SetMuteLoseFocus(true)
	end
	return viewWrapped
end

hook.Add("VRMod_Start", "vrmod_glide_audio", function()
	vrmod.utils.PatchGlideAudio()
	hook.Add("Think", "vrmod_glide_stream_near_ears", StreamNearEarsThink)
end)

hook.Add("VRMod_Exit", "vrmod_glide_audio", function(ply)
	if ply and ply ~= LocalPlayer() then return end
	hook.Remove("Think", "vrmod_glide_stream_near_ears")
	SetMuteLoseFocus(false)
end)

hook.Add("InitPostEntity", "vrmod_glide_audio", function()
	if Glide then
		WrapGetLocalViewLocation()
		TryRebindStreamThink()
	end
end)

-- Late bind: Glide may register ProcessEngineStreams after our first pass
timer.Create("vrmod_glide_audio_late", 1.5, 8, function()
	if not Glide then return end
	WrapGetLocalViewLocation()
	TryRebindStreamThink()
end)

-- Also re-patch when entering a Glide seat (stream may be created later)
hook.Add("VRMod_EnterVehicle", "vrmod_glide_audio_enter", function()
	if not Glide then return end
	vrmod.utils.PatchGlideAudio()
	timer.Simple(0.2, function()
		if g_VR and g_VR.active then
			StreamNearEarsThink()
		end
	end)
end)
