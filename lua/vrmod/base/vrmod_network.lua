g_VR = g_VR or {}
local convars, convarValues = vrmod.GetConvars()
vrmod.AddCallbackedConvar("vrmod_net_tickrate", nil, tostring(math.ceil(1 / engine.TickInterval())), FCVAR_REPLICATED, nil, nil, nil, tonumber, nil)
local function netReadFrame()
	local frame = {
		ts = net.ReadFloat(),
		characterYaw = net.ReadUInt(7) * 2.85714,
		finger1 = net.ReadUInt(7) / 100,
		finger2 = net.ReadUInt(7) / 100,
		finger3 = net.ReadUInt(7) / 100,
		finger4 = net.ReadUInt(7) / 100,
		finger5 = net.ReadUInt(7) / 100,
		finger6 = net.ReadUInt(7) / 100,
		finger7 = net.ReadUInt(7) / 100,
		finger8 = net.ReadUInt(7) / 100,
		finger9 = net.ReadUInt(7) / 100,
		finger10 = net.ReadUInt(7) / 100,
		hmdPos = net.ReadVector(),
		hmdAng = net.ReadAngle(),
		lefthandPos = net.ReadVector(),
		lefthandAng = net.ReadAngle(),
		righthandPos = net.ReadVector(),
		righthandAng = net.ReadAngle(),
	}

	if net.ReadBool() then
		frame.waistPos = net.ReadVector()
		frame.waistAng = net.ReadAngle()
		frame.leftfootPos = net.ReadVector()
		frame.leftfootAng = net.ReadAngle()
		frame.rightfootPos = net.ReadVector()
		frame.rightfootAng = net.ReadAngle()
	end
	return frame
end

-- Per-frame cache reset
hook.Add("Think", "VRMod_ResetClientFrameCache", function()
	g_VR._cachedFrameRelative = nil
	g_VR._cachedFrameAbsolute = nil
end)

-- Caches and returns the built client frame
local function buildClientFrame(relative)
	local cacheKey = relative and "_cachedFrameRelative" or "_cachedFrameAbsolute"
	if g_VR[cacheKey] then return g_VR[cacheKey] end
	local lp = LocalPlayer()
	if not IsValid(lp) then return nil end
	local inVehicle = lp:InVehicle()
	local frame = {
		characterYaw = inVehicle and lp:EyeAngles().yaw or g_VR.characterYaw,
		hmdPos = g_VR.tracking.hmd.pos,
		hmdAng = g_VR.tracking.hmd.ang,
		lefthandPos = g_VR.tracking.pose_lefthand.pos,
		lefthandAng = g_VR.tracking.pose_lefthand.ang,
		righthandPos = g_VR.tracking.pose_righthand.pos,
		righthandAng = g_VR.tracking.pose_righthand.ang,
		finger1 = g_VR.input.skeleton_lefthand.fingerCurls[1],
		finger2 = g_VR.input.skeleton_lefthand.fingerCurls[2],
		finger3 = g_VR.input.skeleton_lefthand.fingerCurls[3],
		finger4 = g_VR.input.skeleton_lefthand.fingerCurls[4],
		finger5 = g_VR.input.skeleton_lefthand.fingerCurls[5],
		finger6 = g_VR.input.skeleton_righthand.fingerCurls[1],
		finger7 = g_VR.input.skeleton_righthand.fingerCurls[2],
		finger8 = g_VR.input.skeleton_righthand.fingerCurls[3],
		finger9 = g_VR.input.skeleton_righthand.fingerCurls[4],
		finger10 = g_VR.input.skeleton_righthand.fingerCurls[5],
	}

	if g_VR.sixPoints then
		frame.waistPos = g_VR.tracking.pose_waist.pos
		frame.waistAng = g_VR.tracking.pose_waist.ang
		frame.leftfootPos = g_VR.tracking.pose_leftfoot.pos
		frame.leftfootAng = g_VR.tracking.pose_leftfoot.ang
		frame.rightfootPos = g_VR.tracking.pose_rightfoot.pos
		frame.rightfootAng = g_VR.tracking.pose_rightfoot.ang
	end

	if relative then
		local plyPos = lp:GetPos()
		local plyAng = inVehicle and lp:GetVehicle():GetAngles() or Angle()
		frame.hmdPos, frame.hmdAng = WorldToLocal(frame.hmdPos, frame.hmdAng, plyPos, plyAng)
		frame.lefthandPos, frame.lefthandAng = WorldToLocal(frame.lefthandPos, frame.lefthandAng, plyPos, plyAng)
		frame.righthandPos, frame.righthandAng = WorldToLocal(frame.righthandPos, frame.righthandAng, plyPos, plyAng)
		if g_VR.sixPoints then
			frame.waistPos, frame.waistAng = WorldToLocal(frame.waistPos, frame.waistAng, plyPos, plyAng)
			frame.leftfootPos, frame.leftfootAng = WorldToLocal(frame.leftfootPos, frame.leftfootAng, plyPos, plyAng)
			frame.rightfootPos, frame.rightfootAng = WorldToLocal(frame.rightfootPos, frame.rightfootAng, plyPos, plyAng)
		end
	end

	frame = vrmod.utils.UpdateHandCollisionShapes(frame)
	g_VR[cacheKey] = frame
	return frame
