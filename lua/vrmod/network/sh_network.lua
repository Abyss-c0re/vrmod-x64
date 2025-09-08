g_VR = g_VR or {}
local _, convarValues = vrmod.GetConvars()
vrmod.AddCallbackedConvar("vrmod_net_tickrate", nil, tostring(math.ceil(1 / engine.TickInterval())), FCVAR_REPLICATED, nil, nil, nil, tonumber, nil)
-- HELPERS
local function netReadFrame()
	local frame = {
		--ts = net.ReadFloat(),
		ts = net.ReadDouble(),
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

local function buildClientFrame(relative)
	local lp = LocalPlayer()
	if not IsValid(lp) then return nil end
	-- Determine character yaw with Glide support
	local vehicle = lp:GetNWEntity("GlideVehicle")
	local characterYaw
	if IsValid(vehicle) then
		characterYaw = vehicle:GetAngles().yaw
	elseif lp:InVehicle() then
		local veh = lp:GetVehicle()
		if IsValid(veh) then
			characterYaw = veh:GetAngles().yaw
		else
			characterYaw = g_VR.characterYaw
		end
	else
		characterYaw = g_VR.characterYaw
	end

	local frame = {
		characterYaw = characterYaw,
		hmdPos = g_VR.tracking.hmd.pos,
		hmdAng = g_VR.tracking.hmd.ang,
		lefthandPos = g_VR.tracking.pose_lefthand.pos,
		lefthandAng = g_VR.tracking.pose_lefthand.ang,
		righthandPos = g_VR.tracking.pose_righthand.pos,
		righthandAng = g_VR.tracking.pose_righthand.ang,
	}

	-- Assign fingers using loop
	for i = 1, 5 do
		frame["finger" .. i] = g_VR.input.skeleton_lefthand.fingerCurls[i]
		frame["finger" .. i + 5] = g_VR.input.skeleton_righthand.fingerCurls[i]
	end

	if g_VR.sixPoints then
		frame.waistPos = g_VR.tracking.pose_waist.pos
		frame.waistAng = g_VR.tracking.pose_waist.ang
		frame.leftfootPos = g_VR.tracking.pose_leftfoot.pos
		frame.leftfootAng = g_VR.tracking.pose_leftfoot.ang
		frame.rightfootPos = g_VR.tracking.pose_rightfoot.pos
		frame.rightfootAng = g_VR.tracking.pose_rightfoot.ang
	end

	if relative then return vrmod.utils.ConvertToRelativeFrame(frame) end
	return frame
end

local function netWriteFrame(frame)
	--net.WriteFloat(SysTime())
	net.WriteDouble(SysTime())
	local tmp = frame.characterYaw + math.ceil(math.abs(frame.characterYaw) / 360) * 360 --normalize and convert characterYaw to 0-360
	tmp = tmp - math.floor(tmp / 360) * 360
	net.WriteUInt(tmp * 0.35, 7) --crush from 0-360 to 0-127
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
	local lastSentFrame
	local function SendFrame(frame)
		net.Start("vrutil_net_tick", true)
		net.WriteVector(g_VR.viewModelMuzzle and g_VR.viewModelMuzzle.Pos or Vector(0, 0, 0))
		netWriteFrame(frame)
		net.SendToServer()
		lastSentFrame = vrmod.utils.CopyFrame(frame)
	end

	function VRUtilNetworkInit() --called by localplayer when they enter vr
		-- transmit loop
		timer.Create("vrmod_transmit", 1 / convarValues.vrmod_net_tickrate, 0, function()
			if g_VR.threePoints and g_VR.active then
				local frame = buildClientFrame(true)
				if lastSentFrame and not vrmod.utils.FramesAreEqual(frame, lastSentFrame) then
					SendFrame(frame)
				else
					vrmod.logger.Debug("Skipping identical frame")
					if not lastSentFrame then SendFrame(frame) end
				end
			end
		end)

		net.Start("vrutil_net_join")
		--send some stuff here that doesnt need to be in every frame
		net.WriteBool(GetConVar("vrmod_althead"):GetBool())
		net.WriteBool(GetConVar("vrmod_floatinghands"):GetBool())
		net.SendToServer()
	end

	local function LerpOtherVRPlayers()
		for steamid, data in pairs(g_VR.net) do
			-- Resolve the player entity if possible
			local ply = data.resolvedPlayer
			if not IsValid(ply) then
				ply = player.GetBySteamID(steamid)
				if IsValid(ply) then
					data.resolvedPlayer = ply
					vrmod.logger.Debug("Resolved player entity for " .. steamid)
				end
			end

			-- Require at least one frame to do anything
			if not data.frames or #data.frames < 1 then
				vrmod.logger.Debug("Skipping " .. steamid .. " (no frames yet)")
				continue
			end

			-- Take the latest frame
			local latestFrame = data.frames[data.latestFrameIndex]
			if not latestFrame then
				vrmod.logger.Debug("Skipping " .. steamid .. " (no latest frame)")
				continue
			end

			-- Build a lerped frame by copying valid fields
			local lerpedFrame = {}
			for k, v in pairs(latestFrame) do
				if k == "characterYaw" then
					lerpedFrame[k] = v
				elseif isnumber(v) or isvector(v) or isangle(v) then
					lerpedFrame[k] = v
				end
			end

			-- If we have a valid player entity, transform relative → world
			if IsValid(ply) then
				local plyPos, plyAng = ply:GetPos(), Angle()
				if ply:InVehicle() then
					plyAng = ply:GetVehicle():GetAngles()
					local _, forwardAng = LocalToWorld(Vector(), Angle(0, 90, 0), Vector(), plyAng)
					lerpedFrame.characterYaw = forwardAng.yaw
				end

				for _, part in ipairs({"hmd", "lefthand", "righthand", "waist", "leftfoot", "rightfoot"}) do
					local posKey, angKey = part .. "Pos", part .. "Ang"
					if lerpedFrame[posKey] then lerpedFrame[posKey], lerpedFrame[angKey] = LocalToWorld(lerpedFrame[posKey], lerpedFrame[angKey], plyPos, plyAng) end
				end
			else
				vrmod.logger.Debug("Player entity unresolved for " .. steamid .. " (keeping relative frame)")
			end

			-- First frame for this player: snap immediately
			if not data.lastLerpedFrame then
				data.lerpedFrame = vrmod.utils.CopyFrame(lerpedFrame)
				data.lastLerpedFrame = vrmod.utils.CopyFrame(lerpedFrame)
				vrmod.logger.Debug("Initialized lerped frame for " .. steamid)
				continue
			end

			-- Only update if something changed
			if not vrmod.utils.FramesAreEqual(lerpedFrame, data.lastLerpedFrame) then
				data.lerpedFrame = vrmod.utils.CopyFrame(lerpedFrame)
				data.lastLerpedFrame = vrmod.utils.CopyFrame(lerpedFrame)
				vrmod.logger.Debug("Updated lerped frame for " .. steamid)
			else
				vrmod.logger.Debug("No change in frame for " .. steamid)
			end
		end
	end

	function VRUtilNetUpdateLocalPly(relative)
		local tab = g_VR.net[LocalPlayer():SteamID()]
		if g_VR.threePoints and tab then
			tab.lerpedFrame = buildClientFrame(relative)
			return tab.lerpedFrame
		end
	end

	function VRUtilNetworkCleanup() --called by localplayer when they exit vr
		timer.Remove("vrmod_transmit")
		net.Start("vrutil_net_exit")
		net.SendToServer()
	end

	net.Receive("vrutil_net_tick", function(len)
		local steamid = net.ReadString()
		if steamid == LocalPlayer():SteamID() then return end
		local tab = g_VR.net[steamid]
		if not tab then
			-- got a tick for an unknown steamid: create a minimal stub so future frames are stored
			tab = {
				frames = {},
				latestFrameIndex = 0,
				resolvedPlayer = player.GetBySteamID(steamid)
			}

			g_VR.net[steamid] = tab
		end

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
		local steamid = net.ReadString()
		local charAltHead = net.ReadBool()
		local dontHide = net.ReadBool()
		-- ensure entry exists even if entity isn't valid yet
		g_VR.net[steamid] = g_VR.net[steamid] or {
			characterAltHead = charAltHead,
			dontHideBullets = dontHide,
			frames = {},
			latestFrameIndex = 0,
			resolvedPlayer = nil, -- we'll try to link later
		}

		-- try to resolve the player to an entity immediately
		local ply = player.GetBySteamID(steamid)
		if IsValid(ply) then
			g_VR.net[steamid].resolvedPlayer = ply
			hook.Run("VRMod_Start", ply)
		end

		-- ensure the lerp hook is present
		if not hook.GetTable().PreRender or not hook.GetTable().PreRender.vrutil_hook_netlerp then hook.Add("PreRender", "vrutil_hook_netlerp", LerpOtherVRPlayers) end
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
		vrmod.logger.Debug("received net_tick, len: " .. len)
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
		net.Start("vrutil_net_tick")
		net.WriteString(ply:SteamID())
		netWriteFrame(frame)
		--net.Broadcast()
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
		net.WriteString(ply:SteamID())
		net.WriteBool(g_VR[ply:SteamID()].characterAltHead)
		net.WriteBool(g_VR[ply:SteamID()].dontHideBullets)
		net.SendOmit(omittedPlayers)
		hook.Run("VRMod_Start", ply)
	end)

	local function net_exit(steamid)
		if g_VR[steamid] ~= nil then
			g_VR[steamid] = nil
			local ply = player.GetBySteamID(steamid)
			if ply.originalViewOffset then
				ply:SetCurrentViewOffset(ply.originalViewOffset)
				ply:SetViewOffset(ply.originalViewOffset)
			end

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
					vrmod.logger.Err("Invalid SteamID \"" .. k .. "\" found in player table")
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