-- Eye gaze for character eyes, and the optional tail on the player frame.
-- Any backend that fills g_VR.tracking.pose_gaze can drive this. The OpenXR
-- module does that via XR_EXT_eye_gaze_interaction (Pico, Quest Pro, Index,
-- Varjo, and other runtimes that expose the extension). Client default off.
-- Server default allows it. A server that has no vrmod_sv_eyetracking convar
-- is treated as allow (see EyeFrame_ServerAllowed).
--
-- Globals:
--   g_VR.tracking.pose_gaze  world pose of the gaze ray (pos + ang)
--   g_VR.eyeTracking         local sample: enabled, supported, active,
--                            pos, ang, localAng (relative to the HMD), lookAt
--   g_VR.net[steamid].eyeGaze  replicated look target for that player
-- The frame tail is the API sample. vrmod_eye_gaze remains so an older
-- sender (no tail) can still move character eyes.
-- Openness is left nil. This extension does not provide it.

local LOOK_DIST = 400
local SEND_DT = 0.066
local STALE_SEC = 0.5

g_VR = g_VR or {}
vrmod = vrmod or {}

local svFlags = bit.bor(FCVAR_ARCHIVE or 128, FCVAR_REPLICATED or 8192)
vrmod.AddCallbackedConvar(
	"vrmod_sv_eyetracking",
	"vrmod_sv_eyetracking",
	"1",
	svFlags,
	"Allow VR eye gaze on the player frame and the legacy eye message",
	0,
	1,
	function(val)
		if vrmod.utils and vrmod.utils.EyeFrame_ServerAllowed then
			return vrmod.utils.EyeFrame_ServerAllowed(val)
		end
		return val ~= "0" and val ~= 0 and val ~= false
	end
)

function vrmod.EyeTrackingAllowed()
	local cv = GetConVar("vrmod_sv_eyetracking")
	local raw = nil
	if cv then
		if cv.GetString then
			raw = cv:GetString()
		elseif cv.GetBool then
			raw = cv:GetBool()
		end
	end
	if vrmod.utils and vrmod.utils.EyeFrame_ServerAllowed then
		return vrmod.utils.EyeFrame_ServerAllowed(raw)
	end
	return raw ~= "0" and raw ~= false and raw ~= 0
end

function vrmod.EyeTrackingEnabled()
	local cv = GetConVar("vrmod_eyetracking")
	if cv then return cv:GetBool() end
	return g_VR.eyeTracking and g_VR.eyeTracking.enabled and true or false
end

if SERVER then
	util.AddNetworkString("vrmod_eye_gaze")
	cvars.AddChangeCallback("vrmod_sv_eyetracking", function()
		if vrmod.EyeTrackingAllowed() then return end
		if vrmod.EyeFrame_RelayStrip then vrmod.EyeFrame_RelayStrip() end
	end, "vrmod_sv_eyetracking_strip")
	-- len is bits. Bool + vector + two angles stays far under this.
	vrmod.NetReceiveLimited("vrmod_eye_gaze", 20, 2048, function(_, ply)
		if not IsValid(ply) then return end
		if not vrmod.EyeTrackingAllowed() then
			-- Drop the sample and tell everyone else the look is off.
			net.Start("vrmod_eye_gaze", true)
			net.WriteEntity(ply)
			net.WriteBool(false)
			net.SendOmit(ply)
			return
		end
		local active = net.ReadBool()
		local lookAt, ang, localAng
		if active then
			lookAt = net.ReadVector()
			ang = net.ReadAngle()
			localAng = net.ReadAngle()
		end
		net.Start("vrmod_eye_gaze", true)
		net.WriteEntity(ply)
		net.WriteBool(active)
		if active then
			net.WriteVector(lookAt)
			net.WriteAngle(ang)
			net.WriteAngle(localAng)
		end
		net.SendOmit(ply)
	end)
	return
end

g_VR = g_VR or {}
g_VR.eyeTracking = g_VR.eyeTracking or {
	enabled = false,
	supported = false,
	active = false,
	pos = Vector(),
	ang = Angle(),
	localAng = Angle(),
	lookAt = Vector(),
	openness = nil,
}

vrmod.AddCallbackedConvar(
	"vrmod_eyetracking",
	"vrmod_eyetracking",
	"0",
	FCVAR_ARCHIVE,
	"Drive character eyes from OpenXR eye gaze",
	nil,
	nil,
	tobool
)

local function EyeConvarOn()
	local cv = GetConVar("vrmod_eyetracking")
	return cv and cv:GetBool() or false
end

local function WriteVec(dst, src)
	dst.x, dst.y, dst.z = src.x, src.y, src.z
end

local function WriteAng(dst, src)
	dst.p, dst.y, dst.r = src.p, src.y, src.r
end

local function RestoreEyes(ply)
	if not IsValid(ply) then return end
	local aim = ply:GetAimVector()
	ply:SetEyeTarget(ply:EyePos() + aim * LOOK_DIST)
end

