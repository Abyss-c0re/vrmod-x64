if SERVER then return end
-- =============================================================================
-- Desktop follow camera + broadcast module seam
--
-- Desktop view modes (vrmod_desktopview):
--   1 = none
--   2 = left eye (stereo RT crop)
--   3 = right eye (stereo RT crop)
--   4 = invisible follow camera (this module) → desktop + optional broadcast
--
-- External apps / native bridges register via vrmod.DesktopBroadcast.Register:
--   control hooks (future remote app) + OnVideoFrame for streaming.
-- Local desktop mirror works without a registered module.
-- =============================================================================

vrmod = vrmod or {}
vrmod.DesktopBroadcast = vrmod.DesktopBroadcast or {}
vrmod.DesktopCam = vrmod.DesktopCam or {}

local DB = vrmod.DesktopBroadcast
local DC = vrmod.DesktopCam

-- Desktop view enum (shared with settings / launcher)
DC.VIEW_NONE = 1
DC.VIEW_LEFT = 2
DC.VIEW_RIGHT = 3
DC.VIEW_FOLLOW_CAM = 4

local cvDist = CreateClientConVar("vrmod_desktop_cam_dist", "72", true, FCVAR_ARCHIVE,
	"Follow-cam distance behind target (units)", 16, 256)
local cvHeight = CreateClientConVar("vrmod_desktop_cam_height", "28", true, FCVAR_ARCHIVE,
	"Follow-cam height above target feet/HMD base (units)", -32, 128)
local cvFov = CreateClientConVar("vrmod_desktop_cam_fov", "75", true, FCVAR_ARCHIVE,
	"Follow-cam FOV", 40, 120)
local cvMode = CreateClientConVar("vrmod_desktop_cam_mode", "0", true, FCVAR_ARCHIVE,
	"0=behind HMD 1=behind player body 2=module-only (needs broadcast module)", 0, 2)
local cvSmooth = CreateClientConVar("vrmod_desktop_cam_smooth", "0.15", true, FCVAR_ARCHIVE,
	"Follow-cam position/angle smooth (0=snap 1=heavy)", 0, 1)
local cvDrawLocal = CreateClientConVar("vrmod_desktop_cam_draw", "1", true, FCVAR_ARCHIVE,
	"When desktopview=follow cam, also blit to GMod window (0=broadcast-only)", 0, 1)

-- Registered external modules (id → mod table)
local modules = {}
local activeModuleId = nil

-- Invisible camera state (no world entity — pure pose + RenderView)
local session = {
	active = false,
	rt = nil,
	rtW = 0,
	rtH = 0,
	mat = nil,
	pos = nil,
	ang = nil,
	frameId = 0,
}

local function log(fmt, ...)
	if vrmod.logger then
		vrmod.logger.Info("[DesktopCam] " .. fmt, ...)
	end
end

--- Pure pose math (offline-testable). Target looks along `fwd`, camera sits behind + up.
function DC.ComputeFollowPose(targetPos, targetAng, dist, height)
	if not targetPos then return Vector(), Angle() end
	targetAng = targetAng or Angle(0, 0, 0)
	dist = tonumber(dist) or 72
	height = tonumber(height) or 28
	local yaw = Angle(0, targetAng.y, 0)
	local back = -yaw:Forward()
	local pos = targetPos + back * dist + Vector(0, 0, height)
	local look = (targetPos + Vector(0, 0, height * 0.35) - pos):Angle()
	look.r = 0
	return pos, look
end

function DC.IsFollowMode(desktopView)
	return tonumber(desktopView) == DC.VIEW_FOLLOW_CAM
end

--- Clamp to 1..4 (none / left / right / follow-cam). Pure — G23 call-site SoT.
function DC.ClampDesktopView(desktopView)
	local v = math.floor(tonumber(desktopView) or DC.VIEW_NONE)
	if v < DC.VIEW_NONE then return DC.VIEW_NONE end
	if v > DC.VIEW_FOLLOW_CAM then return DC.VIEW_FOLLOW_CAM end
	return v
end

--- Cycle desktop view (dir ±1). Pure.
function DC.CycleDesktopView(desktopView, dir)
	dir = tonumber(dir) or 1
	if dir == 0 then dir = 1 end
	local v = DC.ClampDesktopView(desktopView)
	return 1 + ((v - 1 + dir) % 4 + 4) % 4
end

--- Short label for UI / logs.
function DC.DesktopViewLabel(desktopView)
	local v = DC.ClampDesktopView(desktopView)
	if v == DC.VIEW_LEFT then return "left" end
	if v == DC.VIEW_RIGHT then return "right" end
	if v == DC.VIEW_FOLLOW_CAM then return "follow_cam" end
	return "none"
end

--- True when desktop should use stereo eye crop blit (modes 2/3 only — never 4).
function DC.IsEyeCropMode(desktopView)
	local v = DC.ClampDesktopView(desktopView)
	return v == DC.VIEW_LEFT or v == DC.VIEW_RIGHT
