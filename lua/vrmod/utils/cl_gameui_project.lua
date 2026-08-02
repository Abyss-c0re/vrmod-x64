if SERVER then return end
-- =============================================================================
-- vrmod.GameUIProject — find / size / bind stock GameUI (pause & main) into VR
--
-- Shared by pause-menu projection and optional menu-first cinema.
-- Does NOT own open/close policy (callers set g_VR._gameUIProjected).
-- =============================================================================

vrmod = vrmod or {}
vrmod.GameUIProject = vrmod.GameUIProject or {}

local G = vrmod.GameUIProject

local boundUid = nil
local boundPanel = nil

function G.IsBound()
	return boundUid ~= nil and g_VR and g_VR.menus and g_VR.menus[boundUid] ~= nil
end

function G.GetBoundUid()
	return boundUid
end

--- Score VGUI tree for GameUI / main / pause shells
function G.CollectCandidates(root, out, depth)
	if not IsValid(root) or depth > 10 then return out end
	out = out or {}
	local name = string.lower(tostring(root:GetName() or ""))
	local class = ""
	if root.ClassName then
		class = string.lower(tostring(root.ClassName))
	elseif root.GetClassName then
		class = string.lower(tostring(root:GetClassName() or ""))
	end
	local w, h = 0, 0
	if root.GetSize then w, h = root:GetSize() end
	local score = 0
	if name:find("mainmenu", 1, true) or class:find("mainmenu", 1, true) then score = score + 100 end
	if name:find("gamemenu", 1, true) or class:find("gamemenu", 1, true) then score = score + 95 end
	if name:find("gmodmenu", 1, true) or name == "mainmenu" then score = score + 95 end
	if name:find("gameui", 1, true) or class:find("gameui", 1, true) then score = score + 80 end
	if name:find("pausemenu", 1, true) or name:find("pause", 1, true) then score = score + 85 end
	if class:find("dhtml", 1, true) and w >= 400 and h >= 300 then score = score + 50 end
	if class:find("html", 1, true) and w >= 400 and h >= 300 then score = score + 40 end
	if name:find("menu", 1, true) and w >= 400 and h >= 300 then score = score + 15 end
	if root:IsVisible() and w >= 200 and h >= 200 then score = score + 8 end
	if w >= 600 and h >= 400 then score = score + 12 end
	if score > 0 then
		out[#out + 1] = { panel = root, score = score, w = w, h = h, name = name, class = class }
	end
	if root.GetChildren then
		for _, ch in ipairs(root:GetChildren()) do
			G.CollectCandidates(ch, out, depth + 1)
		end
	end
	return out
end

function G.FindPanel()
	local world = vgui.GetWorldPanel and vgui.GetWorldPanel()
	if not IsValid(world) then return nil end
	local cands = G.CollectCandidates(world, {}, 0) or {}
	table.sort(cands, function(a, b) return a.score > b.score end)
	if cands[1] and cands[1].score >= 40 then
		return cands[1].panel, cands[1]
	end
	return nil
end

function G.Metrics()
	if vrmod.GetVRUIPanelMetrics then
		return vrmod.GetVRUIPanelMetrics("mainmenu")
	end
	return 720, 560, 0.02
end

function G.Unbind()
	if boundUid and vrmod.panel2vr and vrmod.panel2vr.Close then
		pcall(vrmod.panel2vr.Close, boundUid)
	end
	if IsValid(boundPanel) and boundPanel.SetPaintedManually then
		pcall(function() boundPanel:SetPaintedManually(false) end)
	end
	boundUid = nil
	boundPanel = nil
end

--- Bind panel to wrist (faces user — freefloat cinema was edge-on).
-- @param panel Panel
-- @param opts { uid=, place= "hand"|"cinema" }
function G.BindPanel(panel, opts)
	opts = opts or {}
	if not (g_VR and g_VR.active) then return nil end
	if not IsValid(panel) then return nil end
	if not (vrmod.panel2vr and vrmod.panel2vr.ManifestPanel) then return nil end

	if boundPanel == panel and boundUid and g_VR.menus and g_VR.menus[boundUid] then
		g_VR.menus[boundUid].dirty = true
		g_VR.menus[boundUid].alwaysRedraw = true
		return boundUid
	end
	G.Unbind()

	local w, h, msc = G.Metrics()
	w = math.min(w, 720)
	h = math.min(h, 560)
	if panel.SetSize then pcall(function() panel:SetSize(w, h) end) end
	if panel.SetPos then pcall(function() panel:SetPos(0, 0) end) end
	if panel.SetVisible then panel:SetVisible(true) end
	if panel.SetMouseInputEnabled then panel:SetMouseInputEnabled(true) end
	if panel.SetKeyboardInputEnabled then panel:SetKeyboardInputEnabled(false) end
	-- Avoid MakePopup in VR — focus steal / pause

	local place = opts.place or "hand"
	local placeOverride = nil
	if place == "hand" then
		local wrist = (vrmod.GetSecondaryHand and vrmod.GetSecondaryHand()) or "left"
		local pos, ang, sc = Vector(5, 5.5, 7), Angle(0, -90, 55), msc or 0.02
		if isfunction(VRUtilHandMenuPose) then
			pos, ang, sc = VRUtilHandMenuPose(w, h, sc or 0.02, Vector(5, 5.5, 7), Angle(0, -90, 55), wrist)
		end
		placeOverride = {
			attachment = true,
			pos = pos,
			ang = ang,
			scale = sc or 0.02,
		}
	end

	local uid = vrmod.panel2vr.ManifestPanel(panel, {
		kind = "mainmenu",
		place = place,
		hint = "gameui",
		uid = opts.uid or "p2v_gameui",
		width = w,
		height = h,
		placeOverride = placeOverride,
	})
	if not uid then return nil end

	boundUid = uid
	boundPanel = panel
	if g_VR.menus and g_VR.menus[uid] then
		local m = g_VR.menus[uid]
		m.dirty = true
		m.alwaysRedraw = true
		m.paintInterval = 0
		m.paintIntervalFocused = 0
		m.persistOpen = true
		m.keepAlive = true
		m.cubeMenu = true
		if place == "hand" then
			m.attachment = true
			m.freeFloat = false
			m.attachHand = (vrmod.GetSecondaryHand and vrmod.GetSecondaryHand()) or "left"
		end
	end
	return uid
end

function G.ActivateStockUI()
	if gui and gui.ActivateGameUI then
		pcall(gui.ActivateGameUI)
		return true
	end
	return false
end

function G.HideStockUI()
	if gui and gui.HideGameUI then
		pcall(gui.HideGameUI)
	end
end
