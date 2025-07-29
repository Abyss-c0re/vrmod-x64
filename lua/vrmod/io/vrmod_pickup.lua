g_VR = g_VR or {}
vrmod = vrmod or {}
scripted_ents.Register({
	Type = "anim",
	Base = "vrmod_pickup"
}, "vrmod_pickup")

local blacklistedClasses = {
	-- Physgun / Gravity Gun Beams
	["physgun_beam"] = true,
	["physcannon_beam"] = true,
	["physcannon_laser"] = true,
	-- Effects / Invisible entities
	["env_sprite"] = true,
	["env_projectedtexture"] = true,
	["env_beam"] = true,
	["env_smoketrail"] = true,
	["env_spritetrail"] = true,
	["env_fire"] = true,
	["env_firesource"] = true,
	["env_explosion"] = true,
	["point_spotlight"] = true,
	["light_dynamic"] = true,
	["shadow_control"] = true,
	-- Toolgun Effects
	["gmod_tool"] = true,
	["gmod_hoverball"] = true,
	["gmod_camera"] = true,
	-- Scripted Weapon Auxiliary Entities (common examples)
	["sent_turret"] = true,
	["npc_turret_floor"] = true,
	-- Misc Helpers
	["class C_BaseFlex"] = true, -- base for some clientside models; exclude if needed
	-- Particle effects and decals (if ever created as entities)
	["info_particle_system"] = true,
	-- Viewmodels (usually clientside)
	["class C_BaseViewModel"] = true,
}

local _, convarValues = vrmod.GetConvars()
vrmod.AddCallbackedConvar("vrmod_pickup_limit", nil, 1, FCVAR_REPLICATED + FCVAR_NOTIFY + FCVAR_ARCHIVE, "", 0, 3, tonumber)
vrmod.AddCallbackedConvar("vrmod_pickup_range", nil, 1.2, FCVAR_REPLICATED + FCVAR_ARCHIVE, "", 0.0, 999.0, tonumber)
vrmod.AddCallbackedConvar("vrmod_pickup_weight", nil, 150, FCVAR_REPLICATED + FCVAR_ARCHIVE, "", 0, 10000, tonumber)
vrmod.AddCallbackedConvar("vrmod_pickup_npcs", nil, 0, FCVAR_REPLICATED + FCVAR_NOTIFY + FCVAR_ARCHIVE, "", 0, 3, tonumber)
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

