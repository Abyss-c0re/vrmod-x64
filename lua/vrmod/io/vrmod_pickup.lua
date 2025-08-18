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
	["C_BaseFlex"] = true,
	["C_BaseViewModel"] = true,
	["func_button"] = true,
	["func_rot_button"] = true,
	["item_healthcharger"] = true,
	["item_suitcharger"] = true,
	["item_ammo_crate"] = true,
	["func_door_rotating"] = true,
}

local blacklistedPatterns = {"beam", "button", "laser", "sprite", "env_", "fire", "trail", "spotlight", "projectedtexture", "shadow", "keypad"}
local _, convarValues = vrmod.GetConvars()
vrmod.AddCallbackedConvar("vrmod_pickup_limit", nil, 1, FCVAR_REPLICATED + FCVAR_NOTIFY + FCVAR_ARCHIVE, "", 0, 3, tonumber)
vrmod.AddCallbackedConvar("vrmod_pickup_range", nil, 1.2, FCVAR_REPLICATED + FCVAR_ARCHIVE, "", 0.0, 999.0, tonumber)
vrmod.AddCallbackedConvar("vrmod_pickup_weight", nil, 150, FCVAR_REPLICATED + FCVAR_ARCHIVE, "", 0, 10000, tonumber)
vrmod.AddCallbackedConvar("vrmod_pickup_npcs", nil, 1, FCVAR_REPLICATED + FCVAR_NOTIFY + FCVAR_ARCHIVE, "", 0, 3, tonumber)
vrmod.AddCallbackedConvar("vrmod_pickup_limit", nil, "1", FCVAR_REPLICATED + FCVAR_NOTIFY + FCVAR_ARCHIVE, "", 0, 3, tonumber)
local function IsWeaponEntity(ent)
	if not IsValid(ent) then return false end
	local c = ent:GetClass()
	return ent:IsWeapon() or c:find("weapon_") or c == "prop_physics" and ent:GetModel():find("w_")
end

local function IsImportantPickup(ent)
	local class = ent:GetClass()
	return class:find("^item_") or class:find("^spawned_") or class:find("^vr_item")
end

local function HasHeldWeaponRight(ply)
	local sid = ply:SteamID()
	return g_VR[sid] and g_VR[sid].heldItems and g_VR[sid].heldItems[2] and IsWeaponEntity(g_VR[sid].heldItems[2].ent)
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
	if not IsValid(ent) then return true end
	local class = ent:GetClass():lower()
	local model = (ent:GetModel() or ""):lower()
	-- Static blacklist
	if blacklistedClasses[class] then return true end
	-- Pattern-based class filter
	for _, pattern in ipairs(blacklistedPatterns) do
		if class:find(pattern:lower(), 1, true) then return true end
	end

	if IsWeaponEntity(ent) or class:find("prop_") or IsImportantPickup(ent) then return false end
	local npcPickupAllowed = (convarValues and convarValues.vrmod_pickup_npcs or 0) >= 1
	if npcPickupAllowed and (ent:IsNPC() or ent:IsNextBot()) then return false end
	-- Final fallback: block non-physics objects
	if ent:GetMoveType() ~= MOVETYPE_VPHYSICS then
		if CLIENT and GetConVar("vrmod_pickup_debug"):GetBool() and not debugPrintedClasses[class] then
			debugPrintedClasses[class] = true
			print("[VRMod] DEBUG fallback: non-blacklisted non-physics entity")
			print("  Class: " .. class)
			print("  Model: " .. model)
			print("  MoveType: " .. tostring(ent:GetMoveType()))
			print("  Owner: " .. tostring(ent:GetOwner()))
		end
		return true
	end
	return false
end

local function IsValidPickupTarget(ent, ply, bLeftHand)
	if not IsValid(ent) or ent:GetNoDraw() or ent:IsDormant() then return false end
	if IsNonPickupable(ent) then return false end
	if ent:GetNWBool("is_npc_ragdoll", false) then return false end
	if bLeftHand and ent == g_VR.heldEntityLeft then return false end
	if not bLeftHand and ent == g_VR.heldEntityRight then return false end
	if ent:IsWeapon() and ent:GetOwner() == ply then return false end
	return true
end

