if SERVER then return end
local window = nil
local function CreateMapBrowserWindow()
	if IsValid(window) then return window end
	window = vgui.Create("DFrame")
	window:SetPos(0, 0)
	window:SetSize(915, 512)
	window:SetTitle("VRMod Map Browser")
	window:MakePopup()
	function window:Paint(w, h)
		surface.SetDrawColor(255, 255, 255, 255)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(80, 80, 80, 255)
		surface.DrawRect(0, 0, w, 28)
	end

	--########################## pre processing ############################
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

	--PrintTable(mapCategories)
	local files, dirs = file.Find("maps/*", "GAME")
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
			sortedMaps[index] = {
				["category"] = category
			}
		end

		sortedMaps[index][#sortedMaps[index] + 1] = {
			["filename"] = files[i],
			["name"] = string.sub(files[i], 1, #files[i] - 4),
			["icon"] = Material("maps/thumb/" .. string.sub(files[i], 1, #files[i] - 4) .. ".png")
		}

		if sortedMaps[index][#sortedMaps[index]].icon:IsError() then sortedMaps[index][#sortedMaps[index]].icon = Material("materials/gui/noicon.png") end
	end

	--PrintTable(sortedMaps)
	local selectedCategory = 1
	local categoryLists = {}
	local selectedMap = sortedMaps[1][1]
	--########################## left side ############################
	local DPanel = vgui.Create("DPanel", window)
	DPanel:SetSize(200, 0)
	DPanel:DockMargin(0, 10, 0, 0)
	DPanel:Dock(LEFT)
	DPanel:SetPaintBackground(false)
	local DScrollPanel = vgui.Create("DScrollPanel", DPanel)
	DScrollPanel:SetSize(200, 0)
	DScrollPanel:Dock(FILL)
	for i = 1, #sortedMaps do
		local DButton = DScrollPanel:Add("DButton")
		DButton:SetText("")
		DButton:Dock(TOP)
		DButton:SetSize(0, 25)
		DButton:DockMargin(0, 0, 0, 5)
		function DButton:Paint(w, h)
			if selectedCategory == i then
				surface.SetDrawColor(153, 204, 255, 255)
			else
				surface.SetDrawColor(221, 221, 221, 255)
			end

			surface.DrawRect(0, 0, w, h)
			draw.SimpleText(sortedMaps[i].category, "Trebuchet18", 5, 5, Color(85, 85, 85, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		end

		function DButton:DoClick()
			categoryLists[selectedCategory]:SetVisible(false)
			selectedCategory = i
			categoryLists[selectedCategory]:SetVisible(true)
		end
	end

	local DButton = vgui.Create("DButton", DPanel)
	DButton:SetText("")
	DButton:Dock(BOTTOM)
	DButton:SetSize(25, 40)
	function DButton:DoClick()
		if g_VR.active then GetConVar("vrmod_autostart"):SetBool(true) end
		RunConsoleCommand("map", selectedMap.filename)
	end

	function DButton:Paint(w, h)
		surface.SetDrawColor(0, 108, 204, 255)
		surface.DrawRect(0, 0, w, h)
		draw.SimpleText("Start Game", "Trebuchet24", w / 2, h / 2, Color(255, 255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	--########################## right side ############################
	for i = 1, #sortedMaps do
		local DScrollPanel = vgui.Create("DScrollPanel", window)
		DScrollPanel:DockMargin(10, 10, 0, 0)
		DScrollPanel:Dock(FILL)
		DScrollPanel:SetVisible(i == 1 and true or false)
		categoryLists[#categoryLists + 1] = DScrollPanel
		local List = vgui.Create("DIconLayout", DScrollPanel)
		List:Dock(FILL)
		List:SetSpaceY(5)
		List:SetSpaceX(5)
		for j = 1, #sortedMaps[i] do
			local ListItem = List:Add("DButton")
			ListItem:SetSize(130, 145)
			ListItem:SetText("")
			ListItem.DoClick = function() selectedMap = sortedMaps[i][j] end
			function ListItem:Paint(w, h)
				if selectedMap == sortedMaps[i][j] then
					surface.SetDrawColor(151, 197, 255, 255)
					surface.DrawRect(0, 0, w, h)
				end

				surface.SetDrawColor(255, 255, 255, 255)
				surface.SetMaterial(sortedMaps[i][j].icon)
				surface.DrawTexturedRect(2, 2, w - 4, w - 4)
				draw.SimpleText(sortedMaps[i][j].name, "DermaDefault", w / 2, h - 2, Color(0, 0, 0, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
			end
		end
	end
	return window
end

vrmod.AddInGameMenuItem("Map Browser", 0, 0, function()
	CreateMapBrowserWindow()
	hook.Add("VRMod_OpenQuickMenu", "closemapbrowser", function()
		hook.Remove("VRMod_OpenQuickMenu", "closemapbrowser")
		if IsValid(window) then
			window:Remove()
			return false
		end
	end)
end)