local function IsValidPickupTarget(ent, ply, bLeftHand)
	if not IsValid(ent) then return false end
	if ent:GetNoDraw() then return false end
	if ent:IsDormant() then return false end
	local class = ent:GetClass()
	if blacklistedClasses[class] then return false end
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
		local boost = IsImportantPickup(ent) and 3.5 or 1.0
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
	local haloEnabled = true
	local pickupTargetEntRight = nil
	local haloTargetsLeft = {}
	local haloTargetsRight = {}
	vrmod.AddCallbackedConvar("vrmod_pickup_halos", nil, "1", FCVAR_REPLICATED + FCVAR_ARCHIVE + FCVAR_NOTIFY, "Toggle pickup halos", nil, nil, tobool, function(val) haloEnabled = val end)
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
		if not haloEnabled then return end
		table.Empty(haloTargetsLeft)
		table.Empty(haloTargetsRight)
		local ply = LocalPlayer()
		local heldLeft, heldRight = g_VR.heldEntityLeft, g_VR.heldEntityRight
		local function IsRagdoll(ent)
			return IsValid(ent) and ent:GetNWBool("is_npc_ragdoll", false)
		end

		local holdingRagdoll = IsRagdoll(heldLeft) or IsRagdoll(heldRight)
		local function ShouldAddHalo(ent, heldEnt)
			return IsValid(ent) and ent ~= heldLeft and ent ~= heldRight and IsValidPickupTarget(ent, ply, false) and not holdingRagdoll
		end

		if ShouldAddHalo(pickupTargetEntLeft) then haloTargetsLeft[#haloTargetsLeft + 1] = pickupTargetEntLeft end
		if ShouldAddHalo(pickupTargetEntRight) then haloTargetsRight[#haloTargetsRight + 1] = pickupTargetEntRight end
	end)

	hook.Add("PreDrawHalos", "vrmod_render_pickup_halo", function()
		if not haloEnabled then return end
		if #haloTargetsLeft > 0 then halo.Add(haloTargetsLeft, Color(255, 100, 0), 2, 2, 1, true, true) end
		if #haloTargetsRight > 0 then
			halo.Add(haloTargetsRight, Color(0, 255, 255), 2, 2, 1, true, true)
			-- for i, ent in ipairs(haloTargetsRight) do
			-- 	if IsValid(ent) then
			-- 		print(string.format("Halo Target %d: Class=%s Model=%s Owner=%s", i, ent:GetClass() or "nil", ent:GetModel() or "nil", IsValid(ent:GetOwner()) and ent:GetOwner():Nick() or "none"))
			-- 	else
			-- 		print("Halo Target " .. i .. ": invalid entity")
			-- 	end
			-- end
		end
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
		local lp, la = net.ReadVector(), net.ReadAngle()
		if not la or la == Angle(0, 0, 0) then return end
		local sid = ply:SteamID()
		if not g_VR.net[sid] then return end
		ent.VRPickupRenderOverride = function()
			-- Use VRMod API to get hand pos and angle instead of direct frame access
			local handPos, handAng
			if bLeftHand then
				handPos = vrmod.GetLeftHandPos(ply)
				handAng = vrmod.GetLeftHandAng(ply)
			else
				handPos = vrmod.GetRightHandPos(ply)
				handAng = vrmod.GetRightHandAng(ply)
			end

			if not handPos or not handAng then return end
			local wpos, wang = LocalToWorld(lp, la, handPos, handAng)
			if not wang then return end
			ent:SetPos(wpos)
			ent:SetAngles(wang)
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
		for i = 1, pickupCount do
			local t = pickupList[i]
			if t.steamid == steamid and t.left == bLeft then
				local ent = t.ent
				if IsValid(pickupController) and IsValid(t.phys) then pickupController:RemoveFromMotionController(t.phys) end
				if IsValid(ent) and ent.original_npc then
					local npc = ent.original_npc
					if IsValid(npc) and not vrmod.utils.IsRagdollGibbed(ent) then
						ent.dropped_manually = true
						local entCopy = ent
						timer.Simple(2.0, function() if IsValid(entCopy) then entCopy:Remove() end end)
						net.Start("vrmod_pickup")
						net.WriteEntity(t.ply)
						net.WriteEntity(npc)
						net.WriteBool(true)
						net.Broadcast()
					else
						ent.dropped_manually = false
						if IsValid(ent) then ent:SetNWBool("is_npc_ragdoll", false) end
						net.Start("vrmod_pickup")
						net.WriteEntity(t.ply)
						net.WriteEntity(IsValid(ent) and ent or NULL)
						net.WriteBool(true)
						net.Broadcast()
					end
				elseif IsValid(ent) then
					ent:SetCollisionGroup(COLLISION_GROUP_NONE)
					if IsValid(t.phys) then
						t.phys:SetPos(ent:GetPos())
						t.phys:SetAngles(ent:GetAngles())
						t.phys:SetVelocity(t.ply:GetVelocity())
						t.phys:Wake()
					end

					net.Start("vrmod_pickup")
					net.WriteEntity(t.ply)
					net.WriteEntity(ent)
					net.WriteBool(true)
					net.Broadcast()
				else
					net.Start("vrmod_pickup")
					net.WriteEntity(t.ply)
					net.WriteEntity(NULL)
					net.WriteBool(true)
					net.Broadcast()
				end

				if g_VR[steamid] and g_VR[steamid].heldItems then g_VR[steamid].heldItems[bLeft and 1 or 2] = nil end
				table.remove(pickupList, i)
				pickupCount = pickupCount - 1
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
		if ent:IsNPC() then ent = vrmod.utils.SpawnPickupRagdoll(ent) end
		local handPos, handAng
		if bLeftHand then
			handPos = vrmod.GetLeftHandPos(ply)
			handAng = vrmod.GetLeftHandAng(ply)
		else
			handPos = vrmod.GetRightHandPos(ply)
			handAng = vrmod.GetRightHandAng(ply)
		end

		if not handPos or not handAng then return end
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
				maxangular = 5000,
				maxangulardamp = 5000,
				maxspeed = 1e6,
				maxspeeddamp = 1e4,
				dampfactor = 0.5,
				teleportdistance = 0,
				deltatime = 0
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
			timer.Simple(0, function() end)
			pickupCount = pickupCount + 1
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
		net.WriteVector(lpos)
		net.WriteAngle(lang)
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

	hook.Add("PlayerDeath", "vrmod_drop_items_on_death", function(ply)
		if not IsValid(ply) then return end
		local sid = ply:SteamID()
		-- Force drop for both hands
		vrmod.Drop(sid, true)
		vrmod.Drop(sid, false)
	end)

	hook.Add("AllowPlayerPickup", "vrmod", function(ply) return not g_VR[ply:SteamID()] end)
end