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

-- Shared logs (ring-style: cap + drop head)
local MAX_CHAT_LINES = 64
local MAX_CONSOLE_LINES = 200
local chatLog = {}
local consoleLog = {}
local cmdHistory = {} -- console command history (newest last)
local MAX_CMD_HISTORY = 48
local cmdHistoryIdx = 0 -- 0 = drafting; 1..n = browsing from end

local function markChatDirty()
	if g_VR and g_VR.menus and g_VR.menus.chat then
		g_VR.menus.chat.dirty = true
	end
	if vrmod and isfunction(vrmod.MarkMenuDirty) then
		vrmod.MarkMenuDirty("chat")
	end
end

-- Shared functions
function addChatMessage(msg)
	table.insert(chatLog, msg)
	while #chatLog > MAX_CHAT_LINES do table.remove(chatLog, 1) end
	markChatDirty()
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
		formattedMsg = { Color(220, 220, 220, 255), tostring(msg) }
	end

	table.insert(consoleLog, formattedMsg)
	while #consoleLog > MAX_CONSOLE_LINES do table.remove(consoleLog, 1) end
	markChatDirty()
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
	local showConsole = false
	local VRClipboard = CreateClientConVar("vrmod_Clipboard", "", false, false, "")
	-- 0=off, 1=only while chat/console panel open, 2=always (debug)
	local cv_capture = CreateClientConVar("vrmod_console_capture", "1", true, FCVAR_ARCHIVE,
		"VR console capture: 0=off 1=when panel open 2=always")
	local scrollOffset = 0
	local maxVisibleLines = 12
	local scrollStep = 5 -- page-ish scroll per button press
	local currentMessage = ""
	local lastDraftText = ""
	local lastSpeaking = false
	local keyboardOpen = false
	local wasClicking = false
	local justClicked = false
	local draftText = "" -- keyboard history browse buffer

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

	local function chatPanelOpen()
		return isfunction(VRUtilIsMenuOpen) and VRUtilIsMenuOpen("chat")
	end

	local function shouldCaptureConsole()
		local mode = cv_capture:GetInt()
		if mode <= 0 then return false end
		if mode >= 2 then return true end
		return chatPanelOpen()
	end

	local function maxScrollFor(logToShow)
		return math.max(0, #logToShow - maxVisibleLines)
	end

	local function clampScroll(logToShow)
		scrollOffset = math.Clamp(scrollOffset, 0, maxScrollFor(logToShow))
	end

	local function runConsoleLine(line)
		line = string.Trim(tostring(line or ""))
		if line == "" then return end
		-- History (dedupe consecutive)
		if cmdHistory[#cmdHistory] ~= line then
			cmdHistory[#cmdHistory + 1] = line
			while #cmdHistory > MAX_CMD_HISTORY do table.remove(cmdHistory, 1) end
		end
		cmdHistoryIdx = 0
		draftText = ""
		addConsoleMessage({ Color(90, 220, 150, 255), "> " .. line })
		-- Prefer full-line ConCommand so args stay intact
		local ply = LocalPlayer()
		if IsValid(ply) then
			pcall(function() ply:ConCommand(line) end)
		else
			pcall(function()
				if game and game.ConsoleCommand then
					game.ConsoleCommand(line .. "\n")
				else
					RunConsoleCommand(line)
				end
			end)
		end
		if VRClipboard and VRClipboard.SetString then VRClipboard:SetString(line) end
		if SetClipboardText then pcall(SetClipboardText, line) end
		scrollOffset = 0 -- jump to latest
		currentMessage = ""
		markChatDirty()
	end

	local function historyPrev()
		if #cmdHistory == 0 then return end
		if cmdHistoryIdx == 0 then
			draftText = currentMessage or ""
		end
		cmdHistoryIdx = math.min(cmdHistoryIdx + 1, #cmdHistory)
		currentMessage = cmdHistory[#cmdHistory - cmdHistoryIdx + 1] or ""
		if keyboardOpen and vrmod.VRKeyboard_SetText then
			vrmod.VRKeyboard_SetText(currentMessage)
		end
		markChatDirty()
	end

	local function historyNext()
		if cmdHistoryIdx <= 0 then return end
		cmdHistoryIdx = cmdHistoryIdx - 1
		if cmdHistoryIdx == 0 then
			currentMessage = draftText or ""
		else
			currentMessage = cmdHistory[#cmdHistory - cmdHistoryIdx + 1] or ""
		end
		if keyboardOpen and vrmod.VRKeyboard_SetText then
			vrmod.VRKeyboard_SetText(currentMessage)
		end
		markChatDirty()
	end

	-- Receive server-side console messages (always show — server already gated)
	net.Receive("VRMod_ConsoleMessage", function()
		local msg = net.ReadTable()
		addConsoleMessage(msg)
	end)

	-- Override client-side Error (always capture — cheap, rare)
	local oldError = Error
	function Error(...)
		oldError(...)
		local args = {...}
		for i = 1, #args do args[i] = tostring(args[i]) end
		addConsoleMessage({ Color(255, 0, 0, 255), "[Lua Error] " .. table.concat(args, " ") })
	end

	local oldErrorNoHalt = ErrorNoHalt
	function ErrorNoHalt(...)
		oldErrorNoHalt(...)
		local args = {...}
		for i = 1, #args do args[i] = tostring(args[i]) end
		addConsoleMessage({ Color(255, 80, 80, 255), "[ErrorNoHalt] " .. table.concat(args, " ") })
	end

	-- Gate print/MsgC: default only while chat panel is open (avoids VR thrash)
	local oldPrint = print
	function print(...)
		oldPrint(...)
		if not shouldCaptureConsole() then return end
		local args = {...}
		for i = 1, #args do args[i] = tostring(args[i]) end
		addConsoleMessage({ Color(245, 147, 20), table.concat(args, " ") })
	end

	local oldMsgC = MsgC
	function MsgC(...)
		local args = {...}
		if shouldCaptureConsole() then
			local stringArgs = {}
			for _, v in ipairs(args) do
				if type(v) == "string" then stringArgs[#stringArgs + 1] = v end
			end
			local msg = table.concat(stringArgs, " ")
			for _, v in ipairs(args) do
				if type(v) == "string" and v:find("Unknown command:", 1, true) then
					addConsoleMessage({ Color(255, 0, 0, 255), v })
				end
			end
			if msg ~= "" then addConsoleMessage({ Color(119, 228, 255), msg }) end
		end
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
			local m = g_VR.menus[uid]
			m.cubeMenu = true
			m.grabbable = true
			m.alwaysRedraw = false
			m.paintInterval = 0 -- unfocused: dirty-only (messages mark dirty)
			m.paintIntervalFocused = 0 -- cursor quantize via MenuShouldRepaint
			if not m.freeFloat then
				m.attachment = true
			end
		end
	end

	local function contentLayout(headerH)
		local contentTop = headerH + 4
		local chatHeight = keyboardOpen and SIZE.CHAT_HEIGHT_KEYBOARD or SIZE.CHAT_HEIGHT_DEFAULT
		chatHeight = math.max(contentTop + 40, math.min(chatHeight, SIZE.BUTTON_BAR_Y - 4))
		return contentTop, chatHeight
	end

	local function recomputeVisibleLines(contentTop, chatHeight, logFont)
		surface.SetFont(logFont)
		local _, lineHeight = surface.GetTextSize("A")
		lineHeight = math.max(lineHeight, 14)
		local bodyH = math.max(20, chatHeight - contentTop - 8)
		maxVisibleLines = math.max(4, math.floor(bodyH / lineHeight))
		scrollStep = math.max(3, math.floor(maxVisibleLines * 0.5))
		return lineHeight
	end

	local function buildButtons(pad, logToShow)
		local buttons = {
			{
				x = pad,
				y = SIZE.BUTTON_BAR_Y,
				w = 68,
				h = SIZE.BUTTON_HEIGHT,
				text = "Voice",
				active = function()
					local ply = LocalPlayer()
					return IsValid(ply) and ply:IsSpeaking()
				end,
				action = function()
					local ply = LocalPlayer()
					if IsValid(ply) then
						permissions.EnableVoiceChat(not ply:IsSpeaking())
					end
					markChatDirty()
				end
			},
			{
				x = pad + 73,
				y = SIZE.BUTTON_BAR_Y,
				w = 72,
				h = SIZE.BUTTON_HEIGHT,
				text = "Console",
				active = function() return showConsole end,
				action = function()
					showConsole = not showConsole
					scrollOffset = 0
					cmdHistoryIdx = 0
					markChatDirty()
				end
			},
			{
				x = pad + 150,
				y = SIZE.BUTTON_BAR_Y,
				w = 78,
				h = SIZE.BUTTON_HEIGHT,
				text = "Keyboard",
				active = function() return keyboardOpen end,
				action = function()
					if keyboardOpen then
						if vrmod.VRKeyboard_Close then vrmod.VRKeyboard_Close(false) end
						keyboardOpen = false
						markChatDirty()
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
							result = string.Trim(tostring(result or ""))
							if showConsole then
								runConsoleLine(result)
							else
								if result ~= "" then
									local ply = LocalPlayer()
									if IsValid(ply) then
										ply:ConCommand("say " .. result)
									end
								end
								currentMessage = ""
							end
							markChatDirty()
						end,
						onCancel = function()
							keyboardOpen = false
							markChatDirty()
						end,
					})
					if not ok then
						keyboardOpen = false
						if vrmod.Toast then vrmod.Toast("Keyboard failed to open", 3, "error") end
					end
					markChatDirty()
				end
			},
			{
				x = pad + 233,
				y = SIZE.BUTTON_BAR_Y,
				w = 38,
				h = SIZE.BUTTON_HEIGHT,
				text = "↑",
				active = function() return scrollOffset < maxScrollFor(logToShow) end,
				action = function()
					scrollOffset = math.min(scrollOffset + scrollStep, maxScrollFor(logToShow))
					markChatDirty()
				end
			},
			{
				x = pad + 276,
				y = SIZE.BUTTON_BAR_Y,
				w = 38,
				h = SIZE.BUTTON_HEIGHT,
				text = "↓",
				active = function() return scrollOffset > 0 end,
				action = function()
					scrollOffset = math.max(scrollOffset - scrollStep, 0)
					markChatDirty()
				end
			},
		}

		if showConsole then
			buttons[#buttons + 1] = {
				x = pad + 319,
				y = SIZE.BUTTON_BAR_Y,
				w = 44,
				h = SIZE.BUTTON_HEIGHT,
				text = "CLR",
				active = function() return #consoleLog > 0 end,
				action = function()
					consoleLog = {}
					scrollOffset = 0
					markChatDirty()
				end
			}
			buttons[#buttons + 1] = {
				x = pad + 368,
				y = SIZE.BUTTON_BAR_Y,
				w = 36,
				h = SIZE.BUTTON_HEIGHT,
				text = "H↑",
				active = function() return #cmdHistory > 0 and cmdHistoryIdx < #cmdHistory end,
				action = historyPrev
			}
			buttons[#buttons + 1] = {
				x = pad + 409,
				y = SIZE.BUTTON_BAR_Y,
				w = 36,
				h = SIZE.BUTTON_HEIGHT,
				text = "H↓",
				active = function() return cmdHistoryIdx > 0 end,
				action = historyNext
			}
		end

		return buttons
	end

	local function paintInner()
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

		local subtitle = showConsole and "CONSOLE" or "SAY"
		if keyboardOpen and currentMessage ~= "" then
			subtitle = string.sub(currentMessage, 1, 28)
		elseif showConsole and #consoleLog > 0 then
			subtitle = string.format("CONSOLE · %d lines", #consoleLog)
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

		-- Close (X)
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

		local contentTop, chatHeight = contentLayout(headerH)
		local lineHeight = recomputeVisibleLines(contentTop, chatHeight, logFont)

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
		local currY = contentTop + 4
		local logToShow = showConsole and consoleLog or chatLog
		clampScroll(logToShow)
		local textAreaW = SIZE.CHAT_TEXT_AREA_WIDTH - pad
		local startIndex = math.max(1, #logToShow - maxVisibleLines - scrollOffset + 1)
		local endIndex = math.min(#logToShow, startIndex + maxVisibleLines - 1)
		for i = startIndex, endIndex do
			local msg = logToShow[i]
			if not msg then continue end
			local lineX = pad + 4
			local currColor = textCol
			-- Console lines are always tables of color/text; plain strings also OK
			if type(msg) ~= "table" then
				msg = { textCol, tostring(msg) }
			end
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

		-- Scroll position hint
		if #logToShow > maxVisibleLines then
			local ms = maxScrollFor(logToShow)
			local hint = scrollOffset == 0 and "latest" or string.format("%d↑", scrollOffset)
			draw.SimpleText(hint, chatFont("CubeTiny", "vrmod_chat_small"), SIZE.CHAT_WIDTH - 8, contentTop + 2, mutedCol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
			-- Mini scrollbar
			local trackX = SIZE.CHAT_WIDTH - 6
			local trackY = contentTop + 16
			local trackH = math.max(20, chatHeight - contentTop - 20)
			surface.SetDrawColor(40, 20, 28, 180)
			surface.DrawRect(trackX, trackY, 3, trackH)
			local thumbH = math.max(8, math.floor(trackH * maxVisibleLines / #logToShow))
			local thumbT = ms > 0 and ((ms - scrollOffset) / ms) or 1
			local thumbY = trackY + math.floor((trackH - thumbH) * (1 - thumbT))
			surface.SetDrawColor(196, 30, 58, 220)
			surface.DrawRect(trackX, thumbY, 3, thumbH)
		end

		-- Playerlist nicks
		surface.SetFont(midFont)
		local py = contentTop + 18
		local ph = select(2, surface.GetTextSize("A"))
		for _, v in ipairs(player.GetAll()) do
			if not IsValid(v) then continue end
			local col = team.GetColor(v:Team())
			if not col or col.a == 0 then
				col = (GAMEMODE and GAMEMODE.GetTeamColor and GAMEMODE:GetTeamColor(v)) or textCol
			end
			surface.SetTextColor(col)
			surface.SetTextPos(SIZE.CHAT_WIDTH + 8, py)
			surface.DrawText(v:Nick())
			py = py + ph
			if py > chatHeight then break end
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

		local buttons = buildButtons(pad, logToShow)
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
	end

	local function handleClick()
		if not justClicked then return end
		if g_VR.menuFocus ~= "chat" then return end

		local C, _T = chatTheme()
		local M = (C and C.Metrics and C.Metrics()) or { pad = 10, headerH = 36 }
		local headerH = M.headerH or 36
		local pad = math.min(M.pad or 10, 12)
		local cx, cy = g_VR.menuCursorX or -1, g_VR.menuCursorY or -1

		local cbx = SIZE.MENU_WIDTH - SIZE.CLOSE_BUTTON_WIDTH - 8
		local cby = math.max(6, math.floor((headerH - SIZE.CLOSE_BUTTON_HEIGHT) * 0.5))
		local cbw, cbh = SIZE.CLOSE_BUTTON_WIDTH, SIZE.CLOSE_BUTTON_HEIGHT
		if cx > cbx and cx < cbx + cbw and cy > cby and cy < cby + cbh then
			VRUtilMenuClose("chat")
			return
		end

		local logToShow = showConsole and consoleLog or chatLog
		local buttons = buildButtons(pad, logToShow)
		for _, btn in ipairs(buttons) do
			if cx > btn.x and cx < btn.x + btn.w and cy > btn.y and cy < btn.y + btn.h then
				btn.action()
				return
			end
		end
	end

	local function paintChat(force)
		if not chatPanelOpen() then return end
		if not (g_VR and g_VR.menus and g_VR.menus.chat) then return end
		markCubeMenu("chat")

		if isfunction(vrmod.NativeMenuPaint) then
			vrmod.NativeMenuPaint("chat", paintInner, force)
			return
		end
		-- Fallback without Cube paint gate
		if not force and g_VR.menus.chat.dirty ~= true then return end
		if not isfunction(VRUtilMenuRenderStart) or not VRUtilMenuRenderStart("chat") then return end
		pcall(paintInner)
		if isfunction(VRUtilMenuRenderEnd) then pcall(VRUtilMenuRenderEnd) end
		g_VR.menus.chat.dirty = false
	end

	local function ToggleChat()
		if VRUtilIsMenuOpen("chat") then
			VRUtilMenuClose("chat")
			return
		end

		scrollOffset = 0
		keyboardOpen = false
		currentMessage = ""
		lastDraftText = ""
		showConsole = false
		cmdHistoryIdx = 0
		draftText = ""
		justClicked = false
		wasClicking = false

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
		if g_VR and g_VR.menus and g_VR.menus.chat then
			g_VR.menus.chat.dirty = true
		end

		hook.Add("VRMod_Input", "vrmod_chat_clickdetect", function(action, pressed)
			if action == "boolean_primaryfire" or action == "boolean_car_mouse_left" then
				justClicked = pressed and not wasClicking
				wasClicking = pressed
				if justClicked then
					markChatDirty() -- ensure hover state paints after click
				end
			end
		end)

		-- Force first paint, then dirty-gated
		paintChat(true)

		hook.Add("PreRender", "vrutil_hook_renderchat", function()
			if not VRUtilIsMenuOpen("chat") then return end
			markCubeMenu("chat")

			-- Live draft from shared module keyboard
			if keyboardOpen and vrmod.VRKeyboard_IsOpen and vrmod.VRKeyboard_IsOpen() then
				local t = vrmod.VRKeyboard_GetText and (vrmod.VRKeyboard_GetText() or "") or currentMessage
				if t ~= lastDraftText then
					lastDraftText = t
					currentMessage = t
					markChatDirty()
				end
			elseif keyboardOpen and not (vrmod.VRKeyboard_IsOpen and vrmod.VRKeyboard_IsOpen()) then
				keyboardOpen = false
				markChatDirty()
			end

			-- Voice button active state
			local ply = LocalPlayer()
			local speaking = IsValid(ply) and ply:IsSpeaking() or false
			if speaking ~= lastSpeaking then
				lastSpeaking = speaking
				markChatDirty()
			end

			-- Input independent of paint skip
			if justClicked then
				handleClick()
				justClicked = false
			end

			paintChat(false)
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
			local col = team.GetColor(ply:Team())
			if not col then
				col = (GAMEMODE and GAMEMODE.GetTeamColor and GAMEMODE:GetTeamColor(ply)) or Color(255, 255, 255)
			end
			table.insert(msg, col)
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
					local col = team.GetColor(args[i]:Team())
					if not col then
						col = (GAMEMODE and GAMEMODE.GetTeamColor and GAMEMODE:GetTeamColor(args[i])) or Color(255, 255, 255)
					end
					table.insert(msg, col)
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
	concommand.Add("vrmod_console_clear", function()
		consoleLog = {}
		scrollOffset = 0
		markChatDirty()
	end)
end
