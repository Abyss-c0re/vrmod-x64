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

local function IsValidPickupTarget(ent, ply, handHeld)
	if not IsValid(ent) then return false end
	if ent:GetNoDraw() then return false end
	if ent:IsDormant() then return false end
	if blacklistedClasses[ent:GetClass()] then return false end
	if ent:GetNWBool("vrmod_is_npc_ragdoll", false) then return false end
	if ent == g_VR.heldEntityLeft or ent == g_VR.heldEntityRight then return false end
	if handHeld then return false end
	if ent:IsWeapon() and ent:GetOwner() == ply then return false end
	return true
end

local function FindPickupTarget(ply, bLeftHand, handPos, handAng, pickupRange)
	if type(pickupRange) ~= "number" or pickupRange <= 0 then pickupRange = 1.2 end
	local heldItems
	if SERVER then
		local sid = ply:SteamID()
		if g_VR[sid] and g_VR[sid].heldItems then heldItems = g_VR[sid].heldItems end
	else
		if ply == LocalPlayer() and g_VR and g_VR.heldItems then heldItems = g_VR.heldItems end
	end

	local slot = bLeftHand and 1 or 2
	if heldItems and heldItems[slot] then
		local ent = heldItems[slot].ent
		if not IsValid(ent) then
			heldItems[slot] = nil
		else
			return
		end
	end

	local cv = convarValues or vrmod.GetConvars()
	local grabPoint = LocalToWorld(Vector(3, bLeftHand and -1.5 or 1.5, 0), Angle(), handPos, handAng)
	local radius = pickupRange * 100
	local candidates = {}
	for _, ent in ipairs(ents.FindInSphere(grabPoint, radius)) do
		if ent == ply then continue end
		if not IsValidPickupTarget(ent, ply, bLeftHand) then continue end
		if not CanPickupEntity(ent, ply, cv) then continue end
		local boostFactor = IsImportantPickup(ent) and 3.5 or 1.0
		local lp = WorldToLocal(grabPoint, Angle(), ent:GetPos(), ent:GetAngles())
		if not lp:WithinAABox(ent:OBBMins() * pickupRange * boostFactor, ent:OBBMaxs() * pickupRange * boostFactor) then continue end
		if IsWeaponEntity(ent) then
			local aw = ply:GetActiveWeapon()
			if IsValid(aw) and aw:GetClass() == ent:GetClass() then continue end
			if not bLeftHand and HasHeldWeaponRight(ply) then continue end
		end

		table.insert(candidates, ent)
	end

	for _, ent in ipairs(candidates) do
		if IsWeaponEntity(ent) then return ent end
	end
	return candidates[1]
end

