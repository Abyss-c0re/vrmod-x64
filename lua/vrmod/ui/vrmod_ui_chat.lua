if CLIENT then
	local pressTime = 0
	local chatLog = {}
	local chatPanel = nil
	local nametags = false
	local VRClipboard = CreateClientConVar("vrmod_Clipboard", "", false, false, "")
	hook.Add("VRMod_Start", "voicepermissions", function(ply) end)
	local function toggleNametags()
		nametags = not nametags
		if nametags then
			hook.Add("PostDrawOpaqueRenderables", "vrutil_hook_nametags", function(depth, sky)
				if not g_VR.threePoints or depth or sky then return end
				surface.SetFont("vrmod_Verdana37")
				surface.SetDrawColor(0, 0, 0, 128)
				for k, v in pairs(player.GetAll()) do
					if v == LocalPlayer() or EyePos():DistToSqr(v:GetPos()) > 1000000 then continue end
					local mtx = v:GetBoneMatrix(v:LookupBone("ValveBiped.Bip01_Head1") or -1)
					local pos = mtx and mtx:GetTranslation() + Vector(0, 0, 15) or v:GetPos() + Vector(0, 0, 74)
					cam.Start3D2D(pos, Angle(0, (g_VR.tracking.hmd.pos - v:GetPos()):Angle().yaw + 90, 90), 0.1)
					local textWidth, textHeight = surface.GetTextSize(v:Nick())
					surface.DrawRect(textWidth * -0.5 - 5, 0, textWidth + 10, textHeight)
					surface.SetTextPos(textWidth * -0.5, 0)
					surface.SetTextColor(GAMEMODE:GetTeamColor(v))
					surface.DrawText(v:Nick())
					cam.End3D2D()
				end
			end)
		else
			hook.Remove("PostDrawOpaqueRenderables", "vrutil_hook_nametags")
		end
	end

	local function addChatMessage(msg)
		if #chatLog > 30 then table.remove(chatLog, 1) end
		if not chatPanel or not chatPanel:IsValid() then return end
		chatPanel.chatbox:InsertColorChange(151, 211, 255, 255)
		for i = 1, #msg do
			if IsColor(msg[i]) then
				chatPanel.chatbox:InsertColorChange(msg[i].r, msg[i].g, msg[i].b, 255)
			else
				chatPanel.chatbox:AppendText(tostring(msg[i]))
			end
		end

		chatPanel.chatbox:AppendText("\n")
		if VRUtilIsMenuOpen("chat") then VRUtilMenuRenderPanel("chat") end
	end

	local function updatePlayerList()
		if not chatPanel or not chatPanel:IsValid() then return end
		chatPanel.playerlist:SetText("")
		for k, v in pairs(player.GetAll()) do
			local col = GAMEMODE:GetTeamColor(v)
			chatPanel.playerlist:InsertColorChange(col.r, col.g, col.b, 255)
			chatPanel.playerlist:AppendText("\n" .. v:Nick())
		end

		if VRUtilIsMenuOpen("chat") then VRUtilMenuRenderPanel("chat") end
	end

	local function ToggleChat()
		if VRUtilIsMenuOpen("chat") then
			VRUtilMenuClose("chat")
			return
		end

		chatPanel = vgui.Create("DPanel")
		chatPanel:SetPos(0, 0)
		chatPanel:SetSize(600, 310)
		chatPanel:SetPaintedManually(true)
		function chatPanel:Paint(w, h)
		end

		function chatPanel:GetSize()
			return 450, 310
		end

		chatPanel.chatbox = vgui.Create("RichText", chatPanel)
		chatPanel.chatbox:SetPos(0, 0)
		chatPanel.chatbox:SetSize(450, 280)
		function chatPanel.chatbox:PerformLayout()
			self:SetFontInternal("ChatFont")
			self:SetBGColor(0, 0, 0, 128)
		end

		chatPanel.msgbar = vgui.Create("DTextEntry", chatPanel)
		chatPanel.msgbar:SetPos(0, 255)
		chatPanel.msgbar:SetSize(450, 25)
		chatPanel.msgbar:SetText("")
		chatPanel.msgbar:SetFont("ChatFont")
		chatPanel.msgbar:SetVisible(false)
		chatPanel.playerlist = vgui.Create("RichText", chatPanel)
		chatPanel.playerlist:SetPos(450, 0)
		chatPanel.playerlist:SetSize(300, 280)
		chatPanel.playerlist:SetVerticalScrollbarEnabled(false)
		function chatPanel.playerlist:PerformLayout()
			self:SetFontInternal("HudSelectionText")
		end

		for i = 1, 3 do
			chatPanel["button" .. i] = vgui.Create("DLabel", chatPanel)
			local button = chatPanel["button" .. i]
			button:SetPos((i - 1) * 85, 285)
			button:SetSize(80, 25)
			button:SetTextColor((i == 1 and LocalPlayer():IsSpeaking() or i == 2 and nametags) and Color(0, 255, 0, 255) or Color(255, 0, 0, 255))
			button:SetText(i == 1 and "Voice" or i == 2 and "Console" or "Keyboard")
			button:SetFont("HudSelectionText")
			button:SetContentAlignment(5)
			button:SetMouseInputEnabled(true)
			function button:Paint(w, h)
				surface.SetDrawColor(Color(0, 0, 0, 128))
				surface.DrawRect(0, 0, w, h)
			end

			button.OnMousePressed = function()
				if i == 1 then
					permissions.EnableVoiceChat(not LocalPlayer():IsSpeaking())
					timer.Simple(0.01, function() chatPanel.button1:SetTextColor(LocalPlayer():IsSpeaking() and Color(0, 255, 0, 255) or Color(255, 0, 0, 255)) end)
				elseif i == 2 then
					toggleNametags()
					chatPanel.button2:SetColor(nametags and Color(0, 255, 0, 255) or Color(255, 0, 0, 255))
				else
					if VRUtilIsMenuOpen("keyboard") then
						VRUtilMenuClose("keyboard")
						return
					end

					chatPanel.button3:SetColor(Color(0, 255, 0, 255))
					chatPanel.msgbar:SetVisible(true)
					chatPanel.chatbox:SetSize(450, 255)
					local keyboardPanel = vgui.Create("DPanel")
					keyboardPanel:SetPos(0, 0)
					keyboardPanel:SetSize(555, 255)
					function keyboardPanel:Paint(w, h)
						surface.SetDrawColor(Color(0, 0, 0, 128))
						surface.DrawRect(0, 0, w, h)
						surface.SetDrawColor(Color(0, 0, 0, 255))
						surface.DrawOutlinedRect(0, 0, w, h)
					end

					local lowerCase = "1234567890\1\nqwertyuiop\nasdfghjkl\2\n\3zxcvbnm?\4\3\n "
					local upperCase = "!@%\"*+=-_\1\nQWERTYUIOP\nASDFGHJKL\2\n\3ZXCVBNM/\4\3\n "
					local selectedCase = lowerCase
					local keys = {}
					local function updateKeyboard()
						for i = 1, #selectedCase do
							if selectedCase[i] == "\n" then continue end
							keys[i]:SetText(selectedCase[i] == "\1" and "Back" or selectedCase[i] == "\2" and "Enter" or selectedCase[i] == "\4" and "Shift" or selectedCase[i] == "\3" and "chat" or selectedCase[i])
						end
					end

					local x, y = 5, 5
					for i = 1, #selectedCase do
						if selectedCase[i] == "\n" then
							y = y + 50
							x = y == 205 and 127 or y == 155 and 5 or 5 + (y - 5) / 50 * 15
							continue
						end

						keys[i] = vgui.Create("DLabel", keyboardPanel)
						local key = keys[i]
						key:SetPos(x, y)
						key:SetSize(selectedCase[i] == " " and 250 or selectedCase[i] == "\2" and 65 or selectedCase[i] == "\4" and 50 or 45, 45) -- chatボタンのサイズを50に変更
						key:SetTextColor(Color(255, 255, 255, 255))
						key:SetFont((selectedCase[i] == "\1" or selectedCase[i] == "\2" or selectedCase[i] == "\3" or selectedCase[i] == "\4") and "HudSelectionText" or "vrmod_Verdana37")
						key:SetText(selectedCase[i] == "\1" and "Back" or selectedCase[i] == "\2" and "Enter" or selectedCase[i] == "\4" and "Shift" or selectedCase[i] == "\3" and "chat" or selectedCase[i])
						key:SetMouseInputEnabled(true)
						key:SetContentAlignment(5)
						key.OnMousePressed = function()
							if key:GetText() == "Back" then
								chatPanel.msgbar:SetText(string.sub(chatPanel.msgbar:GetText(), 1, #chatPanel.msgbar:GetText() - 1))
							elseif key:GetText() == "Enter" then
								if nametags then
									LocalPlayer():ConCommand("" .. chatPanel.msgbar:GetText())
									VRClipboard:SetString("" .. chatPanel.msgbar:GetText())
									SetClipboardText("" .. chatPanel.msgbar:GetText())
								else
									LocalPlayer():ConCommand("say " .. chatPanel.msgbar:GetText())
									chatPanel.msgbar:SetText("")
								end
							elseif key:GetText() == "Shift" then
								selectedCase = selectedCase == lowerCase and upperCase or lowerCase
								updateKeyboard()
							elseif key:GetText() == "chat" then
								VRUtilMenuClose("chat")
								LocalPlayer():ConCommand("vrmod_keyboard")
							else
								chatPanel.msgbar:SetText(chatPanel.msgbar:GetText() .. key:GetText())
							end

							-- chatPanel.msgbar:SetCaretPos(99999)
							VRUtilMenuRenderPanel("chat")
						end

						function key:Paint(w, h)
							surface.SetDrawColor(Color(0, 0, 0, 200))
							surface.DrawRect(0, 0, w, h)
							surface.SetDrawColor(Color(128, 128, 128, 255))
							surface.DrawOutlinedRect(0, 0, w, h)
						end

						x = x + 50
					end

					VRUtilMenuOpen("keyboard", 555, 255, keyboardPanel, 1, Vector(4, 6, 5.5), Angle(0, -90, 10), 0.03, true, function()
						keyboardPanel:Remove()
						keyboardPanel = nil
						if chatPanel then
							chatPanel.msgbar:SetVisible(false)
							chatPanel.chatbox:SetSize(450, 280)
							chatPanel.button3:SetColor(Color(255, 0, 0, 255))
						end
					end)
				end
			end
		end

		timer.Simple(0.1, function()
			for i = 1, #chatLog do
				addChatMessage(chatLog[i])
			end

			updatePlayerList()
			--			
			--forw, left, up
			VRUtilMenuOpen("chat", 600, 310, chatPanel, 1, Vector(10, 6, 13), Angle(0, -90, 50), 0.03, true, function()
				chatPanel:SetVisible(false)
				chatPanel:Remove()
				chatPanel = nil
				VRUtilMenuClose("keyboard")
			end)
		end)
	end

	hook.Add("ChatText", "vrutil_hook_chattext", function(index, name, text, type)
		if type == "joinleave" then
			chatLog[#chatLog + 1] = {Color(162, 255, 162, 255), text}
		else
			chatLog[#chatLog + 1] = {text}
		end

		addChatMessage(chatLog[#chatLog])
	end)

	local orig = chat.AddText
	chat.AddText = function(...)
		local args = {...}
		orig(unpack(args))
		chatLog[#chatLog + 1] = {}
		for i = 1, #args do
			if isentity(args[i]) and IsValid(args[i]) and args[i]:IsPlayer() then
				table.insert(chatLog[#chatLog], GAMEMODE:GetTeamColor(args[i]))
				table.insert(chatLog[#chatLog], args[i]:Nick())
			elseif IsColor(args[i]) then
				table.insert(chatLog[#chatLog], args[i])
			else
				table.insert(chatLog[#chatLog], tostring(args[i]))
			end
		end

		addChatMessage(chatLog[#chatLog])
	end

	concommand.Add("vrmod_chatmode", function(ply, cmd, args) ToggleChat() end)
end