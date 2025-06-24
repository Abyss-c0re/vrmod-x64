if SERVER then return end

local meta = getmetatable(vgui.GetWorldPanel())
local orig = meta.MakePopup

local allPopups = {}

-- Generate a clean, unique identifier based on panel name
local function getPanelIdentifier(panel)
	if not IsValid(panel) then return "popup_unknown" end
	local name = panel:GetName() or "Panel"
	name = name:lower():gsub("[^%w]", "") -- Sanitize: remove non-alphanumeric
	return "popup_" .. name
end

-- Overwrite MakePopup
meta.MakePopup = function(...)
	local args = {...}
	orig(unpack(args))
	if not g_VR.threePoints then return end

	local panel = args[1]
	if not IsValid(panel) then return end

	local uid = getPanelIdentifier(panel)
	allPopups[uid] = panel -- Overwrite any existing entry with same name

	timer.Simple(0.1, function()
		if not IsValid(panel) then return end
		panel:SetPaintedManually(true)

		local name = panel:GetName()
		if name == "DMenu" or name == "DImage" or name == "DPanel" then
			local child = panel:GetChildren()[1]
			if IsValid(child) then
				panel = child
				panel.Paint = function(self, w, h)
					surface.SetDrawColor(175, 174, 187)
					surface.DrawRect(0, 0, w, h)
				end
			end
		end

		local panelWidth, panelHeight = ScrW(), ScrH()
		VRUtilMenuOpen(uid, panelWidth, panelHeight, panel, true, Vector(10, 10, 5), Angle(0, -90, 50), 0.03, true, function()
			timer.Simple(0.1, function()
				if not g_VR.active and IsValid(panel) then
					panel:MakePopup()
					panel:RequestFocus()
				end
			end)
			-- Cleanup
			allPopups[uid] = nil
		end)

		VRUtilMenuRenderPanel(uid)
	end)
end

-- Continuously render active popups
hook.Add("Think", "update_all_popups", function()
	for uid, panel in pairs(allPopups) do
		if IsValid(panel) then
			VRUtilMenuRenderPanel(uid)
		else
			allPopups[uid] = nil -- Auto-cleanup invalid panels
		end
	end
end)
