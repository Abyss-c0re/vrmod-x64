local cv_allowtp = CreateConVar("vrmod_allow_teleport", "1", FCVAR_REPLICATED, "Enable teleportation in VRMod", 0, 1)
local cv_usetp = CreateClientConVar("vrmod_allow_teleport_client", 0, true, FCVAR_ARCHIVE)
local cl_analogmoveonly = CreateClientConVar("vrmod_test_analogmoveonly", 0, false, FCVAR_ARCHIVE)
local cv_tp_hand = CreateClientConVar("vrmod_teleport_use_left", 0, true, FCVAR_ARCHIVE)
local cv_maxTpDist = CreateConVar("vrmod_teleport_maxdist", 50, FCVAR_ARCHIVE + FCVAR_NOTIFY + FCVAR_REPLICATED, "Maximum teleport distance for VRMod")
if SERVER then
	util.AddNetworkString("vrmod_teleport")
	vrmod.NetReceiveLimited("vrmod_teleport", 10, 100, function(len, ply) if cv_allowtp:GetBool() and g_VR[ply:SteamID()] ~= nil and (hook.Run("PlayerNoClip", ply, true) == true or ULib and ULib.ucl.query(ply, "ulx noclip") == true) then ply:SetPos(net.ReadVector()) end end)
	return
end

local tpBeamMatrices, tpBeamEnt, tpBeamHitPos = {}, nil, nil
for i = 1, 17 do
	tpBeamMatrices[i] = Matrix()
end

hook.Add("VRMod_Input", "teleport", function(action, pressed)
	if action == "boolean_teleport" and not LocalPlayer():InVehicle() and cv_allowtp:GetBool() and cv_usetp:GetBool() then
		if pressed then
			tpBeamEnt = ClientsideModel("models/vrmod/tpbeam.mdl")
			tpBeamEnt:SetRenderMode(RENDERMODE_TRANSCOLOR)
			tpBeamEnt.RenderOverride = function(self)
				render.SuppressEngineLighting(true)
				self:SetupBones()
				for i = 1, 17 do
					self:SetBoneMatrix(i - 1, tpBeamMatrices[i])
				end

				self:DrawModel()
				render.SetColorModulation(1, 1, 1)
				render.SuppressEngineLighting(false)
			end

			hook.Add("VRMod_PreRender", "teleport", function()
				local controllerPos, controllerDir
				local cv_maxTpDist = cv_maxTpDist:GetInt()
				if cv_tp_hand:GetBool() then
					controllerPos, controllerDir = g_VR.tracking.pose_lefthand.pos, g_VR.tracking.pose_lefthand.ang:Forward()
				else
					controllerPos, controllerDir = g_VR.tracking.pose_righthand.pos, g_VR.tracking.pose_righthand.ang:Forward()
				end

				prevPos = controllerPos
				local hit = false
				for i = 2, 17 do
					local d = i - 1
					local nextPos = controllerPos + controllerDir * cv_maxTpDist * d + Vector(0, 0, -d * d * 3)
					local v = nextPos - prevPos
					if not hit then
						local tr = util.TraceLine({
							start = prevPos,
							endpos = prevPos + v,
							filter = function(ent) return ent ~= LocalPlayer() and not ent:GetNWBool("IsVRHand", false) end,
							mask = MASK_PLAYERSOLID
						})

						hit = tr.Hit
						if hit then
							tpBeamMatrices[1] = Matrix()
							tpBeamMatrices[1]:Translate(tr.HitPos + tr.HitNormal)
							tpBeamMatrices[1]:Rotate(tr.HitNormal:Angle() + Angle(90, 0, 90))
							if tr.HitNormal.z < 0.7 then
								tpBeamMatrices[1]:Scale(Vector(0.6, 0.6, 0.6))
								tpBeamEnt:SetColor(Color(255, 0, 0, 200))
								tpBeamHitPos = nil
							else
								tpBeamEnt:SetColor(Color(7, 255, 0, 200))
								tpBeamHitPos = tr.HitPos
							end

							tpBeamEnt:SetPos(tr.HitPos)
						end
					end

					tpBeamMatrices[i] = Matrix()
					tpBeamMatrices[i]:Translate(prevPos + v * 0.5)
					tpBeamMatrices[i]:Rotate(v:Angle() + Angle(-90, 0, 0))
					tpBeamMatrices[i]:Scale(Vector(0.5, 0.5, v:Length()))
					prevPos = nextPos
				end

				if not hit then
					tpBeamEnt:SetColor(Color(0, 0, 0, 0))
					tpBeamHitPos = nil
				end
			end)
		else
			tpBeamEnt:Remove()
			hook.Remove("VRMod_PreRender", "teleport")
			if tpBeamHitPos then
				net.Start("vrmod_teleport")
				net.WriteVector(tpBeamHitPos)
				net.SendToServer()
			end
		end
	end
end)

