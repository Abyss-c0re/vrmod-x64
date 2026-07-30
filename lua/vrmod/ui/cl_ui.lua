if CLIENT then
	g_VR = g_VR or {}
	g_VR.menuFocus = false
	g_VR.menuCursorX = 0
	g_VR.menuCursorY = 0
	local heldButtons = {
		[MOUSE_LEFT] = false,
		[MOUSE_RIGHT] = false,
		[MOUSE_MIDDLE] = false
	}

	local _, convarValues = vrmod.GetConvars()
	local uioutline = CreateClientConVar("vrmod_ui_outline", 0, true, FCVAR_ARCHIVE, nil, 0, 1)
	local rt_beam = GetRenderTarget("vrmod_rt_beam", 64, 64, false)
	local mat_beam = CreateMaterial("vrmod_mat_beam", "UnlitGeneric", {
		["$basetexture"] = rt_beam:GetName(),
		["$ignorez"] = 1,
		["$vertexcolor"] = 1,
		["$vertexalpha"] = 1
	})

	local function UpdateBeamColor(colorString)
		local r, g, b, a = string.match(colorString, "(%d+),(%d+),(%d+),(%d+)")
		r, g, b, a = tonumber(r), tonumber(g), tonumber(b), tonumber(a)
		if not (r and g and b and a) then return end
		mat_beam:SetVector("$color", Vector(r / 255, g / 255, b / 255))
		mat_beam:SetFloat("$alpha", a / 255)
		render.PushRenderTarget(rt_beam)
		render.Clear(r, g, b, a)
		render.PopRenderTarget()
	end

	vrmod.AddCallbackedConvar("vrmod_test_ui_testver", nil, 0, nil, "", 0, 1, tonumber)
	vrmod.AddCallbackedConvar("vrmod_beam_color", nil, "255,0,0,255", nil, "", nil, nil, nil, function(newValue) UpdateBeamColor(newValue) end)
	g_VR.menus = {}
	local menus = g_VR.menus
	local menuOrder = {}
	local menusExist = false
	local prevFocusPanel = nil
	UpdateBeamColor(convarValues.vrmod_beam_color)
	function VRUtilMenuRenderPanel(uid)
		local menu = menus[uid]
		if not menu or not menu.rt or not menu.panel or not menu.panel:IsValid() then return end
		render.PushRenderTarget(menu.rt)
		cam.Start2D()
		render.OverrideAlphaWriteEnable(true, true)
		render.Clear(0, 0, 0, 0, true, true)
		local oldclip = DisableClipping(false)
		render.SetWriteDepthToDestAlpha(false)
		menu.panel:PaintManual()
		render.SetWriteDepthToDestAlpha(true)
		DisableClipping(oldclip)
		render.OverrideAlphaWriteEnable(false)
		cam.End2D()
		render.PopRenderTarget()
	end

	function VRUtilMenuRenderStart(uid)
		local menu = menus[uid]
		if not menu or not menu.rt then return false end
		render.PushRenderTarget(menu.rt)
		cam.Start2D()
		render.OverrideAlphaWriteEnable(true, true)
		render.Clear(0, 0, 0, 0, true, true)
		render.SetWriteDepthToDestAlpha(true)
		return true
	end

	function VRUtilMenuRenderEnd()
		render.OverrideAlphaWriteEnable(false)
		cam.End2D()
		render.PopRenderTarget()
	end

	function VRUtilIsMenuOpen(uid)
		return menus[uid] ~= nil
	end

	--- Hand-local top-left so the panel CENTER sits near the wrist (not a far corner).
	-- 3D2D: +X = ang:Right(), +Y cursor = -ang:Forward() (see laser hit test).
	function VRUtilHandMenuPose(w, h, scale, centerLocal, panelAng)
		w = w or 512
		h = h or 512
		scale = scale or 0.025
		panelAng = panelAng or Angle(0, -90, 55)
		-- Palm-forward center (close, readable)
		centerLocal = centerLocal or Vector(2.5, 3.5, 4)
		local halfW = w * scale * 0.5
		local halfH = h * scale * 0.5
		-- top-left = center - Right*halfW + Forward*halfH  (Y-down = -Forward)
		local pos = centerLocal - panelAng:Right() * halfW + panelAng:Forward() * halfH
		return pos, panelAng, scale
	end

	function VRUtilRenderMenuSystem()
		if not menusExist or #menuOrder == 0 then
			g_VR.menuFocus = false
			return
		end
		g_VR.menuFocus = false
		local cursorX, cursorY = 0, 0
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
			-- CubeUI faces / height / cubeMenu keep scale; plain world panels default 0.02
			local uid = v.uid or ""
			local keepScale = v.cubeMenu or v.cubeui
				or uid == "heightmenu"
				or uid == "avatar_menu"
				or uid == "cube_settings"
				or uid == "cubeui_main"
				or string.StartWith(uid, "cubeui_")
			if not keepScale then
				if v.attachment then
					if not v.scale or v.scale < 0.03 then v.scale = 0.04 end
				else
					v.scale = 0.02
				end
			elseif not v.scale or v.scale < 0.03 then
				-- heightmenu / cube_settings SoT scale
				v.scale = 0.04
			end
			if v.attachment then
				local hand = g_VR.tracking and g_VR.tracking.pose_lefthand
				if hand and hand.pos and hand.ang then
					pos, ang = LocalToWorld(pos, ang, hand.pos, hand.ang)
				else
					-- no left hand yet — skip draw rather than park menu off to the side
					continue
				end
			else
				pos, ang = LocalToWorld(pos, ang, g_VR.origin, g_VR.originAngle)
			end

			if v.mat and not v.mat:IsError() then
				v.mat:SetTexture("$basetexture", v.rt)
			end
			cam.IgnoreZ(true)
			cam.Start3D2D(pos, ang, v.scale)
			local blendOn = false
			if render.OverrideBlend then
				blendOn = pcall(function()
					render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD)
				end)
			end
			surface.SetDrawColor(255, 255, 255, 255)
			surface.SetMaterial(v.mat)
			surface.DrawTexturedRect(0, 0, v.width, v.height)
			if blendOn then pcall(function() render.OverrideBlend(false) end) end
			--debug outline
			if uioutline:GetBool() then
				surface.SetDrawColor(255, 0, 0, 255)
				surface.DrawOutlinedRect(0, 0, v.width, v.height)
			end

			cam.End3D2D()
			cam.IgnoreZ(false)
			if v.cursorEnabled then
				local rh = g_VR.tracking and g_VR.tracking.pose_righthand
				if not rh or not rh.pos or not rh.ang then continue end
				local cursorWorldPos = Vector(0, 0, 0)
				local start = rh.pos
				local dir = rh.ang:Forward()
				local dist = nil
				local normal = ang:Up()
				local A = normal:Dot(dir)
				if A < 0 then
					local B = normal:Dot(pos - start)
					if B < 0 then
						dist = B / A
						cursorWorldPos = start + dir * dist
						local tp = WorldToLocal(cursorWorldPos, Angle(0, 0, 0), pos, ang)
						cursorX = tp.x * 1 / v.scale
						cursorY = -tp.y * 1 / v.scale
					end
				end

				if not cursorX or not cursorY or not v or not v.width or not v.height or not dist or not menuFocusDist then continue end
				if cursorX > 0 and cursorY > 0 and cursorX < v.width and cursorY < v.height and dist < menuFocusDist then
					g_VR.menuFocus = k
					menuFocusDist = dist
					menuFocusPanel = v.panel
					v.lastCursorX = cursorX
					v.lastCursorY = cursorY
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

		local focus = g_VR.menuFocus
		if focus and menus[focus] and menuFocusCursorWorldPos then
			g_VR.menuCursorX = menus[focus].lastCursorX
			g_VR.menuCursorY = menus[focus].lastCursorY
			local rh = g_VR.tracking and g_VR.tracking.pose_righthand
			if rh and rh.pos then
				render.SetMaterial(mat_beam)
				render.DrawBeam(rh.pos, menuFocusCursorWorldPos, 0.1, 0, 1, Color(255, 255, 255, 255))
			end
		end

		render.DepthRange(0, 1)
	end

	local function CreateMenuRT(uid, width, height)
		local fmt = IMAGE_FORMAT_BGRA8888 or IMAGE_FORMAT_RGBA8888 or IMAGE_FORMAT_ARGB8888
		if isfunction(GetRenderTargetEx) and fmt then
			local ok, rtEx = pcall(GetRenderTargetEx, "vrmod_rt_ui_" .. uid, width, height,
				RT_SIZE_NO_CHANGE or 0, MATERIAL_RT_DEPTH_NONE or 0,
				bit.bor(TEXTUREFLAGS_CLAMPS or 4, TEXTUREFLAGS_CLAMPT or 8), 0, fmt)
			if ok and rtEx then return rtEx end
		end
		return GetRenderTarget("vrmod_rt_ui_" .. uid, width, height, false)
	end

	function VRUtilMenuOpen(uid, width, height, panel, attachment, pos, ang, scale, cursorEnabled, closeFunc)
		VRUtilMenuClose(uid)
		local rt = CreateMenuRT(uid, width, height)
		menus[uid] = {
			uid = uid,
			panel = panel,
			closeFunc = closeFunc,
			attachment = attachment,
			pos = pos,
			ang = ang,
			scale = scale,
			cursorEnabled = cursorEnabled,
			rt = rt,
			width = width,
			height = height,
			lastCursorX = 0,
			lastCursorY = 0
		}

		menuOrder[#menuOrder + 1] = menus[uid]
		local mat = CreateMaterial("vrmod_mat_ui_" .. uid, "UnlitGeneric", {
			["$basetexture"] = rt:GetName(),
			["$translucent"] = 1,
			["$vertexalpha"] = 1,
			["$vertexcolor"] = 1,
			["$nolod"] = 1,
		})
		if mat and not mat:IsError() then
			mat:SetTexture("$basetexture", rt)
			mat:SetInt("$translucent", 1)
		end
		menus[uid].mat = mat

		-- Clear once, then paint panel (never clear after paint — that blanked hand menus)
		render.PushRenderTarget(menus[uid].rt)
		render.OverrideAlphaWriteEnable(true, true)
		render.Clear(0, 0, 0, 0, true, true)
		render.OverrideAlphaWriteEnable(false)
		render.PopRenderTarget()

		if panel then
			panel:SetPaintedManually(true)
			VRUtilMenuRenderPanel(uid)
		end
		menusExist = true
	end

	local function SyncCursorToVR()
		if not g_VR.menuFocus then return end
		local menu = menus[g_VR.menuFocus]
		if not menu or not menu.lastCursorX or not menu.lastCursorY then return end
		-- Optional: convert local panel coords to screen coords if needed
		local x, y = menu.lastCursorX, menu.lastCursorY
		input.SetCursorPos(x, y)
		-- Also update globals if still needed elsewhere
		g_VR.menuCursorX = x
		g_VR.menuCursorY = y
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
		if not g_VR.menuFocus then return end
		local mouseButton = nil
		if action == "boolean_primaryfire" or action == "boolean_car_mouse_left" then
			mouseButton = MOUSE_LEFT
		elseif action == "boolean_secondaryfire" or action == "boolean_car_mouse_right" then
			mouseButton = MOUSE_RIGHT
		elseif action == "boolean_sprint" then
			mouseButton = MOUSE_MIDDLE
		end

		if mouseButton then
			heldButtons[mouseButton] = pressed
			SyncCursorToVR()
			if pressed then
				gui.InternalMousePressed(mouseButton)
			else
				gui.InternalMouseReleased(mouseButton)
			end

			VRUtilMenuRenderPanel(g_VR.menuFocus)
		end
	end)

	hook.Add("Think", "VRUtil_SyncCursorWhileHeld", function()
		if not g_VR or not g_VR.menuFocus then return end
		SyncCursorToVR()
	end)

	local lastMenuFocus = nil
	hook.Add("Think", "VRMod_MenuFocusChangeDetect", function()
		local cur = g_VR.menuFocus
		if cur ~= lastMenuFocus then
			-- focus just moved
			if cur then
				vrmod.logger.Debug("[UI] Now pointing at menu:", cur)
				-- sync the OS cursor to the new panel
				SyncCursorToVR()
			end

			lastMenuFocus = cur
		end
	end)
end

concommand.Add("vrmod_vgui_reset", function()
	if g_VR and g_VR.menus then
		for uid, _ in pairs(g_VR.menus) do
			VRUtilMenuClose(uid)
		end
	end
end)