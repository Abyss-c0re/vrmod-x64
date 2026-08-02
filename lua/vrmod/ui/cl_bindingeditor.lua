-- OpenXR controller binding editor (replaces SteamVR binding UI).
-- Assign physical buttons (and chords) to logical VRMod actions.

if SERVER then return end

g_VR = g_VR or {}
local open = false
local listen = nil -- { action, chord=bool, collected={} }

local function SourceLabel(id)
	local src = vrmod.bindings.GetSources()
	if src and src[id] and src[id].label then return src[id].label end
	return id
end

local function RefreshList(scroll, scrollTo)
	if not IsValid(scroll) then return end
	scroll:Clear()
	local map = vrmod.bindings.GetMap()
	local actions = vrmod.bindings.ListLogicalActions()

	for _, info in ipairs(actions) do
		local rule = map.actions[info.id]
		local row = scroll:Add("DPanel")
		row:Dock(TOP)
		row:DockMargin(2, 2, 2, 0)
		row:SetTall(28)
		row.Paint = function(self, w, h)
			surface.SetDrawColor(40, 40, 40, 200)
			surface.DrawRect(0, 0, w, h)
			if listen and listen.action == info.id then
				surface.SetDrawColor(80, 120, 40, 220)
				surface.DrawRect(0, 0, w, h)
			end
		end

		local name = vgui.Create("DLabel", row)
		name:SetPos(6, 5)
		name:SetSize(160, 18)
		name:SetText(info.label)
		name:SetTextColor(Color(230, 230, 230))

		local bind = vgui.Create("DLabel", row)
		bind:SetPos(170, 5)
		bind:SetSize(280, 18)
		local txt = vrmod.bindings.FormatRule(rule)
		if listen and listen.action == info.id then
			if listen.chord then
				local parts = {}
				for _, id in ipairs(listen.collected or {}) do
					parts[#parts + 1] = SourceLabel(id)
				end
				txt = "CHORD: press buttons, then Confirm… " .. table.concat(parts, " + ")
			else
				txt = "Press a controller button…"
			end
		end
		bind:SetText(txt)
		bind:SetTextColor(Color(180, 220, 255))

		local btnBind = vgui.Create("DButton", row)
		btnBind:SetText("Bind")
		btnBind:SetSize(50, 22)
		btnBind:SetPos(460, 3)
		btnBind.DoClick = function()
			listen = { action = info.id, chord = false, collected = {} }
			RefreshList(scroll, scroll:GetVBar():GetScroll())
		end

		local btnChord = vgui.Create("DButton", row)
		btnChord:SetText("Chord")
		btnChord:SetSize(50, 22)
		btnChord:SetPos(514, 3)
		btnChord.DoClick = function()
			listen = { action = info.id, chord = true, collected = {} }
			RefreshList(scroll, scroll:GetVBar():GetScroll())
		end

		local btnClear = vgui.Create("DButton", row)
		btnClear:SetText("Clear")
		btnClear:SetSize(50, 22)
		btnClear:SetPos(568, 3)
		btnClear.DoClick = function()
			if listen and listen.action == info.id then listen = nil end
			vrmod.bindings.ClearActionBinding(info.id)
			-- restore default if any
			local def = vrmod.bindings.GetDefaults().actions[info.id]
			if def then
				vrmod.bindings.SetActionBinding(info.id, def.sources, def.mode)
			end
			RefreshList(scroll, scroll:GetVBar():GetScroll())
		end
	end

	timer.Simple(0, function()
		if IsValid(scroll) then scroll:GetVBar():SetScroll(scrollTo or 0) end
	end)
end

local function FinishListen(confirm)
	if not listen then return end
	if confirm and listen.chord and #(listen.collected or {}) > 0 then
		vrmod.bindings.SetActionBinding(listen.action, listen.collected, "all")
	end
	listen = nil
end

concommand.Add("vrmod_bindingeditor", function()
	if open then return end
	if not vrmod.bindings then
		print("[VRMod] Binding system not loaded")
		return
	end
	open = true
	vrmod.bindings.Load()

	local frame = vgui.Create("DFrame")
	frame:SetSize(640, 560)
	frame:SetTitle("VRMod OpenXR Controller Bindings (SteamVR UI replacement)")
	frame:Center()
	frame:MakePopup()
	function frame:OnClose()
		open = false
		listen = nil
		hook.Remove("Think", "vrmod_binding_listen")
		vrmod.bindings.Save()
	end

	local help = vgui.Create("DLabel", frame)
	help:SetPos(10, 28)
	help:SetSize(620, 48)
	help:SetWrap(true)
	help:SetText("Assign controller buttons to game actions. Bind = single button. Chord = hold multiple buttons then click Confirm (e.g. both thumbrests → Reload). Changes apply immediately in VR; saved on close. Analogs (walk stick / turn) stay on OpenXR defaults.")

	local scroll = vgui.Create("DScrollPanel", frame)
	scroll:SetPos(8, 80)
	scroll:SetSize(624, 420)

	local bar = vgui.Create("DPanel", frame)
	bar:SetPos(8, 508)
	bar:SetSize(624, 40)
	bar.Paint = nil

	local btnConfirm = vgui.Create("DButton", bar)
	btnConfirm:SetText("Confirm Chord")
	btnConfirm:SetSize(120, 28)
	btnConfirm:Dock(LEFT)
	btnConfirm:DockMargin(0, 4, 6, 4)
	btnConfirm.DoClick = function()
		if listen and listen.chord then
			FinishListen(true)
			RefreshList(scroll, scroll:GetVBar():GetScroll())
		end
	end

	local btnCancel = vgui.Create("DButton", bar)
	btnCancel:SetText("Cancel Listen")
	btnCancel:SetSize(110, 28)
	btnCancel:Dock(LEFT)
	btnCancel:DockMargin(0, 4, 6, 4)
	btnCancel.DoClick = function()
		listen = nil
		RefreshList(scroll, scroll:GetVBar():GetScroll())
	end

	local btnReset = vgui.Create("DButton", bar)
	btnReset:SetText("Reset Defaults")
	btnReset:SetSize(110, 28)
	btnReset:Dock(LEFT)
	btnReset:DockMargin(0, 4, 6, 4)
	btnReset.DoClick = function()
		vrmod.bindings.ResetDefaults()
		listen = nil
		RefreshList(scroll, 0)
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
	end

	-- Live source readout
	local srcLabel = vgui.Create("DLabel", frame)
	srcLabel:SetPos(10, 485)
	srcLabel:SetSize(620, 18)
	srcLabel:SetText("Sources: (start VR to see live controller state)")
	srcLabel:SetTextColor(Color(160, 160, 160))

	RefreshList(scroll, 0)

	local lastListenRefresh = 0
	hook.Add("Think", "vrmod_binding_listen", function()
		if not IsValid(frame) then
			hook.Remove("Think", "vrmod_binding_listen")
			return
		end
		local sources = vrmod.bindings.GetSources()
		if sources then
			local pressed = {}
			for id, s in pairs(sources) do
				if type(s) == "table" and s.pressed then
					pressed[#pressed + 1] = s.label or id
				end
			end
			table.sort(pressed)
			srcLabel:SetText("Live: " .. (#pressed > 0 and table.concat(pressed, ", ") or "(none)"))

			if listen then
				for id, s in pairs(sources) do
					if type(s) == "table" and s.pressed then
						if listen.chord then
							local found = false
							for _, c in ipairs(listen.collected) do
								if c == id then found = true break end
							end
							if not found then
								listen.collected[#listen.collected + 1] = id
								if CurTime() - lastListenRefresh > 0.15 then
									lastListenRefresh = CurTime()
									RefreshList(scroll, scroll:GetVBar():GetScroll())
								end
							end
						else
							-- single bind on rising edge-ish: first pressed source wins
							vrmod.bindings.SetActionBinding(listen.action, { id }, "any")
							listen = nil
							RefreshList(scroll, scroll:GetVBar():GetScroll())
							break
						end
					end
				end
			end
		else
			srcLabel:SetText("Sources: module has no GetControllerSources (rebuild/install) or VR not started")
		end
	end)
end)

-- Alias people may try
concommand.Add("vrmod_bindings", function() RunConsoleCommand("vrmod_bindingeditor") end)
