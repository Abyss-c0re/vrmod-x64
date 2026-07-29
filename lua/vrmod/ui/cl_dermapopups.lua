if SERVER then return end

local meta = getmetatable(vgui.GetWorldPanel())
local orig = meta.MakePopup

local allPopups = {}
-- Weak-keyed map so the same panel instance reuses one uid (re-open replaces, no collision)
local panelUids = setmetatable({}, {
	__mode = "k"
})
local popupSeq = 0

-- Unique per panel instance. Name alone collides (two DMenus → one uid, last wins).
local function getPanelIdentifier(panel)
	if not IsValid(panel) then return "popup_unknown" end
	local existing = panelUids[panel]
	if existing then return existing end
	popupSeq = popupSeq + 1
	local name = panel:GetName() or "Panel"
	name = name:lower():gsub("[^%w]", "")
	if name == "" then name = "panel" end
	local uid = "popup_" .. name .. "_" .. popupSeq
	panelUids[panel] = uid
	return uid
end

-- Overwrite MakePopup
meta.MakePopup = function(...)
	local args = {...}
	orig(unpack(args))
	if not g_VR.threePoints then return end

	local panel = args[1]
	if not IsValid(panel) then return end

	local uid = getPanelIdentifier(panel)
	allPopups[uid] = panel

	timer.Simple(0.1, function()
		if not IsValid(panel) then return end
		panel:SetPaintedManually(true)

		local paintPanel = panel
		local name = panel:GetName()
		if name == "DMenu" or name == "DImage" or name == "DPanel" then
			local child = panel:GetChildren()[1]
			if IsValid(child) then
				paintPanel = child
				paintPanel.Paint = function(self, w, h)
					surface.SetDrawColor(175, 174, 187)
					surface.DrawRect(0, 0, w, h)
				end
			end
		end

		local panelWidth, panelHeight = ScrW(), ScrH()
		VRUtilMenuOpen(uid, panelWidth, panelHeight, paintPanel, true, Vector(10, 10, 5), Angle(0, -90, 50), 0.03, true, function()
			timer.Simple(0.1, function()
				if not g_VR.active and IsValid(panel) then
					panel:MakePopup()
					panel:RequestFocus()
				end
			end)
			-- Cleanup
			allPopups[uid] = nil
			if panelUids[panel] == uid then panelUids[panel] = nil end
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
