g_VR = g_VR or {}

local convars = vrmod.GetConvars()

vrmod.AddCallbackedConvar("vrmod_configversion", nil, "5")

if convars.vrmod_configversion:GetString() ~= convars.vrmod_configversion:GetDefault() then
	timer.Simple(1,function()
		for k,v in pairs(convars) do
			pcall(function() v:Revert() end) --reverting certain convars makes error
		end
	end)
end

if CLIENT then

	g_VR.scale = 0
	g_VR.origin = Vector(0,0,0)
	g_VR.originAngle = Angle(0,0,0)
	g_VR.viewModel = nil --this will point to either the viewmodel, worldmodel or nil
	g_VR.viewModelMuzzle = nil
	g_VR.viewModelPos = Vector(0,0,0)
	g_VR.viewModelAng = Angle(0,0,0)
	g_VR.usingWorldModels = false
	g_VR.active = false
	g_VR.threePoints = false --hmd + 2 controllers
	g_VR.sixPoints = false --hmd + 2 controllers + 3 trackers
	g_VR.tracking = {}
	g_VR.input = {}
	g_VR.changedInputs = {}
	g_VR.errorText = ""
	local vScale = system.IsLinux() and 0.25 or 0.5
	local hScale = system.IsLinux() and 0.20 or 0.25
	
	--todo move some of these to the files where they belong
	vrmod.AddCallbackedConvar("vrmod_althead", nil, "0")
	vrmod.AddCallbackedConvar("vrmod_autostart", nil, "0")
	vrmod.AddCallbackedConvar("vrmod_scale", nil, "32.7")
	vrmod.AddCallbackedConvar("vrmod_vertical_scale", nil, vScale)
	vrmod.AddCallbackedConvar("vrmod_horizontal_scale", nil, hScale)
	vrmod.AddCallbackedConvar("vrmod_heightmenu", nil, "1")
	vrmod.AddCallbackedConvar("vrmod_floatinghands", nil, "0")
	vrmod.AddCallbackedConvar("vrmod_desktopview", nil, "3")
	vrmod.AddCallbackedConvar("vrmod_useworldmodels", nil, "0")
	vrmod.AddCallbackedConvar("vrmod_laserpointer", nil, "0")
	vrmod.AddCallbackedConvar("vrmod_znear", nil, "1")
	vrmod.AddCallbackedConvar("vrmod_oldcharacteryaw", nil, "0")
	vrmod.AddCallbackedConvar("vrmod_controlleroffset_x", nil, "-15")
	vrmod.AddCallbackedConvar("vrmod_controlleroffset_y", nil, "-1")
	vrmod.AddCallbackedConvar("vrmod_controlleroffset_z", nil, "5")
	vrmod.AddCallbackedConvar("vrmod_controlleroffset_pitch", nil, "50")
	vrmod.AddCallbackedConvar("vrmod_controlleroffset_yaw", nil, "0")
	vrmod.AddCallbackedConvar("vrmod_controlleroffset_roll", nil, "0")
	vrmod.AddCallbackedConvar("vrmod_postprocess", nil, "0", nil, nil, nil, nil, tobool, function(val)
		if g_VR.view then
			g_VR.view.dopostprocess = val
		end
	end)
	
	hook.Add("VRMod_Menu","vrmod_options",function(frame)
		local form = frame.SettingsForm
		form:CheckBox("Use floating hands", "vrmod_floatinghands")
		form:CheckBox("Use weapon world models", "vrmod_useworldmodels")
		form:CheckBox("Add laser pointer to tools/weapons", "vrmod_laserpointer")
		--
		local tmp = form:CheckBox("Show height adjustment menu", "vrmod_heightmenu")
		local checkTime = 0
		function tmp:OnChange(checked)
			if checked and SysTime()-checkTime < 0.1 then --only triggers when checked manually (not when using reset button)
				VRUtilOpenHeightMenu()
			end
			checkTime = SysTime()
		end
		--
		form:CheckBox("Alternative head angle manipulation method", "vrmod_althead")
		form:ControlHelp("Less precise, compatibility for jigglebones")
		form:CheckBox("Automatically start VR after map loads", "vrmod_autostart")
		form:CheckBox("Replace climbing mechanics (when available)", "vrmod_climbing")
		form:CheckBox("Replace door use mechanics (when available)", "vrmod_doors")
		form:CheckBox("Enable engine postprocessing", "vrmod_postprocess")
		--
		local panel = vgui.Create( "DPanel" )
		panel:SetSize( 300, 30 )
		panel.Paint = function() end			
		local dlabel = vgui.Create( "DLabel", panel )
		dlabel:SetSize(100,30)
		dlabel:SetPos(0,-3)
		dlabel:SetText( "Desktop view:" )
		dlabel:SetColor(Color(0,0,0))
		local DComboBox = vgui.Create( "DComboBox",panel )
		DComboBox:Dock( TOP )
		DComboBox:DockMargin( 70, 0, 0, 5 )
		DComboBox:AddChoice( "none" )
		DComboBox:AddChoice( "left eye" )
		DComboBox:AddChoice( "right eye" )
		DComboBox.OnSelect = function( self, index, value )
			convars.vrmod_desktopview:SetInt(index)
		end
		DComboBox.Think = function(self)
			local v = convars.vrmod_desktopview:GetInt()
			if self.ConvarVal ~= v then
				self.ConvarVal = v
				self:ChooseOptionID(v)
			end
		end
		form:AddItem(panel)
		--
		form:Button("Edit custom controller input actions","vrmod_actioneditor")
		form:Button("Reset settings to default","vrmod_reset")
		--
		local offsetForm = vgui.Create("DForm",form)
		offsetForm:SetName("Controller offsets")
		offsetForm:Dock(TOP)
		offsetForm:DockMargin(10,10,10,0)
		offsetForm:DockPadding(0,0,0,0)
		offsetForm:SetExpanded(false)
		local tmp = offsetForm:NumSlider("X","vrmod_controlleroffset_x",-30,30,0)
		tmp.PerformLayout = function(self) self.TextArea:SetWide(30) self.Label:SetWide(30) end
		tmp = offsetForm:NumSlider("Y","vrmod_controlleroffset_y",-30,30,0)
		tmp.PerformLayout = function(self) self.TextArea:SetWide(30) self.Label:SetWide(30) end
		tmp = offsetForm:NumSlider("Z","vrmod_controlleroffset_z",-30,30,0)
		tmp.PerformLayout = function(self) self.TextArea:SetWide(30) self.Label:SetWide(30) end
		tmp = offsetForm:NumSlider("Pitch","vrmod_controlleroffset_pitch",-180,180,0)
		tmp.PerformLayout = function(self) self.TextArea:SetWide(30) self.Label:SetWide(30) end
		tmp = offsetForm:NumSlider("Yaw","vrmod_controlleroffset_yaw",-180,180,0)
		tmp.PerformLayout = function(self) self.TextArea:SetWide(30) self.Label:SetWide(30) end
		tmp = offsetForm:NumSlider("Roll","vrmod_controlleroffset_roll",-180,180,0)
		tmp.PerformLayout = function(self) self.TextArea:SetWide(30) self.Label:SetWide(30) end
		local tmp = offsetForm:Button("Apply offsets","")
		function tmp:OnReleased()
			g_VR.rightControllerOffsetPos  = Vector(convars.vrmod_controlleroffset_x:GetFloat(), convars.vrmod_controlleroffset_y:GetFloat(), convars.vrmod_controlleroffset_z:GetFloat())
			g_VR.leftControllerOffsetPos  = g_VR.rightControllerOffsetPos * Vector(1,-1,1)
			g_VR.rightControllerOffsetAng = Angle(convars.vrmod_controlleroffset_pitch:GetFloat(), convars.vrmod_controlleroffset_yaw:GetFloat(), convars.vrmod_controlleroffset_roll:GetFloat())
			g_VR.leftControllerOffsetAng = g_VR.rightControllerOffsetAng
		end
		--
	end)
		
	concommand.Add( "vrmod_start", function( ply, cmd, args )
		if vgui.CursorVisible() then
			print("vrmod: attempting startup when game is unpaused")
		end
		timer.Create("vrmod_start",0.1,0,function()
			if not vgui.CursorVisible() then
				timer.Remove("vrmod_start")
				VRUtilClientStart()
			end
		end)
	end )
	
	concommand.Add( "vrmod_exit", function( ply, cmd, args )
		timer.Remove("vrmod_start")
		VRUtilClientExit()
	end )
	
	concommand.Add( "vrmod_reset", function( ply, cmd, args )
		for k,v in pairs(vrmod.GetConvars()) do
			pcall(function() v:Revert() end)
		end
		hook.Call("VRMod_Reset")
	end )
	
	
	concommand.Add( "vrmod_info", function( ply, cmd, args )
		print("========================================================================")
		print(string.format("| %-30s %s", "Addon Version:",vrmod.GetVersion()))
		print(string.format("| %-30s %s", "Module Version:",vrmod.GetModuleVersion()))
		print(string.format("| %-30s %s", "GMod Version:",VERSION..", Branch: "..BRANCH))
		print(string.format("| %-30s %s", "Operating System:",system.IsWindows() and "Windows" or system.IsLinux() and "Linux" or system.IsOSX() and "OSX" or "Unknown"))
		print(string.format("| %-30s %s", "Server Type:",game.SinglePlayer() and "Single Player" or "Multiplayer"))
		print(string.format("| %-30s %s", "Server Name:",GetHostName()))
		print(string.format("| %-30s %s", "Server Address:",game.GetIPAddress()))
		print(string.format("| %-30s %s", "Gamemode:",GAMEMODE_NAME))
		local workshopCount = 0
		for k,v in ipairs(engine.GetAddons()) do
			workshopCount = workshopCount + (v.mounted and 1 or 0)
		end
		local _,folders = file.Find("addons/*","GAME")
		local legacyBlacklist = {checkers=true,chess=true,common=true,go=true,hearts=true,spades=true}
		local legacyCount = 0
		for k,v in ipairs(folders) do
			legacyCount = legacyCount+ (legacyBlacklist[v] == nil and 1 or 0)
		end
		print(string.format("| %-30s %s", "Workshop Addons:",workshopCount))
		print(string.format("| %-30s %s", "Legacy Addons:",legacyCount))
		print("|----------")
		local function test(path)
			local files, folders = file.Find(path.."/*","GAME")
			for k,v in ipairs(folders) do
				test(path.."/"..v)
			end
			for k,v in ipairs(files) do
				print(string.format("| %-60s %X", path.."/"..v,util.CRC(file.Read(path.."/"..v,"GAME") or "")))
			end
		end
		test("data/vrmod")
		print("|----------")
		test("lua/bin")
		print("|----------")
		local convarNames = {}
		for k,v in pairs(convars) do
			convarNames[#convarNames+1] = v:GetName()
		end
		table.sort(convarNames)
		for k,v in ipairs(convarNames) do
			v = GetConVar(v)
			print(string.format("| %-30s %-20s %s",v:GetName(),v:GetString(),v:GetString()==v:GetDefault() and "" or "*"))
		end
		print("========================================================================")
	end )
	
		local moduleLoaded = false
		g_VR.moduleVersion = 0
		if system.IsLinux() then
			moduleFile = "lua/bin/gmcl_vrmod_linux64.dll"
		else
			moduleFile = "lua/bin/gmcl_vrmod_win32.dll"
		end


		if file.Exists(moduleFile, "GAME") then
			local tmp = vrmod
			vrmod = {}
			moduleLoaded = pcall(function() require("vrmod") end)
			for k,v in pairs(vrmod) do
				_G["VRMOD_"..k] = v
			end
			vrmod = tmp
			g_VR.moduleVersion = moduleLoaded and VRMOD_GetVersion and VRMOD_GetVersion() or 0
		end
	
	local convarOverrides = {}
	
	local function overrideConvar(name, value)
		local cv = GetConVar(name)
		if cv then
			convarOverrides[name] = cv:GetString()
			RunConsoleCommand(name, value)
		end
	end
	local function restoreConvarOverrides()
		for k,v in pairs(convarOverrides) do
			RunConsoleCommand(k, v)
		end
		convarOverrides = {}
	end
	
	local function pow2ceil(x)
		return math.pow(2, math.ceil(math.log(x,2)))
	end
	
	function VRUtilClientStart()

		local error = vrmod.GetStartupError()
		if error then
			print("VRMod failed to start: "..error)
			return
		end

		VRMOD_Shutdown() --in case we're retrying after an error and shutdown wasn't called
		
		if VRMOD_Init() == false then
			print("vr init failed")
			return
		end
		
		local displayInfo = VRMOD_GetDisplayInfo(1,10)

		local rtWidth, rtHeight = displayInfo.RecommendedWidth*2, displayInfo.RecommendedHeight
		if system.IsLinux() then
			rtWidth, rtHeight = math.min(4096,rtWidth), math.min(4096,rtHeight) 
		end
		
		VRMOD_ShareTextureBegin()
		g_VR.rt = GetRenderTarget( "vrmod_rt".. tostring(SysTime()), rtWidth, rtHeight)
		VRMOD_ShareTextureFinish()
		
		local displayCalculations = { left = {}, right = {}}
		
		for k,v in pairs(displayCalculations) do
			local mtx = (k=="left") and displayInfo.ProjectionLeft or displayInfo.ProjectionRight
			local xscale = mtx[1][1]
			local xoffset = mtx[1][3]
			local yscale = mtx[2][2]
			local yoffset = mtx[2][3]
			local tan_px = math.abs((1.0 - xoffset) / xscale)
			local tan_nx = math.abs((-1.0 - xoffset) / xscale)
			local tan_py = math.abs((1.0 - yoffset) / yscale)
			local tan_ny = math.abs((-1.0 - yoffset) / yscale)
			local w = tan_px + tan_nx
			local h = tan_py + tan_ny
			v.HorizontalFOV = math.atan(w / 2.0) * 180 / math.pi * 2
			v.AspectRatio = w / h
			v.HorizontalOffset = xoffset
			v.VerticalOffset = yoffset
		end
		
		local wLeft = (math.abs((1.0 - displayInfo.ProjectionLeft[1][3]) / displayInfo.ProjectionLeft[1][1]) +
               math.abs((-1.0 - displayInfo.ProjectionLeft[1][3]) / displayInfo.ProjectionLeft[1][1]))
		local hLeft = (math.abs((1.0 - displayInfo.ProjectionLeft[2][3]) / displayInfo.ProjectionLeft[2][2]) +
					math.abs((-1.0 - displayInfo.ProjectionLeft[2][3]) / displayInfo.ProjectionLeft[2][2]))

		local wRight = (math.abs((1.0 - displayInfo.ProjectionRight[1][3]) / displayInfo.ProjectionRight[1][1]) +
						math.abs((-1.0 - displayInfo.ProjectionRight[1][3]) / displayInfo.ProjectionRight[1][1]))
		local hRight = (math.abs((1.0 - displayInfo.ProjectionRight[2][3]) / displayInfo.ProjectionRight[2][2]) +
						math.abs((-1.0 - displayInfo.ProjectionRight[2][3]) / displayInfo.ProjectionRight[2][2]))

		-- Average both eyes
		local wAvg = (wLeft + wRight) / 2
		local hAvg = (hLeft + hRight) / 2

		local hFactor = 0.5 / wAvg
		local vFactor = 1.0 / hAvg

		local vMin = system.IsWindows() and 0 or 1
		local vMax =  system.IsWindows() and 1 or 0
		--local vFactor = convars.vrmod_vertical_scale:GetFloat()
		--local hFactor = convars.vrmod_horizontal_scale:GetFloat()
		local vMinLeft = vMin - math.abs(displayCalculations.left.VerticalOffset * vFactor)
		local vMaxLeft = vMax - math.abs(displayCalculations.left.VerticalOffset * vFactor)
		local vMinRight = vMin - math.abs(displayCalculations.right.VerticalOffset * vFactor)
		local vMaxRight = vMax - math.abs(displayCalculations.right.VerticalOffset * vFactor)
		local uMinLeft =  0.0 + displayCalculations.left.HorizontalOffset * hFactor
		local uMaxLeft = 0.5 + displayCalculations.left.HorizontalOffset * hFactor
		local uMinRight = 0.5 + displayCalculations.right.HorizontalOffset * hFactor
		local uMaxRight = 1.0 + displayCalculations.right.HorizontalOffset * hFactor

		VRMOD_SetSubmitTextureBounds(uMinLeft, vMinLeft, uMaxLeft, vMaxLeft, uMinRight, vMinRight, uMaxRight, vMaxRight)

		local hfovLeft = displayCalculations.left.HorizontalFOV
		local hfovRight = displayCalculations.right.HorizontalFOV

		local aspectLeft = displayCalculations.left.AspectRatio
		local aspectRight = displayCalculations.right.AspectRatio
		local ipd = displayInfo.TransformRight[1][4]*2
		local eyez = displayInfo.TransformRight[3][4]

		--set up active bindings
		VRMOD_SetActionManifest("vrmod/vrmod_action_manifest.txt")
		VRMOD_SetActiveActionSets("/actions/base", LocalPlayer():InVehicle() and "/actions/driving" or "/actions/main")
		VRUtilLoadCustomActions()
		g_VR.input, g_VR.changedInputs = VRMOD_GetActions() --make inputs immediately available
		
		--start transmit loop and send join msg to server
		VRUtilNetworkInit() 
		
		--set initial origin
		g_VR.origin = LocalPlayer():GetPos()
		
		--
		g_VR.scale = convars.vrmod_scale:GetFloat()
		
		--
		g_VR.rightControllerOffsetPos  = Vector(convars.vrmod_controlleroffset_x:GetFloat(), convars.vrmod_controlleroffset_y:GetFloat(), convars.vrmod_controlleroffset_z:GetFloat())
		g_VR.leftControllerOffsetPos  = g_VR.rightControllerOffsetPos * Vector(1,-1,1)
		g_VR.rightControllerOffsetAng = Angle(convars.vrmod_controlleroffset_pitch:GetFloat(), convars.vrmod_controlleroffset_yaw:GetFloat(), convars.vrmod_controlleroffset_roll:GetFloat())
		g_VR.leftControllerOffsetAng = g_VR.rightControllerOffsetAng
		
		g_VR.active = true
		
		overrideConvar("pac_suppress_frames", "0")
		overrideConvar("pac_override_fov", "1")
		overrideConvar("mat_queue_mode", "1")
		overrideConvar("gmod_mcore_test", "1")
		
		--3D audio fix
		hook.Add("CalcView","vrutil_hook_calcview",function(ply, pos, ang, fv)
			return {origin = g_VR.tracking.hmd.pos, angles = g_VR.tracking.hmd.ang, fov = fv} 
		end)
		
		vrmod.StartLocomotion()
		
		
		g_VR.tracking = {
			hmd = {pos=LocalPlayer():GetPos()+Vector(0,0,66.8),ang=Angle(),vel=Vector(),angvel=Angle()},
			pose_lefthand = {pos=LocalPlayer():GetPos(),ang=Angle(),vel=Vector(),angvel=Angle()},
			pose_righthand = {pos=LocalPlayer():GetPos(),ang=Angle(),vel=Vector(),angvel=Angle()},
		}
		g_VR.threePoints = true
		
		--simulate missing hands
		local simulate = {
			{pose = g_VR.tracking.pose_lefthand, offset = Vector(0,10,-30)},
			{pose = g_VR.tracking.pose_righthand, offset = Vector(0,-10,-30)},
		}
		for k,v in ipairs(simulate) do v.pose.simulatedPos = v.pose.pos end
		hook.Add("VRMod_Tracking","simulatehands",function()
			for k,v in ipairs(simulate) do
				if v.pose.pos == v.pose.simulatedPos then
					v.pose.pos,v.pose.ang = LocalToWorld(v.offset,Angle(90,0,0),g_VR.tracking.hmd.pos,Angle(0,g_VR.tracking.hmd.ang.yaw,0)) 
					v.pose.simulatedPos = v.pose.pos
				else
					v.pose.simulatedPos = nil
					table.remove(simulate,k)
				end
			end
			if #simulate == 0 then
				hook.Remove("VRMod_Tracking","simulatehands")
			end
		end)
		
		
		--rendering
		
		
		g_VR.view = {
				x = 0, y = 0,
				w = rtWidth/2, h = rtHeight,
				--aspectratio = aspect,
				--fov = hfov,
				drawmonitors = true,
				drawviewmodel = false,
				znear = convars.vrmod_znear:GetFloat(),
				dopostprocess = convars.vrmod_postprocess:GetBool()
			}
		
		local desktopView = convars.vrmod_desktopview:GetInt()
		local cropVerticalMargin = (1 - (ScrH()/ScrW() * (rtWidth/2) / rtHeight)) / 2
		local cropHorizontalOffset = (desktopView==3) and 0.5 or 0
		local mat_rt = CreateMaterial("vrmod_mat_rt"..tostring(SysTime()), "UnlitGeneric",{ ["$basetexture"] = g_VR.rt:GetName() })
			
		local localply = LocalPlayer()
		local currentViewEnt = localply
		local pos1, ang1
			
		hook.Add("RenderScene","vrutil_hook_renderscene",function()
			
			VRMOD_SubmitSharedTexture()
			VRMOD_UpdatePosesAndActions()

			--handle tracking
			local rawPoses = VRMOD_GetPoses()
			for k,v in pairs(rawPoses) do
				g_VR.tracking[k] = g_VR.tracking[k] or {}
				local worldPose = g_VR.tracking[k]
				worldPose.pos, worldPose.ang = LocalToWorld(v.pos * g_VR.scale, v.ang, g_VR.origin, g_VR.originAngle)
				worldPose.vel = LocalToWorld(v.vel, Angle(0,0,0), Vector(0,0,0), g_VR.originAngle) * g_VR.scale
				worldPose.angvel = LocalToWorld(Vector(v.angvel.pitch, v.angvel.yaw, v.angvel.roll), Angle(0,0,0), Vector(0,0,0), g_VR.originAngle)
				if k == "pose_righthand" then
					worldPose.pos, worldPose.ang = LocalToWorld(g_VR.rightControllerOffsetPos * 0.01 * g_VR.scale, g_VR.rightControllerOffsetAng, worldPose.pos, worldPose.ang)
				elseif k == "pose_lefthand" then
					worldPose.pos, worldPose.ang = LocalToWorld(g_VR.leftControllerOffsetPos * 0.01 * g_VR.scale, g_VR.leftControllerOffsetAng, worldPose.pos, worldPose.ang)
				end
			end
			g_VR.sixPoints = (g_VR.tracking.pose_waist and g_VR.tracking.pose_leftfoot and g_VR.tracking.pose_rightfoot) ~= nil
			hook.Call("VRMod_Tracking")
			
			--handle input
			g_VR.input, g_VR.changedInputs = VRMOD_GetActions()
			for k,v in pairs(g_VR.changedInputs) do
				hook.Call("VRMod_Input",nil,k,v)
			end
			
			--
			if not system.HasFocus() or #g_VR.errorText > 0 then
				render.Clear(0,0,0,255,true,true)
				cam.Start2D()
				local text = not system.HasFocus() and "Please focus the game window" or g_VR.errorText
				draw.DrawText( text, "DermaLarge", ScrW() / 2, ScrH() / 2, Color( 255,255,255, 255 ), TEXT_ALIGN_CENTER )
				cam.End2D()
				return true
			end
			
			--update clientside local player net frame
			local netFrame = VRUtilNetUpdateLocalPly()
			
			--update viewmodel position
			if g_VR.currentvmi then
				local pos, ang = LocalToWorld(g_VR.currentvmi.offsetPos,g_VR.currentvmi.offsetAng,g_VR.tracking.pose_righthand.pos,g_VR.tracking.pose_righthand.ang)
				g_VR.viewModelPos = pos
				g_VR.viewModelAng = ang
			end
			if IsValid(g_VR.viewModel) then
				if not g_VR.usingWorldModels then
					g_VR.viewModel:SetPos(g_VR.viewModelPos)
					g_VR.viewModel:SetAngles(g_VR.viewModelAng)
					g_VR.viewModel:SetupBones()
					--override hand pose in net frame
					if netFrame then
						local b = g_VR.viewModel:LookupBone("ValveBiped.Bip01_R_Hand")
						if b then
							local mtx = g_VR.viewModel:GetBoneMatrix(b)
							netFrame.righthandPos = mtx:GetTranslation()
							netFrame.righthandAng = mtx:GetAngles() - Angle(0,0,180)
						end
					end
				end
				g_VR.viewModelMuzzle = g_VR.viewModel:GetAttachment(1)
			end
			
			--set view according to viewentity
			local viewEnt = localply:GetViewEntity()
			if viewEnt ~= localply then
				local rawPos, rawAng = WorldToLocal(g_VR.tracking.hmd.pos, g_VR.tracking.hmd.ang, g_VR.origin, g_VR.originAngle)
				if viewEnt ~= currentViewEnt then
					local pos,ang = LocalToWorld(rawPos,rawAng,viewEnt:GetPos(),viewEnt:GetAngles())
					pos1, ang1 = WorldToLocal(viewEnt:GetPos(),viewEnt:GetAngles(),pos,ang)
				end
				rawPos, rawAng = LocalToWorld(rawPos, rawAng, pos1, ang1)
				g_VR.view.origin, g_VR.view.angles = LocalToWorld(rawPos,rawAng,viewEnt:GetPos(),viewEnt:GetAngles())
			else
				g_VR.view.origin, g_VR.view.angles = g_VR.tracking.hmd.pos, g_VR.tracking.hmd.ang
			end
			currentViewEnt = viewEnt
			
			--
			g_VR.view.origin = g_VR.view.origin + g_VR.view.angles:Forward()*-(eyez*g_VR.scale)
			g_VR.eyePosLeft = g_VR.view.origin + g_VR.view.angles:Right()*-(ipd*0.5*g_VR.scale)
			g_VR.eyePosRight = g_VR.view.origin + g_VR.view.angles:Right()*(ipd*0.5*g_VR.scale)

			render.PushRenderTarget( g_VR.rt )

				-- left
				g_VR.view.origin = g_VR.eyePosLeft
				g_VR.view.x = 0
				g_VR.view.fov = hfovLeft
				g_VR.view.aspectratio = aspectLeft
				hook.Call("VRMod_PreRender")
				render.RenderView(g_VR.view)
				-- right
				
				g_VR.view.origin = g_VR.eyePosRight
				g_VR.view.x = rtWidth/2
				g_VR.view.fov = hfovRight
				g_VR.view.aspectratio = aspectRight
				hook.Call("VRMod_PreRenderRight")
				render.RenderView(g_VR.view)
				--
				if not LocalPlayer():Alive() then
					cam.Start2D()
					surface.SetDrawColor( 255, 0, 0, 128 )
					surface.DrawRect( 0, 0, rtWidth, rtHeight )
					cam.End2D()
				end
			

			render.PopRenderTarget( g_VR.rt )
			
			if desktopView == nil then
				desktopView = 0
			end

			if desktopView > 1 then
				surface.SetDrawColor(255,255,255,255)
				surface.SetMaterial(mat_rt)
				render.CullMode(1)
				surface.DrawTexturedRectUV(-1, -1, 2, 2, cropHorizontalOffset, 1-cropVerticalMargin, 0.5+cropHorizontalOffset, cropVerticalMargin)
				render.CullMode(0)
			end
			
			hook.Call("VRMod_PostRender")
			
			--return true to override default scene rendering
			return true
		end)
		
		g_VR.usingWorldModels = convars.vrmod_useworldmodels:GetBool()

		if not g_VR.usingWorldModels then
			overrideConvar("viewmodel_fov", GetConVar("fov_desired"):GetString())
	
			hook.Add("CalcViewModelView","vrutil_hook_calcviewmodelview",function(wep, vm, oldPos, oldAng, pos, ang)
				return g_VR.viewModelPos, g_VR.viewModelAng
			end)
	
			local blockViewModelDraw = true
			g_VR.allowPlayerDraw = false
			local hideplayer = convars.vrmod_floatinghands:GetBool()
			hook.Add("PostDrawTranslucentRenderables","vrutil_hook_drawplayerandviewmodel",function( bDrawingDepth, bDrawingSkybox )
				if bDrawingSkybox or not LocalPlayer():Alive() or not (EyePos()==g_VR.eyePosLeft or EyePos()==g_VR.eyePosRight) then return end
				--draw viewmodel
				if IsValid(g_VR.viewModel) then
					blockViewModelDraw = false
					g_VR.viewModel:DrawModel()
					blockViewModelDraw = true
				end
				--draw playermodel
				if not hideplayer then
					g_VR.allowPlayerDraw = true
					cam.Start3D() cam.End3D() --this invalidates ShouldDrawLocalPlayer cache
					local tmp = render.GetBlend()
					render.SetBlend(1) --without this the despawning bullet casing effect gets applied to the player???
					LocalPlayer():DrawModel()
					render.SetBlend(tmp)
					cam.Start3D() cam.End3D()
					g_VR.allowPlayerDraw = false
				end
				--draw menus
				VRUtilRenderMenuSystem()
			end)
	
			hook.Add("PreDrawPlayerHands","vrutil_hook_predrawplayerhands",function()
				return true
			end)
	
			hook.Add("PreDrawViewModel","vrutil_hook_predrawviewmodel",function(vm, ply, wep)
				return blockViewModelDraw or nil
			end)
			
		else
			g_VR.allowPlayerDraw = true
		end
		
		hook.Add("ShouldDrawLocalPlayer","vrutil_hook_shoulddrawlocalplayer",function(ply)
			return g_VR.allowPlayerDraw
		end)
	
	function VRUtilClientExit()
		if not g_VR.active then return end
		
		restoreConvarOverrides()
		VRUtilMenuClose()
		VRUtilNetworkCleanup()	
		vrmod.StopLocomotion()

		if IsValid(g_VR.viewModel) and g_VR.viewModel:GetClass() == "class C_BaseFlex" then
			g_VR.viewModel:Remove()
		end
		g_VR.viewModel = nil
		g_VR.viewModelMuzzle = nil
		
		LocalPlayer():GetViewModel().RenderOverride = nil
		LocalPlayer():GetViewModel():RemoveEffects(EF_NODRAW)
		
		hook.Remove("RenderScene","vrutil_hook_renderscene")
		hook.Remove("PreDrawViewModel","vrutil_hook_predrawviewmodel")
		hook.Remove( "DrawPhysgunBeam", "vrutil_hook_drawphysgunbeam")
		hook.Remove( "PreDrawHalos", "vrutil_hook_predrawhalos")
		hook.Remove("EntityFireBullets","vrutil_hook_entityfirebullets")
		hook.Remove("Tick","vrutil_hook_tick")
		hook.Remove("PostDrawSkyBox","vrutil_hook_postdrawskybox")
		hook.Remove("CalcView","vrutil_hook_calcview")
		hook.Remove("PostDrawTranslucentRenderables","vr_laserpointer")
		hook.Remove("CalcViewModelView","vrutil_hook_calcviewmodelview")
		hook.Remove("PostDrawTranslucentRenderables","vrutil_hook_drawplayerandviewmodel")
		hook.Remove("PreDrawPlayerHands","vrutil_hook_predrawplayerhands")
		hook.Remove("PreDrawViewModel","vrutil_hook_predrawviewmodel")
		hook.Remove("ShouldDrawLocalPlayer","vrutil_hook_shoulddrawlocalplayer")
		
		g_VR.tracking = {}
		g_VR.threePoints = false
		g_VR.sixPoints = false
		g_VR.active = false
		VRMOD_Shutdown()
		
	end
	
	hook.Add("ShutDown","vrutil_hook_shutdown",function()
		if IsValid(LocalPlayer()) and g_VR.net[LocalPlayer():SteamID()] then
			VRUtilClientExit()
		end
	end)

end
		
end