end

-- ─── Broadcast module registry (future control + video app) ───────────────

--- Register an external control/broadcast module.
--- mod = {
---   id = "my_bridge",
---   OnSessionStart = function() end,
---   OnSessionStop = function() end,
---   --- Optional camera override (world pos/ang/fov). Return nil to use built-in follow.
---   GetCamera = function() return pos, ang, fov end,
---   --- Called each frame after RenderView into RT (for encode/stream).
---   OnVideoFrame = function(rt, w, h, frameId, meta) end,
---   --- Future remote control: return command table or nil.
---   OnControlPoll = function() return nil end,
--- }
function DB.Register(mod)
	if type(mod) ~= "table" or not mod.id or mod.id == "" then
		return false, "mod.id required"
	end
	modules[mod.id] = mod
	if not activeModuleId then
		activeModuleId = mod.id
	end
	log("Registered broadcast module %s", tostring(mod.id))
	if session.active and isfunction(mod.OnSessionStart) then
		pcall(mod.OnSessionStart)
	end
	return true
end

function DB.Unregister(id)
	if not id then return end
	local m = modules[id]
	if m and session.active and isfunction(m.OnSessionStop) then
		pcall(m.OnSessionStop)
	end
	modules[id] = nil
	if activeModuleId == id then
		activeModuleId = next(modules)
	end
end

function DB.SetActive(id)
	if id and modules[id] then
		activeModuleId = id
		return true
	end
	return false
end

function DB.GetActive()
	return activeModuleId and modules[activeModuleId] or nil
end

function DB.HasModule()
	return DB.GetActive() ~= nil
end

