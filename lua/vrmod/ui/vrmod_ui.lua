if CLIENT then
	g_VR = g_VR or {}
	g_VR.menuFocus = false
	g_VR.menuCursorX = 0
	g_VR.menuCursorY = 0
	local _, convarValues = vrmod.GetConvars()
	vrmod.AddCallbackedConvar("vrmod_test_ui_testver", nil, 0, nil, "", 0, 1, tonumber) --cvarName, valueName, defaultValue, flags, helptext, min, max, conversionFunc, callbackFunc
	vrmod.AddCallbackedConvar("vrmod_ui_realtime", nil, 0, nil, "", 0, 1, tonumber) --cvarName, valueName, defaultValue, flags, helptext, min, max, conversionFunc, callbackFunc
	vrmod.AddCallbackedConvar("vrmod_attach_weaponmenu", nil, 1, nil, "", 0, 4, tonumber)
	vrmod.AddCallbackedConvar("vrmod_attach_quickmenu", nil, 1, nil, "", 0, 4, tonumber)
	vrmod.AddCallbackedConvar("vrmod_attach_popup", nil, 1, nil, "", 0, 4, tonumber)
	vrmod.AddCallbackedConvar("vrmod_attach_heightmenu", nil, 1, nil, "", 0, 4, tonumber)
	vrmod.AddCallbackedConvar("vrmod_beam_color", nil, "255,0,0,255")
	local uioutline = CreateClientConVar("vrmod_ui_outline", 0, true, FCVAR_ARCHIVE, nil, 0, 1)
	local rt_beam = GetRenderTarget("vrmod_rt_beam", 64, 64, false)
	local mat_beam = CreateMaterial("vrmod_mat_beam", "UnlitGeneric", {
		["$basetexture"] = rt_beam:GetName(),
		["$ignorez"] = 1
	})

	render.PushRenderTarget(rt_beam)
	--menu pointer color
	local beamColor = convarValues.vrmod_beam_color
	local r, g, b, a = string.match(beamColor, "(%d+),(%d+),(%d+),(%d+)")
	render.Clear(tonumber(r), tonumber(g), tonumber(b), tonumber(a))
	render.PopRenderTarget()
	g_VR.menus = {}
	local menus = g_VR.menus
	local menuOrder = {}
	local menusExist = false
	local prevFocusPanel = nil
	function VRUtilMenuRenderPanel(uid)
		if not menus[uid] or not menus[uid].panel or not menus[uid].panel:IsValid() then return end
		render.PushRenderTarget(menus[uid].rt)
		cam.Start2D()
		render.Clear(0, 0, 0, 0, true, true)
		local oldclip = DisableClipping(false)
		render.SetWriteDepthToDestAlpha(false)
		menus[uid].panel:PaintManual()
		render.SetWriteDepthToDestAlpha(true)
		DisableClipping(oldclip)
		cam.End2D()
		render.PopRenderTarget()
	end

	function VRUtilMenuRenderStart(uid)
		render.PushRenderTarget(menus[uid].rt)
		cam.Start2D()
		render.Clear(0, 0, 0, 0, true, true)
		render.SetWriteDepthToDestAlpha(true)
	end

	function VRUtilMenuRenderEnd()
		cam.End2D()
		render.PopRenderTarget()
	end

	function VRUtilIsMenuOpen(uid)
		return menus[uid] ~= nil
	end

	function VRUtilRenderMenuSystem()
		if menusExist == false then return end
		g_VR.menuFocus = false
		local menuFocusDist = 99999
		local menuFocusPanel = nil
		local menuFocusCursorWorldPos = nil
		local tms = render.GetToneMappingScaleLinear()
		render.SetToneMappingScaleLinear(g_VR.view.dopostprocess and Vector(0.50, 0.50, 0.50) or Vector(1, 1, 1))
		for k, v in ipairs(menuOrder) do
			k = v.uid
			if v.panel then
				if not IsValid(v.panel) or not v.panel:IsVisible() then
					VRUtilMenuClose(k)
					continue
				end
			end

			local pos, ang = v.pos, v.ang
			if v.attachment == 1 then
				pos, ang = LocalToWorld(pos, ang, g_VR.tracking.pose_lefthand.pos, g_VR.tracking.pose_lefthand.ang)
			elseif v.attachment == 2 then
				pos, ang = LocalToWorld(pos, ang, g_VR.tracking.pose_righthand.pos, g_VR.tracking.pose_righthand.ang)
			elseif v.attachment == 3 then
				pos, ang = LocalToWorld(pos, ang, g_VR.tracking.hmd.pos, g_VR.tracking.hmd.ang)
			elseif v.attachment == 4 then
				pos, ang = LocalToWorld(pos, ang, g_VR.origin, g_VR.originAngle)
			end

			if v.uid ~= "heightmenu" then v.scale = 0.02 end
			cam.IgnoreZ(true)
			cam.Start3D2D(pos, ang, v.scale)
			surface.SetDrawColor(255, 255, 255, 255)
			surface.SetMaterial(v.mat)
			surface.DrawTexturedRect(0, 0, v.width, v.height)
			--debug outline
			if uioutline:GetBool() then
				surface.SetDrawColor(255, 0, 0, 255)
				surface.DrawOutlinedRect(0, 0, v.width, v.height)
			end

			cam.End3D2D()
			cam.IgnoreZ(false)
			if v.cursorEnabled then
				local cursorX, cursorY = -1, -1
				local cursorWorldPos = Vector(0, 0, 0)
				local start = g_VR.tracking.pose_righthand.pos
				local dir = g_VR.tracking.pose_righthand.ang:Forward()
				local dist = nil
				local normal = ang:Up()
				local A = normal:Dot(dir)
				if A < 0 then
					local B = normal:Dot(pos - start)
					if B < 0 then
						dist = B / A
						cursorWorldPos = start + dir * dist
						local tp, unused = WorldToLocal(cursorWorldPos, Angle(0, 0, 0), pos, ang)
						cursorX = tp.x * 1 / v.scale
						cursorY = -tp.y * 1 / v.scale
					end
				end

				if cursorX > 0 and cursorY > 0 and cursorX < v.width and cursorY < v.height and dist < menuFocusDist then
					g_VR.menuFocus = k
					g_VR.menuCursorX = cursorX
					g_VR.menuCursorY = cursorY
					menuFocusDist = dist
					menuFocusPanel = v.panel
					menuFocusCursorWorldPos = cursorWorldPos
				end
			end
		end

		render.SetToneMappingScaleLinear(tms)
		if menuFocusPanel ~= prevFocusPanel then
			if IsValid(prevFocusPanel) then prevFocusPanel:SetMouseInputEnabled(false) end
			if IsValid(menuFocusPanel) then menuFocusPanel:SetMouseInputEnabled(true) end
			gui.EnableScreenClicker(menuFocusPanel ~= nil)
			prevFocusPanel = menuFocusPanel
		end

		if g_VR.menuFocus then
			render.SetMaterial(mat_beam)
			render.DrawBeam(g_VR.tracking.pose_righthand.pos, menuFocusCursorWorldPos, 0.1, 0, 1, Color(0, 0, 255))
			input.SetCursorPos(g_VR.menuCursorX, g_VR.menuCursorY)
			-- realtime ui start
			if convarValues.vrmod_ui_realtime == 1 then VRUtilMenuRenderPanel(g_VR.menuFocus) end
		end

		render.DepthRange(0, 1)
	end

	function VRUtilMenuOpen(uid, width, height, panel, attachment, pos, ang, scale, cursorEnabled, closeFunc)
		if menus[uid] then return end
		menus[uid] = {
			uid = uid,
			panel = panel,
			closeFunc = closeFunc,
			attachment = attachment,
			pos = pos,
			ang = ang,
			scale = scale,
			cursorEnabled = cursorEnabled,
			rt = GetRenderTarget("vrmod_rt_ui_" .. uid, width, height, false),
			width = width,
			height = height,
		}

		menuOrder[#menuOrder + 1] = menus[uid]
		local mat = Material("!vrmod_mat_ui_" .. uid)
		menus[uid].mat = not mat:IsError() and mat or CreateMaterial("vrmod_mat_ui_" .. uid, "UnlitGeneric", {
			["$basetexture"] = menus[uid].rt:GetName(),
			["$translucent"] = 1
		})

		if panel then
			panel:SetPaintedManually(true)
			VRUtilMenuRenderPanel(uid)
		end

		render.PushRenderTarget(menus[uid].rt)
		render.Clear(0, 0, 0, 0)
		render.PopRenderTarget()
		if GetConVar("vrmod_useworldmodels"):GetBool() then
			hook.Add("PostDrawTranslucentRenderables", "vrutil_hook_drawmenus", function(bDrawingDepth, bDrawingSkybox)
				if bDrawingSkybox then return end
				VRUtilRenderMenuSystem()
			end)
		end

		menusExist = true
	end

	function VRUtilMenuClose(uid)
		for k, v in pairs(menus) do
			if k == uid or not uid then
				if IsValid(v.panel) then v.panel:SetPaintedManually(false) end
				if v.closeFunc then v.closeFunc() end
				for k2, v2 in ipairs(menuOrder) do
					if v2 == v then
						table.remove(menuOrder, k2)
						break
					end
				end

				menus[k] = nil
			end
		end

		if table.IsEmpty(menus) then
			hook.Remove("PostDrawTranslucentRenderables", "vrutil_hook_drawmenus")
			g_VR.menuFocus = false
			menusExist = false
			gui.EnableScreenClicker(false)
		end
	end

	hook.Add("VRMod_Input", "ui", function(action, pressed)
		if g_VR.menuFocus and action == "boolean_primaryfire" then
			if pressed then
				gui.InternalMousePressed(MOUSE_LEFT)
			else
				gui.InternalMouseReleased(MOUSE_LEFT)
			end

			VRUtilMenuRenderPanel(g_VR.menuFocus)
		end

		if g_VR.menuFocus and action == "boolean_secondaryfire" then
			if pressed then
				gui.InternalMousePressed(MOUSE_RIGHT)
			else
				gui.InternalMouseReleased(MOUSE_RIGHT)
			end

			VRUtilMenuRenderPanel(g_VR.menuFocus)
		end

		if g_VR.menuFocus and action == "boolean_sprint" then
			if pressed then
				gui.InternalMousePressed(MOUSE_MIDDLE)
			else
				gui.InternalMouseReleased(MOUSE_MIDDLE)
			end

			VRUtilMenuRenderPanel(g_VR.menuFocus)
		end
	end)
end

concommand.Add("vrmod_vgui_reset", function()
	for _, v in pairs(vgui.GetWorldPanel():GetChildren()) do
		v:Remove()
	end

	RunConsoleCommand("spawnmenu_reload")
	-- It even removes spawnmenu, so we need to reload it
end)