-- vr_viewmodel_config.lua
if CLIENT then
	local CONFIG_PATH = "vrmod/vrmod_weapons_config.json"
	g_VR.viewModelInfo = g_VR.viewModelInfo or {}
	-- Default hardcoded offsets and overrides
	local DEFAULT_VIEWMODEL_INFO = {
		autoOffsetAddPos = Vector(1, 0.2, 0),
		gmod_tool = {
			offsetPos = Vector(-12, 6.5, 7),
			offsetAng = Angle(0, 0, 0),
		},
		weapon_physgun = {
			offsetPos = Vector(-34.5, 13.4, 14.5),
			offsetAng = Angle(0, 0, 0),
			noLaser = true
		},
		weapon_physcannon = {
			offsetPos = Vector(-34.5, 13.4, 10.5),
			offsetAng = Angle(0, 0, 0),
			noLaser = true
		},
		weapon_shotgun = {
			offsetPos = Vector(-14.5, 10, 8.5),
			offsetAng = Angle(0, 0, 0),
		},
		weapon_rpg = {
			offsetPos = Vector(-27.5, 19, 10.5),
			offsetAng = Angle(0, 0, 0),
			noLaser = true
		},
		arcticvr_hl2_rpg = {
			noLaser = true
		},
		weapon_crossbow = {
			offsetPos = Vector(-14.5, 10, 8.5),
			offsetAng = Angle(0, 0, 0),
		},
		weapon_medkit = {
			offsetPos = Vector(-23, 10, 5),
			offsetAng = Angle(0, 0, 0)
		},
		weapon_crowbar = {
			wrongMuzzleAng = true,
		},
		arcticvr_hl2_crowbar = {
			noLaser = true
		},
		weapon_stunstick = {
			offsetPos = Vector(3.35, 1.5, 2.5),
			offsetAng = Angle(0, -90, 0),
			wrongMuzzleAng = true
		},
		arcticvr_hl2_stunstick = {
			noLaser = true
		},
		arcticvr_hl2_knife = {
			noLaser = true
		},
		arcticvr_hl2_cmbsniper = {
			noLaser = true
		},
		laserpointer = {
			noLaser = true
		},
		seal6_c4 = {
			noLaser = true
		},
		seal6_bottle = {
			noLaser = true
		},
		seal6_doritos = {
			noLaser = true
		},
		weapon_bomb = {
			noLaser = true
		},
		weapon_c4 = {
			noLaser = true
		},
		weapon_vfire_gascan = {
			noLaser = true
		},
		weapon_extinguisher_infinte = {
			noLaser = true
		},
		weapon_extinguisher = {
			noLaser = true
		},
		weapon_slam = {
			wrongMuzzleAng = true,
		},
		weapon_microwaverifle = {
			offsetPos = Vector(-9, 6.5, 10),
			offsetAng = Angle(0, 0, 0)
		},
		weapon_vfirethrower = {
			offsetPos = Vector(13, 2, -6),
			offsetAng = Angle(0, 0, 0),
			wrongMuzzleAng = true,
		},
		weapon_newtphysgun = {
			offsetPos = Vector(-34.5, 13.4, 14.5),
			offsetAng = Angle(0, 0, 0),
			noLaser = true
		},
	}

	local function SaveViewModelConfig()
		file.Write(CONFIG_PATH, util.TableToJSON(g_VR.viewModelInfo, true))
	end

	-- Custom deep copy function to handle Vector and Angle
	local function DeepCopy(orig)
		if type(orig) == "table" then
			local copy = {}
			for k, v in pairs(orig) do
				copy[k] = DeepCopy(v)
			end
			return copy
		elseif type(orig) == "Vector" then
			return Vector(orig.x, orig.y, orig.z)
		elseif type(orig) == "Angle" then
			return Angle(orig.p, orig.y, orig.r)
		else
			return orig -- Return non-table, non-userdata values as-is
		end
	end

	local function LoadViewModelConfig()
		-- Initialize g_VR.viewModelInfo if empty
		if not next(g_VR.viewModelInfo) then
			g_VR.viewModelInfo = DeepCopy(DEFAULT_VIEWMODEL_INFO) -- Copy entire default table
		end

		-- Load saved config (if any)
		if file.Exists(CONFIG_PATH, "DATA") then
			local loaded = util.JSONToTable(file.Read(CONFIG_PATH, "DATA")) or {}
			for cls, loadedData in pairs(loaded) do
				-- Ensure the class exists in viewModelInfo, using defaults if not
				if not g_VR.viewModelInfo[cls] then g_VR.viewModelInfo[cls] = DeepCopy(DEFAULT_VIEWMODEL_INFO[cls] or {}) end
				-- Merge loaded data, only updating fields that exist
				if loadedData.offsetPos and type(loadedData.offsetPos) == "table" then g_VR.viewModelInfo[cls].offsetPos = Vector(loadedData.offsetPos[1] or 0, loadedData.offsetPos[2] or 0, loadedData.offsetPos[3] or 0) end
				if loadedData.offsetAng and type(loadedData.offsetAng) == "table" then g_VR.viewModelInfo[cls].offsetAng = Angle(loadedData.offsetAng[1] or 0, loadedData.offsetAng[2] or 0, loadedData.offsetAng[3] or 0) end
				if loadedData.wrongMuzzleAng ~= nil then g_VR.viewModelInfo[cls].wrongMuzzleAng = loadedData.wrongMuzzleAng end
				if loadedData.noLaser ~= nil then g_VR.viewModelInfo[cls].noLaser = loadedData.noLaser end
			end

			-- Handle autoOffsetAddPos separately if present in loaded config
			if loaded.autoOffsetAddPos and type(loaded.autoOffsetAddPos) == "table" then g_VR.viewModelInfo.autoOffsetAddPos = Vector(loaded.autoOffsetAddPos[1] or 0, loaded.autoOffsetAddPos[2] or 0, loaded.autoOffsetAddPos[3] or 0) end
		end

		SaveViewModelConfig()
	end

	-- Initialize on VR start
	hook.Add("VRMod_Start", "InitializeViewModelSettings", function() LoadViewModelConfig() end)
	LoadViewModelConfig()
	function CreateWeaponConfigGUI()
		RunConsoleCommand("vrmod_vgui_reset")
		local frame = vgui.Create("DFrame")
		frame:SetSize(800, 400)
		frame:Center()
		frame:SetTitle("Weapon ViewModel Configuration")
		frame:MakePopup()
		frame.OnClose = function() SaveViewModelConfig() end
		local listview = vgui.Create("DListView", frame)
		listview:Dock(FILL)
		listview:AddColumn("Weapon Class")
		listview:AddColumn("Offset Position")
		listview:AddColumn("Offset Angle")
		listview:AddColumn("Wrong Muzzle Ang")
		listview:AddColumn("No Laser")
		local function UpdateListView()
			if not g_VR.viewModelInfo then return end
			listview:Clear()
			for class, data in pairs(g_VR.viewModelInfo) do
				listview:AddLine(class, tostring(data.offsetPos), tostring(data.offsetAng), tostring(data.wrongMuzzleAng or false), tostring(data.noLaser or false))
			end
		end

		UpdateListView()
		local bottomPanel = vgui.Create("DPanel", frame)
		bottomPanel:Dock(BOTTOM)
		bottomPanel:SetTall(50)
		local leftPanel = vgui.Create("DPanel", bottomPanel)
		leftPanel:SetWide(frame:GetWide() / 2 - 10)
		leftPanel:Dock(LEFT)
		leftPanel:DockMargin(10, 5, 5, 5)
		local rightPanel = vgui.Create("DPanel", bottomPanel)
		rightPanel:SetWide(frame:GetWide() / 2 - 10)
		rightPanel:Dock(RIGHT)
		rightPanel:DockMargin(5, 5, 10, 5)
		local function AddButton(parent, txt, func)
			local btn = vgui.Create("DButton", parent)
			btn:SetText(txt)
			btn:SetSize(120, 30)
			-- Detect parent's docking and dock button accordingly
			local dock = parent:GetDock()
			if dock == LEFT then
				btn:Dock(LEFT)
				btn:DockMargin(0, 0, 10, 0)
			elseif dock == RIGHT then
				btn:Dock(RIGHT)
				btn:DockMargin(10, 0, 0, 0)
			else
				-- fallback to left dock if unknown
				btn:Dock(LEFT)
				btn:DockMargin(0, 0, 10, 0)
			end

			btn.DoClick = func
			return btn
		end

		-- Helper: update just one weapon line in listview by class
		local function UpdateListLine(class)
			local lines = listview:GetLines()
			for i, line in ipairs(lines) do
				if line:GetValue(1) == class then
					local data = g_VR.viewModelInfo[class]
					if data then
						line:SetColumnText(2, tostring(data.offsetPos))
						line:SetColumnText(3, tostring(data.offsetAng))
						line:SetColumnText(4, tostring(data.wrongMuzzleAng or false))
						line:SetColumnText(5, tostring(data.noLaser or false))
					end

					break
				end
			end
		end

		-- Left-side buttons apply changes directly to current weapon config
		AddButton(leftPanel, "Add new", function()
			local wep = LocalPlayer():GetActiveWeapon()
			if IsValid(wep) then
				g_VR.viewModelInfo[wep:GetClass()] = {
					offsetPos = Vector(),
					offsetAng = Angle()
				}

				UpdateListView()
			end
		end)

		AddButton(leftPanel, "Disable Laser", function()
			local wep = LocalPlayer():GetActiveWeapon()
			if not IsValid(wep) then return end
			local class = wep:GetClass()
			local data = g_VR.viewModelInfo[class]
			if not data then return end
			data.noLaser = not data.noLaser
			vrmod.SetViewModelNoLaser(class, data.noLaser)
			UpdateListLine(class)
		end)

		AddButton(leftPanel, "Fix muzzle", function()
			local wep = LocalPlayer():GetActiveWeapon()
			if not IsValid(wep) then return end
			local class = wep:GetClass()
			local data = g_VR.viewModelInfo[class]
			if not data then return end
			data.wrongMuzzleAng = not data.wrongMuzzleAng
			vrmod.SetViewModelFixMuzzle(class, data.wrongMuzzleAng)
			UpdateListLine(class)
		end)

		-- Right-side buttons (reverded orer)
		AddButton(rightPanel, "Reset Config", function()
			local confirm = vgui.Create("DFrame")
			confirm:SetSize(350, 200)
			confirm:Center()
			confirm:SetTitle("Confirm Reset")
			confirm:MakePopup()
			local msg = [[This will permanently delete your saved weapon viewmodel configuration file,
and reset everything to the default values.

You might need to reload the map afterwards in case you use VR specific weapons. 

Are you sure you want to continue?]]
			local lbl = vgui.Create("DLabel", confirm)
			lbl:SetText(msg)
			lbl:SetFont("DermaDefault") -- Optional: Use "DermaLarge" for emphasis
			lbl:SetContentAlignment(7) -- Top-left
			lbl:SetWrap(true)
			lbl:SetAutoStretchVertical(true)
			lbl:Dock(TOP)
			lbl:DockMargin(10, 10, 10, 0)
			local btnPanel = vgui.Create("DPanel", confirm)
			btnPanel:Dock(BOTTOM)
			btnPanel:SetTall(40)
			local function DoReset()
				if file.Exists(CONFIG_PATH, "DATA") then file.Delete(CONFIG_PATH) end
				table.Empty(g_VR.viewModelInfo)
				for cls, data in pairs(DEFAULT_VIEWMODEL_INFO) do
					g_VR.viewModelInfo[cls] = data
				end

				SaveViewModelConfig()
				UpdateListView()
				confirm:Close()
			end

			local yesBtn = vgui.Create("DButton", btnPanel)
			yesBtn:SetText("Yes")
			yesBtn:SetSize(100, 30)
			yesBtn:Dock(LEFT)
			yesBtn:DockMargin(20, 5, 10, 5)
			yesBtn.DoClick = DoReset
			local noBtn = vgui.Create("DButton", btnPanel)
			noBtn:SetText("Cancel")
			noBtn:SetSize(100, 30)
			noBtn:Dock(RIGHT)
			noBtn:DockMargin(10, 5, 20, 5)
			noBtn.DoClick = function() confirm:Close() end
		end)

		AddButton(rightPanel, "Delete", function()
			local selected = listview:GetSelectedLine()
			if selected then
				local class = listview:GetLine(selected):GetValue(1)
				g_VR.viewModelInfo[class] = nil
				UpdateListView() -- full reload because we remove a line
			end
		end)

		AddButton(rightPanel, "Edit offset", function()
			local selected = listview:GetSelectedLine()
			if selected then
				local class = listview:GetLine(selected):GetValue(1)
				CreateAddWeaponConfigGUI(class, true)
				frame:Close()
			end
		end)
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