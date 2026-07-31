if SERVER then return end
-- =============================================================================
-- vrmod.panel2vr — Real-time Derma/VGUI panel → VR surface framework
--
-- Law (Cube Experience):
--   Desktop / non-VR  → Derma / VGUI / spawnmenu as flat 2D panels
--   In VR             → intercept MakePopup / known shells and MANIFEST them
--                       as world/hand 3D surfaces (laser + trigger)
--
-- Name: panel2vr (not "web") — Source VGUI/Derma, not browser UI.
--
-- GMod anchors (wiki.facepunch.com):
--   Panel:SetPaintedManually(true) + Panel:PaintManual() into an RT
--   VRUtilMenuOpen → cam.Start3D2D + laser ray → gui.InternalMouse*
--   GM:OnSpawnMenuOpen / OnContextMenuOpen for sandbox shells
--   DHTML still paints via PaintManual (CEF); prefer native adapters when registered
-- =============================================================================

vrmod = vrmod or {}
vrmod.panel2vr = vrmod.panel2vr or {}

local W = vrmod.panel2vr

-- Glorious Crimson Cube palette (shared with native surfaces)
W.Theme = {
	bg = Color(18, 8, 12, 230),
	panel = Color(36, 12, 18, 240),
	crimson = Color(196, 30, 58, 255),
	crimsonDim = Color(120, 20, 40, 220),
	glass = Color(40, 10, 18, 180),
	text = Color(255, 236, 240, 255),
	muted = Color(200, 160, 170, 220),
	hover = Color(255, 60, 90, 255),
	ok = Color(80, 220, 140, 255),
}

-- Placement presets (HL:A-inspired)
-- attachment: true = local to left hand, false = world origin relative
W.Place = {
	-- Left hand — same family as quickmenu / heightmenu (NOT world-float)
	-- scale = base; global vrmod_ui_scale applied at draw time in cl_ui
	wrist = {
		attachment = true,
		pos = Vector(6, 4, 8),
		ang = Angle(0, -90, 55),
		scale = 0.035,
	},
	-- Alias used by MakePopup intercept for settings / generic derma
	popup = {
		attachment = true,
		pos = Vector(6, 4, 8),
		ang = Angle(0, -90, 55),
		scale = 0.035,
	},
	-- Floating mid-air in front of HMD (spawn/context workbench only)
	float = {
		attachment = false,
		pos = nil, -- computed
		ang = nil,
		scale = 0.022,
	},
	-- Large workbench (spawn menu)
	workbench = {
		attachment = false,
		pos = nil,
		ang = nil,
		scale = 0.018,
	},
}

-- Known class / name → prefer native VR adapter instead of raw panel paint
W.NativeAdapters = W.NativeAdapters or {}

-- Bound surfaces: panel instance → uid
local panelUids = setmetatable({}, { __mode = "k" })
local bound = {} -- uid → { panel, kind, place }
local seq = 0
local hooksInstalled = false
local origMakePopup = nil

local MAX_RT = 1024 -- Linux/ToGL-friendly RT dim for UI surfaces
local MIN_RT = 128

local function log(fmt, ...)
	if vrmod.logger then
		vrmod.logger.Info("[panel2vr] " .. fmt, ...)
	else
		print("[panel2vr] " .. string.format(fmt, ...))
	end
end

function W.IsVR()
	return g_VR and g_VR.active and g_VR.threePoints
end

function W.RegisterNative(key, openFn)
	-- key: panel class name, GetName(), or semantic "settings" / "spawnmenu"
	W.NativeAdapters[string.lower(key)] = openFn
end

local function uidFor(panel, hint)
	if IsValid(panel) and panelUids[panel] then return panelUids[panel] end
	seq = seq + 1
	local name = hint or (IsValid(panel) and panel:GetName()) or "surface"
	name = tostring(name):lower():gsub("[^%w]", "")
	if name == "" then name = "surface" end
	local uid = "p2v_" .. name .. "_" .. seq
	if IsValid(panel) then panelUids[panel] = uid end
	return uid
end

--- World placement from HMD: panel floats in front, facing player
function W.ComputeFloatPose(distance, heightOffset)
	distance = distance or 28
	heightOffset = heightOffset or -4
	if not (g_VR and g_VR.tracking and g_VR.tracking.hmd) then
		return Vector(0, 0, 60), Angle(0, 0, 90)
	end
	local hmd = g_VR.tracking.hmd
	local yawOnly = Angle(0, hmd.ang.yaw, 0)
	local fwd = yawOnly:Forward()
	local pos = hmd.pos + fwd * distance + Vector(0, 0, heightOffset)
	-- 3D2D: ang.up is panel normal; face the player
	local ang = Angle(0, yawOnly.yaw + 180, 90)
	-- Convert to origin-relative if not attachment
	if g_VR.origin and g_VR.originAngle then
		pos, ang = WorldToLocal(pos, ang, g_VR.origin, g_VR.originAngle)
	end
	return pos, ang
