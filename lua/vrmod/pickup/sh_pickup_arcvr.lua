local function init()
	if CLIENT then
		net.Receive("vrutil_net_pickup", function(len)
			local ply = net.ReadEntity()
			local ent = net.ReadEntity()
			local leftHand = net.ReadBool()
			local localPos = net.ReadVector()
			local localAng = net.ReadAngle()
			if not IsValid(ply) or not IsValid(ent) then return end
			local steamid = ply:SteamID()
			-- Ensure local player has a net table so ArcVR pickups always attach
			if g_VR.net[steamid] == nil then
				g_VR.net[steamid] = {
					lastFrame = nil,
					playbackTime = 0,
				}
			end

			-- Capture hand flag for this entity (avoid stale closure bugs across pickups)
			ent.VRPickupLeftHand = leftHand and true or false
			ent.VRPickupLocalPos = Vector(localPos)
			ent.VRPickupLocalAng = Angle(localAng.p, localAng.y, localAng.r)

			-- Stereo-stable hold pose: one world matrix per stereoFrame for both eyes.
			ent.RenderOverride = function(self)
				if not IsValid(self) then return end
				local sf = (g_VR and g_VR.stereoFrame) or (FrameNumber and FrameNumber()) or 0
				if self._vrHoldFrame ~= sf or not self._vrHoldPos or not self._vrHoldAng then
					local useLeft = self.VRPickupLeftHand
					local lpos = self.VRPickupLocalPos or vector_origin
					local lang = self.VRPickupLocalAng or angle_zero
					local handPos, handAng

					-- Prefer frame-frozen stereoPose (set before either eye draws)
					local sp = g_VR and g_VR.stereoPose
					if ply == LocalPlayer() and sp and sp.frame == sf then
						if useLeft and sp.hasLeft then
							handPos, handAng = sp.leftPos, sp.leftAng
						elseif (not useLeft) and sp.hasRight then
							handPos, handAng = sp.rightPos, sp.rightAng
						end
					end
					if not handPos and ply == LocalPlayer() and g_VR and g_VR.tracking then
						local pose = useLeft and g_VR.tracking.pose_lefthand or g_VR.tracking.pose_righthand
						if not pose or not pose.pos then return end
						handPos, handAng = pose.pos, pose.ang
					end
					if not handPos then
						local netData = g_VR and g_VR.net and g_VR.net[steamid]
						if not netData or not netData.lerpedFrame then return end
						local frame = netData.lerpedFrame
						if useLeft then
							handPos, handAng = frame.lefthandPos, frame.lefthandAng
						else
							handPos, handAng = frame.righthandPos, frame.righthandAng
						end
					end
					if not handPos or not handAng then return end

					local wpos, wang = LocalToWorld(lpos, lang, handPos, handAng)
					if not self._vrHoldPos then self._vrHoldPos = Vector() end
					if not self._vrHoldAng then self._vrHoldAng = Angle() end
					self._vrHoldPos:Set(wpos)
					self._vrHoldAng:Set(wang)
					self._vrHoldFrame = sf
					self:SetPos(self._vrHoldPos)
					self:SetAngles(self._vrHoldAng)
					self:SetupBones()
					self._vrHoldBonesFrame = sf
				else
					-- Second eye: same matrix, no re-SetupBones
					self:SetPos(self._vrHoldPos)
					self:SetAngles(self._vrHoldAng)
				end
				self:DrawModel()
			end

			ent.VRPickupRenderOverride = ent.RenderOverride

			if ply == LocalPlayer() then
				if leftHand then
					g_VR.heldEntityLeft = ent
					-- Don't leave the mag also registered as right-hand hold
					if g_VR.heldEntityRight == ent then g_VR.heldEntityRight = nil end
				else
					g_VR.heldEntityRight = ent
					if g_VR.heldEntityLeft == ent then g_VR.heldEntityLeft = nil end
				end
			end

			hook.Call("VRMod_Pickup", nil, ply, ent)
			if leftHand then
				hook.Add("VRMod_Input", "arc_pickup_compat", function(action, pressed)
					if action == "boolean_left_pickup" and not pressed then
						local track = g_VR.tracking and g_VR.tracking.pose_lefthand
						if not track then return end
						net.Start("vrutil_net_drop")
						net.WriteBool(true)
						net.WriteVector(track.pos)
						net.WriteAngle(track.ang)
						net.SendToServer()
						g_VR.heldEntityLeft = nil
						hook.Remove("VRMod_Input", "arc_pickup_compat")
					end
				end)
			end

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

						if not frame then continue end
						local relPos = v.left and frame.lefthandPos or frame.righthandPos
						local relAng = v.left and frame.lefthandAng or frame.righthandAng
						if not relPos or not relAng then continue end
						-- latestFrame hand poses are relative to player origin
						local handPos = LocalToWorld(relPos, Angle(), ply:GetPos(), Angle())
						local handAng = relAng
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