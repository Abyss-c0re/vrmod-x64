if SERVER then return end
-- =============================================================================
-- Map Browser
--   VR session  → Cube ThemeLive (united UI)
--   Desktop     → original stock grey/blue paints (no regression)
-- =============================================================================

local window = nil

local function inVR()
	return g_VR and g_VR.active and true or false
end

local function theme()
	local C = vrmod and vrmod.cube
	local T = (C and C.ThemeLive and C.ThemeLive()) or (C and C.Theme) or {}
	return C, T
end

local function font(name, fallback)
	local C = vrmod and vrmod.cube
	if C and C.Font then
		local f = C.Font(name)
		if f then return f end
	end
	return fallback
end

local function col(T, key, r, g, b, a)
	local c = T and T[key]
	if c then return c end
	return Color(r, g, b, a or 255)
end

--- Build sorted map catalog (shared by both paint modes)
local function buildSortedMaps()
	local sortedMaps = {}
	local mapCategories = {
		["Age of Chivalry"] = {"aoc_"},
		["INFRA"] = {"infra_"},
		["Alien Swarm"] = {"^asi-", "lobby"},
		["Blade Symphony"] = {"cp_docks", "cp_parkour", "cp_sequence", "cp_terrace", "cp_test", "duel_", "ffa_community", "free_", "practice_box", "tut_training", "lightstyle_test"},
		["Counter-Strike"] = {"ar_", "cs_", "de_", "es_", "fy_", "gd_", "dz_", "training1"},
		["Day Of Defeat"] = {"dod_"},
		["Dino D-Day"] = {"ddd_"},
		["DIPRIP"] = {"de_dam", "dm_city", "dm_refinery", "dm_supermarket", "dm_village", "ur_city", "ur_refinery", "ur_supermarket", "ur_village"},
		["Dystopia"] = {"dys_", "pb_dojo", "pb_rooftop", "pb_round", "pb_urbandome", "sav_dojo6", "varena"},
		["Half-Life 2"] = {"d1_", "d2_", "d3_"},
		["Half-Life 2: Deathmatch"] = {"dm_", "halls3"},
		["Half-Life 2: Episode 1"] = {"ep1_"},
		["Half-Life 2: Episode 2"] = {"ep2_"},
		["Half-Life 2: Episode 3"] = {"ep3_"},
		["Half-Life 2: Lost Coast"] = {"d2_lostcoast"},
		["Half-Life"] = {"^c[%d]a", "^t0a"},
		["Half-Life Deathmatch"] = {"boot_camp", "bounce", "crossfire", "datacore", "frenzy", "lambda_bunker", "rapidcore", "snarkpit", "stalkyard", "subtransit", "undertow"},
		["Insurgency"] = {"ins_"},
		["Left 4 Dead"] = {"l4d_"},
		["Left 4 Dead 2"] = {"^c[%d]m", "^c1[%d]m", "curling_stadium", "tutorial_standards", "tutorial_standards_vs"},
		["Nuclear Dawn"] = {"clocktower", "coast", "downtown", "gate", "hydro", "metro", "metro_training", "oasis", "oilfield", "silo", "sk_metro", "training"},
		["Pirates, Vikings, & Knights II"] = {"bt_", "lts_", "te_", "tw_"},
		["Portal"] = {"escape_", "testchmb_"},
		["Portal 2"] = {"e1912", "^mp_coop_", "^sp_a"},
		["Team Fortress 2"] = {"achievement_", "arena_", "cp_", "ctf_", "itemtest", "koth_", "mvm_", "pl_", "plr_", "rd_", "pd_", "sd_", "tc_", "tr_", "trade_", "pass_"},
		["Zombie Panic! Source"] = {"zpa_", "zpl_", "zpo_", "zps_", "zph_"},
		["Bunny Hop"] = {"bhop_"},
		["Cinema"] = {"cinema_", "theater_"},
		["Climb"] = {"xc_"},
		["Deathrun"] = {"deathrun_", "dr_"},
		["Flood"] = {"fm_"},
		["GMod Tower"] = {"gmt_"},
		["Gun Game"] = {"gg_", "scoutzknivez"},
		["Jailbreak"] = {"ba_", "jail_", "jb_"},
		["Minigames"] = {"mg_"},
		["Pirate Ship Wars"] = {"pw_"},
		["Prop Hunt"] = {"ph_"},
		["Roleplay"] = {"rp_"},
		["Sled Build"] = {"slb_"},
		["Spacebuild"] = {"sb_"},
		["Stop it Slender"] = {"slender_"},
		["Stranded"] = {"gms_"},
		["Surf"] = {"surf_"},
		["The Stalker"] = {"ts_"},
		["Zombie Survival"] = {"zm_", "zombiesurvival_", "zs_"},
	}

	local ignore = {"^background", "^devtest", "^ep1_background", "^ep2_background", "^styleguide", "sdk_", "test_", "vst_", "c4a1y", "credits", "d2_coast_02", "d3_c17_02_camera", "ep1_citadel_00_demo", "intro", "test"}
	local gamemodes = engine.GetGamemodes()
	for i = 1, #gamemodes do
		mapCategories[gamemodes[i].title] = mapCategories[gamemodes[i].title] or {}
		local patterns = string.Split(gamemodes[i].maps, "|")
		for j = 1, #patterns do
			if patterns[j] == "" then continue end
			patterns[j] = string.lower(patterns[j])
			local found = false
			for k = 1, #mapCategories[gamemodes[i].title] do
				if mapCategories[gamemodes[i].title][k] == patterns[j] then
					found = true
					break
				end
			end
			if not found then mapCategories[gamemodes[i].title][#mapCategories[gamemodes[i].title] + 1] = patterns[j] end
		end
	end

	local files, _ = file.Find("maps/*", "GAME")
	for i = 1, #files do
		if not string.find(files[i], ".bsp$") then continue end
		local cont = false
		for j = 1, #ignore do
			if string.find(files[i], ignore[j]) then
				cont = true
				break
			end
		end
		if cont then continue end
		local category = "Other"
		for k, v in pairs(mapCategories) do
			for j = 1, #v do
				if string.find(files[i], v[j]) then
					category = k
					break
				end
			end
		end
		local index = nil
		for j = 1, #sortedMaps do
			if sortedMaps[j].category == category then
				index = j
				break
			end
		end
		if not index then
			index = #sortedMaps + 1
			sortedMaps[index] = { ["category"] = category }
		end
		sortedMaps[index][#sortedMaps[index] + 1] = {
			["filename"] = files[i],
			["name"] = string.sub(files[i], 1, #files[i] - 4),
			["icon"] = Material("maps/thumb/" .. string.sub(files[i], 1, #files[i] - 4) .. ".png")
		}
		if sortedMaps[index][#sortedMaps[index]].icon:IsError() then
			sortedMaps[index][#sortedMaps[index]].icon = Material("materials/gui/noicon.png")
		end
	end
	if #sortedMaps == 0 then
		sortedMaps[1] = { category = "Other" }
	end
	return sortedMaps
end

function VRUtilCreateMapBrowserWindow()
	if IsValid(window) then
		window:MakePopup()
		-- Sync Cube derma only while VR; never leave Cube skin on desktop reopen
		if inVR() and vrmod.cube and vrmod.cube.ApplyDermaSkin then
			vrmod.cube.ApplyDermaSkin(window)
		elseif vrmod.cube and vrmod.cube.RestoreDermaSkin then
			vrmod.cube.RestoreDermaSkin(window)
		end
		return window
	end

	local sortedMaps = buildSortedMaps()
	local selectedCategory = 1
	local categoryLists = {}
	local selectedMap = sortedMaps[1] and sortedMaps[1][1] or nil

	window = vgui.Create("DFrame")
	window:SetPos(0, 0)
	window:SetSize(915, 512)
	window:SetDraggable(true)
	window:ShowCloseButton(true)
	window:MakePopup()
	window._mapBrowser = true

	-- Title: stock label on desktop; empty under Cube chrome in VR
	if inVR() then
		window:SetTitle("")
		window:DockPadding(8, 40, 8, 8)
	else
		window:SetTitle("VRMod Map Browser")
		window:DockPadding(5, 28, 5, 5)
	end

	function window:Paint(w, h)
		if inVR() then
			local C, T = theme()
			if C and C.DrawChrome then
				C.DrawChrome(0, 0, w, h, "MAP BROWSER", {
					subtitle = T.presetLabel or "CUBE",
					pad = 12,
					headerH = 36,
				})
			else
				surface.SetDrawColor(12, 6, 10, 245)
				surface.DrawRect(0, 0, w, h)
				surface.SetDrawColor(196, 30, 58, 255)
				surface.DrawRect(0, 0, w, 4)
				draw.SimpleText("MAP BROWSER", "DermaLarge", 12, 10, Color(196, 30, 58), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
			end
		else
			-- Stock desktop frame (pre-Cube)
			surface.SetDrawColor(255, 255, 255, 255)
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(80, 80, 80, 255)
			surface.DrawRect(0, 0, w, 28)
		end
	end

	if inVR() and vrmod.cube and vrmod.cube.ApplyDermaSkin then
		vrmod.cube.ApplyDermaSkin(window)
	end

	--########################## left side ############################
	local DPanel = vgui.Create("DPanel", window)
	DPanel:SetSize(200, 0)
	DPanel:DockMargin(0, inVR() and 4 or 10, inVR() and 8 or 0, 0)
	DPanel:Dock(LEFT)
	function DPanel:Paint(w, h)
		if not inVR() then return end -- stock: no side panel fill
		local _, T = theme()
		surface.SetDrawColor(col(T, "bgGlass", 22, 10, 16, 230))
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(col(T, "crimsonDim", 120, 20, 40, 220))
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end
	if not inVR() then
		DPanel:SetPaintBackground(false)
	end

	local DScrollPanel = vgui.Create("DScrollPanel", DPanel)
	DScrollPanel:SetSize(200, 0)
	DScrollPanel:Dock(FILL)
	if inVR() then DScrollPanel:DockMargin(4, 4, 4, 4) end

	local catFont = font("CubeSmall", "Trebuchet18")
	local labelFont = font("CubeLabel", "Trebuchet24")
	local mapNameFont = font("CubeSmall", "DermaDefault")

	for i = 1, #sortedMaps do
		local DButton = DScrollPanel:Add("DButton")
		DButton:SetText("")
		DButton:Dock(TOP)
		DButton:SetSize(0, inVR() and 28 or 25)
		DButton:DockMargin(0, 0, 0, inVR() and 4 or 5)
		function DButton:Paint(w, h)
			if inVR() then
				local C, T = theme()
				local selected = (selectedCategory == i)
				if C and C.DrawSlot then
					C.DrawSlot(0, 0, w, h, nil, self.Hovered, selected, true)
				else
					local bg = selected and col(T, "btnHover", 100, 22, 38, 255) or col(T, "btn", 55, 14, 24, 250)
					surface.SetDrawColor(bg)
					surface.DrawRect(0, 0, w, h)
					if selected then
						surface.SetDrawColor(col(T, "crimson", 196, 30, 58, 255))
						surface.DrawRect(0, 0, 4, h)
					end
				end
				draw.SimpleText(sortedMaps[i].category, catFont, 10, h * 0.5, col(T, "text", 255, 240, 244, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			else
				-- Original desktop paints
				if selectedCategory == i then
					surface.SetDrawColor(153, 204, 255, 255)
				else
					surface.SetDrawColor(221, 221, 221, 255)
				end
				surface.DrawRect(0, 0, w, h)
				draw.SimpleText(sortedMaps[i].category, "Trebuchet18", 5, 5, Color(85, 85, 85, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
			end
		end
		function DButton:DoClick()
			if categoryLists[selectedCategory] then categoryLists[selectedCategory]:SetVisible(false) end
			selectedCategory = i
			if categoryLists[selectedCategory] then categoryLists[selectedCategory]:SetVisible(true) end
		end
	end

	local startBtn = vgui.Create("DButton", DPanel)
	startBtn:SetText("")
	startBtn:Dock(BOTTOM)
	startBtn:SetSize(25, inVR() and 44 or 40)
	if inVR() then startBtn:DockMargin(4, 6, 4, 4) end
	function startBtn:DoClick()
		if not selectedMap or not selectedMap.name then return end
		RunConsoleCommand("vrmod_autostart", "1")
		RunConsoleCommand("changelevel", selectedMap.name)
	end
	function startBtn:Paint(w, h)
		if inVR() then
			local C, T = theme()
			local ok = selectedMap ~= nil
			local hot = self.Hovered and ok
			if C and C.DrawSlot then
				C.DrawSlot(0, 0, w, h, nil, hot, ok, ok)
			else
				local bg = ok and (hot and col(T, "btnHover", 100, 22, 38, 255) or col(T, "crimson", 196, 30, 58, 255)) or col(T, "btnDim", 30, 10, 16, 220)
				surface.SetDrawColor(bg)
				surface.DrawRect(0, 0, w, h)
			end
			local label = selectedMap and ("START · " .. string.upper(string.sub(selectedMap.name, 1, 18))) or "SELECT MAP"
			draw.SimpleText(label, labelFont, w * 0.5, h * 0.5, col(T, "text", 255, 240, 244, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		else
			surface.SetDrawColor(0, 108, 204, 255)
			surface.DrawRect(0, 0, w, h)
			draw.SimpleText("Start Game", "Trebuchet24", w / 2, h / 2, Color(255, 255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end

	--########################## right side ############################
	for i = 1, #sortedMaps do
		local mapScroll = vgui.Create("DScrollPanel", window)
		mapScroll:DockMargin(inVR() and 0 or 10, inVR() and 4 or 10, 0, 0)
		mapScroll:Dock(FILL)
		mapScroll:SetVisible(i == 1)
		function mapScroll:Paint(w, h)
			if not inVR() then return end
			local _, T = theme()
			surface.SetDrawColor(col(T, "panel", 36, 12, 18, 240))
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(col(T, "crimsonDim", 120, 20, 40, 220))
			surface.DrawOutlinedRect(0, 0, w, h, 1)
		end
		categoryLists[#categoryLists + 1] = mapScroll
		local List = vgui.Create("DIconLayout", mapScroll)
		List:Dock(FILL)
		if inVR() then List:DockMargin(6, 6, 6, 6) end
		List:SetSpaceY(inVR() and 6 or 5)
		List:SetSpaceX(inVR() and 6 or 5)
		for j = 1, #sortedMaps[i] do
			local mapEntry = sortedMaps[i][j]
			local ListItem = List:Add("DButton")
			ListItem:SetSize(130, inVR() and 148 or 145)
			ListItem:SetText("")
			ListItem.DoClick = function() selectedMap = mapEntry end
			function ListItem:Paint(w, h)
				if inVR() then
					local _, T = theme()
					local selected = (selectedMap == mapEntry)
					local hot = self.Hovered or selected
					surface.SetDrawColor(col(T, hot and "btnHover" or "btn", 55, 14, 24, 250))
					surface.DrawRect(0, 0, w, h)
					surface.SetDrawColor(col(T, selected and "crimsonHot" or "crimsonDim", 120, 20, 40, 220))
					surface.DrawOutlinedRect(0, 0, w, h, selected and 3 or 2)
					if selected or hot then
						surface.SetDrawColor(col(T, "crimson", 196, 30, 58, 255))
						surface.DrawRect(0, 0, 4, h)
					end
					surface.SetDrawColor(255, 255, 255, 255)
					surface.SetMaterial(mapEntry.icon)
					surface.DrawTexturedRect(4, 4, w - 8, w - 8)
					surface.SetDrawColor(col(T, "bg", 12, 6, 10, 245))
					surface.DrawRect(2, w - 2, w - 4, h - (w - 2))
					draw.SimpleText(mapEntry.name, mapNameFont, w * 0.5, h - 8, col(T, "text", 255, 240, 244, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
				else
					if selectedMap == mapEntry then
						surface.SetDrawColor(151, 197, 255, 255)
						surface.DrawRect(0, 0, w, h)
					end
					surface.SetDrawColor(255, 255, 255, 255)
					surface.SetMaterial(mapEntry.icon)
					surface.DrawTexturedRect(2, 2, w - 4, w - 4)
					draw.SimpleText(mapEntry.name, "DermaDefault", w / 2, h - 2, Color(0, 0, 0, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
				end
			end
		end
	end

	if inVR() and vrmod.cube and vrmod.cube.ApplyDermaSkin then
		timer.Simple(0, function()
			if IsValid(window) and inVR() then vrmod.cube.ApplyDermaSkin(window) end
		end)
	end

	-- If player exits VR while window open, drop Cube derma skin
	hook.Add("VRMod_Exit", "vrmod_mapbrowser_skin", function()
		if IsValid(window) and vrmod.cube and vrmod.cube.RestoreDermaSkin then
			vrmod.cube.RestoreDermaSkin(window)
		end
	end)

	return window
end
