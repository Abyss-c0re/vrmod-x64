if SERVER then return end
g_VR = g_VR or {}
g_VR.CustomActions = {}
local open = false
function VRUtilLoadCustomActions()
	local str = file.Read("vrmod/vrmod_custom_actions.txt")
	if str then g_VR.CustomActions = util.JSONToTable(str) end
end

concommand.Add("vrmod_actioneditor", function(ply, cmd, args)
	if open or g_VR.active then return end
	open = true
	local window = vgui.Create("DFrame")
	window:SetPos(ScrW() / 2 - 350, ScrH() / 2 - 256)
	window:SetSize(700, 512)
	window:SetTitle("VRMod Custom Input Action Editor")
	window:MakePopup()
	local DLabel = vgui.Create("DLabel", window)
	DLabel:SetText("name                    [driving]    concmd on press                                                   concmd on release")
	DLabel:SetPos(15, 31)
	DLabel:SizeToContents()
	function window:OnClose()
		open = false
		--
		local i = 1
		local names = {}
		while i <= #g_VR.CustomActions do
			if g_VR.CustomActions[i][1] == "" or string.find(g_VR.action_manifest, "/" .. g_VR.CustomActions[i][1] .. "\"", 1, true) or names[g_VR.CustomActions[i][1]] then
				table.remove(g_VR.CustomActions, i)
			else
				names[g_VR.CustomActions[i][1]] = true
				i = i + 1
			end
		end

		--
		file.Write("vrmod/vrmod_custom_actions.txt", util.TableToJSON(g_VR.CustomActions, false))
		--
		local pos = 0
		while true do
			local newPos = string.find(g_VR.action_manifest, "\"type\":", pos + 1)
			if not newPos then
				pos = string.find(g_VR.action_manifest, "}", pos)
				break
			end

			pos = newPos
		end

		local firstPart, lastPart = string.sub(g_VR.action_manifest, 1, pos), string.sub(g_VR.action_manifest, pos + 1)
		for i = 1, #g_VR.CustomActions do
			firstPart = firstPart .. ",\n		{\n			\"name\": \"" .. "/actions/" .. ((g_VR.CustomActions[i].driving or g_VR.CustomActions[i][4] == "1") and "driving" or "main") .. "/in/" .. g_VR.CustomActions[i][1] .. "\",\n			\"type\": \"boolean\"\n		}"
		end

		file.Write("vrmod/vrmod_action_manifest.txt", firstPart .. lastPart)
	end

	local DScrollPanel
	local function UpdateList(scrollTo)
		if DScrollPanel then
			DScrollPanel:Remove()
			DScrollPanel = nil
		end

		DScrollPanel = vgui.Create("DScrollPanel", window)
		DScrollPanel:SetSize(689, 451)
		DScrollPanel:SetPos(6, 56)
		for i = 1, #g_VR.CustomActions do
			local DPanel = DScrollPanel:Add("DPanel")
			DPanel:Dock(TOP)
			DPanel:DockMargin(0, 0, 0, 0)
			DPanel:SetSize(0, 25)
			DPanel:SetPaintBackground(false)
			--name
			local DTextEntry = vgui.Create("DTextEntry", DPanel)
			DTextEntry:SetPos(7, 0)
			DTextEntry:SetSize(110, 20)
			DTextEntry:SetValue(g_VR.CustomActions[i][1])
			local validCharacters = "abcdefghijklmnopqrstuvwxyz0123456789_"
			DTextEntry.AllowInput = function(self, char) if not string.find(validCharacters, char, 1, true) then return true end end
			DTextEntry.OnChange = function(self) g_VR.CustomActions[i][1] = self:GetValue() end
			--use driving actionset?
			local DCheckBox = vgui.Create("DCheckBox", DPanel)
			DCheckBox:SetPos(122, 0)
			DCheckBox:SetValue(g_VR.CustomActions[i].driving or g_VR.CustomActions[i][4] == "1")
			DCheckBox.OnChange = function(self) g_VR.CustomActions[i][4] = self:GetValue() and "1" or "" end
			--cmd on press
			local DTextEntry = vgui.Create("DTextEntry", DPanel)
			DTextEntry:SetPos(7 + 130 + 7, 0)
			DTextEntry:SetSize(225, 20)
			DTextEntry:SetValue(g_VR.CustomActions[i][2])
			DTextEntry.OnChange = function(self) g_VR.CustomActions[i][2] = self:GetValue() end
			--cmd release
			local DTextEntry = vgui.Create("DTextEntry", DPanel)
			DTextEntry:SetPos(7 + 130 + 7 + 225 + 7, 0)
			DTextEntry:SetSize(225, 20)
			DTextEntry:SetValue(g_VR.CustomActions[i][3])
			DTextEntry.OnChange = function(self) g_VR.CustomActions[i][3] = self:GetValue() end
			--remove button
			local DButton = vgui.Create("DButton", DPanel)
			DButton:SetText("REMOVE")
			DButton:SetSize(54, 20)
			DButton:SetPos(608, 0)
			function DButton:DoClick()
				table.remove(g_VR.CustomActions, i)
				UpdateList(DScrollPanel:GetVBar():GetScroll())
			end
		end

		timer.Simple(0, function() if IsValid(DScrollPanel) then DScrollPanel:GetVBar():SetScroll(scrollTo) end end)
	end

	local DButton = vgui.Create("DButton", window)
	DButton:SetText("ADD")
	DButton:SetSize(54, 20)
	DButton:SetPos(614, 31)
	function DButton:DoClick()
		g_VR.CustomActions[#g_VR.CustomActions + 1] = {"", "", "", ""}
		UpdateList(9999999)
	end

	VRUtilLoadCustomActions()
	UpdateList(0)
end)