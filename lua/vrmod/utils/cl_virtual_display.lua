if SERVER then return end
-- =============================================================================
-- vrmod.VirtualDisplay — reusable "monitor" for launcher + in-game VR UI
--
-- Prophecy: one pipeline for menu-first OpenXR launcher and pause/hub while
-- playing. Module owns a GPU virtual display (FBO + optional window capture);
-- Lua owns session policy, panel2vr presentation, and input.
--
-- Sessions (named):
--   "launcher"  — menu-first / OpenXR immersive start
--   "pause"     — ESC / pause hub (never ActivateGameUI)
--   custom      — any string
--
-- Modes:
--   "native"  — drawFn paints into panel2vr RT (Cube hub, custom UI)
--   "vgui"    — bind a live Panel via PaintManual (GameUI / Derma shells)
--   "capture" — module CaptureWindow each frame + optional VGUI overlay
--               (desktop mirror foundation; GL tex for future quad-layer)
--
-- Does NOT call ActivateGameUI (SP freeze). Callers keep the world unpaused.
-- =============================================================================

vrmod = vrmod or {}
vrmod.VirtualDisplay = vrmod.VirtualDisplay or {}

local VD = vrmod.VirtualDisplay

-- name → session state
local sessions = {}

-- Stable module slot hints so recreate is cheap
local SLOT_HINT = {
	launcher = 1,
	pause = 2,
}

local function log(fmt, ...)
	if vrmod.logger then
		vrmod.logger.Info("[VirtualDisplay] " .. fmt, ...)
	else
		print("[VirtualDisplay] " .. string.format(fmt, ...))
	end
end

local function moduleReady()
	return isfunction(VRMOD_VirtualDisplayCreate)
end

local function defaultSize(role)
	if vrmod.GetVRUIPanelMetrics then
		local w, h, sc = vrmod.GetVRUIPanelMetrics(role == "launcher" and "mainmenu" or "popup")
		return w or 720, h or 560, sc or 0.02
	end
	return 720, 560, 0.02
end

--- Module-backed display metrics (creates GPU surface when supported).
function VD.EnsureModuleDisplay(name, width, height)
	if not moduleReady() then return nil end
	local s = sessions[name]
	if s and s.moduleId and s.moduleId > 0 then
		local info = VRMOD_VirtualDisplayGetInfo and VRMOD_VirtualDisplayGetInfo(s.moduleId)
		if info and info.valid then
			if width and height and (info.width ~= width or info.height ~= height) then
				pcall(VRMOD_VirtualDisplayResize, s.moduleId, width, height)
			end
			return s.moduleId, VRMOD_VirtualDisplayGetInfo(s.moduleId)
		end
	end
	local hint = SLOT_HINT[name] or 0
	local ok, idOrErr = pcall(VRMOD_VirtualDisplayCreate, width or 1280, height or 720, hint)
	if not ok then
		log("Create pcall fail: %s", tostring(idOrErr))
		return nil
	end
	-- API: returns id on success, or false, err on failure
	if idOrErr == false or idOrErr == nil then
		return nil
	end
	if type(idOrErr) ~= "number" or idOrErr <= 0 then
		return nil
	end
	return idOrErr, VRMOD_VirtualDisplayGetInfo and VRMOD_VirtualDisplayGetInfo(idOrErr) or nil
end

function VD.IsModuleSupported()
	if isfunction(VRMOD_VirtualDisplayIsSupported) then
		local ok, v = pcall(VRMOD_VirtualDisplayIsSupported)
		return ok and v == true
	end
	return false
end

function VD.GetSession(name)
	return sessions[name]
end

function VD.IsOpen(name)
	local s = sessions[name]
	if not s then return false end
	if s.uid and g_VR and g_VR.menus and g_VR.menus[s.uid] then return true end
	if s.nativeOpen and isfunction(s.nativeOpen) then return s.nativeOpen() end
	return s.open == true
end