end

function W.ResolvePlace(placeName, override)
	local base = table.Copy(W.Place[placeName or "popup"] or W.Place.popup)
	if override then
		for k, v in pairs(override) do
			base[k] = v
		end
	end
	if not base.attachment and (not base.pos or not base.ang) then
		local dist = (placeName == "workbench") and 36 or 28
		base.pos, base.ang = W.ComputeFloatPose(dist, (placeName == "workbench") and -6 or -4)
		base.attachment = false
	end
	return base
end

local function clampSize(w, h)
	w = math.Clamp(math.floor(tonumber(w) or 512), MIN_RT, MAX_RT)
	h = math.Clamp(math.floor(tonumber(h) or 512), MIN_RT, MAX_RT)
	-- Even dims
	w = math.floor(w / 2) * 2
	h = math.floor(h / 2) * 2
	return w, h
end

local function detectKind(panel)
	if not IsValid(panel) then return "panel" end
	local class = panel.ClassName or panel:GetClassName() or ""
	local name = panel:GetName() or ""
	class = string.lower(tostring(class))
	name = string.lower(tostring(name))
	if class:find("dhtml", 1, true) or class:find("html", 1, true) or name:find("html", 1, true) then
		return "html"
	end
	if panel == g_SpawnMenu or name:find("spawnmenu", 1, true) then return "spawnmenu" end
	if panel == g_ContextMenu or name:find("context", 1, true) then return "contextmenu" end
	return "panel"
end

local function tryNative(kind, panel, opts)
	local keys = {
		opts and opts.nativeKey,
		kind,
		IsValid(panel) and panel:GetName(),
		IsValid(panel) and (panel.ClassName or panel:GetClassName()),
	}
	for _, k in ipairs(keys) do
		if k and W.NativeAdapters[string.lower(tostring(k))] then
			return W.NativeAdapters[string.lower(tostring(k))](panel, opts)
		end
	end
	return false
end

