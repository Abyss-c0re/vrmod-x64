if SERVER then return end
-- =============================================================================
-- True menu-first VR — lift the REAL GMod main menu / GameUI into a full-view
-- freefloat cinema surface (HL2VR-style intent). Not a fake hub after construct.
--
-- Stock Source main menu is VGUI (often CEF/DHTML). PaintManual → panel2vr RT.
--
-- Launch: ./scripts/gvrmod_launcher.sh  (default menu mode)
--   sets vrmod_menu_vr 1 + vrmod_autostart 1, no forced +map
-- =============================================================================

vrmod = vrmod or {}
g_VR = g_VR or {}

local boundUid = nil
local boundPanel = nil
local pollId = "vrmod_menu_vr_poll"
local startId = "vrmod_menu_vr_start"
local bootDone = false

-- Convar early (before sh_startup may register siblings)
if not GetConVar("vrmod_menu_vr") then
	CreateClientConVar("vrmod_menu_vr", "0", true, FCVAR_ARCHIVE,
		"1 = menu-first VR: freefloat real MainMenu / GameUI cinema plane")
end

local function MenuVR()
	-- Native Cube wrapper always uses hub — never stock MainMenu cinema
	if vrmod.IsOpenXRLaunchSession and vrmod.IsOpenXRLaunchSession() then
		return false
	end
	local c = GetConVar("vrmod_menu_vr")
	return c and c:GetBool()
end

local function InGame()
	if isfunction(IsInGame) then return IsInGame() end
	local ply = LocalPlayer()
	return IsValid(ply)
end

