g_VR = g_VR or {}
local convars = vrmod.GetConvars()
if CLIENT then
	g_VR.scale = 0
	g_VR.origin = Vector(0, 0, 0)
	g_VR.rtWidth, g_VR.rtHeight = nil, nil
	g_VR.originAngle = Angle(0, 0, 0)
	g_VR.viewModel = nil
	g_VR.viewModelMuzzle = nil
	g_VR.viewModelPos = Vector(0, 0, 0)
	g_VR.viewModelAng = Angle(0, 0, 0)
	g_VR.usingWorldModels = false
	g_VR.active = false
	g_VR.threePoints = false --hmd + 2 controllers
	g_VR.sixPoints = false --hmd + 2 controllers + 3 trackers
	g_VR.tracking = {}
	g_VR.input = {}
	g_VR.changedInputs = {}
	g_VR.errorText = ""
	g_VR.moduleVersion = 0
	local hfovLeft, hfovRight
	local aspectLeft, aspectRight
	local leftCalc, rightCalc
	local ipd, eyez
	local cropVerticalMargin, cropHorizontalOffset
	local lastPosePos = {}
	local lastViewEnt = nil
	local eyeOffset = nil
	local forwardOffset = nil
	local viewEntOffsetPos = Vector(0, 0, 0)
	local viewEntOffsetAng = Angle(0, 0, 0)
	local flipAng180 = Angle(0, 0, 180)
	local convarOverrides = {}
	local moduleFile
	if system.IsLinux() then
		moduleFile = "lua/bin/gmcl_vrmod_linux64.dll"
	elseif system.IsWindows() then
		if file.Exists("lua/bin/gmcl_vrmod_win64.dll", "GAME") then
			moduleFile = "lua/bin/gmcl_vrmod_win64.dll"
		elseif file.Exists("lua/bin/gmcl_vrmod_win32.dll", "GAME") then
			moduleFile = "lua/bin/gmcl_vrmod_win32.dll"
		end
	else
		error("[VRMod] Unsupported OS.")
	end

	if moduleFile then
		local tmp = vrmod
		vrmod = {}
		local success, err = pcall(function() require("vrmod") end)
		if success then
			for k, v in pairs(vrmod) do
				_G["VRMOD_" .. k] = v
			end

			g_VR.moduleVersion = VRMOD_GetVersion and VRMOD_GetVersion() or 0
		else
			print("[VRMod] Failed to load module:", err)
		end

		vrmod = tmp
	else
		print("[VRMod] No compatible module file found.")
	end

	-- 0) Helper functions
	local function overrideConvar(name, value)
		local cv = GetConVar(name)
		if cv then
			convarOverrides[name] = cv:GetString()
			RunConsoleCommand(name, value)
		end
	end

	local function restoreConvarOverrides()
		for k, v in pairs(convarOverrides) do
			RunConsoleCommand(k, v)
		end

		convarOverrides = {}
	end

	local function ComputeDisplayParams()
		local viewscale = convars.vrmod_viewscale:GetFloat()
		local fovX, fovY = convars.vrmod_fovscale_x:GetFloat(), convars.vrmod_fovscale_y:GetFloat()
		local di = VRMOD_GetDisplayInfo(1, 10)
		local rawW, rawH = di.RecommendedWidth * 2, di.RecommendedHeight
		-- preserve your variables exactly
		local leftProj = vrmod.utils.adjustFOV(di.ProjectionLeft, fovX, fovY)
		local rightProj = vrmod.utils.adjustFOV(di.ProjectionRight, fovX, fovY)
		local leftCalc = vrmod.utils.calculateProjectionParams(leftProj, viewscale)
		local rightCalc = vrmod.utils.calculateProjectionParams(rightProj, viewscale)
		-- clamp on Linux exactly as before
		if system.IsLinux() then
			local maxW, maxH = 4096, 4096
			local cw, ch = math.min(maxW, rawW), math.min(maxH, rawH)
			rawW, rawH = cw, ch
		end

		local ipd = di.TransformRight[1][4] * 2
		local eyez = di.TransformRight[3][4]
		return {
			rtW = rawW,
			rtH = rawH,
			leftCalc = leftCalc,
			rightCalc = rightCalc,
			hfovL = leftCalc.HorizontalFOV,
			hfovR = rightCalc.HorizontalFOV,
			aspL = leftCalc.AspectRatio,
			aspR = rightCalc.AspectRatio,
			ipd = ipd,
			eyez = eyez
		}
	end

	local function UpdateTracking()
		local smoothingFactor = vrmod.SMOOTHING_FACTOR
		local maxVelSqr = 2500
		local maxPosDeltaSqr = 100
		local rawPoses = VRMOD_GetPoses()
		for k, v in pairs(rawPoses) do
			if vrmod.utils.LengthSqr(v.vel) > maxVelSqr then continue end
			if lastPosePos[k] then
				local delta = vrmod.utils.SubVec(v.pos, lastPosePos[k])
				if vrmod.utils.LengthSqr(delta) > maxPosDeltaSqr then continue end
			end

			lastPosePos[k] = v.pos
			g_VR.tracking[k] = g_VR.tracking[k] or {}
			local worldPose = g_VR.tracking[k]
			--if vrmod._collisionShapeByHand then vrmod.utils.ApplyCollisionCorrection(k, v) end
			local pos, ang = LocalToWorld(v.pos * g_VR.scale, v.ang, g_VR.origin, g_VR.originAngle)
			if k == "pose_righthand" or k == "pose_lefthand" then
				worldPose.pos = worldPose.pos and vrmod.utils.SmoothVector(worldPose.pos, pos, smoothingFactor) or pos
				--worldPose.pos.z = pos.z
				worldPose.ang = worldPose.ang and vrmod.utils.SmoothAngle(worldPose.ang, ang, smoothingFactor) or ang
			else
				worldPose.pos = pos
				worldPose.ang = ang
			end

			worldPose.vel = LocalToWorld(v.vel, Angle(0, 0, 0), vector_origin, g_VR.originAngle) * g_VR.scale
			worldPose.angvel = LocalToWorld(Vector(v.angvel.pitch, v.angvel.yaw, v.angvel.roll), Angle(0, 0, 0), vector_origin, g_VR.originAngle)
			local isRight = k == "pose_righthand"
			local isLeft = k == "pose_lefthand"
			if isRight or isLeft then
				local offsetPos = (isRight and g_VR.rightControllerOffsetPos or g_VR.leftControllerOffsetPos) * 0.01 * g_VR.scale
				local offsetAng = isRight and g_VR.rightControllerOffsetAng or g_VR.leftControllerOffsetAng
				local offsetWorldPos, offsetWorldAng = LocalToWorld(offsetPos, offsetAng, vector_origin, worldPose.ang)
				worldPose.pos = worldPose.pos + offsetWorldPos
				worldPose.ang = offsetWorldAng
			end
		end

		g_VR.sixPoints = g_VR.tracking.pose_waist and g_VR.tracking.pose_leftfoot and g_VR.tracking.pose_rightfoot
		hook.Call("VRMod_Tracking")
	end

	local function HandleInput()
		g_VR.input, g_VR.changedInputs = VRMOD_GetActions()
		for k, v in pairs(g_VR.changedInputs) do
			hook.Call("VRMod_Input", nil, k, v)
		end
	end

	local function DrawErrorOverlay()
		if not system.HasFocus() or #g_VR.errorText > 0 then
			render.Clear(0, 0, 0, 255, true, true)
			cam.Start2D()
			local text = not system.HasFocus() and "Please focus the game window" or g_VR.errorText
			draw.DrawText(text, "DermaLarge", ScrW() / 2, ScrH() / 2, Color(255, 255, 255, 255), TEXT_ALIGN_CENTER)
			cam.End2D()
			g_VR.active = false
			return true
		end

		g_VR.active = true
	end

	local function UpdateViewModel(netFrame)
		local smoothingFactor = vrmod.SMOOTHING_FACTOR
		local currentvmi = g_VR.currentvmi
		local rh_pose = g_VR.tracking.pose_righthand
		local vm = g_VR.viewModel
		if currentvmi and rh_pose then
			local pos, ang = LocalToWorld(currentvmi.offsetPos, currentvmi.offsetAng, rh_pose.pos, rh_pose.ang)
			g_VR.viewModelPos = g_VR.viewModelPos and vrmod.utils.SmoothVector(g_VR.viewModelPos, pos, smoothingFactor) or pos
			g_VR.viewModelAng = g_VR.viewModelAng and vrmod.utils.SmoothAngle(g_VR.viewModelAng, ang, smoothingFactor) or ang
		end

		if IsValid(vm) then
			if not g_VR.usingWorldModels then
				vm:SetPos(g_VR.viewModelPos)
				vm:SetAngles(g_VR.viewModelAng)
				vm:SetupBones()
				if netFrame and g_VR.viewModelRightHandBone then
					local mtx = vm:GetBoneMatrix(g_VR.viewModelRightHandBone)
					if mtx then
						netFrame.righthandPos = mtx:GetTranslation()
						local ang = mtx:GetAngles()
						ang:Sub(flipAng180)
						netFrame.righthandAng = ang
					end
				end
			end

			g_VR.viewModelMuzzle = vm:GetAttachment(1)
		end
	end

	local function UpdateViewFromEntity()
		local ply = LocalPlayer()
		if not IsValid(ply) then return end
		local viewEnt = ply:GetViewEntity()
		if not IsValid(viewEnt) then return end
		if viewEnt ~= ply then
			local hmd = g_VR.tracking.hmd
			if not hmd then return end
			-- Transform HMD to VR origin local space
			local rawPos, rawAng = WorldToLocal(hmd.pos, hmd.ang, g_VR.origin, g_VR.originAngle)
			-- Update offset only when view entity changes
			if viewEnt ~= lastViewEnt then
				local vePos = viewEnt:GetPos()
				local veAng = viewEnt:GetAngles()
				local worldPos, worldAng = LocalToWorld(rawPos, rawAng, vePos, veAng)
				viewEntOffsetPos, viewEntOffsetAng = WorldToLocal(vePos, veAng, worldPos, worldAng)
				lastViewEnt = viewEnt
			end

			-- Apply offset
			local intermediatePos, intermediateAng = LocalToWorld(rawPos, rawAng, viewEntOffsetPos, viewEntOffsetAng)
			local vePos = viewEnt:GetPos()
			local veAng = viewEnt:GetAngles()
			g_VR.view.origin, g_VR.view.angles = LocalToWorld(intermediatePos, intermediateAng, vePos, veAng)
		else
			g_VR.view.origin = g_VR.tracking.hmd.pos
			g_VR.view.angles = g_VR.tracking.hmd.ang
		end
	end

	local function PerformRenderViews()
		if not eyeOffset or not forwardOffset then
			eyeOffset = ipd * 0.5 * g_VR.scale
			forwardOffset = g_VR.view.angles:Forward() * -(eyez * g_VR.scale)
		end

		g_VR.eyePosLeft = g_VR.view.origin + forwardOffset + g_VR.view.angles:Right() * -eyeOffset
		g_VR.eyePosRight = g_VR.view.origin + forwardOffset + g_VR.view.angles:Right() * eyeOffset
		render.PushRenderTarget(g_VR.rt)
		if DrawErrorOverlay() then
			render.PopRenderTarget()
			return
		end

		render.Clear(0, 0, 0, 255, true, true)
		-- Base view parameters
		local view = g_VR.view
		view.drawmonitors = true
		view.drawviewmodel = false
		-- Left eye
		view.origin = g_VR.eyePosLeft
		view.x = 0
		view.fov = hfovLeft
		view.aspectratio = aspectLeft
		hook.Call("VRMod_PreRender", nil, "left")
		render.RenderView(view)
		-- Right eye
		view.origin = g_VR.eyePosRight
		view.x = g_VR.rtWidth / 2
		view.fov = hfovRight
		view.aspectratio = aspectRight
		hook.Call("VRMod_PreRender", nil, "right")
		render.RenderView(view)
		if not LocalPlayer():Alive() then
			vrmod.utils.DrawDeathAnimation(g_VR.rtWidth, g_VR.rtHeight)
		else
			g_VR.deathTime = nil
		end

		render.PopRenderTarget()
		if g_VR.desktopView > 1 then
			render.CullMode(1)
			surface.SetDrawColor(255, 255, 255, 255)
			surface.SetMaterial(g_VR.rtMaterial)
			surface.DrawTexturedRectUV(-1, -1, 2, 2, cropHorizontalOffset, 1 - cropVerticalMargin, 0.5 + cropHorizontalOffset, cropVerticalMargin)
			render.CullMode(0)
		end
	end

	-- 1) Startup checks & init
	local function PerformStartup()
		local err = vrmod.GetStartupError()
		if err then
			print("VRMod failed to start: " .. err)
			return false
		end

		VRMOD_Shutdown() -- ensure clean state
		if VRMOD_Init() == false then
			print("vr init failed")
			return false
		end
		return true
	end

	-- 2) Convar overrides for performance
	local function OverridePerformanceConvars()
		for _, c in ipairs{"mat_queue_mode", "gmod_mcore_test", "cl_threaded_bone_setup", "cl_threaded_client_leaf_system", "r_threaded_particles"} do
			overrideConvar(c, "1")
		end
	end

	-- 3) Display parameters & render target setup
	local function SetupRenderTargets()
		local hOffset = convars.vrmod_horizontaloffset:GetFloat()
		local vOffset = convars.vrmod_verticaloffset:GetFloat()
		local scaleFactor = convars.vrmod_scalefactor:GetFloat()
		-- average half‐eye extents in tangent space
		local renderOffset = convars.vrmod_renderoffset:GetBool()
		g_VR.desktopView = convars.vrmod_desktopview:GetInt()
		local dp = ComputeDisplayParams()
		g_VR.rtWidth, g_VR.rtHeight = dp.rtW, dp.rtH
		leftCalc, rightCalc = dp.leftCalc, dp.rightCalc
		hfovLeft, hfovRight = dp.hfovL, dp.hfovR
		aspectLeft, aspectRight = dp.aspL, dp.aspR
		ipd, eyez = dp.ipd, dp.eyez
		cropVerticalMargin, cropHorizontalOffset = vrmod.utils.ComputeDesktopCrop(g_VR.desktopView, g_VR.rtWidth, g_VR.rtHeight)
		VRMOD_ShareTextureBegin()
		local rtName = "vrmod_rt_" .. tostring(SysTime())
		g_VR.rt = GetRenderTarget(rtName, g_VR.rtWidth, g_VR.rtHeight)
		local matName = "vrmod_rt_mat_" .. tostring(SysTime())
		g_VR.rtMaterial = CreateMaterial(matName, "UnlitGeneric", {
			["$basetexture"] = g_VR.rt:GetName()
		})

		VRMOD_ShareTextureFinish()
		local bounds = {vrmod.utils.computeSubmitBounds(leftCalc, rightCalc, hOffset, vOffset, scaleFactor, renderOffset)}
		VRMOD_SetSubmitTextureBounds(unpack(bounds))
	end

	-- 4) Action manifest & input initialization
	local function SetupActions()
		VRMOD_SetActionManifest("vrmod/vrmod_action_manifest.txt")
		local set = LocalPlayer():InVehicle() and "/actions/driving" or "/actions/main"
		VRMOD_SetActiveActionSets("/actions/base", set)
		VRUtilLoadCustomActions()
		g_VR.input, g_VR.changedInputs = VRMOD_GetActions()
	end

	-- 5) Networking & origin
	local function SetupNetworkAndOrigin()
		VRUtilNetworkInit()
		g_VR.origin = LocalPlayer():GetPos()
	end

	-- 6) Controller offsets & scale
	local function SetupScaleAndOffsets()
		g_VR.scale = convars.vrmod_scale:GetFloat()
		g_VR.rightControllerOffsetPos = Vector(convars.vrmod_controlleroffset_x:GetFloat(), convars.vrmod_controlleroffset_y:GetFloat(), convars.vrmod_controlleroffset_z:GetFloat())
		g_VR.leftControllerOffsetPos = g_VR.rightControllerOffsetPos * Vector(1, -1, 1)
		g_VR.rightControllerOffsetAng = Angle(convars.vrmod_controlleroffset_pitch:GetFloat(), convars.vrmod_controlleroffset_yaw:GetFloat(), convars.vrmod_controlleroffset_roll:GetFloat())
		g_VR.leftControllerOffsetAng = g_VR.rightControllerOffsetAng
	end

	-- 7) Initial view setup
	local function SetupViewParams()
		g_VR.view = {
			x = 0,
			y = 0,
			w = g_VR.rtWidth / 2,
			h = g_VR.rtHeight,
			drawmonitors = true,
			drawviewmodel = false,
			znear = convars.vrmod_znear:GetFloat(),
			dopostprocess = convars.vrmod_postprocess:GetBool()
		}
	end

	-- 8) Initial tracking state
	local function InitializeTracking()
		lastPosePos = {}
		g_VR.tracking = {
			hmd = {
				pos = LocalPlayer():GetPos() + Vector(0, 0, 66.8),
				ang = Angle(),
				vel = Vector(),
				angvel = Angle()
			},
			pose_lefthand = {
				pos = LocalPlayer():GetPos(),
				ang = Angle(),
				vel = Vector(),
				angvel = Angle()
			},
			pose_righthand = {
				pos = LocalPlayer():GetPos(),
				ang = Angle(),
				vel = Vector(),
				angvel = Angle()
			},
		}

		g_VR.threePoints = true
	end

	-- 9) Simulated hand fallback
	local function SetupHandSimulation()
		local simulate = {
			{
				pose = g_VR.tracking.pose_lefthand,
				offset = Vector(0, 10, -30)
			},
			{
				pose = g_VR.tracking.pose_righthand,
				offset = Vector(0, -10, -30)
			},
		}

		for _, v in ipairs(simulate) do
			v.pose.simulatedPos = v.pose.pos
		end

		hook.Add("VRMod_Tracking", "simulatehands", function()
			for i = #simulate, 1, -1 do
				local v = simulate[i]
				if v.pose.pos == v.pose.simulatedPos then
					v.pose.pos, v.pose.ang = LocalToWorld(v.offset, Angle(90, 0, 0), g_VR.tracking.hmd.pos, Angle(0, g_VR.tracking.hmd.ang.yaw, 0))
					v.pose.simulatedPos = v.pose.pos
				else
					table.remove(simulate, i)
				end
			end

			if #simulate == 0 then hook.Remove("VRMod_Tracking", "simulatehands") end
		end)
	end

	local function BindRenderSceneHook()
		hook.Add("RenderScene", "vrutil_hook_renderscene", function()
			if DrawErrorOverlay() then return true end
			VRMOD_SubmitSharedTexture()
			VRMOD_UpdatePosesAndActions()
			UpdateTracking()
			HandleInput()
			local netFrame = VRUtilNetUpdateLocalPly()
			UpdateViewModel(netFrame)
			UpdateViewFromEntity()
			PerformRenderViews()
			hook.Call("VRMod_PostRender")
			return true
		end)
	end

	local function SetupModelAndPlayerHooks()
		g_VR.usingWorldModels = convars.vrmod_useworldmodels:GetBool()
		if not g_VR.usingWorldModels then
			overrideConvar("viewmodel_fov", GetConVar("fov_desired"):GetString())
			hook.Add("CalcViewModelView", "vrutil_hook_calcviewmodelview", function(_, vm, _, _, _, _) return g_VR.viewModelPos, g_VR.viewModelAng end)
			local blockViewModelDraw = true
			g_VR.allowPlayerDraw = false
			local hideplayer = convars.vrmod_floatinghands:GetBool()
			hook.Add("PostDrawTranslucentRenderables", "vrutil_hook_drawplayerandviewmodel", function(bSky, _)
				if bSky or not LocalPlayer():Alive() then return end
				if IsValid(g_VR.viewModel) then
					blockViewModelDraw = false
					g_VR.viewModel:DrawModel()
					blockViewModelDraw = true
				end

				if not hideplayer then
					g_VR.allowPlayerDraw = true
					cam.Start3D()
					cam.End3D()
					local prev = render.GetBlend()
					render.SetBlend(1)
					LocalPlayer():DrawModel()
					render.SetBlend(prev)
					cam.Start3D()
					cam.End3D()
					g_VR.allowPlayerDraw = false
				end

				VRUtilRenderMenuSystem()
			end)

			hook.Add("PreDrawPlayerHands", "vrutil_hook_predrawplayerhands", function() return true end)
			hook.Add("PreDrawViewModel", "vrutil_hook_predrawviewmodel", function() return blockViewModelDraw end)
		else
			g_VR.allowPlayerDraw = true
		end

		hook.Add("ShouldDrawLocalPlayer", "vrutil_hook_shoulddrawlocalplayer", function() return g_VR.allowPlayerDraw end)
	end

	local function SetupShutdownHooks()
		function VRUtilClientExit()
			if not g_VR.active then return end
			restoreConvarOverrides()
			VRUtilMenuClose()
			VRUtilNetworkCleanup()
			vrmod.StopLocomotion()
			if IsValid(g_VR.viewModel) and g_VR.viewModel:GetClass() == "class C_BaseFlex" then g_VR.viewModel:Remove() end
			g_VR.viewModel = nil
			g_VR.viewModelMuzzle = nil
			LocalPlayer():GetViewModel().RenderOverride = nil
			LocalPlayer():GetViewModel():RemoveEffects(EF_NODRAW)
			hook.Remove("RenderScene", "vrutil_hook_renderscene")
			hook.Remove("CalcViewModelView", "vrutil_hook_calcviewmodelview")
			hook.Remove("PostDrawTranslucentRenderables", "vrutil_hook_drawplayerandviewmodel")
			hook.Remove("PreDrawPlayerHands", "vrutil_hook_predrawplayerhands")
			hook.Remove("PreDrawViewModel", "vrutil_hook_predrawviewmodel")
			hook.Remove("ShouldDrawLocalPlayer", "vrutil_hook_shoulddrawlocalplayer")
			hook.Remove("CalcView", "vrutil_hook_calcview")
			g_VR.tracking = {}
			g_VR.threePoints = false
			g_VR.sixPoints = false
			if g_VR.rt then
				render.PushRenderTarget(g_VR.rt)
				render.Clear(0, 0, 0, 255, true, true)
				render.PopRenderTarget()
				g_VR.rt = nil
			end

			g_VR.active = false
			VRMOD_Shutdown()
		end

		hook.Add("ShutDown", "vrutil_hook_shutdown", function() if IsValid(LocalPlayer()) and g_VR.net[LocalPlayer():SteamID()] then VRUtilClientExit() end end)
	end

	-- Main ----------------------------------------------------------------------
	function VRUtilClientStart()
		if not PerformStartup() then return end
		OverridePerformanceConvars()
		SetupRenderTargets()
		SetupActions()
		SetupNetworkAndOrigin()
		SetupScaleAndOffsets()
		SetupViewParams()
		InitializeTracking()
		SetupHandSimulation()
		BindRenderSceneHook()
		SetupModelAndPlayerHooks()
		SetupShutdownHooks()
		-- finalize
		vrmod.StartLocomotion()
		VRMOD_UpdatePosesAndActions()
		g_VR.active = true
	end
end