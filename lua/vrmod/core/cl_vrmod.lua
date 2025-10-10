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
	local eyeOffset = nil
	local forwardOffset = nil
	local convarOverrides = {}
	local moduleFile
	local wasPaused = false
	if system.IsLinux() then
		moduleFile = "lua/bin/gmcl_vrmod_linux64.dll"
	elseif system.IsWindows() then
		if file.Exists("lua/bin/gmcl_vrmod_win64.dll", "GAME") then
			moduleFile = "lua/bin/gmcl_vrmod_win64.dll"
		elseif file.Exists("lua/bin/gmcl_vrmod_win32.dll", "GAME") then
			moduleFile = "lua/bin/gmcl_vrmod_win32.dll"
		end
	else
		vrmod.logger.Err("Unsupported OS.")
	end

	if moduleFile then
		vrmod = vrmod or {}
		local success, err = pcall(function() require("vrmod") end)
		if success then
			for k, v in pairs(vrmod) do
				_G["VRMOD_" .. k] = v
			end

			g_VR.moduleVersion = VRMOD_GetVersion and VRMOD_GetVersion() or 0
		else
			vrmod.logger.Err("Failed to load module:", err)
		end
	else
		vrmod.logger.Err("No compatible module file found.")
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
		local leftProj = vrmod.utils.AdjustFOV(di.ProjectionLeft, fovX, fovY)
		local rightProj = vrmod.utils.AdjustFOV(di.ProjectionRight, fovX, fovY)
		local leftCalc = vrmod.utils.CalculateProjectionParams(leftProj, viewscale)
		local rightCalc = vrmod.utils.CalculateProjectionParams(rightProj, viewscale)
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
		local maxPosDeltaSqr = 100
		local rawPoses = VRMOD_GetPoses()
		for k, v in pairs(rawPoses) do
			local lastPos = lastPosePos[k]
			local currentPos = v.pos
			if lastPos then
				local delta = vrmod.utils.SubVec(currentPos, lastPos)
				local deltaLenSqr = vrmod.utils.LengthSqr(delta)
				if deltaLenSqr > maxPosDeltaSqr then
					local deltaLen = math.sqrt(deltaLenSqr)
					local clampedDelta = vrmod.utils.MulVec(delta, maxPosDeltaSqr / deltaLen)
					currentPos = vrmod.utils.AddVec(lastPos, clampedDelta)
					vrmod.logger.Warn("Pose %s exceeded max delta, clamped.", k)
				end
			end

			lastPosePos[k] = currentPos
			g_VR.tracking[k] = g_VR.tracking[k] or {}
			local worldPose = g_VR.tracking[k]
			local pos, ang = LocalToWorld(currentPos * g_VR.scale, v.ang, g_VR.origin, g_VR.originAngle)
			if k == "pose_righthand" or k == "pose_lefthand" then
				worldPose.pos = worldPose.pos and vrmod.utils.SmoothVector(worldPose.pos, pos, smoothingFactor) or pos
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

			vrmod.logger.Debug("Updated tracking for %s: pos=%s ang=%s", k, tostring(worldPose.pos), tostring(worldPose.ang))
		end

		g_VR.sixPoints = g_VR.tracking.pose_waist and g_VR.tracking.pose_leftfoot and g_VR.tracking.pose_rightfoot
		hook.Call("VRMod_Tracking")
	end

	local function UpdateCollisionsAndWepPos()
		if g_VR.tracking.pose_lefthand and g_VR.tracking.pose_righthand and vrmod.utils then
			vrmod.utils.CollisionsPreCheck(g_VR.tracking.pose_lefthand.pos, g_VR.tracking.pose_righthand.pos)
			vrmod.utils.UpdateViewModelPos(g_VR.tracking.pose_righthand.pos, g_VR.tracking.pose_righthand.ang)
			local leftPos, leftAng, rightPos, rightAng = vrmod.utils.UpdateHandCollisions(g_VR.tracking.pose_lefthand.pos, g_VR.tracking.pose_lefthand.ang, g_VR.tracking.pose_righthand.pos, g_VR.tracking.pose_righthand.ang)
			g_VR.tracking.pose_lefthand.pos = leftPos
			g_VR.tracking.pose_lefthand.ang = leftAng
			g_VR.tracking.pose_righthand.pos = rightPos
			g_VR.tracking.pose_righthand.ang = rightAng
			vrmod.utils.UpdateViewModelPos(rightPos, rightAng)
		end
	end

	local function HandleInput()
		g_VR.input, g_VR.changedInputs = VRMOD_GetActions()
		for k, v in pairs(g_VR.changedInputs) do
			hook.Call("VRMod_Input", nil, k, v)
		end
	end

	local function DrawErrorOverlay()
		local isPaused = not system.HasFocus() or #g_VR.errorText > 0
		if isPaused then
			render.Clear(0, 0, 0, 255, true, true)
			cam.Start2D()
			local text = not system.HasFocus() and "Please focus the game window" or g_VR.errorText
			draw.DrawText(text, "DermaLarge", ScrW() / 2, ScrH() / 2, Color(255, 255, 255, 255), TEXT_ALIGN_CENTER)
			cam.End2D()
			g_VR.active = false
			-- Only log on state change
			if not wasPaused then vrmod.logger.Info("VR session paused") end
			wasPaused = true
			return true
		else
			g_VR.active = true
			-- Only log unpause on state change
			if wasPaused then vrmod.logger.Info("VR session resumed") end
			wasPaused = false
		end
	end

	local function UpdateViewFromEntity()
		local ply = LocalPlayer()
		if not IsValid(ply) then return end
		local viewEnt = ply:GetViewEntity()
		if not IsValid(viewEnt) then return end
		local hmd = g_VR.tracking.hmd
		if not hmd then return end
		-- Transform HMD to VR origin local space
		local rawPos, rawAng = WorldToLocal(hmd.pos, hmd.ang, g_VR.origin, g_VR.originAngle)
		-- Base position and angle
		local finalPos, finalAng = hmd.pos, hmd.ang
		-- If we are viewing through an entity (not player), apply offset
		if viewEnt ~= ply then
			local vePos = viewEnt:GetPos()
			local veAng = viewEnt:GetAngles()
			finalPos, finalAng = LocalToWorld(rawPos, rawAng, vePos, veAng)
		end

		-- Detect Glide vehicle and apply small lift/forward
		if g_VR.vehicle.glide then
			local forward = g_VR.view.angles:Forward() -- view/vehicle facing direction
			local up = g_VR.view.angles:Up()
			if g_VR.vehicle.type == "motorcycle" then
				-- Move 6 units forward instead of just down
				g_VR.view.origin = finalPos + forward * 8 + up * 3
			else
				-- Move slightly forward and up
				g_VR.view.origin = finalPos + forward * 6 + up * 6
			end

			g_VR.tracking.pose_lefthand.pos = g_VR.tracking.pose_lefthand.pos + forward * 3.5
			g_VR.tracking.pose_righthand.pos = g_VR.tracking.pose_righthand.pos + forward * 3.5
		else
			g_VR.view.origin = finalPos
		end

		g_VR.view.angles = finalAng
	end

	local function PerformRenderViews()
		local eyeScale = convars.vrmod_eyescale:GetFloat()
		-- cache angles once per frame
		local ang = g_VR.view.angles
		local fwd = ang:Forward()
		local right = ang:Right()
		local up = ang:Up()
		-- only recompute offsets when needed
		if not eyeOffset or not forwardOffset or not verticalOffset then
			eyeOffset = ipd * g_VR.scale
			forwardOffset = fwd * -(eyez * g_VR.scale)
			verticalOffset = up * -2.1
		end

		-- compute eye positions
		g_VR.eyePosLeft = g_VR.view.origin + forwardOffset + right * -eyeOffset * eyeScale + verticalOffset
		g_VR.eyePosRight = g_VR.view.origin + forwardOffset + right * eyeOffset * eyeScale + verticalOffset
		render.PushRenderTarget(g_VR.rt)
		if DrawErrorOverlay() then
			render.PopRenderTarget()
			vrmod.logger.Warn("Render skipped due to error overlay.")
			return
		end

		render.Clear(0, 0, 0, 255, true, true)
		-- cache common values
		local ply = LocalPlayer()
		local rtHalfW = g_VR.rtWidth / 2
		local rtH = g_VR.rtHeight
		-- left eye
		g_VR.view.origin = g_VR.eyePosLeft
		g_VR.view.fov = hfovLeft
		g_VR.view.aspectratio = aspectLeft
		g_VR.view.x = 0
		g_VR.view.y = 0
		g_VR.view.w = rtHalfW
		g_VR.view.h = rtH
		hook.Call("VRMod_PreRender", nil, "left")
		render.RenderView(g_VR.view)
		-- right eye
		g_VR.view.origin = g_VR.eyePosRight
		g_VR.view.fov = hfovRight
		g_VR.view.aspectratio = aspectRight
		g_VR.view.x = rtHalfW
		g_VR.view.y = 0
		g_VR.view.w = rtHalfW
		g_VR.view.h = rtH
		hook.Call("VRMod_PreRender", nil, "right")
		render.RenderView(g_VR.view)
		-- death animation
		if ply and not ply:Alive() then
			vrmod.utils.DrawDeathAnimation(g_VR.rtWidth, g_VR.rtHeight)
			vrmod.logger.Debug("Player is dead, drawing death animation.")
		else
			g_VR.deathTime = nil
		end

		render.PopRenderTarget()
		-- desktop view remains untouched
		if g_VR.desktopView > 1 then
			render.CullMode(1)
			surface.SetDrawColor(255, 255, 255, 255)
			surface.SetMaterial(g_VR.rtMaterial)
			surface.DrawTexturedRectUV(-1, -1, 2, 2, cropHorizontalOffset, 1 - cropVerticalMargin, 0.5 + cropHorizontalOffset, cropVerticalMargin)
			render.CullMode(0)
			vrmod.logger.Debug("Desktop view rendered.")
		end
	end

	-- 1) Startup checks & init
	local function PerformStartup()
		local err = vrmod.GetStartupError()
		if err then
			vrmod.logger.Err("Failed to start: " .. err)
			return false
		end

		VRMOD_Shutdown() -- ensure clean state
		if VRMOD_Init() == false then
			vrmod.logger.Err("Init failed")
			return false
		end
		return true
	end

	-- 2) Convar overrides for performance
	local function OverridePerformanceConvars()
		local convarOverrides = {
			cl_threaded_bone_setup = "1",
			gmod_mcore_test = "1",
			mat_queue_mode = "1",
			mat_disable_bloom = "1",
			mat_disable_fancy_blending = "1",
			mat_disable_lightwarp = "1",
			mat_disable_ps_patch = "1",
			mat_motion_blur_enabled = "0",
			mat_reduceparticles = "1",
			r_lod = "2",
			r_shadowrendertotexture = "0",
			r_3dsky = tostring(convars.vrmod_skybox:GetBool() and 1 or 0),
			r_threaded_particles = "1",
			r_queued_ropes = "1",
		}

		for cvar, val in pairs(convarOverrides) do
			overrideConvar(cvar, val)
		end
	end

	-- 3) Display parameters & render target setup
	local function SetupRenderTargets()
		local hOffset = convars.vrmod_horizontaloffset:GetFloat()
		local vOffset = convars.vrmod_verticaloffset:GetFloat()
		local scaleFactor = convars.vrmod_scalefactor:GetFloat()
		local renderOffset = convars.vrmod_renderoffset:GetBool()
		g_VR.desktopView = convars.vrmod_desktopview:GetInt()
		-- compute display params with fallback
		local dp = ComputeDisplayParams() or {}
		g_VR.rtWidth = dp.rtW or 1024
		g_VR.rtHeight = dp.rtH or 1024
		leftCalc = dp.leftCalc or 0
		rightCalc = dp.rightCalc or 0
		hfovLeft = dp.hfovL or 90
		hfovRight = dp.hfovR or 90
		aspectLeft = dp.aspL or 1
		aspectRight = dp.aspR or 1
		ipd = dp.ipd or 0.064
		eyez = dp.eyez or 0
		cropVerticalMargin, cropHorizontalOffset = vrmod.utils.ComputeDesktopCrop(g_VR.desktopView, g_VR.rtWidth, g_VR.rtHeight)
		VRMOD_ShareTextureBegin()
		local rtName = "vrmod_rt_" .. tostring(SysTime())
		-- safe fallback for constants
		local depthMode = MATERIAL_RT_DEPTH_SEPARATE or 0
		local rtFlags = CREATERENDERTARGETFLAGS_UNFILTERABLE_OK or 0
		local imgFormat = IMAGE_FORMAT_RGBA8888
		g_VR.rt = GetRenderTargetEx(rtName, g_VR.rtWidth, g_VR.rtHeight, RT_SIZE_LITERAL or 0, depthMode, 0, rtFlags, imgFormat)
		local matName = "vrmod_rt_mat_" .. tostring(SysTime())
		g_VR.rtMaterial = CreateMaterial(matName, "UnlitGeneric", {
			["$basetexture"] = g_VR.rt:GetName()
		})

		VRMOD_ShareTextureFinish()
		-- submit bounds
		local bounds = {vrmod.utils.ComputeSubmitBounds(leftCalc, rightCalc, hOffset, vOffset, scaleFactor, renderOffset)}
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
			VRMOD_UpdatePosesAndActions()
			UpdateTracking()
			UpdateCollisionsAndWepPos()
			HandleInput()
			VRUtilNetUpdateLocalPly()
			UpdateViewFromEntity()
			PerformRenderViews()
			VRMOD_SubmitSharedTexture()
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
			vrmod.logger.Info("Ended VR session")
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
		vrmod.logger.Info("Started VR session")
	end
end