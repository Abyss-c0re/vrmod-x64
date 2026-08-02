-- Controller binding editor (SteamVR-style: action sets + chords + conflict report).
-- Desktop Derma only — not floated into the HMD.

if SERVER then return end

g_VR = g_VR or {}
local open = false
local listen = nil -- { action, chord=bool, collected={} }
local tabFilter = "main" -- "main" | "driving"
local editorScroll = nil
local conflictLabel = nil

local function SourceLabel(id)
	if vrmod.bindings and vrmod.bindings.SourceLabel then
		return vrmod.bindings.SourceLabel(id)
	end
	return id
end

local function BeginListen(action, chord)
	local held = (vrmod.bindings.SnapshotHeldSources and vrmod.bindings.SnapshotHeldSources()) or {}
	listen = {
		action = action,
		chord = not not chord,
		collected = {},
		held = held,
		armUntil = CurTime() + 0.2,
	}
	if vrmod.bindings.SetListenSuppress then
		vrmod.bindings.SetListenSuppress(true)
	end
end

local function StopListen()
	listen = nil
	if vrmod.bindings.SetListenSuppress then
		vrmod.bindings.SetListenSuppress(false)
	end
end

local function FinishListen(confirm)
	if not listen then return end
	if confirm and listen.chord then
		local collected = listen.collected or {}
		if #collected < 2 then
			if vrmod.Toast then
				vrmod.Toast("Chord needs 2+ buttons held together", 3, "hint")
			else
				print("[VRMod] Chord needs 2+ buttons")
			end
			return -- keep listening
		end
		local prev = vrmod.bindings.GetMap().actions[listen.action]
		local set = prev and prev.set or nil
		local warnings = vrmod.bindings.SetActionBinding(listen.action, collected, "all", set)
		if warnings and warnings[1] and vrmod.Toast then
			vrmod.Toast(warnings[1], 3, "hint")
		end
	end
	StopListen()
end

