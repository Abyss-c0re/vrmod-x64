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
	local pickupTargetEntLeft = nil
	local pickupTargetEntRight = nil
	local haloTargetsLeft = {}
	local haloTargetsRight = {}
	-- Cleanup clones only for normal props on drop
	hook.Add("VRMod_Drop", "vrmod_drop_cooldown", function(ply, ent)
		if not IsValid(ent) or vrmod.utils.IsIgnoredProp(ent) then return end
		for _, hand in ipairs({"Left", "Right"}) do
			if g_VR then
				local key = hand == "Left" and "cooldownLeft" or "cooldownRight"
				g_VR[key] = true
				timer.Simple(0.5, function() if g_VR then g_VR[key] = false end end)
			end
		end
	end)

	hook.Add("Tick", "vrmod_find_pickup_target", function()
		local ply = LocalPlayer()
		if not IsValid(ply) or not g_VR or not vrmod.IsPlayerInVR(ply) or not ply:Alive() then return end
		local pickupRange = GetConVar("vrmod_pickup_range"):GetFloat()
		local heldLeft = g_VR.heldEntityLeft
		local heldRight = g_VR.heldEntityRight
		local rightHand = g_VR.tracking and g_VR.tracking.pose_righthand
		if rightHand and not heldRight and not vrmod.utils.IsValidWep(ply:GetActiveWeapon()) then
			pickupTargetEntRight = vrmod.utils.FindPickupTarget(ply, false, rightHand.pos, rightHand.ang, pickupRange)
		else
			pickupTargetEntRight = nil
		end

		local leftHand = g_VR.tracking and g_VR.tracking.pose_lefthand
		if leftHand and not heldLeft then
			pickupTargetEntLeft = vrmod.utils.FindPickupTarget(ply, true, leftHand.pos, leftHand.ang, pickupRange)
		else
			pickupTargetEntLeft = nil
		end
	end)

	hook.Add("PostDrawOpaqueRenderables", "vrmod_draw_pickup_halo", function()
		if not GetConVar("vrmod_pickup_halos"):GetBool() then return end
		table.Empty(haloTargetsLeft)
		table.Empty(haloTargetsRight)
		local ply = LocalPlayer()
		local heldLeft, heldRight = g_VR.heldEntityLeft, g_VR.heldEntityRight
		local holdingRagdoll = IsValid(heldLeft) and heldLeft:GetNWBool("is_npc_ragdoll", false) or IsValid(heldRight) and heldRight:GetNWBool("is_npc_ragdoll", false)
		local function ShouldAddHalo(ent)
			if not IsValid(ent) or ent == heldLeft or ent == heldRight or holdingRagdoll then return false end
			-- Check server flag for pickup validity, fallback to IsValidPickupTarget if flag missing
			local serverFlag = ent:GetNWBool("vrmod_pickup_valid_for_" .. ply:SteamID(), nil)
			if serverFlag == nil then
				-- If no server flag, fallback to your clientside logic
				return vrmod.utils.IsValidPickupTarget(ent, ply, false)
			end
			return serverFlag
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

		-- Per-hand ragdoll bone cleanup: remove only THIS hand's bones from the
		-- controller and bone map, so the other hand's bones remain active.
		local ent = info.ent
		if IsValid(ent) and ent:GetClass() == "prop_ragdoll" and info.ragdoll_bone_phys then
			local controller = vrmod.utils.GetPickupController and vrmod.utils.GetPickupController() or nil
			for _, bonePhys in ipairs(info.ragdoll_bone_phys) do
				if IsValid(bonePhys) then
					-- Remove from motion controller
					if IsValid(controller) and bonePhys ~= info.phys then
						controller:RemoveFromMotionController(bonePhys)
					end
					-- Restore normal mass/damping for released bones
					local origMasses = ent.vrmod_original_masses
					if origMasses then
						-- Find the phys index to restore original mass
						for i = 0, ent:GetPhysicsObjectCount() - 1 do
							if ent:GetPhysicsObjectNum(i) == bonePhys then
								if origMasses[i] then
									bonePhys:SetMass(origMasses[i])
								end
								bonePhys:SetDamping(0.5, 0.5)
								break
							end
						end
					end
				end
			end
			-- Clean up bone hand map entries for this hand
			if ent.vrmod_bone_hand_map then
				for physIdx, mappedInfo in pairs(ent.vrmod_bone_hand_map) do
					if mappedInfo == info then
						ent.vrmod_bone_hand_map[physIdx] = nil
					end
				end
				-- If no bones left in map, clean up the map itself
				if not next(ent.vrmod_bone_hand_map) then
					ent.vrmod_bone_hand_map = nil
				end
			end
			info.ragdoll_bone_phys = nil
			vrmod.logger.Debug("vrmod.Drop: cleaned up ragdoll bone physics for " .. (bLeft and "left" or "right") .. " hand")
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
		end
		-- Use PASSABLE_DOOR for both ragdolls and props so held entities
		-- never collide with the player or VR hands while being carried
		ent:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)

		local controller = vrmod.utils.InitPickupController()
		local info = vrmod.utils.CreatePickupInfo(ply, bLeftHand, ent, handPos, handAng)
		vrmod.utils.AttachPhysicsToController(info, controller)

		-- Ragdoll two-hand grab system:
		-- Each hand controls up to 4 nearest bones. A per-bone map on the entity
		-- (ent.vrmod_bone_hand_map) tells PhysicsSimulate which hand's info to use
		-- for each bone, enabling simultaneous two-hand ragdoll manipulation.
		if ent:GetClass() == "prop_ragdoll" and IsValid(controller) then
			-- Initialize per-bone hand map if not present
			ent.vrmod_bone_hand_map = ent.vrmod_bone_hand_map or {}

			-- Build a set of bone physics indices already claimed by the OTHER hand
			local claimedByOtherHand = {}
			for physIdx, otherInfo in pairs(ent.vrmod_bone_hand_map) do
				if otherInfo and otherInfo ~= info and otherInfo.left ~= bLeftHand then
					claimedByOtherHand[physIdx] = true
				end
			end

			-- Build per-hand offsets so each hand's bones track relative to THAT hand
			local handOffsets = {}
			for i = 0, ent:GetPhysicsObjectCount() - 1 do
				local bonePhys = ent:GetPhysicsObjectNum(i)
				if IsValid(bonePhys) then
					local physPos, physAng = bonePhys:GetPos(), bonePhys:GetAngles()
					local lpos, lang = WorldToLocal(physPos, physAng, handPos, handAng)
					handOffsets[i] = { localPos = lpos, localAng = lang }
				end
			end
			info.vrmod_physOffsets = handOffsets

			-- Collect unclaimed bone physics with distance to this hand
			local boneDistances = {}
			for i = 0, ent:GetPhysicsObjectCount() - 1 do
				local bonePhys = ent:GetPhysicsObjectNum(i)
				if IsValid(bonePhys) and not claimedByOtherHand[i] then
					local dist = bonePhys:GetPos():DistToSqr(handPos)
					boneDistances[#boneDistances + 1] = { phys = bonePhys, dist = dist, idx = i, isRoot = (bonePhys == info.phys) }
				end
			end

			-- Sort by distance to hand (nearest first)
			table.sort(boneDistances, function(a, b) return a.dist < b.dist end)

			-- Attach up to 4 nearest unclaimed bones to this hand
			local maxBones = 4
			local bonePhysList = {}
			local attached = 0
			for _, entry in ipairs(boneDistances) do
				if attached >= maxBones then break end
				local bonePhys = entry.phys
				-- Add non-root bones to the controller (root already added by AttachPhysicsToController)
				if not entry.isRoot then
					controller:AddToMotionController(bonePhys)
				end
				bonePhys:Wake()
				-- Light mass + zero damping = shadow controller can snap bones instantly
				bonePhys:SetMass(8)
				bonePhys:SetDamping(0, 0)
				bonePhysList[#bonePhysList + 1] = bonePhys
				-- Map this bone to this hand's info for PhysicsSimulate
				ent.vrmod_bone_hand_map[entry.idx] = info
				attached = attached + 1
			end
			-- Store refs on the info (not entity) for per-hand cleanup on drop
			info.ragdoll_bone_phys = bonePhysList
			vrmod.logger.Debug("Pickup: Attached " .. #bonePhysList .. " nearest ragdoll bone physics (of " .. #boneDistances .. " unclaimed) to " .. (bLeftHand and "left" or "right") .. " hand controller for " .. tostring(ent))
		end

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

	local function UpdatePickupFlags()
		vrmod.logger.Debug("Updating pickup flags for all players")
		for _, ply in ipairs(player.GetAll()) do
			local nearbyEntities = ents.FindInSphere(ply:GetPos(), 300)
			local cv = {
				vrmod_pickup_npcs = GetConVar("vrmod_pickup_npcs"):GetInt(),
				vrmod_pickup_limit = GetConVar("vrmod_pickup_limit"):GetInt(),
				vrmod_pickup_weight = GetConVar("vrmod_pickup_weight"):GetFloat()
			}

			vrmod.logger.Debug("Convar values: npcs=" .. cv.vrmod_pickup_npcs .. ", limit=" .. cv.vrmod_pickup_limit .. ", weight=" .. cv.vrmod_pickup_weight)
			for _, ent in ipairs(nearbyEntities) do
				local canPickup = vrmod.utils.CanPickupEntity(ent, ply, cv)
				vrmod.logger.Debug("Setting pickup flag for entity: " .. tostring(ent) .. ", player: " .. ply:SteamID() .. ", canPickup: " .. tostring(canPickup))
				ent:SetNWBool("vrmod_pickup_valid_for_" .. ply:SteamID(), canPickup)
			end
		end

		vrmod.logger.Debug("Finished updating pickup flags")
	end

	-- Run every second for performance
	timer.Create("VRMod_UpdatePickupFlags", 1, 0, UpdatePickupFlags)
	hook.Add("PlayerDeath", "vrmod_drop_items_on_death", function(ply)
		if not IsValid(ply) then return end
		local sid = ply:SteamID()
		-- Force drop for both hands
		vrmod.Drop(sid, true)
		vrmod.Drop(sid, false)
	end)

	hook.Add("AllowPlayerPickup", "vrmod", function(ply) return not g_VR[ply:SteamID()] end)
end