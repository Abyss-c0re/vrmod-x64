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
	-- Primary hand (SoT): laser + menu LMB. Opposite hand = wrist menus.
	-- 0 = right (default), 1 = left. Integer so Cube combo + Derma combo share one path.
	local cv_primary_hand = CreateClientConVar("vrmod_primary_hand", "0", true, FCVAR_ARCHIVE,
		"VR primary hand: 0=right (laser+click), 1=left. Wrist menus use the other hand.", 0, 1)

	------------------------------------------------------------------------
	-- Primary hand SoT (single truth — not dual free-for-all lasers)
	--   Primary   → laser pointer + menu primary click (LMB)
	--   Secondary → wrist-attached panels (QM, settings, spawn shell)
	--   Either grip still free-grabs a laser-focused panel
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

	--- Wrist hand for a menu: explicit attachHand wins, else secondary (non-primary).
	function vrmod.GetMenuWristHand(menu)
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

	--- Paint Derma panel into menu RT.
	--- force=true always paints. Otherwise: focused every frame; unfocused every N frames or dirty.
	--- Always PopRenderTarget even if PaintManual errors (nested RT stack corruption → hard crash).
	function VRUtilMenuRenderPanel(uid, force)
		local menu = menus[uid]
		if not menu or not menu.rt or not menu.panel or not menu.panel:IsValid() then return end
		local fn = FrameNumber and FrameNumber() or 0
		if not force then
			local focused = (g_VR.menuFocus == uid)
			local interval = focused and 1 or (menu.paintInterval or 4)
			if not menu.dirty and menu._lastPaintFrame
				and (fn - menu._lastPaintFrame) < interval then
				return
			end
		end
		menu.dirty = false
		menu._lastPaintFrame = fn

		render.PushRenderTarget(menu.rt)
		cam.Start2D()
		ClearMenuRT(menu.width, menu.height)
		local ok, err = pcall(function()
			local oldclip = DisableClipping(false)
			render.SetWriteDepthToDestAlpha(false)
			menu.panel:PaintManual()
			render.SetWriteDepthToDestAlpha(true)
			DisableClipping(oldclip)
		end)
		render.OverrideAlphaWriteEnable(false)
		cam.End2D()
		render.PopRenderTarget()
		if not ok then
			menu._paintErrN = (menu._paintErrN or 0) + 1
			if menu._paintErrN <= 3 and vrmod and vrmod.logger then
				vrmod.logger.Warn("Menu RT paint %s: %s", tostring(uid), tostring(err))
			end
		end
	end

	function VRUtilMenuRenderStart(uid)
		local menu = menus[uid]
		if not menu or not menu.rt then return false end
		-- Native paint paths always force (caller owns full redraw)
		menu.dirty = false
		menu._lastPaintFrame = FrameNumber and FrameNumber() or 0
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
		local halfW = w * scale * 0.5
		local halfH = h * scale * 0.5
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
		local entry = {
			scale = sc,
			scaleLocked = menu.scaleLocked and true or false,
			freeFloat = (menu.freeFloat or not menu.attachment) and true or false,
			width = menu.width,
			height = menu.height,
		}
		if menu.pos then
			entry.pos = { x = menu.pos.x, y = menu.pos.y, z = menu.pos.z }
		end
		if menu.ang then
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
		if e.scale and tonumber(e.scale) and tonumber(e.scale) > 0 then
			LockMenuScale(menu, tonumber(e.scale))
			applied = true
		elseif e.scaleLocked then
			menu.scaleLocked = true
		end
		-- freeFloat==false means user reattached: keep open-time attachment, only scale above
		if e.freeFloat and e.pos and e.ang then
			local px, py, pz = e.pos.x or e.pos[1], e.pos.y or e.pos[2], e.pos.z or e.pos[3]
			local ap, ay, ar = e.ang.p or e.ang[1], e.ang.y or e.ang[2], e.ang.r or e.ang[3]
			if px and py and pz and ap and ay and ar then
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

	local function EndResize(handName)
		if not resizeState or resizeState.hand ~= handName then return false end
		local uid = resizeState.uid
		local menu = menus[uid]
		if menu then
			LockMenuScale(menu, menu.baseScale or menu.scale)
			-- Resnap pose+scale and clear stale laser UV (was pre-stretch)
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
		return true
	end

	local function EndGrab(handName)
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
			vrmod.SaveMenuLayout(grabState.uid)
		end
		grabState = nil
		g_VR.menuGrabActive = false
		return true
	end

	--- Resize from grip-hand distance to panel origin (stereo-safe; no per-eye laser).
	local function UpdateResizeFromHand()
		if not resizeState then return end
		local menu = menus[resizeState.uid]
		if not menu then return end
		local hand = HandPose(resizeState.hand)
		if not hand or not hand.pos then return end
		local origin = resizeState.origin
		if not origin then return end
		local dist = hand.pos:Distance(origin)
		local startDist = resizeState.startDist or 1
		if startDist < 2 then startDist = 2 end
		local ns = (resizeState.startScale or 0.03) * (dist / startDist)
		local prev = menu.baseScale or menu.scale or 0
		LockMenuScale(menu, ns)
		if math.abs((menu.baseScale or 0) - prev) > 1e-6 then
			menu._snapFrame = -1
			InvalidateMenuHit(menu)
		end
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

		-- Corner grip → resize (every window by default); body grip → free-move if grabbable
		if resizeOn and MenuIsResizable(menu) and CursorInResizeCorner(menu, cx, cy) then
			-- Detach to free-float so resize stays put while scaling
			local wPos, wAng = ResolveMenuWorldPose(menu)
			if not menu.freeFloat and wPos and wAng then
				local origin = g_VR.origin or Vector()
				local originAng = g_VR.originAngle or Angle()
				menu.pos, menu.ang = WorldToLocal(wPos, wAng, origin, originAng)
				menu.freeFloat = true
				menu.attachment = false
				wPos, wAng = ResolveMenuWorldPose(menu)
			end
			local hand = HandPose(handName)
			if not wPos or not hand or not hand.pos then return false end
			local startDist = hand.pos:Distance(wPos)
			if startDist < 2 then startDist = 2 end
			resizeState = {
				uid = uid,
				hand = handName,
				startScale = menu.baseScale or menu.scale or 0.03,
				origin = Vector(wPos), -- panel TL world (fixed while resizing)
				startDist = startDist,
			}
			menu.scaleLocked = true
			menu.resizable = true
			g_VR.menuResizeActive = true
			MarkConsumed(handName, pressed)
			if vrmod.logger then
				vrmod.logger.Debug("[UI] Panel resize start uid=%s hand=%s scale=%.4f",
					tostring(uid), handName, resizeState.startScale)
			end
			return true
		end

		if not grabOn then return false end
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

	--- Snap a free-floating panel back to wrist attach (secondary / attachHand).
	function vrmod.MenuReattach(uid)
		local menu = menus[uid or g_VR.menuFocus]
		if not menu then return false end
		local wPos, wAng = ResolveMenuWorldPose(menu)
		local wrist = MenuAttachHandName(menu)
		local hand = HandPose(wrist)
		if not wPos or not hand or not hand.pos or not hand.ang then return false end
		menu.pos, menu.ang = WorldToLocal(wPos, wAng, hand.pos, hand.ang)
		menu.freeFloat = false
		menu.attachment = true
		menu.attachHand = wrist
		menu.grabHand = nil
		menu.grabPos = nil
		menu.grabAng = nil
		if grabState and grabState.uid == menu.uid then
			grabState = nil
			g_VR.menuGrabActive = false
		end
		if resizeState and resizeState.uid == menu.uid then
			resizeState = nil
			g_VR.menuResizeActive = false
		end
		-- Remember reattached state (no free-float on next open)
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
				local inside = hitCursorX > -cz * 0.2 and hitCursorY > -cz * 0.2
					and hitCursorX < v.width + cz * 0.2 and hitCursorY < v.height + cz * 0.2
				local keepResize = resizingThis and hitDist < menuFocusDist + 50
				if (inside or keepResize) and hitDist < menuFocusDist then
					g_VR.menuFocus = k
					menuFocusDist = hitDist
					menuFocusPanel = v.panel
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
			paintInterval = 4, -- unfocused RT refresh every N frames
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
		-- Panel-local laser → screen space (spawn/content icons need absolute pos)
		local x, y = menu.lastCursorX, menu.lastCursorY
		g_VR.menuCursorX = x
		g_VR.menuCursorY = y
		if IsValid(menu.panel) and menu.panel.LocalToScreen then
			local sx, sy = menu.panel:LocalToScreen(x, y)
			if sx and sy then
				input.SetCursorPos(sx, sy)
				return
			end
		end
		input.SetCursorPos(x, y)
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
		local mouseButton = nil
		if vrmod.IsMenuPrimaryClick(action) then
			mouseButton = MOUSE_LEFT
		elseif vrmod.IsMenuSecondaryClick(action) then
			-- Right-click: ContentIcon spawn options, Derma context, etc.
			mouseButton = MOUSE_RIGHT
		elseif action == "boolean_sprint" then
			-- Middle-click for Derma. Reattach only if laser is on the title bar
			-- (free-float panels used to steal ALL mid-clicks → spawn menu broke).
			if pressed then
				local m = menus[g_VR.menuFocus]
				local cy = (m and m.lastCursorY) or g_VR.menuCursorY or 999
				local titleH = 36
				if m and m.freeFloat and not g_VR.menuGrabActive
					and cy >= 0 and cy < titleH then
					vrmod.MenuReattach(g_VR.menuFocus)
					return
				end
			end
			mouseButton = MOUSE_MIDDLE
		end

		if mouseButton then
			heldButtons[mouseButton] = pressed
			SyncCursorToVR()

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

			-- Force-paint focused shell so DMenus appear on RT this frame
			if g_VR.menuFocus then
				vrmod.MarkMenuDirty(g_VR.menuFocus)
				if isfunction(VRUtilMenuRenderPanel) then
					VRUtilMenuRenderPanel(g_VR.menuFocus, true)
				end
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

concommand.Add("vrmod_menu_layout_clear", function(ply, cmd, args)
	if not CLIENT then return end
	local uid = args and args[1]
	if uid and uid ~= "" then
		vrmod.ClearMenuLayout(uid)
		print("[vrmod] Cleared layout for " .. tostring(uid))
	else
		vrmod.ClearMenuLayout()
		print("[vrmod] Cleared all panel layouts (data/vrmod/panel_layouts.json)")
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