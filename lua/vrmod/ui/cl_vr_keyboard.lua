if SERVER then return end
-- =============================================================================
-- Shared VR keyboard — reusable launcher + in-game (chat, actions, forms)
--
-- Module driver (v46+): layout, text buffer, hit-test, shift (VRMOD_Keyboard*)
-- Lua: surface paint + laser focus + session policy (onDone / filter / place)
--
-- API (stable):
--   vrmod.VRKeyboard_Open({ title, text, onDone, onCancel, filter, place, role })
--   vrmod.VRKeyboard_Close(commit)
--   vrmod.VRKeyboard_IsOpen()
--   vrmod.VRKeyboard_GetText()
--   vrmod.VRKeyboard_AttachTextEntry(panel, opts)  -- DTextEntry → keyboard
--
-- Roles (module slots): default=1 launcher=2 chat=3 form=4
-- =============================================================================

vrmod = vrmod or {}

local UID = "vrmod_shared_keyboard"
local open = false
local session = nil -- { moduleId, onDone, onCancel, filter, role, uid }

-- Action codes (must match src/input/vkeyboard.h)
local ACT = {
	NONE = 0,
	CHAR = 1,
	BACKSPACE = 2,
	DONE = 3,
	CANCEL = 4,
	SHIFT = 5,
	CLOSE = 6,
	SPACE = 7,
}

local ROLE_SLOT = {
	default = 1,
	launcher = 2,
	chat = 3,
	form = 4,
}

local KW, KH = 555, 300

local function Theme()
	if vrmod.cube and vrmod.cube.ThemeLive then return vrmod.cube.ThemeLive() end
	return {
		text = Color(255, 240, 244, 255),
		muted = Color(200, 150, 165, 230),
		hot = Color(255, 70, 100, 255),
	}
end

local function Font(key)
	if vrmod.cube and vrmod.cube.Font then return vrmod.cube.Font(key) end
	return key == "CubeSmall" and "DermaDefault" or "DermaDefaultBold"
end

local function moduleReady()
	return isfunction(VRMOD_KeyboardOpen) and isfunction(VRMOD_KeyboardPointerClick)
end

function vrmod.VRKeyboard_IsOpen()
	if open and session and session.moduleId and isfunction(VRMOD_KeyboardIsOpen) then
		local ok, v = pcall(VRMOD_KeyboardIsOpen, session.moduleId)
		if ok and v then return true end
	end
	return open == true
end

function vrmod.VRKeyboard_GetText()
	if session and session.moduleId and isfunction(VRMOD_KeyboardGetText) then
		local ok, t = pcall(VRMOD_KeyboardGetText, session.moduleId)
		if ok and t ~= nil then return tostring(t) end
	end
	return session and session.fallbackText or ""
end

function vrmod.VRKeyboard_GetModuleId()
	return session and session.moduleId or nil
end

function vrmod.VRKeyboard_Close(commit)
	if not open and not session then return end
	local s = session
	open = false
	session = nil

	hook.Remove("PreRender", "vrmod_shared_kb_paint")
	hook.Remove("VRMod_Input", "vrmod_shared_kb_input")
	hook.Remove("VRMod_Exit", "vrmod_shared_kb_exit")

	local text = ""
	if s and s.moduleId and isfunction(VRMOD_KeyboardGetText) then
		local ok, t = pcall(VRMOD_KeyboardGetText, s.moduleId)
		if ok then text = tostring(t or "") end
	elseif s then
		text = s.fallbackText or ""
	end

	if s and s.moduleId and isfunction(VRMOD_KeyboardClose) then
		pcall(VRMOD_KeyboardClose, s.moduleId)
	end

	local uid = (s and s.uid) or UID
	if g_VR and g_VR.menus and g_VR.menus[uid] then
		g_VR.menus[uid].closeFunc = nil
	end
	if isfunction(VRUtilMenuClose) then
		pcall(VRUtilMenuClose, uid)
	end

	if s then
		if commit and s.onDone then
			pcall(s.onDone, text)
		elseif not commit and s.onCancel then
			pcall(s.onCancel)
		end
	end
end

