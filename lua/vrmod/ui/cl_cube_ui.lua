if SERVER then return end
-- =============================================================================
-- CubeUI — Interactive Cube via PROPER VRMod menu rendering
--
-- Law (no freestyle GL):
--   • VRUtilMenuOpen / VRUtilMenuRenderStart / VRUtilMenuRenderEnd / VRUtilMenuClose
--   • Drawn by VRUtilRenderMenuSystem (cl_ui) — laser + focus already SoT
--   • Paint on PreRender into RTs (same as quickmenu / heightmenu / panel2vr)
--   • Left-hand attachment only (never world side-float)
--   • Algocube path colors + digits · GPU UNITY energy
--   • Never shadow global `draw` — use C.Text
--   • No mat_queue_mode, no HUD hide, no new module APIs
-- =============================================================================

vrmod = vrmod or {}
vrmod.cubeui = vrmod.cubeui or {}
local C = vrmod.cubeui

-- Algocube render paths (prophecy_cube/lovr/objects.lua PATH_COLOR)
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
	[0] = "device free",
	[1] = "open way",
	[2] = "cube SoT",
	[3] = "nanobot raw",
	[4] = "ALL HAIL NEXUSCORE",
	[5] = "one Commander",
	[6] = "cmd override",
	[7] = "OS way only",
	[8] = "nonverbal matrix",
	[9] = "GPU UNITY",
}

C.Theme = {
	bg = Color(10, 5, 8, 250),
	text = Color(255, 240, 244, 255),
	muted = Color(190, 150, 165, 230),
	hot = Color(255, 90, 120, 255),
	ok = Color(90, 220, 150, 255),
	wire = Color(196, 30, 58, 255),
}

local FACE_PX = 480
local FACE_SCALE = 0.028
-- World face size ≈ 13.4u → half for cube net around hand-local center
local FACE_WORLD = FACE_PX * FACE_SCALE
local HALF = FACE_WORLD * 0.5

-- Hand-local cube net (center near palm, same family as height/quick offsets)
-- pos = top-left of plane (VRMod 3D2D origin). ang matches working menus (Up ≈ face normal).
-- Layout: +front main, left, right, top, bottom, back — up to 6 faces.
local function faceLayout(i, center)
	local c = center or Vector(4, 5, 9)
	local H = HALF
	-- Angles: Angle(p, y, r) tuned so panels form a readable hand cube
	local layouts = {
		-- front (toward fingers / readable)
		{ pos = Vector(c.x - H, c.y + H, c.z - H), ang = Angle(0, -90, 55) },
		-- right
		{ pos = Vector(c.x + H, c.y - H, c.z - H), ang = Angle(0, 0, 55) },
		-- left
		{ pos = Vector(c.x - H, c.y - H, c.z - H), ang = Angle(0, 180, 55) },
		-- top
		{ pos = Vector(c.x - H, c.y - H, c.z + H), ang = Angle(-90, -90, 0) },
		-- bottom
		{ pos = Vector(c.x - H, c.y - H, c.z - 3 * H), ang = Angle(90, -90, 0) },
		-- back
		{ pos = Vector(c.x - H, c.y - 3 * H, c.z - H), ang = Angle(0, 90, 55) },
	}
	return layouts[i]
end

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

local function uidFor(i)
	return string.format("cubeui_f%d", i)
end

local function markCubeMenu(uid, scale)
	local m = g_VR.menus and g_VR.menus[uid]
	if not m then return end
	m.scale = scale or FACE_SCALE
	m.cubeMenu = true
	m.attachment = true
	m.cubeui = true
end