--- Prepare oversized sandbox shells for VR (readable RT, not ScrW×ScrH)
local function preparePanelForVR(panel, kind)
	if not IsValid(panel) then return end
	if kind == "spawnmenu" or kind == "contextmenu" then
		-- Fit MAX_RT (1024): avoid cut-off workbench (workshop #349)
		local tw, th = 1024, 768
		if panel.SetSize then panel:SetSize(tw, th) end
		if panel.SetPos then panel:SetPos(0, 0) end
		if panel.InvalidateLayout then panel:InvalidateLayout(true) end
	end
end

--- Manifest a live VGUI/DHTML panel into a VR surface (real-time paint).
-- @return uid or nil
function W.ManifestPanel(panel, opts)
	opts = opts or {}
	if not W.IsVR() then return nil end
	if not IsValid(panel) then return nil end
	if not isfunction(VRUtilMenuOpen) then
		log("VRUtilMenuOpen missing — cl_ui not loaded?")
		return nil
	end

	local kind = opts.kind or detectKind(panel)
	-- VRMod settings Derma → Cube UI on left hand (removes Derma frame)
	if opts.kind ~= "panel" and IsValid(panel) and panel.GetTitle then
		local title = tostring(panel:GetTitle() or "")
		if title:find("VRMod", 1, true) and tryNative("settings", panel, opts) then
			if IsValid(panel) then panel:Remove() end
			return "native_settings"
		end
	end
	if opts.kind ~= "panel" and tryNative(kind, panel, opts) then
		log("native adapter handled %s", kind)
		return "native_" .. kind
	end

	preparePanelForVR(panel, kind)

	local uid = opts.uid or uidFor(panel, opts.hint or kind)
	-- Settings / generic derma → left HAND. Spawn/context stay workbench float.
	local placeName = opts.place
		or ((kind == "spawnmenu" or kind == "contextmenu") and "workbench")
		or "popup"
	local place = W.ResolvePlace(placeName, opts.placeOverride)

	local pw, ph = panel:GetSize()
	if not pw or pw < 32 then pw = 512 end
	if not ph or ph < 32 then ph = 512 end
	-- Settings frame is small (420x505) — keep readable RT
	if kind == "settings" then
		pw, ph = math.max(pw, 420), math.max(ph, 505)
	end
	local w, h = clampSize(opts.width or pw, opts.height or ph)

	panel:SetPaintedManually(true)
	if panel.SetMouseInputEnabled then panel:SetMouseInputEnabled(true) end

	VRUtilMenuOpen(uid, w, h, panel, place.attachment, place.pos, place.ang, place.scale, true, function()
		if IsValid(panel) then
			panel:SetPaintedManually(false)
		end
		bound[uid] = nil
		if panelUids[panel] == uid then panelUids[panel] = nil end
		if opts.onClose then opts.onClose(panel) end
	end)

	-- Keep hand scale (cl_ui must not crush attached menus)
	if g_VR.menus and g_VR.menus[uid] then
		g_VR.menus[uid].scale = place.scale
		g_VR.menus[uid].cubeMenu = place.attachment and true or nil
		g_VR.menus[uid].attachment = place.attachment
	end

	bound[uid] = {
		panel = panel,
		kind = kind,
		place = placeName,
		html = (kind == "html"),
		alwaysPaint = (kind == "settings" or kind == "html" or kind == "spawnmenu" or kind == "contextmenu"),
	}

	if isfunction(VRUtilMenuRenderPanel) then
		VRUtilMenuRenderPanel(uid)
	end

	log("manifest %s uid=%s %dx%d place=%s attach=%s", kind, uid, w, h, placeName, tostring(place.attachment))
	return uid
end

--- Pure native VR surface (no VGUI panel) — drawFn paints 2D into the RT each refresh.
function W.ManifestNative(uid, width, height, drawFn, opts)
	opts = opts or {}
	if not W.IsVR() then return nil end
	if not isfunction(VRUtilMenuOpen) then return nil end

	uid = uid or ("native_" .. seq)
	-- Default wrist (left hand). Callers must opt into float explicitly.
	local placeName = opts.place or "wrist"
	local place = W.ResolvePlace(placeName, opts.placeOverride)
	local w, h = clampSize(width or 512, height or 512)
	local dirty = true

	VRUtilMenuOpen(uid, w, h, nil, place.attachment, place.pos, place.ang, place.scale, true, function()
		hook.Remove("PreRender", "panel2vr_native_" .. uid)
		bound[uid] = nil
		if opts.onClose then opts.onClose() end
	end)

	if g_VR.menus and g_VR.menus[uid] then
		g_VR.menus[uid].scale = place.scale or 0.035
		g_VR.menus[uid].cubeMenu = true
		g_VR.menus[uid].attachment = place.attachment and true or false
	end

	hook.Add("PreRender", "panel2vr_native_" .. uid, function()
		if not VRUtilIsMenuOpen or not VRUtilIsMenuOpen(uid) then
			hook.Remove("PreRender", "panel2vr_native_" .. uid)
			return
		end
		local m = g_VR.menus and g_VR.menus[uid]
		if m and place.attachment then
			m.scale = place.scale or 0.035
			m.cubeMenu = true
			m.attachment = true
		end
		if not dirty and not opts.alwaysRedraw then return end
		dirty = false
		VRUtilMenuRenderStart(uid)
		if drawFn then drawFn(w, h, g_VR.menuFocus == uid) end
		VRUtilMenuRenderEnd()
	end)

	-- Immediate first paint so RT is never blank
	if drawFn and isfunction(VRUtilMenuRenderStart) then
		VRUtilMenuRenderStart(uid)
		drawFn(w, h, false)
		VRUtilMenuRenderEnd()
	end

	bound[uid] = { kind = "native", place = placeName, dirty = function() dirty = true end }
	dirty = true
	return uid, function() dirty = true end
end

function W.Close(uid)
	if uid and isfunction(VRUtilMenuClose) then
		VRUtilMenuClose(uid)
	end
end

function W.CloseAll()
	for uid in pairs(bound) do
		W.Close(uid)
	end
	if isfunction(VRUtilMenuClose) then
		-- also clear anything opened outside registry
	end
end

function W.IsBound(panel)
	return IsValid(panel) and panelUids[panel] ~= nil
end

function W.GetBound()
	return bound
end

-- ─── Intercept: MakePopup (any Derma/DHTML that wants the "web" screen) ─────

local IGNORE_NAMES = {
	-- engine / steam overlay noise
	dmenuoption = true, -- leaf items; parent DMenu is enough sometimes
}

local function shouldIntercept(panel)
	if not W.IsVR() then return false end
	if not IsValid(panel) then return false end
	if W.IsBound(panel) then return false end
	-- Skip if already painted manually by someone else intentionally without us
	local name = string.lower(panel:GetName() or "")
	if IGNORE_NAMES[name] then return false end
	-- Skip tiny tooltips
	local w, h = panel:GetSize()
	if w and h and w < 40 and h < 40 then return false end
	return true
end

function W.InstallHooks()
	if hooksInstalled then return end
	hooksInstalled = true

	local meta = getmetatable(vgui.GetWorldPanel())
	if not meta or not meta.MakePopup then
		log("WorldPanel MakePopup meta missing")
		return
	end
	if not origMakePopup then
		origMakePopup = meta.MakePopup
	end

	meta.MakePopup = function(panel, ...)
		origMakePopup(panel, ...)
		if not shouldIntercept(panel) then return end
		-- Defer one frame so layout finishes (sandbox menus size after Open)
		timer.Simple(0, function()
			if not IsValid(panel) or not shouldIntercept(panel) then return end
			W.ManifestPanel(panel, { place = "popup" })
		end)
	end

	-- Spawn / context: ensure open shells are resized + manifested even if
	-- they already called MakePopup before VR, or use non-standard popup paths.
	hook.Add("OnSpawnMenuOpen", "panel2vr_spawn", function()
		if not W.IsVR() then return end
		timer.Simple(0, function()
			if IsValid(g_SpawnMenu) then
				W.ManifestPanel(g_SpawnMenu, {
					kind = "spawnmenu",
					place = "workbench",
					hint = "spawnmenu",
				})
			end
		end)
	end)

	hook.Add("OnSpawnMenuClose", "panel2vr_spawn", function()
		if IsValid(g_SpawnMenu) and panelUids[g_SpawnMenu] then
			W.Close(panelUids[g_SpawnMenu])
		end
	end)

	hook.Add("OnContextMenuOpen", "panel2vr_ctx", function()
		if not W.IsVR() then return end
		timer.Simple(0, function()
			if IsValid(g_ContextMenu) then
				W.ManifestPanel(g_ContextMenu, {
					kind = "contextmenu",
					place = "workbench",
					hint = "contextmenu",
				})
			end
		end)
	end)

	hook.Add("OnContextMenuClose", "panel2vr_ctx", function()
		if IsValid(g_ContextMenu) and panelUids[g_ContextMenu] then
			W.Close(panelUids[g_ContextMenu])
		end
	end)

	-- Continuous re-paint: settings always, others when focused / alwaysPaint
	hook.Add("Think", "panel2vr_repaint", function()
		if not W.IsVR() then return end
		for uid, info in pairs(bound) do
			if info.panel and IsValid(info.panel) and isfunction(VRUtilMenuRenderPanel) then
				if info.alwaysPaint or info.html or g_VR.menuFocus == uid then
					VRUtilMenuRenderPanel(uid)
				end
				-- Hold hand scale for attached surfaces
				local m = g_VR.menus and g_VR.menus[uid]
				if m and m.cubeMenu and m.scale and m.scale < 0.03 then
					m.scale = 0.035
				end
			elseif info.panel and not IsValid(info.panel) then
				W.Close(uid)
			end
		end
	end)

	hook.Add("VRMod_Exit", "panel2vr_cleanup", function()
		W.CloseAll()
	end)

	log("hooks installed (MakePopup + spawn/context + repaint)")
end

-- Public: same settings catalog in VR (hand) and desktop (Derma)
function W.OpenSettings()
	if isfunction(vrmod.Settings_Open) then
		return vrmod.Settings_Open()
	end
	if W.IsVR() and isfunction(vrmod.CubeSettings_Open) then
		vrmod.CubeSettings_Open()
		return nil
	end
	if isfunction(VRUtilOpenMenu) then
		return VRUtilOpenMenu()
	end
	return nil
end

-- Install after UI subsystem is ready
hook.Add("InitPostEntity", "panel2vr_install", function()
	timer.Simple(0, function() W.InstallHooks() end)
end)

-- Also on VR start (in case world panel meta was reset)
hook.Add("VRMod_Start", "panel2vr_install", function()
	W.InstallHooks()
end)

concommand.Add("vrmod_panel2vr_status", function()
	print("[panel2vr] VR=", tostring(W.IsVR()), "hooks=", tostring(hooksInstalled))
	for uid, info in pairs(bound) do
		print(" ", uid, info.kind, info.place, IsValid(info.panel) and info.panel:GetName() or "-")
	end
end)

concommand.Add("vrmod_panel2vr_closeall", function()
	W.CloseAll()
end)

-- Deprecated aliases (old web2vr name — Derma/VGUI is not web)
vrmod.web2vr = vrmod.panel2vr
concommand.Add("vrmod_web2vr_status", function()
	RunConsoleCommand("vrmod_panel2vr_status")
end)
concommand.Add("vrmod_web2vr_closeall", function()
	RunConsoleCommand("vrmod_panel2vr_closeall")
end)