local function PoseKeyboard(place)
	place = place or "float"
	if place == "hand" or place == "wrist" then
		local wrist = (vrmod.GetSecondaryHand and vrmod.GetSecondaryHand()) or "left"
		if isfunction(VRUtilHandMenuPose) then
			local pos, ang, sc = VRUtilHandMenuPose(KW, KH, 0.028, Vector(5, 4, 3.5), Angle(0, -90, 10), wrist)
			return pos, ang, true, sc
		end
		return Vector(5, 4, 3.5), Angle(0, -90, 10), true, 0.028
	end
	if vrmod.panel2vr and isfunction(vrmod.panel2vr.ComputeFloatPose) then
		local p, a = vrmod.panel2vr.ComputeFloatPose(20, -8)
		if p and a then return p, a, false, 0.028 end
	end
	if g_VR and g_VR.tracking and g_VR.tracking.hmd then
		local hmd = g_VR.tracking.hmd
		local yaw = Angle(0, hmd.ang.yaw, 0)
		local pos = hmd.pos + yaw:Forward() * 18 + Vector(0, 0, -8)
		local ang = Angle(0, yaw.yaw + 180, 90)
		if g_VR.origin and g_VR.originAngle then
			pos, ang = WorldToLocal(pos, ang, g_VR.origin, g_VR.originAngle)
		end
		return pos, ang, false, 0.028
	end
	return Vector(5, 4, 3.5), Angle(0, -90, 10), true, 0.028
end

local function getKeys(moduleId)
	if isfunction(VRMOD_KeyboardGetKeys) then
		local ok, keys = pcall(VRMOD_KeyboardGetKeys, moduleId)
		if ok and istable(keys) then return keys end
	end
	return {}
end