local function FindPickupTarget(ply, bLeftHand, handPos, handAng, pickupRange)
	-- Ensure a sane default
	if type(pickupRange) ~= "number" or pickupRange <= 0 then pickupRange = 1.2 end
	-- Compute grab origin in worldspace
	local grabOffset = Vector(3, bLeftHand and -1.5 or 1.5, 0)
	local grabPoint = LocalToWorld(grabOffset, Angle(), handPos, handAng)
	local radius = pickupRange * 100
	-- Gather candidates
	local candidates = {}
	for _, ent in ipairs(ents.FindInSphere(grabPoint, radius)) do
		-- Basic filters
		if ent == ply then continue end
		if not IsValidPickupTarget(ent, ply, bLeftHand) then continue end
		if not CanPickupEntity(ent, ply, convarValues or vrmod.GetConvars()) then continue end
		-- AABB “point-in-box” check around the entity
		local boost = IsImportantPickup(ent) and 5.5 or 1.0
		local localPos = WorldToLocal(grabPoint, Angle(), ent:GetPos(), ent:GetAngles())
		local mins, maxs = ent:OBBMins() * pickupRange * boost, ent:OBBMaxs() * pickupRange * boost
		if not localPos:WithinAABox(mins, maxs) then continue end
		-- Weapon‑specific rules
		if IsWeaponEntity(ent) then
			local aw = ply:GetActiveWeapon()
			if IsValid(aw) and aw:GetClass() == ent:GetClass() then continue end
			-- Prevent right‑hand from grabbing a second weapon if it already holds one
			if not bLeftHand and HasHeldWeaponRight(ply) then continue end
		end

		table.insert(candidates, ent)
	end

	-- Prioritize weapons
	for _, ent in ipairs(candidates) do
		if IsWeaponEntity(ent) then return ent end
	end
	-- Fallback: first valid candidate
	return candidates[1]
end