end

local function netWriteFrame(frame)
	net.WriteFloat(SysTime())
	local tmp = frame.characterYaw + math.ceil(math.abs(frame.characterYaw) / 360) * 360 --normalize and convert characterYaw to 0-360
	tmp = tmp - math.floor(tmp / 360) * 360
	net.WriteUInt(frame.characterYaw * 0.35, 7) --crush from 0-360 to 0-127
	net.WriteUInt(frame.finger1 * 100, 7)
	net.WriteUInt(frame.finger2 * 100, 7)
	net.WriteUInt(frame.finger3 * 100, 7)
	net.WriteUInt(frame.finger4 * 100, 7)
	net.WriteUInt(frame.finger5 * 100, 7)
	net.WriteUInt(frame.finger6 * 100, 7)
	net.WriteUInt(frame.finger7 * 100, 7)
	net.WriteUInt(frame.finger8 * 100, 7)
	net.WriteUInt(frame.finger9 * 100, 7)
	net.WriteUInt(frame.finger10 * 100, 7)
	net.WriteVector(frame.hmdPos)
	net.WriteAngle(frame.hmdAng)
	net.WriteVector(frame.lefthandPos)
	net.WriteAngle(frame.lefthandAng)
	net.WriteVector(frame.righthandPos)
	net.WriteAngle(frame.righthandAng)
	net.WriteBool(frame.waistPos ~= nil)
	if frame.waistPos then
		net.WriteVector(frame.waistPos)
		net.WriteAngle(frame.waistAng)
		net.WriteVector(frame.leftfootPos)
		net.WriteAngle(frame.leftfootAng)
		net.WriteVector(frame.rightfootPos)
		net.WriteAngle(frame.rightfootAng)
	end
end