local function RefreshConflicts()
	if not IsValid(conflictLabel) or not vrmod.bindings.DetectConflicts then return end
	local all = vrmod.bindings.DetectConflicts()
	local hard, soft = {}, {}
	for _, c in ipairs(all) do
		if c.severity == "hard" then
			hard[#hard + 1] = c.message
		else
			soft[#soft + 1] = c.message
		end
	end
	if #hard == 0 and #soft == 0 then
		conflictLabel:SetText("Conflicts: none")
		conflictLabel:SetTextColor(Color(120, 200, 140))
		return
	end
	local lines = {}
	if #hard > 0 then
		lines[#lines + 1] = "HARD (" .. #hard .. "): " .. table.concat(hard, " · ")
	end
	if #soft > 0 then
		-- Soft includes intentional Quest patterns (sprint under teleport chord)
		lines[#lines + 1] = "Note (" .. #soft .. "): " .. table.concat(soft, " · ")
	end
	local txt = table.concat(lines, "  |  ")
	if #txt > 220 then txt = string.sub(txt, 1, 217) .. "…" end
	conflictLabel:SetText(txt)
	conflictLabel:SetTextColor(#hard > 0 and Color(255, 120, 100) or Color(230, 190, 100))
end

local function ActionHasHardConflict(actionId)
	if not vrmod.bindings.ConflictsForAction then return false end
	for _, c in ipairs(vrmod.bindings.ConflictsForAction(actionId)) do
		if c.severity == "hard" then return true end
	end
	return false
end

local function ActionHasSoftConflict(actionId)
	if not vrmod.bindings.ConflictsForAction then return false end
	for _, c in ipairs(vrmod.bindings.ConflictsForAction(actionId)) do
		if c.severity == "soft" then return true end
	end
	return false
end

local function RefreshList(scroll, scrollTo)
	if not IsValid(scroll) then return end
	scroll:Clear()
	local map = vrmod.bindings.GetMap()
	local actions
	if vrmod.bindings.ListLogicalActionsFiltered then
		actions = vrmod.bindings.ListLogicalActionsFiltered(tabFilter)
	else
		actions = vrmod.bindings.ListLogicalActions()
	end

	for _, info in ipairs(actions) do
		local rule = map.actions[info.id]
		local hard = ActionHasHardConflict(info.id)
		local soft = (not hard) and ActionHasSoftConflict(info.id)
		local row = scroll:Add("DPanel")
		row:Dock(TOP)
		row:DockMargin(2, 2, 2, 0)
		row:SetTall(28)
		row.Paint = function(self, w, h)
			if listen and listen.action == info.id then
				surface.SetDrawColor(80, 120, 40, 220)
			elseif hard then
				surface.SetDrawColor(90, 30, 30, 220)
			elseif soft then
				surface.SetDrawColor(70, 55, 25, 200)
			else
				surface.SetDrawColor(40, 40, 40, 200)
			end
			surface.DrawRect(0, 0, w, h)
		end

		local name = vgui.Create("DLabel", row)
		name:SetPos(6, 5)
		name:SetSize(150, 18)
		name:SetText(info.label)
		name:SetTextColor(hard and Color(255, 180, 170) or Color(230, 230, 230))

		local bind = vgui.Create("DLabel", row)
		bind:SetPos(160, 5)
		bind:SetSize(290, 18)
		local txt = vrmod.bindings.FormatRule(rule, true)
		if listen and listen.action == info.id then
			if listen.chord then
				local parts = {}
				for _, id in ipairs(listen.collected or {}) do
					parts[#parts + 1] = SourceLabel(id)
				end
				txt = "CHORD (hold 2+): " .. (#parts > 0 and table.concat(parts, " + ") or "…")
			else
				txt = "Press one controller button…"
			end
		elseif hard then
			txt = txt .. "  ⚠ conflict"
		end
		bind:SetText(txt)
		bind:SetTextColor(hard and Color(255, 160, 140) or Color(180, 220, 255))

		local btnBind = vgui.Create("DButton", row)
		btnBind:SetText("Bind")
		btnBind:SetSize(50, 22)
		btnBind:SetPos(460, 3)
		btnBind.DoClick = function()
			BeginListen(info.id, false)
			RefreshList(scroll, scroll:GetVBar():GetScroll())
		end

		local btnChord = vgui.Create("DButton", row)
		btnChord:SetText("Chord")
		btnChord:SetTooltip("AND of 2+ buttons (e.g. both thumbrests → Reload)")
		btnChord:SetSize(50, 22)
		btnChord:SetPos(514, 3)
		btnChord.DoClick = function()
			BeginListen(info.id, true)
			RefreshList(scroll, scroll:GetVBar():GetScroll())
		end

		local btnClear = vgui.Create("DButton", row)
		btnClear:SetText("Def")
		btnClear:SetTooltip("Restore Quest default for this action")
		btnClear:SetSize(50, 22)
		btnClear:SetPos(568, 3)
		btnClear.DoClick = function()
			if listen and listen.action == info.id then StopListen() end
			if vrmod.bindings.RestoreActionDefault then
				vrmod.bindings.RestoreActionDefault(info.id)
			end
			RefreshList(scroll, scroll:GetVBar():GetScroll())
			RefreshConflicts()
		end
	end

	RefreshConflicts()
	timer.Simple(0, function()
		if IsValid(scroll) then scroll:GetVBar():SetScroll(scrollTo or 0) end
	end)
end

local function FullRefresh()
	if IsValid(editorScroll) then
		RefreshList(editorScroll, 0)
	end
end

concommand.Add("vrmod_bindingeditor", function()
	if open then return end
	if not vrmod.bindings then
		print("[VRMod] Binding system not loaded")
		return
	end
	-- In VR: native hand panel (never float Derma into HMD).
	if g_VR and g_VR.active then
		if vrmod.BindingsPanel_Open then
			vrmod.BindingsPanel_Open()
		else
			print("[VRMod] BindingsPanel_Open missing — need cl_bindings_panel.lua")
		end
		return
	end
	open = true
	tabFilter = "main"
	vrmod.bindings.Load()

	local frame = vgui.Create("DFrame")
	frame:SetSize(660, 600)
	frame:SetTitle("Controller Bindings — Quest 3 defaults (SteamVR-style)")
	frame:Center()
	frame:MakePopup()
	function frame:OnClose()
		open = false
		StopListen()
		editorScroll = nil
		conflictLabel = nil
		hook.Remove("Think", "vrmod_binding_listen")
		vrmod.bindings.Save()
	end

	local help = vgui.Create("DLabel", frame)
	help:SetPos(10, 28)
	help:SetSize(640, 36)
	help:SetWrap(true)
	help:SetText("Bind = one button. Chord = hold 2+ buttons then Confirm (AND). Def = Quest default. On foot vs Vehicle are separate sets (shared buttons OK across sets). Red = hard conflict.")

	-- Action-set tabs (SteamVR main / driving)
	local tabBar = vgui.Create("DPanel", frame)
	tabBar:SetPos(8, 68)
	tabBar:SetSize(644, 28)
	tabBar.Paint = nil

	local function makeTab(label, filter, x)
		local b = vgui.Create("DButton", tabBar)
		b:SetText(label)
		b:SetPos(x, 0)
		b:SetSize(120, 26)
		b.DoClick = function()
			tabFilter = filter
			StopListen()
			FullRefresh()
		end
		b.Paint = function(self, w, h)
			local on = (tabFilter == filter)
			surface.SetDrawColor(on and Color(180, 50, 70) or Color(50, 50, 50))
			surface.DrawRect(0, 0, w, h)
			draw.SimpleText(label, "DermaDefaultBold", w * 0.5, h * 0.5, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			return true
		end
		return b
	end
	makeTab("On foot", "main", 0)
	makeTab("Vehicle", "driving", 124)

	local scroll = vgui.Create("DScrollPanel", frame)
	scroll:SetPos(8, 100)
	scroll:SetSize(644, 360)
	editorScroll = scroll

	conflictLabel = vgui.Create("DLabel", frame)
	conflictLabel:SetPos(10, 465)
	conflictLabel:SetSize(640, 32)
	conflictLabel:SetWrap(true)
	conflictLabel:SetText("Conflicts: …")
	conflictLabel:SetTextColor(Color(160, 160, 160))

	local bar = vgui.Create("DPanel", frame)
	bar:SetPos(8, 502)
	bar:SetSize(644, 40)
	bar.Paint = nil

	local btnConfirm = vgui.Create("DButton", bar)
	btnConfirm:SetText("Confirm Chord")
	btnConfirm:SetSize(120, 28)
	btnConfirm:Dock(LEFT)
	btnConfirm:DockMargin(0, 4, 6, 4)
	btnConfirm.DoClick = function()
		if listen and listen.chord then
			FinishListen(true)
			FullRefresh()
		end
	end

	local btnCancel = vgui.Create("DButton", bar)
	btnCancel:SetText("Cancel Listen")
	btnCancel:SetSize(110, 28)
	btnCancel:Dock(LEFT)
	btnCancel:DockMargin(0, 4, 6, 4)
	btnCancel.DoClick = function()
		StopListen()
		FullRefresh()
	end

	local btnReset = vgui.Create("DButton", bar)
	btnReset:SetText("Reset Defaults")
	btnReset:SetSize(110, 28)
	btnReset:Dock(LEFT)
	btnReset:DockMargin(0, 4, 6, 4)
	btnReset.DoClick = function()
		vrmod.bindings.ResetDefaults()
		StopListen()
		FullRefresh()
	end

	local btnCustom = vgui.Create("DButton", bar)
	btnCustom:SetText("Custom Actions…")
	btnCustom:SetSize(120, 28)
	btnCustom:Dock(LEFT)
	btnCustom:DockMargin(0, 4, 6, 4)
	btnCustom.DoClick = function()
		RunConsoleCommand("vrmod_actioneditor")
	end

	local btnSave = vgui.Create("DButton", bar)
	btnSave:SetText("Save")
	btnSave:SetSize(70, 28)
	btnSave:Dock(RIGHT)
	btnSave:DockMargin(0, 4, 0, 4)
	btnSave.DoClick = function()
		vrmod.bindings.Save()
		local n = 0
		if vrmod.bindings.DetectConflicts then
			for _, c in ipairs(vrmod.bindings.DetectConflicts()) do
				if c.severity == "hard" then n = n + 1 end
			end
		end
		if n > 0 then
			print("[VRMod] Saved with " .. n .. " hard binding conflict(s) — check red rows")
		else
			print("[VRMod] Bindings saved")
		end
	end

	local srcLabel = vgui.Create("DLabel", frame)
	srcLabel:SetPos(10, 548)
	srcLabel:SetSize(640, 18)
	srcLabel:SetText("Sources: (start VR / OpenXR for live controller state)")
	srcLabel:SetTextColor(Color(160, 160, 160))

	FullRefresh()

	local lastListenRefresh = 0
	hook.Add("Think", "vrmod_binding_listen", function()
		if not IsValid(frame) then
			hook.Remove("Think", "vrmod_binding_listen")
			return
		end
		if not vrmod.bindings.HasSourcesAPI or not vrmod.bindings.HasSourcesAPI() then
			srcLabel:SetText("Sources: need OpenXR module (GetControllerSources). OpenVR uses SteamVR bind UI.")
			return
		end

		local sources = vrmod.bindings.GetSources()
		if sources then
			local pressed = {}
			for id, s in pairs(sources) do
				if type(s) == "table" and vrmod.bindings.SourceIsPressed and vrmod.bindings.SourceIsPressed(s) then
					pressed[#pressed + 1] = s.label or id
				elseif type(s) == "table" and s.pressed then
					pressed[#pressed + 1] = s.label or id
				end
			end
			table.sort(pressed)
			srcLabel:SetText("Live: " .. (#pressed > 0 and table.concat(pressed, ", ") or "(none) — press a controller button"))

			if listen and CurTime() >= (listen.armUntil or 0) then
				local news = {}
				if vrmod.bindings.PollListenPresses then
					news = vrmod.bindings.PollListenPresses(listen.held)
				end
				for _, id in ipairs(news) do
					if listen.chord then
						local found = false
						for _, c in ipairs(listen.collected) do
							if c == id then found = true break end
						end
						if not found then
							listen.collected[#listen.collected + 1] = id
							if CurTime() - lastListenRefresh > 0.1 then
								lastListenRefresh = CurTime()
								if IsValid(editorScroll) then
									RefreshList(editorScroll, editorScroll:GetVBar():GetScroll())
								end
							end
						end
					else
						local prev = vrmod.bindings.GetMap().actions[listen.action]
						local set = prev and prev.set or nil
						vrmod.bindings.SetActionBinding(listen.action, { id }, "any", set)
						StopListen()
						FullRefresh()
						break
					end
				end
			end
		else
			srcLabel:SetText("Sources: empty — start VR with OpenXR (Quest/WiVRn)")
		end
	end)
end)

concommand.Add("vrmod_bindings", function() RunConsoleCommand("vrmod_bindingeditor") end)

-- Console: dump conflicts
concommand.Add("vrmod_bindings_conflicts", function()
	if not vrmod.bindings or not vrmod.bindings.DetectConflicts then
		print("[VRMod] bindings conflict API missing")
		return
	end
	vrmod.bindings.Load()
	local list = vrmod.bindings.DetectConflicts()
	if #list == 0 then
		print("[VRMod] No binding conflicts")
		return
	end
	print(string.format("[VRMod] %d conflict(s):", #list))
	for _, c in ipairs(list) do
		print(string.format("  [%s] %s", c.severity, c.message))
	end
end)
