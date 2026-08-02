if SERVER then return end
-- =============================================================================
-- vrmod.GameUIProject — find / size / bind stock GameUI into VR
--
-- Routes through vrmod.VirtualDisplay so launcher cinema and in-game projection
-- share one pipeline (module virtual monitor + panel2vr present).
-- Does NOT ActivateGameUI (SP freeze). Callers own open/close policy.
-- =============================================================================

vrmod = vrmod or {}
vrmod.GameUIProject = vrmod.GameUIProject or {}

local G = vrmod.GameUIProject

local SESSION = "gameui"

function G.IsBound()
	if vrmod.VirtualDisplay and vrmod.VirtualDisplay.IsOpen then
		return vrmod.VirtualDisplay.IsOpen(SESSION)
	end
	return false
end

function G.GetBoundUid()
	local s = vrmod.VirtualDisplay and vrmod.VirtualDisplay.GetSession and vrmod.VirtualDisplay.GetSession(SESSION)
	return s and s.uid or nil
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
	if vrmod.VirtualDisplay and vrmod.VirtualDisplay.Close then
		vrmod.VirtualDisplay.Close(SESSION)
	end
end

--- Bind panel through VirtualDisplay (hand by default — faces user).
-- @param panel Panel
-- @param opts { uid=, place= "hand"|"cinema", capture=bool, session= }
function G.BindPanel(panel, opts)
	opts = opts or {}
	if not (g_VR and g_VR.active) then return nil end
	if not IsValid(panel) then return nil end
	if not (vrmod.VirtualDisplay and vrmod.VirtualDisplay.Present) then return nil end

	local w, h = G.Metrics()
	w = math.min(w, opts.width or 720)
	h = math.min(h, opts.height or 560)
	local session = opts.session or SESSION

	local s = vrmod.VirtualDisplay.Present(session, {
		mode = opts.capture and "capture" or "vgui",
		panel = panel,
		place = opts.place or "float",
		width = w,
		height = h,
		uid = opts.uid or ("vdisp_" .. session),
		kind = "mainmenu",
		hint = "gameui",
		capture = opts.capture,
	})
	return s and s.uid or nil
end

function G.ActivateStockUI()
	-- Intentionally weak: callers must not rely on this in VR (freezes SP).
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