--- Walk VGUI tree for main menu / game menu shells (score best candidate)
local function CollectCandidates(root, out, depth)
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
	if name:find("gamemenu", 1, true) or class:find("gamemenu", 1, true) then score = score + 90 end
	if name:find("gmodmenu", 1, true) or name == "mainmenu" then score = score + 95 end
	if name:find("gameui", 1, true) or class:find("gameui", 1, true) then score = score + 70 end
	if name:find("menu", 1, true) and w >= 400 and h >= 300 then score = score + 20 end
	if class:find("dhtml", 1, true) and w >= 600 and h >= 400 then score = score + 45 end
	if class:find("html", 1, true) and w >= 500 and h >= 350 then score = score + 35 end
	if root:IsVisible() and w >= 200 and h >= 200 then score = score + 5 end
	-- Prefer large visible surfaces (desktop menu is often ScrW×ScrH)
	if w >= 800 and h >= 500 then score = score + 15 end
	if score > 0 then
		out[#out + 1] = { panel = root, score = score, w = w, h = h, name = name, class = class }
	end
	if root.GetChildren then
		for _, ch in ipairs(root:GetChildren()) do
			CollectCandidates(ch, out, depth + 1)
		end
	end
	return out
end

function vrmod.FindMainMenuPanel()
	local world = vgui.GetWorldPanel and vgui.GetWorldPanel()
	if not IsValid(world) then return nil end
	local cands = CollectCandidates(world, {}, 0) or {}
	table.sort(cands, function(a, b) return a.score > b.score end)
	if cands[1] and cands[1].score >= 40 then
		return cands[1].panel, cands[1]
	end
	return nil
end

local function CinemaMetrics()
	if vrmod.GetVRUIPanelMetrics then
		return vrmod.GetVRUIPanelMetrics("mainmenu")
	end
	local max = (vrmod.GetVRUIMaxRT and vrmod.GetVRUIMaxRT()) or 1024
	local w = math.min(max, 1280)
	local h = math.min(max, 800)
	w = math.floor(w / 2) * 2
	h = math.floor(h / 2) * 2
	return w, h, 0.038
end

local function UnbindMenu()
	if boundUid and vrmod.panel2vr and vrmod.panel2vr.Close then
		pcall(vrmod.panel2vr.Close, boundUid)
	end
	boundUid = nil
	if IsValid(boundPanel) then
		if boundPanel.SetPaintedManually then
			pcall(function() boundPanel:SetPaintedManually(false) end)
		end
	end
	boundPanel = nil
end

--- Project launcher surface into VR via VirtualDisplay (shared with pause).
-- Prefer live MainMenu VGUI when found; else Cube hub delegate.
function vrmod.BindMainMenuToVR()
	if not (g_VR and g_VR.active) then return false end

	-- Optional: stock main-menu VGUI already visible (no ActivateGameUI)
	local panel = nil
	if vrmod.GameUIProject and vrmod.GameUIProject.FindPanel then
		panel = vrmod.GameUIProject.FindPanel()
	elseif vrmod.FindMainMenuPanel then
		panel = vrmod.FindMainMenuPanel()
	end

	if vrmod.VirtualDisplay and vrmod.VirtualDisplay.PresentLauncher then
		local s = vrmod.VirtualDisplay.PresentLauncher({
			panel = panel,
			place = "float", -- free-float; hand-stacking broke close/focus UX
			uid = "vdisp_launcher",
			-- capture = true  -- enable when desktop mirror should tick module FBO
		})
		if s then
			boundUid = s.uid
			boundPanel = s.panel
			return true
		end
	end

	-- Fallback: pause/hub path
	if vrmod.OpenPauseMenuVR then
		return vrmod.OpenPauseMenuVR() and true or false
	end
	if vrmod.GameUIProject and IsValid(panel) then
		return vrmod.GameUIProject.BindPanel(panel, { uid = "p2v_mainmenu", place = "hand" }) ~= nil
	end
	return false
end

function vrmod.UnbindMainMenuFromVR()
	if vrmod.VirtualDisplay and vrmod.VirtualDisplay.Close then
		pcall(vrmod.VirtualDisplay.Close, "launcher")
	end
	UnbindMenu()
end

local function TryStartVRAtMenu()
	if not MenuVR() then return end
	if g_VR and g_VR.active then return end
	if not isfunction(VRUtilClientStart) then return end
	if isfunction(VRMOD_IsHMDPresent) then
		local ok, present = pcall(VRMOD_IsHMDPresent)
		-- OpenXR: still try when probe flakes
		if ok and present == false then
			local prefer = GetConVar("vrmod_prefer_backend")
			local backend = prefer and string.lower(prefer:GetString() or "") or "auto"
			if backend == "openvr" then return end
		end
	end
	pcall(VRUtilClientStart)
end

local function FallbackHub()
	if not (g_VR and g_VR.active) then return end
	if vrmod.VRHub_Open then
		pcall(vrmod.VRHub_Open)
		if vrmod.Toast then
			vrmod.Toast("Main menu VGUI not found — launcher surface open", 5, "hint")
		end
	end
end

local function MenuModeTick()
	if not MenuVR() then return end

	if not (g_VR and g_VR.active) then
		local auto = GetConVar("vrmod_autostart")
		if auto and auto:GetBool() then
			TryStartVRAtMenu()
		end
		return
	end

	if not IsValid(boundPanel) or not boundUid or not (g_VR.menus and g_VR.menus[boundUid]) then
		vrmod.BindMainMenuToVR()
	elseif g_VR.menus[boundUid] then
		g_VR.menus[boundUid].dirty = true
	end
end

local function OnVRStarted()
	if not MenuVR() then return end
	if vrmod.panel2vr and vrmod.panel2vr.InstallHooks then
		pcall(vrmod.panel2vr.InstallHooks)
	end
	timer.Simple(0.5, function()
		if not (g_VR and g_VR.active) then return end
		if not vrmod.BindMainMenuToVR() then
			local n = 0
			timer.Create("vrmod_menu_vr_retry", 0.8, 10, function()
				n = n + 1
				if vrmod.BindMainMenuToVR() then
					timer.Remove("vrmod_menu_vr_retry")
					return
				end
				if n >= 10 then
					timer.Remove("vrmod_menu_vr_retry")
					FallbackHub()
				end
			end)
		end
		timer.Create(pollId, 0.4, 0, MenuModeTick)
	end)
end

--- Boot menu mode without waiting for InitPostEntity (pre-map main menu)
local function BootMenuMode()
	if bootDone or not MenuVR() then return end
	bootDone = true
	if vrmod.logger then
		vrmod.logger.Info("[menu-vr] boot — freefloat real main menu path")
	end
	if vrmod.panel2vr and vrmod.panel2vr.InstallHooks then
		pcall(vrmod.panel2vr.InstallHooks)
	end
	-- Aggressive early start: no player model required
	timer.Create(startId, 0.75, 0, function()
		if not MenuVR() then
			timer.Remove(startId)
			return
		end
		if g_VR and g_VR.active then
			timer.Remove(startId)
			OnVRStarted()
			return
		end
		local auto = GetConVar("vrmod_autostart")
		if auto and auto:GetBool() then
			TryStartVRAtMenu()
		end
	end)
end

hook.Add("InitPostEntity", "vrmod_menu_vr_init", function()
	if not MenuVR() then return end
	BootMenuMode()
end)

-- Pre-map: InitPostEntity never fires. Start from first client Think after load.
hook.Add("Think", "vrmod_menu_vr_boot_think", function()
	if not MenuVR() then return end
	hook.Remove("Think", "vrmod_menu_vr_boot_think")
	timer.Simple(0.3, BootMenuMode)
end)

hook.Add("VRMod_Start", "vrmod_menu_vr_bind", function(ply)
	if ply and IsValid(LocalPlayer()) and ply ~= LocalPlayer() then return end
	if not MenuVR() then return end
	OnVRStarted()
end)

hook.Add("VRMod_Exit", "vrmod_menu_vr_exit", function()
	UnbindMenu()
	timer.Remove(pollId)
	timer.Remove(startId)
	timer.Remove("vrmod_menu_vr_retry")
	bootDone = false
end)

-- ESC handled by cl_vr_unpause (no GameUI / no SP pause)

-- After map change while menu VR on, re-bind when GameUI reappears
hook.Add("OnEntityCreated", "vrmod_menu_vr_map", function()
	-- no-op sentinel; map loads fire InitPostEntity which reboots
end)

concommand.Add("vrmod_menu_vr_bind", function()
	if not (g_VR and g_VR.active) then
		print("[gVRMod] Start VR first (vrmod_start)")
		return
	end
	local ok = vrmod.BindMainMenuToVR()
	print("[gVRMod] BindMainMenuToVR → " .. tostring(ok))
end)

concommand.Add("vrmod_menu_vr_status", function()
	local p, m = vrmod.FindMainMenuPanel()
	print(string.format("[gVRMod] menu_vr=%s active=%s panel=%s score=%s uid=%s",
		tostring(MenuVR()),
		tostring(g_VR and g_VR.active),
		IsValid(p) and (p:GetName() or "?") or "nil",
		tostring(m and m.score),
		tostring(boundUid)))
	if IsValid(p) and p.GetSize then
		local w, h = p:GetSize()
		print(string.format("  size=%sx%s class=%s", tostring(w), tostring(h),
			tostring(p.ClassName or (p.GetClassName and p:GetClassName()) or "?")))
	end
end)
