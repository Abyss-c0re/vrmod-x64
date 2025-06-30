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
			if v.uid ~= "heightmenu" then
				v.scale = 0.02
				if v.attachment then
					pos, ang = LocalToWorld(pos, ang, g_VR.tracking.pose_lefthand.pos, g_VR.tracking.pose_lefthand.ang)
				else
					pos, ang = LocalToWorld(pos, ang, g_VR.origin, g_VR.originAngle)
				end
			end

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
						local tp = WorldToLocal(cursorWorldPos, Angle(0, 0, 0), pos, ang)
						cursorX = tp.x * 1 / v.scale
						cursorY = -tp.y * 1 / v.scale
					end
				end

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
		if focus and menus[focus] then
			g_VR.menuCursorX = menus[focus].lastCursorX
			g_VR.menuCursorY = menus[focus].lastCursorY
			render.SetMaterial(mat_beam)
			render.DrawBeam(g_VR.tracking.pose_righthand.pos, menuFocusCursorWorldPos, 0.1, 0, 1, Color(255, 255, 255, 255))
		end

		render.DepthRange(0, 1)
	end

	function VRUtilMenuOpen(uid, width, height, panel, attachment, pos, ang, scale, cursorEnabled, closeFunc)
		VRUtilMenuClose(uid)
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
			lastCursorX = 0,
			lastCursorY = 0
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
		if action == "boolean_primaryfire" then
			mouseButton = MOUSE_LEFT
		elseif action == "boolean_secondaryfire" then
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
				--print("[VRMod] Now pointing at menu:", cur)
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