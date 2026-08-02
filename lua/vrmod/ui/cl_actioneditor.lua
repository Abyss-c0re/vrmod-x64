if SERVER then return end
-- Custom named actions → console commands on press/release.
-- Must be merged into the action manifest BEFORE VRMOD_SetActionManifest
-- (every VR start), or OpenXR/OpenVR never see them.

g_VR = g_VR or {}
g_VR.CustomActions = g_VR.CustomActions or {}

local open = false
local CUSTOM_FILE = "vrmod/vrmod_custom_actions.txt"

function VRUtilLoadCustomActions()
	g_VR.CustomActions = g_VR.CustomActions or {}
	if not file.Exists(CUSTOM_FILE, "DATA") then return g_VR.CustomActions end
	local str = file.Read(CUSTOM_FILE, "DATA")
	if not str or str == "" then return g_VR.CustomActions end
	local ok, data = pcall(util.JSONToTable, str)
	if ok and type(data) == "table" then
		g_VR.CustomActions = data
	end
	return g_VR.CustomActions
end

--- Drop empty / duplicate / name-colliding-with-built-in rows.
function VRUtilSanitizeCustomActions()
	g_VR.CustomActions = g_VR.CustomActions or {}
	local base = g_VR.action_manifest or ""
	local i = 1
	local names = {}
	while i <= #g_VR.CustomActions do
		local row = g_VR.CustomActions[i]
		local name = row and row[1] or ""
		local bad = name == ""
			or names[name]
			or (base ~= "" and string.find(base, "/" .. name .. "\"", 1, true) ~= nil)
		if bad then
			table.remove(g_VR.CustomActions, i)
		else
			names[name] = true
			i = i + 1
		end
	end
	return g_VR.CustomActions
end

--- Inject custom booleans into a SteamVR-format action manifest string.
function VRUtilBuildActionManifestWithCustoms(baseManifest)
	baseManifest = baseManifest or g_VR.action_manifest or ""
	if baseManifest == "" then return baseManifest end
	VRUtilLoadCustomActions()
	VRUtilSanitizeCustomActions()
	if not g_VR.CustomActions or #g_VR.CustomActions == 0 then
		return baseManifest
	end

	local pos = 0
	while true do
		local newPos = string.find(baseManifest, "\"type\":", pos + 1, true)
		if not newPos then
			pos = string.find(baseManifest, "}", pos, true) or #baseManifest
			break
		end
		pos = newPos
	end

	local firstPart = string.sub(baseManifest, 1, pos)
	local lastPart = string.sub(baseManifest, pos + 1)
	for i = 1, #g_VR.CustomActions do
		local row = g_VR.CustomActions[i]
		local name = row[1]
		if name and name ~= "" then
			local driving = row.driving or row[4] == "1"
			local set = driving and "driving" or "main"
			firstPart = firstPart
				.. ",\n		{\n			\"name\": \"/actions/"
				.. set
				.. "/in/"
				.. name
				.. "\",\n			\"type\": \"boolean\"\n		}"
		end
	end
	return firstPart .. lastPart
end

--- Write DATA/vrmod/vrmod_action_manifest.txt with customs applied.
--- Call this BEFORE VRMOD_SetActionManifest every VR start.
function VRUtilWriteActionManifestWithCustoms()
	if not file.Exists("vrmod", "DATA") then file.CreateDir("vrmod") end
	if not g_VR.action_manifest then return false end
	local body = VRUtilBuildActionManifestWithCustoms(g_VR.action_manifest)
	file.Write("vrmod/vrmod_action_manifest.txt", body)
	return true
end

function VRUtilSaveCustomActions()
	if not file.Exists("vrmod", "DATA") then file.CreateDir("vrmod") end
	VRUtilSanitizeCustomActions()
	file.Write(CUSTOM_FILE, util.TableToJSON(g_VR.CustomActions or {}, false))
	VRUtilWriteActionManifestWithCustoms()
	-- If already in VR, re-push manifest so new names exist (may need restart on some runtimes)
	if g_VR and g_VR.active and isfunction(VRMOD_SetActionManifest) then
		pcall(VRMOD_SetActionManifest, "vrmod/vrmod_action_manifest.txt")
	end
end

concommand.Add("vrmod_actioneditor", function()
	if open then return end

	open = true
	VRUtilLoadCustomActions()

	local window = vgui.Create("DFrame")
	window:SetPos(ScrW() / 2 - 350, ScrH() / 2 - 256)
	window:SetSize(700, 512)
	window:SetTitle("VRMod Custom Input Action Editor")
	-- Mark so panel2vr can still surface it, but this is the action editor — not bindings.
	window._vrmod_action_editor = true
	window:MakePopup()

	local DLabel = vgui.Create("DLabel", window)
	DLabel:SetText("name                    [driving]    concmd on press                                                   concmd on release")
	DLabel:SetPos(15, 31)
	DLabel:SizeToContents()

	function window:OnClose()
		open = false
		VRUtilSaveCustomActions()
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

			local DTextEntry = vgui.Create("DTextEntry", DPanel)
			DTextEntry:SetPos(7, 0)
			DTextEntry:SetSize(110, 20)
			DTextEntry:SetValue(g_VR.CustomActions[i][1] or "")
			local validCharacters = "abcdefghijklmnopqrstuvwxyz0123456789_"
			DTextEntry.AllowInput = function(self, char)
				if not string.find(validCharacters, char, 1, true) then return true end
			end
			DTextEntry.OnChange = function(self)
				g_VR.CustomActions[i][1] = self:GetValue()
			end

			local DCheckBox = vgui.Create("DCheckBox", DPanel)
			DCheckBox:SetPos(122, 0)
			DCheckBox:SetValue(g_VR.CustomActions[i].driving or g_VR.CustomActions[i][4] == "1")
			DCheckBox.OnChange = function(self)
				g_VR.CustomActions[i][4] = self:GetValue() and "1" or ""
			end

			local pressEntry = vgui.Create("DTextEntry", DPanel)
			pressEntry:SetPos(7 + 130 + 7, 0)
			pressEntry:SetSize(225, 20)
			pressEntry:SetValue(g_VR.CustomActions[i][2] or "")
			pressEntry.OnChange = function(self)
				g_VR.CustomActions[i][2] = self:GetValue()
			end

			local releaseEntry = vgui.Create("DTextEntry", DPanel)
			releaseEntry:SetPos(7 + 130 + 7 + 225 + 7, 0)
			releaseEntry:SetSize(225, 20)
			releaseEntry:SetValue(g_VR.CustomActions[i][3] or "")
			releaseEntry.OnChange = function(self)
				g_VR.CustomActions[i][3] = self:GetValue()
			end

			local DButton = vgui.Create("DButton", DPanel)
			DButton:SetText("REMOVE")
			DButton:SetSize(54, 20)
			DButton:SetPos(608, 0)
			function DButton:DoClick()
				table.remove(g_VR.CustomActions, i)
				UpdateList(DScrollPanel:GetVBar():GetScroll())
			end
		end

		timer.Simple(0, function()
			if IsValid(DScrollPanel) then DScrollPanel:GetVBar():SetScroll(scrollTo) end
		end)
	end

	local DButton = vgui.Create("DButton", window)
	DButton:SetText("ADD")
	DButton:SetSize(54, 20)
	DButton:SetPos(614, 31)
	function DButton:DoClick()
		g_VR.CustomActions[#g_VR.CustomActions + 1] = { "", "", "", "" }
		UpdateList(9999999)
	end

	UpdateList(0)
end)
