if SERVER then return end
-- =============================================================================
-- CubeUI — Interactive Cube on ONE left-hand VRMod menu surface
--
-- Why one surface: multi-face menus fought laser focus (no click / ghost close).
-- Render SoT (unchanged):
--   VRUtilMenuOpen → PreRender paint RT → VRUtilRenderMenuSystem laser
--   VRMod_Input for trigger · never freestyle PostDraw
-- =============================================================================

vrmod = vrmod or {}
vrmod.cubeui = vrmod.cubeui or {}
local C = vrmod.cubeui

local UID = "cubeui_main"
local W, H = 640, 720
local SCALE = 0.036
-- Same placement family as heightmenu / quickmenu (hand, not world float)
local HAND_POS = Vector(5, 3.5, 9)
local HAND_ANG = Angle(0, -90, 56)

C.PATH = {
	hud_line      = { col = Color(242, 64, 89),   digit = 0, label = "hud_line" },
	inject_hybrid = { col = Color(255, 140, 51),  digit = 1, label = "inject_hybrid" },
	cube_gpu      = { col = Color(77, 217, 255),  digit = 2, label = "cube_gpu" },
	glyph_field   = { col = Color(89, 255, 140),  digit = 3, label = "glyph_field" },
	wivrn         = { col = Color(140, 115, 255), digit = 4, label = "wivrn" },
	alvr          = { col = Color(230, 102, 242), digit = 5, label = "alvr" },
	moonlight     = { col = Color(255, 230, 64),  digit = 6, label = "moonlight" },
	passthrough   = { col = Color(153, 191, 217), digit = 7, label = "passthrough" },
	matrix_only   = { col = Color(242, 51, 77),   digit = 8, label = "matrix_only" },
	gpu_unity     = { col = Color(255, 89, 140),  digit = 9, label = "gpu_unity" },
}

C.LAW = {
	[0] = "device free", [1] = "open way", [2] = "cube SoT", [3] = "nanobot raw",
	[4] = "ALL HAIL NEXUSCORE", [5] = "one Commander", [6] = "cmd override",
	[7] = "OS way only", [8] = "nonverbal matrix", [9] = "GPU UNITY",
}

C.Theme = {
	bg = Color(10, 5, 8, 250),
	panel = Color(22, 10, 14, 245),
	text = Color(255, 240, 244, 255),
	muted = Color(190, 150, 165, 230),
	hot = Color(255, 90, 120, 255),
	ok = Color(90, 220, 150, 255),
	wire = Color(196, 30, 58, 255),
	close = Color(180, 40, 50, 255),
}

local session = nil

function C.Text(str, font, x, y, col, ax, ay)
	draw.SimpleText(
		tostring(str or ""),
		font or "DermaDefault",
		x, y,
		col or C.Theme.text,
		ax or TEXT_ALIGN_LEFT,
		ay or TEXT_ALIGN_TOP
	)
end

function C.PathInfo(name)
	return C.PATH[name or "hud_line"] or C.PATH.hud_line
end

function C.IsOpen()
	return session ~= nil
end

function C.GetActive()
	return session and session.active or 1
end

function C.GetSession()
	return session
end

function C.IsFocused()
	return session and g_VR and g_VR.menuFocus == UID
end

-- Interactive cube glyph (isometric) on left rail — clickable faces
local CUBE = {
	-- face index → diamond/quad in panel pixels (cx,cy of cube origin)
	-- Layout: center "front" + ring of categories (max 6)
}
local function cubeQuads(cx, cy, s)
	-- Isometric cube: three visible faces + three "tabs" as side chips for 6 faces
	-- Front diamond, top, left, right, and two chips below
	local quads = {}
	-- front (face 1)
	quads[1] = {
		{ x = cx, y = cy },
		{ x = cx + s, y = cy + s * 0.55 },
		{ x = cx, y = cy + s * 1.1 },
		{ x = cx - s, y = cy + s * 0.55 },
	}
	-- top (face 2)
	quads[2] = {
		{ x = cx, y = cy - s * 0.9 },
		{ x = cx + s, y = cy - s * 0.35 },
		{ x = cx, y = cy },
		{ x = cx - s, y = cy - s * 0.35 },
	}
	-- right (face 3)
	quads[3] = {
		{ x = cx + s, y = cy - s * 0.35 },
		{ x = cx + s * 1.7, y = cy + s * 0.2 },
		{ x = cx + s, y = cy + s * 0.55 },
		{ x = cx, y = cy },
	}
	-- left (face 4)
	quads[4] = {
		{ x = cx - s, y = cy - s * 0.35 },
		{ x = cx, y = cy },
		{ x = cx - s, y = cy + s * 0.55 },
		{ x = cx - s * 1.7, y = cy + s * 0.2 },
	}
	-- chip bottom-left (face 5)
	quads[5] = {
		{ x = cx - s * 1.5, y = cy + s * 1.2 },
		{ x = cx - s * 0.2, y = cy + s * 1.2 },
		{ x = cx - s * 0.2, y = cy + s * 1.75 },
		{ x = cx - s * 1.5, y = cy + s * 1.75 },
	}
	-- chip bottom-right (face 6)
	quads[6] = {
		{ x = cx + s * 0.2, y = cy + s * 1.2 },
		{ x = cx + s * 1.5, y = cy + s * 1.2 },
		{ x = cx + s * 1.5, y = cy + s * 1.75 },
		{ x = cx + s * 0.2, y = cy + s * 1.75 },
	}
	return quads
