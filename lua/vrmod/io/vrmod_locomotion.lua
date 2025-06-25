local cv_allowtp = CreateClientConVar("vrmod_allow_teleport", 1, true, FCVAR_REPLICATED)
local cv_usetp = CreateClientConVar("vrmod_allow_teleport_client", 0, true, FCVAR_ARCHIVE)
local cl_analogmoveonly = CreateClientConVar("vrmod_test_analogmoveonly", 0, false, FCVAR_ARCHIVE)
if SERVER then
	util.AddNetworkString("vrmod_teleport")
	vrmod.NetReceiveLimited("vrmod_teleport", 10, 333, function(len, ply) if cv_allowtp:GetBool() and g_VR[ply:SteamID()] ~= nil and (hook.Run("PlayerNoClip", ply, true) == true or ULib and ULib.ucl.query(ply, "ulx noclip") == true) then ply:SetPos(net.ReadVector()) end end)
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
				local controllerPos, controllerDir = g_VR.tracking.pose_lefthand.pos, g_VR.tracking.pose_lefthand.ang:Forward()
				prevPos = controllerPos
				local hit = false
				for i = 2, 17 do
					local d = i - 1
					local nextPos = controllerPos + controllerDir * 50 * d + Vector(0, 0, -d * d * 3)
					local v = nextPos - prevPos
					if not hit then
						local tr = util.TraceLine({
							start = prevPos,
							endpos = prevPos + v,
							filter = LocalPlayer(),
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
local _, convarValues = vrmod.AddCallbackedConvar("vrmod_controlleroriented", "controllerOriented", "0", nil, nil, nil, nil, tobool)
vrmod.AddCallbackedConvar("vrmod_smoothturn", "smoothTurn", "0", nil, nil, nil, nil, tobool)
vrmod.AddCallbackedConvar("vrmod_smoothturnrate", "smoothTurnRate", "180", nil, nil, nil, nil, tonumber)
vrmod.AddCallbackedConvar("vrmod_crouchthreshold", "crouchThreshold", "40", nil, nil, nil, nil, tonumber)
local zeroVec, zeroAng = Vector(), Angle()
local upVec = Vector(0, 0, 1)
local function start()
	local ply = LocalPlayer()
	local followVec = zeroVec
	local originVehicleLocalPos, originVehicleLocalAng = zeroVec, zeroAng
	vrmod.AddInGameMenuItem("Reset Vehicle View", 3, 1, function() originVehicleLocalPos = nil end)
	hook.Add("PreRender", "vrmod_locomotion", function()
		if not g_VR.threePoints then return end
		if ply:InVehicle() then
			local v = ply:GetVehicle()
			local attachment = v:GetAttachment(v:LookupAttachment("vehicle_driver_eyes"))
			if not originVehicleLocalPos then
				local originHmdRelV, originHmdRelA = WorldToLocal(g_VR.origin, g_VR.originAngle, g_VR.tracking.hmd.pos, Angle(0, g_VR.tracking.hmd.ang.yaw, 0)) --where the origin is relative to the hmd				
				g_VR.origin, g_VR.originAngle = LocalToWorld(originHmdRelV + Vector(7, 0, 2), originHmdRelA, attachment.Pos, attachment.Ang) --where the origin would be if the attachment was the hmd
				originVehicleLocalPos, originVehicleLocalAng = WorldToLocal(g_VR.origin, g_VR.originAngle, attachment.Pos, attachment.Ang) --new origin relative to the attachment
			end

			g_VR.origin, g_VR.originAngle = LocalToWorld(originVehicleLocalPos, originVehicleLocalAng, attachment.Pos, attachment.Ang)
			return
		end

		if originVehicleLocalPos then
			originVehicleLocalPos = nil
			g_VR.originAngle = Angle(0, g_VR.originAngle.yaw, 0)
		end

		local plyPos = ply:GetPos()
		local turnAmount = convarValues.smoothTurn and -g_VR.input.vector2_smoothturn.x * convarValues.smoothTurnRate * RealFrameTime() or g_VR.changedInputs.boolean_turnright and -30 or g_VR.changedInputs.boolean_turnleft and 30 or 0
		if turnAmount ~= 0 then
			g_VR.origin = LocalToWorld(g_VR.origin - plyPos, zeroAng, plyPos, Angle(0, turnAmount, 0))
			g_VR.originAngle.yaw = g_VR.originAngle.yaw + turnAmount
		end

		--make the player follow the hmd
		local plyTargetPos = g_VR.tracking.hmd.pos + upVec:Cross(g_VR.tracking.hmd.ang:Right()) * -10
		followVec = ply:GetMoveType() == MOVETYPE_NOCLIP and zeroVec or Vector((plyTargetPos.x - plyPos.x) * 8, (plyPos.y - plyTargetPos.y) * -8, 0)
		--teleport view if further than 64 units from target
		if followVec:LengthSqr() > 262144 then
			g_VR.origin = g_VR.origin + plyPos - plyTargetPos
			g_VR.origin.z = plyPos.z
			followVec = zeroVec
			return
		end

		local groundEnt = ply:GetGroundEntity()
		local groundVel = IsValid(groundEnt) and groundEnt:GetVelocity() or zeroVec
		originVelocity = ply:GetVelocity() - followVec + groundVel
		originVelocity.z = 0
		if originVelocity:Length() < 15 then originVelocity = zeroVec end
		g_VR.origin = g_VR.origin + originVelocity * FrameTime()
		g_VR.origin.z = plyPos.z
	end)

	hook.Add("CreateMove", "vrmod_locomotion", function(cmd)
		if not g_VR.threePoints then return end
		--vehicle behaviour
		if ply:InVehicle() then
			cmd:SetForwardMove((g_VR.input.vector1_forward - g_VR.input.vector1_reverse) * 400)
			cmd:SetSideMove(g_VR.input.vector2_steer.x * 400)
			local _, relativeAng = WorldToLocal(Vector(0, 0, 0), g_VR.tracking.hmd.ang, Vector(0, 0, 0), ply:GetVehicle():GetAngles())
			cmd:SetViewAngles(relativeAng) --turret aiming
			cmd:SetButtons(bit.bor(cmd:GetButtons(), g_VR.input.boolean_turbo and IN_SPEED or 0, g_VR.input.boolean_handbrake and IN_JUMP or 0))
			return
		end

		local moveType = ply:GetMoveType()
		cmd:SetButtons(bit.bor(cmd:GetButtons(), g_VR.input.boolean_jump and IN_JUMP + IN_DUCK or 0, g_VR.input.boolean_sprint and IN_SPEED or 0, moveType == MOVETYPE_LADDER and IN_FORWARD or 0, g_VR.tracking.hmd.pos.z < g_VR.origin.z + convarValues.crouchThreshold and IN_DUCK or 0))
		--set view angles to viewmodel muzzle angles for engine weapon support, note: movement is relative to view angles
		local viewAngles = g_VR.currentvmi and g_VR.currentvmi.wrongMuzzleAng and g_VR.tracking.pose_righthand.ang or g_VR.viewModelMuzzle and g_VR.viewModelMuzzle.Ang or g_VR.tracking.hmd.ang
		viewAngles = viewAngles:Forward():Angle()
		cmd:SetViewAngles(viewAngles)
		--noclip behaviour
		if moveType == MOVETYPE_NOCLIP then
			if cl_analogmoveonly:GetBool() then LocalPlayer():ConCommand("vrmod_test_analogmoveonly 1") end
			cmd:SetForwardMove(math.abs(g_VR.input.vector2_walkdirection.y) > 0.5 and g_VR.input.vector2_walkdirection.y or 0)
			cmd:SetSideMove(math.abs(g_VR.input.vector2_walkdirection.x) > 0.5 and g_VR.input.vector2_walkdirection.x or 0)
			originVelocity = ply:GetVelocity()
			return
		else
			if cl_analogmoveonly:GetBool() then LocalPlayer():ConCommand("vrmod_test_analogmoveonly 0") end
		end

		--
		local joystickVec = LocalToWorld(Vector(g_VR.input.vector2_walkdirection.y * math.abs(g_VR.input.vector2_walkdirection.y), -g_VR.input.vector2_walkdirection.x * math.abs(g_VR.input.vector2_walkdirection.x), 0) * ply:GetMaxSpeed() * 0.9, Angle(0, 0, 0), Vector(0, 0, 0), Angle(0, convarValues.controllerOriented and g_VR.tracking.pose_lefthand.ang.yaw or g_VR.tracking.hmd.ang.yaw, 0))
		--
		local walkDirViewAngRelative = WorldToLocal(followVec + joystickVec, zeroAng, zeroVec, Angle(0, viewAngles.yaw, 0))
		cmd:SetForwardMove(walkDirViewAngRelative.x)
		cmd:SetSideMove(-walkDirViewAngRelative.y)
	end)

	--
	concommand.Add("vrmod_debuglocomotion", function(ply, cmd, args)
		hook[args[1] == "1" and "Add" or "Remove"]("PostDrawTranslucentRenderables", "vrmod_playspaceviz", function(depth, sky)
			if depth or sky then return end
			render.SetColorMaterial()
			render.DrawWireframeBox(LocalPlayer():GetPos(), zeroAng, Vector(1, 1, 0) * -16, Vector(1, 1, 4.5) * 16, Color(255, 0, 0))
			render.DrawWireframeBox(g_VR.origin, g_VR.originAngle, Vector(-200, -200, 0.1), Vector(200, 200, 200), Color(255, 255, 255), true)
			for i = 1, 4 do
				render.DrawWireframeBox(g_VR.origin, g_VR.originAngle, Vector(-200, -300 + i * 100, 0.1), Vector(200, -250 + i * 100, 0.1), Color(255, 255, 255), true)
				render.DrawWireframeBox(g_VR.origin, g_VR.originAngle, Vector(-300 + i * 100, -200, 0.1), Vector(-250 + i * 100, 200, 0.1), Color(255, 255, 255), true)
			end
		end)
	end)
	--]]
end

local function stop()
	hook.Remove("CreateMove", "vrmod_locomotion")
	hook.Remove("PreRender", "vrmod_locomotion")
	--
	hook.Remove("VRMod_PreRender", "teleport")
	if IsValid(tpBeamEnt) then tpBeamEnt:Remove() end
	vrmod.RemoveInGameMenuItem("Map Browser")
	vrmod.RemoveInGameMenuItem("Reset Vehicle View")
end

timer.Simple(0, function()
	vrmod.AddLocomotionOption("default", start, stop, options)
	vrmod.AddInGameMenuItem("Toggle Noclip", 2, 1, function() LocalPlayer():ConCommand("noclip") end)
end)