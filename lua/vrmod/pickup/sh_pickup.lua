g_VR = g_VR or {}
vrmod = vrmod or {}
local debugPrintedClasses = {}
scripted_ents.Register({
	Type = "anim",
	Base = "vrmod_pickup"
}, "vrmod_pickup")

local blacklistedClasses = {
	["npc_turret_floor"] = true,
	["info_particle_system"] = true,
	["item_healthcharger"] = true,
	["item_suitcharger"] = true,
	["item_ammo_crate"] = true,
}

local blacklistedPatterns = {"beam", "button", "dynamic", "func_", "c_base", "laser", "info_", "sprite", "env_", "fire", "trail", "light", "spotlight", "streetlight", "traffic", "texture", "shadow", "keypad"}
local _, convarValues = vrmod.GetConvars()
vrmod.AddCallbackedConvar("vrmod_pickup_limit", nil, 1, FCVAR_REPLICATED + FCVAR_NOTIFY + FCVAR_ARCHIVE, "", 0, 3, tonumber)
vrmod.AddCallbackedConvar("vrmod_pickup_range", nil, 1.2, FCVAR_REPLICATED + FCVAR_ARCHIVE, "", 0.0, 999.0, tonumber)
vrmod.AddCallbackedConvar("vrmod_pickup_weight", nil, 150, FCVAR_REPLICATED + FCVAR_ARCHIVE, "", 0, 10000, tonumber)
vrmod.AddCallbackedConvar("vrmod_pickup_npcs", nil, 1, FCVAR_REPLICATED + FCVAR_NOTIFY + FCVAR_ARCHIVE, "", 0, 3, tonumber)
vrmod.AddCallbackedConvar("vrmod_pickup_limit", nil, "1", FCVAR_REPLICATED + FCVAR_NOTIFY + FCVAR_ARCHIVE, "", 0, 3, tonumber)
local pickupableCache = {}
local function IsImportantPickup(ent)
	local class = ent:GetClass()
	return class:find("^item_") or class:find("^spawned_") or class:find("^vr_item") or vrmod.utils.IsWeaponEntity(ent)
end

local function HasHeldWeaponRight(ply)
	return vrmod.utils.IsValidWep(ply:GetActiveWeapon())
end

local function CanPickupEntity(v, ply, cv)
	if not IsValid(v) or v == ply or ply:InVehicle() then return false end
	if cv.vrmod_pickup_npcs == 1 then if v:IsNPC() or v:IsNextBot() then return true end end
	-- Only do physics mass check server-side
	if SERVER then
		local phys = v:GetPhysicsObject()
		if not IsValid(phys) then return false end
		if cv.vrmod_pickup_limit == 1 then return v:GetMoveType() == MOVETYPE_VPHYSICS and phys:GetMass() <= cv.vrmod_pickup_weight end
	end
	return true
end

local function IsNonPickupable(ent)
	if not IsValid(ent) then
		vrmod.logger.Debug("IsNonPickupable: Entity is invalid")
		return true
	end

	local class = ent:GetClass():lower()
	local model = (ent:GetModel() or ""):lower()
	local key = class .. "|" .. model
	if pickupableCache[key] ~= nil then
		vrmod.logger.Debug("IsNonPickupable: Cache hit for " .. key .. " -> " .. tostring(pickupableCache[key]))
		return pickupableCache[key]
	end

	-- Class blacklist (exact match)
	if blacklistedClasses[class] then
		vrmod.logger.Debug("IsNonPickupable: Class is blacklisted -> " .. class)
		pickupableCache[key] = true
		return true
	end

	-- Pattern blacklists
	for _, pattern in ipairs(blacklistedPatterns) do
		pattern = pattern:lower()
		if class:find(pattern, 1, true) or model:find(pattern, 1, true) then
			vrmod.logger.Debug("IsNonPickupable: Class or model matches blacklist pattern '" .. pattern .. "' -> " .. class .. ", " .. model)
			pickupableCache[key] = true
			return true
		end
	end

	-- Weapon or important item overrides
	if vrmod.utils.IsWeaponEntity(ent) or class:find("prop_") or IsImportantPickup(ent) then
		vrmod.logger.Debug("IsNonPickupable: Entity is a weapon, prop, or important pickup -> " .. class)
		pickupableCache[key] = false
		return false
	end

	local npcPickupAllowed = (convarValues and convarValues.vrmod_pickup_npcs or 0) >= 1
	if npcPickupAllowed and (ent:IsNPC() or ent:IsNextBot()) then
		vrmod.logger.Debug("IsNonPickupable: NPC pickup allowed, entity is NPC/NextBot -> " .. class)
		pickupableCache[key] = false
		return false
	end

	-- Physics check
	if ent:GetMoveType() ~= MOVETYPE_VPHYSICS then
		vrmod.logger.Debug("IsNonPickupable: Non-physics entity -> " .. class .. " | MoveType: " .. tostring(ent:GetMoveType()))
		pickupableCache[key] = true
		return true
	end

	pickupableCache[key] = false
	return false
