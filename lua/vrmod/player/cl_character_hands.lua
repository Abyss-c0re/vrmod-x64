if CLIENT then
	local hands
	CreateClientConVar("vrmod_floatinghands_material", "models/c_arms_citizen_hand", true, FCVAR_ARCHIVE)
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

				-- Prefer live post-collision tracking for local player (gun/hands stay locked when blocked)
				local netFrame = g_VR.net[steamid] and g_VR.net[steamid].lerpedFrame
				local useTrack = (ply == LocalPlayer()) and g_VR.tracking and g_VR.tracking.pose_lefthand and g_VR.tracking.pose_righthand
				if useTrack then
					-- Always clone into overrides — never hold tracking Vector refs
					local lt, rt = g_VR.tracking.pose_lefthand, g_VR.tracking.pose_righthand
					local lpos = lt.pos and Vector(lt.pos.x, lt.pos.y, lt.pos.z) or nil
					local rpos = rt.pos and Vector(rt.pos.x, rt.pos.y, rt.pos.z) or nil
					local lang = lt.ang and Angle(lt.ang.p, lt.ang.y, lt.ang.r) or Angle()
					local rang = rt.ang and Angle(rt.ang.p, rt.ang.y, rt.ang.r) or Angle()
					-- If still collapsed, fall back to rawTracking
					local raw = g_VR.rawTracking
					if lpos and rpos and lpos:DistToSqr(rpos) < 4 and raw then
						local rL, rR = raw.pose_lefthand, raw.pose_righthand
						if rL and rR and rL.pos and rR.pos and rL.pos:DistToSqr(rR.pos) > 36 then
							lpos = Vector(rL.pos.x, rL.pos.y, rL.pos.z)
							rpos = Vector(rR.pos.x, rR.pos.y, rR.pos.z)
							if rL.ang then lang = Angle(rL.ang.p, rL.ang.y, rL.ang.r) end
							if rR.ang then rang = Angle(rR.ang.p, rR.ang.y, rR.ang.r) end
						end
					end
					if leftHand and leftHand >= 0 and boneinfo[leftHand] and lpos then
						boneinfo[leftHand].overridePos = lpos
						boneinfo[leftHand].overrideAng = lang
					end
					if rightHand and rightHand >= 0 and boneinfo[rightHand] and rpos then
						boneinfo[rightHand].overridePos = rpos
						boneinfo[rightHand].overrideAng = rang + Angle(0, 0, 180)
					end
					-- fingers from input / netFrame
					local curls = g_VR.input and g_VR.input.skeleton_lefthand and g_VR.input.skeleton_lefthand.fingerCurls
					for k, v in pairs(fingerboneids) do
						if not boneinfo[v] then continue end
						local fi = math.floor((k - 1) / 3 + 1)
						local curl = 0
						if curls and k <= 15 then
							curl = curls[fi] or 0
						elseif netFrame then
							curl = netFrame["finger" .. fi] or 0
						end
						if k > 15 and g_VR.input and g_VR.input.skeleton_righthand and g_VR.input.skeleton_righthand.fingerCurls then
							curl = g_VR.input.skeleton_righthand.fingerCurls[fi] or curl
						end
						boneinfo[v].offsetAng = LerpAngle(curl, g_VR.openHandAngles[k], g_VR.closedHandAngles[k])
					end
					hands:SetPos(LocalPlayer():GetPos())
				elseif netFrame then
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
		-- Cube: no floatinghands dummymirror. It drew a Core_DX90 world quad (black slab)
		-- that occluded the Real. Height cal mirror lives only in cl_heightadjust while open.
	end)

	hook.Add("VRMod_Exit", "vrmod_stophandsonly", function(ply, steamid)
		if IsValid(hands) then
			hands:Remove()
			LocalPlayer().RenderOverride = nil
			hook.Remove("PreDrawTranslucentRenderables", "vrmod_floatinghands_dummymirror")
		end
	end)
end