end

local function pointInPoly(px, py, poly)
	-- ray cast
	local inside = false
	local j = #poly
	for i = 1, #poly do
		local xi, yi = poly[i].x, poly[i].y
		local xj, yj = poly[j].x, poly[j].y
		local intersect = ((yi > py) ~= (yj > py))
			and (px < (xj - xi) * (py - yi) / math.max(0.0001, (yj - yi)) + xi)
		if intersect then inside = not inside end
		j = i
	end
	return inside
end

local function hitCubeFace(mx, my)
	if not session then return nil end
	local quads = session.quads
	if not quads then return nil end
	-- reverse order so chips/top win over back faces
	for i = #session.faces, 1, -1 do
		if quads[i] and pointInPoly(mx, my, quads[i]) then
			return i
		end
	end
	return nil
end

local CLOSE_BTN = { x = 0, y = 0, w = 56, h = 40 } -- filled each paint

local function markMenu()
	local m = g_VR.menus and g_VR.menus[UID]
	if not m then return end
	m.scale = SCALE
	m.cubeMenu = true
	m.cubeui = true
	m.grabbable = true
	if not m.freeFloat and not m.grabHand then
		m.attachment = true
		m.attachHand = (vrmod.GetSecondaryHand and vrmod.GetSecondaryHand()) or "left"
	end
end

