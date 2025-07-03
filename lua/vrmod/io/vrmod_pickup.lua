g_VR = g_VR or {}
vrmod = vrmod or {}
scripted_ents.Register({
	Type = "anim",
	Base = "vrmod_pickup"
}, "vrmod_pickup")

local _, convarValues = vrmod.GetConvars()
vrmod.AddCallbackedConvar("vrmod_pickup_limit", nil, 1, FCVAR_REPLICATED + FCVAR_NOTIFY + FCVAR_ARCHIVE, "", 0, 3, tonumber) --cvarName, valueName, defaultValue, flags, helptext, min, max, conversionFunc, callbackFunc --cvarName, valueName, defaultValue, flags, helptext, min, max, conversionFunc, callbackFunc
vrmod.AddCallbackedConvar("vrmod_pickup_range", nil, 1.3, FCVAR_REPLICATED + FCVAR_ARCHIVE, "", 0.0, 999.0, tonumber) --cvarName, valueName, defaultValue, flags, helptext, min, max, conversionFunc, callbackFunc
vrmod.AddCallbackedConvar("vrmod_pickup_weight", nil, 150, FCVAR_REPLICATED + FCVAR_ARCHIVE, "", 0, 10000, tonumber)
local function CanPickupEntity(v, ply, convarValues)
	if not IsValid(v) or not IsValid(v:GetPhysicsObject()) or v == ply or ply:InVehicle() then return false end
	local phys = v:GetPhysicsObject()
	local limitEnabled = convarValues.vrmod_pickup_limit == 1
	local weightLimit = convarValues.vrmod_pickup_weight
	if limitEnabled then
		return v:GetMoveType() == MOVETYPE_VPHYSICS and phys:GetMass() <= weightLimit
	else
		return true
	end
end

--cvarName, valueName, defaultValue, flags, helptext, min, max, conversionFunc, callbackFunc
if CLIENT then
	function vrmod.Pickup(bLeftHand, bDrop)
		net.Start("vrmod_pickup")
		net.WriteBool(bLeftHand)
		net.WriteBool(bDrop or false)
		local pose = bLeftHand and g_VR.tracking.pose_lefthand or g_VR.tracking.pose_righthand
		net.WriteVector(pose.pos)
		net.WriteAngle(pose.ang)
		if bDrop then
			net.WriteVector(pose.vel)
			net.WriteVector(pose.angvel)
			g_VR[bLeftHand and "heldEntityLeft" or "heldEntityRight"] = nil
		end

		net.SendToServer()
	end

	net.Receive("vrmod_pickup", function(len)
		local ply = net.ReadEntity()
		local ent = net.ReadEntity()
		local bDrop = net.ReadBool()
		if bDrop then
			--print("client received drop")
			if IsValid(ent) and ent.RenderOverride == ent.VRPickupRenderOverride then ent.RenderOverride = nil end
			hook.Call("VRMod_Drop", nil, ply, ent)
		else
			local bLeftHand = net.ReadBool()
			local localPos = net.ReadVector()
			local localAng = net.ReadAngle()
			--
			local steamid = IsValid(ply) and ply:SteamID()
			if g_VR.net[steamid] == nil then return end
			--
			ent.RenderOverride = function()
				if g_VR.net[steamid] == nil then return end
				local wpos, wang
				if bLeftHand then
					wpos, wang = LocalToWorld(localPos, localAng, g_VR.net[steamid].lerpedFrame.lefthandPos, g_VR.net[steamid].lerpedFrame.lefthandAng)
				else
					wpos, wang = LocalToWorld(localPos, localAng, g_VR.net[steamid].lerpedFrame.righthandPos, g_VR.net[steamid].lerpedFrame.righthandAng)
				end

				ent:SetPos(wpos)
				ent:SetAngles(wang)
				ent:SetupBones()
				ent:DrawModel()
			end

			ent.VRPickupRenderOverride = ent.RenderOverride
			if ply == LocalPlayer() then g_VR[bLeftHand and "heldEntityLeft" or "heldEntityRight"] = ent end
			--]]
			hook.Call("VRMod_Pickup", nil, ply, ent)
		end
	end)
