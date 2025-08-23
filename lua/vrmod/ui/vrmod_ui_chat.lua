local SIZE = {
	CHAT_WIDTH = 555,
	PLAYERLIST_WIDTH = 150,
	CHAT_HEIGHT_DEFAULT = 280,
	CHAT_HEIGHT_KEYBOARD = 255,
	CLOSE_BUTTON_WIDTH = 40,
	CLOSE_BUTTON_HEIGHT = 25,
	BUTTON_BAR_Y = 285,
	BUTTON_HEIGHT = 25,
	BUTTON_SPACING = 5,
	MENU_WIDTH = 750,
	MENU_HEIGHT = 350,
	KEYBOARD_WIDTH = 555,
	KEYBOARD_HEIGHT = 250,
	KEYBOARD_KEY_WIDTH = 45,
	KEYBOARD_KEY_HEIGHT = 45,
	KEYBOARD_SPACE_WIDTH = 545,
	KEYBOARD_ENTER_WIDTH = 65,
	KEYBOARD_SPECIAL_WIDTH = 48,
	KEYBOARD_KEY_SPACING = 1.5,
	CHAT_TEXT_AREA_WIDTH = 550,
}

-- Shared logs
local chatLog = {}
local consoleLog = {}
-- Shared functions
function addChatMessage(msg)
	table.insert(chatLog, msg)
	if #chatLog > 30 then table.remove(chatLog, 1) end
end

function addConsoleMessage(msg)
	local formattedMsg
	if type(msg) == "table" then
		formattedMsg = {}
		for _, v in ipairs(msg) do
			if IsColor(v) then
				table.insert(formattedMsg, v)
			else
				table.insert(formattedMsg, tostring(v))
			end
		end
	else
		formattedMsg = tostring(msg)
	end

	table.insert(consoleLog, formattedMsg)
	if #consoleLog > 30 then table.remove(consoleLog, 1) end
end

-- Server-side logic
if SERVER then
	util.AddNetworkString("VRMod_ConsoleMessage")
	-- Override server-side print
	local oldPrint = print
	function print(...)
		oldPrint(...)
		local args = {...}
		for i = 1, #args do
			args[i] = tostring(args[i])
		end

		local msg = table.concat(args, " ")
		--addConsoleMessage({Color(255, 255, 255, 255),   .. msg})
		net.Start("VRMod_ConsoleMessage")
		net.WriteTable({Color(3, 163, 255), msg})
		net.Broadcast()
	end

	-- Override server-side MsgC
	local oldMsgC = MsgC
	function MsgC(...)
		oldMsgC(...)
		local args = {...}
		local formattedMsg = {}
		for _, v in ipairs(args) do
			if IsColor(v) then
				table.insert(formattedMsg, v)
			else
				table.insert(formattedMsg, tostring(v))
			end
		end

		--addConsoleMessage(formattedMsg)
		net.Start("VRMod_ConsoleMessage")
		net.WriteTable(formattedMsg)
		net.Broadcast()
	end
end