-- One look point for both eyes. A hit along the gaze ray, otherwise a point
-- LOOK_DIST units out so the eyes still follow the direction.
local function WriteLookAt(dst, pos, ang, filter)
	local fwd = ang:Forward()
	local tr = util.TraceLine({
		start = pos,
		endpos = pos + fwd * 4096,
		filter = filter,
		mask = MASK_SHOT,
	})
	if tr.Hit and not tr.HitSky then
		dst.x, dst.y, dst.z = tr.HitPos.x, tr.HitPos.y, tr.HitPos.z
		return
	end
	dst.x = pos.x + fwd.x * LOOK_DIST
	dst.y = pos.y + fwd.y * LOOK_DIST
	dst.z = pos.z + fwd.z * LOOK_DIST
end

local function LocalSlot(ply)
	if not IsValid(ply) then return nil end
	g_VR.net = g_VR.net or {}
	local sid = ply:SteamID()
	g_VR.net[sid] = g_VR.net[sid] or {}
	local slot = g_VR.net[sid].eyeGaze
	if not slot then
		slot = { active = false, lookAt = Vector(), ang = Angle(), localAng = Angle(), time = 0 }
		g_VR.net[sid].eyeGaze = slot
	end
	return slot
end

local lastSentActive = nil
local nextSend = 0

local function SendGaze(active, et)
	if vrmod.EyeTrackingAllowed and not vrmod.EyeTrackingAllowed() then return end
	local now = CurTime()
	if active == lastSentActive and (not active or now < nextSend) then return end
	-- Stay quiet until a real sample has been shared.
	if not active and lastSentActive ~= true then return end
	lastSentActive = active
	nextSend = now + SEND_DT
	net.Start("vrmod_eye_gaze", true)
	net.WriteBool(active)
	if active then
		net.WriteVector(et.lookAt)
		net.WriteAngle(et.ang)
		net.WriteAngle(et.localAng)
	end
	net.SendToServer()
end

local function ApplyLocal()
	local et = g_VR.eyeTracking
	local lp = LocalPlayer()
	et.enabled = EyeConvarOn()
	if isfunction(VRMOD_EyeGazeSupported) then
		local ok, sup = pcall(VRMOD_EyeGazeSupported)
		if ok and sup then et.supported = true end
	end

	local pose = g_VR.tracking and g_VR.tracking.pose_gaze
	local hmd = g_VR.tracking and g_VR.tracking.hmd
	local fresh = pose and pose.pos and pose.ang and hmd and hmd.ang
	if fresh then et.supported = true end

	-- Archived default is 0, so a connected eye tracker stayed off.
	-- Arm once when a real gaze sample arrives. A later explicit 0 stays off.
	if fresh and not et.enabled and not g_VR._eyeGazeArmed then
		g_VR._eyeGazeArmed = true
		RunConsoleCommand("vrmod_eyetracking", "1")
		et.enabled = true
	end

	local was = et.active
	et.active = et.enabled and fresh and true or false
	et.openness = nil
	if not et.active then
		if was then RestoreEyes(lp) end
		local slot = LocalSlot(lp)
		if slot then
			slot.active = false
			slot.time = CurTime()
		end
		if g_VR.active then SendGaze(false, et) end
		return
	end

	WriteVec(et.pos, pose.pos)
	WriteAng(et.ang, pose.ang)
	local _, rel = WorldToLocal(vector_origin, pose.ang, vector_origin, hmd.ang)
	WriteAng(et.localAng, rel)
	WriteLookAt(et.lookAt, pose.pos, pose.ang, lp)

	local slot = LocalSlot(lp)
	if slot then
		slot.active = true
		WriteVec(slot.lookAt, et.lookAt)
		WriteAng(slot.ang, et.ang)
		WriteAng(slot.localAng, et.localAng)
		slot.time = CurTime()
	end
	if IsValid(lp) then lp:SetEyeTarget(et.lookAt) end
	SendGaze(true, et)
end

-- Remote frame tail. A fresh vrmod_eye_gaze sample (source "net") keeps the
-- traced look point. The tail is applied when that channel is idle, which is
-- how a peer with only the frame still moves character eyes.
-- A missing tail does not clear a "net" sample: older clients never write one.
function vrmod.EyeFrame_NoteRemote(ply, frame)
	if not IsValid(ply) or ply == LocalPlayer() then return end
	local slot = LocalSlot(ply)
	if not slot then return end
	local now = CurTime()
	local netFresh = slot.source == "net" and slot.active and slot.time and (now - slot.time) <= STALE_SEC
	local pitch, yaw
	if frame and vrmod.utils and vrmod.utils.EyeFrame_UnpackLocal then
		pitch, yaw = vrmod.utils.EyeFrame_UnpackLocal(frame.eyePitchU, frame.eyeYawU)
	end
	if pitch and frame.hmdPos and frame.hmdAng and vrmod.utils.EyeFrame_ComposeAng then
		if netFresh then return end
		local hp = frame.hmdAng.p or frame.hmdAng.pitch or 0
		local hy = frame.hmdAng.y or frame.hmdAng.yaw or 0
		local hr = frame.hmdAng.r or frame.hmdAng.roll or 0
		local p, y, r = vrmod.utils.EyeFrame_ComposeAng(hp, hy, hr, pitch, yaw)
		if not p then return end
		slot.active = true
		slot.source = "frame"
		slot.time = now
		local ang = Angle(p, y, r)
		WriteAng(slot.ang, ang)
		WriteAng(slot.localAng, Angle(pitch, yaw, 0))
		local fwd = ang:Forward()
		slot.lookAt.x = frame.hmdPos.x + fwd.x * LOOK_DIST
		slot.lookAt.y = frame.hmdPos.y + fwd.y * LOOK_DIST
		slot.lookAt.z = frame.hmdPos.z + fwd.z * LOOK_DIST
		ply:SetEyeTarget(slot.lookAt)
		return
	end
	if slot.source == "frame" and slot.active then
		slot.active = false
		slot.time = now
		RestoreEyes(ply)
	end
