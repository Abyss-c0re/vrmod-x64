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
	-- Corner resize: grip + pull bottom-right corner to scale a panel.
	local cv_menu_resize = CreateClientConVar("vrmod_menu_resize", "1", true, FCVAR_ARCHIVE,
		"Grip + pull panel corner to resize (scale) VR menus", 0, 1)
	-- Primary hand (SoT): laser + menu LMB. Opposite hand = default wrist menus.
	-- 0 = right (default), 1 = left. Integer so Cube combo + Derma combo share one path.
	local cv_primary_hand = CreateClientConVar("vrmod_primary_hand", "0", true, FCVAR_ARCHIVE,
		"VR primary hand: 0=right (laser+click), 1=left. Wrist menus use the other hand.", 0, 1)
	-- Quick menu attach: 0=left, 1=right, 2=free float
	local cv_qm_attach = CreateClientConVar("vrmod_qm_attach", "0", true, FCVAR_ARCHIVE,
		"Quick menu attach: 0=left hand, 1=right hand, 2=free float", 0, 2)

	------------------------------------------------------------------------
	-- Primary hand SoT (single truth — not dual free-for-all lasers)
	--   Primary   → laser pointer + menu primary click (LMB)
	--   Secondary → default wrist for non-QM panels
	--   QM attach → vrmod_qm_attach (left / right / free float)
	------------------------------------------------------------------------

	function vrmod.GetPrimaryHand()
		local v = cv_primary_hand and cv_primary_hand:GetInt() or 0
		return (v == 1) and "left" or "right"
	end

	function vrmod.GetSecondaryHand()
		return vrmod.GetPrimaryHand() == "left" and "right" or "left"
	end

	function vrmod.IsPrimaryHand(handName)
		return handName == vrmod.GetPrimaryHand()
	end

	--- Quick menu mode: "left" | "right" | "float"
	function vrmod.GetQuickMenuAttachMode()
		local v = cv_qm_attach and cv_qm_attach:GetInt() or 0
		if v == 1 then return "right" end
		if v == 2 then return "float" end
		return "left"
	end

	--- True if QM is free-float (not hand-locked)
	function vrmod.IsQuickMenuFreeFloat()
		return vrmod.GetQuickMenuAttachMode() == "float"
	end

	--- Hand for QM when attached (nil if free float)
	function vrmod.GetQuickMenuHand()
		local m = vrmod.GetQuickMenuAttachMode()
		if m == "float" then return nil end
		return m -- "left" or "right"
	end

	--- Wrist hand for a menu: explicit attachHand wins; miscmenu uses qm_attach; else secondary.
	function vrmod.GetMenuWristHand(menu)
		if menu and menu.uid == "miscmenu" then
			local h = vrmod.GetQuickMenuHand()
			if h then return h end
		end
		if menu and (menu.attachHand == "left" or menu.attachHand == "right") then
			return menu.attachHand
		end
		return vrmod.GetSecondaryHand()
	end

	--- Primary-hand trigger → LMB (right fire or left fire depending on setting).
	function vrmod.IsMenuPrimaryClick(action)
		if action == "boolean_car_mouse_left" then return true end
		if vrmod.GetPrimaryHand() == "left" then
			return action == "boolean_left_primaryfire"
		end
		return action == "boolean_primaryfire"
	end

	--- Secondary / cancel / RMB (either hand secondary + car RMB).
	function vrmod.IsMenuSecondaryClick(action)
		return action == "boolean_secondaryfire"
			or action == "boolean_left_secondaryfire"
			or action == "boolean_car_mouse_right"
	end

	function vrmod.IsMenuCloseAction(action)
		return vrmod.IsMenuSecondaryClick(action)
			or action == "boolean_chat"
	end

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

	------------------------------------------------------------------------
	-- VR-resolution panel metrics (Derma shells + native RTs)
	-- Pixel size tracks headset eye RT × design fraction × vrmod_ui_scale.
	-- baseScale is derived so world size = designPhys * ui_scale (once).
	------------------------------------------------------------------------
	local UI_KIND = {
		-- fracW/H of one eye; designPhys = full panel width in Source units @ ui_scale=1
		spawnmenu = { fracW = 0.58, fracH = 0.72, designPhys = 16, minW = 640, minH = 480 },
		contextmenu = { fracW = 0.36, fracH = 0.62, designPhys = 11, minW = 320, minH = 400 },
		settings = { fracW = 0.38, fracH = 0.58, designPhys = 12, minW = 380, minH = 460 },
		-- Glide Styled_TabbedFrame design is 850×600 — need enough RT for form rows
		popup = { fracW = 0.52, fracH = 0.62, designPhys = 14, minW = 420, minH = 360 },
		panel = { fracW = 0.48, fracH = 0.55, designPhys = 13, minW = 320, minH = 280 },
	}

	--- One-eye pixel size from the active VR stereo RT (SBS → half width).
	function vrmod.GetVREyeSize()
		local rtW = g_VR and tonumber(g_VR.rtWidth) or 0
		local rtH = g_VR and tonumber(g_VR.rtHeight) or 0
		local eyeW = g_VR and g_VR.view and tonumber(g_VR.view.w) or 0
		local eyeH = g_VR and g_VR.view and tonumber(g_VR.view.h) or 0
		if eyeW < 64 and rtW >= 64 then eyeW = math.floor(rtW * 0.5) end
		if eyeH < 64 and rtH >= 64 then eyeH = rtH end
		if eyeW < 64 then eyeW = math.max(ScrW() or 1280, 1024) end
		if eyeH < 64 then eyeH = math.max(ScrH() or 720, 720) end
		return eyeW, eyeH
	end

	--- Max UI RT edge (GPU-safe). Prefer eye dim; hard cap 2048.
	function vrmod.GetVRUIMaxRT()
		local eyeW, eyeH = vrmod.GetVREyeSize()
		return math.Clamp(math.max(eyeW, eyeH), 512, 2048)
	end

	--- Pixel W/H + recommended base 3D2D scale for a UI kind (spawn/context/popup/…).
	-- @param kind string
	-- @param opts optional { fracW, fracH, designPhys, minW, minH, width, height }
	-- @return w, h, baseScale
	function vrmod.GetVRUIPanelMetrics(kind, opts)
		opts = opts or {}
		local spec = UI_KIND[kind] or UI_KIND.panel
		local eyeW, eyeH = vrmod.GetVREyeSize()
		local uiS = vrmod.GetUIScale()
		local fracW = opts.fracW or spec.fracW or 0.4
		local fracH = opts.fracH or spec.fracH or 0.5
		local designPhys = opts.designPhys or spec.designPhys or 12
		local minW = opts.minW or spec.minW or 256
		local minH = opts.minH or spec.minH or 256
		local maxRT = vrmod.GetVRUIMaxRT()

		local w = opts.width or math.floor(eyeW * fracW * uiS + 0.5)
		local h = opts.height or math.floor(eyeH * fracH * uiS + 0.5)
		w = math.Clamp(w, minW, maxRT)
		h = math.Clamp(h, minH, maxRT)
		-- Even dims for RT
		w = math.floor(w / 2) * 2
		h = math.floor(h / 2) * 2

		-- World width ≈ designPhys * ui_scale (draw multiplies baseScale × ui_scale)
		local baseScale = designPhys / math.max(w, 1)
		baseScale = math.Clamp(baseScale, 0.008, 0.08)
		return w, h, baseScale
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
	-- Wipe menu RT (alpha 0). Cheap path: Clear alone (no full-screen DrawRect/blend).
	local function ClearMenuRT(_w, _h)
		render.OverrideAlphaWriteEnable(true, true)
		render.Clear(0, 0, 0, 0, true, true)
	end

	--- Mark a menu RT dirty so the next paint is not skipped (input, open, resize).
	function vrmod.MarkMenuDirty(uid)
		if uid and menus[uid] then
			menus[uid].dirty = true
		elseif not uid then
			for _, m in pairs(menus) do
				m.dirty = true
			end
		end
	end

	------------------------------------------------------------------------
	-- Cube paint law (one energy):
	--   • Never nest menu RTs under g_VR.rt (stereoRtActive) — crash + waste
	--   • Paint when dirty / forced / controlled idle heartbeat
	--   • Focused: dirty on cursor move (smooth hover) — not blind every frame
	--   • Unfocused: idle heartbeat only (paintInterval frames), not busy-loop
	------------------------------------------------------------------------

	--- True if this menu should repaint now. Call before VRUtilMenuRenderStart / full paint.
	function vrmod.MenuShouldRepaint(uid, force)
		local menu = menus[uid]
		if not menu or not menu.rt then return false end
		if g_VR.stereoRtActive then
			-- Defer to next PreStereoCapture / PreRender window
			menu.dirty = true
			return false
		end
		if force or menu.dirty then return true end

		local fn = FrameNumber and FrameNumber() or 0
		local focused = (g_VR.menuFocus == uid)

		-- Cursor motion on the focused panel → dirty once (not every frame)
		if focused then
			local cx, cy = menu.lastCursorX, menu.lastCursorY
			if cx and cy then
				-- quantize UV so tiny laser jitter does not thrash fonts/draw every frame
				local qx = math.floor((cx or 0) / 4)
				local qy = math.floor((cy or 0) / 4)
				if menu._paintQX ~= qx or menu._paintQY ~= qy then
					menu._paintQX = qx
					menu._paintQY = qy
					menu.dirty = true
					return true
				end
			end
			-- Focused heartbeat 0 = dirty-only (default). Set >0 only for animated HTML.
			local fi = menu.paintIntervalFocused
			if fi == nil then fi = 0 end
			if not menu._lastPaintFrame then return true end
			if fi > 0 and (fn - menu._lastPaintFrame) >= fi then return true end
			return false
		end

		-- Unfocused: optional idle refresh only (0 = never until dirty)
		local idle = menu.paintInterval
		if idle == nil then idle = 12 end
		if idle <= 0 then return false end
		if not menu._lastPaintFrame then return true end
		return (fn - menu._lastPaintFrame) >= idle
	end

	--- Paint Derma panel into menu RT.
	--- force=true always paints (if not under stereo RT). Otherwise Cube gate.
	--- Always PopRenderTarget even if PaintManual errors (nested RT stack corruption → hard crash).
	function VRUtilMenuRenderPanel(uid, force)
		local menu = menus[uid]
		if not menu or not menu.rt or not menu.panel or not menu.panel:IsValid() then return end
		if not vrmod.MenuShouldRepaint(uid, force) then return end

		local fn = FrameNumber and FrameNumber() or 0
		menu.dirty = false
		menu._lastPaintFrame = fn
		if menu.lastCursorX then
			menu._paintCursorX = menu.lastCursorX
			menu._paintCursorY = menu.lastCursorY
		end

		if g_VR.stereoRtActive then
			menu.dirty = true
			return
		end

		render.PushRenderTarget(menu.rt)
		local ok, err = pcall(function()
			cam.Start2D()
			ClearMenuRT(menu.width, menu.height)
			local oldclip = DisableClipping(false)
			render.SetWriteDepthToDestAlpha(false)
			menu.panel:PaintManual()
			render.SetWriteDepthToDestAlpha(true)
			DisableClipping(oldclip)
			render.OverrideAlphaWriteEnable(false)
			cam.End2D()
		end)
		render.PopRenderTarget()
		if not ok then
			menu.dirty = true
			menu._paintErrN = (menu._paintErrN or 0) + 1
			if menu._paintErrN <= 3 and vrmod and vrmod.logger then
				vrmod.logger.Warn("Menu RT paint %s: %s", tostring(uid), tostring(err))
			end
		end
	end

	function VRUtilMenuRenderStart(uid)
		local menu = menus[uid]
		if not menu or not menu.rt then return false end
		if g_VR.stereoRtActive then
			menu.dirty = true
			return false
		end
		-- Native paint paths own full redraw
		menu.dirty = false
		menu._lastPaintFrame = FrameNumber and FrameNumber() or 0
		if menu.lastCursorX then
			menu._paintCursorX = menu.lastCursorX
			menu._paintCursorY = menu.lastCursorY
		end
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
	-- forHand: "left"|"right" (default = secondary / wrist hand from primary setting).
	function VRUtilHandMenuPose(w, h, scale, centerLocal, panelAng, forHand)
		w = w or 512
		h = h or 512
		scale = scale or 0.025
		panelAng = panelAng or Angle(0, -90, 55)
		-- Palm-forward center (close, readable) — tuned for left controller local space
		centerLocal = centerLocal or Vector(2.5, 3.5, 4)
		forHand = forHand or (vrmod.GetSecondaryHand and vrmod.GetSecondaryHand()) or "left"
		if forHand == "right" then
			-- Mirror across controller forward so the panel faces the user on the right wrist
			centerLocal = Vector(centerLocal.x, -centerLocal.y, centerLocal.z)
			panelAng = Angle(panelAng.p, -panelAng.y, -panelAng.r)
		end
		-- Half-size must match DRAW scale (base × global UI scale) or dock feels huge/misaligned
		local drawS = scale * (vrmod.GetUIScale and vrmod.GetUIScale() or 1)
		local halfW = w * drawS * 0.5
		local halfH = h * drawS * 0.5
		-- top-left = center - Right*halfW + Forward*halfH  (Y-down = -Forward)
		local pos = centerLocal - panelAng:Right() * halfW + panelAng:Forward() * halfH
		return pos, panelAng, scale
	end

	------------------------------------------------------------------------
	-- Panel layout persistence (pos / ang / scale / freeFloat) — all menus
	-- File: data/vrmod/panel_layouts.json
	------------------------------------------------------------------------
	local LAYOUT_FILE = "vrmod/panel_layouts.json"
	local layoutCache = nil
	local SCALE_MIN, SCALE_MAX = 0.008, 0.22
	-- Corner grip zone (any of 4 corners) — large enough to hit reliably in VR
	local CORNER_PX = 80
	local CORNER_FRAC = 0.16

	local function EnsureLayoutDir()
		if not file.IsDir("vrmod", "DATA") then
			file.CreateDir("vrmod")
		end
	end

	local function ReadLayouts()
		if layoutCache then return layoutCache end
		EnsureLayoutDir()
		local raw = file.Read(LAYOUT_FILE, "DATA")
		layoutCache = util.JSONToTable(raw or "") or {}
		return layoutCache
	end

	local function WriteLayouts(all)
		EnsureLayoutDir()
		layoutCache = all or layoutCache or {}
		file.Write(LAYOUT_FILE, util.TableToJSON(layoutCache, true) or "{}")
	end

	local function LockMenuScale(menu, sc)
		if not menu then return end
		sc = math.Clamp(tonumber(sc) or menu.baseScale or menu.scale or 0.03, SCALE_MIN, SCALE_MAX)
		menu.scale = sc
		menu.baseScale = sc
		menu._lastAssignedScale = sc
		menu.scaleLocked = true -- paint hooks must not overwrite user size
	end

	--- Persist pose + scale for a menu uid (origin-relative pos/ang when free-floating).
	function vrmod.SaveMenuLayout(uid)
		if not uid or uid == false then return false end
		local menu = menus[uid]
		if not menu then return false end
		local sc = menu.baseScale or menu.scale or 0.03
		local all = ReadLayouts()
		-- QM only saves free-float pose when attach mode is free float
		local isQM = (tostring(uid) == "miscmenu")
		local qmFloat = isQM and vrmod.IsQuickMenuFreeFloat and vrmod.IsQuickMenuFreeFloat()
		local allowFloat = (not isQM) or qmFloat
		local entry = {
			scale = sc,
			scaleLocked = menu.scaleLocked and true or false,
			freeFloat = allowFloat and (menu.freeFloat or not menu.attachment) and true or false,
			width = menu.width,
			height = menu.height,
		}
		if allowFloat and menu.pos and entry.freeFloat then
			entry.pos = { x = menu.pos.x, y = menu.pos.y, z = menu.pos.z }
		end
		if allowFloat and menu.ang and entry.freeFloat then
			entry.ang = { p = menu.ang.p, y = menu.ang.y, r = menu.ang.r }
		end
		all[tostring(uid)] = entry
		WriteLayouts(all)
		if vrmod.logger then
			vrmod.logger.Info("[UI] Saved layout uid=%s scale=%.4f float=%s",
				tostring(uid), entry.scale, tostring(entry.freeFloat))
		end
		return true
	end

	--- Apply saved layout onto a menu table. Returns true if anything applied.
	function vrmod.ApplyMenuLayout(uid, menu)
		menu = menu or (uid and menus[uid])
		if not menu or not uid then return false end
		local e = ReadLayouts()[tostring(uid)]
		if not e then return false end
		local applied = false
		local sc = e.scale and tonumber(e.scale) or nil
		local isQM = (tostring(uid) == "miscmenu")
		local qmFloat = isQM and vrmod.IsQuickMenuFreeFloat and vrmod.IsQuickMenuFreeFloat()
		-- Hand-locked QM: scale only, never free-float restore
		if isQM and not qmFloat then
			if sc and sc >= SCALE_MIN and sc <= SCALE_MAX then
				menu.scale = sc
				menu.baseScale = sc
				menu._lastAssignedScale = sc
				applied = true
			end
			menu.freeFloat = false
			menu.attachment = true
			menu.grabbable = false
			return applied
		end
		if sc and sc >= SCALE_MIN and sc <= SCALE_MAX then
			LockMenuScale(menu, sc)
			applied = true
		elseif e.scaleLocked and sc and sc > 0 then
			menu.scaleLocked = false
		end
		if e.freeFloat and e.pos and e.ang then
			local px, py, pz = e.pos.x or e.pos[1], e.pos.y or e.pos[2], e.pos.z or e.pos[3]
			local ap, ay, ar = e.ang.p or e.ang[1], e.ang.y or e.ang[2], e.ang.r or e.ang[3]
			local okPos = px and py and pz and math.abs(px) < 1e5 and math.abs(py) < 1e5 and math.abs(pz) < 1e5
			if okPos and ap and ay and ar and (not sc or (sc >= SCALE_MIN and sc <= SCALE_MAX)) then
				menu.pos = Vector(px, py, pz)
				menu.ang = Angle(ap, ay, ar)
				menu.freeFloat = true
				menu.attachment = false
				applied = true
			end
		end
		return applied
	end

	function vrmod.GetMenuLayout(uid)
		if not uid then return nil end
		return ReadLayouts()[tostring(uid)]
	end

	function vrmod.ClearMenuLayout(uid)
		local all = ReadLayouts()
		if uid then
			all[tostring(uid)] = nil
		else
			all = {}
		end
		WriteLayouts(all)
		return true
	end

	local function CornerZoneSize(menu)
		if not menu or not menu.width or not menu.height then return CORNER_PX end
		return math.max(CORNER_PX, math.min(menu.width, menu.height) * CORNER_FRAC)
	end

	--- True if laser is in any corner resize zone (all windows are resizable by default).
	local function CursorInResizeCorner(menu, cx, cy)
		if not menu or not cx or not cy then return false end
		local w, h = menu.width or 0, menu.height or 0
		if w < 8 or h < 8 then return false end
		local cz = CornerZoneSize(menu)
		local pad = cz * 0.35 -- allow slightly outside the rect
		local nearL = cx >= -pad and cx <= cz
		local nearR = cx >= (w - cz) and cx <= (w + pad)
		local nearT = cy >= -pad and cy <= cz
		local nearB = cy >= (h - cz) and cy <= (h + pad)
		return (nearL or nearR) and (nearT or nearB)
	end

	local function MenuIsResizable(menu)
		if not menu then return false end
		if menu.resizable == false then return false end
		return true -- default: every VR window is resizable
	end

	------------------------------------------------------------------------
	-- WayVR-style free panel grab + corner resize
	-- Point laser at panel + grip → detach from hand, drag freely, release to float in world.
	-- Point laser at bottom-right corner + grip → pull to scale; release saves layout.
	------------------------------------------------------------------------
	local grabState = nil -- { uid, hand ("left"|"right") }
	local resizeState = nil -- { uid, hand, startScale, startDiag }
	-- Same-frame multi-hook idempotency (ui + defaultinput both call TryMenuGrab)
	local consumeStamp = { frame = -1, hand = nil, pressed = nil }

	--- Live tracking hand (input / grab start only).
	local function HandPoseLive(handName)
		if not g_VR.tracking then return nil end
		if handName == "left" then return g_VR.tracking.pose_lefthand end
		if handName == "right" then return g_VR.tracking.pose_righthand end
		return nil
	end

	--- Stereo-frozen hand for draw/grab pose (same L+R eyes). Falls back to live.
	local function HandPose(handName)
		local sp = g_VR.stereoPose
		local sf = g_VR.stereoFrame or 0
		if sp and sp.frame == sf then
			if handName == "left" and sp.hasLeft then
				return { pos = sp.leftPos, ang = sp.leftAng }
			end
			if handName == "right" and sp.hasRight then
				return { pos = sp.rightPos, ang = sp.rightAng }
			end
		end
		return HandPoseLive(handName)
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

	local function MenuAttachHandName(menu)
		return vrmod.GetMenuWristHand(menu)
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
		local hand = HandPose(MenuAttachHandName(menu))
		if hand and hand.pos and hand.ang then
			return LocalToWorld(pos, ang, hand.pos, hand.ang)
		end
		return nil, nil
	end

	-- Forward-declared: focus freeze for stereo (filled in VRUtilRenderMenuSystem)
	local focusSnap = {
		frame = -1,
		uid = false,
		panel = nil,
		cursorWorld = nil,
		cursorX = 0,
		cursorY = 0,
		scaleKey = 0,
	}

	local function InvalidateMenuHit(menu)
		if not menu then return end
		menu._hitFrame = -1
		menu._hitScale = nil
		menu._hitX, menu._hitY, menu._hitDist, menu._hitWorld = nil, nil, nil, nil
		-- Force laser remap next eye so close/buttons match new scale immediately
		menu.lastCursorX, menu.lastCursorY = nil, nil
	end

	--- Default wrist pose + unlocked scale for one open menu.
	function vrmod.ResetMenuPose(uid, opts)
		opts = opts or {}
		local menu = menus[uid]
		if not menu then return false end
		menu.scaleLocked = false
		menu.freeFloat = false
		menu.attachment = true
		menu.grabHand = nil
		menu.grabPos = nil
		menu.grabAng = nil
		menu._snapFrame = -1
		local wrist = MenuAttachHandName(menu)
		menu.attachHand = wrist
		local defSc = menu.baseScale or menu.scale or 0.03
		if defSc < 0.01 or defSc > 0.12 then defSc = 0.03 end
		if uid == "miscmenu" then defSc = 0.025 end
		if uid == "p2v_spawnmenu" or uid == "p2v_contextmenu" then
			if vrmod.GetVRUIPanelMetrics then
				local _, _, msc = vrmod.GetVRUIPanelMetrics(
					uid == "p2v_contextmenu" and "contextmenu" or "spawnmenu")
				if msc then defSc = msc end
			else
				defSc = 0.016
			end
		end
		menu.scale = defSc
		menu.baseScale = defSc
		menu._lastAssignedScale = defSc
		if isfunction(VRUtilHandMenuPose) then
			local lp, la = VRUtilHandMenuPose(
				menu.width or 512, menu.height or 512, defSc, nil, nil, wrist)
			if lp then menu.pos = lp end
			if la then menu.ang = la end
		end
		InvalidateMenuHit(menu)
		menu.dirty = true
		if opts.save then
			local all = ReadLayouts()
			all[tostring(uid)] = {
				scale = defSc,
				scaleLocked = false,
				freeFloat = false,
			}
			WriteLayouts(all)
		end
		return true
	end

	--- Wipe saved poses/sizes/anchors and re-dock every open window to the wrist.
	-- Use after a menu crash, lost panel, or unusable free-float placement.
	function vrmod.ResetAllWindowLayouts(opts)
		opts = opts or {}
		local reopenQM = opts.reopenQM ~= false
		local closeAll = opts.closeAll
		if closeAll == nil then closeAll = reopenQM end

		vrmod.ClearMenuLayout()
		if vrmod.panel2vr and vrmod.panel2vr.ClearAllShellFloatPoses then
			vrmod.panel2vr.ClearAllShellFloatPoses()
		end

		grabState = nil
		resizeState = nil
		g_VR.menuGrabActive = false
		g_VR.menuResizeActive = false
		g_VR.menuFocus = false

		if g_VR.menus then
			for uid in pairs(g_VR.menus) do
				vrmod.ResetMenuPose(uid)
			end
		end

		if closeAll then
			if isfunction(vrmod.CloseAllWindows) then
				vrmod.CloseAllWindows({ alsoQuickMenu = true })
			elseif g_VR.menus then
				local list = {}
				for uid in pairs(g_VR.menus) do list[#list + 1] = uid end
				for _, uid in ipairs(list) do
					if isfunction(VRUtilMenuClose) then VRUtilMenuClose(uid) end
				end
			end
			if g_VR.MenuClose then pcall(g_VR.MenuClose) end
		end

		if reopenQM and g_VR.active then
			timer.Simple(0.05, function()
				if not g_VR or not g_VR.active then return end
				if (not g_VR.menuItems or #g_VR.menuItems == 0)
					and isfunction(vrmod.RebuildInGameMenuItems) then
					pcall(vrmod.RebuildInGameMenuItems)
				end
				if g_VR.MenuOpen then pcall(g_VR.MenuOpen) end
				if vrmod.Toast then
					vrmod.Toast("Windows reset — wrist dock, default size", 3, "ok")
				end
			end)
		elseif vrmod.Toast then
			vrmod.Toast("Window poses cleared", 2, "ok")
		end

		if vrmod.logger then
			vrmod.logger.Info("[UI] ResetAllWindowLayouts reopenQM=%s", tostring(reopenQM))
		end
		return true
	end

	--- Re-pin hand shell top-left for current scale (HandMenuPose half-size must match).
	local function ReposeHandMenu(menu)
		if not menu or menu.freeFloat or menu.grabHand then return end
		if not isfunction(VRUtilHandMenuPose) then return end
		local wrist = MenuAttachHandName(menu)
		local center = menu._centerLocal
		local lp, la = VRUtilHandMenuPose(
			menu.width or 512, menu.height or 512,
			menu.baseScale or menu.scale or 0.03,
			center, menu._panelAng, wrist
		)
		if lp then menu.pos = lp end
		if la then menu.ang = la end
		menu.attachment = true
		menu.attachHand = wrist
	end

	--- Keep free-float world *center* fixed when scale changes (TL would slide UV under laser).
	local function AdjustFreeFloatForScale(menu, oldBase, newBase)
		if not menu or not menu.pos or not menu.ang then return end
		if not (menu.freeFloat or not menu.attachment) then return end
		oldBase = tonumber(oldBase) or 0.03
		newBase = tonumber(newBase) or oldBase
		if math.abs(oldBase - newBase) < 1e-8 then return end
		local uiS = vrmod.GetUIScale()
		local w = menu.width or 512
		local h = menu.height or 512
		local wPos, wAng = ResolveMenuWorldPose(menu)
		if not wPos or not wAng then return end
		local oldD = oldBase * uiS
		local newD = newBase * uiS
		local center = wPos + wAng:Right() * (w * oldD * 0.5) - wAng:Forward() * (h * oldD * 0.5)
		local newTL = center - wAng:Right() * (w * newD * 0.5) + wAng:Forward() * (h * newD * 0.5)
		local origin = g_VR.origin or Vector()
		local originAng = g_VR.originAngle or Angle()
		menu.pos, menu.ang = WorldToLocal(newTL, wAng, origin, originAng)
	end

	local function EndResize(handName)
		if not resizeState or resizeState.hand ~= handName then return false end
		local uid = resizeState.uid
		local menu = menus[uid]
		if menu then
			LockMenuScale(menu, menu.baseScale or menu.scale)
			-- Hand shells: stay attached and re-pose for new half-size (click UV must match draw)
			if resizeState.keepAttached or (not menu.freeFloat and menu.attachment) then
				menu.freeFloat = false
				menu.attachment = true
				ReposeHandMenu(menu)
			end
			if IsValid(menu.panel) and menu.panel.SetMouseInputEnabled then
				menu.panel:SetMouseInputEnabled(true)
			end
			menu.cursorEnabled = true
			menu.dirty = true
			menu._snapFrame = -1
			InvalidateMenuHit(menu)
			vrmod.SaveMenuLayout(uid)
		end
		resizeState = nil
		g_VR.menuResizeActive = false
		-- Drop focus freeze so next eye rebuilds cursor on new scale
		focusSnap.frame = -1
		focusSnap.uid = false
		focusSnap.panel = nil
		focusSnap.cursorWorld = nil
		focusSnap.scaleKey = 0
		return true
	end

	-- How close panel center must be to the wrist palm to snap on grip release (Source units)
	local WRIST_SNAP_DIST = 16

	--- World-space center of a menu panel (from top-left + scale).
	local function MenuWorldCenter(menu, wPos, wAng, drawScale)
		if not menu or not wPos or not wAng then return wPos end
		local sc = drawScale or ((menu.baseScale or menu.scale or 0.03) * vrmod.GetUIScale())
		local w = menu.width or 512
		local h = menu.height or 512
		return wPos + wAng:Right() * (w * sc * 0.5) - wAng:Forward() * (h * sc * 0.5)
	end

	local function EndGrab(handName)
		if not grabState or grabState.hand ~= handName then return false end
		local uid = grabState.uid
		local menu = menus[uid]
		if menu and menu.grabPos and menu.grabAng then
			local hand = HandPose(handName)
			local wPos, wAng
			if hand and hand.pos and hand.ang then
				wPos, wAng = LocalToWorld(menu.grabPos, menu.grabAng, hand.pos, hand.ang)
			end
			menu.grabHand = nil
			menu.grabPos = nil
			menu.grabAng = nil

			-- Natural wrist dock: release grip near the wrist hand → re-anchor
			local wristName = MenuAttachHandName(menu)
			local wrist = HandPose(wristName)
			local center = wPos and MenuWorldCenter(menu, wPos, wAng) or nil
			local nearWrist = wrist and wrist.pos and center
				and center:Distance(wrist.pos) <= WRIST_SNAP_DIST

			if nearWrist then
				-- Clean palm pose: use real RT size + base scale (HandMenuPose applies UI scale to half-size)
				local lp, la = VRUtilHandMenuPose(
					menu.width or 512, menu.height or 512,
					menu.baseScale or menu.scale or 0.03,
					(menu.width or 512) >= 800 and Vector(4, 5, 6) or nil,
					nil, wristName
				)
				menu.pos, menu.ang = lp, la
				menu.freeFloat = false
				menu.attachment = true
				menu.attachHand = wristName
				menu._snapFrame = -1
				InvalidateMenuHit(menu)
				-- Persist wrist attach (not free-float)
				local all = ReadLayouts()
				local e = all[tostring(uid)] or {}
				e.scale = menu.baseScale or menu.scale
				e.freeFloat = false
				e.pos = nil
				e.ang = nil
				all[tostring(uid)] = e
				WriteLayouts(all)
				if vrmod.Toast then
					vrmod.Toast("Docked to wrist", 1.5, "hint")
				end
				if vrmod.logger then
					vrmod.logger.Debug("[UI] Panel docked to %s wrist uid=%s", wristName, tostring(uid))
				end
			elseif wPos and wAng then
				local origin = g_VR.origin or Vector()
				local originAng = g_VR.originAngle or Angle()
				menu.pos, menu.ang = WorldToLocal(wPos, wAng, origin, originAng)
				menu.freeFloat = true
				menu.attachment = false
				vrmod.SaveMenuLayout(uid)
			else
				menu.freeFloat = true
				menu.attachment = false
			end
		end
		grabState = nil
		g_VR.menuGrabActive = false
		return true
	end

	--- Resize from grip-hand distance (stereo-safe; no per-eye laser).
	local function UpdateResizeFromHand()
		if not resizeState then return end
		local menu = menus[resizeState.uid]
		if not menu then return end
		local hand = HandPose(resizeState.hand)
		if not hand or not hand.pos then return end
		local startDist = resizeState.startDist or 1
		if startDist < 2 then startDist = 2 end
		local dist
		if resizeState.keepAttached then
			-- Hand shell: scale from grip↔wrist span (stable while panel re-poses on palm)
			local wrist = HandPose(MenuAttachHandName(menu))
			if not wrist or not wrist.pos then return end
			dist = hand.pos:Distance(wrist.pos)
		else
			-- Free float: grip distance to fixed world center at grab start
			local origin = resizeState.origin
			if not origin then return end
			dist = hand.pos:Distance(origin)
		end
		local ns = (resizeState.startScale or 0.03) * (dist / startDist)
		ns = math.Clamp(ns, SCALE_MIN, SCALE_MAX)
		local prev = menu.baseScale or menu.scale or 0
		if math.abs(ns - prev) < 1e-7 then return end
		LockMenuScale(menu, ns)
		if resizeState.keepAttached then
			menu.freeFloat = false
			menu.attachment = true
			ReposeHandMenu(menu)
		else
			AdjustFreeFloatForScale(menu, prev, ns)
		end
		menu._snapFrame = -1
		InvalidateMenuHit(menu)
	end

	--- World pose for a menu. Uses stereo-frozen hands only (never mutates mid-eye).
	local function ResolveDrawPose(v)
		local pos, ang
		if v.grabHand and v.grabPos and v.grabAng then
			local hand = HandPose(v.grabHand)
			if hand and hand.pos and hand.ang then
				pos, ang = LocalToWorld(v.grabPos, v.grabAng, hand.pos, hand.ang)
			end
		elseif v.freeFloat or not v.attachment then
			pos, ang = LocalToWorld(v.pos, v.ang, g_VR.origin or Vector(), g_VR.originAngle or Angle())
		else
			local hand = HandPose(MenuAttachHandName(v))
			if hand and hand.pos and hand.ang then
				pos, ang = LocalToWorld(v.pos, v.ang, hand.pos, hand.ang)
			end
		end
		local drawScale = (v.baseScale or v.scale or 0.03) * vrmod.GetUIScale()
		return pos, ang, drawScale
	end

	--- Once per stereo frame: freeze world matrix copies for BOTH eyes.
	local function SnapshotMenuDrawState()
		UpdateResizeFromHand()
		local sf = g_VR.stereoFrame or 0
		for _, v in ipairs(menuOrder) do
			local pos, ang, drawScale = ResolveDrawPose(v)
			if pos and ang then
				-- Own copies — never alias LocalToWorld temps or tracking tables
				if not v._snapPos then v._snapPos = Vector() end
				if not v._snapAng then v._snapAng = Angle() end
				v._snapPos:Set(pos)
				v._snapAng:Set(ang)
				v._snapScale = drawScale
				v._snapFrame = sf
			else
				v._snapFrame = -1
			end
		end
	end

	hook.Add("VRMod_PreStereo", "vrmod_ui_snapshot", function()
		if not g_VR or not g_VR.active then return end
		if not menusExist then return end
		SnapshotMenuDrawState()
	end)

	--- Called from default input before entity pickup. Returns true if grip was consumed by UI grab/resize.
	--- Safe to call from multiple VRMod_Input hooks on the same event (idempotent).
	function vrmod.TryMenuGrab(handName, pressed)
		if not g_VR.active then return false end
		local grabOn = cv_menu_grab:GetBool()
		local resizeOn = cv_menu_resize:GetBool()
		if not grabOn and not resizeOn then return false end
		if AlreadyConsumed(handName, pressed) then return true end

		if not pressed then
			local ended = false
			if resizeState and resizeState.hand == handName then
				ended = EndResize(handName) or ended
			end
			if grabState and grabState.hand == handName then
				ended = EndGrab(handName) or ended
			end
			if ended then
				MarkConsumed(handName, pressed)
				return true
			end
			return false
		end

		-- Already holding resize/grab with this hand
		if resizeState then
			if resizeState.hand == handName then
				MarkConsumed(handName, pressed)
				return true
			end
			return false
		end
		if grabState then
			if grabState.hand == handName then
				MarkConsumed(handName, pressed)
				return true
			end
			return false
		end

		-- Press: laser on a panel (resize works even if grab is disabled)
		local uid = g_VR.menuFocus
		if not uid or uid == false then return false end
		local menu = menus[uid]
		if not menu then return false end

		local cx = menu.lastCursorX or g_VR.menuCursorX or 0
		local cy = menu.lastCursorY or g_VR.menuCursorY or 0

		-- Hand-locked quick menu: no free-float grab; free-float mode allows grab
		local isQM = (uid == "miscmenu")
		local qmHandLocked = isQM and not (vrmod.IsQuickMenuFreeFloat and vrmod.IsQuickMenuFreeFloat())
		if qmHandLocked then
			menu.freeFloat = false
			menu.attachment = true
			menu.grabbable = false
			menu.grabHand = nil
		elseif isQM then
			menu.grabbable = true
		end

		-- Corner grip → resize (every window by default); body grip → free-move if grabbable
		if resizeOn and MenuIsResizable(menu) and CursorInResizeCorner(menu, cx, cy) then
			local wPos, wAng = ResolveMenuWorldPose(menu)
			local hand = HandPose(handName)
			if not wPos or not wAng or not hand or not hand.pos then return false end

			-- Spawn/context (+ other hand-attached shells): stay on wrist and re-pose each tick.
			-- Free-floating detaches content under the laser → "unclickable after resize".
			local keepAttached = (not qmHandLocked)
				and menu.attachment and not menu.freeFloat and not menu.grabHand
			if not keepAttached and not qmHandLocked and not menu.freeFloat and wPos and wAng then
				local origin = g_VR.origin or Vector()
				local originAng = g_VR.originAngle or Angle()
				menu.pos, menu.ang = WorldToLocal(wPos, wAng, origin, originAng)
				menu.freeFloat = true
				menu.attachment = false
				wPos, wAng = ResolveMenuWorldPose(menu)
			end
			if not wPos then return false end

			local uiS = vrmod.GetUIScale()
			local drawS = (menu.baseScale or menu.scale or 0.03) * uiS
			local mw, mh = menu.width or 512, menu.height or 512
			local center = wPos + wAng:Right() * (mw * drawS * 0.5) - wAng:Forward() * (mh * drawS * 0.5)
			local startDist
			if keepAttached then
				local wrist = HandPose(MenuAttachHandName(menu))
				if not wrist or not wrist.pos then return false end
				startDist = hand.pos:Distance(wrist.pos)
			else
				startDist = hand.pos:Distance(center)
			end
			if startDist < 2 then startDist = 2 end
			resizeState = {
				uid = uid,
				hand = handName,
				startScale = menu.baseScale or menu.scale or 0.03,
				origin = Vector(center), -- free-float: fixed world center
				startDist = startDist,
				keepAttached = keepAttached and true or false,
			}
			menu.scaleLocked = true
			menu.resizable = true
			menu.cursorEnabled = true
			g_VR.menuResizeActive = true
			MarkConsumed(handName, pressed)
			if vrmod.logger then
				vrmod.logger.Debug("[UI] Panel resize start uid=%s hand=%s scale=%.4f attach=%s",
					tostring(uid), handName, resizeState.startScale, tostring(keepAttached))
			end
			return true
		end

		if not grabOn then return false end
		if qmHandLocked or menu.grabbable == false then return false end

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

	--- Call from menus that re-apply hand pose each paint. Skips when free-floating / grabbed / resizing.
	--- Never overwrites scale when user locked size (resize / saved layout).
	function vrmod.MenuApplyHandAnchor(menu, scale, pos, ang, attachHand)
		if not menu then return end
		if scale and not menu.scaleLocked then
			menu.scale = scale
			menu.baseScale = scale
			menu._lastAssignedScale = scale
		end
		menu.cubeMenu = true
		menu.grabbable = menu.grabbable ~= false
		menu.resizable = menu.resizable ~= false -- every window resizable unless opted out
		if menu.grabHand or menu.freeFloat or (resizeState and resizeState.uid == menu.uid) then return end
		if pos then menu.pos = pos end
		if ang then menu.ang = ang end
		menu.attachment = true
		if attachHand == "left" or attachHand == "right" then
			menu.attachHand = attachHand
		elseif not menu.attachHand then
			menu.attachHand = vrmod.GetSecondaryHand()
		end
	end

	--- Snap a free-floating panel back to wrist (default palm pose). Natural path is
	--- grip + release near wrist; this is for scripts / concommand.
	function vrmod.MenuReattach(uid)
		local menu = menus[uid or g_VR.menuFocus]
		if not menu then return false end
		local wrist = MenuAttachHandName(menu)
		local hand = HandPose(wrist)
		if not hand or not hand.pos or not hand.ang then return false end
		local lp, la = VRUtilHandMenuPose(
			menu.width, menu.height,
			menu.baseScale or menu.scale or 0.03,
			nil, nil, wrist
		)
		menu.pos, menu.ang = lp, la
		menu.freeFloat = false
		menu.attachment = true
		menu.attachHand = wrist
		menu.grabHand = nil
		menu.grabPos = nil
		menu.grabAng = nil
		menu._snapFrame = -1
		InvalidateMenuHit(menu)
		if grabState and grabState.uid == menu.uid then
			grabState = nil
			g_VR.menuGrabActive = false
		end
		if resizeState and resizeState.uid == menu.uid then
			resizeState = nil
			g_VR.menuResizeActive = false
		end
		local all = ReadLayouts()
		local e = all[tostring(menu.uid)] or {}
		e.scale = menu.baseScale or menu.scale
		e.freeFloat = false
		e.pos = nil
		e.ang = nil
		all[tostring(menu.uid)] = e
		WriteLayouts(all)
		return true
	end

	-- focusSnap declared above (EndResize invalidates it after stretch)

	function VRUtilRenderMenuSystem()
		if not menusExist or #menuOrder == 0 then
			g_VR.menuFocus = false
			return
		end
		local sf = g_VR.stereoFrame or 0
		local eye = g_VR.stereoEye
		-- First eye of the frame solves laser focus; second eye reuses (no double hit tests)
		-- Always re-solve while resizing or if scale changed since freeze (close-btn desync)
		local mustResolve = g_VR.menuResizeActive
			or (focusSnap.frame ~= sf)
			or (eye == "left")
			or (eye == nil)
		local solveFocus = mustResolve
		if solveFocus then
			g_VR.menuFocus = false
			focusSnap.frame = sf
			focusSnap.uid = false
			focusSnap.panel = nil
			focusSnap.cursorWorld = nil
			focusSnap.scaleKey = 0
		else
			g_VR.menuFocus = focusSnap.uid
		end

		local menuFocusDist = 99999
		local menuFocusPanel = nil
		local menuFocusCursorWorldPos = nil
		local tms = render.GetToneMappingScaleLinear()
		render.SetToneMappingScaleLinear(g_VR.view.dopostprocess and Vector(0.50, 0.50, 0.50) or Vector(1, 1, 1))

		-- Laser from primary hand only (never dual free-for-all)
		local primaryName = vrmod.GetPrimaryHand()
		local laserHand = HandPoseLive(primaryName) or HandPose(primaryName)
		local laserPos = laserHand and laserHand.pos
		local laserAng = laserHand and laserHand.ang
		g_VR.menuPointerHand = primaryName

		for _, v in ipairs(menuOrder) do
			local k = v.uid
			if v.panel then
				if not IsValid(v.panel) then
					VRUtilMenuClose(k)
					continue
				end
				if not v.panel:IsVisible() then
					local keep = v.persistOpen or v.keepAlive or v.allowHiddenPanel
						or (v.panel.IsPaintedManually and v.panel:IsPaintedManually())
						or k == "p2v_spawnmenu" or k == "p2v_contextmenu"
					if keep then
						v.panel:SetVisible(true)
					else
						VRUtilMenuClose(k)
						continue
					end
				end
			end

			if not v.baseScale then
				local uid = v.uid or ""
				local isShell = uid == "p2v_spawnmenu" or uid == "p2v_contextmenu"
					or string.StartWith(uid, "p2v_")
				local keepScale = v.cubeMenu or v.cubeui or isShell
					or uid == "heightmenu"
					or uid == "avatar_menu"
					or uid == "cube_settings"
					or uid == "cubeui_main"
					or string.StartWith(uid, "cubeui_")
				local base = v.scale
				if not base or base <= 0 then
					base = keepScale and (isShell and 0.018 or 0.04) or (v.attachment and 0.04 or 0.02)
				elseif not keepScale and v.attachment and base < 0.03 then
					-- Never inflate intentional shell scales (0.016) to 0.04 — breaks UV hit
					base = 0.04
				elseif not keepScale and not v.attachment then
					base = 0.02
				elseif keepScale and base < 0.01 then
					base = isShell and 0.016 or 0.04
				end
				v.baseScale = base
			end
			if not v.scaleLocked and v.scale and v.scale > 0
				and math.abs(v.scale - (v._lastAssignedScale or -1)) > 1e-6 then
				v.baseScale = v.scale
				v._lastAssignedScale = v.scale
			elseif v.scaleLocked and v.baseScale then
				v.scale = v.baseScale
				v._lastAssignedScale = v.baseScale
			end

			-- Draw ONLY from PreStereo snap. Never re-resolve during eye passes
			-- (live hand between L/R was "new pose on one eye only" while gripping).
			local pos, ang, drawScale = v._snapPos, v._snapAng, v._snapScale
			if not pos or not ang or not drawScale or drawScale <= 0 or v._snapFrame ~= sf then
				if g_VR.stereoEye == "right" and v._snapPos and v._snapAng and v._snapScale then
					-- Prefer previous snap over live recompute on second eye
					pos, ang, drawScale = v._snapPos, v._snapAng, v._snapScale
				else
					pos, ang, drawScale = ResolveDrawPose(v)
					if not pos or not ang then continue end
					if not v._snapPos then v._snapPos = Vector() end
					if not v._snapAng then v._snapAng = Angle() end
					v._snapPos:Set(pos)
					v._snapAng:Set(ang)
					v._snapScale = drawScale
					v._snapFrame = sf
				end
			end
			if not pos or not ang then continue end

			-- SetTexture only when RT instance changes
			if v.mat and not v.mat:IsError() and v._boundRT ~= v.rt then
				v.mat:SetTexture("$basetexture", v.rt)
				v._boundRT = v.rt
			end

			local hitCursorX, hitCursorY, hitDist, hitWorld = nil, nil, nil, nil
			local resizingThis = resizeState and resizeState.uid == k
			local wantCursor = v.cursorEnabled or MenuIsResizable(v) or resizingThis
			-- Recompute UV if scale/pose changed (stale UV after stretch → X button miss)
			local hitStale = (v._hitFrame ~= sf)
				or not v._hitScale
				or math.abs((v._hitScale or 0) - drawScale) > 1e-7
			if wantCursor and (solveFocus or hitStale or resizingThis) and laserPos and laserAng then
				local dir = laserAng:Forward()
				local normal = ang:Up()
				local A = normal:Dot(dir)
				if A < 0 then
					local B = normal:Dot(pos - laserPos)
					if B < 0 then
						hitDist = B / A
						hitWorld = laserPos + dir * hitDist
						local tp = WorldToLocal(hitWorld, Angle(0, 0, 0), pos, ang)
						hitCursorX = tp.x / drawScale
						hitCursorY = -tp.y / drawScale
						v._hitX, v._hitY, v._hitDist, v._hitWorld = hitCursorX, hitCursorY, hitDist, hitWorld
						v._hitFrame = sf
						v._hitScale = drawScale
						v.lastCursorX = hitCursorX
						v.lastCursorY = hitCursorY
					end
				end
			elseif wantCursor and v._hitFrame == sf and v._hitScale and math.abs(v._hitScale - drawScale) <= 1e-7 then
				hitCursorX, hitCursorY, hitDist, hitWorld = v._hitX, v._hitY, v._hitDist, v._hitWorld
			end

			cam.IgnoreZ(true)
			cam.Start3D2D(pos, ang, drawScale)
			surface.SetDrawColor(255, 255, 255, 255)
			surface.SetMaterial(v.mat)
			surface.DrawTexturedRect(0, 0, v.width, v.height)
			if uioutline:GetBool() then
				surface.SetDrawColor(255, 0, 0, 255)
				surface.DrawOutlinedRect(0, 0, v.width, v.height)
			end

			local inCorner = hitCursorX and hitCursorY and MenuIsResizable(v)
				and CursorInResizeCorner(v, hitCursorX, hitCursorY)
			if (resizingThis or inCorner) and cv_menu_resize:GetBool() then
				local a = resizingThis and 90 or 45
				surface.SetDrawColor(255, 255, 255, a)
				local w, h = v.width, v.height
				local function cornerGrip(x0, y0, sx, sy)
					surface.DrawLine(x0, y0 + sy * 12, x0, y0)
					surface.DrawLine(x0, y0, x0 + sx * 12, y0)
				end
				if hitCursorX and hitCursorY then
					local left = hitCursorX < w * 0.5
					local top = hitCursorY < h * 0.5
					if left and top then cornerGrip(3, 3, 1, 1)
					elseif (not left) and top then cornerGrip(w - 3, 3, -1, 1)
					elseif left and (not top) then cornerGrip(3, h - 3, 1, -1)
					else cornerGrip(w - 3, h - 3, -1, -1)
					end
				else
					cornerGrip(w - 3, h - 3, -1, -1)
				end
			end
			cam.End3D2D()
			cam.IgnoreZ(false)

			if solveFocus and wantCursor and hitCursorX and hitCursorY and hitDist then
				local cz = CornerZoneSize(v)
				-- Generous pad so large shells stay focusable at arm's length
				local pad = math.max(cz * 0.35, 24)
				local inside = hitCursorX > -pad and hitCursorY > -pad
					and hitCursorX < v.width + pad and hitCursorY < v.height + pad
				local keepResize = resizingThis and hitDist < menuFocusDist + 50
				if (inside or keepResize) and hitDist < menuFocusDist then
					g_VR.menuFocus = k
					menuFocusDist = hitDist
					menuFocusPanel = v.panel
					-- Cursor move dirties RT for hover paint (MenuShouldRepaint)
					if v.lastCursorX ~= hitCursorX or v.lastCursorY ~= hitCursorY then
						v.dirty = true
					end
					v.lastCursorX = hitCursorX
					v.lastCursorY = hitCursorY
					menuFocusCursorWorldPos = hitWorld
					focusSnap.uid = k
					focusSnap.panel = v.panel
					focusSnap.cursorWorld = hitWorld
					focusSnap.cursorX = hitCursorX
					focusSnap.cursorY = hitCursorY
					focusSnap.scaleKey = drawScale
				end
			end
		end

		render.SetToneMappingScaleLinear(tms)

		if solveFocus then
			if focusSnap.panel ~= prevFocusPanel then
				if IsValid(prevFocusPanel) then prevFocusPanel:SetMouseInputEnabled(false) end
				if IsValid(focusSnap.panel) then focusSnap.panel:SetMouseInputEnabled(true) end
				gui.EnableScreenClicker(focusSnap.panel ~= nil)
				prevFocusPanel = focusSnap.panel
			end
		end

		local focus = g_VR.menuFocus
		if focus and menus[focus] then
			-- Always prefer live lastCursor (remapped after stretch) over frozen snap UV
			local lcX = menus[focus].lastCursorX
			local lcY = menus[focus].lastCursorY
			if lcX and lcY then
				g_VR.menuCursorX = lcX
				g_VR.menuCursorY = lcY
			else
				g_VR.menuCursorX = focusSnap.cursorX
				g_VR.menuCursorY = focusSnap.cursorY
			end
			local beamEnd = menus[focus]._hitWorld or focusSnap.cursorWorld
			if laserPos and beamEnd then
				render.SetMaterial(mat_beam)
				-- Cool tint when primary is left so it's obvious which hand aims
				local col = (primaryName == "left")
					and Color(180, 220, 255, 255)
					or Color(255, 255, 255, 255)
				render.DrawBeam(laserPos, beamEnd, 0.1, 0, 1, col)
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
			-- Laser hit always on for VR windows (needed for corner resize on every panel)
			cursorEnabled = cursorEnabled ~= false,
			rt = rt,
			width = width,
			height = height,
			lastCursorX = 0,
			lastCursorY = 0,
			-- Every VR window: free-grab + corner resize (opt out with grabbable/resizable=false)
			grabbable = true,
			resizable = true,
			scaleLocked = false,
			freeFloat = not attachment,
			-- Wrist menus default to secondary (non-primary) hand
			attachHand = attachment and vrmod.GetSecondaryHand() or nil,
			grabHand = nil,
			grabPos = nil,
			grabAng = nil,
			dirty = true,
			-- Cube: unfocused idle heartbeat (0=dirty-only). Focused: dirty-only by default
			-- (paintIntervalFocused>0 only for animated HTML — avoids CUtlRBTree overflow).
			paintInterval = 12,
			paintIntervalFocused = 0,
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

		-- Restore remembered pos / size (scale) / free-float for this panel
		vrmod.ApplyMenuLayout(uid, menus[uid])

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
		-- Panel-local laser UV (RT space). Shells are forced to SetPos(0,0) — LocalToScreen
		-- is only safe when the panel actually sits at origin; otherwise clicks miss.
		local x, y = menu.lastCursorX, menu.lastCursorY
		x = math.Clamp(x, 0, (menu.width or 1024) - 1)
		y = math.Clamp(y, 0, (menu.height or 768) - 1)
		g_VR.menuCursorX = x
		g_VR.menuCursorY = y
		local panel = menu.panel
		if IsValid(panel) then
			if panel.SetMouseInputEnabled then panel:SetMouseInputEnabled(true) end
			local px, py = 0, 0
			if panel.GetPos then px, py = panel:GetPos() end
			-- Painted-manual shells at 0,0: UV is already "screen" for InternalMouse*
			if (px == 0 and py == 0) or menu.uid and string.StartWith(tostring(menu.uid), "p2v_") then
				input.SetCursorPos(math.floor(x + 0.5), math.floor(y + 0.5))
				return
			end
			if panel.LocalToScreen then
				local sx, sy = panel:LocalToScreen(x, y)
				if sx and sy then
					input.SetCursorPos(math.floor(sx + 0.5), math.floor(sy + 0.5))
					return
				end
			end
		end
		input.SetCursorPos(math.floor(x + 0.5), math.floor(y + 0.5))
	end

	function VRUtilMenuClose(uid)
		for k, v in pairs(menus) do
			if k == uid or not uid then
				-- Persist last free-float pose/size before teardown
				if v and (v.freeFloat or not v.attachment) and v.pos and v.ang then
					vrmod.SaveMenuLayout(k)
				elseif v and (v.baseScale or v.scale) then
					-- Still remember scale even if hand-attached
					local all = ReadLayouts()
					local e = all[tostring(k)] or {}
					e.scale = v.baseScale or v.scale
					if e.freeFloat == nil then e.freeFloat = false end
					all[tostring(k)] = e
					WriteLayouts(all)
				end
				if grabState and grabState.uid == k then
					grabState = nil
					g_VR.menuGrabActive = false
				end
				if resizeState and resizeState.uid == k then
					resizeState = nil
					g_VR.menuResizeActive = false
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
			g_VR.menuResizeActive = false
			grabState = nil
			resizeState = nil
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
		-- Don't inject clicks while resizing (corner drag is not a button press)
		if g_VR.menuResizeActive then return end

		-- Close shells: chat/B always; secondary only on title strip (keep RMB for spawn icons)
		if pressed then
			local uid = g_VR.menuFocus
			local isShell = uid == "p2v_spawnmenu" or uid == "p2v_contextmenu"
			if isShell and vrmod.panel2vr and vrmod.panel2vr.CloseSandboxShell then
				local closeShell = false
				if action == "boolean_chat" then
					closeShell = true
				elseif vrmod.IsMenuSecondaryClick and vrmod.IsMenuSecondaryClick(action) then
					local menu = menus[uid]
					local cy = menu and (menu.lastCursorY or g_VR.menuCursorY) or 999
					-- Title bar (~32px) or context shell: secondary = close
					if uid == "p2v_contextmenu" or cy < 40 then
						closeShell = true
					end
				end
				if closeShell then
					local which = (uid == "p2v_contextmenu") and "context" or "spawn"
					vrmod.panel2vr.CloseSandboxShell(which)
					return
				end
			end
		end

		local mouseButton = nil
		if vrmod.IsMenuPrimaryClick(action) then
			mouseButton = MOUSE_LEFT
		elseif vrmod.IsMenuSecondaryClick(action) then
			-- Right-click: ContentIcon spawn options, Derma context, etc.
			mouseButton = MOUSE_RIGHT
		elseif action == "boolean_sprint" then
			-- Middle-click for Derma only (wrist dock is grip+release near hand — not mid-click)
			mouseButton = MOUSE_MIDDLE
		end

		if mouseButton then
			heldButtons[mouseButton] = pressed
			SyncCursorToVR()
			-- Nudge hover state for Derma under PaintManual
			if gui.InternalCursorMoved then
				pcall(gui.InternalCursorMoved, g_VR.menuCursorX or 0, g_VR.menuCursorY or 0)
			end

			-- RIGHT CLICK (spawn ContentIcon menu):
			-- Derma only calls DoRightClick on mouse *release* when panel.Hovered.
			-- Laser VR often has Hovered=false on release → menu never opens.
			-- Fire DoRightClick on press while laser hover is valid; DMenu:Open is
			-- patched in panel2vr to parent onto the spawn RT.
			if mouseButton == MOUSE_RIGHT then
				if pressed then
					g_VR._dmenuOpened = false
					local p = vgui.GetHoveredPanel and vgui.GetHoveredPanel() or nil
					-- Fallback: walk spawn/context children under laser UV
					if not IsValid(p) and IsValid(menus[g_VR.menuFocus] and menus[g_VR.menuFocus].panel) then
						local root = menus[g_VR.menuFocus].panel
						local lx = menus[g_VR.menuFocus].lastCursorX or g_VR.menuCursorX or 0
						local ly = menus[g_VR.menuFocus].lastCursorY or g_VR.menuCursorY or 0
						-- Convert root-local laser → screen → find child (VGUI helpers)
						if root.LocalToScreen then
							local sx, sy = root:LocalToScreen(lx, ly)
							if sx and vgui.GetHoveredPanel then
								input.SetCursorPos(sx, sy)
								p = vgui.GetHoveredPanel()
							end
						end
					end
					local hops = 0
					while IsValid(p) and hops < 32 do
						if isfunction(p.DoRightClick) then
							pcall(function() p:DoRightClick() end)
							break
						end
						if isfunction(p.OpenMenu) then
							pcall(function() p:OpenMenu() end)
							break
						end
						p = p:GetParent()
						hops = hops + 1
					end
					gui.InternalMousePressed(MOUSE_RIGHT)
				else
					SyncCursorToVR()
					gui.InternalMouseReleased(MOUSE_RIGHT)
				end
			else
				if pressed then
					gui.InternalMousePressed(mouseButton)
				else
					gui.InternalMouseReleased(mouseButton)
				end
			end

			-- Defer shell repaint to PreStereoCapture (never nest under stereo RT mid-input)
			if g_VR.menuFocus then
				vrmod.MarkMenuDirty(g_VR.menuFocus)
			end
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

--- Close every VR window / sandbox shell / Derma popup.
-- @param opts.keep table|nil map of menu uid → true to leave open (default keeps quick menu)
-- @param opts.alsoQuickMenu boolean also close miscmenu (default false)
function vrmod.CloseAllWindows(opts)
	opts = opts or {}
	local keep = {}
	if opts.keep then
		for k, v in pairs(opts.keep) do
			if v then keep[k] = true end
		end
	elseif not opts.alsoQuickMenu then
		keep.miscmenu = true -- stay on QM after "close all windows"
	end

	-- Sandbox shells (proper teardown + HangOpen)
	if vrmod.panel2vr then
		if vrmod.panel2vr.CloseSandboxShell then
			pcall(function() vrmod.panel2vr.CloseSandboxShell("spawn") end)
			pcall(function() vrmod.panel2vr.CloseSandboxShell("context") end)
		end
		if vrmod.panel2vr.CloseAll then
			pcall(function() vrmod.panel2vr.CloseAll() end)
		end
	end

	-- Glide settings (context DesktopWindows)
	if Glide and Glide.Config and isfunction(Glide.Config.CloseFrame) then
		pcall(function() Glide.Config:CloseFrame() end)
	end

	-- Native Cube / avatar / settings helpers
	if isfunction(vrmod.CubeSettings_Close) then pcall(vrmod.CubeSettings_Close) end
	if isfunction(vrmod.AvatarMenu_Close) then pcall(vrmod.AvatarMenu_Close) end
	if isfunction(vrmod.WeaponSettings_Close) then pcall(vrmod.WeaponSettings_Close) end

	-- Derma option menus floating on desktop
	if isfunction(CloseDermaMenus) then pcall(CloseDermaMenus) end

	-- Every VR surface still open
	if g_VR and g_VR.menus then
		local list = {}
		for uid in pairs(g_VR.menus) do
			if not keep[uid] then list[#list + 1] = uid end
		end
		for _, uid in ipairs(list) do
			if isfunction(VRUtilMenuClose) then VRUtilMenuClose(uid) end
		end
	end

	return true
end

concommand.Add("vrmod_close_all_windows", function()
	vrmod.CloseAllWindows()
end)

concommand.Add("vrmod_reset_window_layouts", function()
	-- Poses, sizes, free-float, shell float cache → wrist defaults + reopen QM
	vrmod.ResetAllWindowLayouts({ reopenQM = true, closeAll = true })
end)

concommand.Add("vrmod_vgui_reset", function()
	-- Hard recovery: clear layouts, close everything, reopen QM
	vrmod.ResetAllWindowLayouts({ reopenQM = true, closeAll = true })
end)

-- Rebuild HUD mesh when UI scale changes; dirty open menus (world scale is live via GetUIScale)
cvars.AddChangeCallback("vrmod_ui_scale", function()
	if vrmod.RefreshHUD then vrmod.RefreshHUD() end
	-- Glide/StyledTheme form metrics track ui_scale via ScaleSize
	if g_VR and g_VR.active and vrmod.panel2vr and vrmod.panel2vr.ApplyStyledThemeVRScale then
		vrmod.panel2vr.ApplyStyledThemeVRScale()
	end
	if g_VR and g_VR.menus then
		for uid, m in pairs(g_VR.menus) do
			if m then
				m.dirty = true
				-- Re-pin hand shells so HandMenuPose half-size tracks new draw scale
				if m.attachment and not m.freeFloat and m.width and m.height then
					local sc = m.baseScale or m.scale or 0.03
					if isfunction(VRUtilHandMenuPose) and m._centerLocal then
						local wrist = vrmod.GetMenuWristHand and vrmod.GetMenuWristHand(m) or "left"
						local hp, ha = VRUtilHandMenuPose(m.width, m.height, sc, m._centerLocal, m.ang, wrist)
						if hp then m.pos = hp end
						if ha then m.ang = ha end
					end
				end
			end
		end
	end
end, "vrmod_ui_scale_hud")

concommand.Add("vrmod_menu_reattach", function()
	if not CLIENT then return end
	if vrmod.MenuReattach and vrmod.MenuReattach() then
		local h = vrmod.GetSecondaryHand and vrmod.GetSecondaryHand() or "wrist"
		if vrmod.logger then vrmod.logger.Info("[UI] Menu reattached to %s hand", h) end
	end
end)

concommand.Add("vrmod_menu_layout_clear", function(ply, cmd, args)
	if not CLIENT then return end
	local uid = args and args[1]
	if uid and uid ~= "" then
		vrmod.ClearMenuLayout(uid)
		if g_VR and g_VR.menus and g_VR.menus[uid] then
			vrmod.ResetMenuPose(uid)
		end
		print("[vrmod] Cleared layout for " .. tostring(uid))
	else
		vrmod.ResetAllWindowLayouts({ reopenQM = true, closeAll = true })
		print("[vrmod] Reset all window poses/sizes/anchors + reopened QM")
	end
end)

concommand.Add("vrmod_menu_layout_save", function()
	if not CLIENT or not g_VR or not g_VR.menus then return end
	local n = 0
	for uid, _ in pairs(g_VR.menus) do
		if vrmod.SaveMenuLayout(uid) then n = n + 1 end
	end
	print("[vrmod] Saved layouts for " .. n .. " open panel(s)")
end)