local function paint()
	if not open or not session or not session.moduleId then return end
	local uid = session.uid or UID
	if not (g_VR and g_VR.menus and g_VR.menus[uid]) then return end

	g_VR.menus[uid].dirty = true
	if isfunction(VRUtilMenuRenderStart) then VRUtilMenuRenderStart(uid) end

	local T = Theme()
	local info = nil
	if isfunction(VRMOD_KeyboardGetInfo) then
		local ok, i = pcall(VRMOD_KeyboardGetInfo, session.moduleId)
		if ok then info = i end
	end
	local title = (info and info.title) or (session.title) or "KEYBOARD"
	local text = (info and info.text) or vrmod.VRKeyboard_GetText() or ""
	local headerH = (info and info.headerH) or 48
	local w = (info and info.width) or KW
	local h = (info and info.height) or KH

	surface.SetDrawColor(12, 6, 10, 250)
	surface.DrawRect(0, 0, w, h)
	surface.SetDrawColor(196, 30, 58, 255)
	surface.DrawRect(0, 0, w, 4)

	draw.SimpleText(title, Font("CubeLabel"), 10, 8, T.hot or Color(255, 70, 100), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

	surface.SetDrawColor(40, 14, 20, 255)
	surface.DrawRect(8, 26, w - 16, 28)
	surface.SetDrawColor(255, 70, 100, 200)
	surface.DrawOutlinedRect(8, 26, w - 16, 28, 2)
	local show = text
	if show == "" then show = "…" end
	draw.SimpleText(show, Font("CubeLabel"), 14, 40, T.text or color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

	local focused = (g_VR.menuFocus == uid)
	local cx, cy = g_VR.menuCursorX or -1, g_VR.menuCursorY or -1
	local clicked = session.pendingClick == true
	if clicked then session.pendingClick = false end

	local keys = getKeys(session.moduleId)
	local hoverIdx = -1
	if focused and isfunction(VRMOD_KeyboardHitTest) then
		local ok, hi = pcall(VRMOD_KeyboardHitTest, session.moduleId, cx, cy)
		if ok then hoverIdx = tonumber(hi) or -1 end
	end

	for i, key in ipairs(keys) do
		local kx, ky, kw, kh = key.x, key.y, key.w, key.h
		local hovered = focused and (hoverIdx == (i - 1)
			or (cx > kx and cx < kx + kw and cy > ky and cy < ky + kh))
		surface.SetDrawColor(hovered and Color(120, 30, 48, 255) or Color(55, 14, 24, 240))
		surface.DrawRect(kx, ky, kw, kh)
		surface.SetDrawColor(196, 30, 58, hovered and 255 or 120)
		surface.DrawOutlinedRect(kx, ky, kw, kh, 1)
		draw.SimpleText(key.label or "", Font("CubeSmall"), kx + kw * 0.5, ky + kh * 0.5,
			T.text or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	if clicked and focused then
		local act, newText, lastChar = 0, text, ""
		if isfunction(VRMOD_KeyboardPointerClick) then
			-- Filter path: hit first, then decide append
			local hi = -1
			if isfunction(VRMOD_KeyboardHitTest) then
				local ok, h = pcall(VRMOD_KeyboardHitTest, session.moduleId, cx, cy)
				if ok then hi = tonumber(h) or -1 end
			end
			if hi >= 0 and keys[hi + 1] then
				local key = keys[hi + 1]
				local a = tonumber(key.action) or 0
				if a == ACT.CHAR or a == ACT.SPACE then
					-- Filtered insert: Lua owns char policy; module owns buffer
					local ch = (a == ACT.SPACE) and " " or tostring(key.label or "")
					if ch == "space" then ch = " " end
					if session.filter and isfunction(session.filter) then
						local ok, out = pcall(session.filter, ch, text)
						if ok then
							if out == false or out == nil then ch = "" else ch = tostring(out) end
						end
					end
					if ch ~= "" and isfunction(VRMOD_KeyboardAppend) then
						pcall(VRMOD_KeyboardAppend, session.moduleId, ch)
					end
				else
					local ok, a2 = pcall(VRMOD_KeyboardPointerClick, session.moduleId, cx, cy)
					if ok then act = tonumber(a2) or 0 end
					if act == ACT.DONE then
						if isfunction(VRUtilMenuRenderEnd) then VRUtilMenuRenderEnd() end
						vrmod.VRKeyboard_Close(true)
						return
					elseif act == ACT.CANCEL or act == ACT.CLOSE then
						if isfunction(VRUtilMenuRenderEnd) then VRUtilMenuRenderEnd() end
						vrmod.VRKeyboard_Close(false)
						return
					end
				end
			end
		end
	end

	if focused and cx >= 0 and cy >= 0 then
		surface.SetDrawColor(255, 70, 100, 255)
		surface.DrawRect(cx - 2, cy - 12, 4, 24)
		surface.DrawRect(cx - 12, cy - 2, 24, 4)
	end

	if isfunction(VRUtilMenuRenderEnd) then VRUtilMenuRenderEnd() end
end

--- Open shared keyboard. Returns true on success.
-- opts.role = "default"|"launcher"|"chat"|"form" (module slot)
-- opts.place = "float"|"hand"
-- opts.uid = optional menu uid (default vrmod_shared_keyboard)
function vrmod.VRKeyboard_Open(opts)
	opts = opts or {}
	if open then
		vrmod.VRKeyboard_Close(false)
	end
	if not (g_VR and g_VR.active) then
		return false
	end
	if not isfunction(VRUtilMenuOpen) then
		if vrmod.Toast then vrmod.Toast("VR menus unavailable", 3, "error") end
		return false
	end

	local role = opts.role or "default"
	local slot = ROLE_SLOT[role] or ROLE_SLOT.default
	local title = opts.title or "KEYBOARD"
	local initial = opts.text or ""
	local uid = opts.uid or UID
	local width = opts.width or KW
	local height = opts.height or KH

	local moduleId = nil
	if moduleReady() then
		local ok, id = pcall(VRMOD_KeyboardOpen, title, initial, width, height, slot)
		if ok and type(id) == "number" and id > 0 then
			moduleId = id
		elseif ok and id == false then
			-- create failed
		end
	end

	-- Soft fallback: pure Lua buffer if module missing (old DLL)
	if not moduleId then
		session = {
			moduleId = nil,
			fallbackText = initial,
			title = title,
			onDone = opts.onDone,
			onCancel = opts.onCancel,
			filter = opts.filter,
			role = role,
			uid = uid,
			pendingClick = false,
			soft = true,
		}
		-- Still open UI; paint uses soft path via GetText
		if vrmod.logger then
			vrmod.logger.Warn("[VRKeyboard] module driver missing — soft Lua mode")
		end
	else
		session = {
			moduleId = moduleId,
			title = title,
			onDone = opts.onDone,
			onCancel = opts.onCancel,
			filter = opts.filter,
			role = role,
			uid = uid,
			pendingClick = false,
		}
	end
	open = true

	local pos, ang, attach, scale = PoseKeyboard(opts.place or "float")
	scale = scale or 0.028
	VRUtilMenuOpen(uid, width, height, nil, attach, pos, ang, scale, true, function()
		if open then
			vrmod.VRKeyboard_Close(false)
		end
	end)

	if not (g_VR.menus and g_VR.menus[uid] and g_VR.menus[uid].rt) then
		vrmod.VRKeyboard_Close(false)
		if vrmod.Toast then vrmod.Toast("Keyboard failed to open", 3, "error") end
		return false
	end

	local sm = g_VR.menus[uid]
	sm.cubeMenu = true
	sm.grabbable = true
	sm.freeFloat = not attach
	sm.attachment = attach and true or false
	sm.dirty = true
	sm.pos = pos
	sm.ang = ang
	sm.virtualKeyboard = true
	if not sm.scaleLocked then sm.scale = scale end

	hook.Add("PreRender", "vrmod_shared_kb_paint", function()
		if not open then
			hook.Remove("PreRender", "vrmod_shared_kb_paint")
			return
		end
		if not session then return end
		local u = session.uid or UID
		if not (g_VR.menus and g_VR.menus[u]) then
			open = false
			return
		end
		if session.soft then
			-- Minimal soft paint if no module (legacy)
			paintSoft()
		else
			paint()
		end
	end)

	hook.Add("VRMod_Input", "vrmod_shared_kb_input", function(action, pressed)
		if not open or not pressed or not session then return end
		if g_VR.menuFocus ~= (session.uid or UID) then return end
		if vrmod.IsMenuPrimaryClick and vrmod.IsMenuPrimaryClick(action) then
			session.pendingClick = true
		end
	end)

	hook.Add("VRMod_Exit", "vrmod_shared_kb_exit", function()
		vrmod.VRKeyboard_Close(false)
	end)

	if vrmod.Toast then
		vrmod.Toast((title) .. " — laser + trigger, Done to confirm", 3, "hint")
	end
	return true
end

-- Soft layout (module absent) — keep actions panel usable
local softLower = "1234567890\1\nqwertyuiop\nasdfghjkl\2\n\3zxcvbnm?\4\3\n "
local softUpper = "!@%\"*+=-_:\1\nQWERTYUIOP\nASDFGHJKL\2\n\3ZXCVBNM/\4\3\n "

function paintSoft()
	if not open or not session then return end
	local uid = session.uid or UID
	if not (g_VR.menus and g_VR.menus[uid]) then return end
	g_VR.menus[uid].dirty = true
	if isfunction(VRUtilMenuRenderStart) then VRUtilMenuRenderStart(uid) end
	local T = Theme()
	surface.SetDrawColor(12, 6, 10, 250)
	surface.DrawRect(0, 0, KW, KH)
	surface.SetDrawColor(196, 30, 58, 255)
	surface.DrawRect(0, 0, KW, 4)
	draw.SimpleText(session.title or "KEYBOARD", Font("CubeLabel"), 10, 8, T.hot, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	surface.SetDrawColor(40, 14, 20, 255)
	surface.DrawRect(8, 26, KW - 16, 28)
	local show = session.fallbackText or ""
	if show == "" then show = "…" end
	draw.SimpleText(show, Font("CubeLabel"), 14, 40, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

	local caseStr = session.upper and softUpper or softLower
	local x, y, rowIndex, closeKeyCount = 1.5, 48 + 1.5, 0, 0
	local KEY_W, KEY_H, SPACING = 45, 42, 1.5
	local focused = (g_VR.menuFocus == uid)
	local cx, cy = g_VR.menuCursorX or -1, g_VR.menuCursorY or -1
	local clicked = session.pendingClick == true
	if clicked then session.pendingClick = false end

	for i = 1, #caseStr do
		local char = string.sub(caseStr, i, i)
		if char == "\n" then
			y = y + KEY_H + SPACING
			rowIndex = rowIndex + 1
			x = (rowIndex == 1 and 20) or (rowIndex == 2 and 35) or (rowIndex == 3 and 5) or (rowIndex == 4 and 127) or 5
		else
			if char == "\3" then closeKeyCount = closeKeyCount + 1 end
			local txt = char
			if char == "\1" then txt = "Del"
			elseif char == "\2" then txt = "Done"
			elseif char == "\4" then txt = "Shift"
			elseif char == "\3" then txt = (closeKeyCount == 1) and "Cancel" or "Close"
			elseif char == " " then txt = "space"
			end
			local w = char == " " and 545 or char == "\2" and 65 or (char == "\4" or char == "\3") and 48 or KEY_W
			local hovered = focused and cx > x and cx < x + w and cy > y and cy < y + KEY_H
			surface.SetDrawColor(hovered and Color(120, 30, 48, 255) or Color(55, 14, 24, 240))
			surface.DrawRect(x, y, w, KEY_H)
			draw.SimpleText(txt, Font("CubeSmall"), x + w * 0.5, y + KEY_H * 0.5, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			if hovered and clicked then
				if txt == "Del" then
					local t = session.fallbackText or ""
					session.fallbackText = string.sub(t, 1, math.max(0, #t - 1))
				elseif txt == "Done" then
					if isfunction(VRUtilMenuRenderEnd) then VRUtilMenuRenderEnd() end
					vrmod.VRKeyboard_Close(true)
					return
				elseif txt == "Shift" then
					session.upper = not session.upper
				elseif txt == "Cancel" or txt == "Close" then
					if isfunction(VRUtilMenuRenderEnd) then VRUtilMenuRenderEnd() end
					vrmod.VRKeyboard_Close(false)
					return
				else
					local ch = (txt == "space") and " " or char
					if session.filter then
						local ok, out = pcall(session.filter, ch, session.fallbackText or "")
						if ok then
							if out == false or out == nil then ch = "" else ch = tostring(out) end
						end
					end
					if ch ~= "" then session.fallbackText = (session.fallbackText or "") .. ch end
				end
			end
			x = x + w + SPACING
		end
	end
	if isfunction(VRUtilMenuRenderEnd) then VRUtilMenuRenderEnd() end
end

--- Bind a DTextEntry (or any GetValue/SetValue panel) to the shared keyboard.
function vrmod.VRKeyboard_AttachTextEntry(panel, opts)
	opts = opts or {}
	if not IsValid(panel) then return false end
	if not (g_VR and g_VR.active) then return false end
	local initial = ""
	if panel.GetValue then initial = tostring(panel:GetValue() or "")
	elseif panel.GetText then initial = tostring(panel:GetText() or "")
	end
	return vrmod.VRKeyboard_Open({
		title = opts.title or "INPUT",
		text = initial,
		role = opts.role or "form",
		place = opts.place or "float",
		filter = opts.filter,
		onDone = function(text)
			if not IsValid(panel) then return end
			if panel.SetValue then pcall(function() panel:SetValue(text) end)
			elseif panel.SetText then pcall(function() panel:SetText(text) end)
			end
			if panel.OnValueChange then pcall(function() panel:OnValueChange(text) end) end
			if opts.onDone then pcall(opts.onDone, text, panel) end
		end,
		onCancel = opts.onCancel,
	})
end

--- Patch a TextEntry so VR laser click opens the shared module keyboard.
function vrmod.VRKeyboard_BindPanel(panel, opts)
	if not IsValid(panel) then return end
	opts = opts or {}
	if panel._vrmodKbBound then return end
	panel._vrmodKbBound = true
	local old = panel.OnMousePressed
	function panel:OnMousePressed(code)
		if g_VR and g_VR.active and isfunction(vrmod.VRKeyboard_AttachTextEntry) then
			timer.Simple(0, function()
				if IsValid(self) then
					vrmod.VRKeyboard_AttachTextEntry(self, opts)
				end
			end)
			return
		end
		if old then return old(self, code) end
	end
end

--- Launcher helper (same driver, launcher slot)
function vrmod.VRKeyboard_OpenLauncher(opts)
	opts = opts or {}
	opts.role = "launcher"
	opts.place = opts.place or "float"
	return vrmod.VRKeyboard_Open(opts)
end

concommand.Add("vrmod_keyboard_status", function()
	print(string.format("[gVRMod] VRKeyboard open=%s moduleId=%s text=%q module=%s",
		tostring(vrmod.VRKeyboard_IsOpen()),
		tostring(session and session.moduleId),
		vrmod.VRKeyboard_GetText(),
		tostring(moduleReady())))
	if isfunction(VRMOD_KeyboardSystemAvailable) then
		local ok, sys = pcall(VRMOD_KeyboardSystemAvailable)
		print("  systemKeyboard=", ok and sys)
	end
end)

concommand.Add("vrmod_keyboard_test", function()
	if not (g_VR and g_VR.active) then
		print("[gVRMod] start VR first")
		return
	end
	vrmod.VRKeyboard_Open({
		title = "TEST",
		text = "",
		role = "default",
		onDone = function(t) print("[gVRMod] keyboard done:", t) end,
		onCancel = function() print("[gVRMod] keyboard cancel") end,
	})
end)
