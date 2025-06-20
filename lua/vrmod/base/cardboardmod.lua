if SERVER then return end
CreateClientConVar("cardboardmod_scale", "39.37008", true, false)
CreateClientConVar("cardboardmod_sensitivity", "0.01", true, false)
local ogMcore, ogBorder, ogVMFOV
concommand.Add("cardboardmod_start", function(ply, cmd, args)
	ogMcore = GetConVar("gmod_mcore_test"):GetString()
	if g_SpawnMenu then
		ogBorder = GetConVar("spawnmenu_border"):GetString()
		RunConsoleCommand("spawnmenu_border", "0")
	end

	ogVMFOV = GetConVar("viewmodel_fov"):GetString()
	RunConsoleCommand("gmod_mcore_test", "0")
	RunConsoleCommand("viewmodel_fov", "90")
	if VRMOD_GetVersion() >= 12 then VRMOD_Shutdown() end
	if VRMOD_Init() == false then
		print("vr init failed")
		return
	end

	--
	local displayInfo = VRMOD_GetDisplayInfo(1, 10)
	local displayCalculations = {
		left = {},
		right = {}
	}

	for k, v in pairs(displayCalculations) do
		local mtx = k == "left" and displayInfo.ProjectionLeft or displayInfo.ProjectionRight
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

	local uMinLeft = 0.0 + displayCalculations.left.HorizontalOffset * 0.25
	local uMaxLeft = 0.5 + displayCalculations.left.HorizontalOffset * 0.25
	local vMinLeft = 0.0 - displayCalculations.left.VerticalOffset * 0.5
	local vMaxLeft = 1.0 - displayCalculations.left.VerticalOffset * 0.5
	local uMinRight = 0.5 + displayCalculations.right.HorizontalOffset * 0.25
	local uMaxRight = 1.0 + displayCalculations.right.HorizontalOffset * 0.25
	local vMinRight = 0.0 - displayCalculations.right.VerticalOffset * 0.5
	local vMaxRight = 1.0 - displayCalculations.right.VerticalOffset * 0.5
	VRMOD_SetSubmitTextureBounds(uMinLeft, vMinLeft, uMaxLeft, vMaxLeft, uMinRight, vMinRight, uMaxRight, vMaxRight)
	local hfovLeft = displayCalculations.left.HorizontalFOV
	local hfovRight = displayCalculations.right.HorizontalFOV
	local aspectLeft = displayCalculations.left.AspectRatio
	local aspectRight = displayCalculations.right.AspectRatio
	local ipd = displayInfo.TransformRight[1][4] * 2
	local eyez = displayInfo.TransformRight[3][4]
	local rtWidth, rtHeight = displayInfo.RecommendedWidth * 2, displayInfo.RecommendedHeight
	--
	VRMOD_ShareTextureBegin()
	local rt = GetRenderTarget("rt_cardboardmod" .. math.floor(SysTime()), rtWidth, rtHeight)
	VRMOD_ShareTextureFinish()
	VRMOD_SetActionManifest("vrmod/vrmod_action_manifest.txt")
	VRMOD_SetActiveActionSets("/actions/vrmod")
	local scale = GetConVar("cardboardmod_scale"):GetFloat()
	local view = {
		x = 0,
		y = 0,
		w = rtWidth / 2,
		h = rtHeight,
		--aspectratio = aspect,
		--fov = hfov,
		drawmonitors = true,
		--viewmodelfov = hfov,
		dopostprocess = true,
		bloomtone = true,
		drawviewmodel = false
	}

	local tracking = {}
	local pitchOffset, yawOffset = 0, 0
	local sensitivity = GetConVar("cardboardmod_sensitivity"):GetFloat()
	hook.Add("CreateMove", "cardboardmod_createmove", function(cmd)
		if tracking.hmd then
			yawOffset = yawOffset - cmd:GetMouseX() * sensitivity
			pitchOffset = pitchOffset + cmd:GetMouseY() * sensitivity
			cmd:SetViewAngles(Angle(tracking.hmd.ang.pitch + pitchOffset, tracking.hmd.ang.yaw + yawOffset, tracking.hmd.ang.roll))
		end
	end)

	local rt_hud = GetRenderTarget("rt_cardboardmod_hud" .. math.floor(SysTime()), rtWidth, rtHeight, false)
	local mat_hud = CreateMaterial("mat_cardboardmod_hud" .. math.floor(SysTime()), "UnlitGeneric", {
		["$basetexture"] = rt_hud:GetName(),
		["$translucent"] = 1
	})

	hook.Add("HUDShouldDraw", "cardboardmod_hudshoulddraw", function(name) if name == "CHudWeaponSelection" then render.SetRenderTarget(rt_hud) end end)
	vgui.GetWorldPanel():SetSize(1024, 768)
	--local panels = vgui.GetWorldPanel():GetChildren()
	--panels[#panels+1] = GetHUDPanel()
	--for k,v in pairs(panels) do
	--	v:SetPaintedManually(true)
	--end
	local panels = {g_SpawnMenu, g_ContextMenu}
	hook.Add("PostDrawTranslucentRenderables", "cardboardmod_postdrawtranslucentrenderables", function()
		local _, ang = LocalToWorld(Vector(), Angle(0, -90, 90), Vector(), LocalPlayer():EyeAngles())
		LocalPlayer():GetViewModel():DrawModel()
		cam.IgnoreZ(true)
		cam.Start3D2D(LocalPlayer():EyePos() - ang:Up() * 100 - ang:Forward() * 512 * 0.1 - ang:Right() * 384 * 0.1, ang, 0.1)
		surface.SetDrawColor(255, 255, 255, 255)
		surface.SetMaterial(mat_hud)
		local tmp = render.GetToneMappingScaleLinear()
		render.SetToneMappingScaleLinear(Vector(0.8, 0.8, 0.8))
		surface.DrawTexturedRectUV(0, 0, 1024, 768, 0, 0, 1024 / rtWidth, 768 / rtHeight)
		render.SetToneMappingScaleLinear(tmp)
		--surface.SetDrawColor(255,0,0,255)
		--surface.DrawOutlinedRect(0,0,1024,768)
		cam.End3D2D()
		cam.IgnoreZ(false)
	end)

	--local screentex = render.GetScreenEffectTexture()
	hook.Add("RenderScene", "cardboardmod_renderscene", function(viewOrigin, viewAngles)
		VRMOD_SubmitSharedTexture()
		VRMOD_UpdatePosesAndActions()
		tracking = VRMOD_GetPoses()
		render.PushRenderTarget(rt)
		--render stereo views
		view.angles = viewAngles
		view.origin = viewOrigin + view.angles:Right() * -((ipd * scale) / 2)
		view.x = 0
		view.fov = hfovLeft
		view.aspectratio = aspectLeft
		render.RenderView(view)
		view.origin = viewOrigin + view.angles:Right() * ipd * scale
		view.x = rtWidth / 2
		view.fov = hfovRight
		view.aspectratio = aspectRight
		render.RenderView(view)
		render.PopRenderTarget()
		--update hud texture
		render.SetRenderTarget(rt_hud)
		cam.Start2D()
		render.OverrideAlphaWriteEnable(true, true)
		render.Clear(0, 0, 0, 0, true, true)
		render.RenderHUD(0, 0, 1024, 768)
		for k, v in pairs(panels) do
			if IsValid(v) and v:IsVisible() then v:PaintManual() end
		end

		if vgui.CursorVisible() then
			local x, y = input.GetCursorPos()
			surface.SetDrawColor(255, 0, 0, 255)
			surface.DrawRect(x - 5, y - 5, 10, 10)
		end

		render.OverrideAlphaWriteEnable(false)
		cam.End2D()
		render.SetRenderTarget(nil)
		return true
	end)
end)

concommand.Add("cardboardmod_exit", function(ply, cmd, args)
	VRMOD_Shutdown()
	hook.Remove("RenderScene", "cardboardmod_renderscene")
	hook.Remove("PostDrawTranslucentRenderables", "cardboardmod_postdrawtranslucentrenderables")
	hook.Remove("HUDShouldDraw", "cardboardmod_hudshoulddraw")
	hook.Add("CreateMove", "cardboardmod_createmove", function(cmd)
		cmd:SetViewAngles(Angle(0, 0, 0))
		hook.Remove("CreateMove", "cardboardmod_createmove")
	end)

	RunConsoleCommand("gmod_mcore_test", ogMcore)
	if g_SpawnMenu then RunConsoleCommand("spawnmenu_border", ogBorder) end
	RunConsoleCommand("viewmodel_fov", ogVMFOV)
	vgui.GetWorldPanel():SetSize(ScrW(), ScrH())
end)