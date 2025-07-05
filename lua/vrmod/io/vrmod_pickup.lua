g_VR = g_VR or {}
vrmod = vrmod or {}
scripted_ents.Register({
	Type = "anim",
	Base = "vrmod_pickup"
}, "vrmod_pickup")

local _, convarValues = vrmod.GetConvars()
vrmod.AddCallbackedConvar("vrmod_pickup_limit", nil, 1, FCVAR_REPLICATED + FCVAR_NOTIFY + FCVAR_ARCHIVE, "", 0, 3, tonumber)
vrmod.AddCallbackedConvar("vrmod_pickup_range", nil, 1.2, FCVAR_REPLICATED + FCVAR_ARCHIVE, "", 0.0, 999.0, tonumber)
vrmod.AddCallbackedConvar("vrmod_pickup_weight", nil, 150, FCVAR_REPLICATED + FCVAR_ARCHIVE, "", 0, 10000, tonumber)
if CLIENT then
	function vrmod.Pickup(bLeftHand, bDrop)
		local pose = bLeftHand and g_VR.tracking.pose_lefthand or g_VR.tracking.pose_righthand
		net.Start("vrmod_pickup")
		net.WriteBool(bLeftHand)
		net.WriteBool(bDrop)
		net.WriteVector(pose.pos)
		net.WriteAngle(pose.ang)
		if bDrop then
			net.WriteVector(pose.vel)
			net.WriteVector(pose.angvel)
			g_VR[bLeftHand and "heldEntityLeft" or "heldEntityRight"] = nil
		end

		net.SendToServer()
	end

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
			local frame = g_VR.net[sid].lerpedFrame
			if not frame then return end
			local handPos, handAng
			if bLeftHand then
				handPos, handAng = frame.lefthandPos, frame.lefthandAng
			else
				handPos, handAng = frame.righthandPos, frame.righthandAng
			end

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
elseif SERVER then
	util.AddNetworkString("vrmod_pickup")
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
		if not IsValid(v) or not IsValid(v:GetPhysicsObject()) or v == ply or ply:InVehicle() then return false end
		local phys = v:GetPhysicsObject()
		if cv.vrmod_pickup_limit == 1 then return v:GetMoveType() == MOVETYPE_VPHYSICS and phys:GetMass() <= cv.vrmod_pickup_weight end
		return true
	end

	local function shouldPickUp(ent)
		if ent:GetNoDraw() then return false end
		return true
	end

	local function FindPickupTarget(ply, bLeftHand, handPos, handAng)
		local sid = ply:SteamID()
		if g_VR[sid] and g_VR[sid].heldItems and g_VR[sid].heldItems[bLeftHand and 1 or 2] then return end
		local cv = convarValues
		local baseRange = cv.vrmod_pickup_range * 100
		local boostedRange = cv.vrmod_pickup_range * 250
		local grabPoint = LocalToWorld(Vector(3, bLeftHand and -1.5 or 1.5, 0), Angle(), handPos, handAng)
		local candidates = {}
		for _, ent in ipairs(ents.FindInSphere(grabPoint, baseRange + boostedRange)) do
			if not shouldPickUp(ent) or not CanPickupEntity(ent, ply, cv) then continue end
			local isWep = IsWeaponEntity(ent)
			local isImportant = isWep or IsImportantPickup(ent)
			local boost = isImportant and boostedRange or 0
			local testRng = cv.vrmod_pickup_range + boost / 100
			local lp = WorldToLocal(grabPoint, Angle(), ent:GetPos(), ent:GetAngles())
			if not lp:WithinAABox(ent:OBBMins() * testRng, ent:OBBMaxs() * testRng) then continue end
			if isWep then
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

	local pickupController, pickupList, pickupCount = nil, {}, 0
	function drop(steamid, bLeft, handPos, handAng, handVel, handAngVel)
		for i = 1, pickupCount do
			local t = pickupList[i]
			if t and t.steamid == steamid and t.left == bLeft then
				if IsValid(t.phys) and IsValid(t.ent) then
					local phys, ent = t.phys, t.ent
					pickupController:RemoveFromMotionController(phys)
					ent:SetCollisionGroup(t.collisionGroup or COLLISION_GROUP_NONE)
					if handPos then
						local wpos, wang = LocalToWorld(t.localPos, t.localAng, handPos, handAng)
						phys:SetPos(wpos)
						phys:SetAngles(wang)
						phys:SetVelocity(t.ply:GetVelocity() + handVel)
						phys:AddAngleVelocity(-phys:GetAngleVelocity() + phys:WorldToLocalVector(handAngVel))
						phys:Wake()
					end
				end

				net.Start("vrmod_pickup")
				net.WriteEntity(t.ply)
				net.WriteEntity(t.ent)
				net.WriteBool(true)
				net.Broadcast()
				g_VR[steamid].heldItems[bLeft and 1 or 2] = nil
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

	local function pickup(ply, bLeftHand, handPos, handAng)
		local sid = ply:SteamID()
		if g_VR[sid] and g_VR[sid].heldItems and g_VR[sid].heldItems[bLeftHand and 1 or 2] then return end
		local ent = FindPickupTarget(ply, bLeftHand, handPos, handAng)
		if not IsValid(ent) or hook.Call("VRMod_Pickup", nil, ply, ent) == false then return end
		-- Ragdoll position fix
		if ent:GetClass() == "prop_ragdoll" then
			local delta = handPos - ent:GetPos()
			for i = 0, ent:GetPhysicsObjectCount() - 1 do
				local phys = ent:GetPhysicsObjectNum(i)
				if IsValid(phys) then phys:SetPos(phys:GetPos() - delta) end
			end

			ent:SetAngles(handAng)
		end

		if not IsValid(pickupController) then
			pickupController = ents.Create("vrmod_pickup")
			pickupController.ShadowParams = {
				secondstoarrive = 0.0001,
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
				local frame = g_VR[info.steamid].latestFrame
				if not frame then return end
				local hp, ha = LocalToWorld(info.left and frame.lefthandPos or frame.righthandPos, info.left and frame.lefthandAng or frame.righthandAng, info.ply:GetPos(), Angle())
				self.ShadowParams.pos, self.ShadowParams.angle = LocalToWorld(info.localPos, info.localAng, hp, ha)
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

		local lpos, lang = WorldToLocal(ent:GetPos(), ent:GetAngles(), handPos, handAng)
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
		local pos, ang = net.ReadVector(), net.ReadAngle()
		if bDrop then
			local vel, angVel = net.ReadVector(), net.ReadVector()
			drop(ply:SteamID(), bLeft, pos, ang, vel, angVel)
		else
			pickup(ply, bLeft, pos, ang)
		end
	end)

	hook.Add("AllowPlayerPickup", "vrmod", function(ply) return not g_VR[ply:SteamID()] end)
end