elseif SERVER then
	util.AddNetworkString("vrmod_pickup")
	local pickupController = nil
	local pickupList = {}
	local pickupCount = 0
	function drop(steamid, bLeftHand, handPos, handAng, handVel, handAngVel)
		for i = 1, pickupCount do
			local t = pickupList[i]
			if not t then continue end
			if t.steamid ~= steamid or t.left ~= bLeftHand then continue end
			local phys = t.phys
			if not istable(t) or not t.ent then
				drop(t.steamid, t.left)
				break
			end

			if IsValid(phys) and IsValid(t.ent) then
				t.ent:SetCollisionGroup(t.collisionGroup)
				pickupController:RemoveFromMotionController(phys)
				if handPos then
					local wPos, wAng = LocalToWorld(t.localPos, t.localAng, handPos, handAng)
					phys:SetPos(wPos)
					phys:SetAngles(wAng)
					phys:SetVelocity(t.ply:GetVelocity() + handVel)
					phys:AddAngleVelocity(-phys:GetAngleVelocity() + phys:WorldToLocalVector(handAngVel))
					phys:Wake()
				end
			end

			net.Start("vrmod_pickup")
			net.WriteEntity(t.ply)
			net.WriteEntity(t.ent)
			net.WriteBool(true) --drop
			net.Broadcast()
			if g_VR[t.steamid] then g_VR[t.steamid].heldItems[bLeftHand and 1 or 2] = nil end
			pickupList[i] = pickupList[pickupCount]
			pickupList[pickupCount] = nil
			pickupCount = pickupCount - 1
			if pickupCount == 0 then
				pickupController:StopMotionController()
				pickupController:Remove()
				pickupController = nil
				hook.Remove("Tick", "vrmod_pickup")
			end

			hook.Call("VRMod_Drop", nil, t.ply, t.ent)
			return
		end
	end

	function shouldPickUp(ent)
		local vphys = ent:GetPhysicsObject()
		if ent:GetModel() == "models/hunter/plates/plate.mdl" and IsValid(vphys) and vphys:GetMass() == 20 and ent:GetNoDraw() == true then return false end
		if ent:GetNoDraw() == true then return false end
		return true
	end

	function pickup(ply, bLeftHand, handPos, handAng)
		local steamid = ply:SteamID()
		local pickupPoint = LocalToWorld(Vector(3, bLeftHand and -1.5 or 1.5, 0), Angle(), handPos, handAng)
		local entities = ents.FindInSphere(pickupPoint, 100)
		for k = 1, #entities do
			local v = entities[k]
			if not shouldPickUp(v) then continue end
			if not CanPickupEntity(v, ply, convarValues) then continue end
			--pescorrzoneend
			if not WorldToLocal(pickupPoint - v:GetPos(), Angle(), Vector(), v:GetAngles()):WithinAABox(v:OBBMins() * convarValues.vrmod_pickup_range, v:OBBMaxs() * convarValues.vrmod_pickup_range) then continue end
			if hook.Call("VRMod_Pickup", nil, ply, v) == false then return end
			-- Ragdoll pickup modification
			if IsValid(v:GetPhysicsObject()) and v:GetClass() == "prop_ragdoll" then
				local offset = handPos - v:GetPos()
				for i = 0, v:GetPhysicsObjectCount() - 1 do
					local phys = v:GetPhysicsObjectNum(i)
					if IsValid(phys) then phys:SetPos(phys:GetPos() - offset) end
				end

				v:SetAngles(handAng)
			end

			if pickupController == nil then
				--print("created controller")
				pickupController = ents.Create("vrmod_pickup")
				pickupController.ShadowParams = {
					secondstoarrive = 0.0001, --1/cv_tickrate:GetInt()
					maxangular = 5000,
					maxangulardamp = 5000,
					maxspeed = 1000000,
					maxspeeddamp = 10000,
					dampfactor = 0.5,
					teleportdistance = 0,
					deltatime = 0,
				}

				function pickupController:PhysicsSimulate(phys, deltatime)
					phys:Wake()
					local t = phys:GetEntity().vrmod_pickup_info
					if not t then return end
					local frame = g_VR[t.steamid] and g_VR[t.steamid].latestFrame
					if not frame then return end
					local handPos, handAng = LocalToWorld(t.left and frame.lefthandPos or frame.righthandPos, t.left and frame.lefthandAng or frame.righthandAng, t.ply:GetPos(), Angle()) --frame is relative to ply pos when on foot
					self.ShadowParams.pos, self.ShadowParams.angle = LocalToWorld(t.localPos, t.localAng, handPos, handAng)
					--this doesn't have to be inside PhysicsSimulate, we could potentially get rid of the motion controller entirely (as a micro optimization) and do this from the tick hook, but it seems to work better from here
					phys:ComputeShadowControl(self.ShadowParams)
				end

				pickupController:StartMotionController()
				hook.Add("Tick", "vrmod_pickup", function()
					--drop items that have become immovable or invalid
					for i = 1, pickupCount do
						local t = pickupList[i]
						if t == nil then
							i = 0
							break
						end
					end
				end)
			end

			--if the item is already being held we should overwrite the existing pickup instead of adding a new one
			local index = pickupCount + 1
			for k2 = 1, pickupCount do
				local v2 = pickupList[k2]
				if not v2 then continue end
				if not istable(v2) then continue end
				if v == v2.ent then
					index = k2
					if g_VR[v2.steamid] and g_VR[v2.steamid].heldItems then g_VR[v2.steamid].heldItems[v2.left and 1 or 2] = nil end
					break
				end
			end

			--new pickup
			if index > pickupCount then
				--print("new pickup")
				ply:PickupObject(v) --this is done to trigger map logic
				timer.Simple(0, function() ply:DropObject() end)
				pickupCount = pickupCount + 1
				if pickupController ~= nil or v ~= nil then
					local tmp_object = v:GetPhysicsObject()
					if IsValid(tmp_object) and IsValid(tmp_object:GetEntity()) then
						pickupController:AddToMotionController(tmp_object)
						pickupController:AddToMotionController(tmp_object)
						tmp_object:Wake()
					else
						-- 'ent' is NULL or invalid, handle the case appropriately                                                      
						--print("trying to pick up empty object!")
						ply:DropObject()
					end
				else
					ply:DropObject()
				end
			end

			local localPos, localAng = WorldToLocal(v:GetPos(), v:GetAngles(), handPos, handAng)
			pickupList[index] = {
				ent = v,
				phys = v:GetPhysicsObject(),
				left = bLeftHand,
				localPos = localPos,
				localAng = localAng,
				collisionGroup = pickupList[index] and pickupList[index].collisionGroup or v:GetCollisionGroup(),
				steamid = steamid,
				ply = ply
			}

			g_VR[steamid].heldItems = g_VR[steamid].heldItems or {}
			g_VR[steamid].heldItems[bLeftHand and 1 or 2] = pickupList[index]
			v.vrmod_pickup_info = pickupList[index]
			v:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR) --don't collide with the player
			net.Start("vrmod_pickup")
			net.WriteEntity(ply)
			net.WriteEntity(v)
			net.WriteBool(bDrop)
			net.WriteBool(bLeftHand)
			net.WriteVector(localPos)
			net.WriteAngle(localAng)
			net.Broadcast()
		end
	end

	vrmod.NetReceiveLimited("vrmod_pickup", 10, 400, function(len, ply)
		local bLeftHand = net.ReadBool()
		local bDrop = net.ReadBool()
		if not bDrop then
			pickup(ply, bLeftHand, net.ReadVector(), net.ReadAngle())
		else
			drop(ply:SteamID(), bLeftHand, net.ReadVector(), net.ReadAngle(), net.ReadVector(), net.ReadVector())
		end
	end)

	hook.Add("EntityRemoved", "vrmod_cleanup_drop_handler", function(ent)
		for i = 1, pickupCount do
			local t = pickupList[i]
			if t and t.ent == ent then
				drop(t.steamid, t.left)
				break
			end
		end
	end)

	hook.Add("VRMod_Exit", "pickupreset", function(ply, ent)
		pickupCount = 0
		hook.Call("VRMod_Drop", nil, ply, ent)
	end)

	hook.Add("AllowPlayerPickup", "vrmod", function(ply) if g_VR[ply:SteamID()] ~= nil then return false end end)
end

if SERVER then
	concommand.Add("vrmod_reset_pickup", function(ply)
		if not ply:IsValid() or not ply:IsSuperAdmin() then -- プレイヤーが無効または管理者でない場合は実行しない
			return
		end

		pickupList = {}
		pickupCount = 0
		if IsValid(pickupController) then
			pickupController:Remove()
			pickupController = nil
		end

		net.Start("vrmod_pickup_reset")
		net.Broadcast()
		print("VRMod pickup table has been reset by " .. ply:Nick())
	end)

	util.AddNetworkString("vrmod_pickup_reset")
elseif CLIENT then
	net.Receive("vrmod_pickup_reset", function()
		local steamid = LocalPlayer():SteamID()
		if g_VR[steamid] then g_VR[steamid].heldItems = {} end
		g_VR.heldEntityLeft = nil
		g_VR.heldEntityRight = nil
		print("VRMod pickup table has been reset")
	end)
end