-- Client-side logic
if CLIENT then
	local TOTAL_WIDTH = SIZE.CHAT_WIDTH + SIZE.PLAYERLIST_WIDTH
	local CLOSE_BUTTON_X = TOTAL_WIDTH - SIZE.CLOSE_BUTTON_WIDTH
	local CLOSE_BUTTON_Y = 0
	local showConsole = false
	local VRClipboard = CreateClientConVar("vrmod_Clipboard", "", false, false, "")
	local scrollOffset = 0
	local maxVisibleLines = 10
	local lowerCase = "1234567890\1\nqwertyuiop\nasdfghjkl\2\n\3zxcvbnm?\4\3\n "
	local upperCase = "!@%\"*+=-_:\1\nQWERTYUIOP\nASDFGHJKL\2\n\3ZXCVBNM/\4\3\n "
	local selectedCase = lowerCase
	local currentMessage = ""
	local keyboardOpen = false
	local wasClicking = false
	local justClicked = false
	-- Define fonts
	surface.CreateFont("vrmod_chat_normal", {
		font = "Trebuchet24",
		size = 20,
		antialias = true
	})

	surface.CreateFont("vrmod_chat_mid", {
		font = "Trebuchet24",
		size = 16,
		weight = 600,
		antialias = true
	})

	surface.CreateFont("vrmod_chat_small", {
		font = "Trebuchet24",
		size = 12,
		antialias = true
	})

	-- Receive server-side console messages
	net.Receive("VRMod_ConsoleMessage", function()
		local msg = net.ReadTable()
		addConsoleMessage(msg)
	end)

	-- Override client-side Error
	local oldError = Error
	function Error(...)
		oldError(...)
		local args = {...}
		local msg = "[Lua Error] " .. table.concat(args, " ")
		addConsoleMessage({Color(255, 0, 0, 255), msg})
	end

	-- Override client-side ErrorNoHalt
	local oldErrorNoHalt = ErrorNoHalt
	function ErrorNoHalt(...)
		oldErrorNoHalt(...)
		local args = {...}
		local msg = "[Lua Error (No Halt)] " .. table.concat(args, " ")
		addConsoleMessage({Color(255, 0, 0, 255), msg})
	end

	-- Override client-side print
	local oldPrint = print
	function print(...)
		oldPrint(...)
		local args = {...}
		for i = 1, #args do
			args[i] = tostring(args[i])
		end

		local msg = table.concat(args, " ")
		addConsoleMessage({Color(245, 147, 20), msg})
	end

	-- Override client-side MsgC
	local oldMsgC = MsgC
	function MsgC(...)
		local args = {...}
		local stringArgs = {}
		for _, v in ipairs(args) do
			if type(v) == "string" then table.insert(stringArgs, v) end
		end

		local msg = table.concat(stringArgs, " ")
		for _, v in ipairs(args) do
			if type(v) == "string" and v:match("Unknown command:") then addConsoleMessage({Color(255, 0, 0, 255), "[Unknown Command Error] " .. v}) end
		end

		if msg ~= "" then addConsoleMessage({Color(119, 228, 255), msg}) end
		oldMsgC(...)
	end

	-- Override Player:ConCommand
	local meta = FindMetaTable("Player")
	local oldConCommand = meta.ConCommand
	function meta:ConCommand(cmd)
		addConsoleMessage({Color(0, 255, 255, 255), "[Command] " .. tostring(cmd)})
		local function errorHandler(err)
			local errorMsg = "[Lua Error] " .. tostring(err)
			addConsoleMessage({Color(255, 0, 0, 255), errorMsg})
			local stackTrace = debug.traceback("", 2)
			for _, line in ipairs(string.Split(tostring(stackTrace), "\n")) do
				if line ~= "" then addConsoleMessage({Color(255, 0, 0, 255), "  " .. line}) end
			end
		end

		xpcall(function() oldConCommand(self, cmd) end, errorHandler)
		return
	end

	local function ToggleChat()
		if VRUtilIsMenuOpen("chat") then
			VRUtilMenuClose("chat")
			return
		end

		-- Initialize chat
		scrollOffset = 0
		keyboardOpen = false
		currentMessage = ""
		showConsole = false
		VRUtilMenuOpen("chat", SIZE.MENU_WIDTH, SIZE.MENU_HEIGHT, nil, true, Vector(10, 4, 8), Angle(0, -90, 50), 0.03, true, function()
			VRUtilMenuClose("keyboard")
			keyboardOpen = false
			currentMessage = ""
			showConsole = false
			hook.Remove("PreRender", "vrutil_hook_renderchat")
			hook.Remove("PreRender", "vrutil_hook_renderkeyboard")
			hook.Remove("VRMod_Input", "vrmod_chat_clickdetect")
			wasClicking = false
			justClicked = false
		end)

		hook.Add("VRMod_Input", "vrmod_chat_clickdetect", function(action, pressed)
			local clickInCar = LocalPlayer():InVehicle() and action == "boolean_right_pickup"
			if action == "boolean_primaryfire" or clickInCar then
				justClicked = pressed and not wasClicking
				wasClicking = pressed
			end
		end)

		hook.Add("PreRender", "vrutil_hook_renderchat", function()
			if not VRUtilIsMenuOpen("chat") then return end
			VRUtilMenuRenderStart("chat")
			local chatHeight = keyboardOpen and SIZE.CHAT_HEIGHT_KEYBOARD or SIZE.CHAT_HEIGHT_DEFAULT
			-- Chatbox background
			surface.SetDrawColor(0, 0, 0, 128)
			surface.DrawRect(0, 30, SIZE.CHAT_WIDTH, chatHeight - 30)
			-- Close button
			surface.SetDrawColor(255, 0, 0, 128)
			surface.DrawRect(CLOSE_BUTTON_X, CLOSE_BUTTON_Y, SIZE.CLOSE_BUTTON_WIDTH, SIZE.CLOSE_BUTTON_HEIGHT)
			surface.SetFont("vrmod_chat_mid")
			surface.SetTextColor(255, 255, 255, 255)
			local tw, th = surface.GetTextSize("X")
			surface.SetTextPos(CLOSE_BUTTON_X + SIZE.CLOSE_BUTTON_WIDTH / 2 - tw / 2, CLOSE_BUTTON_Y + SIZE.CLOSE_BUTTON_HEIGHT / 2 - th / 2)
			surface.DrawText("X")
			-- Draw chat or console log
			surface.SetFont("vrmod_chat_normal")
			local _, lineHeight = surface.GetTextSize("A")
			local currY = 30
			local logToShow = showConsole and consoleLog or chatLog
			local startIndex = math.max(1, #logToShow - maxVisibleLines - scrollOffset + 1)
			for i = startIndex, math.min(#logToShow, startIndex + maxVisibleLines - 1) do
				local msg = logToShow[i]
				if not msg then continue end
				local lineX = 5
				local currColor = Color(255, 255, 255, 255)
				for j = 1, #msg do
					if IsColor(msg[j]) then
						currColor = Color(msg[j].r, msg[j].g, msg[j].b, 255)
					else
						local txt = tostring(msg[j])
						for word in txt:gmatch("%S+%s*") do
							local tw, _ = surface.GetTextSize(word)
							if lineX + tw > SIZE.CHAT_TEXT_AREA_WIDTH then
								currY = currY + lineHeight
								if currY > chatHeight - lineHeight then break end
								lineX = 5
							end

							surface.SetTextColor(currColor)
							surface.SetTextPos(lineX, currY)
							surface.DrawText(word)
							lineX = lineX + tw
						end
					end
				end

				currY = currY + lineHeight
				if currY > chatHeight - lineHeight then break end
			end

			-- Playerlist
			surface.SetFont("vrmod_chat_mid")
			local py = 30
			local ph = select(2, surface.GetTextSize("A"))
			for k, v in ipairs(player.GetAll()) do
				if not IsValid(v) then continue end
				local col = GAMEMODE:GetTeamColor(v)
				surface.SetTextColor(col)
				surface.SetTextPos(SIZE.CHAT_WIDTH + 5, py)
				surface.DrawText(v:Nick())
				py = py + ph
				if py > chatHeight then break end
			end

			-- Message bar if keyboard open
			if keyboardOpen then
				surface.SetDrawColor(0, 0, 0, 128)
				surface.DrawRect(0, SIZE.CHAT_HEIGHT_KEYBOARD, SIZE.CHAT_WIDTH, SIZE.BUTTON_HEIGHT)
				surface.SetFont("vrmod_chat_normal")
				surface.SetTextColor(255, 255, 255, 255)
				surface.SetTextPos(5, SIZE.CHAT_HEIGHT_KEYBOARD + 2)
				surface.DrawText(currentMessage)
			end

			-- Buttons
			local buttons = {
				{
					x = 0,
					y = SIZE.BUTTON_BAR_Y,
					w = 80,
					h = SIZE.BUTTON_HEIGHT,
					text = "Voice",
					active = function() return LocalPlayer():IsSpeaking() end,
					action = function() permissions.EnableVoiceChat(not LocalPlayer():IsSpeaking()) end
				},
				{
					x = 85,
					y = SIZE.BUTTON_BAR_Y,
					w = 80,
					h = SIZE.BUTTON_HEIGHT,
					text = "Console",
					active = function() return showConsole end,
					action = function()
						showConsole = not showConsole
						scrollOffset = 0
					end
				},
				{
					x = 170,
					y = SIZE.BUTTON_BAR_Y,
					w = 80,
					h = SIZE.BUTTON_HEIGHT,
					text = "Keyboard",
					active = function() return keyboardOpen end,
					action = function()
						if keyboardOpen then
							VRUtilMenuClose("keyboard")
							keyboardOpen = false
						else
							keyboardOpen = true
							VRUtilMenuOpen("keyboard", SIZE.KEYBOARD_WIDTH, SIZE.KEYBOARD_HEIGHT, nil, true, Vector(5, 4, 3.5), Angle(0, -90, 10), 0.03, true, function()
								keyboardOpen = false
								currentMessage = ""
							end)
						end
					end
				},
				{
					x = 255,
					y = SIZE.BUTTON_BAR_Y,
					w = 40,
					h = SIZE.BUTTON_HEIGHT,
					text = "↑",
					active = function() return scrollOffset < #logToShow - maxVisibleLines end,
					action = function() scrollOffset = math.min(scrollOffset + 1, #logToShow - maxVisibleLines) end
				},
				{
					x = 300,
					y = SIZE.BUTTON_BAR_Y,
					w = 40,
					h = SIZE.BUTTON_HEIGHT,
					text = "↓",
					active = function() return scrollOffset > 0 end,
					action = function() scrollOffset = math.max(scrollOffset - 1, 0) end
				}
			}

			surface.SetFont("vrmod_chat_mid")
			for i, btn in ipairs(buttons) do
				local col = btn.active() and Color(0, 255, 0, 128) or Color(255, 0, 0, 128)
				surface.SetDrawColor(col)
				surface.DrawRect(btn.x, btn.y, btn.w, btn.h)
				surface.SetTextColor(255, 255, 255, 255)
				local tw, th = surface.GetTextSize(btn.text)
				surface.SetTextPos(btn.x + btn.w / 2 - tw / 2, btn.y + btn.h / 2 - th / 2)
				surface.DrawText(btn.text)
			end

			-- Handle clicks
			if justClicked and VRUtilIsMenuOpen("chat") then
				local cx, cy = g_VR.menuCursorX, g_VR.menuCursorY
				if cx >= 0 and cx <= SIZE.MENU_WIDTH and cy >= 0 and cy <= SIZE.MENU_HEIGHT then
					if cx > CLOSE_BUTTON_X and cx < CLOSE_BUTTON_X + SIZE.CLOSE_BUTTON_WIDTH and cy > CLOSE_BUTTON_Y and cy < CLOSE_BUTTON_Y + SIZE.CLOSE_BUTTON_HEIGHT then
						VRUtilMenuClose("chat")
					else
						for _, btn in ipairs(buttons) do
							if cx > btn.x and cx < btn.x + btn.w and cy > btn.y and cy < btn.y + btn.h then
								btn.action()
								break
							end
						end
					end
				end
			end

			VRUtilMenuRenderEnd()
			justClicked = false
		end)

		hook.Add("PreRender", "vrutil_hook_renderkeyboard", function()
			if not VRUtilIsMenuOpen("keyboard") or not keyboardOpen then return end
			VRUtilMenuRenderStart("keyboard")
			surface.SetDrawColor(0, 0, 0, 128)
			surface.DrawRect(0, 0, SIZE.KEYBOARD_WIDTH, SIZE.KEYBOARD_HEIGHT)
			surface.SetDrawColor(0, 0, 0, 255)
			surface.DrawOutlinedRect(0, 0, SIZE.KEYBOARD_WIDTH, SIZE.KEYBOARD_HEIGHT)
			local x, y = SIZE.KEYBOARD_KEY_SPACING, SIZE.KEYBOARD_KEY_SPACING
			local closeKeyCount = 0
			for i = 1, #selectedCase do
				local char = selectedCase[i]
				if char == "\n" then
					y = y + SIZE.KEYBOARD_KEY_HEIGHT + SIZE.KEYBOARD_KEY_SPACING
					x = y == 55 and 20 or y == 105 and 35 or y == 155 and 5 or y == 205 and 127 or 5
					continue
				end

				if char == "\3" then closeKeyCount = closeKeyCount + 1 end
				local txt
				if char == "\1" then
					txt = "Del"
				elseif char == "\2" then
					txt = "Enter"
				elseif char == "\4" then
					txt = "Shift"
				elseif char == "\3" then
					txt = closeKeyCount == 1 and "Exit" or "Close"
				else
					txt = char
				end

				local w = char == " " and SIZE.KEYBOARD_SPACE_WIDTH or char == "\2" and SIZE.KEYBOARD_ENTER_WIDTH or (char == "\4" or char == "\3") and SIZE.KEYBOARD_SPECIAL_WIDTH or SIZE.KEYBOARD_KEY_WIDTH
				local h = SIZE.KEYBOARD_KEY_HEIGHT
				local hovered = g_VR.menuFocus == "keyboard" and g_VR.menuCursorX > x and g_VR.menuCursorX < x + w and g_VR.menuCursorY > y and g_VR.menuCursorY < y + h
				surface.SetDrawColor(0, 0, 0, hovered and 200 or 128)
				surface.DrawRect(x, y, w, h)
				surface.SetDrawColor(128, 128, 128, 255)
				surface.DrawOutlinedRect(x, y, w, h)
				local font = (char == "\1" or char == "\2" or char == "\3" or char == "\4") and "vrmod_chat_mid" or "vrmod_chat_normal"
				surface.SetFont(font)
				surface.SetTextColor(255, 255, 255, 255)
				local tw, th = surface.GetTextSize(txt)
				surface.SetTextPos(x + w / 2 - tw / 2, y + h / 2 - th / 2)
				surface.DrawText(txt)
				-- Handle clicks
				if hovered and justClicked and g_VR.menuFocus == "keyboard" then
					if txt == "Del" then
						currentMessage = string.sub(currentMessage, 1, #currentMessage - 1)
					elseif txt == "Enter" then
						if showConsole then
							LocalPlayer():ConCommand(currentMessage)
							VRClipboard:SetString(currentMessage)
							SetClipboardText(currentMessage)
						else
							LocalPlayer():ConCommand("say " .. currentMessage)
							currentMessage = ""
						end

						VRUtilMenuClose("keyboard")
						keyboardOpen = false
					elseif txt == "Shift" then
						selectedCase = selectedCase == lowerCase and upperCase or lowerCase
					elseif txt == "Exit" then
						VRUtilMenuClose("chat") -- close chat entirely
						VRUtilMenuClose("keyboard")
						keyboardOpen = false
					elseif txt == "Close" then
						VRUtilMenuClose("keyboard") -- only close keyboard
						keyboardOpen = false
					else
						currentMessage = currentMessage .. txt
					end
				end

				x = x + (w == SIZE.KEYBOARD_SPACE_WIDTH and w + SIZE.KEYBOARD_KEY_SPACING or w == SIZE.KEYBOARD_ENTER_WIDTH and w + SIZE.KEYBOARD_KEY_SPACING or SIZE.KEYBOARD_SPECIAL_WIDTH + SIZE.KEYBOARD_KEY_SPACING)
			end

			VRUtilMenuRenderEnd()
			justClicked = false
		end)
	end

	hook.Add("ChatText", "vrutil_hook_chattext", function(index, name, text, type)
		if type == "joinleave" then
			addChatMessage({Color(162, 255, 162, 255), text})
		elseif type ~= "chat" then
			addChatMessage({Color(255, 255, 255, 255), text})
		end
	end)

	hook.Add("OnPlayerChat", "vrutil_hook_onplayerchat", function(ply, text, teamChat, isDead)
		local msg = {}
		if isDead then
			table.insert(msg, Color(255, 50, 50, 255))
			table.insert(msg, "*DEAD* ")
		end

		if teamChat then
			table.insert(msg, Color(50, 255, 50, 255))
			table.insert(msg, "(TEAM) ")
		end

		if IsValid(ply) then
			table.insert(msg, GAMEMODE:GetTeamColor(ply))
			table.insert(msg, ply:Nick() .. ": ")
		end

		table.insert(msg, Color(255, 255, 255, 255))
		table.insert(msg, text)
		addChatMessage(msg)
	end)

	local orig = chat.AddText
	chat.AddText = function(...)
		local args = {...}
		orig(unpack(args))
		if not (isentity(args[1]) and IsValid(args[1]) and args[1]:IsPlayer()) then
			local msg = {}
			for i = 1, #args do
				if isentity(args[i]) and IsValid(args[i]) and args[i]:IsPlayer() then
					table.insert(msg, GAMEMODE:GetTeamColor(args[i]))
					table.insert(msg, args[i]:Nick())
				elseif IsColor(args[i]) then
					table.insert(msg, Color(args[i].r, args[i].g, args[i].b, 255))
				else
					table.insert(msg, tostring(args[i]))
				end
			end

			addChatMessage(msg)
		end
	end

	concommand.Add("vrmod_chatmode", function(ply, cmd, args) ToggleChat() end)
end