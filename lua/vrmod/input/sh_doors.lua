if CLIENT then
	local definedGrabPoints = {}
	function vrmod.AddUseGrabPoint(uid, map, class, model, bodygroup_id, bodygroup_value, bone, pos, ang_left_hand, ang_right_hand)
		definedGrabPoints[class] = definedGrabPoints[class] or {}
		definedGrabPoints[class][uid] = {
			map = map,
			model = model,
			bodygroup_id = bodygroup_id,
			bodygroup_value = bodygroup_value,
			bone = bone,
			pos = pos,
			angles = {ang_left_hand, ang_right_hand}
		}
	end

	vrmod.AddUseGrabPoint("default1", nil, "prop_door_rotating", "models/props_c17/door01_left.mdl", 1, 1, 1, Vector(-3, 1, -9), Angle(-90, 0, 0), Angle(-90, 0, 180))
	vrmod.AddUseGrabPoint("default2", nil, "prop_door_rotating", "models/props_c17/door01_left.mdl", 1, 1, 1, Vector(-3, 1, 7), Angle(90, 0, 0), Angle(90, 0, 180))
	vrmod.AddUseGrabPoint("default3", nil, "prop_door_rotating", "models/props_c17/door02_double.mdl", 1, 1, 1, Vector(-3, 1, -9), Angle(-90, 0, 0), Angle(-90, 0, 180))
	vrmod.AddUseGrabPoint("default4", nil, "prop_door_rotating", "models/props_c17/door02_double.mdl", 1, 1, 1, Vector(-3, 1, 7), Angle(90, 0, 0), Angle(90, 0, 180))
	vrmod.AddUseGrabPoint("default5", nil, "prop_dynamic", "models/props_wasteland/exterior_fence003b.mdl", 1, 0, 0, Vector(-8, -22, -25), Angle(0, 0, 0), Angle(0, 0, 0))
	vrmod.AddUseGrabPoint("default6", nil, "prop_dynamic", "models/props_wasteland/exterior_fence003b.mdl", 1, 0, 0, Vector(8, -22, -25), Angle(0, 180, 0), Angle(0, 180, 0))
	vrmod.AddUseGrabPoint("default7", "d1_trainstation_01", "func_door_rotating", "*17", 1, nil, nil, Vector(-3, -13, 3), Angle(), Angle()) --left locker doors
	vrmod.AddUseGrabPoint("default8", "d1_trainstation_01", "func_door_rotating", "*23", 1, nil, nil, Vector(-0, -14, 3), Angle(0, 15, 0), Angle(0, 15, 0))
	vrmod.AddUseGrabPoint("default9", "d1_trainstation_01", "func_door_rotating", "*20", 1, nil, nil, Vector(-3, -13, 3), Angle(), Angle())
	vrmod.AddUseGrabPoint("default10", "d1_trainstation_01", "func_door_rotating", "*16", 1, nil, nil, Vector(-3, 12, 3), Angle(), Angle()) --right locker doors
	vrmod.AddUseGrabPoint("default11", "d1_trainstation_01", "func_door_rotating", "*15", 1, nil, nil, Vector(-3, 10, 3), Angle(), Angle())
	vrmod.AddUseGrabPoint("default12", "d1_trainstation_01", "func_door_rotating", "*22", 1, nil, nil, Vector(-6, 11, 3), Angle(0, 15, 0), Angle(0, 15, 0))
	vrmod.AddUseGrabPoint("default13", "d1_trainstation_01", "func_door_rotating", "*21", 1, nil, nil, Vector(-6, 9, 3), Angle(0, 15, 0), Angle(0, 15, 0))
	vrmod.AddUseGrabPoint("default14", "d1_trainstation_01", "func_door_rotating", "*19", 1, nil, nil, Vector(-3, 12, 3), Angle(), Angle())
	vrmod.AddUseGrabPoint("default15", "d1_trainstation_01", "func_door_rotating", "*18", 1, nil, nil, Vector(-3, 10, 3), Angle(), Angle())
	local hands = {
		{
			poseName = "pose_lefthand",
			overrideFunc = vrmod.SetLeftHandPose,
			getFunc = vrmod.GetLeftHandPose
		},
		{
			poseName = "pose_righthand",
			overrideFunc = vrmod.SetRightHandPose,
			getFunc = vrmod.GetRightHandPose,
		},
	}

	local actionHand = {
		["boolean_left_pickup"] = hands[1],
		["boolean_right_pickup"] = hands[2]
	}

	local function releaseHand(hand)
		if hand.grabbing then
			hand.grabbing = false
			hand.lerpStartTime = SysTime()
			hand.lerpStartPos, hand.lerpStartAng = hand.getFunc()
		end
	end

	local doors = {}
	local invalidDoors = {}
	hook.Add("OnEntityCreated", "vrmod_doors", function(ent)
		local potentialGrabPoints = definedGrabPoints[ent:GetClass()]
		if potentialGrabPoints then
			timer.Simple(0.1, function()
				if not IsValid(ent) then return end
				local t = {
					ent = ent,
					pos = ent:GetPos(),
					grabPoints = {}
				}

				for k, v in pairs(potentialGrabPoints) do
					if (not v.map or game.GetMap() == v.map) and ent:GetModel() == v.model and ent:GetBodygroup(v.bodygroup_id) == v.bodygroup_value then t.grabPoints[#t.grabPoints + 1] = v end
				end

				if #t.grabPoints > 0 then
					doors[#doors + 1] = t
					ent.vrmod_door = true
					--print(math.floor(SysTime()),"added door", ent)
					ent:CallOnRemove("vrmod_door", function()
						for i = 1, #doors do
							if doors[i].ent == ent then
								table.remove(doors, i)
								break
							end
						end

						hands[1].grabEnt = nil
						hands[2].grabEnt = nil
						--print("door removed", ent)
					end)
				else
					invalidDoors[#invalidDoors + 1] = ent
				end
			end)
		end
	end)

	local function init()
		if #doors == 0 then return end
		hook.Add("VRMod_AllowDefaultAction", "doors", function(action) if action == "boolean_use" and LocalPlayer():GetEyeTrace().Entity.vrmod_door then return false end end)
		hook.Add("VRMod_Input", "doors", function(action, pressed)
			local hand = actionHand[action]
			if hand then
				if pressed then
					local handPose = g_VR.tracking[hand.poseName]
					local closestEnt, closestGrabPoint, closestDist = nil, nil, 9999
					for k, v in ipairs(doors) do
						if v.pos:DistToSqr(handPose.pos) < 4096 then
							for k2, v2 in ipairs(v.grabPoints) do
								local mtx = v2.bone and v.ent:GetBoneMatrix(v2.bone) or v.ent:GetWorldTransformMatrix()
								if mtx then
									local pos, ang = LocalToWorld(v2.pos, v2.angles[1], mtx:GetTranslation(), mtx:GetAngles())
									local dist = handPose.pos:DistToSqr(pos)
									if dist < closestDist and handPose.ang:Forward():Dot(ang:Forward()) > 0.5 then
										closestGrabPoint = v2
										closestDist = dist
										closestEnt = v.ent
									end
								end
							end
						end
					end

					if closestDist < 64 then
						hand.grabbing = true
						hand.blockUse = false
						hand.grabEnt = closestEnt
						hand.grabPoint = closestGrabPoint
						hand.lerpStartTime = SysTime()
						hand.lerpStartPos, hand.lerpStartAng = hand.getFunc()
						hook.Add("VRMod_PreRender", "doors", function()
							local remove = true
							for k, v in ipairs(hands) do
								if v.grabEnt then
									local fraction = math.min((SysTime() - v.lerpStartTime) * 10, 1)
									local pos, ang
									if v.grabbing then
										local mtx = v.grabPoint.bone and v.grabEnt:GetBoneMatrix(v.grabPoint.bone) or v.grabEnt:GetWorldTransformMatrix()
										pos, ang = LocalToWorld(v.grabPoint.pos, v.grabPoint.angles[k], mtx:GetTranslation(), mtx:GetAngles())
										if fraction == 1 and not v.blockUse then
											v.blockUse = true
											net.Start("vrmod_doors")
											net.WriteEntity(v.grabEnt)
											net.SendToServer()
											timer.Simple(0.2, function() releaseHand(v) end)
										end
									else
										pos, ang = g_VR.tracking[v.poseName].pos, g_VR.tracking[v.poseName].ang
										v.grabEnt = fraction < 1 and v.grabEnt or nil
									end

									pos, ang = LerpVector(fraction, v.lerpStartPos, pos), LerpAngle(fraction, v.lerpStartAng, ang)
									v.overrideFunc(pos, ang)
									remove = remove and fraction == 1 and not v.grabbing
								end
							end

							if remove then hook.Remove("VRMod_PreRender", "doors") end
						end)
						return false
					end
				else
					releaseHand(hand)
				end
			end
		end)
	end

	local function cleanup()
		hook.Remove("VRMod_Input", "doors")
		hook.Remove("VRMod_PreRender", "doors")
		hook.Remove("VRMod_AllowDefaultAction", "doors")
	end

	local _, convarValues = vrmod.AddCallbackedConvar("vrmod_doors", "vrmod_doors", "1", FCVAR_ARCHIVE, "", nil, nil, tobool, function(val)
		if val and g_VR.active then
			init()
		else
			cleanup()
		end
	end)

	hook.Add("VRMod_Start", "doors", function(ply)
		if ply ~= LocalPlayer() or not convarValues.vrmod_doors then return end
		init()
	end)

	hook.Add("VRMod_Exit", "doors", function(ply)
		if ply ~= LocalPlayer() then return end
		cleanup()
	end)

	--
	concommand.Add("vrmod_doordebug", function(ply, cmd, args)
		hook[args[1] == "1" and "Add" or "Remove"]("PostDrawTranslucentRenderables", "vrmod_doordebug", function(depth, sky)
			if depth or sky then return end
			render.SetColorMaterial()
			for k, v in ipairs(doors) do
				render.DrawWireframeSphere(v.pos, 64, 8, 8)
				for k2, v2 in ipairs(v.grabPoints) do
					local mtx = v2.bone and v.ent:GetBoneMatrix(v2.bone) or v.ent:GetWorldTransformMatrix()
					if mtx then
						local pos, ang = LocalToWorld(v2.pos, v2.angles[1], mtx:GetTranslation(), mtx:GetAngles())
						render.DrawWireframeBox(pos, ang, Vector(-1, -1, -1), Vector(1, 1, 1), Color(0, 255, 0, 128))
					end
				end
			end

			for k, v in ipairs(invalidDoors) do
				if IsValid(v) then render.DrawWireframeSphere(v:GetPos(), 64, 8, 8, Color(255, 0, 0)) end
			end
		end)
	end)
	--]]
elseif SERVER then
	util.AddNetworkString("vrmod_doors")
	vrmod.NetReceiveLimited("vrmod_doors", 5, 32, function(len, ply)
		local ent = net.ReadEntity()
		if hook.Run("PlayerUse", ply, ent) ~= false then ent:Use(ply) end
	end)
end