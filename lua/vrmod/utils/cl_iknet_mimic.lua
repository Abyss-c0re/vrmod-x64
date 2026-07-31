-- =============================================================================
-- vrmod.iknet.mimic — Client: record VR IK + drive NPC / any ValveBiped with charik
--
-- Law: same frame schema + charik.Update (player / twin / NPC one energy path).
-- Never write g_VR.net for NPC. Relative retarget via FrameToAbsolute(npc feet).
--
-- Braincube: recording → ExportPlate → data/vrmod/iknet_plate_*.json
-- =============================================================================
if SERVER then return end

vrmod = vrmod or {}
vrmod.iknet = vrmod.iknet or {}
local N = vrmod.iknet
N.mimic = N.mimic or {}
N.record = N.record or {}

local sessions = {} -- [entIndex] = session
local recBuf = nil
local recActive = false
local recMeta = {}

local cv_rec = CreateClientConVar("vrmod_iknet_record", "0", false, FCVAR_NONE, "1 = record local VR relative frames")
local cv_rate = CreateClientConVar("vrmod_iknet_rate", "30", true, FCVAR_ARCHIVE, "Mimic/record Hz", 5, 90)

------------------------------------------------------------------------
-- Source frames
------------------------------------------------------------------------
local function CopyNetFrame(steamid)
	local tab = g_VR.net and g_VR.net[steamid]
	local src = tab and tab.lerpedFrame
	if not src then return nil end
	return vrmod.utils.CopyFrame(src)
end

local function LocalAbsFrame()
	local lp = LocalPlayer()
	if not IsValid(lp) then return nil end
	if g_VR and g_VR.active then
		local fr = CopyNetFrame(lp:SteamID())
		if fr and fr.lefthandPos then return fr end
	end
	-- tracking fallback (not writing net)
	local tr = g_VR and g_VR.tracking
	if not tr or not tr.hmd or not tr.hmd.pos then return nil end
	local frame = {
		characterYaw = g_VR.characterYaw or (tr.hmd.ang and tr.hmd.ang.yaw) or 0,
		hmdPos = Vector(tr.hmd.pos),
		hmdAng = Angle(tr.hmd.ang.p, tr.hmd.ang.y, tr.hmd.ang.r),
	}
	if tr.pose_lefthand and tr.pose_lefthand.pos then
		frame.lefthandPos = Vector(tr.pose_lefthand.pos)
		frame.lefthandAng = Angle(tr.pose_lefthand.ang.p, tr.pose_lefthand.ang.y, tr.pose_lefthand.ang.r)
	end
	if tr.pose_righthand and tr.pose_righthand.pos then
		frame.righthandPos = Vector(tr.pose_righthand.pos)
		frame.righthandAng = Angle(tr.pose_righthand.ang.p, tr.pose_righthand.ang.y, tr.pose_righthand.ang.r)
	end
	local inL = g_VR.input and g_VR.input.skeleton_lefthand and g_VR.input.skeleton_lefthand.fingerCurls
	local inR = g_VR.input and g_VR.input.skeleton_righthand and g_VR.input.skeleton_righthand.fingerCurls
	for i = 1, 5 do
		frame["finger" .. i] = inL and inL[i] or 0
		frame["finger" .. (i + 5)] = inR and inR[i] or 0
	end
	return frame
end

--- Absolute frame for a source: "local" | steamid | packed sequence index via session
function N.GetSourceFrame(source)
	if not source or source == "local" or source == "" then
		return LocalAbsFrame()
	end
	return CopyNetFrame(source)
end

------------------------------------------------------------------------
-- Record (relative on player feet — retargetable)
------------------------------------------------------------------------
function N.record.Start(opts)
	opts = opts or {}
	recBuf = N.NewBuffer(opts.capacity or 1800) -- 60s @ 30Hz
	recActive = true
	recMeta = {
		started = SysTime(),
		source = opts.source or "local",
		map = game.GetMap and game.GetMap() or "?",
	}
	vrmod.logger.Info("[iknet] record START cap=%s", recBuf.cap)
	return true
end

function N.record.Stop()
	recActive = false
	vrmod.logger.Info("[iknet] record STOP n=%s", recBuf and recBuf.n or 0)
	return recBuf
end

function N.record.IsActive()
	return recActive and recBuf ~= nil
end

function N.record.Buffer()
	return recBuf
end