end

local function IsValidPickupTarget(ent, ply, bLeftHand)
	if not IsValid(ent) then
		vrmod.logger.Debug("IsValidPickupTarget: Entity invalid")
		return false
	end

	if ent:GetNoDraw() then
		vrmod.logger.Debug("IsValidPickupTarget: Entity has NoDraw -> " .. ent:GetClass())
		return false
	end

	if ent:IsDormant() then
		vrmod.logger.Debug("IsValidPickupTarget: Entity is dormant -> " .. ent:GetClass())
		return false
	end

	if IsNonPickupable(ent) then
		vrmod.logger.Debug("IsValidPickupTarget: Entity is non-pickupable -> " .. ent:GetClass())
		return false
	end

	if ent:GetNWBool("is_npc_ragdoll", false) then
		vrmod.logger.Debug("IsValidPickupTarget: Entity is NPC ragdoll -> " .. ent:GetClass())
		return false
	end

	if bLeftHand and ent == g_VR.heldEntityLeft then
		vrmod.logger.Debug("IsValidPickupTarget: Already held in left hand -> " .. ent:GetClass())
		return false
	end

	if not bLeftHand and ent == g_VR.heldEntityRight then
		vrmod.logger.Debug("IsValidPickupTarget: Already held in right hand -> " .. ent:GetClass())
		return false
	end

	if ent:IsWeapon() and ent:GetOwner() == ply then
		vrmod.logger.Debug("IsValidPickupTarget: Weapon already owned by player -> " .. ent:GetClass())
		return false
	end

	vrmod.logger.Debug("IsValidPickupTarget: Valid pickup -> " .. ent:GetClass())
	return true
end

local function FindPickupTarget(ply, bLeftHand, handPos, handAng, pickupRange)
	-- Ensure a sane default
	if type(pickupRange) ~= "number" or pickupRange <= 0 then pickupRange = 1.2 end
	local ent
	local hand = bLeftHand and "left" or "right"
	-- Sphere search first (tiny radius)
	local nearby = ents.FindInSphere(handPos, 5)
	local closestDistSq = math.huge
	for _, e in ipairs(nearby) do
		if e ~= ply and IsValidPickupTarget(e, ply, bLeftHand) and CanPickupEntity(e, ply, convarValues or vrmod.GetConvars()) then
			local distSq = e:GetPos():DistToSqr(handPos)
			if distSq < closestDistSq then
				ent = e
				closestDistSq = distSq
			end
		end
	end

	-- Fallback to trace if nothing found
	if not IsValid(ent) then
		local tr = vrmod.utils.TraceHand(ply, hand, true)
		if tr and tr.Entity and IsValid(tr.Entity) then
			local e = tr.Entity
			if e ~= ply and IsValidPickupTarget(e, ply, bLeftHand) and CanPickupEntity(e, ply, convarValues or vrmod.GetConvars()) then ent = e end
		end
	end

	if not IsValid(ent) then return nil end
	-- Range check with boost
	local boost = IsImportantPickup(ent) and 5.0 or 1.0
	local maxDist = pickupRange * 100 * boost
	if (ent:GetPos() - handPos):LengthSqr() > maxDist ^ 2 then return nil end
	-- Weapon-specific rules
	if vrmod.utils.IsWeaponEntity(ent) then
		local aw = ply:GetActiveWeapon()
		if IsValid(aw) and aw:GetClass() == ent:GetClass() then return nil end
		if not bLeftHand and HasHeldWeaponRight(ply) then return nil end
	end
	return ent
