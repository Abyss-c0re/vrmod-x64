-- VRMod-scope Glide *audio* overrides (do not edit Glide addon files).
-- Cube: one quiet path — no per-frame thrash, no HasFocus hijack, no FP camera fight.

if SERVER then return end

g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

local viewWrapped = false
local muteSaved = nil
local rebindDone = false
local nextStreamNudge = 0

local function HmdLocation()
	if not (g_VR and g_VR.active) then return nil end
	local hmd = g_VR.tracking and g_VR.tracking.hmd
	if hmd and hmd.pos and hmd.ang then
		return hmd.pos, hmd.ang
	end
	if g_VR.view and g_VR.view.origin and g_VR.view.angles then
		return g_VR.view.origin, g_VR.view.angles
	end
	return nil
end

local function WrapGetLocalViewLocation()
	if viewWrapped or not Glide or not isfunction(Glide.GetLocalViewLocation) then return end
	local orig = Glide.GetLocalViewLocation
	function Glide.GetLocalViewLocation()
		local pos, ang = HmdLocation()
		if pos then return pos, ang end
		return orig()
	end
	viewWrapped = true
end

local function RebindAudioUpvalue(fn)
	if not isfunction(fn) or not debug or not debug.getupvalue or not debug.setupvalue then
		return false
	end
	local i = 1
	while true do
		local name = debug.getupvalue(fn, i)
		if not name then break end
		if name == "GetLocalViewLocation" then
			debug.setupvalue(fn, i, function()
				return Glide.GetLocalViewLocation()
			end)
			return true
		end
		i = i + 1
	end
	return false
end

--- Once per session (not every VR start loop) — rebinding is not free.
local function RebindStreamThinkUpvaluesOnce()
	if rebindDone or not Glide then return end
	local thinks = hook.GetTable()["Think"] or {}
	for _, name in ipairs({ "Glide.ProcessEngineStreams", "Glide.WebAudio.Think" }) do
		if isfunction(thinks[name]) then
			RebindAudioUpvalue(thinks[name])
		end
	end
	if Glide.WebAudio and isfunction(Glide.WebAudio.Think) then
		RebindAudioUpvalue(Glide.WebAudio.Think)
	end
	rebindDone = true
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

--- ~20 Hz stream ear-nudge when driving — not every frame.
local function StreamNearEarsThink()
	if not g_VR.active then return end
	local now = CurTime()
	if now < nextStreamNudge then return end
	nextStreamNudge = now + 0.05

	local ply = LocalPlayer()
	if not IsValid(ply) or not ply.GlideGetVehicle then return end
	local veh = ply:GlideGetVehicle()
	if not IsValid(veh) or not veh.IsGlideVehicle then return end
	local stream = veh.stream
	if not stream then return end
	stream.firstPerson = true
	if stream.isWebAudio then
		local pos, ang = HmdLocation()
		if pos and ang then
			stream.position = pos + ang:Forward() * 10
		end
	end
end

function vrmod.utils.PatchGlideAudio()
	if not Glide then return false end
	WrapGetLocalViewLocation()
	RebindStreamThinkUpvaluesOnce()
	if g_VR and g_VR.active then
		SetMuteLoseFocus(true)
	end
	return true
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
		RebindStreamThinkUpvaluesOnce()
	end
end)

timer.Create("vrmod_glide_audio_late", 2, 4, function()
	if not Glide then return end
	WrapGetLocalViewLocation()
	RebindStreamThinkUpvaluesOnce()
	if viewWrapped then
		timer.Remove("vrmod_glide_audio_late")
	end
end)