function N.record.Save(name)
	if not recBuf or recBuf.n < 1 then
		vrmod.logger.Warn("[iknet] nothing to save")
		return nil
	end
	name = name or ("iknet_" .. os.date("%Y%m%d_%H%M%S"))
	-- Heavy plate export off the VR tick — deferred one frame so record_stop stays snappy
	local buf, meta = recBuf, recMeta
	timer.Simple(0, function()
		local ok, err = pcall(function()
			local plate = N.ExportPlate(buf, meta)
			file.CreateDir("vrmod")
			file.CreateDir("vrmod/iknet")
			local path = "vrmod/iknet/" .. name .. ".json"
			local head = util.TableToJSON({
				schema = plate.schema,
				kind = plate.kind,
				ts = plate.ts,
				meta = plate.meta,
				n = plate.n,
			}, true)
			local ndPath = "vrmod/iknet/" .. name .. ".ndjson"
			local nd = {}
			for _, s in ipairs(plate.samples) do
				nd[#nd + 1] = util.TableToJSON({
					i = s.i,
					digit = s.digit,
					payload = s.payload,
					seed = s.seed,
					feat = s.feat,
					bits = s.bits,
					frame = s.frame,
				})
			end
			file.Write(path, head or "{}")
			file.Write(ndPath, table.concat(nd, "\n") .. "\n")
			vrmod.logger.Info("[iknet] saved data/%s + %s n=%s", path, ndPath, plate.n)
		end)
		if not ok then
			vrmod.logger.Err("[iknet] save failed: %s", err)
		end
	end)
	return "vrmod/iknet/" .. name .. ".json", "vrmod/iknet/" .. name .. ".ndjson", buf.n
end

local function tickRecord()
	if not recActive or not recBuf then return end
	if cv_rec:GetInt() == 0 and not recActive then return end
	local abs = N.GetSourceFrame(recMeta.source or "local")
	if not abs then return end
	local originPos, originAng = vrmod.utils.FrameOrigin(abs, LocalPlayer():GetPos())
	local rel = vrmod.utils.FrameToRelative(abs, originPos, originAng)
	if not rel then return end
	-- store yaw relative to origin (0 when facing origin forward)
	rel.characterYaw = 0
	rel.characterYawAbsolute = false
	rel.ts = SysTime()
	N.BufferPush(recBuf, rel, true)
end

------------------------------------------------------------------------
-- Mimic session on entity
------------------------------------------------------------------------
local Session = {}
Session.__index = Session

function Session:Stop()
	self.active = false
	if self.hookId then
		hook.Remove("PostDrawOpaqueRenderables", self.hookId)
		hook.Remove("PostDrawTranslucentRenderables", self.hookId)
		hook.Remove("Think", self.hookId .. "_think")
	end
	if self.boneCb and IsValid(self.ent) then
		self.ent:RemoveCallback("BuildBonePositions", self.boneCb)
		self.boneCb = nil
	end
	if self.ik and IsValid(self.ent) then
		local charik = vrmod.charik or vrmod.frameik
		if charik and charik.ClearManip then
			pcall(charik.ClearManip, self.ent, self.ik)
		end
	end
	if IsValid(self.ent) then
		sessions[self.ent:EntIndex()] = nil
	end
	self.ent = nil
end