end

hook.Add("VRMod_Tracking", "vrmod_eye_tracking", ApplyLocal)

-- Once for the stereo pair, immediately before both eyes draw.
hook.Add("VRMod_PreStereo", "vrmod_eye_tracking_apply", function()
	local et = g_VR.eyeTracking
	local lp = LocalPlayer()
	if et and et.active and et.lookAt and IsValid(lp) then
		lp:SetEyeTarget(et.lookAt)
	end
end)

-- Draw-time apply. Same stored lookAt for every eye; nothing is recomputed here.
hook.Add("PrePlayerDraw", "vrmod_eye_gaze_draw", function(ply)
	if not IsValid(ply) then return end
	local tab = g_VR.net and g_VR.net[ply:SteamID()]
	local eg = tab and tab.eyeGaze
	if eg and eg.active and eg.lookAt then
		ply:SetEyeTarget(eg.lookAt)
	end
end)

hook.Add("VRMod_Exit", "vrmod_eye_tracking_exit", function(ply)
	if ply ~= LocalPlayer() then return end
	local et = g_VR.eyeTracking
	if et then
		et.active = false
		et.supported = false
	end
	local slot = LocalSlot(ply)
	if slot then slot.active = false end
	lastSentActive = nil
	RestoreEyes(ply)
	SendGaze(false, et or {})
end)

hook.Add("VRMod_OpenQuickMenu", "eyetrack_quickmenu", function()
	if not vrmod.RemoveInGameMenuItem or not vrmod.AddInGameMenuItem then return end
	vrmod.RemoveInGameMenuItem("Enable Eye Tracking")
	vrmod.RemoveInGameMenuItem("Disable Eye Tracking")
	if EyeConvarOn() then
		vrmod.AddInGameMenuItem("Disable Eye Tracking", 5, 1, function()
			RunConsoleCommand("vrmod_eyetracking", "0")
		end, false, nil, "eyetrack_disable")
	else
		vrmod.AddInGameMenuItem("Enable Eye Tracking", 5, 1, function()
			RunConsoleCommand("vrmod_eyetracking", "1")
		end, false, "OpenXR gaze", "eyetrack_enable")
	end
end)

net.Receive("vrmod_eye_gaze", function()
	local ply = net.ReadEntity()
	if not IsValid(ply) or ply == LocalPlayer() then return end
	local sid = ply:SteamID()
	g_VR.net = g_VR.net or {}
	g_VR.net[sid] = g_VR.net[sid] or {}
	local active = net.ReadBool()
	local slot = g_VR.net[sid].eyeGaze
	if not slot then
		slot = { active = false, lookAt = Vector(), ang = Angle(), localAng = Angle(), time = 0 }
		g_VR.net[sid].eyeGaze = slot
	end
	if not active then
		-- Frame-owned look stays until a tailless tick or the stale timer.
		-- An explicit false still clears a legacy sample.
		if slot.source == "frame" and slot.active then return end
		if slot.active then RestoreEyes(ply) end
		slot.active = false
		slot.source = "net"
		slot.time = CurTime()
		return
	end
	if slot.source == "frame" and slot.active and slot.time and (CurTime() - slot.time) <= STALE_SEC then
		return
	end
	slot.time = CurTime()
	slot.active = true
	slot.source = "net"
	WriteVec(slot.lookAt, net.ReadVector())
	WriteAng(slot.ang, net.ReadAngle())
	WriteAng(slot.localAng, net.ReadAngle())
	ply:SetEyeTarget(slot.lookAt)
end)

-- Once per frame, not once per eye. Both eyes share slot.lookAt.
hook.Add("Think", "vrmod_eye_gaze_apply", function()
	if not g_VR.net then return end
	local now = CurTime()
	for sid, tab in pairs(g_VR.net) do
		local eg = tab and tab.eyeGaze
		if eg and eg.active then
			local ply = player.GetBySteamID(sid)
			if eg.time and now - eg.time > STALE_SEC then
				eg.active = false
				RestoreEyes(ply)
			elseif IsValid(ply) and eg.lookAt then
				ply:SetEyeTarget(eg.lookAt)
			end
		end
	end
end)