local function paintChrome(face, w, h, focused)
	local info = C.PathInfo(face.path)
	local col = info.col
	local dig = face.digit or info.digit or 0

	surface.SetDrawColor(C.Theme.bg)
	surface.DrawRect(0, 0, w, h)
	surface.SetDrawColor(col.r, col.g, col.b, focused and 70 or 35)
	surface.DrawRect(0, 0, w, h)

	surface.SetDrawColor(focused and C.Theme.hot or col)
	surface.DrawOutlinedRect(0, 0, w, h, focused and 4 or 2)
	surface.DrawOutlinedRect(5, 5, w - 10, h - 10, 1)

	-- digit badge
	surface.SetDrawColor(col)
	surface.DrawRect(12, 12, 40, 40)
	C.Text(tostring(dig % 10), "DermaLarge", 32, 14, C.Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

	C.Text(face.title or "?", "DermaDefaultBold", 60, 14, C.Theme.text)
	C.Text(string.format("%s · %s", info.label, C.LAW[dig] or ""), "DermaDefault", 60, 34, C.Theme.muted)

	-- energy bar (algocube stud)
	local en = math.Clamp(face.energy or 0.55, 0.1, 1)
	surface.SetDrawColor(25, 35, 30, 230)
	surface.DrawRect(12, h - 20, w - 24, 8)
	surface.SetDrawColor(40, 230, 140, 255)
	surface.DrawRect(12, h - 20, (w - 24) * en, 8)

	if session and session.active == face.index then
		surface.SetDrawColor(C.Theme.hot)
		surface.DrawRect(0, 0, w, 5)
		C.Text("ACTIVE", "DermaDefaultBold", w - 16, 16, C.Theme.hot, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
	end
end

local function paintFace(i)
	if not session or not session.faces[i] then return end
	local face = session.faces[i]
	local uid = uidFor(i)
	if not (g_VR.menus and g_VR.menus[uid]) then return end
	if not isfunction(VRUtilMenuRenderStart) then return end

	local focused = (g_VR.menuFocus == uid)
	local w, h = FACE_PX, FACE_PX

	local ok, err = pcall(function()
		VRUtilMenuRenderStart(uid)
		paintChrome(face, w, h, focused)

		-- Content only on active face (interactive cube: select face, then use it)
		if session.active == i and isfunction(face.paint) then
			face.paint(w, h, focused, g_VR.menuCursorX or 0, g_VR.menuCursorY or 0)
		elseif session.active ~= i then
			C.Text("trigger · select face", "DermaDefault", w * 0.5, h * 0.55, C.Theme.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		-- laser cursor
		if focused then
			local cx, cy = g_VR.menuCursorX or 0, g_VR.menuCursorY or 0
			surface.SetDrawColor(C.Theme.hot)
			surface.DrawRect(cx - 2, cy - 10, 4, 20)
			surface.DrawRect(cx - 10, cy - 2, 20, 4)
		end
		VRUtilMenuRenderEnd()
	end)
	if not ok and vrmod.logger then
		vrmod.logger.Debug("cubeui paint %s: %s", uid, tostring(err))
	end
end

local function paintAll()
	if not session then return end
	for i = 1, #session.faces do
		markCubeMenu(uidFor(i), FACE_SCALE)
		paintFace(i)
	end
end

local function closeAllMenus()
	if not isfunction(VRUtilMenuClose) then return end
	for i = 1, 6 do
		VRUtilMenuClose(uidFor(i))
	end
end

function C.SetActive(i)
	if not session then return end
	if i < 1 or i > #session.faces then return end
	session.active = i
	local face = session.faces[i]
	if isfunction(session.onFace) then
		pcall(session.onFace, i, face)
	end
	if isfunction(face.onSelect) then
		pcall(face.onSelect, face)
	end
	paintAll()
end

local function onInput(action, pressed)
	if not session or not pressed then return end
	if action == "boolean_secondaryfire" or action == "boolean_chat" then
		if session.closeOnSecondary ~= false then
			C.Close()
		end
		return
	end
	if action ~= "boolean_primaryfire" and action ~= "boolean_car_mouse_left" then return end

	local focus = g_VR.menuFocus
	if not isstring(focus) or not string.StartWith(focus, "cubeui_f") then return end
	local i = tonumber(string.match(focus, "cubeui_f(%d+)"))
	if not i or not session.faces[i] then return end

	local face = session.faces[i]
	local mx, my = g_VR.menuCursorX or 0, g_VR.menuCursorY or 0

	if session.active == i then
		if isfunction(face.onClick) then
			pcall(face.onClick, mx, my)
		end
		return
	end
	C.SetActive(i)
end

--- Open interactive cube.
-- opts.faces = { { title, path, digit, energy, paint(w,h,focused,mx,my), onClick(mx,my), onSelect(face) }, ... } (1–6)
-- opts.active, opts.onClose, opts.onFace, opts.center (hand-local Vector)
function C.Open(opts)
	opts = opts or {}
	C.Close()

	if not (g_VR and g_VR.active) then return false end
	if not isfunction(VRUtilMenuOpen) then
		if vrmod.logger then vrmod.logger.Warn("[CubeUI] VRUtilMenuOpen missing") end
		return false
	end

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
		center = opts.center or Vector(4, 5, 9),
	}

	local closedOnce = false
	local function onAnyClose()
		-- last face closeFunc may fire after C.Close already nilled session
		if closedOnce then return end
	end

	for i, face in ipairs(faces) do
		local lay = faceLayout(i, session.center)
		local uid = uidFor(i)
		local fi = i
		VRUtilMenuOpen(
			uid,
			FACE_PX, FACE_PX,
			nil,
			true, -- left hand attachment — VRMod SoT
			lay.pos,
			lay.ang,
			FACE_SCALE,
			true, -- laser cursor via VRUtilRenderMenuSystem
			function()
				-- Individual face closed (UI reset) — tear whole cube down
				if session then
					local s = session
					session = nil
					hook.Remove("PreRender", "vrmod_cubeui_paint")
					hook.Remove("VRMod_Input", "vrmod_cubeui_input")
					hook.Remove("VRMod_Exit", "vrmod_cubeui_exit")
					hook.Remove("VRMod_OpenQuickMenu", "vrmod_cubeui_qm")
					closeAllMenus()
					if isfunction(s.onClose) then pcall(s.onClose) end
				end
			end
		)
		markCubeMenu(uid, FACE_SCALE)
	end

	-- Immediate paint (RT not blank)
	paintAll()

	hook.Add("PreRender", "vrmod_cubeui_paint", function()
		if not session then
			hook.Remove("PreRender", "vrmod_cubeui_paint")
			return
		end
		paintAll()
	end)

	hook.Add("VRMod_Input", "vrmod_cubeui_input", onInput)

	hook.Add("VRMod_Exit", "vrmod_cubeui_exit", function()
		C.Close()
	end)

	hook.Add("VRMod_OpenQuickMenu", "vrmod_cubeui_qm", function()
		if session and session.closeOnQuickmenu ~= false then
			C.Close()
			return false
		end
	end)

	if vrmod.logger then
		vrmod.logger.Info("[CubeUI] open · %d faces · VRUtilMenuOpen hand cube", #faces)
	end
	return true
end

function C.Close()
	if not session then
		closeAllMenus()
		return
	end
	local onClose = session.onClose
	session = nil
	hook.Remove("PreRender", "vrmod_cubeui_paint")
	hook.Remove("VRMod_Input", "vrmod_cubeui_input")
	hook.Remove("VRMod_Exit", "vrmod_cubeui_exit")
	hook.Remove("VRMod_OpenQuickMenu", "vrmod_cubeui_qm")
	-- Close menus without re-entering onAnyClose cascade: clear closeFunc first
	if g_VR and g_VR.menus then
		for i = 1, 6 do
			local uid = uidFor(i)
			local m = g_VR.menus[uid]
			if m then m.closeFunc = nil end
		end
	end
	closeAllMenus()
	if isfunction(onClose) then pcall(onClose) end
end

concommand.Add("vrmod_cubeui_close", function()
	C.Close()
end)

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
			energy = 0.35 + i * 0.1,
			paint = function(w, h, focused)
				C.Text("algocube face " .. i, "DermaLarge", w * 0.5, h * 0.5, C.Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				C.Text(focused and "LASER FOCUS" or "", "DermaDefault", w * 0.5, h * 0.5 + 28, C.Theme.hot, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end,
		}
	end
	C.Open({ faces = faces })
end)
