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
	-- Floating mid-air in front of HMD (opt-in only)
	float = {
		attachment = false,
		pos = nil, -- computed
		ang = nil,
		scale = 0.022,
	},
	-- Spawn / context: FOLLOW LEFT HAND (same SoT as quickmenu / settings)
	-- Not world-float — edge-on strip was broken workbench pose.
	workbench = {
		attachment = true,
		pos = Vector(8, 5, 12),
		ang = Angle(0, -90, 55),
		scale = 0.022,
	},
	-- Alias: explicit hand large shell
	hand = {
		attachment = true,
		pos = Vector(8, 5, 12),
		ang = Angle(0, -90, 55),
		scale = 0.022,
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
-- Last free-float pose per shell kind (origin-relative) so reopen keeps placement
local shellFloatPose = {} -- kind → { pos, ang, scale }

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

-- Stable uids so re-open replaces the same VR surface (no stacked ghosts)
local STABLE_UID = {
	spawnmenu = "p2v_spawnmenu",
	contextmenu = "p2v_contextmenu",
}

local function uidFor(panel, hint, kind)
	if kind and STABLE_UID[kind] then
		local uid = STABLE_UID[kind]
		if IsValid(panel) then panelUids[panel] = uid end
		return uid
	end
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
	-- Hand shells: convert center → top-left once (same as quickmenu). Never re-run every Think.
	if base.attachment and (placeName == "hand" or placeName == "workbench" or placeName == "popup" or placeName == "wrist") then
		local sc = base.scale or 0.022
		local center = base.pos or Vector(6, 4, 8)
		local pang = base.ang or Angle(0, -90, 55)
		local pw = (placeName == "hand" or placeName == "workbench") and 1024 or 512
		local ph = (placeName == "hand" or placeName == "workbench") and 768 or 512
		if isfunction(VRUtilHandMenuPose) then
			local hp, ha, hs = VRUtilHandMenuPose(pw, ph, sc, center, pang)
			if hp then base.pos = hp end
			if ha then base.ang = ha end
			if hs then base.scale = hs end
		else
			base.pos = center
			base.ang = pang
			base.scale = sc
		end
		base.attachment = true
	elseif not base.attachment and (not base.pos or not base.ang) then
		base.pos, base.ang = W.ComputeFloatPose(28, -4)
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
	-- ContentIcon right-click menus
	if class == "dmenu" or class:find("dmenu", 1, true) or name == "dmenu" then
		return "dmenu"
	end
	return "panel"
end

--- Parent a DMenu under the focused spawn/context shell so it paints into the same RT.
--- Separate MakePopup surfaces were unusable for spawn right-click.
local function attachDMenuToShell(panel)
	if not IsValid(panel) then return false end
	local host, mx, my = nil, g_VR.menuCursorX or 8, g_VR.menuCursorY or 8
	if g_VR.menuFocus == STABLE_UID.spawnmenu and IsValid(g_SpawnMenu) then
		host = g_SpawnMenu
	elseif g_VR.menuFocus == STABLE_UID.contextmenu and IsValid(g_ContextMenu) then
		host = g_ContextMenu
	elseif IsValid(g_SpawnMenu) and g_SpawnMenu:IsVisible() and bound[STABLE_UID.spawnmenu] then
		host = g_SpawnMenu
	elseif IsValid(g_ContextMenu) and g_ContextMenu:IsVisible() and bound[STABLE_UID.contextmenu] then
		host = g_ContextMenu
	end
	if not IsValid(host) then return false end

	local hw = host:GetWide() or 1024
	local hh = host:GetTall() or 768
	local pw = panel:GetWide() or 160
	local ph = panel:GetTall() or 120
	mx = math.Clamp(math.floor(mx), 0, math.max(0, hw - pw - 4))
	my = math.Clamp(math.floor(my), 0, math.max(0, hh - ph - 4))

	if panel.SetParent then panel:SetParent(host) end
	if panel.SetPos then panel:SetPos(mx, my) end
	if panel.SetPaintedManually then panel:SetPaintedManually(true) end
	if panel.SetVisible then panel:SetVisible(true) end
	if panel.SetMouseInputEnabled then panel:SetMouseInputEnabled(true) end
	if panel.SetKeyboardInputEnabled then panel:SetKeyboardInputEnabled(false) end
	if panel.MakePopup then
		-- already called by caller; ensure focus stays usable for clicks
	end
	if panel.MoveToFront then panel:MoveToFront() end
	-- Force host RT refresh so menu appears this frame
	local uid = STABLE_UID.spawnmenu
	if host == g_ContextMenu then uid = STABLE_UID.contextmenu end
	if isfunction(VRUtilMenuRenderPanel) then
		VRUtilMenuRenderPanel(uid)
	end
	log("dmenu attached to shell uid=%s at %s,%s", uid, tostring(mx), tostring(my))
	return true
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

--- Walk all DHorizontalDividers — desktop cookies misplace the props tree (left)
--- and crush Tools (right) on a 1024 VR surface.
local function fitSandboxLayout(panel, tw, th)
	if not IsValid(panel) then return end
	tw = math.max(tonumber(tw) or 1024, 640)
	th = math.max(tonumber(th) or 768, 480)

	local function walk(p, depth)
		if not IsValid(p) or (depth or 0) > 24 then return end
		local cls = string.lower(tostring(p.ClassName or p:GetClassName() or ""))
		local name = string.lower(tostring(p:GetName() or ""))

		-- Root: Creation | Tools
		if p == panel.HorizontalDivider or (cls:find("dhorizontaldivider", 1, true) and depth <= 1) then
			if p.SetRightMin then p:SetRightMin(math.floor(tw * 0.30)) end
			if p.SetLeftMin then p:SetLeftMin(math.floor(tw * 0.40)) end
			if p.SetLeftWidth then p:SetLeftWidth(math.floor(tw * 0.62)) end
			if p.SetDividerWidth then p:SetDividerWidth(4) end
		end

		-- Inner content: ContentSidebar (tree) | icon grid
		-- Cookie SpawnMenuCreationMenuDiv often leaves tree off-frame / wrong width
		if cls:find("dhorizontaldivider", 1, true) and depth >= 2 then
			if p.SetLeftMin then p:SetLeftMin(140) end
			if p.SetRightMin then p:SetRightMin(280) end
			if p.SetLeftWidth then p:SetLeftWidth(200) end -- tree column
			if p.SetDividerWidth then p:SetDividerWidth(4) end
		end

		-- DTree / ContentSidebar: translucent Cube glass, not solid grey brick
		if cls:find("dtree", 1, true) or name:find("contentsidebar", 1, true) then
			if p.SetBackgroundColor then
				p:SetBackgroundColor(Color(22, 10, 16, 160))
			end
			if p.SetPaintBackground then p:SetPaintBackground(true) end
		end

		-- Desktop-only chrome that sits wrong on hand panel
		if name:find("tooltoggle", 1, true) or (p.GetImage and tostring(p:GetImage() or ""):find("spawnmenu_toggle", 1, true)) then
			if p.SetVisible then p:SetVisible(false) end
		end

		for _, ch in ipairs(p:GetChildren() or {}) do
			walk(ch, (depth or 0) + 1)
		end
	end

	walk(panel, 0)
end

--- Prepare oversized sandbox shells for VR (readable RT, not ScrW×ScrH)
local function preparePanelForVR(panel, kind)
	if not IsValid(panel) then return end
	if kind == "spawnmenu" or kind == "contextmenu" then
		local tw, th = 1024, 768
		if panel.SetSize then panel:SetSize(tw, th) end
		if panel.SetPos then panel:SetPos(0, 0) end
		-- Kill desktop border emptiness (spawnmenu_border uses ScrW)
		if panel.DockPadding then panel:DockPadding(0, 0, 0, 0) end
		fitSandboxLayout(panel, tw, th)
		if panel.InvalidateLayout then panel:InvalidateLayout(true) end
		timer.Simple(0, function()
			if IsValid(panel) then fitSandboxLayout(panel, tw, th) end
		end)
		timer.Simple(0.05, function()
			if IsValid(panel) then fitSandboxLayout(panel, tw, th) end
		end)
		if vrmod.cube and W.IsVR() then
			if kind == "spawnmenu" and vrmod.cube.ThemeSpawnMenu then
				vrmod.cube.ThemeSpawnMenu(panel)
			elseif kind == "contextmenu" and vrmod.cube.ThemeContextMenu then
				vrmod.cube.ThemeContextMenu(panel)
			elseif vrmod.cube.ApplyDermaSkin then
				vrmod.cube.ApplyDermaSkin(panel)
			end
		end
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

	local uid = opts.uid or uidFor(panel, opts.hint or kind, kind)
	-- Drop any other bound shells of same kind (prevents multi-stack)
	for buid, info in pairs(bound) do
		if info.kind == kind and buid ~= uid then
			W.Close(buid)
		end
	end
	local placeName = opts.place
		or ((kind == "spawnmenu" or kind == "contextmenu") and "hand")
		or "popup"
	if placeName == "workbench" then placeName = "hand" end
	local place = W.ResolvePlace(placeName, opts.placeOverride)

	local pw, ph = panel:GetSize()
	if not pw or pw < 32 then pw = 512 end
	if not ph or ph < 32 then ph = 512 end
	if kind == "settings" then
		pw, ph = math.max(pw, 420), math.max(ph, 505)
	end
	if kind == "spawnmenu" or kind == "contextmenu" then
		pw, ph = 1024, 768
	end
	local w, h = clampSize(opts.width or pw, opts.height or ph)

	if panel.SetVisible then panel:SetVisible(true) end
	if panel.SetMouseInputEnabled then panel:SetMouseInputEnabled(true) end
	if panel.SetKeyboardInputEnabled then panel:SetKeyboardInputEnabled(false) end
	panel:SetPaintedManually(true)

	local isShell = (kind == "spawnmenu" or kind == "contextmenu")
	-- Restore free-float placement: session cache, then disk layout (panel_layouts.json)
	local saved = isShell and shellFloatPose[kind] or nil
	if not saved and isfunction(vrmod.GetMenuLayout) then
		local lay = vrmod.GetMenuLayout(uid)
		if lay and lay.freeFloat and lay.pos and lay.ang then
			saved = {
				pos = Vector(lay.pos.x or lay.pos[1], lay.pos.y or lay.pos[2], lay.pos.z or lay.pos[3]),
				ang = Angle(lay.ang.p or lay.ang[1], lay.ang.y or lay.ang[2], lay.ang.r or lay.ang[3]),
				scale = lay.scale,
			}
			if isShell then shellFloatPose[kind] = saved end
		elseif lay and lay.scale then
			place.scale = lay.scale
		end
	end
	local useFloat = saved and saved.pos and saved.ang
	if useFloat then
		place.attachment = false
		place.pos = saved.pos
		place.ang = saved.ang
		if saved.scale then place.scale = saved.scale end
	end

	-- Already bound same surface + same size: do NOT VRUtilMenuClose/reopen (pose jump)
	local existing = bound[uid]
	local already = existing and existing.panel == panel
		and g_VR.menus and g_VR.menus[uid]
		and g_VR.menus[uid].width == w and g_VR.menus[uid].height == h
	if already then
		local m = g_VR.menus[uid]
		-- Never reset free-float; only re-pin hand if still attached
		if m.freeFloat or m.grabHand then
			-- keep parked world pose
		elseif place.attachment then
			m.attachment = true
			m.freeFloat = false
			m.pos = place.pos
			m.ang = place.ang
			m.scale = place.scale or m.scale
			m.baseScale = m.scale
			m._lastAssignedScale = m.scale
		end
		m.cubeMenu = true
		m.grabbable = true
		m.persistOpen = isShell
		if isfunction(VRUtilMenuRenderPanel) then VRUtilMenuRenderPanel(uid) end
		log("manifest keep %s uid=%s (no reopen)", kind, uid)
		return uid
	end

	VRUtilMenuOpen(uid, w, h, panel, place.attachment, place.pos, place.ang, place.scale, true, function()
		-- Snapshot free-float before drop so reopen restores placement
		local m = g_VR and g_VR.menus and g_VR.menus[uid]
		if m and (m.freeFloat or not m.attachment) and m.pos and m.ang and isShell then
			shellFloatPose[kind] = {
				pos = Vector(m.pos),
				ang = Angle(m.ang.p, m.ang.y, m.ang.r),
				scale = m.baseScale or m.scale,
			}
		end
		if m and isfunction(vrmod.SaveMenuLayout) then
			vrmod.SaveMenuLayout(uid)
		end
		if IsValid(panel) then
			panel:SetPaintedManually(false)
		end
		bound[uid] = nil
		if panelUids[panel] == uid then panelUids[panel] = nil end
		if opts.onClose then opts.onClose(panel) end
	end)

	if g_VR.menus and g_VR.menus[uid] then
		local m = g_VR.menus[uid]
		local disk = isfunction(vrmod.GetMenuLayout) and vrmod.GetMenuLayout(uid) or nil
		-- Prefer layout already applied by VRUtilMenuOpen; only fill defaults if missing
		if not (disk and disk.scale) then
			local sc = place.scale or m.scale or 0.022
			if isShell then sc = math.max(sc, 0.02) end
			m.scale = sc
			m.baseScale = sc
			m._lastAssignedScale = sc
		end
		m.cubeMenu = true
		m.grabbable = true
		m.resizable = true
		-- Stay alive while QM / other menus open (IsVisible flicker must not kill shell)
		m.persistOpen = isShell
		m.keepAlive = isShell
		m.allowHiddenPanel = isShell
		if useFloat or m.freeFloat then
			m.attachment = false
			m.freeFloat = true
			if useFloat then
				m.pos = place.pos
				m.ang = place.ang
				if place.scale and not (disk and disk.scale) then
					m.scale = place.scale
					m.baseScale = place.scale
					m._lastAssignedScale = place.scale
				end
			end
		else
			m.attachment = place.attachment and true or false
			m.freeFloat = not m.attachment
			m.pos = place.pos
			m.ang = place.ang
		end
	end

	bound[uid] = {
		panel = panel,
		kind = kind,
		place = placeName,
		html = (kind == "html"),
		alwaysPaint = (kind == "settings" or kind == "html" or kind == "spawnmenu" or kind == "contextmenu"),
		handPos = place.pos,
		handAng = place.ang,
		handScale = place.scale,
		persistOpen = isShell,
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
		local m = g_VR.menus[uid]
		if not m.scaleLocked then
			local sc = place.scale or 0.035
			m.scale = sc
			m.baseScale = sc
			m._lastAssignedScale = sc
		end
		m.cubeMenu = true
		m.grabbable = true
		m.resizable = true
		if not m.freeFloat and not m.grabHand then
			m.attachment = place.attachment and true or false
		end
	end

	hook.Add("PreRender", "panel2vr_native_" .. uid, function()
		if not VRUtilIsMenuOpen or not VRUtilIsMenuOpen(uid) then
			hook.Remove("PreRender", "panel2vr_native_" .. uid)
			return
		end
		local m = g_VR.menus and g_VR.menus[uid]
		if m and place.attachment and not m.freeFloat and not m.grabHand then
			if not m.scaleLocked then
				m.scale = place.scale or 0.035
			end
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
		if not W.IsVR() then return end
		if not IsValid(panel) then return end
		local kind = detectKind(panel)
		-- Spawn/context: OpenSandboxShell / OnSpawn* own a single manifest — skip here
		if kind == "spawnmenu" or kind == "contextmenu" then return end
		-- Right-click menus must live ON the spawn RT (not a second broken surface)
		if kind == "dmenu" then
			timer.Simple(0, function()
				if not IsValid(panel) or not W.IsVR() then return end
				if not attachDMenuToShell(panel) then
					-- Fallback: free-float tiny popup if no shell open
					if W.IsBound(panel) then return end
					W.ManifestPanel(panel, {
						kind = "dmenu",
						place = "popup",
						hint = "dmenu",
						alwaysPaint = true,
					})
				end
			end)
			return
		end
		if not shouldIntercept(panel) then return end
		timer.Simple(0, function()
			if not IsValid(panel) or not W.IsVR() then return end
			if W.IsBound(panel) then return end
			W.ManifestPanel(panel, {
				kind = kind,
				place = "popup",
				hint = kind,
			})
		end)
	end

	-- Spawn: only if nothing bound yet (e.g. +menu without our OpenSandboxShell)
	hook.Add("OnSpawnMenuOpen", "panel2vr_spawn", function()
		if not W.IsVR() then return end
		timer.Simple(0, function()
			if not IsValid(g_SpawnMenu) or not W.IsVR() then return end
			if W.IsBound(g_SpawnMenu) or bound[STABLE_UID.spawnmenu] then return end
			if vrmod.cube and vrmod.cube.ThemeSpawnMenu then
				vrmod.cube.ThemeSpawnMenu(g_SpawnMenu)
			end
			W.ManifestPanel(g_SpawnMenu, {
				kind = "spawnmenu",
				place = "hand",
				hint = "spawnmenu",
				uid = STABLE_UID.spawnmenu,
			})
		end)
	end)

	hook.Add("OnSpawnMenuClose", "panel2vr_spawn", function()
		-- Always tear down VR surface on sandbox close
		W.Close(STABLE_UID.spawnmenu)
		if IsValid(g_SpawnMenu) and panelUids[g_SpawnMenu] then
			W.Close(panelUids[g_SpawnMenu])
			panelUids[g_SpawnMenu] = nil
		end
	end)

	hook.Add("OnContextMenuOpen", "panel2vr_ctx", function()
		if not W.IsVR() then return end
		timer.Simple(0, function()
			if not IsValid(g_ContextMenu) or not W.IsVR() then return end
			if W.IsBound(g_ContextMenu) or bound[STABLE_UID.contextmenu] then return end
			if vrmod.cube and vrmod.cube.ThemeContextMenu then
				vrmod.cube.ThemeContextMenu(g_ContextMenu)
			end
			W.ManifestPanel(g_ContextMenu, {
				kind = "contextmenu",
				place = "hand",
				hint = "contextmenu",
				uid = STABLE_UID.contextmenu,
			})
		end)
	end)

	hook.Add("OnContextMenuClose", "panel2vr_ctx", function()
		W.Close(STABLE_UID.contextmenu)
		if IsValid(g_ContextMenu) and panelUids[g_ContextMenu] then
			W.Close(panelUids[g_ContextMenu])
			panelUids[g_ContextMenu] = nil
		end
	end)

	-- Hold-open / layout bookkeeping (throttled — not every Think field rewrite)
	local keepAliveN = 0
	hook.Add("Think", "panel2vr_keepalive", function()
		if not W.IsVR() then return end
		keepAliveN = keepAliveN + 1
		local heavy = (keepAliveN % 15) == 0 -- ~4 Hz pose snapshot
		for uid, info in pairs(bound) do
			if info.panel and IsValid(info.panel) then
				if info.kind == "spawnmenu" or info.kind == "contextmenu" then
					if info.panel.SetVisible then info.panel:SetVisible(true) end
					if info.panel.SetPaintedManually then info.panel:SetPaintedManually(true) end
				end
				local m = g_VR.menus and g_VR.menus[uid]
				if m then
					if info.kind == "spawnmenu" or info.kind == "contextmenu" then
						m.cubeMenu = true
						m.grabbable = true
						m.resizable = true
						m.persistOpen = true
						m.keepAlive = true
						m.allowHiddenPanel = true
						m.paintInterval = 3 -- unfocused spawn RT cheaper than full rate
						if heavy and (m.freeFloat or not m.attachment) and m.pos and m.ang then
							shellFloatPose[info.kind] = {
								pos = Vector(m.pos),
								ang = Angle(m.ang.p, m.ang.y, m.ang.r),
								scale = m.baseScale or m.scale,
							}
						end
						if not m.freeFloat and not m.grabHand and not g_VR.menuResizeActive then
							m.attachment = true
						end
					elseif m.cubeMenu and not m.scaleLocked and m.scale and m.scale < 0.03 and m.attachment then
						m.scale = 0.035
						m.baseScale = 0.035
					end
				end
			elseif info.panel and not IsValid(info.panel) then
				W.Close(uid)
			end
		end
	end)

	-- RT paint once per stereo frame (shared both eyes).
	-- Focused / dirty / alwaysPaint → full rate; idle shells use paintInterval inside RenderPanel.
	hook.Add("VRMod_PreStereo", "panel2vr_repaint", function()
		if not W.IsVR() then return end
		if not isfunction(VRUtilMenuRenderPanel) then return end
		for uid, info in pairs(bound) do
			if info.panel and IsValid(info.panel) then
				local m = g_VR.menus and g_VR.menus[uid]
				if m then
					if info.alwaysPaint or info.html then
						m.paintInterval = 2
					end
					if g_VR.menuFocus == uid then
						m.dirty = true -- hover/selection needs every-frame while pointed
					end
				end
				VRUtilMenuRenderPanel(uid)
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

function W.IsShellOpen(which)
	local isCtx = (which == "context" or which == "contextmenu")
	local panel = isCtx and g_ContextMenu or g_SpawnMenu
	local uid = isCtx and STABLE_UID.contextmenu or STABLE_UID.spawnmenu
	if bound[uid] then return true end
	if IsValid(panel) and panel.IsVisible and panel:IsVisible() and W.IsBound(panel) then
		return true
	end
	return false
end

--- Hard close — one surface, no ghosts (X button / QM toggle only)
function W.CloseSandboxShell(which)
	local isCtx = (which == "context" or which == "contextmenu")
	local panel = isCtx and g_ContextMenu or g_SpawnMenu
	local uid = isCtx and STABLE_UID.contextmenu or STABLE_UID.spawnmenu
	local kind = isCtx and "contextmenu" or "spawnmenu"

	-- Save free-float before teardown (reopen restores)
	local m = g_VR and g_VR.menus and g_VR.menus[uid]
	if m and (m.freeFloat or not m.attachment) and m.pos and m.ang then
		shellFloatPose[kind] = {
			pos = Vector(m.pos),
			ang = Angle(m.ang.p, m.ang.y, m.ang.r),
			scale = m.baseScale or m.scale,
		}
	end
	if m and isfunction(vrmod.SaveMenuLayout) then
		vrmod.SaveMenuLayout(uid)
	end
	if m then
		m.persistOpen = false
		m.keepAlive = false
		m.allowHiddenPanel = false
	end

	if IsValid(panel) then
		if panel.SetHangOpen then panel:SetHangOpen(false) end
		if panel.Close then pcall(function() panel:Close() end) end
		if panel.SetVisible then panel:SetVisible(false) end
		if panel.SetPaintedManually then panel:SetPaintedManually(false) end
	end
	W.Close(uid)
	if IsValid(panel) and panelUids[panel] then
		W.Close(panelUids[panel])
		panelUids[panel] = nil
	end
	for buid, info in pairs(bound) do
		if info.kind == kind then W.Close(buid) end
	end
	log("CloseSandboxShell %s", kind)
	return true
end

--- Clear saved free-float (reattach next open to hand)
function W.ClearShellFloatPose(which)
	local isCtx = (which == "context" or which == "contextmenu")
	shellFloatPose[isCtx and "contextmenu" or "spawnmenu"] = nil
end

--- Toggle spawn/context — never stack a second copy
function W.OpenSandboxShell(which)
	which = which or "spawn"
	if not W.IsVR() then return false end
	local isCtx = (which == "context" or which == "contextmenu")
	local panel = isCtx and g_ContextMenu or g_SpawnMenu
	local kind = isCtx and "contextmenu" or "spawnmenu"
	local uidStable = isCtx and STABLE_UID.contextmenu or STABLE_UID.spawnmenu

	-- Already open → CLOSE (toggle)
	if W.IsShellOpen(which) then
		return W.CloseSandboxShell(which)
	end

	if not IsValid(panel) then
		log("%s panel missing — try spawnmenu_reload / sandbox", kind)
		if isCtx then
			LocalPlayer():ConCommand("+menu_context")
		else
			LocalPlayer():ConCommand("+menu")
		end
		timer.Simple(0.15, function()
			panel = isCtx and g_ContextMenu or g_SpawnMenu
			if not IsValid(panel) then
				if isCtx then LocalPlayer():ConCommand("-menu_context") else LocalPlayer():ConCommand("-menu") end
				log("%s still missing after +menu", kind)
				return
			end
			-- Only open if still closed (avoid double from hooks)
			if not W.IsShellOpen(which) then
				W.OpenSandboxShell(which)
			end
		end)
		return false
	end

	-- Spawn + context may both stay open (close via X or toggle same QM item)

	if panel.SetHangOpen then panel:SetHangOpen(false) end
	if panel.SetMouseInputEnabled then panel:SetMouseInputEnabled(true) end
	if panel.SetKeyboardInputEnabled then panel:SetKeyboardInputEnabled(false) end

	-- Open sandbox once; MakePopup intercept skips spawn/context (we manifest below)
	if panel.Open and not panel:IsVisible() then
		panel:Open()
	elseif not panel:IsVisible() then
		if panel.MakePopup then panel:MakePopup() end
		panel:SetVisible(true)
	end

	if vrmod.cube then
		if isCtx and vrmod.cube.ThemeContextMenu then
			vrmod.cube.ThemeContextMenu(panel)
		elseif (not isCtx) and vrmod.cube.ThemeSpawnMenu then
			vrmod.cube.ThemeSpawnMenu(panel)
		end
	end

	-- Single manifest after Open (hooks will no-op if already bound)
	local uid = W.ManifestPanel(panel, {
		kind = kind,
		place = "hand",
		hint = kind,
		uid = uidStable,
	})

	if uid and isfunction(VRUtilMenuRenderPanel) then
		VRUtilMenuRenderPanel(uid)
	end

	log("OpenSandboxShell %s uid=%s vis=%s", kind, tostring(uid), tostring(panel:IsVisible()))
	return uid ~= nil
end

function W.OpenSpawnMenu()
	return W.OpenSandboxShell("spawn")
end

function W.OpenContextMenu()
	return W.OpenSandboxShell("context")
end

function W.CloseSpawnMenu()
	return W.CloseSandboxShell("spawn")
end

function W.CloseContextMenu()
	return W.CloseSandboxShell("context")
end

function vrmod.OpenSpawnMenuVR()
	return W.OpenSpawnMenu()
end
function vrmod.OpenContextMenuVR()
	return W.OpenContextMenu()
end
function vrmod.CloseSpawnMenuVR()
	return W.CloseSpawnMenu()
end

concommand.Add("vrmod_spawnmenu", function()
	if not W.IsVR() then
		print("[panel2vr] vrmod_spawnmenu is VR-only")
		return
	end
	local ok = W.OpenSpawnMenu()
	print("[panel2vr] spawn toggle:", tostring(ok), "open=", tostring(W.IsShellOpen("spawn")))
end)
concommand.Add("vrmod_spawnmenu_close", function()
	W.CloseSpawnMenu()
	print("[panel2vr] spawn forced closed")
end)
concommand.Add("vrmod_contextmenu", function()
	if not W.IsVR() then return end
	W.OpenContextMenu()
end)

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
