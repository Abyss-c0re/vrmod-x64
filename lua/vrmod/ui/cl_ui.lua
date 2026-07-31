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
	-- Global UI scale: VR menus (3D2D) + Derma frames. 1.0 = default.
	local cv_ui_scale = CreateClientConVar("vrmod_ui_scale", "1", true, FCVAR_ARCHIVE,
		"Global VR/Derma UI scale (0.5–2.0)", 0.5, 2.0)
	-- WayVR-style free grab: grip while laser-focused on a panel to drag it into world space.
	local cv_menu_grab = CreateClientConVar("vrmod_menu_grab", "1", true, FCVAR_ARCHIVE,
		"Grip + laser on VR menu panels to free-move them (WayVR overlay style)", 0, 1)

	function vrmod.GetUIScale()
		-- Default 1.0 — never silently shrink fonts/menus
		local s = cv_ui_scale and cv_ui_scale:GetFloat() or 1
		if s ~= s or s <= 0 then s = 1 end
		if s < 0.75 then s = 0.75 end -- floor so QM text stays readable
		if s > 2 then s = 2 end
		return s
	end

	--- Effective 3D2D scale for a menu entry (open scale × global UI scale)
	function vrmod.GetMenuDrawScale(menu)
		local base = (menu and (menu.baseScale or menu.scale)) or 0.03
		return base * vrmod.GetUIScale()
	end
	local rt_beam = GetRenderTarget("vrmod_rt_beam", 64, 64, false)
	local mat_beam = CreateMaterial("vrmod_mat_beam", "UnlitGeneric", {
		["$basetexture"] = rt_beam:GetName(),
		["$ignorez"] = 1,
		["$vertexcolor"] = 1,
		["$vertexalpha"] = 1
	})

	local function UpdateBeamColor(colorString)
		if not colorString or colorString == "" then return end
		local r, g, b, a = string.match(tostring(colorString), "(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
		r, g, b, a = tonumber(r), tonumber(g), tonumber(b), tonumber(a)
		if not (r and g and b and a) then return end
		mat_beam:SetVector("$color", Vector(r / 255, g / 255, b / 255))
		mat_beam:SetFloat("$alpha", a / 255)
		render.PushRenderTarget(rt_beam)
		render.Clear(r, g, b, a)
		render.PopRenderTarget()
	end

	-- Public so settings UI can force-apply without relying on cvar callback
	vrmod.ApplyBeamColor = UpdateBeamColor

	vrmod.AddCallbackedConvar("vrmod_test_ui_testver", nil, 0, nil, "", 0, 1, tonumber)
	vrmod.AddCallbackedConvar("vrmod_beam_color", nil, "255,0,0,255", nil, "", nil, nil, nil, function(newValue) UpdateBeamColor(newValue) end)
	g_VR.menus = {}
	local menus = g_VR.menus
	local menuOrder = {}
	local menusExist = false
	local prevFocusPanel = nil
	local beamInit = convarValues.vrmod_beam_color
	if not beamInit or beamInit == "" then
		local cv = GetConVar("vrmod_beam_color")
		beamInit = cv and cv:GetString() or "255,0,0,255"
	end
	UpdateBeamColor(beamInit)
	-- Wipe menu RT completely (alpha 0). Prevents ghosted pixels / uncleared HUD-style trails
	-- when panel paint is sparse (workshop bugs #349 weapon wheel + hand menus).
	local function ClearMenuRT(w, h)
		render.OverrideAlphaWriteEnable(true, true)
		if render.ClearDepth then render.ClearDepth() end
		render.Clear(0, 0, 0, 0, true, true)
		if render.OverrideBlend then
			pcall(function()
				render.OverrideBlend(true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
			end)
		end
		surface.SetDrawColor(0, 0, 0, 0)
		surface.DrawRect(0, 0, w or 2048, h or 2048)
		if render.OverrideBlend then pcall(function() render.OverrideBlend(false) end) end
	end

	function VRUtilMenuRenderPanel(uid)
		local menu = menus[uid]
		if not menu or not menu.rt or not menu.panel or not menu.panel:IsValid() then return end
		render.PushRenderTarget(menu.rt)
		cam.Start2D()
		ClearMenuRT(menu.width, menu.height)
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
		ClearMenuRT(menu.width, menu.height)
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

	------------------------------------------------------------------------
	-- WayVR-style free panel grab
	-- Point laser at panel + grip → detach from hand, drag freely, release to float in world.
	------------------------------------------------------------------------
	local grabState = nil -- { uid, hand ("left"|"right") }
	-- Same-frame multi-hook idempotency (ui + defaultinput both call TryMenuGrab)
	local consumeStamp = { frame = -1, hand = nil, pressed = nil }

	local function HandPose(handName)
		if not g_VR.tracking then return nil end
		if handName == "left" then return g_VR.tracking.pose_lefthand end
		if handName == "right" then return g_VR.tracking.pose_righthand end
		return nil
	end

	local function MarkConsumed(handName, pressed)
		consumeStamp.frame = FrameNumber and FrameNumber() or 0
		consumeStamp.hand = handName
		consumeStamp.pressed = pressed and true or false
	end

	local function AlreadyConsumed(handName, pressed)
		local f = FrameNumber and FrameNumber() or 0
		return consumeStamp.frame == f
			and consumeStamp.hand == handName
			and consumeStamp.pressed == (pressed and true or false)
	end

	local function ResolveMenuWorldPose(menu)
		if not menu then return nil, nil end
		local pos, ang = menu.pos, menu.ang
		if menu.grabHand and menu.grabPos and menu.grabAng then
			local hand = HandPose(menu.grabHand)
			if hand and hand.pos and hand.ang then
				return LocalToWorld(menu.grabPos, menu.grabAng, hand.pos, hand.ang)
			end
		end
		if menu.freeFloat or not menu.attachment then
			local origin = g_VR.origin or Vector()
			local originAng = g_VR.originAngle or Angle()
			return LocalToWorld(pos, ang, origin, originAng)
		end
		local hand = HandPose("left")
		if hand and hand.pos and hand.ang then
			return LocalToWorld(pos, ang, hand.pos, hand.ang)
		end
		return nil, nil
	end

	--- Called from default input before entity pickup. Returns true if grip was consumed by UI grab.
	--- Safe to call from multiple VRMod_Input hooks on the same event (idempotent).
	function vrmod.TryMenuGrab(handName, pressed)
		if not cv_menu_grab:GetBool() then return false end
		if not g_VR.active then return false end
		if AlreadyConsumed(handName, pressed) then return true end

		if not pressed then
			if not grabState or grabState.hand ~= handName then return false end
			local menu = menus[grabState.uid]
			if menu and menu.grabPos and menu.grabAng then
				local hand = HandPose(handName)
				if hand and hand.pos and hand.ang then
					local wPos, wAng = LocalToWorld(menu.grabPos, menu.grabAng, hand.pos, hand.ang)
					local origin = g_VR.origin or Vector()
					local originAng = g_VR.originAngle or Angle()
					menu.pos, menu.ang = WorldToLocal(wPos, wAng, origin, originAng)
				end
				menu.grabHand = nil
				menu.grabPos = nil
				menu.grabAng = nil
				menu.freeFloat = true
				menu.attachment = false
			end
			grabState = nil
			g_VR.menuGrabActive = false
			MarkConsumed(handName, pressed)
			return true
		end

		-- Already holding a panel with this hand
		if grabState then
			if grabState.hand == handName then
				MarkConsumed(handName, pressed)
				return true
			end
			return false
		end

		-- Press: only start grab when laser is on a grabbable panel
		local uid = g_VR.menuFocus
		if not uid or uid == false then return false end
		local menu = menus[uid]
		if not menu then return false end
		if menu.grabbable == false then return false end

		local wPos, wAng = ResolveMenuWorldPose(menu)
		local hand = HandPose(handName)
		if not wPos or not hand or not hand.pos or not hand.ang then return false end

		menu.grabPos, menu.grabAng = WorldToLocal(wPos, wAng, hand.pos, hand.ang)
		menu.grabHand = handName
		menu.freeFloat = true
		menu.attachment = false
		grabState = { uid = uid, hand = handName }
		g_VR.menuGrabActive = true
		MarkConsumed(handName, pressed)
		if vrmod.logger then
			vrmod.logger.Debug("[UI] Panel grab start uid=%s hand=%s", tostring(uid), handName)
		end
		return true
	end

	--- Call from menus that re-apply hand pose each paint. Skips when free-floating / grabbed.
	function vrmod.MenuApplyHandAnchor(menu, scale, pos, ang)
		if not menu then return end
		if scale then menu.scale = scale end
		menu.cubeMenu = true
		menu.grabbable = menu.grabbable ~= false
		if menu.grabHand or menu.freeFloat then return end
		if pos then menu.pos = pos end
		if ang then menu.ang = ang end
		menu.attachment = true
	end

	--- Snap a free-floating panel back to left-hand attach (optional helper / concommand).
	function vrmod.MenuReattach(uid)
		local menu = menus[uid or g_VR.menuFocus]
		if not menu then return false end
		local wPos, wAng = ResolveMenuWorldPose(menu)
		local hand = HandPose("left")
		if not wPos or not hand or not hand.pos or not hand.ang then return false end
		menu.pos, menu.ang = WorldToLocal(wPos, wAng, hand.pos, hand.ang)
		menu.freeFloat = false
		menu.attachment = true
		menu.grabHand = nil
		menu.grabPos = nil
		menu.grabAng = nil
		if grabState and grabState.uid == menu.uid then
			grabState = nil
			g_VR.menuGrabActive = false
		end
		return true
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
				if not IsValid(v.panel) then
					VRUtilMenuClose(k)
					continue
				end
				-- Spawn/context (and other PaintManual shells) can report IsVisible=false
				-- while still the active VR surface — never auto-close those.
				if not v.panel:IsVisible() then
					local keep = v.keepAlive or v.allowHiddenPanel
						or (v.panel.IsPaintedManually and v.panel:IsPaintedManually())
					if keep then
						v.panel:SetVisible(true)
					else
						VRUtilMenuClose(k)
						continue
					end
				end
			end

			-- Remember open-time scale once; never bake global UI scale into baseScale
			if not v.baseScale then
				local uid = v.uid or ""
				local keepScale = v.cubeMenu or v.cubeui
					or uid == "heightmenu"
					or uid == "avatar_menu"
					or uid == "cube_settings"
					or uid == "cubeui_main"
					or string.StartWith(uid, "cubeui_")
				local base = v.scale
				if not base or base <= 0 then
					base = keepScale and 0.04 or (v.attachment and 0.04 or 0.02)
				elseif not keepScale and v.attachment and base < 0.03 then
					base = 0.04
				elseif not keepScale and not v.attachment then
					base = 0.02
				elseif keepScale and base < 0.02 then
					base = 0.04
				end
				v.baseScale = base
			end
			-- Callers that re-assign .scale (cube_settings paint) update baseScale
			if v.scale and v.scale > 0 and math.abs(v.scale - (v._lastAssignedScale or -1)) > 1e-6 then
				v.baseScale = v.scale
				v._lastAssignedScale = v.scale
			end
			local drawScale = (v.baseScale or v.scale or 0.03) * vrmod.GetUIScale()

			-- WayVR free-float / grab wins over attachment (callers may re-set attachment each frame)
			local pos, ang
			if v.grabHand and v.grabPos and v.grabAng then
				local hand = HandPose(v.grabHand)
				if hand and hand.pos and hand.ang then
					pos, ang = LocalToWorld(v.grabPos, v.grabAng, hand.pos, hand.ang)
				else
					continue
				end
			elseif v.freeFloat then
				pos, ang = LocalToWorld(v.pos, v.ang, g_VR.origin or Vector(), g_VR.originAngle or Angle())
			elseif v.attachment then
				local hand = g_VR.tracking and g_VR.tracking.pose_lefthand
				if hand and hand.pos and hand.ang then
					pos, ang = LocalToWorld(v.pos, v.ang, hand.pos, hand.ang)
				else
					-- no left hand yet — skip draw rather than park menu off to the side
					continue
				end
			else
				pos, ang = LocalToWorld(v.pos, v.ang, g_VR.origin, g_VR.originAngle)
			end

			if v.mat and not v.mat:IsError() then
				v.mat:SetTexture("$basetexture", v.rt)
			end
			cam.IgnoreZ(true)
			cam.Start3D2D(pos, ang, drawScale)
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
						cursorX = tp.x * 1 / drawScale
						cursorY = -tp.y * 1 / drawScale
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
		local baseScale = scale or 0.03
		menus[uid] = {
			uid = uid,
			panel = panel,
			closeFunc = closeFunc,
			attachment = attachment,
			pos = pos,
			ang = ang,
			scale = baseScale,
			baseScale = baseScale,
			_lastAssignedScale = baseScale,
			cursorEnabled = cursorEnabled,
			rt = rt,
			width = width,
			height = height,
			lastCursorX = 0,
			lastCursorY = 0,
			-- WayVR free-grab defaults: all menus grabbable unless marked grabbable=false
			grabbable = true,
			freeFloat = not attachment,
			grabHand = nil,
			grabPos = nil,
			grabAng = nil,
		}

		menuOrder[#menuOrder + 1] = menus[uid]
		local mat = CreateMaterial("vrmod_mat_ui_" .. uid, "UnlitGeneric", {
			["$basetexture"] = rt:GetName(),
			["$translucent"] = 1,
			["$vertexalpha"] = 1,
			["$vertexcolor"] = 1,
			["$nolod"] = 1,
			["$nocull"] = 1,
			["$ignorez"] = 1,
		})
		if mat and not mat:IsError() then
			mat:SetTexture("$basetexture", rt)
			mat:SetInt("$translucent", 1)
			mat:SetInt("$vertexalpha", 1)
		end
		menus[uid].mat = mat

		-- Clear once, then paint panel (never clear after paint — that blanked hand menus)
		render.PushRenderTarget(menus[uid].rt)
		cam.Start2D()
		ClearMenuRT(width, height)
		render.OverrideAlphaWriteEnable(false)
		cam.End2D()
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
				if grabState and grabState.uid == k then
					grabState = nil
					g_VR.menuGrabActive = false
				end
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
			g_VR.menuGrabActive = false
			grabState = nil
			menusExist = false
			gui.EnableScreenClicker(false)
		end
	end

	hook.Add("VRMod_Input", "ui", function(action, pressed)
		-- Panel grab is handled in cl_input (before entity pickup) via vrmod.TryMenuGrab.
		-- Also handle here so grab works if default input is disabled / reordered.
		if action == "boolean_left_pickup" or action == "boolean_right_pickup" then
			local hand = action == "boolean_left_pickup" and "left" or "right"
			if vrmod.TryMenuGrab(hand, pressed) then return end
		end

		if not g_VR.menuFocus then return end
		local mouseButton = nil
		if action == "boolean_primaryfire" or action == "boolean_car_mouse_left" then
			mouseButton = MOUSE_LEFT
		elseif action == "boolean_secondaryfire" or action == "boolean_car_mouse_right" then
			mouseButton = MOUSE_RIGHT
		elseif action == "boolean_sprint" then
			-- Sprint while laser-focused on a free-floating panel re-snaps it to left hand
			if pressed then
				local m = menus[g_VR.menuFocus]
				if m and m.freeFloat and not g_VR.menuGrabActive then
					vrmod.MenuReattach(g_VR.menuFocus)
					return
				end
			end
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

-- Rebuild HUD mesh when UI scale changes
cvars.AddChangeCallback("vrmod_ui_scale", function()
	if vrmod.RefreshHUD then vrmod.RefreshHUD() end
end, "vrmod_ui_scale_hud")

concommand.Add("vrmod_menu_reattach", function()
	if not CLIENT then return end
	if vrmod.MenuReattach and vrmod.MenuReattach() then
		if vrmod.logger then vrmod.logger.Info("[UI] Menu reattached to left hand") end
	end
end)