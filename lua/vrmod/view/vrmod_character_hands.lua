if CLIENT then
	local hands
	CreateClientConVar("vrmod_floatinghands_material", "models/shiny", true, FCVAR_ARCHIVE)
	CreateClientConVar("vrmod_floatinghands_model", "models/player/vr_hands.mdl", true, FCVAR_ARCHIVE)
	local convars = vrmod.GetConvars()
	hook.Add("VRMod_Start", "vrmod_starthandsonly", function(ply)
		if not (ply == LocalPlayer() and convars.vrmod_floatinghands:GetBool()) then return end
		timer.Simple(0, function() LocalPlayer().RenderOverride = function() end end)
		local zeroVec, zeroAng = Vector(), Angle()
		local steamid = LocalPlayer():SteamID()
		hands = ClientsideModel(GetConVar("vrmod_floatinghands_model"):GetString())
		hands:SetupBones()
		g_VR.hands = hands
		hands:SetMaterial(GetConVar("vrmod_floatinghands_material"):GetString())
		local leftHand = hands:LookupBone("ValveBiped.Bip01_L_Hand")
		local rightHand = hands:LookupBone("ValveBiped.Bip01_R_Hand")
		local fingerboneids = {}
		local tmp = {"0", "01", "02", "1", "11", "12", "2", "21", "22", "3", "31", "32", "4", "41", "42"}
		for i = 1, 30 do
			fingerboneids[#fingerboneids + 1] = hands:LookupBone("ValveBiped.Bip01_" .. (i < 16 and "L" or "R") .. "_Finger" .. tmp[i - (i < 16 and 0 or 15)]) or -1
		end

		local boneinfo = {}
		local boneCount = hands:GetBoneCount()
		for i = 0, boneCount - 1 do
			local parent = hands:GetBoneParent(i)
			local mtx = hands:GetBoneMatrix(i) or Matrix()
			local mtxParent = hands:GetBoneMatrix(parent) or mtx
			local relativePos, relativeAng = WorldToLocal(mtx:GetTranslation(), mtx:GetAngles(), mtxParent:GetTranslation(), mtxParent:GetAngles())
			boneinfo[i] = {
				name = hands:GetBoneName(i),
				parent = parent,
				relativePos = relativePos,
				relativeAng = relativeAng,
				offsetAng = zeroAng,
				pos = zeroVec,
				ang = zeroAng,
				targetMatrix = mtx
			}
		end

		hands:SetPos(LocalPlayer():GetPos())
		hands:SetRenderBounds(zeroVec, zeroVec, Vector(1, 1, 1) * 65000)
		local frame = 0
		hands:AddCallback("BuildBonePositions", function(ent, numbones)
			if frame ~= FrameNumber() then
				frame = FrameNumber()
				if LocalPlayer():InVehicle() and LocalPlayer():GetVehicle():GetClass() ~= "prop_vehicle_prisoner_pod" then
					hands:AddEffects(EF_NODRAW) --note: this will block BuildBonePositions from running
					hook.Add("VRMod_ExitVehicle", "vrmod_floatinghands", function()
						hook.Remove("VRMod_ExitVehicle", "vrmod_floatinghands")
						hands:RemoveEffects(EF_NODRAW)
					end)
					return
				end

				local netFrame = g_VR.net[steamid] and g_VR.net[steamid].lerpedFrame
				if netFrame then
					boneinfo[leftHand].overridePos, boneinfo[leftHand].overrideAng = netFrame.lefthandPos, netFrame.lefthandAng
					boneinfo[rightHand].overridePos, boneinfo[rightHand].overrideAng = netFrame.righthandPos, netFrame.righthandAng + Angle(0, 0, 180)
					for k, v in pairs(fingerboneids) do
						if not boneinfo[v] then continue end
						boneinfo[v].offsetAng = LerpAngle(netFrame["finger" .. math.floor((k - 1) / 3 + 1)], g_VR.openHandAngles[k], g_VR.closedHandAngles[k])
					end

					hands:SetPos(LocalPlayer():GetPos()) --for lighting
				end

				for i = 0, boneCount - 1 do
					local info = boneinfo[i]
					local parentInfo = boneinfo[info.parent] or info
					local wpos, wang = LocalToWorld(info.relativePos, info.relativeAng + info.offsetAng, parentInfo.pos, parentInfo.ang)
					wpos = info.overridePos or wpos
					wang = info.overrideAng or wang
					local mat = Matrix()
					mat:Translate(wpos)
					mat:Rotate(wang)
					info.targetMatrix = mat
					info.pos = wpos
					info.ang = wang
				end
			end

			for i = 0, boneCount - 1 do
				if hands:GetBoneMatrix(i) then hands:SetBoneMatrix(i, boneinfo[i].targetMatrix) end
			end
		end)

		g_VR = g_VR or {}
		g_VR.characterYaw = 0
		local convars, convarValues = vrmod.GetConvars()
		if not g_VR.threePoints or VRUtilIsMenuOpen("heightmenu") then return end
		--create mirror
		rt_mirror = GetRenderTarget("rt_vrmod_heightcalmirror", 2048, 2048)
		mat_mirror = CreateMaterial("mat_vrmod_heightcalmirror", "Core_DX90", {
			["$basetexture"] = "rt_vrmod_heightcalmirror",
			["$model"] = "1"
		})

		local mirrorYaw = 0
		hook.Add("PreDrawTranslucentRenderables", "vrmod_floatinghands_dummymirror", function(depth, skybox)
			if depth or skybox or not (EyePos() == g_VR.eyePosLeft or EyePos() == g_VR.eyePosRight) then return end
			local ad = math.AngleDifference(EyeAngles().yaw, mirrorYaw)
			if math.abs(ad) > 45 then mirrorYaw = mirrorYaw + (ad > 0 and 45 or -45) end
			local mirrorPos = Vector(g_VR.tracking.hmd.pos.x, g_VR.tracking.hmd.pos.y, g_VR.origin.z + 45) + Angle(0, mirrorYaw, 0):Forward() * -5
			local mirrorAng = Angle(0, mirrorYaw - 90, 90)
			-- g_VR.menus.heightmenu.pos = mirrorPos + Vector(0,0,30) + mirrorAng:Forward()*-15
			-- g_VR.menus.heightmenu.ang = mirrorAng
			local camPos = LocalToWorld(WorldToLocal(EyePos(), Angle(), mirrorPos, mirrorAng) * Vector(1, 1, -1), Angle(), mirrorPos, mirrorAng)
			local camAng = EyeAngles()
			camAng = Angle(camAng.pitch, mirrorAng.yaw + mirrorAng.yaw - camAng.yaw, 180 - camAng.roll)
			cam.Start({
				x = 0,
				y = 0,
				w = 2048,
				h = 2048,
				type = "3D",
				fov = g_VR.view.fov,
				aspect = -g_VR.view.aspectratio,
				origin = camPos,
				angles = camAng
			})

			render.PushRenderTarget(rt_mirror)
			render.Clear(200, 230, 255, 0, true, true)
			render.CullMode(1)
			local alloworig = g_VR.allowPlayerDraw
			g_VR.allowPlayerDraw = true
			cam.Start3D()
			cam.End3D()
			local ogEyePos = EyePos
			EyePos = function() return Vector(0, 0, 0) end
			local ogRenderOverride = LocalPlayer().RenderOverride
			LocalPlayer().RenderOverride = nil
			render.SuppressEngineLighting(true)
			LocalPlayer():DrawModel()
			render.SuppressEngineLighting(false)
			EyePos = ogEyePos
			LocalPlayer().RenderOverride = ogRenderOverride
			g_VR.allowPlayerDraw = alloworig
			cam.Start3D()
			cam.End3D()
			render.CullMode(0)
			render.PopRenderTarget()
			cam.End3D()
			render.SetMaterial(mat_mirror)
			render.DrawQuadEasy(mirrorPos, mirrorAng:Up(), 1, 1, Color(255, 255, 255, 255), 0)
		end)
	end)

	hook.Add("VRMod_Exit", "vrmod_stophandsonly", function(ply, steamid)
		if IsValid(hands) then
			hands:Remove()
			LocalPlayer().RenderOverride = nil
			hook.Remove("PreDrawTranslucentRenderables", "vrmod_floatinghands_dummymirror")
		end
	end)
end