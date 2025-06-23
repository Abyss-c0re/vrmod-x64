if SERVER then return end
local meta = getmetatable(vgui.GetWorldPanel())
local orig = meta.MakePopup
local popupCount = 0
-- All active popups
local allPopups = {}
meta.MakePopup = function(...)
	local args = {...}
	orig(unpack(args))
	if not g_VR.threePoints then return end
	local panel = args[1]
	local uid = "popup_" .. popupCount
	-- Add the new popup to the list
	table.insert(allPopups, uid)
	--wait because makepopup might be called before menu is fully built
	timer.Simple(0.1, function()
		if not IsValid(panel) then return end
		panel:SetPaintedManually(true)
		if panel:GetName() == "DMenu" then
			--temporary hack because paintmanual doesnt seem to work on the dmenu for some reason
			panel = panel:GetChildren()[1]
			panel.Paint = function(self, w, h)
				surface.SetDrawColor(150, 149, 160)
				surface.DrawRect(0, 0, w, h)
			end
		end

		if panel:GetName() == "DImage" then
			--temporary hack because paintmanual doesnt seem to work on the dmenu for some reason
			panel = panel:GetChildren()[1]
			panel.Paint = function(self, w, h)
				surface.SetDrawColor(175, 174, 187)
				surface.DrawRect(0, 0, w, h)
			end
		end

		if panel:GetName() == "DPanel" then
			panel = panel:GetChildren()[1]
			panel.Paint = function(self, w, h)
				surface.SetDrawColor(175, 174, 187)
				surface.DrawRect(0, 0, w, h)
			end
		end

		local panelWidth, panelHeight = ScrW(), ScrH()
		VRUtilMenuOpen(uid, panelWidth, panelHeight, panel, true, Vector(20, 11, 8), Angle(0, -90, 50), 0.03, true, function()
			timer.Simple(0.1, function()
				if not g_VR.active and IsValid(panel) then
					panel:MakePopup() --make sure we don't leave unclickable panels open when exiting vr
					panel:RequestFocus()
				end
			end)

			popupCount = popupCount - 1
			-- Remove the popup from the list when it closes
			for i, v in ipairs(allPopups) do
				if v == uid then
					table.remove(allPopups, i)
					break
				end
			end
		end)

		popupCount = popupCount + 1
		VRUtilMenuRenderPanel(uid)
	end)
end

-- Render all popups every frame
hook.Add("Think", "update_all_popups", function()
	for _, uid in ipairs(allPopups) do
		VRUtilMenuRenderPanel(uid)
	end
end)