if CLIENT then
	CreateClientConVar("vrmod_pickup_halos", "1", true, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
	CreateClientConVar("vrmod_pickup_debug", "0", false, FCVAR_CLIENTCMD_CAN_EXECUTE + FCVAR_ARCHIVE)
	local pickupTargetEntLeft = nil
	local pickupTargetEntRight = nil
	local haloTargetsLeft = {}
	local haloTargetsRight = {}
	hook.Add("Tick", "vrmod_find_pickup_target", function()
		local ply = LocalPlayer()
		if not IsValid(ply) or not g_VR or not vrmod.IsPlayerInVR(ply) then return end
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
		if bDrop then
			net.Start("vrmod_pickup")
			net.WriteBool(bLeftHand)
			net.WriteBool(true)
			net.SendToServer()
			g_VR[bLeftHand and "heldEntityLeft" or "heldEntityRight"] = nil
		else
			local targetEnt = bLeftHand and pickupTargetEntLeft or pickupTargetEntRight
			local handSlot = bLeftHand and 1 or 2
			if g_VR[sid] and g_VR[sid].heldItems and g_VR[sid].heldItems[handSlot] then
				local ent = g_VR[sid].heldItems[handSlot].ent
				if not IsValid(ent) then g_VR[sid].heldItems[handSlot] = nil end
			end

			if IsValid(targetEnt) and not (g_VR[sid] and g_VR[sid].heldItems and g_VR[sid].heldItems[handSlot]) then
				net.Start("vrmod_pickup")
				net.WriteBool(bLeftHand)
				net.WriteBool(false)
				net.WriteEntity(targetEnt)
				net.SendToServer()
			end
		end
	end

	-- Handle server response
	net.Receive("vrmod_pickup", function()
		local ply, ent = net.ReadEntity(), net.ReadEntity()
		if not IsValid(ply) or not IsValid(ent) then return end
		local bDrop = net.ReadBool()
		if bDrop then
			if ent.RenderOverride == ent.VRPickupRenderOverride then
				ent.RenderOverride = nil
				ent.VRPickupRenderOverride = nil
			end

			hook.Call("VRMod_Drop", nil, ply, ent)
			return
		end

		local bLeftHand = net.ReadBool()
		local sid = ply:SteamID()
		if not g_VR.net[sid] then return end
		ent.VRPickupRenderOverride = function()
			-- Use VRMod API to get hand pos and angle instead of direct frame access
			local handPos, handAng, trace
			if bLeftHand then
				handPos = vrmod.GetLeftHandPos(ply)
				handAng = vrmod.GetLeftHandAng(ply)
				trace = vrmod.utils.TraceHand(ply, "left")
			else
				handPos = vrmod.GetRightHandPos(ply)
				handAng = vrmod.GetRightHandAng(ply)
				trace = vrmod.utils.TraceHand(ply, "right")
			end

			local offset = handAng:Forward() * (vrmod.DEFAULT_REACH * vrmod.DEFAULT_OFFSET)
			local finalPos
			if trace and IsValid(trace.Entity) and trace.Entity == ent then
				finalPos = handPos - trace.HitPos
			else
				finalPos = handPos + offset
			end

			ent:SetPos(finalPos)
			ent:SetupBones()
			ent:DrawModel()
		end

		ent.RenderOverride = ent.VRPickupRenderOverride
		if ply == LocalPlayer() then g_VR[bLeftHand and "heldEntityLeft" or "heldEntityRight"] = ent end
		hook.Call("VRMod_Pickup", nil, ply, ent)
	end)
end

if SERVER then
	util.AddNetworkString("vrmod_pickup")
	local pickupController, pickupList, pickupCount = nil, {}, 0
	-- Drop function
	function vrmod.Drop(steamid, bLeft)
		local function SendPickupNetMsg(ply, ent)
			net.Start("vrmod_pickup")
			net.WriteEntity(ply)
			net.WriteEntity(IsValid(ent) and ent or NULL)
			net.WriteBool(true)
			net.Broadcast()
		end

		local handVel = bLeft and vrmod.GetLeftHandVelocity(ply) or vrmod.GetRightHandVelocity(ply) or Vector(0, 0, 0)
		local handPos = bLeft and vrmod.GetLeftHandPos(ply) or vrmod.GetRightHandPos(ply) or Vector(0, 0, 0)
		local handAng = bLeft and vrmod.GetLeftHandAng(ply) or vrmod.GetRightHandAng(ply) or Angle(0, 0, 0)
		for i = 1, pickupCount do
			local t = pickupList[i]
			if t.steamid == steamid and t.left == bLeft then
				local ent = t.ent
				if IsValid(pickupController) and IsValid(t.phys) then pickupController:RemoveFromMotionController(t.phys) end
				if IsValid(ent) and ent.original_npc then
					local npc = ent.original_npc
					if IsValid(npc) and not vrmod.utils.IsRagdollDead(ent) then
						ent.dropped_manually = true
						ent.noDamage = true --preventing damage by the mass increase
						vrmod.utils.SetBoneMass(ent, 300, 0, handVel, 5)
						timer.Simple(0.1, function() if IsValid(ent) then ent:SetCollisionGroup(COLLISION_GROUP_NONE) end end)
						SendPickupNetMsg(t.ply, npc)
						if not vrmod.utils.IsRagdollDead(ent) then timer.Simple(3.0, function() ent:Remove() end) end
					else
						ent.dropped_manually = false
						if IsValid(ent) then ent:SetNWBool("is_npc_ragdoll", false) end
						SendPickupNetMsg(t.ply, ent)
					end
				elseif IsValid(ent) then
					ent:SetCollisionGroup(COLLISION_GROUP_NONE)
					if IsValid(t.phys) then
						local wpos, _ = LocalToWorld(ent:GetPos(), ent:GetAngles(), handPos, handAng)
						t.phys:SetPos(wpos)
						t.phys:SetVelocity(handVel)
						t.phys:Wake()
					end

					SendPickupNetMsg(t.ply, ent)
				else
					SendPickupNetMsg(t.ply, nil)
				end

				if g_VR[steamid] and g_VR[steamid].heldItems then g_VR[steamid].heldItems[bLeft and 1 or 2] = nil end
				table.remove(pickupList, i)
				pickupCount = pickupCount - 1
				if IsValid(ent) then ent.picked = false end
				if pickupCount == 0 and IsValid(pickupController) then
					pickupController:StopMotionController()
					pickupController:Remove()
					pickupController = nil
				end

				hook.Call("VRMod_Drop", nil, t.ply, t.ent)
				return
			end
		end
	end

	-- Pickup function
	function vrmod.Pickup(ply, bLeftHand, ent)
		local sid = ply:SteamID()
		if g_VR[sid] and g_VR[sid].heldItems and g_VR[sid].heldItems[bLeftHand and 1 or 2] then return end
		if not IsValid(ent) or not CanPickupEntity(ent, ply, convarValues) or hook.Call("VRMod_Pickup", nil, ply, ent) == false then return end
		if ent:IsNPC() then ent = vrmod.utils.SpawnPickupRagdoll(ply, ent) end
		ent.picked = true
		local handPos, handAng
		if bLeftHand then
			handPos = vrmod.GetLeftHandPos(ply)
			handAng = vrmod.GetLeftHandAng(ply)
		else
			handPos = vrmod.GetRightHandPos(ply)
			handAng = vrmod.GetRightHandAng(ply)
		end

		-- For ragdolls, store local offsets per physics bone relative to hand pose
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
				end
			end

			ent.vrmod_physOffsets = physOffsets
		end

		if not IsValid(pickupController) then
			pickupController = ents.Create("vrmod_pickup")
			pickupController.ShadowParams = {
				secondstoarrive = engine.TickInterval(),
				maxangular = 3000,
				maxangulardamp = 300,
				maxspeed = 3000,
				maxspeeddamp = 300,
				dampfactor = 0.3,
				teleportdistance = 0,
				deltatime = FrameTime()
			}

			function pickupController:PhysicsSimulate(phys, dt)
				phys:Wake()
				local info = phys:GetEntity().vrmod_pickup_info
				if not info then return end
				local ply = info.ply
				if not IsValid(ply) then return end
				local handPos, handAng
				if info.left then
					handPos = vrmod.GetLeftHandPos(ply)
					handAng = vrmod.GetLeftHandAng(ply)
				else
					handPos = vrmod.GetRightHandPos(ply)
					handAng = vrmod.GetRightHandAng(ply)
				end

				if not handPos or not handAng then return end
				-- Special case for ragdoll: apply per-physobj local offsets
				if phys:GetEntity():GetClass() == "prop_ragdoll" and phys:GetEntity().vrmod_physOffsets then
					local physIndex = nil
					-- Find physics index in ragdoll
					local ent = phys:GetEntity()
					for i = 0, ent:GetPhysicsObjectCount() - 1 do
						if ent:GetPhysicsObjectNum(i) == phys then
							physIndex = i
							break
						end
					end

					if physIndex and ent.vrmod_physOffsets[physIndex] then
						local offset = ent.vrmod_physOffsets[physIndex]
						self.ShadowParams.pos, self.ShadowParams.angle = LocalToWorld(offset.localPos, offset.localAng, handPos, handAng)
						phys:ComputeShadowControl(self.ShadowParams)
						return
					end
				end

				-- Default fallback: use stored localPos/localAng for non-ragdolls
				self.ShadowParams.pos, self.ShadowParams.angle = LocalToWorld(info.localPos, info.localAng, handPos, handAng)
				phys:ComputeShadowControl(self.ShadowParams)
			end

			pickupController:StartMotionController()
		end

		local index = pickupCount + 1
		for k, v2 in ipairs(pickupList) do
			if v2.ent == ent then
				index = k
				g_VR[v2.steamid].heldItems[v2.left and 1 or 2] = nil
				break
			end
		end

		if index > pickupCount then
			pickupCount = pickupCount + 1
			if ent:GetClass() == "prop_ragdoll" then vrmod.utils.SetBoneMass(ent, 15, 0.5) end
			local phys = ent:GetPhysicsObject()
			if IsValid(phys) then
				pickupController:AddToMotionController(phys)
				phys:Wake()
			end
		end

		-- For non-ragdoll, store localPos/localAng relative to hand pose for entity root
		local lpos, lang
		if ent:GetClass() ~= "prop_ragdoll" then
			lpos, lang = WorldToLocal(ent:GetPos(), ent:GetAngles(), handPos, handAng)
		else
			lpos, lang = Vector(0, 0, 0), Angle(0, 0, 0) -- Not used for ragdolls, since per-physobj offsets exist
		end

		pickupList[index] = {
			ent = ent,
			phys = ent:GetPhysicsObject(),
			left = bLeftHand,
			localPos = lpos,
			localAng = lang,
			collisionGroup = ent:GetCollisionGroup(),
			steamid = sid,
			ply = ply
		}

		g_VR[sid].heldItems = g_VR[sid].heldItems or {}
		g_VR[sid].heldItems[bLeftHand and 1 or 2] = pickupList[index]
		ent.vrmod_pickup_info = pickupList[index]
		ent:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)
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
		if bDrop then
			vrmod.Drop(ply:SteamID(), bLeft)
		else
			local ent = net.ReadEntity()
			vrmod.Pickup(ply, bLeft, ent)
		end
	end)

	local function UpdatePickupFlags()
		for _, ply in ipairs(player.GetAll()) do
			local nearbyEntities = ents.FindInSphere(ply:GetPos(), 300) -- adjust radius as needed
			local cv = {
				vrmod_pickup_npcs = GetConVar("vrmod_pickup_npcs"):GetInt(),
				vrmod_pickup_limit = GetConVar("vrmod_pickup_limit"):GetInt(),
				vrmod_pickup_weight = GetConVar("vrmod_pickup_weight"):GetFloat()
			}

			for _, ent in ipairs(nearbyEntities) do
				local canPickup = CanPickupEntity(ent, ply, cv)
				ent:SetNWBool("vrmod_pickup_valid_for_" .. ply:SteamID(), canPickup)
			end
		end
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