--- Close a named session (panel + module slot optional keep).
-- @param name string
-- @param opts { keepModule=bool }
function VD.Close(name, opts)
	opts = opts or {}
	local s = sessions[name]
	if not s then return end

	if s.captureHook then
		hook.Remove("PostRender", s.captureHook)
		s.captureHook = nil
	end

	if s.uid and vrmod.panel2vr and vrmod.panel2vr.Close then
		pcall(vrmod.panel2vr.Close, s.uid)
	elseif s.uid and isfunction(VRUtilMenuClose) then
		pcall(VRUtilMenuClose, s.uid)
	end

	if IsValid(s.panel) and s.panel.SetPaintedManually then
		pcall(function() s.panel:SetPaintedManually(false) end)
	end

	if s.onClose then pcall(s.onClose, s) end

	if not opts.keepModule and s.moduleId and isfunction(VRMOD_VirtualDisplayDestroy) then
		pcall(VRMOD_VirtualDisplayDestroy, s.moduleId)
		s.moduleId = nil
	end

	s.open = false
	s.uid = nil
	s.panel = nil
	sessions[name] = s -- keep size / module if keepModule
	if not opts.keepModule then
		sessions[name] = nil
	end
	log("closed session %s", name)
end

function VD.CloseAll(opts)
	for name in pairs(sessions) do
		VD.Close(name, opts)
	end
end

local function placeOpts(place, width, height, scale)
	place = place or "hand"
	if place == "cinema" or place == "float" then
		return {
			place = place,
			width = width,
			height = height,
		}
	end
	-- hand / wrist: face user on secondary hand
	local wrist = (vrmod.GetSecondaryHand and vrmod.GetSecondaryHand()) or "left"
	local pos, ang, sc = Vector(5, 5.5, 7), Angle(0, -90, 55), scale or 0.02
	if isfunction(VRUtilHandMenuPose) then
		pos, ang, sc = VRUtilHandMenuPose(width, height, sc, Vector(5, 5.5, 7), Angle(0, -90, 55), wrist)
	end
	return {
		place = place,
		width = width,
		height = height,
		placeOverride = {
			attachment = true,
			pos = pos,
			ang = ang,
			scale = sc or scale or 0.02,
		},
	}
end

local function markMenuCube(uid, place)
	if not (g_VR and g_VR.menus and g_VR.menus[uid]) then return end
	local m = g_VR.menus[uid]
	m.dirty = true
	m.alwaysRedraw = true
	m.paintInterval = 0
	m.paintIntervalFocused = 0
	-- Do not persistOpen/keepAlive — fights close buttons / stacking
	m.persistOpen = false
	m.keepAlive = false
	m.cubeMenu = true
	m.virtualDisplay = true
	m.grabbable = true
	if place == "cinema" or place == "float" then
		m.attachment = false
		m.freeFloat = true
		m.attachHand = nil
	elseif place == "hand" or place == "wrist" or place == "popup" then
		m.attachment = true
		m.freeFloat = false
		m.attachHand = (vrmod.GetSecondaryHand and vrmod.GetSecondaryHand()) or "left"
	end
end