if CLIENT then
	local haloEnabled = true
	local pickupTargetEntRight = nil
	local haloTargets = {}
	vrmod.AddCallbackedConvar("vrmod_pickup_halos", nil, "1", FCVAR_REPLICATED + FCVAR_ARCHIVE + FCVAR_NOTIFY, "Toggle pickup halos", nil, nil, tobool, function(val) haloEnabled = val end)
	hook.Add("Tick", "vrmod_find_pickup_target", function()
		local ply = LocalPlayer()
		local pickupRange = GetConVar("vrmod_pickup_range"):GetFloat()
		if not IsValid(ply) or not g_VR then return end
		if not vrmod.IsPlayerInVR(ply) then return end
		local rightHand = g_VR.tracking and g_VR.tracking.pose_righthand
		if rightHand then
			local handPos, handAng = rightHand.pos, rightHand.ang
			pickupTargetEntRight = FindPickupTarget(ply, false, handPos, handAng, pickupRange) -- pass the updated pickupRange here
		else
			pickupTargetEntRight = nil
		end

		local leftHand = g_VR.tracking and g_VR.tracking.pose_lefthand
		if leftHand then
			local handPos, handAng = leftHand.pos, leftHand.ang
			pickupTargetEntLeft = FindPickupTarget(ply, true, handPos, handAng, pickupRange) -- pass the updated pickupRange here
		else
			pickupTargetEntLeft = nil
		end
	end)

	hook.Add("PostDrawOpaqueRenderables", "vrmod_draw_pickup_halo", function()
		if not haloEnabled then return end
		table.Empty(haloTargets)
		local heldLeft = g_VR.heldEntityLeft
		local heldRight = g_VR.heldEntityRight
		local function IsRagdoll(ent)
			return ent:GetNWBool("vrmod_is_npc_ragdoll", false)
		end

		if not heldLeft and IsValidPickupTarget(pickupTargetEntLeft, LocalPlayer(), false) and not IsRagdoll(pickupTargetEntLeft) then table.insert(haloTargets, pickupTargetEntLeft) end
		if not heldRight and IsValidPickupTarget(pickupTargetEntRight, LocalPlayer(), false) and not IsRagdoll(pickupTargetEntRight) then table.insert(haloTargets, pickupTargetEntRight) end
	end)

	hook.Add("PreDrawHalos", "vrmod_render_pickup_halo", function()
		if not haloEnabled then return end
		if haloTargets and #haloTargets > 0 then
			-- for i, ent in ipairs(haloTargets) do
			-- 	if IsValid(ent) then
			-- 		print(string.format("Halo Target %d: Class=%s Model=%s Owner=%s", i, ent:GetClass() or "nil", ent:GetModel() or "nil", IsValid(ent:GetOwner()) and ent:GetOwner():Nick() or "none"))
			-- 	else
			-- 		print("Halo Target " .. i .. ": invalid entity")
			-- 	end
			-- end
			halo.Add(haloTargets, Color(0, 255, 255), 2, 2, 1, true, true)
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
	local function ForwardRagdollDamage(ent, dmginfo)
		if not (ent:IsRagdoll() and IsValid(ent.vr_original_npc)) then return end
		local npc = ent.vr_original_npc
		local dmg = dmginfo:GetDamage()
		npc:SetHealth(math.max(0, npc:Health() - dmg))
		local force = dmginfo:GetDamageForce() or Vector(0, 0, 0)
		if not force:IsZero() then
			local physCount = ent:GetPhysicsObjectCount()
			for i = 0, physCount - 1 do
				local phys = ent:GetPhysicsObjectNum(i)
				if IsValid(phys) then phys:ApplyForceCenter(force) end
			end
		end
	end

	local function SpawnPickupRagdoll(npc)
		if not IsValid(npc) then return end
		-- 1) Create the ragdoll immediately
		local rag = ents.Create("prop_ragdoll")
		if not IsValid(rag) then return end
		rag:SetModel(npc:GetModel())
		rag:SetNWBool("vrmod_is_npc_ragdoll", true)
		rag:SetPos(npc:GetPos())
		rag:SetAngles(npc:GetAngles())
		rag:Spawn()
		rag:Activate()
		-- 2) Copy bones in a next-tick timer
		timer.Simple(0, function()
			if not (IsValid(npc) and IsValid(rag)) then return end
			if npc.SetupBones then npc:SetupBones() end
			for i = 0, (npc.GetBoneCount and npc:GetBoneCount() or 0) - 1 do
				local pos, ang = npc:GetBonePosition(i)
				if pos and ang and rag.SetBonePosition then rag:SetBonePosition(i, pos, ang) end
			end

			for i = 0, (rag.GetPhysicsObjectCount and rag:GetPhysicsObjectCount() or 0) - 1 do
				local phys = rag:GetPhysicsObjectNum(i)
				if IsValid(phys) then
					phys:EnableMotion(true)
					phys:Wake()
				end
			end
		end)

		-- 3) Fully disable & hide the original NPC
		rag.vr_original_npc = npc
		rag.vr_dropped_manually = false
		hook.Add("EntityTakeDamage", "VRMod_ForwardRagdollDamage", ForwardRagdollDamage)
		npc:SetNoDraw(true)
		npc:SetNotSolid(true)
		npc:SetMoveType(MOVETYPE_NONE)
		npc:SetCollisionGroup(COLLISION_GROUP_VEHICLE)
		npc:ClearSchedule()
		if npc.StopMoving then npc:StopMoving() end
		-- **Silence AI & thinking completely**
		npc:AddEFlags(EFL_NO_THINK_FUNCTION) -- stops Think() calls
		if npc.SetNPCState then npc:SetNPCState(NPC_STATE_NONE) end
		npc:SetSaveValue("m_bInSchedule", false) -- stop any running schedule
		if npc.GetActiveWeapon and IsValid(npc:GetActiveWeapon()) then npc:GetActiveWeapon():Remove() end
		-- 4) On rag removal, restore or remove the NPC
		rag:CallOnRemove("vrmod_cleanup_npc_" .. rag:EntIndex(), function()
			if not IsValid(npc) then return end
			-- re-enable thinking
			npc:RemoveEFlags(EFL_NO_THINK_FUNCTION)
			if rag.vr_dropped_manually then
				-- Restore NPC at rag’s last pose
				local p, a = rag:GetPos(), rag:GetAngles()
				npc:SetPos(p)
				npc:SetAngles(a)
				npc:SetNoDraw(false)
				npc:SetNotSolid(false)
				npc:SetMoveType(MOVETYPE_STEP)
				npc:SetCollisionGroup(COLLISION_GROUP_NONE)
				npc:ClearSchedule()
				npc:SetSaveValue("m_bInSchedule", false)
				if npc.SetNPCState then npc:SetNPCState(NPC_STATE_ALERT) end
				npc:DropToFloor()
				-- Restart thinking/AI
				if npc.BehaveStart then pcall(npc.BehaveStart, npc) end
				npc:SetSchedule(SCHED_IDLE_STAND)
				npc:NextThink(CurTime())
			else
				-- Rag was gibbed: kill the NPC too
				npc:Remove()
			end

			hook.Remove("EntityTakeDamage", "VRMod_ForwardRagdollDamage")
		end)
		return rag
	end

	local function IsRagdollGibbed(ent)
		-- 0) Missing or invalid entity → treat as gibbed
		if not IsValid(ent) then return true end
		-- 0) Zero HP is gibbed too
		local npc = ent.vr_original_npc
		if IsValid(npc) and npc:Health() <= 0 then return true end
		-- 2) Look for Zippy’s health table, only if it exists
		local hpTable = ent.ZippyGoreMod3_PhysBoneHPs
		if type(hpTable) == "table" then
			for boneIndex, hp in pairs(hpTable) do
				if hp == -1 then return true end
			end
		end

		-- 3) Look for Zippy’s gib‑flag table, only if it exists
		local gibTable = ent.ZippyGoreMod3_GibbedPhysBones
		if type(gibTable) == "table" then
			for boneIndex, wasGibbed in pairs(gibTable) do
				if wasGibbed then return true end
			end
		end

		-- 4) If neither table is there, Zippy is disabled or not applied—assume “not gibbed”
		if hpTable == nil and gibTable == nil then return false end
		-- 5) Physics‐object count heuristic (only if we have a hpTable)
		if type(hpTable) == "table" then
			local expectedBones = table.Count(hpTable)
			if ent:GetPhysicsObjectCount() < expectedBones then return true end
		end
		-- No evidence of gibbing
		return false
	end

	-- Drop function
	local function drop(steamid, bLeft)
		for i = 1, pickupCount do
			local t = pickupList[i]
			if t.steamid == steamid and t.left == bLeft then
				local ent = t.ent
				if IsValid(pickupController) and IsValid(t.phys) then pickupController:RemoveFromMotionController(t.phys) end
				if IsValid(ent) and ent.vr_original_npc then
					local npc = ent.vr_original_npc
					if IsValid(npc) and not IsRagdollGibbed(ent) then
						ent.vr_dropped_manually = true
						local entCopy = ent
						timer.Simple(2.0, function() if IsValid(entCopy) then entCopy:Remove() end end)
						net.Start("vrmod_pickup")
						net.WriteEntity(t.ply)
						net.WriteEntity(npc)
						net.WriteBool(true)
						net.Broadcast()
					else
						ent.vr_dropped_manually = false
						if IsValid(ent) then ent:SetNWBool("vrmod_is_npc_ragdoll", false) end
						net.Start("vrmod_pickup")
						net.WriteEntity(t.ply)
						net.WriteEntity(IsValid(ent) and ent or NULL)
						net.WriteBool(true)
						net.Broadcast()
					end

					hook.Remove("EntityTakeDamage", "VRMod_ForwardRagdollDamage")
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
	local function pickup(ply, bLeftHand, ent)
		local sid = ply:SteamID()
		if g_VR[sid] and g_VR[sid].heldItems and g_VR[sid].heldItems[bLeftHand and 1 or 2] then return end
		if not IsValid(ent) or not CanPickupEntity(ent, ply, convarValues) or hook.Call("VRMod_Pickup", nil, ply, ent) == false then return end
		if ent:IsNPC() then ent = SpawnPickupRagdoll(ent) end
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
			drop(ply:SteamID(), bLeft)
		else
			local ent = net.ReadEntity()
			pickup(ply, bLeft, ent)
		end
	end)

	hook.Add("PlayerDeath", "vrmod_drop_items_on_death", function(ply)
		if not IsValid(ply) then return end
		local sid = ply:SteamID()
		-- Force drop for both hands
		drop(sid, true)
		drop(sid, false)
	end)

	hook.Add("AllowPlayerPickup", "vrmod", function(ply) return not g_VR[ply:SteamID()] end)
end