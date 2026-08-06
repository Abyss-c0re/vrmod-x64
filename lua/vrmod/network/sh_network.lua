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
	local vehicle = g_VR.vehicle.current
	local characterYaw
	if g_VR.vehicle.inside and IsValid(vehicle) then
		local rawYaw = vehicle:GetAngles().yaw
		rawYaw = (rawYaw + 180) % 360 - 180
		local MAX_YAW = 90
		characterYaw = math.Clamp(rawYaw, -MAX_YAW, MAX_YAW)
	else
		characterYaw = g_VR.characterYaw or 0
	end

	-- Always clone pos/ang off tracking — never share Vector identity into net frames
	-- (L/R glue + playermodel glitch if two fields hold the same userdata).
	local function clonePose(pose)
		if not pose or not pose.pos or not pose.ang then return nil, nil end
		return Vector(pose.pos.x, pose.pos.y, pose.pos.z), Angle(pose.ang.p, pose.ang.y, pose.ang.r)
	end

	local hmd = g_VR.tracking and g_VR.tracking.hmd
	local hmdPos, hmdAng = clonePose(hmd)
	if not hmdPos then return nil end

	local frame = {
		characterYaw = characterYaw,
		hmdPos = hmdPos,
		hmdAng = hmdAng,
	}

	local netFrame = g_VR.net and g_VR.net[lp:SteamID()] and g_VR.net[lp:SteamID()].lerpedFrame
	-- Handle hands: use netFrame if gripping, otherwise tracking clones
	if g_VR.wheelGrippedLeft and netFrame and netFrame.lefthandPos then
		frame.lefthandPos = Vector(netFrame.lefthandPos.x, netFrame.lefthandPos.y, netFrame.lefthandPos.z)
		frame.lefthandAng = netFrame.lefthandAng and Angle(netFrame.lefthandAng.p, netFrame.lefthandAng.y, netFrame.lefthandAng.r) or Angle()
	else
		local p, a = clonePose(g_VR.tracking.pose_lefthand)
		if p then frame.lefthandPos, frame.lefthandAng = p, a end
	end

	if g_VR.wheelGrippedRight and netFrame and netFrame.righthandPos then
		frame.righthandPos = Vector(netFrame.righthandPos.x, netFrame.righthandPos.y, netFrame.righthandPos.z)
		frame.righthandAng = netFrame.righthandAng and Angle(netFrame.righthandAng.p, netFrame.righthandAng.y, netFrame.righthandAng.r) or Angle()
	else
		local p, a = clonePose(g_VR.tracking.pose_righthand)
		if p then frame.righthandPos, frame.righthandAng = p, a end
	end

	-- Assign fingers using loop
	local inL = g_VR.input and g_VR.input.skeleton_lefthand and g_VR.input.skeleton_lefthand.fingerCurls
	local inR = g_VR.input and g_VR.input.skeleton_righthand and g_VR.input.skeleton_righthand.fingerCurls
	for i = 1, 5 do
		frame["finger" .. i] = inL and inL[i] or 0
		frame["finger" .. (i + 5)] = inR and inR[i] or 0
	end

	if g_VR.sixPoints then
		local wp, wa = clonePose(g_VR.tracking.pose_waist)
		local lfp, lfa = clonePose(g_VR.tracking.pose_leftfoot)
		local rfp, rfa = clonePose(g_VR.tracking.pose_rightfoot)
		if wp then frame.waistPos, frame.waistAng = wp, wa end
		if lfp then frame.leftfootPos, frame.leftfootAng = lfp, lfa end
		if rfp then frame.rightfootPos, frame.rightfootAng = rfp, rfa end
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
		net.WriteAngle(g_VR.viewModelMuzzle and g_VR.viewModelMuzzle.Ang or Angle(0, 0, 0))
		netWriteFrame(frame)
		net.SendToServer()
		lastSentFrame = vrmod.utils.CopyFrame(frame)
	end

	-- Desktop window focus → multiplayer presence (Cube: no black local wall; others see a chip).
	local lastDesktopFocused = nil
	local function SendDesktopFocus(focused)
		focused = focused and true or false
		if lastDesktopFocused == focused then return end
		lastDesktopFocused = focused
		net.Start("vrmod_net_desktop_focus", true)
		net.WriteBool(focused)
		net.SendToServer()
		if g_VR then g_VR.desktopFocused = focused end
	end

	local function PollDesktopFocus()
		if not g_VR or not g_VR.active then return end
		-- system.HasFocus: false when alt-tabbed / compositor focus elsewhere
		local focused = true
		if system and system.HasFocus then
			focused = system.HasFocus() and true or false
		end
		SendDesktopFocus(focused)
	end

	function VRUtilNetworkInit() --called by localplayer when they enter vr
		lastDesktopFocused = nil
		-- Menu-first: no LocalPlayer / no game server yet — skip net, keep local XR only
		local ply = LocalPlayer()
		local inGame = IsValid(ply)
		if isfunction(IsInGame) then
			inGame = inGame and IsInGame()
		end

		-- transmit loop (only useful when connected)
		timer.Create("vrmod_transmit", 1 / convarValues.vrmod_net_tickrate, 0, function()
			if not (g_VR.threePoints and g_VR.active) then return end
			if not IsValid(LocalPlayer()) then return end
			local frame = buildClientFrame(true)
			if lastSentFrame and not vrmod.utils.FramesAreEqual(frame, lastSentFrame) then
				SendFrame(frame)
			else
				vrmod.logger.Debug("Skipping identical frame")
				if not lastSentFrame then SendFrame(frame) end
			end
			PollDesktopFocus()
		end)
		-- Also poll focus on a slow timer (tick may skip identical pose frames)
		timer.Create("vrmod_desktop_focus", 0.35, 0, PollDesktopFocus)

		if inGame then
			local okJoin = pcall(function()
				net.Start("vrutil_net_join", true)
				net.WriteBool(GetConVar("vrmod_althead"):GetBool())
				net.WriteBool(GetConVar("vrmod_floatinghands"):GetBool())
				net.SendToServer()
			end)
			if not okJoin and vrmod.logger then
				vrmod.logger.Debug("vrutil_net_join skipped (menu-only or no net)")
			end
		elseif vrmod.logger then
			vrmod.logger.Info("Menu-first VR: local session only (no net join yet)")
		end
		-- Initial presence (usually focused at start)
		timer.Simple(0.2, PollDesktopFocus)
	end

	local function LerpOtherVRPlayers()
		local lp = LocalPlayer()
		for steamid, v in pairs(g_VR.net) do
			local ply = player.GetBySteamID(steamid)
			-- skip invalid or local player
			if not IsValid(ply) or ply == lp then continue end
			-- skip if no frame available
			if not v.lastFrame then
				vrmod.logger.Debug("Skipping player " .. tostring(steamid) .. " (no frame)")
				continue
			end

			local latestFrame = v.lastFrame
			local lerpedFrame = {}
			-- shallow copy numeric/vector/angle fields
			for k2, v2 in pairs(latestFrame) do
				if k2 == "characterYaw" then
					lerpedFrame[k2] = v2
				elseif isnumber(v2) or isvector(v2) or isangle(v2) then
					lerpedFrame[k2] = v2
				end
			end

			-- transform to world space
			local plyPos, plyAng = ply:GetPos(), Angle()
			if ply:InVehicle() then
				plyAng = ply:GetVehicle():GetAngles()
				local _, forwardAng = LocalToWorld(Vector(), Angle(0, 90, 0), Vector(), plyAng)
				lerpedFrame.characterYaw = forwardAng.yaw
			end

			for _, part in ipairs({"hmd", "lefthand", "righthand", "waist", "leftfoot", "rightfoot"}) do
				if lerpedFrame[part .. "Pos"] then lerpedFrame[part .. "Pos"], lerpedFrame[part .. "Ang"] = LocalToWorld(lerpedFrame[part .. "Pos"], lerpedFrame[part .. "Ang"], plyPos, plyAng) end
			end

			-- assign the lerped frame directly
			v.lerpedFrame = lerpedFrame
		end
	end

	-- Update self
	function VRUtilNetUpdateLocalPly(relative)
		local tab = g_VR.net[LocalPlayer():SteamID()]
		if g_VR.threePoints and tab then
			tab.lerpedFrame = buildClientFrame(relative)
			return tab.lerpedFrame
		end
	end

	-- Cleanup on exit
	function VRUtilNetworkCleanup()
		timer.Remove("vrmod_transmit")
		timer.Remove("vrmod_desktop_focus")
		lastDesktopFocused = nil
		if g_VR then g_VR.desktopFocused = nil end
		-- Menu-first may never have joined a server
		if IsValid(LocalPlayer()) then
			pcall(function()
				net.Start("vrutil_net_exit")
				net.SendToServer()
			end)
		end
	end

	-- Remote players: desktop unfocused chip state
	net.Receive("vrmod_net_desktop_focus", function()
		local ply = net.ReadEntity()
		local focused = net.ReadBool()
		if not IsValid(ply) or ply == LocalPlayer() then return end
		local tab = g_VR.net and g_VR.net[ply:SteamID()]
		if not tab then return end
		tab.desktopFocused = focused
		tab.desktopUnfocused = not focused
	end)

	-- Receive remote tick frames
	net.Receive("vrutil_net_tick", function(len)
		local ply = net.ReadEntity()
		if not IsValid(ply) or ply == LocalPlayer() then return end
		local steamid = ply:SteamID()
		local tab = g_VR.net[steamid]
		if not tab then return end
		local frame = netReadFrame()
		-- first frame
		if not tab.lastFrame then
			tab.lastFrame = frame
			tab.playbackTime = frame.ts
			return
		end

		-- skip if same as last frame
		if vrmod.utils.FramesAreEqual(frame, tab.lastFrame) then return end
		-- accept new frame
		tab.lastFrame = frame
		tab.playbackTime = frame.ts
	end)

	-- When another player joins
	net.Receive("vrutil_net_join", function(len)
		local ply = net.ReadEntity()
		if not IsValid(ply) then return end
		g_VR.net[ply:SteamID()] = {
			characterAltHead = net.ReadBool(),
			dontHideBullets = net.ReadBool(),
			lastFrame = nil,
			playbackTime = 0,
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
		-- Handle invalid weapon/magazine
		if class == "" or vm == "" then
			-- Race: server sometimes samples before viewmodel path is ready.
			-- Do not wipe a good bind if we still hold a real weapon.
			local weapon = LocalPlayer():GetActiveWeapon()
			if IsValid(weapon) and vrmod.utils and vrmod.utils.IsValidWep and vrmod.utils.IsValidWep(weapon) then
				local viewModel = LocalPlayer():GetViewModel()
				if IsValid(viewModel) then
					viewModel:SetNoDraw(false)
					g_VR.viewModel = viewModel
				end
				if IsValid(weapon) then weapon:SetNoDraw(true) end
				return
			end
			g_VR.viewModel = nil
			g_VR.openHandAngles = g_VR.defaultOpenHandAngles
			g_VR.closedHandAngles = g_VR.defaultClosedHandAngles
			g_VR.currentvmi = nil
			g_VR.viewModelMuzzle = nil
			if IsValid(weapon) then weapon:SetNoDraw(true) end
			local viewModel = LocalPlayer():GetViewModel()
			if IsValid(viewModel) then viewModel:SetNoDraw(false) end
			-- Remove leftover world model VM
			if IsValid(g_VR.worldModelVM) then
				g_VR.worldModelVM:Remove()
				g_VR.worldModelVM = nil
			end
			return
		end

		local wep = LocalPlayer():GetActiveWeapon()
		local viewModel = LocalPlayer():GetViewModel()
		-- Default hide weapon world model
		if IsValid(wep) then wep:SetNoDraw(true) end
		if IsValid(viewModel) then
			viewModel:SetNoDraw(false)
			g_VR.viewModel = viewModel
		end

		if wep and wep.ViewModelFOV then
			if not swepOriginalFovs[class] then swepOriginalFovs[class] = wep.ViewModelFOV end
			wep.ViewModelFOV = GetConVar("fov_desired"):GetFloat()
		end

		-- Load/create VMI
		local vmi = g_VR.viewModelInfo[class] or {}
		local model = isMag and vm or vmi.modelOverride or vm
		-- Initialize offsets
		if not vmi.offsetPos or not vmi.offsetAng then
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
					vmi.offsetPos = vmi.offsetPos + (g_VR.viewModelInfo.autoOffsetAddPos or Vector(0, 0, 0))
				end

				cm:Remove()
			end
		end

		-- Finger poses
		vmi.closedHandAngles = vrmod.GetRightHandFingerAnglesFromModel(model)
		vrmod.SetRightHandClosedFingerAngles(vmi.closedHandAngles)
		vrmod.SetRightHandOpenFingerAngles(vmi.closedHandAngles)
		-- Handle world model per VMI
		if vmi.useWorldModel then
			-- Remove previous world model if exists
			if IsValid(g_VR.worldModelVM) then g_VR.worldModelVM:Remove() end
			-- Create new world model VM
			vrmod.utils.CreateWorldModelVM(class, vmi)
			-- Zero out hand animations
			vrmod.SetRightHandOpenFingerAngles(g_VR.zeroHandAngles)
			vrmod.SetRightHandClosedFingerAngles(g_VR.zeroHandAngles)
			-- Hide real weapon & viewmodel
			if IsValid(wep) then wep:SetNoDraw(true) end
			if IsValid(viewModel) then viewModel:SetNoDraw(true) end
		else
			-- Normal viewmodel usage
			if IsValid(wep) then wep:SetNoDraw(true) end
			if IsValid(viewModel) then viewModel:SetNoDraw(false) end
			-- Remove leftover world model
			if IsValid(g_VR.worldModelVM) then
				g_VR.worldModelVM:Remove()
				g_VR.worldModelVM = nil
			end
		end

		g_VR.viewModelInfo[class] = vmi
		g_VR.currentvmi = vmi
	end)

	hook.Add("CreateMove", "vrutil_hook_joincreatemove", function(cmd)
		hook.Remove("CreateMove", "vrutil_hook_joincreatemove")
		timer.Simple(2, function()
			net.Start("vrutil_net_requestvrplayers", true)
			net.SendToServer()
		end)

		timer.Simple(0.5, function()
			-- Keep autostart for Cube wrapper / hub / OpenXR (never strip in first 120s).
			local hub = GetConVar("vrmod_hub")
			local menuVR = GetConVar("vrmod_menu_vr")
			local prefer = GetConVar("vrmod_prefer_backend")
			local auto = GetConVar("vrmod_autostart")
			local hubMode = hub and hub:GetBool()
			local menuMode = menuVR and menuVR:GetBool()
			local forceXR = prefer and string.lower(prefer:GetString() or "") == "openxr"
			local launch = vrmod.IsOpenXRLaunchSession and vrmod.IsOpenXRLaunchSession()
			-- Native Cube wrapper: hub + openxr + marker = start NOW (no player-model wait)
			local cubeWrapper = launch or hubMode or forceXR or menuMode
			if SysTime() < 120 and not cubeWrapper then
				if auto then auto:SetBool(false) end
			end
			if not (auto and auto:GetBool()) then return end
			timer.Create("vrutil_timer_tryautostart", 0.5, 0, function()
				if g_VR and g_VR.active then
					timer.Remove("vrutil_timer_tryautostart")
					return
				end
				-- Cube / OpenXR: use take_xr handshake (do not call VRUtilClientStart while Cube holds XR)
				if cubeWrapper or hubMode or menuMode or launch then
					if vrmod.OpenXR_ForceStartWithHandoff then
						pcall(vrmod.OpenXR_ForceStartWithHandoff, "createmove_autostart")
						-- ForceStartWithHandoff owns its own retry timer
						timer.Remove("vrutil_timer_tryautostart")
					elseif isfunction(VRUtilClientStart) then
						pcall(VRUtilClientStart)
					end
					if g_VR and g_VR.active then
						timer.Remove("vrutil_timer_tryautostart")
					end
					return
				end
				local ply = LocalPlayer()
				if not IsValid(ply) then return end
				local pm = ply:GetModel()
				if pm ~= nil and pm ~= "models/player.mdl" and pm ~= "" then
					if isfunction(VRUtilClientStart) then pcall(VRUtilClientStart) end
					timer.Remove("vrutil_timer_tryautostart")
				end
			end)
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
	util.AddNetworkString("vrmod_net_desktop_focus")
	-- Presence: desktop window focus (rare; on-change only)
	vrmod.NetReceiveLimited("vrmod_net_desktop_focus", 8, 1, function(len, ply)
		if not IsValid(ply) then return end
		local sid = ply:SteamID()
		if g_VR[sid] == nil then return end
		local focused = net.ReadBool()
		g_VR[sid].desktopFocused = focused
		net.Start("vrmod_net_desktop_focus", true)
		net.WriteEntity(ply)
		net.WriteBool(focused)
		net.SendOmit(ply)
	end)
	vrmod.NetReceiveLimited("vrutil_net_tick", convarValues.vrmod_net_tickrate + 5, 1200, function(len, ply)
		vrmod.logger.Debug("received net_tick, len: " .. len)
		if g_VR[ply:SteamID()] == nil then return end
		local viewHackPos = net.ReadVector()
		local viewHackAng = net.ReadAngle()
		-- Store muzzle/VR viewmodel info
		g_VR[ply:SteamID()].muzzlePos = viewHackPos
		g_VR[ply:SteamID()].muzzleAng = viewHackAng
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
		--net.Broadcast()
		net.SendOmit(ply)
	end)

	vrmod.NetReceiveLimited("vrutil_net_join", 5, 2, function(len, ply)
		local sid = ply:SteamID()
		local altHead = net.ReadBool()
		local dontHide = net.ReadBool()
		-- Restart path: exit→start can race; allow re-join to refresh flags + re-fire Start
		-- (old code early-returned and skipped VRMod_Start → settings/hooks not re-applied).
		local rejoin = g_VR[sid] ~= nil
		if not rejoin then
			ply:DrawShadow(false)
			ply.originalViewOffset = ply:GetViewOffset()
			ply.viewOffset = Vector(0, 0, 0)
			ply:Give("weapon_vrmod_empty")
			ply:SelectWeapon("weapon_vrmod_empty")
		end
		g_VR[sid] = {
			characterAltHead = altHead,
			dontHideBullets = dontHide,
		}

		--relay join message to everyone except players that aren't fully loaded in yet
		local omittedPlayers = {}
		for k, v in ipairs(player.GetAll()) do
			if not v.hasRequestedVRPlayers then omittedPlayers[#omittedPlayers + 1] = v end
		end

		net.Start("vrutil_net_join")
		net.WriteEntity(ply)
		net.WriteBool(altHead)
		net.WriteBool(dontHide)
		net.SendOmit(omittedPlayers)
		hook.Run("VRMod_Start", ply)
		if rejoin and vrmod.logger then
			vrmod.logger.Info("VR re-join (restart) for " .. tostring(sid))
		end
	end)

	local function net_exit(steamid, ply)
		if g_VR[steamid] == nil then return end
		g_VR[steamid] = nil

		-- Prefer the player argument (disconnect hook); fall back to SteamID lookup
		if not IsValid(ply) then
			ply = player.GetBySteamID(steamid)
		end

		if IsValid(ply) then
			if ply.originalViewOffset then
				ply:SetCurrentViewOffset(ply.originalViewOffset)
				ply:SetViewOffset(ply.originalViewOffset)
			end
			hook.Run("VRMod_Exit", ply)
		end

		net.Start("vrutil_net_exit")
		net.WriteString(steamid)
		net.Broadcast()
	end

	vrmod.NetReceiveLimited("vrutil_net_exit", 5, 0, function(len, ply)
		if not IsValid(ply) then return end
		net_exit(ply:SteamID(), ply)
	end)
	hook.Add("PlayerDisconnected", "vrutil_hook_playerdisconnected", function(ply)
		if not IsValid(ply) then return end
		net_exit(ply:SteamID(), ply)
	end)
	vrmod.NetReceiveLimited("vrutil_net_requestvrplayers", 5, 0, function(len, ply)
		ply.hasRequestedVRPlayers = true
		for k, v in pairs(g_VR) do
			if type(k) == "string" and k:match("^STEAM_[0-5]:[01]:%d+$") then
				local vrPly = player.GetBySteamID(k)
				if IsValid(vrPly) then
					net.Start("vrutil_net_join", true)
					net.WriteEntity(vrPly)
					net.WriteBool(v.characterAltHead)
					net.WriteBool(v.dontHideBullets)
					net.Send(ply)
					-- Late joiners also get current desktop-focus presence
					if v.desktopFocused ~= nil then
						net.Start("vrmod_net_desktop_focus", true)
						net.WriteEntity(vrPly)
						net.WriteBool(v.desktopFocused and true or false)
						net.Send(ply)
					end
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
			net.Start("vrutil_net_join", true)
			net.WriteEntity(ply)
			net.WriteBool(g_VR[ply:SteamID()].characterAltHead)
			net.WriteBool(g_VR[ply:SteamID()].dontHideBullets)
			net.Broadcast()
		end
	end)

	hook.Add("PlayerSwitchWeapon", "vrutil_hook_playerswitchweapon", function(ply, old, new)
		if g_VR[ply:SteamID()] == nil then return end
		-- Next tick: GetWeaponViewModel is often empty on the switch frame.
		timer.Simple(0, function()
			if not IsValid(ply) or g_VR[ply:SteamID()] == nil then return end
			local wep = IsValid(new) and new or ply:GetActiveWeapon()
			net.Start("vrutil_net_switchweapon", true)
			local class, vm = vrmod.utils.WepInfo(wep)
			if class and vm then
				if vrmod.utils.ComputePhysicsParams then
					pcall(vrmod.utils.ComputePhysicsParams, vm)
				end
				net.WriteString(class)
				net.WriteString(vm)
			else
				net.WriteString("")
				net.WriteString("")
			end
			net.Send(ply)
		end)
	end)

	hook.Add("PlayerEnteredVehicle", "vrutil_hook_playerenteredvehicle", function(ply, veh)
		if g_VR[ply:SteamID()] ~= nil then
			net.Start("vrutil_net_entervehicle", true)
			net.Send(ply)
			ply:SetAllowWeaponsInVehicle(1)
			vrmod.SetVRHandsNoCollide(ply, true)
		end
	end)

	hook.Add("PlayerLeaveVehicle", "vrutil_hook_playerleavevehicle", function(ply, veh)
		if g_VR[ply:SteamID()] ~= nil then
			net.Start("vrutil_net_exitvehicle", true)
			net.Send(ply)
			timer.Simple(1, function() if IsValid(ply) and vrmod.IsPlayerInVR(ply) and not ply:InVehicle() then vrmod.SetVRHandsNoCollide(ply, false) end end)
		end
	end)
end