--- Present a reusable VR panel session.
-- @param name "launcher"|"pause"|string
-- @param opts table
--   mode = "native"|"vgui"|"capture"
--   place = "hand"|"cinema"|"float"|"wrist"
--   width, height
--   panel = Panel (vgui mode)
--   drawFn = function(w,h,focused) (native mode)
--   openFn = function() → bool  (delegate: open Cube hub etc.)
--   closeFn / onClose
--   uid = stable panel2vr uid
--   capture = bool (also tick module CaptureWindow)
--   keepWorldUnpaused = true (default)
function VD.Present(name, opts)
	opts = opts or {}
	if not (g_VR and g_VR.active) then
		log("Present(%s): VR not active", tostring(name))
		return nil
	end

	name = tostring(name or "default")
	local mode = opts.mode or (opts.panel and "vgui") or (opts.drawFn and "native") or (opts.openFn and "delegate") or "native"
	local role = (name == "launcher") and "launcher" or "pause"
	local dw, dh, dsc = defaultSize(role)
	local width = opts.width or dw
	local height = opts.height or dh
	-- Large surfaces default to free-float; small popups may still use hand
	local place = opts.place or ((name == "launcher" or name == "pause") and "float" or "hand")

	-- Close prior presentation of same name (keep module if resizing)
	if sessions[name] and sessions[name].open then
		VD.Close(name, { keepModule = true })
	end

	local s = sessions[name] or {}
	s.name = name
	s.mode = mode
	s.width = width
	s.height = height
	s.place = place
	s.onClose = opts.onClose or opts.closeFn
	s.open = true

	-- Module virtual monitor (real GPU surface when GL ready)
	local mid, minfo = VD.EnsureModuleDisplay(name, width, height)
	s.moduleId = mid
	s.moduleInfo = minfo

	if opts.keepWorldUnpaused ~= false and vrmod.VRUnpauseWorld then
		pcall(vrmod.VRUnpauseWorld)
	end

	-- ── Delegate: external open (Cube hub) still counts as VirtualDisplay session
	if mode == "delegate" and isfunction(opts.openFn) then
		local ok = opts.openFn(s)
		s.nativeOpen = opts.isOpenFn
		s.uid = opts.uid -- may be filled by openFn
		sessions[name] = s
		log("Present(%s) delegate moduleId=%s", name, tostring(mid))
		return s
	end

	-- ── Native draw surface
	if mode == "native" and isfunction(opts.drawFn) then
		if not (vrmod.panel2vr and vrmod.panel2vr.ManifestNative) then
			log("Present(%s): panel2vr.ManifestNative missing", name)
			return nil
		end
		local uid = opts.uid or ("vdisp_" .. name)
		local pOpts = placeOpts(place, width, height, dsc)
		pOpts.uid = uid
		local got = vrmod.panel2vr.ManifestNative(uid, width, height, opts.drawFn, pOpts)
		local boundUid = isstring(got) and got or uid
		s.uid = boundUid
		markMenuCube(boundUid, place)
		sessions[name] = s
		log("Present(%s) native %dx%d place=%s", name, width, height, place)
		return s
	end

	-- ── VGUI panel bind
	if mode == "vgui" and IsValid(opts.panel) then
		if not (vrmod.panel2vr and vrmod.panel2vr.ManifestPanel) then
			log("Present(%s): panel2vr.ManifestPanel missing", name)
			return nil
		end
		local panel = opts.panel
		if panel.SetSize then pcall(function() panel:SetSize(width, height) end) end
		if panel.SetPos then pcall(function() panel:SetPos(0, 0) end) end
		if panel.SetVisible then panel:SetVisible(true) end
		if panel.SetMouseInputEnabled then panel:SetMouseInputEnabled(true) end
		if panel.SetKeyboardInputEnabled then panel:SetKeyboardInputEnabled(false) end

		local pOpts = placeOpts(place, width, height, dsc)
		pOpts.kind = opts.kind or name
		pOpts.hint = opts.hint or "virtualdisplay"
		pOpts.uid = opts.uid or ("vdisp_" .. name)
		pOpts.width = width
		pOpts.height = height

		local uid = vrmod.panel2vr.ManifestPanel(panel, pOpts)
		if not uid then
			log("Present(%s): ManifestPanel failed", name)
			return nil
		end
		s.uid = uid
		s.panel = panel
		markMenuCube(uid, place)
		sessions[name] = s
		log("Present(%s) vgui %dx%d", name, width, height)
		return s
	end

	-- ── Capture: module blits desktop window each frame; optional panel overlay
	if mode == "capture" or opts.capture then
		if mid and isfunction(VRMOD_VirtualDisplayCaptureWindow) then
			local hookName = "vrmod_vdisp_capture_" .. name
			s.captureHook = hookName
			hook.Add("PostRender", hookName, function()
				if not (g_VR and g_VR.active) then return end
				local ss = sessions[name]
				if not ss or not ss.moduleId then return end
				pcall(VRMOD_VirtualDisplayCaptureWindow, ss.moduleId)
				-- Keep VR panel dirty so laser UI stays live when we have VGUI overlay
				if ss.uid and g_VR.menus and g_VR.menus[ss.uid] then
					g_VR.menus[ss.uid].dirty = true
				end
			end)
			log("Present(%s) capture armed moduleId=%s", name, tostring(mid))
		else
			log("Present(%s) capture: module surface unavailable (Lua-only session)", name)
		end

		if IsValid(opts.panel) then
			opts.mode = "vgui"
			opts.capture = nil
			-- recursive present with vgui + already armed capture via session
			local prev = sessions[name]
			sessions[name] = s
			local r = VD.Present(name, {
				mode = "vgui",
				panel = opts.panel,
				place = place,
				width = width,
				height = height,
				uid = opts.uid,
				kind = opts.kind,
				onClose = function()
					if s.captureHook then
						hook.Remove("PostRender", s.captureHook)
					end
					if opts.onClose then opts.onClose() end
				end,
			})
			if r and prev and prev.moduleId then
				r.moduleId = prev.moduleId or r.moduleId
			end
			if r and s.captureHook then
				r.captureHook = s.captureHook
			end
			return r
		end

		sessions[name] = s
		return s
	end

	log("Present(%s): no mode payload (need drawFn, panel, or openFn)", name)
	sessions[name] = s
	return s
end

