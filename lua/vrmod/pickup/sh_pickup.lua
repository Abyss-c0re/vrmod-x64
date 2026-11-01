g_VR = g_VR or {}
vrmod = vrmod or {}
scripted_ents.Register({
	Type = "anim",
	Base = "vrmod_pickup"
}, "vrmod_pickup")

vrmod.AddCallbackedConvar("vrmod_pickup_limit", nil, 1, FCVAR_REPLICATED + FCVAR_NOTIFY + FCVAR_ARCHIVE, "", 0, 3, tonumber)
vrmod.AddCallbackedConvar("vrmod_pickup_range", nil, 3.5, FCVAR_REPLICATED + FCVAR_ARCHIVE, "", 0.0, 999.0, tonumber)
vrmod.AddCallbackedConvar("vrmod_pickup_weight", nil, 150, FCVAR_REPLICATED + FCVAR_ARCHIVE, "", 0, 10000, tonumber)
vrmod.AddCallbackedConvar("vrmod_pickup_npcs", nil, 1, FCVAR_REPLICATED + FCVAR_NOTIFY + FCVAR_ARCHIVE, "", 0, 3, tonumber)
vrmod.AddCallbackedConvar("vrmod_pickup_limit", nil, "1", FCVAR_REPLICATED + FCVAR_NOTIFY + FCVAR_ARCHIVE, "", 0, 3, tonumber)
vrmod.AddCallbackedConvar("vrmod_pickup_no_phys", nil, 0, FCVAR_REPLICATED + FCVAR_NOTIFY + FCVAR_ARCHIVE, "", 0, 3, tonumber)
if CLIENT then
	if g_VR then
		g_VR.cooldownLeft = false
		g_VR.cooldownRight = false
	end

	CreateClientConVar("vrmod_pickup_halos", "1", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
	vrmod.AddCallbackedConvar("vrmod_pickup_eye", nil, "0", FCVAR_ARCHIVE, "Grab the prop you look at when either grip is pressed", 0, 1, tobool)
	vrmod.AddCallbackedConvar("vrmod_pickup_eye_range", nil, "12", FCVAR_ARCHIVE, "Eye pickup range, same scale as vrmod_pickup_range", 0, 32, function(v)
		if vrmod.utils.LookTarget_ClampRange then return vrmod.utils.LookTarget_ClampRange(v) end
		return tonumber(v) or 12
	end)
	local pickupTargetEntLeft = nil
	local pickupTargetEntRight = nil
	local haloTargetsLeft = {}
	local haloTargetsRight = {}
	-- G44: per-hand drop cooldown after grab_end (pure GrabEndLaw_*).
	-- Prevents re-grab storms; never thrash climb grip path.
	hook.Add("VRMod_Drop", "vrmod_drop_cooldown", function(ply, ent)
		local U = vrmod.utils
		local ignored = IsValid(ent) and U and U.IsIgnoredProp and U.IsIgnoredProp(ent)
		if not IsValid(ent) or ignored then return end
		local startCd = true
		if U and U.GrabEndLaw_ShouldStartCooldown then
			startCd = U.GrabEndLaw_ShouldStartCooldown({
				ent_valid = true,
				ignored_prop = false,
			})
		end
		if not startCd then return end
		local cd = (U and U.GrabEndLaw_CooldownSeconds and U.GrabEndLaw_CooldownSeconds()) or 0.1
		for _, hand in ipairs({"Left", "Right"}) do
			if g_VR then
				local key = hand == "Left" and "cooldownLeft" or "cooldownRight"
				g_VR[key] = true
				timer.Simple(cd, function() if g_VR then g_VR[key] = false end end)
			end
		end
		if U and U.GrabEndLaw_Decide then
			local d = U.GrabEndLaw_Decide({
				hand = "right",
				cooldown_active = true,
				ent_valid = true,
				primary_hand = (vrmod.GetPrimaryHand and vrmod.GetPrimaryHand()) or "right",
			})
			g_VR = g_VR or {}
			g_VR._grabEndLaw = d
			g_VR._grabEndLawLabel = U.GrabEndLaw_StatusLabel and U.GrabEndLaw_StatusLabel(d) or nil
			g_VR._grabEndLawHmdExpect = U.GrabEndLaw_HmdExpect and U.GrabEndLaw_HmdExpect(d) or nil
		end
	end)

	local function pointDist(fromPos, ent, fallbackPos)
		if not fromPos or not vrmod.utils.LookTarget_Distance then return nil end
		local p = fallbackPos
		if IsValid(ent) and ent.NearestPoint then
			local ok, np = pcall(ent.NearestPoint, ent, fromPos)
			if ok and np then p = np end
		elseif IsValid(ent) and ent.GetPos then
			local ok, gp = pcall(ent.GetPos, ent)
			if ok and gp then p = gp end
		end
		if not p then return nil end
		return vrmod.utils.LookTarget_Distance(
			{ x = fromPos.x, y = fromPos.y, z = fromPos.z },
			{ x = p.x, y = p.y, z = p.z }
		)
	end

	local function eyePickupEnabled()
		local cv = GetConVar("vrmod_pickup_eye")
		if not cv or not cv:GetBool() then return false end
		if vrmod.EyeTrackingEnabled and not vrmod.EyeTrackingEnabled() then return false end
		if vrmod.EyeTrackingAllowed and not vrmod.EyeTrackingAllowed() then return false end
		return vrmod.utils.LookTarget_Query ~= nil and vrmod.utils.LookTarget_ChoosePickup ~= nil
	end

	-- Same reach rule as the hand, with the eye slider. Important items use boost 5
	-- for the trace; the hit is then checked with that entity's own boost.
	local function findEyeTarget(ply)
		local rangeCv = GetConVar("vrmod_pickup_eye_range")
		local range = vrmod.utils.LookTarget_ClampRange(rangeCv and rangeCv:GetFloat() or nil)
		local reach = vrmod.utils.LookTarget_MaxDistance(range, vrmod.utils.LookTarget_Boost(true, false))
		local ent, pos, reason = vrmod.utils.LookTarget_Query(ply, reach)
		-- No eye sample: look along the HMD so a headset without gaze still selects.
		if reason == "no_gaze" and vrmod.utils.LookTarget_QueryPose then
			local hmd = g_VR.tracking and g_VR.tracking.hmd
			if hmd and hmd.pos and hmd.ang then
				ent, pos = vrmod.utils.LookTarget_QueryPose(ply, hmd.pos, hmd.ang, reach)
			end
		end
		if not IsValid(ent) or not pos then return nil, nil end
		local gazePos = vrmod.GetEyeGaze and select(1, vrmod.GetEyeGaze(ply))
		local dist = pointDist(gazePos, nil, pos)
		local important = false
		if vrmod.utils.IsImportantPickup then
			local okImp, resImp = pcall(vrmod.utils.IsImportantPickup, ent)
			important = okImp and resImp and true or false
		end
		local npc = false
		if ent.IsNPC then
			local okNpc, resNpc = pcall(ent.IsNPC, ent)
			npc = okNpc and resNpc and true or false
		end
		if not vrmod.utils.LookTarget_Within(dist, range, vrmod.utils.LookTarget_Boost(important, npc)) then
			return nil, nil
		end
		return ent, pos
	end

	local function targetForHand(ply, bLeft, handPos, handEnt, eyeEnt, eyePos, hmdPos)
		if not IsValid(eyeEnt) or not vrmod.utils.LookTarget_ChoosePickup then return handEnt end
		local useEye = eyeEnt
		local _, cv = vrmod.GetConvars()
		local aw = ply.GetActiveWeapon and ply:GetActiveWeapon() or nil
		local isWep = vrmod.utils.IsWeaponEntity and vrmod.utils.IsWeaponEntity(useEye)
		local same = IsValid(aw) and useEye.GetClass and aw.GetClass and useEye:GetClass() == aw:GetClass()
		local holding = vrmod.utils.IsValidWep and vrmod.utils.IsValidWep(aw)
		local allowWep = true
		if vrmod.utils.LookTarget_AllowHeldWeapon then
			allowWep = vrmod.utils.LookTarget_AllowHeldWeapon(isWep, same, bLeft, holding)
		end
		local okTarget = vrmod.utils.IsValidPickupTarget(useEye, ply, bLeft)
		local okCan = vrmod.utils.CanPickupEntity(useEye, ply, cv or {})
		if not okTarget or not okCan or not allowWep then useEye = nil end
		local choice = vrmod.utils.LookTarget_ChoosePickup({
			eye_enabled = useEye ~= nil,
			hand_ent = IsValid(handEnt) and handEnt or nil,
			hand_dist = pointDist(handPos, handEnt, nil),
			eye_ent = useEye,
			hand_to_eye = pointDist(handPos, useEye, eyePos),
			hmd_to_eye = pointDist(hmdPos, useEye, eyePos),
		})
		if choice.source == "none" then return nil end
		return choice.ent
	end

	hook.Add("Think", "vrmod_find_pickup_target", function()
		-- Sphere+trace both hands every Think hitches prop-dense maps. 30 Hz is enough.
		local fn = FrameNumber and FrameNumber() or 0
		if fn % 2 == 1 then return end
		local ply = LocalPlayer()
		if not IsValid(ply) or not g_VR or not vrmod.IsPlayerInVR(ply) or not ply:Alive() then return end
		local pickupRange = GetConVar("vrmod_pickup_range"):GetFloat()
		local heldLeft = g_VR.heldEntityLeft
		local heldRight = g_VR.heldEntityRight
		local useEye = eyePickupEnabled()
		local eyeEnt, eyePos = nil, nil
		if useEye then eyeEnt, eyePos = findEyeTarget(ply) end
		local hmdPos = g_VR.tracking and g_VR.tracking.hmd and g_VR.tracking.hmd.pos
		local rightHand = g_VR.tracking and g_VR.tracking.pose_righthand
		-- Right grip still refuses world props while a weapon is out.
		if rightHand and not heldRight and not vrmod.utils.IsValidWep(ply:GetActiveWeapon()) then
			local handEnt = vrmod.utils.FindPickupTarget(ply, false, rightHand.pos, rightHand.ang, pickupRange)
			if useEye then
				pickupTargetEntRight = targetForHand(ply, false, rightHand.pos, handEnt, eyeEnt, eyePos, hmdPos)
			else
				pickupTargetEntRight = handEnt
			end
		else
			pickupTargetEntRight = nil
		end

		local leftHand = g_VR.tracking and g_VR.tracking.pose_lefthand
		if leftHand and not heldLeft then
			local handEnt = vrmod.utils.FindPickupTarget(ply, true, leftHand.pos, leftHand.ang, pickupRange)
			if useEye then
				pickupTargetEntLeft = targetForHand(ply, true, leftHand.pos, handEnt, eyeEnt, eyePos, hmdPos)
			else
				pickupTargetEntLeft = handEnt
			end
		else
			pickupTargetEntLeft = nil
		end
		-- Publish for vehicle wheel-grip vs mag-grab arbitration (cl_input)
		g_VR.pickupTargetLeft = pickupTargetEntLeft
		g_VR.pickupTargetRight = pickupTargetEntRight
	end)

	hook.Add("PostDrawOpaqueRenderables", "vrmod_draw_pickup_halo", function(depth, sky)
		if depth or sky then return end
		if not g_VR or not g_VR.active then return end
		if not GetConVar("vrmod_pickup_halos"):GetBool() then return end
		-- Only during a real stereo eye (nested RT captures have stereoEye nil)
		if g_VR.stereoEye ~= "left" and g_VR.stereoEye ~= "right" then return end

		table.Empty(haloTargetsLeft)
		table.Empty(haloTargetsRight)
		local ply = LocalPlayer()
		if not IsValid(ply) then return end
		local heldLeft, heldRight = g_VR.heldEntityLeft, g_VR.heldEntityRight
		-- Clear stale held refs (entity removed / dropped without client nil)
		if heldLeft ~= nil and not IsValid(heldLeft) then
			g_VR.heldEntityLeft = nil
			heldLeft = nil
		end
		if heldRight ~= nil and not IsValid(heldRight) then
			g_VR.heldEntityRight = nil
			heldRight = nil
		end
		local holdingRagdoll = (IsValid(heldLeft) and heldLeft:GetNWBool("is_npc_ragdoll", false))
			or (IsValid(heldRight) and heldRight:GetNWBool("is_npc_ragdoll", false))
		local function ShouldAddHalo(ent)
			if not IsValid(ent) or ent == heldLeft or ent == heldRight or holdingRagdoll then return false end
			-- Check server flag for pickup validity, fallback to IsValidPickupTarget if flag missing
			-- GetNWBool cannot report "unset" (nil default becomes false), so a
			-- prop the server has not scanned yet drew no halo. The grip
			-- target was already accepted by IsValidPickupTarget.
			return vrmod.utils.IsValidPickupTarget(ent, ply, false)
		end

		if ShouldAddHalo(pickupTargetEntLeft) then haloTargetsLeft[#haloTargetsLeft + 1] = pickupTargetEntLeft end
		if ShouldAddHalo(pickupTargetEntRight) then haloTargetsRight[#haloTargetsRight + 1] = pickupTargetEntRight end
		if #haloTargetsLeft > 0 then halo.Add(haloTargetsLeft, Color(250, 100, 0), 1, 1, 1, true, true) end
		if #haloTargetsRight > 0 then halo.Add(haloTargetsRight, Color(0, 255, 255), 1, 1, 1, true, true) end
	end)

	function vrmod.Pickup(bLeftHand, bDrop)
		local handStr = bLeftHand and "Left" or "Right"
		if bDrop then
			local held = g_VR[bLeftHand and "heldEntityLeft" or "heldEntityRight"]
			vrmod.logger.Debug("Pickup: Dropping entity from " .. handStr .. " hand -> " .. tostring(held))
			net.Start("vrmod_pickup")
			net.WriteBool(bLeftHand)
			net.WriteBool(true)
			net.SendToServer()
			g_VR[bLeftHand and "heldEntityLeft" or "heldEntityRight"] = nil
		else
			local targetEnt = bLeftHand and pickupTargetEntLeft or pickupTargetEntRight
			if IsValid(targetEnt) then
				if g_VR[bLeftHand and "heldEntityLeft" or "heldEntityRight"] ~= targetEnt then
					vrmod.logger.Debug("Pickup: Attempting to pick up entity with " .. handStr .. " hand -> " .. targetEnt:GetClass() .. " | Model: " .. (targetEnt:GetModel() or "nil"))
					net.Start("vrmod_pickup")
					net.WriteBool(bLeftHand)
					net.WriteBool(false)
					net.WriteEntity(targetEnt)
					net.SendToServer()
				else
					vrmod.logger.Debug("Pickup: Already holding target in " .. handStr .. " hand -> " .. targetEnt:GetClass())
				end
			else
				vrmod.logger.Debug("Pickup: No valid target to pick up in " .. handStr .. " hand")
			end
		end
	end

	net.Receive("vrmod_pickup", function()
		local ply, ent = net.ReadEntity(), net.ReadEntity()
		if not IsValid(ply) then
			vrmod.logger.Debug("net.Receive vrmod_pickup: Invalid player")
			return
		end

		if not IsValid(ent) then
			vrmod.logger.Debug("net.Receive vrmod_pickup: Invalid entity")
			return
		end

		local bDrop = net.ReadBool()
		if bDrop then
			vrmod.logger.Debug("net.Receive vrmod_pickup: Player " .. ply:Nick() .. " dropped entity -> " .. ent:GetClass())
			-- Always clear held on drop net (local drop path also nils; keep both in sync)
			if ply == LocalPlayer() then
				if g_VR.heldEntityLeft == ent then g_VR.heldEntityLeft = nil end
				if g_VR.heldEntityRight == ent then g_VR.heldEntityRight = nil end
			end
			hook.Call("VRMod_Drop", nil, ply, ent)
			return
		end

		local bLeftHand = net.ReadBool()
		local sid = ply:SteamID()
		if not g_VR.net[sid] then
			vrmod.logger.Debug("net.Receive vrmod_pickup: No VR data for player " .. ply:Nick())
			return
		end

		if ply == LocalPlayer() then
			g_VR[bLeftHand and "heldEntityLeft" or "heldEntityRight"] = ent
			vrmod.logger.Debug("net.Receive vrmod_pickup: Picked up entity with " .. (bLeftHand and "Left" or "Right") .. " hand -> " .. ent:GetClass())
		end

		hook.Call("VRMod_Pickup", nil, ply, ent)
	end)
end

if SERVER then
	local UpdateCoroutine = nil
	util.AddNetworkString("vrmod_pickup")
	-- Drop function
	function vrmod.Drop(steamid, bLeft)
		vrmod.logger.Debug("Entering vrmod.Drop with steamid: " .. tostring(steamid) .. ", bLeft: " .. tostring(bLeft))
		local ply = player.GetBySteamID(steamid)
		if not IsValid(ply) then vrmod.logger.Debug("vrmod.Drop: invalid player for steamid " .. tostring(steamid)) end
		local handVel = Vector(0, 0, 0)
		if IsValid(ply) then handVel = bLeft and (vrmod.GetLeftHandVelocity(ply) or Vector(0, 0, 0)) or vrmod.GetRightHandVelocity(ply) or Vector(0, 0, 0) end
		vrmod.logger.Debug("vrmod.Drop: hand velocity: " .. tostring(handVel))
		local index, info = vrmod.utils.FindPickupBySteamIDAndHand(steamid, bLeft)
		if not index or not info then
			vrmod.logger.Debug("vrmod.Drop: no matching pickup entry found for steamid: " .. tostring(steamid))
			return
		end

		vrmod.logger.Debug("vrmod.Drop: found pickup entry, releasing...")
		vrmod.utils.ReleasePickupEntry(index, info, handVel)
	end

	function vrmod.Pickup(ply, bLeftHand, ent)
		if not vrmod.utils.ValidatePickup(ply, bLeftHand, ent) then return end
		ent = vrmod.utils.HandleNPCRagdoll(ply, ent)
		local handPos, handAng = vrmod.utils.GetHandTransform(ply, bLeftHand)
		if not handPos or not handAng then return end
		if ent:GetClass() == "prop_ragdoll" then
			ent.vrmod_physOffsets = vrmod.utils.BuildRagdollOffsets(ent, handPos, handAng)
			ent:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)
		else
			if not GetConVar("vrmod_pickup_no_phys"):GetBool() then
				vrmod.utils.PatchOwnerCollision(ent, ply)
			else
				ent:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)
			end
		end

		local controller = vrmod.utils.InitPickupController()
		local info = vrmod.utils.CreatePickupInfo(ply, bLeftHand, ent, handPos, handAng)
		vrmod.utils.AttachPhysicsToController(info, controller)
		vrmod.utils.SendPickupNetMessage(ply, ent, bLeftHand)
	end

	vrmod.NetReceiveLimited("vrmod_pickup", 10, 400, function(len, ply)
		local bLeft = net.ReadBool()
		local bDrop = net.ReadBool()
		vrmod.logger.Debug("Received net message vrmod_pickup, bLeft: " .. tostring(bLeft) .. ", bDrop: " .. tostring(bDrop) .. ", player: " .. tostring(ply))
		if bDrop then
			vrmod.logger.Debug("Calling vrmod.Drop for player: " .. tostring(ply:SteamID()) .. ", bLeft: " .. tostring(bLeft))
			vrmod.Drop(ply:SteamID(), bLeft)
		else
			local ent = net.ReadEntity()
			vrmod.logger.Debug("Calling vrmod.Pickup for entity: " .. tostring(ent))
			vrmod.Pickup(ply, bLeft, ent)
		end
	end)

	-- Note: do NOT use GLua `continue` inside coroutines — it can throw
	-- "attempt to call a number value" (see GitHub issue #30).
	local function UpdatePickupFlagsCoroutine()
		local cv = {
			vrmod_pickup_npcs = GetConVar("vrmod_pickup_npcs"):GetInt(),
			vrmod_pickup_limit = GetConVar("vrmod_pickup_limit"):GetInt(),
			vrmod_pickup_weight = GetConVar("vrmod_pickup_weight"):GetFloat()
		}

		local players = player.GetAll()
		for i = 1, #players do
			local ply = players[i]
			if IsValid(ply) and g_VR[ply:SteamID()] and not ply:InVehicle() then
				local sid = ply:SteamID()
				local nearby = ents.FindInSphere(ply:GetPos(), 1000)
				for j = 1, #nearby do
					local ent = nearby[j]
					if IsValid(ent) and ent._vrmod_pickupable ~= false then
						local canPickup = vrmod.utils.CanPickupEntity(ent, ply, cv)
						local flag = "vrmod_pickup_valid_for_" .. sid
						if ent:GetNWBool(flag, false) ~= canPickup then
							ent:SetNWBool(flag, canPickup)
						end
						-- Yield occasionally so the Think budget stays light
						if j % 8 == 0 then
							coroutine.yield()
						end
					end
				end
				coroutine.yield()
			end
		end
	end

	-- Helper function to mark + auto-clean
	local function MarkAsReAgdollHidden(ent)
		if not IsValid(ent) then return end
		ent.ReAgdoll_HiddenNPC = true
		ent:SetNWBool("ReAgdoll_HiddenNPC", true)
		-- Auto-cleanup when entity is removed
		ent:CallOnRemove("ReAgdoll_HiddenNPC_Cleanup", function(e)
			if IsValid(e) then
				e.ReAgdoll_HiddenNPC = nil
				-- NWBool will automatically disappear when entity is removed
			end
		end)
	end

	-- Hook for NPC ragdolls created by ReAgdoll
	hook.Add("ReAgdoll_CreateNPCRagdoll", "MyVR_ReAgdollHiddenNPC", function(npc, ragdoll)
		MarkAsReAgdollHidden(npc)
		MarkAsReAgdollHidden(ragdoll)
	end)

	-- Hook for Player ragdolls created by ReAgdoll
	hook.Add("ReAgdoll_CreatePlayerRagdoll", "MyVR_ReAgdollHiddenPlayer", function(ply, ragdoll)
		MarkAsReAgdollHidden(ply)
		MarkAsReAgdollHidden(ragdoll)
	end)

	hook.Add("Think", "VRMod_UpdatePickupFlags", function()
		if not UpdateCoroutine or coroutine.status(UpdateCoroutine) == "dead" then
			UpdateCoroutine = coroutine.create(UpdatePickupFlagsCoroutine)
		end
		-- Only resume suspended coroutines (skip "running" / "dead")
		if coroutine.status(UpdateCoroutine) ~= "suspended" then return end
		local success, err = coroutine.resume(UpdateCoroutine)
		if not success then
			ErrorNoHaltWithStack("Pickup flag coroutine error: " .. tostring(err) .. "\n" .. debug.traceback(UpdateCoroutine))
			UpdateCoroutine = nil
		end
	end)

	hook.Add("PlayerDeath", "vrmod_drop_items_on_death", function(ply)
		if not IsValid(ply) then return end
		local sid = ply:SteamID()
		-- Force drop for both hands
		vrmod.Drop(sid, true)
		vrmod.Drop(sid, false)
	end)

	hook.Add("OnEntityCreated", "VRMod_PreloadPickupFlags", function(ent)
		if not IsValid(ent) then return end
		-- Skip players, weapons in hand, etc.
		if ent:IsPlayer() or ent:IsWeapon() then return end
		-- Use the existing heavy logic ONCE when the entity spawns
		local isPickupable = not vrmod.utils.IsNonPickupable(ent)
		-- Store it directly on the entity (fastest possible check later)
		ent._vrmod_pickupable = isPickupable
		-- Also set a networked bool so clients can see it without calling utils
		ent:SetNWBool("vrmod_pickupable", isPickupable)
	end)

	hook.Add("AllowPlayerPickup", "vrmod", function(ply) return not g_VR[ply:SteamID()] end)
end