end

if CLIENT then
	CreateClientConVar("vrmod_pickup_halos", "1", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
	local pickupTargetEntLeft = nil
	local pickupTargetEntRight = nil
	local haloTargetsLeft = {}
	local haloTargetsRight = {}
	hook.Add("Tick", "vrmod_find_pickup_target", function()
		local ply = LocalPlayer()
		if not IsValid(ply) or not g_VR or not vrmod.IsPlayerInVR(ply) or not ply:Alive() then return end
		local pickupRange = GetConVar("vrmod_pickup_range"):GetFloat()
		local heldLeft = g_VR.heldEntityLeft
		local heldRight = g_VR.heldEntityRight
		local rightHand = g_VR.tracking and g_VR.tracking.pose_righthand
		if rightHand and not heldRight and not HasHeldWeaponRight(ply) then
			pickupTargetEntRight = FindPickupTarget(ply, false, rightHand.pos, rightHand.ang, pickupRange)
		else
			pickupTargetEntRight = nil
		end

		local leftHand = g_VR.tracking and g_VR.tracking.pose_lefthand
		if leftHand and not heldLeft then
			pickupTargetEntLeft = FindPickupTarget(ply, true, leftHand.pos, leftHand.ang, pickupRange)
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
				return IsValidPickupTarget(ent, ply, false)
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
	local pickupController, pickupList, pickupCount = nil, {}, 0
	-- Drop function
	function vrmod.Drop(steamid, bLeft)
		vrmod.logger.Debug("Entering vrmod.Drop with steamid: " .. tostring(steamid) .. ", bLeft: " .. tostring(bLeft))
		local function SendPickupNetMsg(ply, ent)
			vrmod.logger.Debug("Sending pickup net message for player: " .. tostring(ply) .. ", entity: " .. tostring(ent))
			net.Start("vrmod_pickup")
			net.WriteEntity(ply)
			net.WriteEntity(IsValid(ent) and ent or NULL)
			net.WriteBool(true)
			net.Broadcast()
		end

		local ply = player.GetBySteamID(steamid)
		vrmod.logger.Debug("Player retrieved: " .. tostring(ply))
		local handVel = bLeft and vrmod.GetLeftHandVelocity(ply) or vrmod.GetRightHandVelocity(ply) or Vector(0, 0, 0)
		vrmod.logger.Debug("Hand velocity: " .. tostring(handVel))
		for i = 1, pickupCount do
			local t = pickupList[i]
			if t.steamid == steamid and t.left == bLeft then
				vrmod.logger.Debug("Found matching pickup entry at index: " .. i .. ", entity: " .. tostring(t.ent))
				local ent = t.ent
				if IsValid(pickupController) and IsValid(t.phys) then
					vrmod.logger.Debug("Removing physics object from motion controller: " .. tostring(t.phys))
					pickupController:RemoveFromMotionController(t.phys)
				end

				if IsValid(ent) and ent.original_npc then
					local npc = ent.original_npc
					vrmod.logger.Debug("Handling NPC ragdoll, NPC: " .. tostring(npc) .. ", is dead: " .. tostring(vrmod.utils.IsRagdollDead(ent)))
					if IsValid(npc) and not vrmod.utils.IsRagdollDead(ent) then
						ent.dropped_manually = true
						ent.noDamage = true
						vrmod.logger.Debug("Setting bone mass for entity: " .. tostring(ent))
						vrmod.utils.SetBoneMass(ent, 300, 0, handVel, 5)
						timer.Simple(0.1, function()
							if IsValid(ent) then
								vrmod.logger.Debug("Patching owner collision for entity: " .. tostring(ent))
								vrmod.utils.PatchOwnerCollision(ent)
							end
						end)

						SendPickupNetMsg(t.ply, npc)
						if not vrmod.utils.IsRagdollDead(ent) then
							vrmod.logger.Debug("Scheduling entity removal: " .. tostring(ent))
							timer.Simple(3.0, function() ent:Remove() end)
						end
					else
						ent.dropped_manually = false
						if IsValid(ent) then
							vrmod.logger.Debug("Setting NWBool is_npc_ragdoll to false for entity: " .. tostring(ent))
							ent:SetNWBool("is_npc_ragdoll", false)
						end

						SendPickupNetMsg(t.ply, ent)
					end
				elseif IsValid(ent) then
					local phys = ent:GetPhysicsObject()
					if IsValid(phys) and pickupController then
						vrmod.logger.Debug("Removing physics object from motion controller: " .. tostring(phys))
						pickupController:RemoveFromMotionController(phys)
					end

					vrmod.logger.Debug("Patching owner collision for entity: " .. tostring(t.ent))
					vrmod.utils.PatchOwnerCollision(t.ent, t.ply)
					if IsValid(t.phys) then
						vrmod.logger.Debug("Waking physics object: " .. tostring(t.phys))
						t.phys:Wake()
					end

					SendPickupNetMsg(t.ply, ent)
				else
					vrmod.logger.Debug("Sending pickup net message with nil entity for player: " .. tostring(t.ply))
					SendPickupNetMsg(t.ply, nil)
				end

				if g_VR[steamid] and g_VR[steamid].heldItems then
					vrmod.logger.Debug("Clearing held item for steamid: " .. steamid .. ", hand: " .. (bLeft and "left" or "right"))
					g_VR[steamid].heldItems[bLeft and 1 or 2] = nil
				end

				vrmod.logger.Debug("Removing pickup entry at index: " .. i)
				table.remove(pickupList, i)
				pickupCount = pickupCount - 1
				if IsValid(ent) then
					vrmod.logger.Debug("Setting picked to false for entity: " .. tostring(ent))
					ent.picked = false
				end

				if pickupCount == 0 and IsValid(pickupController) then
					vrmod.logger.Debug("Stopping and removing pickup controller")
					pickupController:StopMotionController()
					pickupController:Remove()
					pickupController = nil
				end

				vrmod.logger.Debug("Calling VRMod_Drop hook for player: " .. tostring(t.ply) .. ", entity: " .. tostring(t.ent))
				hook.Call("VRMod_Drop", nil, t.ply, t.ent)
				return
			end
		end

		vrmod.logger.Debug("No matching pickup entry found for steamid: " .. steamid .. ", bLeft: " .. tostring(bLeft))
	end

	function vrmod.Pickup(ply, bLeftHand, ent)
		local sid = ply:SteamID()
		vrmod.logger.Debug("Entering vrmod.Pickup with player: " .. tostring(ply) .. ", bLeftHand: " .. tostring(bLeftHand) .. ", entity: " .. tostring(ent))
		if g_VR[sid] and g_VR[sid].heldItems and g_VR[sid].heldItems[bLeftHand and 1 or 2] then
			vrmod.logger.Debug("Player already holding an item in hand: " .. (bLeftHand and "left" or "right"))
			return
		end

		if not IsValid(ent) or not CanPickupEntity(ent, ply, convarValues) or hook.Call("VRMod_Pickup", nil, ply, ent) == false then
			vrmod.logger.Debug("Cannot pick up entity: valid=" .. tostring(IsValid(ent)) .. ", canPickup=" .. tostring(CanPickupEntity(ent, ply, convarValues)) .. ", hookResult=" .. tostring(hook.Call("VRMod_Pickup", nil, ply, ent)))
			return
		end

		if ent:IsNPC() then
			vrmod.logger.Debug("Spawning pickup ragdoll for NPC: " .. tostring(ent))
			ent = vrmod.utils.SpawnPickupRagdoll(ply, ent)
		end

		vrmod.logger.Debug("Setting picked to true for entity: " .. tostring(ent))
		ent.picked = true
		local handPos, handAng
		if bLeftHand then
			handPos = vrmod.GetLeftHandPos(ply)
			handAng = vrmod.GetLeftHandAng(ply)
			vrmod.logger.Debug("Left hand pos: " .. tostring(handPos) .. ", ang: " .. tostring(handAng))
		else
			handPos = vrmod.GetRightHandPos(ply)
			handAng = vrmod.GetRightHandAng(ply)
			vrmod.logger.Debug("Right hand pos: " .. tostring(handPos) .. ", ang: " .. tostring(handAng))
		end

		if ent:GetClass() == "prop_ragdoll" then
			local physOffsets = {}
			for i = 0, ent:GetPhysicsObjectCount() - 1 do
				local phys = ent:GetPhysicsObjectNum(i)
				if IsValid(phys) then
					local physPos, physAng = phys:GetPos(), phys:GetAngles()
					local lpos, lang = WorldToLocal(physPos, physAng, handPos, handAng)
					physOffsets[i] = {
						localPos = lpos,
						localAng = lang
					}

					vrmod.logger.Debug("Ragdoll phys index: " .. i .. ", localPos: " .. tostring(lpos) .. ", localAng: " .. tostring(lang))
				end
			end

			ent.vrmod_physOffsets = physOffsets
			vrmod.logger.Debug("Stored physOffsets for ragdoll: " .. tostring(ent))
		end

		local phys = ent:GetPhysicsObject()
		local mass = IsValid(phys) and phys:GetMass() or 1
		vrmod.logger.Debug("Entity physics mass: " .. mass)
		local damp = 0.35
		local secondstoarrive = 0.001
		local teleportdistance = 0
		if ent:GetClass() ~= "prop_ragdoll" then
			damp = math.Clamp(0.0058 * mass * 1.5, 0.15, 0.35)
			vrmod.logger.Debug("Non-ragdoll damping: " .. damp)
		end

		vrmod.logger.Debug("Patching owner collision for entity: " .. tostring(ent) .. ", player: " .. tostring(ply))
		vrmod.utils.PatchOwnerCollision(ent, ply)
		if not IsValid(pickupController) then
			vrmod.logger.Debug("Creating new pickup controller")
			pickupController = ents.Create("vrmod_pickup")
			pickupController.ShadowParams = {
				secondstoarrive = secondstoarrive,
				maxangular = 99999,
				maxangulardamp = 999,
				maxspeed = 99999,
				maxspeeddamp = 999,
				dampfactor = damp,
				teleportdistance = teleportdistance,
				deltatime = 0
			}

			function pickupController:PhysicsSimulate(phys, dt)
				vrmod.logger.Debug("PhysicsSimulate for phys: " .. tostring(phys) .. ", deltaTime: " .. dt)
				phys:Wake()
				local info = phys:GetEntity().vrmod_pickup_info
				if not info then
					vrmod.logger.Debug("No pickup info found for phys: " .. tostring(phys))
					return
				end

				local ply = info.ply
				if not IsValid(ply) then
					vrmod.logger.Debug("Invalid player in pickup info")
					return
				end

				local handPos, handAng
				if info.left then
					handPos = vrmod.GetLeftHandPos(ply)
					handAng = vrmod.GetLeftHandAng(ply)
					vrmod.logger.Debug("PhysicsSimulate left hand pos: " .. tostring(handPos) .. ", ang: " .. tostring(handAng))
				else
					handPos = vrmod.GetRightHandPos(ply)
					handAng = vrmod.GetRightHandAng(ply)
					vrmod.logger.Debug("PhysicsSimulate right hand pos: " .. tostring(handPos) .. ", ang: " .. tostring(handAng))
				end

				if not handPos or not handAng then
					vrmod.logger.Debug("Invalid hand position or angle")
					return
				end

				local targetPos, targetAng
				local ent = phys:GetEntity()
				if ent:GetClass() == "prop_ragdoll" and ent.vrmod_physOffsets then
					local physIndex
					for i = 0, ent:GetPhysicsObjectCount() - 1 do
						if ent:GetPhysicsObjectNum(i) == phys then
							physIndex = i
							break
						end
					end

					if physIndex and ent.vrmod_physOffsets[physIndex] then
						local offset = ent.vrmod_physOffsets[physIndex]
						targetPos, targetAng = LocalToWorld(offset.localPos, offset.localAng, handPos, handAng)
						vrmod.logger.Debug("Ragdoll target pos: " .. tostring(targetPos) .. ", ang: " .. tostring(targetAng) .. " for phys index: " .. physIndex)
					end
				else
					targetPos, targetAng = LocalToWorld(info.localPos, info.localAng, handPos, handAng)
					vrmod.logger.Debug("Non-ragdoll target pos: " .. tostring(targetPos) .. ", ang: " .. tostring(targetAng))
					if mass < 3 then
						local jitter = 0.5 * 1 / mass
						targetPos = targetPos + VectorRand() * jitter
						vrmod.logger.Debug("Applied jitter to target pos: " .. tostring(targetPos) .. ", jitter amount: " .. jitter)
					end
				end

				if not targetPos then
					vrmod.logger.Debug("No target position calculated")
					return
				end

				local effectiveMass = math.max(mass, 2)
				vrmod.logger.Debug("Applying player velocity, effective mass: " .. effectiveMass)
				phys:AddVelocity(ply:GetVelocity() * dt * effectiveMass)
				pickupController.ShadowParams.pos = targetPos
				pickupController.ShadowParams.angle = targetAng
				vrmod.logger.Debug("Computing shadow control with pos: " .. tostring(targetPos) .. ", angle: " .. tostring(targetAng))
				phys:ComputeShadowControl(pickupController.ShadowParams)
			end

			vrmod.logger.Debug("Starting motion controller for pickup")
			pickupController:StartMotionController()
		end

		local index = pickupCount + 1
		for k, v2 in ipairs(pickupList) do
			if v2.ent == ent then
				index = k
				vrmod.logger.Debug("Found existing pickup entry for entity: " .. tostring(ent) .. " at index: " .. index)
				g_VR[v2.steamid].heldItems[v2.left and 1 or 2] = nil
				break
			end
		end

		if index > pickupCount then
			pickupCount = pickupCount + 1
			vrmod.logger.Debug("Incremented pickupCount to: " .. pickupCount)
			if ent:GetClass() == "prop_ragdoll" then
				vrmod.logger.Debug("Setting bone mass for ragdoll: " .. tostring(ent))
				vrmod.utils.SetBoneMass(ent, 15, 0.5)
			end
		end

		vrmod.logger.Debug("Snapping entity to hand: " .. tostring(ent))
		local didSnap = vrmod.utils.SnapEntityToHand(ent, handPos, handAng)
		vrmod.logger.Debug("Snap result: " .. tostring(didSnap))
		local lpos, lang
		if ent:GetClass() ~= "prop_ragdoll" then
			lpos, lang = WorldToLocal(ent:GetPos(), ent:GetAngles(), handPos, handAng)
			vrmod.logger.Debug("Non-ragdoll local pos: " .. tostring(lpos) .. ", ang: " .. tostring(lang))
		else
			lpos, lang = Vector(0, 0, 0), Angle(0, 0, 0)
			vrmod.logger.Debug("Ragdoll local pos: " .. tostring(lpos) .. ", ang: " .. tostring(lang))
		end

		pickupList[index] = {
			ent = ent,
			phys = ent:GetPhysicsObject(),
			left = bLeftHand,
			localPos = lpos,
			localAng = lang,
			collisionGroup = ent:GetCollisionGroup(),
			steamid = sid,
			ply = ply,
			snapped = didSnap
		}

		vrmod.logger.Debug("Added pickup entry at index: " .. index .. ", entity: " .. tostring(ent))
		g_VR[sid].heldItems = g_VR[sid].heldItems or {}
		g_VR[sid].heldItems[bLeftHand and 1 or 2] = pickupList[index]
		vrmod.logger.Debug("Stored held item for steamid: " .. sid .. ", hand: " .. (bLeftHand and "left" or "right"))
		ent.vrmod_pickup_info = pickupList[index]
		local phys = IsValid(ent) and ent:GetPhysicsObject()
		if IsValid(phys) and IsValid(pickupController) then
			vrmod.logger.Debug("Adding physics object to motion controller: " .. tostring(phys))
			pickupController:AddToMotionController(phys)
			phys:Wake()
		end

		vrmod.logger.Debug("Sending pickup net message for player: " .. tostring(ply) .. ", entity: " .. tostring(ent) .. ", bLeftHand: " .. tostring(bLeftHand))
		net.Start("vrmod_pickup")
		net.WriteEntity(ply)
		net.WriteEntity(ent)
		net.WriteBool(false)
		net.WriteBool(bLeftHand)
		net.Broadcast()
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
				local canPickup = CanPickupEntity(ent, ply, cv)
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