--- Map laser UV (0–1) into virtual display pixels.
function VD.MapPointer(name, u, v)
	local s = sessions[name]
	if not s then return nil, nil end
	local w, h = s.width or 1, s.height or 1
	local x = math.floor(math.Clamp(u or 0, 0, 1) * (w - 1) + 0.5)
	local y = math.floor(math.Clamp(v or 0, 0, 1) * (h - 1) + 0.5)
	return x, y
end

--- Launcher / menu-first helper: present VGUI or fall back to hub delegate.
function VD.PresentLauncher(opts)
	opts = opts or {}
	opts.place = opts.place or "float"
	if IsValid(opts.panel) then
		return VD.Present("launcher", {
			mode = opts.capture and "capture" or "vgui",
			panel = opts.panel,
			place = opts.place,
			width = opts.width,
			height = opts.height,
			uid = opts.uid or "vdisp_launcher",
			kind = "mainmenu",
			capture = opts.capture,
		})
	end
	if opts.drawFn then
		return VD.Present("launcher", {
			mode = "native",
			drawFn = opts.drawFn,
			place = opts.place,
			width = opts.width,
			height = opts.height,
			uid = opts.uid or "vdisp_launcher",
		})
	end
	-- Default: Cube hub as launcher surface (hub itself chooses wrist dock)
	return VD.Present("launcher", {
		mode = "delegate",
		openFn = function()
			if vrmod.VRHub_Open then
				vrmod.VRHub_Open()
				return true
			end
			return false
		end,
		isOpenFn = function()
			return vrmod.VRHub_IsOpen and vrmod.VRHub_IsOpen()
		end,
		uid = "vr_hub",
	})
end

--- In-game pause helper: Cube hub via same session machinery (never GameUI).
function VD.PresentPause(opts)
	opts = opts or {}
	return VD.Present("pause", {
		mode = "delegate",
		openFn = function()
			if vrmod.VRHub_Open then
				vrmod.VRHub_Open()
				return true
			elseif vrmod.VRHub_OpenWhenReady then
				vrmod.VRHub_OpenWhenReady()
				return true
			end
			return false
		end,
		isOpenFn = function()
			return vrmod.VRHub_IsOpen and vrmod.VRHub_IsOpen()
		end,
		uid = "vr_hub",
		onClose = opts.onClose,
	})
end

function VD.Status()
	local rows = {}
	for name, s in pairs(sessions) do
		rows[#rows + 1] = {
			name = name,
			mode = s.mode,
			open = s.open,
			uid = s.uid,
			moduleId = s.moduleId,
			w = s.width,
			h = s.height,
		}
	end
	return rows
end

hook.Add("VRMod_Exit", "vrmod_virtual_display_exit", function()
	VD.CloseAll()
end)

concommand.Add("vrmod_vdisplay_status", function()
	print("[gVRMod] VirtualDisplay moduleSupported=" .. tostring(VD.IsModuleSupported()))
	for _, r in ipairs(VD.Status()) do
		print(string.format("  %s mode=%s open=%s uid=%s module=%s %sx%s",
			r.name, tostring(r.mode), tostring(r.open), tostring(r.uid),
			tostring(r.moduleId), tostring(r.w), tostring(r.h)))
	end
	if not next(sessions) then print("  (no sessions)") end
end)

concommand.Add("vrmod_vdisplay_capture", function(_, _, args)
	local name = args[1] or "pause"
	local s = sessions[name]
	if not s or not s.moduleId then
		-- ensure display
		local id = VD.EnsureModuleDisplay(name, 1280, 720)
		if not id then
			print("[gVRMod] no module display")
			return
		end
		sessions[name] = sessions[name] or { name = name, moduleId = id, width = 1280, height = 720 }
		s = sessions[name]
		s.moduleId = id
	end
	if not isfunction(VRMOD_VirtualDisplayCaptureWindow) then
		print("[gVRMod] CaptureWindow not in module")
		return
	end
	local ok, err = VRMOD_VirtualDisplayCaptureWindow(s.moduleId)
	print("[gVRMod] CaptureWindow", ok, err or "")
	local info = VRMOD_VirtualDisplayGetInfo and VRMOD_VirtualDisplayGetInfo(s.moduleId)
	if info then
		print(string.format("  id=%s %sx%s tex=%s hasCapture=%s",
			tostring(info.id), tostring(info.width), tostring(info.height),
			tostring(info.glTexture), tostring(info.hasCapture)))
	end
end)
