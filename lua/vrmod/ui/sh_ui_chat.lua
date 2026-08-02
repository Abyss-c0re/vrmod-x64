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
	KEYBOARD_HEIGHT = 275,
	KEYBOARD_KEY_WIDTH = 45,
	KEYBOARD_KEY_HEIGHT = 42,
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
	local sv_redirect = CreateConVar("vrmod_console_redirect", "0", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Redirect VRMod logs to player consoles (0=off, 1=on)")
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
		if sv_redirect:GetBool() then
			net.Start("VRMod_ConsoleMessage")
			net.WriteTable({Color(3, 163, 255), msg})
			net.Broadcast()
		end
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

		if sv_redirect:GetBool() then
			net.Start("VRMod_ConsoleMessage")
			net.WriteTable(formattedMsg)
			net.Broadcast()
		end
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
	local currentMessage = ""
	local keyboardOpen = false
	local wasClicking = false
	local justClicked = false
	-- Keyboard geometry lives in module driver (v46+); chat uses shared VRKeyboard
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

	local function chatTheme()
		local C = vrmod and vrmod.cube
		local T = (C and C.ThemeLive and C.ThemeLive()) or (C and C.Theme) or {}
		return C, T
	end

	local function chatFont(name, fallback)
		local C = vrmod and vrmod.cube
		if C and C.Font then
			local f = C.Font(name)
			if f then return f end
		end
		return fallback
	end

	local function markCubeMenu(uid)
		if g_VR and g_VR.menus and g_VR.menus[uid] then
			g_VR.menus[uid].cubeMenu = true
			g_VR.menus[uid].grabbable = true
			if not g_VR.menus[uid].freeFloat then
				g_VR.menus[uid].attachment = true
			end
		end
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
			if vrmod.VRKeyboard_IsOpen and vrmod.VRKeyboard_IsOpen() then
				vrmod.VRKeyboard_Close(false)
			end
			keyboardOpen = false
			currentMessage = ""
			showConsole = false
			hook.Remove("PreRender", "vrutil_hook_renderchat")
			hook.Remove("VRMod_Input", "vrmod_chat_clickdetect")
			wasClicking = false
			justClicked = false
		end)

		markCubeMenu("chat")

		hook.Add("VRMod_Input", "vrmod_chat_clickdetect", function(action, pressed)
			if action == "boolean_primaryfire" or action == "boolean_car_mouse_left" then
				justClicked = pressed and not wasClicking
				wasClicking = pressed
			end
		end)

		hook.Add("PreRender", "vrutil_hook_renderchat", function()
			if not VRUtilIsMenuOpen("chat") then return end
			markCubeMenu("chat")

			local C, T = chatTheme()
			local M = (C and C.Metrics and C.Metrics()) or { pad = 10, headerH = 36, bar = 4 }
			local headerH = M.headerH or 36
			local pad = math.min(M.pad or 10, 12)
			local logFont = chatFont("CubeLabel", "vrmod_chat_normal")
			local midFont = chatFont("CubeSmall", "vrmod_chat_mid")
			local textCol = T.text or Color(255, 240, 244, 255)
			local mutedCol = T.muted or Color(200, 150, 165, 230)
			local panelCol = T.panel or Color(36, 12, 18, 240)
			local glassCol = T.bgGlass or Color(22, 10, 16, 230)

			VRUtilMenuRenderStart("chat")

			-- Cube chrome over full chat panel
			local subtitle = showConsole and "CONSOLE" or "SAY"
			if keyboardOpen and currentMessage ~= "" then
				subtitle = string.sub(currentMessage, 1, 28)
			end
			if C and C.DrawChrome then
				C.DrawChrome(0, 0, SIZE.MENU_WIDTH, SIZE.MENU_HEIGHT, "CHAT", {
					subtitle = subtitle,
					pad = pad,
					headerH = headerH,
				})
			else
				surface.SetDrawColor(12, 6, 10, 245)
				surface.DrawRect(0, 0, SIZE.MENU_WIDTH, SIZE.MENU_HEIGHT)
				surface.SetDrawColor(196, 30, 58, 255)
				surface.DrawRect(0, 0, SIZE.MENU_WIDTH, 4)
				draw.SimpleText("CHAT", "DermaLarge", pad, 10, Color(196, 30, 58), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
			end

			-- Close (X) — header top-right, Cube slot
			local cbx = SIZE.MENU_WIDTH - SIZE.CLOSE_BUTTON_WIDTH - 8
			local cby = math.max(6, math.floor((headerH - SIZE.CLOSE_BUTTON_HEIGHT) * 0.5))
			local cbw, cbh = SIZE.CLOSE_BUTTON_WIDTH, SIZE.CLOSE_BUTTON_HEIGHT
			local cx, cy = g_VR.menuCursorX or -1, g_VR.menuCursorY or -1
			local focused = (g_VR.menuFocus == "chat")
			local closeHot = focused and cx > cbx and cx < cbx + cbw and cy > cby and cy < cby + cbh
			if C and C.DrawSlot then
				C.DrawSlot(cbx, cby, cbw, cbh, "X", closeHot, false, true)
			else
				surface.SetDrawColor(closeHot and Color(100, 22, 38, 255) or Color(55, 14, 24, 230))
				surface.DrawRect(cbx, cby, cbw, cbh)
				draw.SimpleText("X", midFont, cbx + cbw * 0.5, cby + cbh * 0.5, textCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end

			local contentTop = headerH + 4
			local chatHeight = keyboardOpen and SIZE.CHAT_HEIGHT_KEYBOARD or SIZE.CHAT_HEIGHT_DEFAULT
			-- Keep log within chrome body (below header, above button bar)
			chatHeight = math.max(contentTop + 40, math.min(chatHeight, SIZE.BUTTON_BAR_Y - 4))

			-- Chat log panel
			surface.SetDrawColor(glassCol)
			surface.DrawRect(pad, contentTop, SIZE.CHAT_WIDTH - pad, chatHeight - contentTop)
			if T.crimsonDim then
				surface.SetDrawColor(T.crimsonDim)
				surface.DrawOutlinedRect(pad, contentTop, SIZE.CHAT_WIDTH - pad, chatHeight - contentTop, 1)
			end

			-- Playerlist panel
			surface.SetDrawColor(panelCol)
			surface.DrawRect(SIZE.CHAT_WIDTH + 2, contentTop, SIZE.PLAYERLIST_WIDTH - 4, chatHeight - contentTop)
			if T.crimsonDim then
				surface.SetDrawColor(T.crimsonDim)
				surface.DrawOutlinedRect(SIZE.CHAT_WIDTH + 2, contentTop, SIZE.PLAYERLIST_WIDTH - 4, chatHeight - contentTop, 1)
			end
			draw.SimpleText("PLAYERS", midFont, SIZE.CHAT_WIDTH + 8, contentTop + 2, mutedCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

			-- Draw chat or console log
			surface.SetFont(logFont)
			local _, lineHeight = surface.GetTextSize("A")
			local currY = contentTop + 4
			local logToShow = showConsole and consoleLog or chatLog
			local textAreaW = SIZE.CHAT_TEXT_AREA_WIDTH - pad
			local startIndex = math.max(1, #logToShow - maxVisibleLines - scrollOffset + 1)
			for i = startIndex, math.min(#logToShow, startIndex + maxVisibleLines - 1) do
				local msg = logToShow[i]
				if not msg then continue end
				local lineX = pad + 4
				local currColor = textCol
				for j = 1, #msg do
					if IsColor(msg[j]) then
						currColor = Color(msg[j].r, msg[j].g, msg[j].b, 255)
					else
						local txt = tostring(msg[j])
						for word in txt:gmatch("%S+%s*") do
							local tw, _ = surface.GetTextSize(word)
							if lineX + tw > pad + textAreaW then
								currY = currY + lineHeight
								if currY > chatHeight - lineHeight then break end
								lineX = pad + 4
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

			-- Playerlist nicks
			surface.SetFont(midFont)
			local py = contentTop + 18
			local ph = select(2, surface.GetTextSize("A"))
			for _, v in ipairs(player.GetAll()) do
				if not IsValid(v) then continue end
				local col = GAMEMODE:GetTeamColor(v)
				surface.SetTextColor(col)
				surface.SetTextPos(SIZE.CHAT_WIDTH + 8, py)
				surface.DrawText(v:Nick())
				py = py + ph
				if py > chatHeight then break end
			end

			-- Live draft from shared module keyboard
			if keyboardOpen and vrmod.VRKeyboard_IsOpen and vrmod.VRKeyboard_IsOpen() then
				currentMessage = vrmod.VRKeyboard_GetText and (vrmod.VRKeyboard_GetText() or "") or currentMessage
			elseif keyboardOpen and not (vrmod.VRKeyboard_IsOpen and vrmod.VRKeyboard_IsOpen()) then
				keyboardOpen = false
			end

			-- Message bar if keyboard open
			if keyboardOpen then
				local barY = SIZE.CHAT_HEIGHT_KEYBOARD
				if C and C.DrawSlot then
					C.DrawSlot(pad, barY, SIZE.CHAT_WIDTH - pad, SIZE.BUTTON_HEIGHT, nil, false, true, true)
				else
					surface.SetDrawColor(panelCol)
					surface.DrawRect(pad, barY, SIZE.CHAT_WIDTH - pad, SIZE.BUTTON_HEIGHT)
				end
				local prompt = showConsole and "> " or ""
				draw.SimpleText(prompt .. currentMessage, logFont, pad + 6, barY + SIZE.BUTTON_HEIGHT * 0.5, textCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end

			-- Buttons
			local buttons = {
				{
					x = pad,
					y = SIZE.BUTTON_BAR_Y,
					w = 80,
					h = SIZE.BUTTON_HEIGHT,
					text = "Voice",
					active = function() return LocalPlayer():IsSpeaking() end,
					action = function() permissions.EnableVoiceChat(not LocalPlayer():IsSpeaking()) end
				},
				{
					x = pad + 85,
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
					x = pad + 170,
					y = SIZE.BUTTON_BAR_Y,
					w = 90,
					h = SIZE.BUTTON_HEIGHT,
					text = "Keyboard",
					active = function() return keyboardOpen end,
					action = function()
						if keyboardOpen then
							if vrmod.VRKeyboard_Close then vrmod.VRKeyboard_Close(false) end
							keyboardOpen = false
							return
						end
						if not isfunction(vrmod.VRKeyboard_Open) then
							if vrmod.Toast then vrmod.Toast("VR keyboard missing", 3, "error") end
							return
						end
						keyboardOpen = true
						local ok = vrmod.VRKeyboard_Open({
							title = showConsole and "CONSOLE" or "CHAT",
							text = currentMessage or "",
							role = "chat",
							place = "float",
							uid = "vrmod_shared_keyboard",
							onDone = function(result)
								keyboardOpen = false
								result = result or ""
								if showConsole then
									LocalPlayer():ConCommand(result)
									VRClipboard:SetString(result)
									if SetClipboardText then SetClipboardText(result) end
									currentMessage = result
								else
									if result ~= "" then
										LocalPlayer():ConCommand("say " .. result)
									end
									currentMessage = ""
								end
							end,
							onCancel = function()
								keyboardOpen = false
							end,
						})
						if not ok then
							keyboardOpen = false
							if vrmod.Toast then vrmod.Toast("Keyboard failed to open", 3, "error") end
						end
					end
				},
				{
					x = pad + 265,
					y = SIZE.BUTTON_BAR_Y,
					w = 40,
					h = SIZE.BUTTON_HEIGHT,
					text = "↑",
					active = function() return scrollOffset < #logToShow - maxVisibleLines end,
					action = function() scrollOffset = math.min(scrollOffset + 1, #logToShow - maxVisibleLines) end
				},
				{
					x = pad + 310,
					y = SIZE.BUTTON_BAR_Y,
					w = 40,
					h = SIZE.BUTTON_HEIGHT,
					text = "↓",
					active = function() return scrollOffset > 0 end,
					action = function() scrollOffset = math.max(scrollOffset - 1, 0) end
				}
			}

			for _, btn in ipairs(buttons) do
				local hovered = focused and cx > btn.x and cx < btn.x + btn.w and cy > btn.y and cy < btn.y + btn.h
				local selected = btn.active()
				if C and C.DrawSlot then
					C.DrawSlot(btn.x, btn.y, btn.w, btn.h, btn.text, hovered, selected, true)
				else
					local col = selected and Color(0, 180, 80, 200) or (hovered and Color(100, 22, 38, 255) or Color(55, 14, 24, 230))
					surface.SetDrawColor(col)
					surface.DrawRect(btn.x, btn.y, btn.w, btn.h)
					draw.SimpleText(btn.text, midFont, btn.x + btn.w * 0.5, btn.y + btn.h * 0.5, textCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
			end

			if C and C.DrawFooterLaw then
				C.DrawFooterLaw(SIZE.CHAT_WIDTH + 4, SIZE.MENU_HEIGHT - 16, SIZE.PLAYERLIST_WIDTH - 8, 2)
			end

			-- Handle clicks (defer justClicked clear when keyboard is open so key hooks see it)
			if justClicked and focused then
				if closeHot then
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