if CLIENT then
	vrmod.AddCallbackedConvar("vrmod_net_delay", nil, "0.1", nil, nil, nil, nil, tonumber, nil)
	vrmod.AddCallbackedConvar("vrmod_net_delaymax", nil, "0.2", nil, nil, nil, nil, tonumber, nil)
	vrmod.AddCallbackedConvar("vrmod_net_storedframes", nil, "15", nil, nil, nil, nil, tonumber, nil)
	local debugToggle = false
	concommand.Add("vrmod_net_debug", function(ply, cmd, args)
		if debugToggle then
			hook.Remove("PostRender", "vrutil_netdebug")
			debugToggle = false
			return
		end

		debugToggle = true
		hook.Add("PostRender", "vrutil_netdebug", function()
			cam.Start2D()
			surface.SetFont("ChatFont")
			surface.SetTextColor(255, 255, 255)
			surface.SetTextPos(128, 100)
			surface.DrawText("vrmod_net_debug")
			local leftSide, rightSide = 140, 628
			local verticalSpacing = 100
			local iply = 0
			for k, v in pairs(g_VR.net) do
				if not v.playbackTime then continue end
				if SysTime() - (v.debugTpsT or 0) > 1 then
					v.debugTpsT = SysTime()
					v.debugTps = v.debugTickCount
					v.debugTickCount = 0
				end

				local mints, maxts = 9999999, 0
				for i = 1, #v.frames do
					mints = v.frames[i].ts < mints and v.frames[i].ts or mints
					maxts = v.frames[i].ts > maxts and v.frames[i].ts or maxts
				end

				surface.SetDrawColor(0, 0, 0, 200)
				surface.DrawRect(128, 128 + iply * verticalSpacing, 512, 90)
				surface.SetFont("ChatFont")
				surface.SetTextColor(255, 255, 255)
				surface.SetTextPos(140, 140 + iply * verticalSpacing)
				surface.DrawText(k .. " | " .. v.debugState .. " | " .. (v.debugTps or 0) .. " | " .. math.floor((maxts - v.playbackTime) * 1000))
				surface.SetDrawColor(0, 0, 0, 200)
				surface.DrawRect(leftSide, 160 + iply * verticalSpacing, rightSide - leftSide, 20)
				local tileWidth = (rightSide - leftSide) / #v.frames
				for i = 1, #v.frames do
					tsfraction = (v.frames[i].ts - mints) / (maxts - mints)
					surface.SetDrawColor(255 - tsfraction * 255, 0, tsfraction * 255, 255)
					surface.DrawRect(leftSide + tileWidth * (i - 1), 160 + iply * verticalSpacing, 2, 20)
					if i == v.debugPreviousFrame or i == v.debugNextFrame then
						surface.SetDrawColor(0, 255, 0)
						surface.DrawRect(leftSide + tileWidth * (i - 1), 160 + iply * verticalSpacing + (i == v.debugNextFrame and 18 or 0), 2, 2)
						if i == v.debugPreviousFrame then surface.DrawRect(leftSide + tileWidth * (i - 1 + v.debugFraction), 159 + iply * verticalSpacing, 2, 22) end
					end
				end

				surface.SetDrawColor(0, 0, 0, 200)
				surface.DrawRect(leftSide, 185 + iply * verticalSpacing, rightSide - leftSide, 20)
				for i = 1, #v.frames do
					tsfraction = (v.frames[i].ts - mints) / (maxts - mints)
					surface.SetDrawColor(255 - tsfraction * 255, 0, tsfraction * 255, 255)
					surface.DrawRect(leftSide + tsfraction * (rightSide - leftSide - 2), 185 + iply * verticalSpacing, 2, 20)
				end

				surface.SetDrawColor(0, 255, 0, 255)
				surface.DrawRect(leftSide + (v.playbackTime - mints) / (maxts - mints) * (rightSide - leftSide - 2), 185 + iply * verticalSpacing, 2, 20)
				iply = iply + 1
			end

			cam.End2D()
		end)
	end)

	function VRUtilNetworkInit() --called by localplayer when they enter vr
		-- transmit loop
		timer.Create("vrmod_transmit", 1 / convarValues.vrmod_net_tickrate, 0, function()
			if g_VR.threePoints then
				net.Start("vrutil_net_tick", true)
				--write viewHackPos
				net.WriteVector(g_VR.viewModelMuzzle and g_VR.viewModelMuzzle.Pos or Vector(0, 0, 0))
				--write frame
				netWriteFrame(buildClientFrame(true))
				net.SendToServer()
			end
		end)

		net.Start("vrutil_net_join")
		--send some stuff here that doesnt need to be in every frame
		net.WriteBool(GetConVar("vrmod_althead"):GetBool())
		net.WriteBool(GetConVar("vrmod_floatinghands"):GetBool())
		net.SendToServer()
	end

	-- update all lerpedFrames, except for the local player (this function will be hooked to PreRender)
	local function LerpOtherVRPlayers()
		local lerpDelay = convarValues.vrmod_net_delay
		local lerpDelayMax = convarValues.vrmod_net_delaymax
		for k, v in pairs(g_VR.net) do
			local ply = player.GetBySteamID(k)
			if #v.frames < 2 or not ply then --len check discards the localplayer, ply might be invalid for a few frames before exit msg upon disconnect
				continue
			end

			if v.buffering then
				if not (v.playbackTime > v.frames[v.latestFrameIndex].ts - lerpDelay) then
					v.buffering = false
					v.sysTime = SysTime()
					v.debugState = "playing"
				end
			else
				--advance playhead
				v.playbackTime = v.playbackTime + SysTime() - v.sysTime
				v.sysTime = SysTime()
				--check if we reached the end
				if v.playbackTime > v.frames[v.latestFrameIndex].ts then
					v.buffering = true
					v.debugState = "buffering (reached end)"
					v.playbackTime = v.frames[v.latestFrameIndex].ts
				end

				--check if we're too far behind
				if v.frames[v.latestFrameIndex].ts - v.playbackTime > lerpDelayMax then
					v.buffering = true
					v.playbackTime = v.frames[v.latestFrameIndex].ts
					v.debugState = "buffering (catching up)"
				end
			end

			--lerp according to current playhead pos
			for i = 1, #v.frames do
				local nextFrame = i
				local previousFrame = i - 1
				if previousFrame == 0 then previousFrame = #v.frames end
				if v.frames[nextFrame].ts >= v.playbackTime and v.frames[previousFrame].ts <= v.playbackTime then
					local fraction = (v.playbackTime - v.frames[previousFrame].ts) / (v.frames[nextFrame].ts - v.frames[previousFrame].ts)
					--
					v.debugNextFrame = nextFrame
					v.debugPreviousFrame = previousFrame
					v.debugFraction = fraction
					--
					v.lerpedFrame = {}
					for k2, v2 in pairs(v.frames[previousFrame]) do
						if k2 == "characterYaw" then
							v.lerpedFrame[k2] = LerpAngle(fraction, Angle(0, v2, 0), Angle(0, v.frames[nextFrame][k2], 0)).yaw
						elseif isnumber(v2) then
							v.lerpedFrame[k2] = Lerp(fraction, v2, v.frames[nextFrame][k2])
						elseif isvector(v2) then
							v.lerpedFrame[k2] = LerpVector(fraction, v2, v.frames[nextFrame][k2])
						elseif isangle(v2) then
							v.lerpedFrame[k2] = LerpAngle(fraction, v2, v.frames[nextFrame][k2])
						end
					end

					--
					local plyPos, plyAng = ply:GetPos(), Angle()
					if ply:InVehicle() then
						plyAng = ply:GetVehicle():GetAngles()
						local _, forwardAng = LocalToWorld(Vector(), Angle(0, 90, 0), Vector(), plyAng)
						v.lerpedFrame.characterYaw = forwardAng.yaw
					end

					v.lerpedFrame.hmdPos, v.lerpedFrame.hmdAng = LocalToWorld(v.lerpedFrame.hmdPos, v.lerpedFrame.hmdAng, plyPos, plyAng)
					v.lerpedFrame.lefthandPos, v.lerpedFrame.lefthandAng = LocalToWorld(v.lerpedFrame.lefthandPos, v.lerpedFrame.lefthandAng, plyPos, plyAng)
					v.lerpedFrame.righthandPos, v.lerpedFrame.righthandAng = LocalToWorld(v.lerpedFrame.righthandPos, v.lerpedFrame.righthandAng, plyPos, plyAng)
					if v.lerpedFrame.waistPos then
						v.lerpedFrame.waistPos, v.lerpedFrame.waistAng = LocalToWorld(v.lerpedFrame.waistPos, v.lerpedFrame.waistAng, plyPos, plyAng)
						v.lerpedFrame.leftfootPos, v.lerpedFrame.leftfootAng = LocalToWorld(v.lerpedFrame.leftfootPos, v.lerpedFrame.leftfootAng, plyPos, plyAng)
						v.lerpedFrame.rightfootPos, v.lerpedFrame.rightfootAng = LocalToWorld(v.lerpedFrame.rightfootPos, v.lerpedFrame.rightfootAng, plyPos, plyAng)
					end

					--
					break
				end
			end
		end
	end

	function VRUtilNetUpdateLocalPly()
		local tab = g_VR.net[LocalPlayer():SteamID()]
		if g_VR.threePoints and tab then
			tab.lerpedFrame = buildClientFrame()
			return tab.lerpedFrame
		end
	end

	function VRUtilNetworkCleanup() --called by localplayer when they exit vr
		timer.Remove("vrmod_transmit")
		net.Start("vrutil_net_exit")
		net.SendToServer()
	end

	net.Receive("vrutil_net_tick", function(len)
		local ply = net.ReadEntity()
		if not IsValid(ply) then return end
		local tab = g_VR.net[ply:SteamID()]
		if not tab then return end
		tab.debugTickCount = tab.debugTickCount + 1
		local frame = netReadFrame()
		if tab.latestFrameIndex == 0 then
			tab.playbackTime = frame.ts
		elseif frame.ts <= tab.frames[tab.latestFrameIndex].ts then
			return
		end

		local index = tab.latestFrameIndex + 1
		if index > convarValues.vrmod_net_storedframes then index = 1 end
		tab.frames[index] = frame
		tab.latestFrameIndex = index
	end)

	net.Receive("vrutil_net_join", function(len)
		local ply = net.ReadEntity()
		if not IsValid(ply) then --todo fix this properly lol
			return
		end

		g_VR.net[ply:SteamID()] = {
			characterAltHead = net.ReadBool(),
			dontHideBullets = net.ReadBool(),
			frames = {},
			latestFrameIndex = 0,
			buffering = true,
			debugState = "buffering (initial)",
			debugTickCount = 0,
		}

		hook.Add("PreRender", "vrutil_hook_netlerp", LerpOtherVRPlayers)
		hook.Run("VRMod_Start", ply)
	end)

	local swepOriginalFovs = {}
	net.Receive("vrutil_net_exit", function(len)
		local steamid = net.ReadString()
		if game.SinglePlayer() then steamid = LocalPlayer():SteamID() end
		local ply = player.GetBySteamID(steamid)
		g_VR.net[steamid] = nil
		if table.Count(g_VR.net) == 0 then hook.Remove("PreRender", "vrutil_hook_netlerp") end
		if ply == LocalPlayer() then
			for k, v in pairs(swepOriginalFovs) do
				local wep = ply:GetWeapon(k)
				if IsValid(wep) then wep.ViewModelFOV = v end
			end

			swepOriginalFovs = {}
		end

		hook.Run("VRMod_Exit", ply, steamid)
	end)

	net.Receive("vrutil_net_switchweapon", function(len)
		local class = net.ReadString()
		local vm = net.ReadString()
		local isMag = string.StartWith(class, "avrmag_") -- Check if the entity is a magazine
		-- Handle case where no valid weapon or magazine is selected
		if class == "" or vm == "" then
			g_VR.viewModel = nil
			g_VR.openHandAngles = g_VR.defaultOpenHandAngles
			g_VR.closedHandAngles = g_VR.defaultClosedHandAngles
			g_VR.currentvmi = nil
			g_VR.viewModelMuzzle = nil
			-- Ensure world model is hidden
			local weapon = LocalPlayer():GetActiveWeapon()
			if IsValid(weapon) then weapon:SetNoDraw(true) end
			local viewModel = LocalPlayer():GetViewModel()
			if IsValid(viewModel) then viewModel:SetNoDraw(false) end
			return
		end

		if GetConVar("vrmod_useworldmodels"):GetBool() then
			vrmod.SetRightHandOpenFingerAngles(g_VR.zeroHandAngles)
			vrmod.SetRightHandClosedFingerAngles(g_VR.zeroHandAngles)
			timer.Create("vrutil_waitforwm", 0, 0, function()
				if IsValid(LocalPlayer():GetActiveWeapon()) and LocalPlayer():GetActiveWeapon():GetClass() == class then
					timer.Remove("vrutil_waitforwm")
					g_VR.viewModel = LocalPlayer():GetActiveWeapon()
					-- Hide view model to avoid rendering conflicts
					local viewModel = LocalPlayer():GetViewModel()
					if IsValid(viewModel) then viewModel:SetNoDraw(true) end
					-- Ensure magazine world model is visible if applicable
					local weapon = LocalPlayer():GetActiveWeapon()
					if IsValid(weapon) and isMag then weapon:SetNoDraw(false) end
				end
			end)
		else
			-- Explicitly disable world model rendering for both weapons and magazines
			local wep = LocalPlayer():GetActiveWeapon()
			if IsValid(wep) then
				wep:SetNoDraw(true) -- Prevent world model from rendering
			end

			-- Ensure view model is used and visible
			local viewModel = LocalPlayer():GetViewModel()
			if IsValid(viewModel) then
				viewModel:SetNoDraw(false)
				g_VR.viewModel = viewModel
			end

			if wep.ViewModelFOV then
				if not swepOriginalFovs[class] then swepOriginalFovs[class] = wep.ViewModelFOV end
				wep.ViewModelFOV = GetConVar("fov_desired"):GetFloat()
			end

			-- Create offsets for view model if they don't exist
			local vmi = g_VR.viewModelInfo[class] or {}
			local model = isMag and vm or vmi.modelOverride ~= nil and vmi.modelOverride or vm -- Use view model for magazines
			if vmi.offsetPos == nil or vmi.offsetAng == nil then
				vmi.offsetPos, vmi.offsetAng = Vector(0, 0, 0), Angle(0, 0, 0)
				local cm = ClientsideModel(model)
				if IsValid(cm) then
					cm:SetupBones()
					local bone = cm:LookupBone("ValveBiped.Bip01_R_Hand")
					if bone then
						local boneMat = cm:GetBoneMatrix(bone)
						local bonePos, boneAng = boneMat:GetTranslation(), boneMat:GetAngles()
						boneAng:RotateAroundAxis(boneAng:Forward(), 180)
						vmi.offsetPos, vmi.offsetAng = WorldToLocal(Vector(0, 0, 0), Angle(0, 0, 0), bonePos, boneAng)
						vmi.offsetPos = vmi.offsetPos + g_VR.viewModelInfo.autoOffsetAddPos
					end

					cm:Remove()
				end
			end

			-- Create finger poses for magazines or weapons
			vmi.closedHandAngles = vrmod.GetRightHandFingerAnglesFromModel(model)
			vrmod.SetRightHandClosedFingerAngles(vmi.closedHandAngles)
			vrmod.SetRightHandOpenFingerAngles(vmi.closedHandAngles)
			g_VR.viewModelInfo[class] = vmi
			g_VR.currentvmi = vmi
		end
	end)

	hook.Add("CreateMove", "vrutil_hook_joincreatemove", function(cmd)
		hook.Remove("CreateMove", "vrutil_hook_joincreatemove")
		timer.Simple(2, function()
			net.Start("vrutil_net_requestvrplayers")
			net.SendToServer()
		end)

		timer.Simple(2, function()
			if SysTime() < 120 then GetConVar("vrmod_autostart"):SetBool(false) end
			if GetConVar("vrmod_autostart"):GetBool() then
				timer.Create("vrutil_timer_tryautostart", 1, 0, function()
					local pm = LocalPlayer():GetModel()
					if pm ~= nil and pm ~= "models/player.mdl" and pm ~= "" then
						VRUtilClientStart()
						timer.Remove("vrutil_timer_tryautostart")
					end
				end)
			end
		end)
	end)

	net.Receive("vrutil_net_entervehicle", function(len) hook.Call("VRMod_EnterVehicle", nil) end)
	net.Receive("vrutil_net_exitvehicle", function(len) hook.Call("VRMod_ExitVehicle", nil) end)
