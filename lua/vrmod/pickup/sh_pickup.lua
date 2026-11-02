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
	-- Kept so a saved "eye pickup on" migrates into vrmod_pickup_source. Not a settings row.
	vrmod.AddCallbackedConvar("vrmod_pickup_eye", nil, "0", FCVAR_ARCHIVE, "Legacy. Use vrmod_pickup_source", 0, 1, tobool)
	local _, pickupValues = vrmod.AddCallbackedConvar("vrmod_pickup_source", nil, "0", FCVAR_ARCHIVE, "0 hand proximity, 1 eye gazing", 0, 1, function(v)
		if vrmod.utils.LookTarget_SourceMode and vrmod.utils.LookTarget_SourceMode(v) == "eye" then return 1 end
		return 0
	end)
	vrmod.AddCallbackedConvar("vrmod_pickup_hand_range", nil, "3.5", FCVAR_ARCHIVE, "Client hand trigger distance, same scale as vrmod_pickup_range", 0, 16, function(v)
		v = tonumber(v)
		if not v or v ~= v then return 3.5 end
		if v < 0 then return 0 end
		if v > 16 then return 16 end
		return v
	end)
	vrmod.AddCallbackedConvar("vrmod_pickup_eye_range", nil, "12", FCVAR_ARCHIVE, "Client eye trigger distance, same scale as vrmod_pickup_range", 0, 32, function(v)
		if vrmod.utils.LookTarget_ClampRange then return vrmod.utils.LookTarget_ClampRange(v) end
		return tonumber(v) or 12
	end)
	local sourceMig = GetConVar("vrmod_pickup_source_migrated")
	if not sourceMig then
		sourceMig = CreateConVar("vrmod_pickup_source_migrated", "0", FCVAR_ARCHIVE or 128, "Copied vrmod_pickup_eye into vrmod_pickup_source once")
	end
	if sourceMig and not sourceMig:GetBool() then
		local oldEye = GetConVar("vrmod_pickup_eye")
		if oldEye and oldEye:GetBool() then
			pickupValues.vrmod_pickup_source = 1
			local src = GetConVar("vrmod_pickup_source")
			if src and src.SetInt then pcall(function() src:SetInt(1) end) end
			RunConsoleCommand("vrmod_pickup_source", "1")
		end
		if sourceMig.SetInt then pcall(function() sourceMig:SetInt(1) end) end
		RunConsoleCommand("vrmod_pickup_source_migrated", "1")
	end
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

	local function pickupSourceMode()
		local cv = GetConVar("vrmod_pickup_source")
		local raw = cv and cv:GetInt() or 0
		if vrmod.utils.LookTarget_SourceMode and vrmod.utils.LookTarget_SourceMode(raw) == "eye" then
			return "eye"
		end
		return "hand"
	end

	local function clientHandRange()
		local cv = GetConVar("vrmod_pickup_hand_range")
		local v = cv and cv:GetFloat() or 3.5
		if v ~= v or v < 0 then return 3.5 end
		return v
	end

	-- Gaze sample only. No sample is not an HMD look. The caller falls back to the hand.
	local function findEyeTarget(ply)
		if not vrmod.utils.LookTarget_Query then return nil, nil, false end
		local rangeCv = GetConVar("vrmod_pickup_eye_range")
		local range = vrmod.utils.LookTarget_ClampRange(rangeCv and rangeCv:GetFloat() or nil)
		local reach = vrmod.utils.LookTarget_MaxDistance(range, vrmod.utils.LookTarget_Boost(true, false))
		local ent, pos, reason = vrmod.utils.LookTarget_Query(ply, reach)
		if reason == "no_gaze" or reason == "no_api" then return nil, nil, false end
		if not IsValid(ent) or not pos then return nil, nil, true end
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
			return nil, nil, true
		end
		return ent, pos, true
	end

	local function handMayTake(ply, bLeft, ent)
		if not IsValid(ent) then return false end
		local _, cv = vrmod.GetConvars()
		if vrmod.utils.IsValidPickupTarget and not vrmod.utils.IsValidPickupTarget(ent, ply, bLeft) then return false end
		if vrmod.utils.CanPickupEntity and not vrmod.utils.CanPickupEntity(ent, ply, cv or {}) then return false end
		local aw = ply.GetActiveWeapon and ply:GetActiveWeapon() or nil
		local isWep = vrmod.utils.IsWeaponEntity and vrmod.utils.IsWeaponEntity(ent)
		local same = IsValid(aw) and ent.GetClass and aw.GetClass and ent:GetClass() == aw:GetClass()
		local holding = vrmod.utils.IsValidWep and vrmod.utils.IsValidWep(aw)
		if vrmod.utils.LookTarget_AllowHeldWeapon and not vrmod.utils.LookTarget_AllowHeldWeapon(isWep, same, bLeft, holding) then
			return false
		end
		return true
	end

	-- Touch is contact with THIS hand. A nearby search hit is not a touch.
	local function touchedByHand(handPos, handEnt, eyeEnt, eyePos)
		local touchDist = vrmod.utils.LookTarget_TouchDistance and vrmod.utils.LookTarget_TouchDistance() or 6
		local best, bestDist = nil, math.huge
		local function consider(ent, fallback)
			if not IsValid(ent) then return end
			local dist = pointDist(handPos, ent, fallback)
			if vrmod.utils.LookTarget_IsTouch and vrmod.utils.LookTarget_IsTouch(dist, touchDist) and dist < bestDist then
				best, bestDist = ent, dist
			end
		end
		consider(handEnt, nil)
		consider(eyeEnt, eyePos)
		return best
	end

	local function targetForHand(ply, bLeft, handPos, handEnt, eyeEnt, eyePos, sensor)
		if not vrmod.utils.LookTarget_ChoosePickup then return handEnt end
		local useEye = eyeEnt
		if not handMayTake(ply, bLeft, useEye) then useEye = nil end
		local useHand = handEnt
		if not handMayTake(ply, bLeft, useHand) then useHand = nil end
		local touchEnt = touchedByHand(handPos, useHand, useEye or eyeEnt, eyePos)
		if touchEnt and not handMayTake(ply, bLeft, touchEnt) then touchEnt = nil end
		local choice = vrmod.utils.LookTarget_ChoosePickup({
			mode = pickupSourceMode(),
			eye_sensor = sensor,
			touch_ent = touchEnt,
			hand_ent = useHand,
			eye_ent = useEye,
		})
		if not choice or choice.source == "none" then return nil end
		return choice.ent
	end

	hook.Add("Think", "vrmod_find_pickup_target", function()
		-- Sphere+trace both hands every Think hitches prop-dense maps. 30 Hz is enough.
		local fn = FrameNumber and FrameNumber() or 0
		if fn % 2 == 1 then return end
		local ply = LocalPlayer()
		if not IsValid(ply) or not g_VR or not vrmod.IsPlayerInVR(ply) or not ply:Alive() then return end
		local handRange = clientHandRange()
		local heldLeft = g_VR.heldEntityLeft
		local heldRight = g_VR.heldEntityRight
		local mode = pickupSourceMode()
		local eyeEnt, eyePos, sensor = nil, nil, false
		if mode == "eye" then
			eyeEnt, eyePos, sensor = findEyeTarget(ply)
		end
		-- Both hands run the same resolver. A weapon in the right hand no longer
		-- blanks that grip; it only refuses a second copy of the held weapon.
		local rightHand = g_VR.tracking and g_VR.tracking.pose_righthand
		if rightHand and not heldRight then
			local handEnt = vrmod.utils.FindPickupTarget(ply, false, rightHand.pos, rightHand.ang, handRange)
			pickupTargetEntRight = targetForHand(ply, false, rightHand.pos, handEnt, eyeEnt, eyePos, sensor)
		else
			pickupTargetEntRight = nil
		end

		local leftHand = g_VR.tracking and g_VR.tracking.pose_lefthand
		if leftHand and not heldLeft then
			local handEnt = vrmod.utils.FindPickupTarget(ply, true, leftHand.pos, leftHand.ang, handRange)
			pickupTargetEntLeft = targetForHand(ply, true, leftHand.pos, handEnt, eyeEnt, eyePos, sensor)
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