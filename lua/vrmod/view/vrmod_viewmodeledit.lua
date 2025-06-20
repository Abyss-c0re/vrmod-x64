if CLIENT then
	local function LoadViewModelConfig()
		if file.Exists("vrmod/viewmodelinfo.json", "DATA") then
			local json = file.Read("vrmod/viewmodelinfo.json", "DATA")
			viewModelConfig = util.JSONToTable(json)
		else
			viewModelConfig = {}
		end
	end

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
			if not viewModelConfig then return end
			listview:Clear()
			for class, data in pairs(viewModelConfig) do
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
				viewModelConfig[class] = nil
				UpdateListView()
				SaveViewModelConfig()
			end
		end
	end

	-- viewModelConfig
	viewModelConfig = viewModelConfig or {}
	local function LoadViewModelConfig()
		if file.Exists("vrmod/viewmodelinfo.json", "DATA") then
			local json = file.Read("vrmod/viewmodelinfo.json", "DATA")
			viewModelConfig = util.JSONToTable(json)
		else
			viewModelConfig = {}
		end
	end

	function CreateAddWeaponConfigGUI(class, isEditing)
		local frame = vgui.Create("DFrame")
		frame:SetSize(300, 300)
		frame:Center()
		frame:SetTitle(isEditing and "Edit ViewModel Config" or "Add ViewModel Config")
		frame:MakePopup()
		local data = viewModelConfig[class] or {
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

		-- SaveViewModelConfig
		local function SaveViewModelConfig()
			if not viewModelConfig then return end
			local json = util.TableToJSON(viewModelConfig, true) -- JSON形式で保存
			file.Write("vrmod/viewmodelinfo.json", json)
		end

		local applyButton = vgui.Create("DButton", frame)
		applyButton:SetText("Apply")
		applyButton:Dock(BOTTOM)
		applyButton.DoClick = function()
			data.offsetPos = Vector(posSliders[1]:GetValue(), posSliders[2]:GetValue(), posSliders[3]:GetValue())
			data.offsetAng = Angle(angSliders[1]:GetValue(), angSliders[2]:GetValue(), angSliders[3]:GetValue())
			vrmod.SetViewModelOffsetForWeaponClass(class, data.offsetPos, data.offsetAng)
			viewModelConfig[class] = data
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
		if not viewModelConfig then LoadViewModelConfig() end
		CreateWeaponConfigGUI()
	end)

	local function InitializeVRModViewModelSettings()
		LoadViewModelConfig()
		for classname, settings in pairs(viewModelConfig) do
			if settings.offsetPos and settings.offsetAng then vrmod.SetViewModelOffsetForWeaponClass(classname, settings.offsetPos, settings.offsetAng) end
		end
	end

	hook.Add("VRMod_Start", "InitializeViewModelSettings", InitializeVRModViewModelSettings)
end