end

if SERVER then
	util.AddNetworkString("vrutil_net_join")
	util.AddNetworkString("vrutil_net_exit")
	util.AddNetworkString("vrutil_net_switchweapon")
	util.AddNetworkString("vrutil_net_tick")
	util.AddNetworkString("vrutil_net_requestvrplayers")
	util.AddNetworkString("vrutil_net_entervehicle")
	util.AddNetworkString("vrutil_net_exitvehicle")
	vrmod.NetReceiveLimited("vrutil_net_tick", convarValues.vrmod_net_tickrate + 5, 1200, function(len, ply)
		--print("sv received net_tick, len: "..len)
		if g_VR[ply:SteamID()] == nil then return end
		local viewHackPos = net.ReadVector()
		local frame = netReadFrame()
		g_VR[ply:SteamID()].latestFrame = frame
		if not viewHackPos:IsZero() and util.IsInWorld(viewHackPos) then
			ply.viewOffset = viewHackPos - ply:EyePos() + ply.viewOffset
			ply:SetCurrentViewOffset(ply.viewOffset)
			ply:SetViewOffset(Vector(0, 0, ply.viewOffset.z))
		else
			ply:SetCurrentViewOffset(ply.originalViewOffset)
			ply:SetViewOffset(ply.originalViewOffset)
		end

		--relay frame to everyone except sender
		net.Start("vrutil_net_tick", true)
		net.WriteEntity(ply)
		netWriteFrame(frame)
		net.SendOmit(ply)
	end)

	vrmod.NetReceiveLimited("vrutil_net_join", 5, 2, function(len, ply)
		if g_VR[ply:SteamID()] ~= nil then return end
		ply:DrawShadow(false)
		ply.originalViewOffset = ply:GetViewOffset()
		ply.viewOffset = Vector(0, 0, 0)
		--add gt entry
		g_VR[ply:SteamID()] = {
			--store join values so we can re-send joins to players that connect later
			characterAltHead = net.ReadBool(),
			dontHideBullets = net.ReadBool(),
		}

		ply:Give("weapon_vrmod_empty")
		ply:SelectWeapon("weapon_vrmod_empty")
		--relay join message to everyone except players that aren't fully loaded in yet
		local omittedPlayers = {}
		for k, v in ipairs(player.GetAll()) do
			if not v.hasRequestedVRPlayers then omittedPlayers[#omittedPlayers + 1] = v end
		end

		net.Start("vrutil_net_join")
		net.WriteEntity(ply)
		net.WriteBool(g_VR[ply:SteamID()].characterAltHead)
		net.WriteBool(g_VR[ply:SteamID()].dontHideBullets)
		net.SendOmit(omittedPlayers)
		hook.Run("VRMod_Start", ply)
	end)

	local function net_exit(steamid)
		if g_VR[steamid] ~= nil then
			g_VR[steamid] = nil
			local ply = player.GetBySteamID(steamid)
			ply:SetCurrentViewOffset(ply.originalViewOffset)
			ply:SetViewOffset(ply.originalViewOffset)
			-- ply:StripWeapon("weapon_vrmod_empty")
			--relay exit message to everyone
			net.Start("vrutil_net_exit")
			net.WriteString(steamid)
			net.Broadcast()
			hook.Run("VRMod_Exit", ply)
		end
	end

	vrmod.NetReceiveLimited("vrutil_net_exit", 5, 0, function(len, ply) net_exit(ply:SteamID()) end)
	hook.Add("PlayerDisconnected", "vrutil_hook_playerdisconnected", function(ply) net_exit(ply:SteamID()) end)
	vrmod.NetReceiveLimited("vrutil_net_requestvrplayers", 5, 0, function(len, ply)
		ply.hasRequestedVRPlayers = true
		for k, v in pairs(g_VR) do
			if type(k) == "string" and k:match("^STEAM_[0-5]:[01]:%d+$") then
				local vrPly = player.GetBySteamID(k)
				if IsValid(vrPly) then
					net.Start("vrutil_net_join")
					net.WriteEntity(vrPly)
					net.WriteBool(v.characterAltHead)
					net.WriteBool(v.dontHideBullets)
					net.Send(ply)
				else
					print("VRMod: Invalid SteamID \"" .. k .. "\" found in player table")
				end
			end
		end
	end)

	hook.Add("PlayerDeath", "vrutil_hook_playerdeath", function(ply, inflictor, attacker)
		if g_VR[ply:SteamID()] ~= nil then
			net.Start("vrutil_net_exit")
			net.WriteString(ply:SteamID())
			net.Broadcast()
		end
	end)

	hook.Add("PlayerSpawn", "vrutil_hook_playerspawn", function(ply)
		if g_VR[ply:SteamID()] ~= nil then
			ply:Give("weapon_vrmod_empty")
			net.Start("vrutil_net_join")
			net.WriteEntity(ply)
			net.WriteBool(g_VR[ply:SteamID()].characterAltHead)
			net.WriteBool(g_VR[ply:SteamID()].dontHideBullets)
			net.Broadcast()
		end
	end)

	hook.Add("PlayerSwitchWeapon", "vrutil_hook_playerswitchweapon", function(ply, old, new)
		if g_VR[ply:SteamID()] ~= nil then
			net.Start("vrutil_net_switchweapon")
			local class, vm = vrmod.utils.WepInfo(new)
			if class and vm then
				timer.Simple(0, function() vrmod.utils.ComputePhysicsParams(vm) end)
				net.WriteString(class)
				net.WriteString(vm)
			else
				net.WriteString("")
				net.WriteString("")
			end

			net.Send(ply)
			timer.Simple(0, function() end)
		end
	end)

	hook.Add("PlayerEnteredVehicle", "vrutil_hook_playerenteredvehicle", function(ply, veh)
		if g_VR[ply:SteamID()] ~= nil then
			ply:SelectWeapon("weapon_vrmod_empty")
			ply:SetActiveWeapon(ply:GetWeapon("weapon_vrmod_empty"))
			net.Start("vrutil_net_entervehicle")
			net.Send(ply)
			ply:SetAllowWeaponsInVehicle(1)
		end
	end)

	hook.Add("PlayerLeaveVehicle", "vrutil_hook_playerleavevehicle", function(ply, veh)
		if g_VR[ply:SteamID()] ~= nil then
			net.Start("vrutil_net_exitvehicle")
			net.Send(ply)
		end
	end)
end