--******************************************************************************************************************************
if SERVER then return end
-- Convars
local _, convarValues = vrmod.AddCallbackedConvar("vrmod_controlleroriented", "controllerOriented", "0", nil, nil, nil, nil, tobool)
vrmod.AddCallbackedConvar("vrmod_smoothturn", "smoothTurn", "1", nil, nil, nil, nil, tobool)
vrmod.AddCallbackedConvar("vrmod_smoothturnrate", "smoothTurnRate", "180", nil, nil, nil, nil, tonumber)
vrmod.AddCallbackedConvar("vrmod_crouchthreshold", "crouchThreshold", "40", nil, nil, nil, nil, tonumber)
-- Helpers
local zeroVec, zeroAng = Vector(), Angle()
local upVec = Vector(0, 0, 1)
-- Vehicle origin tracking
local originVehicleLocalPos, originVehicleLocalAng = Vector(), Angle()
function VRUtilresetVehicleView()
	if not g_VR.threePoints and not LocalPlayer():InVehicle() then return end
	originVehicleLocalPos = nil
end

-- Locomotion start/stop
local function start()
	local ply = LocalPlayer()
	local followVec = zeroVec
	originVehicleLocalPos, originVehicleLocalAng = zeroVec, zeroAng
	-- Snap-turn config
	local snapTurnAngle = 45
	local snapThreshold = 0.5
	local snapped = false
	-- Dedicated Think hook for snap-turn
	hook.Add("Think", "vrmod_snapturn", function()
		if not g_VR.threePoints then return end
		if convarValues.smoothTurn then
			snapped = false
			return
		end

		local axis = g_VR.input.vector2_smoothturn.x
		-- Snap right
		if axis > snapThreshold and not snapped then
			local pos = ply:GetPos()
			g_VR.origin = LocalToWorld(g_VR.origin - pos, zeroAng, pos, Angle(0, -snapTurnAngle, 0))
			g_VR.originAngle.yaw = g_VR.originAngle.yaw - snapTurnAngle
			snapped = true
			-- Snap left
		elseif axis < -snapThreshold and not snapped then
			local pos = ply:GetPos()
			g_VR.origin = LocalToWorld(g_VR.origin - pos, zeroAng, pos, Angle(0, snapTurnAngle, 0))
			g_VR.originAngle.yaw = g_VR.originAngle.yaw + snapTurnAngle
			snapped = true
			-- Reset when back in deadzone
		elseif math.abs(axis) <= snapThreshold then
			snapped = false
		end
	end)

	-- PreRender hook: smooth-turn and follow logic
	hook.Add("PreRender", "vrmod_locomotion", function()
		if not g_VR.threePoints then return end
		-- Vehicle mode
		if ply:InVehicle() then
			local v = ply:GetVehicle()
			local att = v:GetAttachment(v:LookupAttachment("vehicle_driver_eyes"))
			if not originVehicleLocalPos then
				local relV, relA = WorldToLocal(g_VR.origin, g_VR.originAngle, g_VR.tracking.hmd.pos, Angle(0, g_VR.tracking.hmd.ang.yaw, 0))
				g_VR.origin, g_VR.originAngle = LocalToWorld(relV + Vector(7, 0, 2), relA, att.Pos, att.Ang)
				originVehicleLocalPos, originVehicleLocalAng = WorldToLocal(g_VR.origin, g_VR.originAngle, att.Pos, att.Ang)
			end

			g_VR.origin, g_VR.originAngle = LocalToWorld(originVehicleLocalPos, originVehicleLocalAng, att.Pos, att.Ang)
			return
		end

		-- Exit vehicle
		if originVehicleLocalPos then
			originVehicleLocalPos = nil
			g_VR.originAngle = Angle(0, g_VR.originAngle.yaw, 0)
		end

		-- Smooth turn
		if convarValues.smoothTurn then
			local amt = -g_VR.input.vector2_smoothturn.x * convarValues.smoothTurnRate * RealFrameTime()
			if amt ~= 0 then
				local pos = ply:GetPos()
				g_VR.origin = LocalToWorld(g_VR.origin - pos, zeroAng, pos, Angle(0, amt, 0))
				g_VR.originAngle.yaw = g_VR.originAngle.yaw + amt
			end
		end

		-- Follow HMD
		local pos = ply:GetPos()
		local target = g_VR.tracking.hmd.pos + upVec:Cross(g_VR.tracking.hmd.ang:Right()) * -10
		followVec = ply:GetMoveType() == MOVETYPE_NOCLIP and zeroVec or Vector((target.x - pos.x) * 8, (pos.y - target.y) * -8, 0)
		if followVec:LengthSqr() > 262144 then
			g_VR.origin = g_VR.origin + pos - target
			g_VR.origin.z = pos.z
			return
		end

		local ground = ply:GetGroundEntity()
		local gvel = IsValid(ground) and ground:GetVelocity() or zeroVec
		local vel = ply:GetVelocity() - followVec + gvel
		vel.z = 0
		if vel:Length() < 15 then vel = zeroVec end
		g_VR.origin = g_VR.origin + vel * FrameTime()
		g_VR.origin.z = pos.z
	end)

	-- CreateMove hook (unchanged)
	hook.Add("CreateMove", "vrmod_locomotion", function(cmd)
		if not g_VR.threePoints then return end
		if ply:InVehicle() then
			cmd:SetForwardMove((g_VR.input.vector1_forward - g_VR.input.vector1_reverse) * 400)
			cmd:SetSideMove(g_VR.input.vector2_steer.x * 400)
			local _, ra = WorldToLocal(Vector(), g_VR.tracking.hmd.ang, Vector(), ply:GetVehicle():GetAngles())
			cmd:SetViewAngles(ra)
			cmd:SetButtons(bit.bor(cmd:GetButtons(), g_VR.input.boolean_turbo and IN_SPEED or 0, g_VR.input.boolean_handbrake and IN_JUMP or 0))
			return
		end

		local mt = ply:GetMoveType()
		cmd:SetButtons(bit.bor(cmd:GetButtons(), g_VR.input.boolean_jump and IN_JUMP + IN_DUCK or 0, g_VR.input.boolean_sprint and IN_SPEED or 0, mt == MOVETYPE_LADDER and IN_FORWARD or 0, g_VR.tracking.hmd.pos.z < g_VR.origin.z + convarValues.crouchThreshold and IN_DUCK or 0))
		local va = g_VR.currentvmi and g_VR.currentvmi.wrongMuzzleAng and g_VR.tracking.pose_righthand.ang or g_VR.viewModelMuzzle and g_VR.viewModelMuzzle.Ang or g_VR.tracking.hmd.ang
		cmd:SetViewAngles(va:Forward():Angle())
		if mt == MOVETYPE_NOCLIP then
			if cl_analogmoveonly:GetBool() then ply:ConCommand("vrmod_test_analogmoveonly 1") end
			cmd:SetForwardMove(math.abs(g_VR.input.vector2_walkdirection.y) > 0.5 and g_VR.input.vector2_walkdirection.y or 0)
			cmd:SetSideMove(math.abs(g_VR.input.vector2_walkdirection.x) > 0.5 and g_VR.input.vector2_walkdirection.x or 0)
			return
		else
			if cl_analogmoveonly:GetBool() then ply:ConCommand("vrmod_test_analogmoveonly 0") end
		end

		local jv = LocalToWorld(Vector(g_VR.input.vector2_walkdirection.y * math.abs(g_VR.input.vector2_walkdirection.y), -g_VR.input.vector2_walkdirection.x * math.abs(g_VR.input.vector2_walkdirection.x), 0) * ply:GetMaxSpeed() * 0.9, zeroAng, zeroVec, Angle(0, convarValues.controllerOriented and g_VR.tracking.pose_lefthand.ang.yaw or g_VR.tracking.hmd.ang.yaw, 0))
		local wr = WorldToLocal(followVec + jv, zeroAng, zeroVec, Angle(0, va.yaw, 0))
		cmd:SetForwardMove(wr.x)
		cmd:SetSideMove(-wr.y)
	end)
end

local function stop()
	hook.Remove("Think", "vrmod_snapturn")
	hook.Remove("CreateMove", "vrmod_locomotion")
	hook.Remove("PreRender", "vrmod_locomotion")
	hook.Remove("VRMod_PreRender", "teleport")
	if IsValid(tpBeamEnt) then tpBeamEnt:Remove() end
	vrmod.RemoveInGameMenuItem("Map Browser")
	vrmod.RemoveInGameMenuItem("Reset Vehicle View")
end

-- Register locomotion
timer.Simple(0, function() vrmod.AddLocomotionOption("default", start, stop, options) end)