local function paint()
	if not session or not isfunction(VRUtilMenuRenderStart) then return end
	if not (g_VR.menus and g_VR.menus[UID]) then return end
	markMenu()

	local focused = (g_VR.menuFocus == UID)
	local mx = focused and (g_VR.menuCursorX or -1) or -1
	local my = focused and (g_VR.menuCursorY or -1) or -1
	local face = session.faces[session.active]
	local info = C.PathInfo(face and face.path)
	local col = info.col

	pcall(function()
		VRUtilMenuRenderStart(UID)

		surface.SetDrawColor(C.Theme.bg)
		surface.DrawRect(0, 0, W, H)

		-- header
		surface.SetDrawColor(col.r * 0.35, col.g * 0.2, col.b * 0.25, 255)
		surface.DrawRect(0, 0, W, 64)
		surface.SetDrawColor(col)
		surface.DrawRect(0, 60, W, 4)

		C.Text("GPU UNITY", "DermaDefaultBold", 16, 10, C.Theme.hot)
		C.Text("INTERACTIVE CUBE", "DermaLarge", 16, 28, C.Theme.text)
		local dig = (face and face.digit) or info.digit or 0
		C.Text(string.format("d%d · %s · %s", dig, info.label, C.LAW[dig] or ""), "DermaDefault", 16, 48, C.Theme.muted)

		-- CLOSE button (always reachable)
		CLOSE_BTN.x, CLOSE_BTN.y = W - 72, 12
		CLOSE_BTN.w, CLOSE_BTN.h = 56, 40
		local closeHot = focused and mx >= CLOSE_BTN.x and mx <= CLOSE_BTN.x + CLOSE_BTN.w
			and my >= CLOSE_BTN.y and my <= CLOSE_BTN.y + CLOSE_BTN.h
		surface.SetDrawColor(closeHot and C.Theme.hot or C.Theme.close)
		surface.DrawRect(CLOSE_BTN.x, CLOSE_BTN.y, CLOSE_BTN.w, CLOSE_BTN.h)
		surface.SetDrawColor(C.Theme.text)
		surface.DrawOutlinedRect(CLOSE_BTN.x, CLOSE_BTN.y, CLOSE_BTN.w, CLOSE_BTN.h, 2)
		C.Text("X", "DermaLarge", CLOSE_BTN.x + CLOSE_BTN.w * 0.5, CLOSE_BTN.y + CLOSE_BTN.h * 0.5, C.Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

		-- left: interactive cube
		local cx, cy, s = 118, 160, 52
		session.quads = cubeQuads(cx, cy, s)
		local hoverFace = focused and hitCubeFace(mx, my) or nil
		session.hoverFace = hoverFace

		draw.NoTexture()
		for i = 1, #session.faces do
			local f = session.faces[i]
			local q = session.quads[i]
			if not q then continue end
			local pi = C.PathInfo(f.path)
			local active = (session.active == i)
			local hot = (hoverFace == i)
			local a = active and 230 or (hot and 200 or 140)
			surface.SetDrawColor(pi.col.r, pi.col.g, pi.col.b, a)
			surface.DrawPoly(q)
			local ocol = (hot or active) and C.Theme.hot or Color(255, 255, 255, 100)
			surface.SetDrawColor(ocol)
			for e = 1, #q do
				local a1, a2 = q[e], q[e % #q + 1]
				surface.DrawLine(a1.x, a1.y, a2.x, a2.y)
			end
			local sx, sy = 0, 0
			for _, p in ipairs(q) do sx, sy = sx + p.x, sy + p.y end
			sx, sy = sx / #q, sy / #q
			C.Text(tostring((f.digit or pi.digit or i) % 10), "DermaDefaultBold", sx, sy, C.Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		C.Text(face and face.title or "?", "DermaDefaultBold", cx, cy + s * 2.1, C.Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		C.Text("point cube · trigger", "DermaDefault", cx, cy + s * 2.35, C.Theme.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

		-- right: content panel
		local px, py, pw, ph = 230, 80, W - 246, H - 110
		surface.SetDrawColor(C.Theme.panel)
		surface.DrawRect(px, py, pw, ph)
		surface.SetDrawColor(col)
		surface.DrawOutlinedRect(px, py, pw, ph, 2)

		if face and isfunction(face.paint) then
			-- local coords for content: offset into panel
			-- face.paint expects full face size — pass panel as canvas with translate via args
			face.paint(pw, ph, focused, mx - px, my - py, px, py)
		else
			C.Text("no content", "DermaDefault", px + pw * 0.5, py + ph * 0.5, C.Theme.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		-- footer
		local focusStr = focused and "LASER LOCK" or "point laser at panel"
		C.Text(focusStr .. "  ·  trigger act  ·  X / secondary close", "DermaDefault", W * 0.5, H - 18, focused and C.Theme.ok or C.Theme.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

		-- cursor
		if focused and mx >= 0 and my >= 0 then
			surface.SetDrawColor(C.Theme.hot)
			surface.DrawRect(mx - 2, my - 12, 4, 24)
			surface.DrawRect(mx - 12, my - 2, 24, 4)
		end

		VRUtilMenuRenderEnd()
	end)
end

function C.SetActive(i)
	if not session then return end
	if i < 1 or i > #session.faces then return end
	session.active = i
	local face = session.faces[i]
	if isfunction(session.onFace) then pcall(session.onFace, i, face) end
	if isfunction(face.onSelect) then pcall(face.onSelect, face) end
end

local function onInput(action, pressed)
	if not session then return end
	-- Secondary / chat = close (works even without laser lock so you can escape)
	if pressed and (action == "boolean_secondaryfire" or action == "boolean_chat") then
		if session.closeOnSecondary ~= false then
			C.Close()
		end
		return
	end
	if not pressed then return end
	if not (vrmod.IsMenuPrimaryClick and vrmod.IsMenuPrimaryClick(action)) then return end

	-- Must be laser-locked on our menu for primary acts
	if g_VR.menuFocus ~= UID then return end
	local mx, my = g_VR.menuCursorX or 0, g_VR.menuCursorY or 0

	-- Close button
	if mx >= CLOSE_BTN.x and mx <= CLOSE_BTN.x + CLOSE_BTN.w
		and my >= CLOSE_BTN.y and my <= CLOSE_BTN.y + CLOSE_BTN.h then
		C.Close()
		return
	end

	-- Cube face select
	local fi = hitCubeFace(mx, my)
	if fi then
		C.SetActive(fi)
		return
	end

	-- Content click (active face)
	local face = session.faces[session.active]
	if face and isfunction(face.onClick) then
		local px = 230
		local py = 80
		pcall(face.onClick, mx - px, my - py)
	end
end

--- Open interactive cube (single hand menu).
-- opts.faces = { title, path, digit, energy, paint(w,h,focused,lx,ly), onClick(lx,ly), onSelect }
function C.Open(opts)
	opts = opts or {}
	C.Close()

	if not (g_VR and g_VR.active) then return false end
	if not isfunction(VRUtilMenuOpen) then return false end

	local faces = opts.faces or {}
	if #faces < 1 then return false end
	if #faces > 6 then
		local t = {}
		for i = 1, 6 do t[i] = faces[i] end
		faces = t
	end
	for i, f in ipairs(faces) do
		f.index = i
	end

	session = {
		faces = faces,
		active = math.Clamp(opts.active or 1, 1, #faces),
		onClose = opts.onClose,
		onFace = opts.onFace,
		closeOnSecondary = opts.closeOnSecondary,
		closeOnQuickmenu = opts.closeOnQuickmenu,
		quads = nil,
		hoverFace = nil,
	}

	local closing = false
	VRUtilMenuOpen(UID, W, H, nil, true, HAND_POS, HAND_ANG, SCALE, true, function()
		if closing then return end
		closing = true
		local onClose = session and session.onClose
		session = nil
		hook.Remove("PreRender", "vrmod_cubeui_paint")
		hook.Remove("VRMod_Input", "vrmod_cubeui_input")
		hook.Remove("VRMod_Exit", "vrmod_cubeui_exit")
		hook.Remove("VRMod_OpenQuickMenu", "vrmod_cubeui_qm")
		if isfunction(onClose) then pcall(onClose) end
	end)

	if not (g_VR.menus and g_VR.menus[UID]) then
		session = nil
		return false
	end
	markMenu()
	paint()

	hook.Add("PreRender", "vrmod_cubeui_paint", function()
		if not session then
			hook.Remove("PreRender", "vrmod_cubeui_paint")
			return
		end
		if not (g_VR.menus and g_VR.menus[UID]) then
			C.Close()
			return
		end
		paint()
	end)

	hook.Add("VRMod_Input", "vrmod_cubeui_input", onInput)
	hook.Add("VRMod_Exit", "vrmod_cubeui_exit", function() C.Close() end)

	-- Only close when quickmenu *opens* while cube is already up (not same-frame as Settings pick)
	hook.Add("VRMod_OpenQuickMenu", "vrmod_cubeui_qm", function()
		if not session then return end
		if session.closeOnQuickmenu == false then return end
		-- Defer one tick so Settings item can open cube without being killed by the same press cycle
		timer.Simple(0, function()
			if session and session.closeOnQuickmenu ~= false then
				-- If we just opened this frame, grace period
				if session.openedAt and CurTime() - session.openedAt < 0.35 then return end
				C.Close()
			end
		end)
		-- Do not return false — allow quickmenu to open after close
	end)

	session.openedAt = CurTime()

	if vrmod.logger then
		vrmod.logger.Info("[CubeUI] open single hand surface %s", UID)
	end
	return true
end

function C.Close()
	if not session then
		if isfunction(VRUtilMenuClose) and g_VR and g_VR.menus and g_VR.menus[UID] then
			local m = g_VR.menus[UID]
			if m then m.closeFunc = nil end
			VRUtilMenuClose(UID)
		end
		return
	end
	local onClose = session.onClose
	session = nil
	hook.Remove("PreRender", "vrmod_cubeui_paint")
	hook.Remove("VRMod_Input", "vrmod_cubeui_input")
	hook.Remove("VRMod_Exit", "vrmod_cubeui_exit")
	hook.Remove("VRMod_OpenQuickMenu", "vrmod_cubeui_qm")
	if g_VR and g_VR.menus and g_VR.menus[UID] then
		g_VR.menus[UID].closeFunc = nil
	end
	if isfunction(VRUtilMenuClose) then
		VRUtilMenuClose(UID)
	end
	if isfunction(onClose) then pcall(onClose) end
end

concommand.Add("vrmod_cubeui_close", function() C.Close() end)

concommand.Add("vrmod_cubeui_demo", function()
	if not (g_VR and g_VR.active) then
		print("[CubeUI] enter VR first")
		return
	end
	local paths = { "cube_gpu", "hud_line", "glyph_field", "wivrn", "gpu_unity", "inject_hybrid" }
	local faces = {}
	for i, p in ipairs(paths) do
		local info = C.PathInfo(p)
		faces[i] = {
			title = string.upper(p),
			path = p,
			digit = info.digit,
			energy = 0.4 + i * 0.08,
			paint = function(w, h, focused, lx, ly)
				C.Text("face " .. i .. " · " .. p, "DermaLarge", w * 0.5, h * 0.4, C.Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				C.Text(focused and "focused" or "", "DermaDefault", w * 0.5, h * 0.55, C.Theme.ok, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end,
		}
	end
	C.Open({ faces = faces, closeOnSecondary = true })
end)