function DB.List()
	local t = {}
	for id in pairs(modules) do
		t[#t + 1] = id
	end
	return t
end

-- ─── Session / RT ─────────────────────────────────────────────────────────

local function ensureRT(w, h)
	w = math.max(320, math.floor(w or ScrW()))
	h = math.max(180, math.floor(h or ScrH()))
	-- Cap cost for stream + desktop
	if w > 1920 then
		h = math.floor(h * (1920 / w))
		w = 1920
	end
	if session.rt and session.rtW == w and session.rtH == h and session.rt:IsValid() then
		return session.rt
	end
	if session.rt and session.rt:IsValid() then
		-- GetRenderTarget reuses name; size change needs new name
	end
	local name = string.format("vrmod_desktop_cam_%dx%d", w, h)
	session.rt = GetRenderTarget(name, w, h, false)
	session.rtW, session.rtH = w, h
	session.mat = CreateMaterial("vrmod_desktop_cam_mat_" .. w .. "x" .. h, "UnlitGeneric", {
		["$basetexture"] = session.rt:GetName(),
		["$translucent"] = 0,
		["$nolod"] = 1,
		["$ignorez"] = 1,
	})
	if session.mat and not session.mat:IsError() then
		session.mat:SetTexture("$basetexture", session.rt)
	end
	return session.rt
end

function DC.Start()
	if session.active then return end
	session.active = true
	session.pos = nil
	session.ang = nil
	session.frameId = 0
	ensureRT(ScrW(), ScrH())
	local mod = DB.GetActive()
	if mod and isfunction(mod.OnSessionStart) then
		pcall(mod.OnSessionStart)
	end
	log("Follow-cam session start")
end

function DC.Stop()
	if not session.active then return end
	session.active = false
	local mod = DB.GetActive()
	if mod and isfunction(mod.OnSessionStop) then
		pcall(mod.OnSessionStop)
	end
	log("Follow-cam session stop")
end

function DC.IsActive()
	return session.active == true
end

function DC.GetRT()
	return session.rt, session.rtW, session.rtH
end

function DC.GetPose()
	return session.pos, session.ang
end

--- Resolve world camera pose for this frame.
function DC.ResolveCamera()
	local mod = DB.GetActive()
	local mode = cvMode:GetInt()

	-- Mode 2: module must supply camera; if missing, fall back to HMD follow
	if mode == 2 and mod and isfunction(mod.GetCamera) then
		local ok, p, a, f = pcall(mod.GetCamera)
		if ok and p and a then
			return p, a, tonumber(f) or cvFov:GetFloat()
		end
	end

	-- Optional module override even in mode 0/1
	if mod and isfunction(mod.GetCamera) then
		local ok, p, a, f = pcall(mod.GetCamera)
		if ok and p and a then
			return p, a, tonumber(f) or cvFov:GetFloat()
		end
	end

	local dist = cvDist:GetFloat()
	local height = cvHeight:GetFloat()
	local fov = cvFov:GetFloat()
	local targetPos, targetAng

	if mode == 1 then
		local ply = LocalPlayer()
		if IsValid(ply) then
			targetPos = ply:GetPos() + Vector(0, 0, 64)
			targetAng = Angle(0, ply:EyeAngles().y, 0)
			if g_VR and g_VR.tracking and g_VR.tracking.hmd and g_VR.tracking.hmd.ang then
				targetAng = Angle(0, g_VR.tracking.hmd.ang.y, 0)
			end
		end
	end

	if not targetPos and g_VR and g_VR.tracking and g_VR.tracking.hmd then
		local hmd = g_VR.tracking.hmd
		targetPos = hmd.pos
		targetAng = hmd.ang
	end

	if not targetPos then
		local ply = LocalPlayer()
		if IsValid(ply) then
			targetPos = ply:EyePos()
			targetAng = ply:EyeAngles()
		else
			return Vector(), Angle(0, 0, 0), fov
		end
	end

	local pos, ang = DC.ComputeFollowPose(targetPos, targetAng, dist, height)
	return pos, ang, fov
end

local function smoothPose(pos, ang)
	local s = math.Clamp(cvSmooth:GetFloat(), 0, 1)
	if s <= 0 or not session.pos then
		session.pos = Vector(pos)
		session.ang = Angle(ang)
		return session.pos, session.ang
	end
	-- Higher s = stickier previous
	local k = 1 - s
	session.pos = LerpVector(k, session.pos, pos)
	session.ang = LerpAngle(k, session.ang, ang)
	return session.pos, session.ang
end

--- Capture one frame into RT. Call only when NOT nested under stereo RT.
function DC.CaptureFrame()
	if not session.active then return false end
	if g_VR and g_VR.stereoRtActive then return false end

	local rt = ensureRT(ScrW(), ScrH())
	if not rt then return false end

	local pos, ang, fov = DC.ResolveCamera()
	pos, ang = smoothPose(pos, ang)
	session.frameId = session.frameId + 1

	local w, h = session.rtW, session.rtH
	render.PushRenderTarget(rt)
	local ok, err = pcall(function()
		render.Clear(0, 0, 0, 255, true, true)
		render.RenderView({
			origin = pos,
			angles = ang,
			x = 0,
			y = 0,
			w = w,
			h = h,
			fov = fov or 75,
			aspectratio = w / math.max(h, 1),
			drawhud = false,
			drawmonitors = true,
			drawviewmodel = false,
			dopostprocess = false,
		})
	end)
	render.PopRenderTarget()
	if not ok then
		if vrmod.logger then
			vrmod.logger.Warn("[DesktopCam] RenderView: %s", tostring(err))
		end
		return false
	end

	local mod = DB.GetActive()
	if mod and isfunction(mod.OnVideoFrame) then
		pcall(mod.OnVideoFrame, rt, w, h, session.frameId, {
			pos = pos,
			ang = ang,
			fov = fov,
		})
	end

	-- Future remote control poll (module drives app; gVRMod applies later)
	if mod and isfunction(mod.OnControlPoll) then
		local okc, cmd = pcall(mod.OnControlPoll)
		if okc and cmd and vrmod.DesktopBroadcast.ApplyControl then
			pcall(vrmod.DesktopBroadcast.ApplyControl, cmd)
		end
	end

	return true
end

--- Blit follow-cam RT to the full desktop framebuffer (RenderScene end).
function DC.PresentDesktop()
	if not session.active or not session.rt or not session.mat then return end
	if not cvDrawLocal:GetBool() then return end
	-- Only draw when follow-cam mode is selected
	local dv = g_VR and g_VR.desktopView
	if not DC.IsFollowMode(dv) then return end

	surface.SetDrawColor(255, 255, 255, 255)
	surface.SetMaterial(session.mat)
	-- Same NDC full-screen path as eye crop blit
	render.CullMode(1)
	surface.DrawTexturedRectUV(-1, -1, 2, 2, 0, 0, 1, 1)
	render.CullMode(0)
end

--- Sync session to desktopview convar (call from VR frame loop).
function DC.SyncFromDesktopView(desktopView)
	if DC.IsFollowMode(desktopView) then
		-- Mode 2 without module: still allow built-in follow so desktop is not black
		DC.Start()
	else
		DC.Stop()
	end
end

--- Hook VR start/exit
hook.Add("VRMod_Start", "vrmod_desktop_cam", function(ply)
	if ply ~= LocalPlayer() then return end
	local cv = GetConVar("vrmod_desktopview")
	if cv and DC.IsFollowMode(cv:GetInt()) then
		DC.Start()
	end
end)

hook.Add("VRMod_Exit", "vrmod_desktop_cam", function(ply)
	if ply ~= LocalPlayer() then return end
	DC.Stop()
end)

cvars.AddChangeCallback("vrmod_desktopview", function(_, _, new)
	if not g_VR or not g_VR.active then return end
	DC.SyncFromDesktopView(tonumber(new) or 1)
end, "vrmod_desktop_cam_mode_switch")
