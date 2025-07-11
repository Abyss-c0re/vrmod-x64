-- vr_viewmodel_config.lua
if CLIENT then
	g_VR.viewModelInfo = g_VR.viewModelInfo or {}
	-- Default hardcoded offsets and overrides
	local DEFAULT_VIEWMODEL_INFO = {
		autoOffsetAddPos = Vector(1, 0.2, 0),
		gmod_tool = {
			--modelOverride = "models/weapons/w_toolgun.mdl",
			offsetPos = Vector(-12, 6.5, 7),
			offsetAng = Angle(0, 0, 0),
			wrongMuzzleAng = false,
			noLaser = false
		},
		weapon_physgun = {
			offsetPos = Vector(-34.5, 13.4, 14.5),
			offsetAng = Angle(0, 0, 0),
			wrongMuzzleAng = false,
			noLaser = true
		},
		weapon_physcannon = {
			offsetPos = Vector(-34.5, 13.4, 10.5),
			offsetAng = Angle(0, 0, 0),
			wrongMuzzleAng = false,
			noLaser = true
		},
		weapon_shotgun = {
			offsetPos = Vector(-14.5, 10, 8.5),
			offsetAng = Angle(0, 0, 0),
			wrongMuzzleAng = false,
			noLaser = false
		},
		weapon_rpg = {
			offsetPos = Vector(-27.5, 19, 10.5),
			offsetAng = Angle(0, 0, 0),
			wrongMuzzleAng = false,
			noLaser = true
		},
		arcticvr_hl2_rpg = {
			offsetPos = Vector(),
			offsetAng = Angle(),
			wrongMuzzleAng = false,
			noLaser = true
		},
		weapon_crossbow = {
			offsetPos = Vector(-14.5, 10, 8.5),
			offsetAng = Angle(0, 0, 0),
			wrongMuzzleAng = false,
			noLaser = true
		},
		weapon_medkit = {
			offsetPos = Vector(-23, 10, 5),
			offsetAng = Angle(0, 0, 0),
			wrongMuzzleAng = false,
			noLaser = false
		},
		weapon_crowbar = {
			offsetPos = Vector(),
			offsetAng = Angle(),
			wrongMuzzleAng = true,
			noLaser = false
		},
		arcticvr_hl2_crowbar = {
			offsetPos = Vector(),
			offsetAng = Angle(),
			wrongMuzzleAng = false,
			noLaser = true
		},
		weapon_stunstick = {
			offsetPos = Vector(),
			offsetAng = Angle(),
			wrongMuzzleAng = true,
			noLaser = false
		},
		arcticvr_hl2_stunstick = {
			offsetPos = Vector(),
			offsetAng = Angle(),
			wrongMuzzleAng = false,
			noLaser = true
		},
		arcticvr_hl2_knife = {
			offsetPos = Vector(),
			offsetAng = Angle(),
			wrongMuzzleAng = false,
			noLaser = true
		},
		arcticvr_hl2_cmbsniper = {
			offsetPos = Vector(),
			offsetAng = Angle(),
			wrongMuzzleAng = false,
			noLaser = true
		},
		laserpointer = {
			offsetPos = Vector(),
			offsetAng = Angle(),
			wrongMuzzleAng = false,
			noLaser = true
		},
		seal6_c4 = {
			offsetPos = Vector(),
			offsetAng = Angle(),
			wrongMuzzleAng = false,
			noLaser = true
		},
		seal6_bottle = {
			offsetPos = Vector(),
			offsetAng = Angle(),
			wrongMuzzleAng = false,
			noLaser = true
		},
		seal6_doritos = {
			offsetPos = Vector(),
			offsetAng = Angle(),
			wrongMuzzleAng = false,
			noLaser = true
		},
		weapon_bomb = {
			offsetPos = Vector(),
			offsetAng = Angle(),
			wrongMuzzleAng = false,
			noLaser = true
		},
		weapon_c4 = {
			offsetPos = Vector(),
			offsetAng = Angle(),
			wrongMuzzleAng = false,
			noLaser = true
		},
		weapon_vfire_gascan = {
			offsetPos = Vector(),
			offsetAng = Angle(),
			wrongMuzzleAng = false,
			noLaser = true
		},
		weapon_extinguisher_infinte = {
			offsetPos = Vector(),
			offsetAng = Angle(),
			wrongMuzzleAng = false,
			noLaser = true
		},
		weapon_extinguisher = {
			offsetPos = Vector(),
			offsetAng = Angle(),
			wrongMuzzleAng = false,
			noLaser = true
		},
		weapon_slam = {
			offsetPos = Vector(),
			offsetAng = Angle(),
			wrongMuzzleAng = true,
			noLaser = false
		},
		weapon_microwaverifle = {
			offsetPos = Vector(-9, 6.5, 10),
			offsetAng = Angle(0, 0, 0),
			wrongMuzzleAng = false,
			noLaser = false
		},
		weapon_vfirethrower = {
			offsetPos = Vector(13, 2, -6),
			offsetAng = Angle(0, 0, 0),
			wrongMuzzleAng = true,
			noLaser = false
		},
		weapon_newtphysgun = {
			offsetPos = Vector(-34.5, 13.4, 14.5),
			offsetAng = Angle(0, 0, 0),
			wrongMuzzleAng = false,
			noLaser = true
		},
	}

	local CONFIG_PATH = "vrmod/viewmodelinfo.json"
	g_VR = g_VR or {}
	local function SaveViewModelConfig()
		file.Write(CONFIG_PATH, util.TableToJSON(g_VR.viewModelInfo, true))
	end

	local function LoadViewModelConfig()
		-- Load saved config (if any)
		if file.Exists(CONFIG_PATH, "DATA") then
			local loaded = util.JSONToTable(file.Read(CONFIG_PATH, "DATA")) or {}
			for cls, data in pairs(loaded) do
				g_VR.viewModelInfo[cls] = data
			end
		else
			-- If no saved config, merge in defaults
			for cls, data in pairs(DEFAULT_VIEWMODEL_INFO) do
				if not g_VR.viewModelInfo[cls] then g_VR.viewModelInfo[cls] = data end
			end

			-- Save this as the initial config
			SaveViewModelConfig()
		end

		-- Reflect g_VR into local viewModelConfig (for editor)
		viewModelConfig = table.Copy(g_VR.viewModelInfo)
	end

	-- Initialize on VR start
	hook.Add("VRMod_Start", "InitializeViewModelSettings", function()
		LoadViewModelConfig()
		for cls, data in pairs(g_VR.viewModelInfo) do
			if data.offsetPos and data.offsetAng then vrmod.SetViewModelOffsetForWeaponClass(cls, data.offsetPos, data.offsetAng) end
			if data.modelOverride then vrmod.SetViewModelModelOverride(cls, data.modelOverride) end
			if data.wrongMuzzleAng then vrmod.SetViewModelFixMuzzle(cls, data.wrongMuzzleAng) end
			if data.noLaser then vrmod.SetViewModelNoLaser(cls, data.noLaser) end
		end
	end)

	LoadViewModelConfig()
	function CreateWeaponConfigGUI()
		local frame = vgui.Create("DFrame")
		frame:SetSize(600, 400)
		frame:Center()
		frame:SetTitle("Weapon ViewModel Configuration")
		frame:MakePopup()
		local listview = vgui.Create("DListView", frame)
		listview:Dock(FILL)
		listview:AddColumn("Weapon Class")
		listview:AddColumn("Offset Position")
		listview:AddColumn("Offset Angle")
		local function UpdateListView()
			if not g_VR.viewModelInfo then return end
			listview:Clear()
			for class, data in pairs(g_VR.viewModelInfo) do
				listview:AddLine(class, tostring(data.offsetPos), tostring(data.offsetAng))
			end
		end

		UpdateListView()
		local addButton = vgui.Create("DButton", frame)
		addButton:SetText("New")
		addButton:Dock(BOTTOM)
		addButton.DoClick = function()
			local currentWeapon = LocalPlayer():GetActiveWeapon()
			if IsValid(currentWeapon) then
				CreateAddWeaponConfigGUI(currentWeapon:GetClass())
				frame:Close()
			end
		end

		local editButton = vgui.Create("DButton", frame)
		editButton:SetText("Edit")
		editButton:Dock(BOTTOM)
		editButton.DoClick = function()
			local selected = listview:GetSelectedLine()
			if selected then
				local class = listview:GetLine(selected):GetValue(1)
				CreateAddWeaponConfigGUI(class, true)
				frame:Close()
			end
		end

		local deleteButton = vgui.Create("DButton", frame)
		deleteButton:SetText("Delete")
		deleteButton:Dock(BOTTOM)
		deleteButton.DoClick = function()
			local selected = listview:GetSelectedLine()
			if selected then
				local class = listview:GetLine(selected):GetValue(1)
				g_VR.viewModelInfo[class] = nil
				UpdateListView()
				SaveViewModelConfig()
			end
		end
	end

	function CreateAddWeaponConfigGUI(class, isEditing)
		local frame = vgui.Create("DFrame")
		frame:SetSize(300, 300)
		frame:Center()
		frame:SetTitle(isEditing and "Edit ViewModel Config" or "Add ViewModel Config")
		frame:MakePopup()
		local data = g_VR.viewModelInfo[class] or {
			offsetPos = Vector(),
			offsetAng = Angle()
		}

		local originalData = table.Copy(data)
		-- Offset Position
		local posPanel = vgui.Create("DPanel", frame)
		posPanel:Dock(TOP)
		posPanel:SetHeight(100)
		posPanel:SetPaintBackground(false)
		local posLabel = vgui.Create("DLabel", posPanel)
		posLabel:SetText("Offset Position:")
		posLabel:Dock(TOP)
		local posSliders = {}
		for i, axis in ipairs({"X", "Y", "Z"}) do
			local slider = vgui.Create("DNumSlider", posPanel)
			slider:Dock(TOP)
			slider:SetText(axis)
			slider:SetMin(-100)
			slider:SetMax(100)
			slider:SetValue(data.offsetPos[i])
			slider:SetDecimals(3)
			posSliders[i] = slider
		end

		-- Offset Angle
		local angPanel = vgui.Create("DPanel", frame)
		angPanel:Dock(TOP)
		angPanel:SetHeight(100)
		angPanel:SetPaintBackground(false)
		local angLabel = vgui.Create("DLabel", angPanel)
		angLabel:SetText("Offset Angle:")
		angLabel:Dock(TOP)
		local angSliders = {}
		for i, axis in ipairs({"P", "Y", "R"}) do
			local slider = vgui.Create("DNumSlider", angPanel)
			slider:Dock(TOP)
			slider:SetText(axis)
			slider:SetMin(-180)
			slider:SetMax(180)
			slider:SetValue(data.offsetAng[i])
			slider:SetDecimals(3)
			angSliders[i] = slider
		end

		-- Offset Position
		for i, slider in ipairs(posSliders) do
			slider.OnValueChanged = function()
				local pos = Vector(posSliders[1]:GetValue(), posSliders[2]:GetValue(), posSliders[3]:GetValue())
				local ang = Angle(angSliders[1]:GetValue(), angSliders[2]:GetValue(), angSliders[3]:GetValue())
				vrmod.SetViewModelOffsetForWeaponClass(class, pos, ang)
			end
		end

		-- Offset Angle
		for i, slider in ipairs(angSliders) do
			slider.OnValueChanged = function()
				local pos = Vector(posSliders[1]:GetValue(), posSliders[2]:GetValue(), posSliders[3]:GetValue())
				local ang = Angle(angSliders[1]:GetValue(), angSliders[2]:GetValue(), angSliders[3]:GetValue())
				vrmod.SetViewModelOffsetForWeaponClass(class, pos, ang)
			end
		end

		local applyButton = vgui.Create("DButton", frame)
		applyButton:SetText("Apply")
		applyButton:Dock(BOTTOM)
		applyButton.DoClick = function()
			data.offsetPos = Vector(posSliders[1]:GetValue(), posSliders[2]:GetValue(), posSliders[3]:GetValue())
			data.offsetAng = Angle(angSliders[1]:GetValue(), angSliders[2]:GetValue(), angSliders[3]:GetValue())
			vrmod.SetViewModelOffsetForWeaponClass(class, data.offsetPos, data.offsetAng)
			g_VR.viewModelInfo[class] = data
			SaveViewModelConfig()
			frame:Close()
		end

		local cancelButton = vgui.Create("DButton", frame)
		vrmod.SetViewModelOffsetForWeaponClass(class, originalData.offsetPos, originalData.offsetAng)
		cancelButton:SetText("Cancel")
		cancelButton:Dock(BOTTOM)
		cancelButton.DoClick = function() frame:Close() end
	end

	-- GUI
	concommand.Add("vrmod_weaponconfig", function()
		if not g_VR.viewModelInfo then LoadViewModelConfig() end
		CreateWeaponConfigGUI()
	end)
end