function Session:_resolveFrame()
	if self.mode == "playback" and self.sequence and #self.sequence > 0 then
		local t = SysTime() - (self.playStart or SysTime())
		local hz = self.hz or cv_rate:GetFloat()
		local idx = math.floor(t * hz) + 1
		if self.loop then
			idx = ((idx - 1) % #self.sequence) + 1
		elseif idx > #self.sequence then
			idx = #self.sequence
		end
		local packed = self.sequence[idx]
		local rel = N.Unpack(packed)
		if not rel then return nil end
		local originPos = self.ent:GetPos()
		local originAng = Angle(0, self.ent:GetAngles().yaw, 0)
		return vrmod.utils.FrameToAbsolute(rel, originPos, originAng)
	end

	-- live: absolute from source, re-origin to NPC feet
	local abs = N.GetSourceFrame(self.source)
	if not abs then return nil end
	local srcOrigin, srcAng = vrmod.utils.FrameOrigin(abs)
	local rel = vrmod.utils.FrameToRelative(abs, srcOrigin, srcAng)
	if not rel then return nil end
	rel.characterYaw = 0
	local dstPos = self.ent:GetPos()
	local dstAng = Angle(0, self.ent:GetAngles().yaw, 0)
	local world = vrmod.utils.FrameToAbsolute(rel, dstPos, dstAng)
	if world then
		world.characterYaw = dstAng.yaw
	end
	return world
end

function Session:_tick()
	if not self.active or not IsValid(self.ent) then return end
	local charik = vrmod.charik or vrmod.frameik
	if not charik then return end
	if not self.ik then
		self.ik = charik.Init(self.ent, {
			noStretch = self.noStretch ~= false,
			headDampen = true,
		})
		if not self.ik then return end
	end

	local frame = self:_resolveFrame()
	if not frame then
		self.miss = (self.miss or 0) + 1
		return
	end
	self.miss = 0
	self.lastFrame = frame

	-- braincube observe: throttled (never every frame — export plate does bulk offline)
	if self.train and vrmod.algocube then
		local now = SysTime()
		if not self._nextTrain or now >= self._nextTrain then
			self._nextTrain = now + 0.25 -- 4 Hz max
			local o, a = vrmod.utils.FrameOrigin(frame, self.ent:GetPos())
			local rel = vrmod.utils.FrameToRelative(frame, o, a) or frame
			local digit, payload = N.BrainDecide(rel, self.algo)
			self.lastDigit = digit
			self.lastPayload = payload
			g_VR.iknetDiag = g_VR.iknetDiag or {}
			g_VR.iknetDiag.digit = digit
			g_VR.iknetDiag.ent = self.ent:EntIndex()
			g_VR.iknetDiag.ts = now
		end
	end

	-- Pose apply is the only hot work; no logging here
	charik.Update(self.ent, self.ik, frame, {
		baseZ = self.ent:GetPos().z,
		eyeHeight = self.eyeHeight or 66.8,
		applyManip = true,
		plyAng = Angle(0, frame.characterYaw or self.ent:GetAngles().yaw, 0),
	})
end

function Session:_applyBones()
	if not self.active or not IsValid(self.ent) or not self.ik then return end
	local charik = vrmod.charik or vrmod.frameik
	if not charik then return end
	if charik.ApplyMatrices then
		charik.ApplyMatrices(self.ent, self.ik)
	end
	if charik.ApplyHead and self.lastFrame then
		charik.ApplyHead(self.ent, self.ik, self.lastFrame)
	end
end

--- Start mimicking on ent (NPC, nextbot, ClientsideModel, ragdoll with bones).
-- opts.source = "local" | SteamID
-- opts.mode = "live" | "playback"
-- opts.sequence = packed frame list (relative)
-- opts.train = bool  (feed braincube digits)
-- opts.loop = bool for playback
function N.mimic.Start(ent, opts)
	if not IsValid(ent) then return nil end
	opts = opts or {}
	local id = ent:EntIndex()
	if sessions[id] then sessions[id]:Stop() end

	local s = setmetatable({
		active = true,
		ent = ent,
		source = opts.source or "local",
		mode = opts.mode or "live",
		sequence = opts.sequence,
		loop = opts.loop ~= false,
		hz = opts.hz or cv_rate:GetFloat(),
		noStretch = opts.noStretch ~= false,
		train = opts.train and true or false,
		algo = vrmod.algocube and vrmod.algocube.New(0xB001) or nil,
		eyeHeight = opts.eyeHeight or 66.8,
		hookId = "vrmod_iknet_mimic_" .. id,
		playStart = SysTime(),
		ik = nil,
	}, Session)

	-- Prefer player models
	if ent.SetIK then pcall(function() ent:SetIK(false) end) end

	s.boneCb = ent:AddCallback("BuildBonePositions", function(e, _)
		if not s.active then return end
		s:_applyBones()
	end)

	hook.Add("Think", s.hookId .. "_think", function()
		if not s.active then return end
		-- rate limit
		local now = SysTime()
		local dt = 1 / math.max(5, s.hz or 30)
		if s._next and now < s._next then return end
		s._next = now + dt
		pcall(function() s:_tick() end)
	end)

	-- SetupBones only when we have a fresh pose (avoid dual-eye double work every draw)
	hook.Add("PostDrawOpaqueRenderables", s.hookId, function(depth, sky)
		if depth or sky or not s.active or not IsValid(s.ent) then return end
		if not s.lastFrame then return end
		local fn = FrameNumber()
		if s._lastSetupFrame == fn then return end
		s._lastSetupFrame = fn
		pcall(function()
			s.ent:InvalidateBoneCache()
			s.ent:SetupBones()
		end)
	end)

	sessions[id] = s
	vrmod.logger.Info("[iknet] mimic START ent=%s mode=%s source=%s train=%s",
		id, s.mode, s.source, s.train)
	return s
end

function N.mimic.Stop(ent)
	if isnumber(ent) then
		local s = sessions[ent]
		if s then s:Stop() end
		return
	end
	if IsValid(ent) and sessions[ent:EntIndex()] then
		sessions[ent:EntIndex()]:Stop()
	end
end

function N.mimic.StopAll()
	for _, s in pairs(sessions) do
		if s then s:Stop() end
	end
end

function N.mimic.Get(ent)
	if not IsValid(ent) then return nil end
	return sessions[ent:EntIndex()]
end

function N.mimic.List()
	local t = {}
	for id, s in pairs(sessions) do
		if s and s.active then t[#t + 1] = id end
	end
	return t
end

------------------------------------------------------------------------
-- Think: optional continuous record
------------------------------------------------------------------------
hook.Add("Think", "vrmod_iknet_record", function()
	if recActive or cv_rec:GetBool() then
		if cv_rec:GetBool() and not recActive then
			N.record.Start({ source = "local" })
		end
		local now = SysTime()
		local dt = 1 / math.max(5, cv_rate:GetFloat())
		if not N._recNext or now >= N._recNext then
			N._recNext = now + dt
			pcall(tickRecord)
		end
	end
end)

hook.Add("VRMod_Exit", "vrmod_iknet_cleanup", function(ply)
	if ply == LocalPlayer() then
		if recActive then N.record.Stop() end
		N.mimic.StopAll()
	end
end)

------------------------------------------------------------------------
-- Console
------------------------------------------------------------------------
concommand.Add("vrmod_iknet_record_start", function()
	N.record.Start({ source = "local" })
	cv_rec:SetInt(1)
end)

concommand.Add("vrmod_iknet_record_stop", function()
	cv_rec:SetInt(0)
	N.record.Stop()
end)

concommand.Add("vrmod_iknet_record_save", function(_, _, args)
	cv_rec:SetInt(0)
	N.record.Stop()
	N.record.Save(args[1])
end)

concommand.Add("vrmod_iknet_mimic", function(ply, cmd, args)
	-- vrmod_iknet_mimic <entindex> [steamid|local] [train=1]
	local idx = tonumber(args[1] or "")
	if not idx then
		-- aim: use eye trace entity
		local lp = LocalPlayer()
		local tr = lp:GetEyeTrace()
		if IsValid(tr.Entity) then idx = tr.Entity:EntIndex() end
	end
	if not idx then
		vrmod.logger.Info("[iknet] usage: vrmod_iknet_mimic <entindex|aim> [local|STEAM_x] [train]")
		return
	end
	local ent = Entity(idx)
	if not IsValid(ent) then
		vrmod.logger.Warn("[iknet] invalid ent %s", idx)
		return
	end
	local source = args[2] or "local"
	local train = args[3] == "1" or args[3] == "train"
	N.mimic.Start(ent, { source = source, mode = "live", train = train })
end)

concommand.Add("vrmod_iknet_mimic_stop", function(_, _, args)
	local idx = tonumber(args[1] or "")
	if idx then
		N.mimic.Stop(idx)
	else
		N.mimic.StopAll()
	end
end)

concommand.Add("vrmod_iknet_playback", function(_, _, args)
	-- playback last recording onto aimed/ent
	local idx = tonumber(args[1] or "")
	local ent = idx and Entity(idx) or LocalPlayer():GetEyeTrace().Entity
	if not IsValid(ent) then
		vrmod.logger.Warn("[iknet] aim at NPC or pass entindex")
		return
	end
	local buf = recBuf
	if not buf or buf.n < 1 then
		vrmod.logger.Warn("[iknet] no buffer — record first or load")
		return
	end
	N.mimic.Start(ent, {
		mode = "playback",
		sequence = N.BufferList(buf),
		loop = true,
		train = args[2] == "train",
	})
end)

concommand.Add("vrmod_iknet_status", function()
	vrmod.logger.Info("========== vrmod iknet ==========")
	vrmod.logger.Info("record active=%s n=%s", recActive, recBuf and recBuf.n or 0)
	vrmod.logger.Info("mimic sessions=%s", table.concat(N.mimic.List(), ","))
	local d = g_VR.iknetDiag
	if d then
		vrmod.logger.Info("brain digit=%s ent=%s ts=%.2f", d.digit, d.ent, tonumber(d.ts) or 0)
	end
	vrmod.logger.Info("=================================")
end)

-- Net: server bind NPC to source (optional)
net.Receive("vrmod_iknet_bind", function()
	local ent = net.ReadEntity()
	local source = net.ReadString()
	local train = net.ReadBool()
	if not IsValid(ent) then return end
	if source == "" or source == "stop" then
		N.mimic.Stop(ent)
		return
	end
	N.mimic.Start(ent, { source = source, mode = "live", train = train })
end)

return N.mimic
