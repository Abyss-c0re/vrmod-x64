local function init()
	if CLIENT then
		net.Receive("vrutil_net_pickup", function(len)
			local ply = net.ReadEntity()
			local ent = net.ReadEntity()
			local leftHand = net.ReadBool()
			local localPos = net.ReadVector()
			local localAng = net.ReadAngle()
			local steamid = ply:SteamID()
			if g_VR.net[steamid] == nil then return end
			--
			ent.RenderOverride = function()
				if g_VR.net[steamid] == nil then return end
				local wpos, wang
				if leftHand then
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
			--]]
			if ply == LocalPlayer() then
				if leftHand then
					g_VR.heldEntityLeft = ent
				else
					g_VR.heldEntityRight = ent
				end
			end

			hook.Call("VRMod_Pickup", nil, ply, ent)
			hook.Add("VRMod_Input", "arc_pickup_compat", function(action, pressed)
				if action == "boolean_left_pickup" and not pressed then
					net.Start("vrutil_net_drop")
					net.WriteBool(true)
					net.WriteVector(g_VR.tracking.pose_lefthand.pos)
					net.WriteAngle(g_VR.tracking.pose_lefthand.ang)
					net.SendToServer()
					g_VR.heldEntityLeft = nil
					hook.Remove("VRMod_Input", "arc_pickup_compat")
				end
			end)

			--notify server that arcvr pickups exist and we should run the position update thing
			net.Start("vrutil_net_pickup")
			net.SendToServer()
		end)

		net.Receive("vrutil_net_drop", function(len)
			local ply = net.ReadEntity()
			local ent = net.ReadEntity()
			if IsValid(ent) and ent.RenderOverride == ent.VRPickupRenderOverride then ent.RenderOverride = nil end
			hook.Call("VRMod_Drop", nil, ply, ent)
		end)
	elseif SERVER then
		util.AddNetworkString("vrutil_net_pickup")
		util.AddNetworkString("vrutil_net_drop")
		local function drop(ply, leftHand, handPos, handAng)
			for k, v in pairs(g_VR[ply:SteamID()].heldItems) do
				if v.left == leftHand then
					if IsValid(v.ent) and IsValid(v.ent:GetPhysicsObject()) and v.ent:GetPhysicsObject():IsMoveable() then
						local vel = v.ent:GetVelocity()
						local angvel = v.ent:GetPhysicsObject():GetAngleVelocity()
						if handPos and handAng then
							local wPos, wAng = LocalToWorld(v.localPos, v.localAng, handPos, handAng)
							v.ent:SetPos(wPos)
							v.ent:SetAngles(wAng)
						end

						v.ent:SetCollisionGroup(v.ent.originalCollisionGroup)
						v.ent:PhysicsInit(SOLID_VPHYSICS)
						v.ent:PhysWake()
						v.ent:GetPhysicsObject():SetVelocity(vel)
						v.ent:GetPhysicsObject():AddAngleVelocity(angvel)
					end

					net.Start("vrutil_net_drop")
					net.WriteEntity(ply)
					net.WriteEntity(v.ent)
					net.Broadcast()
					hook.Call("VRMod_Drop", nil, ply, v.ent)
					table.remove(g_VR[ply:SteamID()].heldItems, k)
				end
			end
		end

		vrmod.NetReceiveLimited("vrutil_net_pickup", 10, 0, function(len, ply)
			local tickrate = GetConVar("vrmod_net_tickrate"):GetInt()
			hook.Add("Tick", "arc_pickup_compat", function()
				local updates = false
				for k2, v2 in pairs(g_VR) do
					local ply = player.GetBySteamID(k2)
					if not IsValid(ply) then continue end
					local frame = v2.latestFrame
					for k, v in pairs(v2.heldItems) do
						if v.ply then --ignore if using new table structure
							continue
						end

						if not IsValid(v.ent) or not IsValid(v.ent:GetPhysicsObject()) or not v.ent:GetPhysicsObject():IsMoveable() or not ply:Alive() then
							drop(ply, v.left)
							continue
						end

						local handPos = LocalToWorld(v.left and frame.lefthandPos or frame.righthandPos, Angle(), ply:GetPos(), Angle())
						local handAng = v.left and frame.lefthandAng or frame.righthandAng
						local wPos, wAng = LocalToWorld(v.localPos, v.localAng, handPos, handAng)
						v.targetPos = wPos
						v.ent:GetPhysicsObject():UpdateShadow(wPos, wAng, 1 / tickrate)
						updates = true
					end
				end

				if not updates then hook.Remove("Tick", "arc_pickup_compat") end
			end)
		end)

		vrmod.NetReceiveLimited("vrutil_net_drop", 10, 300, function(len, ply)
			local leftHand = net.ReadBool()
			local handPos = net.ReadVector()
			local handAng = net.ReadAngle()
			drop(ply, leftHand, handPos, handAng)
		end)

		hook.Add("VRMod_Start", "arc_pickup_compat", function(ply) g_VR[ply:SteamID()].heldItems = {} end)
	end
end

timer.Simple(0, function() if ArcticVR then init() end end)