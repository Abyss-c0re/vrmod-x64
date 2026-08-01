if SERVER then return end
-- =============================================================================
-- Cube Avatar — player customization experience (hand VRMod menu)
-- Tabs: Height · Model · Body · Bones
-- Twin driven by g_VR.tracking via vrmod.avatar (Pescorr IK)
-- =============================================================================

vrmod = vrmod or {}

local UID = "avatar_menu"
local open = false
local tab = 1 -- 1 height 2 model 3 body 4 bones
local modelScroll = 0
local bodyScroll = 0
local avatarSession = nil
local modelList = {}
local buttons = {}
local statusMsg = ""
local statusUntil = 0

local W, H = 512, 600
local livePos, liveAng, liveScale = Vector(2.5, 3, 4), Angle(0, -90, 55), 0.025

-- Live theme (Settings → Theme applies to Avatar + all menus)
local function Theme()
	if vrmod.cube and vrmod.cube.ThemeLive then
		local T = vrmod.cube.ThemeLive()
		-- rowOn alias for selected tabs
		if not T.rowOn then T.rowOn = T.rowHot or T.btnHover end
		return T
	end
	return {
		bg = Color(12, 6, 10, 250),
		header = Color(196, 30, 58, 255),
		headerDim = Color(70, 14, 24, 255),
		row = Color(40, 14, 20, 245),
		rowHot = Color(95, 24, 38, 255),
		rowOn = Color(120, 30, 48, 255),
		text = Color(255, 240, 244, 255),
		muted = Color(200, 150, 165, 230),
		hot = Color(255, 70, 100, 255),
		ok = Color(90, 220, 150, 255),
		off = Color(70, 20, 30, 255),
	}
end

local TAB_NAMES = { "Height", "Model", "Body", "Bones" }
local HEADER, TAB_H, PAD, ROW_H = 52, 36, 12, 44

local convars = vrmod.GetConvars()

local function WristHand()
	return (vrmod.GetSecondaryHand and vrmod.GetSecondaryHand()) or "left"
end

local function WristPose()
	local wrist = WristHand()
	if isfunction(VRUtilHandMenuPose) then
		return VRUtilHandMenuPose(W, H, 0.025, Vector(2.5, 3.5, 4), Angle(0, -90, 55), wrist)
	end
	return Vector(2.5, 3, 4), Angle(0, -90, 55), 0.025
end

local function AutoScale()
	if not g_VR.tracking or not g_VR.tracking.hmd then return end
	local eyeH = g_VR.tracking.hmd.pos.z - g_VR.origin.z
	if eyeH < 8 then eyeH = 66.8 end
	g_VR.scale = 66.8 / (eyeH / math.max(g_VR.scale, 0.01))
	if convars and convars.vrmod_scale then
		convars.vrmod_scale:SetFloat(g_VR.scale)
	end
end

function vrmod.AutoScaleHeight()
	if not g_VR or not g_VR.tracking or not g_VR.tracking.hmd then return false end
	AutoScale()
	return true, g_VR.scale
end

function vrmod.AutoSeatedOffset()
	if not g_VR or not g_VR.origin then return false end
	local hmd = (g_VR.rawTracking and g_VR.rawTracking.hmd) or (g_VR.tracking and g_VR.tracking.hmd)
	if not hmd or not hmd.pos then return false end
	local offset = 66.8 - (hmd.pos.z - g_VR.origin.z)
	if convars then
		if convars.vrmod_seatedoffset then convars.vrmod_seatedoffset:SetFloat(offset) end
		if convars.vrmod_seated then convars.vrmod_seated:SetBool(true) end
	end
	return true, offset
end

local function StopTwin()
	if avatarSession then
		avatarSession:Close()
		avatarSession = nil
	end
	if vrmod.avatar then
		vrmod.avatar.Close("avatar")
		vrmod.avatar.Close("height")
	end
end

local function StartTwin()
	StopTwin()
	if vrmod.avatar and vrmod.avatar.OpenHeightCal then
		avatarSession = vrmod.avatar.OpenHeightCal(UID)
	end
end

local function sess()
	return avatarSession or (vrmod.avatar and vrmod.avatar.Get("avatar"))
end

local function seated()
	return convars and convars.vrmod_seated and convars.vrmod_seated:GetBool()
end

local function rebuildButtons()
	buttons = {}
	-- Large close hitbox (top-right) — easy laser target
	buttons[#buttons + 1] = { x = W - 64, y = 4, w = 56, h = 44, kind = "close" }

	local n = #TAB_NAMES
	local tw = (W - PAD * 2) / n
	for i = 1, n do
		buttons[#buttons + 1] = {
			x = PAD + (i - 1) * tw, y = HEADER, w = tw - 3, h = TAB_H,
			kind = "tab", index = i,
		}
	end

	local y0 = HEADER + TAB_H + 10

	if tab == 1 then
		-- Height controls
		local bw = (W - PAD * 2 - 16) / 3
		buttons[#buttons + 1] = { x = PAD, y = y0 + 50, w = bw, h = 48, kind = "h_plus" }
		buttons[#buttons + 1] = { x = PAD + bw + 8, y = y0 + 50, w = bw, h = 48, kind = "h_auto" }
		buttons[#buttons + 1] = { x = PAD + (bw + 8) * 2, y = y0 + 50, w = bw, h = 48, kind = "h_minus" }
		buttons[#buttons + 1] = { x = PAD, y = y0 + 110, w = (W - PAD * 2 - 8) / 2, h = 48, kind = "h_seated" }
		buttons[#buttons + 1] = { x = PAD + (W - PAD * 2 - 8) / 2 + 8, y = y0 + 110, w = (W - PAD * 2 - 8) / 2, h = 48, kind = "h_offset" }
		buttons[#buttons + 1] = { x = PAD, y = y0 + 170, w = W - PAD * 2, h = 40, kind = "reset_place" }
		buttons[#buttons + 1] = { x = PAD, y = y0 + 218, w = (W - PAD * 2 - 8) / 2, h = 40, kind = "dist_minus" }
		buttons[#buttons + 1] = { x = PAD + (W - PAD * 2 - 8) / 2 + 8, y = y0 + 218, w = (W - PAD * 2 - 8) / 2, h = 40, kind = "dist_plus" }
		buttons[#buttons + 1] = { x = PAD, y = y0 + 266, w = (W - PAD * 2 - 8) / 2, h = 40, kind = "yaw_ccw" }
		buttons[#buttons + 1] = { x = PAD + (W - PAD * 2 - 8) / 2 + 8, y = y0 + 266, w = (W - PAD * 2 - 8) / 2, h = 40, kind = "yaw_cw" }
	elseif tab == 2 then
		-- Model list (scrollable window)
		local vis = 8
		for i = 1, vis do
			local idx = modelScroll + i
			if modelList[idx] then
				buttons[#buttons + 1] = {
					x = PAD, y = y0 + (i - 1) * (ROW_H + 4),
					w = W - PAD * 2 - 48, h = ROW_H,
					kind = "model", index = idx,
				}
			end
		end
		buttons[#buttons + 1] = { x = W - PAD - 40, y = y0, w = 36, h = 40, kind = "model_up" }
		buttons[#buttons + 1] = { x = W - PAD - 40, y = y0 + 200, w = 36, h = 40, kind = "model_dn" }
		buttons[#buttons + 1] = { x = PAD, y = H - 120, w = W - PAD * 2, h = 40, kind = "model_player" }
		buttons[#buttons + 1] = { x = PAD, y = H - 70, w = W - PAD * 2, h = 48, kind = "model_save" }
	elseif tab == 3 then
		local s = sess()
		local ent = s and s:GetEntity()
		if IsValid(ent) then
			local nbg = ent:GetNumBodyGroups() or 0
			local vis = 7
			for i = 1, vis do
				local bg = bodyScroll + i - 1
				if bg >= 0 and bg < nbg then
					local y = y0 + (i - 1) * (ROW_H + 6)
					buttons[#buttons + 1] = {
						x = PAD, y = y, w = 48, h = ROW_H, kind = "bg_prev", bg = bg,
					}
					buttons[#buttons + 1] = {
						x = W - PAD - 48, y = y, w = 48, h = ROW_H, kind = "bg_next", bg = bg,
					}
				end
			end
			buttons[#buttons + 1] = { x = PAD, y = H - 120, w = (W - PAD * 2 - 8) / 2, h = 40, kind = "skin_prev" }
			buttons[#buttons + 1] = { x = PAD + (W - PAD * 2 - 8) / 2 + 8, y = H - 120, w = (W - PAD * 2 - 8) / 2, h = 40, kind = "skin_next" }
			buttons[#buttons + 1] = { x = PAD, y = H - 70, w = W - PAD * 2, h = 48, kind = "model_save" }
		end
		buttons[#buttons + 1] = { x = W - PAD - 40, y = y0, w = 36, h = 36, kind = "body_up" }
		buttons[#buttons + 1] = { x = W - PAD - 40, y = y0 + 160, w = 36, h = 36, kind = "body_dn" }
	elseif tab == 4 then
		buttons[#buttons + 1] = { x = PAD, y = y0 + 8, w = W - PAD * 2, h = 40, kind = "toggle_head" }
		buttons[#buttons + 1] = { x = PAD, y = y0 + 54, w = W - PAD * 2, h = 40, kind = "toggle_hands" }
		buttons[#buttons + 1] = { x = PAD, y = y0 + 100, w = W - PAD * 2, h = 40, kind = "toggle_trackers" }
		buttons[#buttons + 1] = { x = PAD, y = y0 + 146, w = W - PAD * 2, h = 40, kind = "toggle_laser_pick" }
		buttons[#buttons + 1] = { x = PAD, y = y0 + 192, w = W - PAD * 2, h = 40, kind = "clear_hidden_bones" }
		buttons[#buttons + 1] = { x = PAD, y = y0 + 238, w = W - PAD * 2, h = 40, kind = "restart_twin" }
		buttons[#buttons + 1] = { x = PAD, y = y0 + 284, w = W - PAD * 2, h = 40, kind = "model_save" }
	end
end

local function drawBtn(x, y, w, h, label, hot, on)
	surface.SetDrawColor(on and Theme().rowOn or (hot and Theme().rowHot or Theme().row))
	surface.DrawRect(x, y, w, h)
	surface.SetDrawColor(hot and Theme().hot or Theme().header)
	surface.DrawOutlinedRect(x, y, w, h, hot and 2 or 1)
	draw.SimpleText(tostring(label or ""), "DermaDefaultBold", x + w * 0.5, y + h * 0.5, Theme().text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function paint()
	if not open or not (g_VR.menus and g_VR.menus[UID]) then return end
	if not isfunction(VRUtilMenuRenderStart) or not isfunction(VRUtilMenuRenderEnd) then return end
	local m = g_VR.menus[UID]
	if not m.rt then return end
	m.paintInterval = m.paintInterval or 12
	m.paintIntervalFocused = 0
	if vrmod.MenuApplyHandAnchor then
		vrmod.MenuApplyHandAnchor(m, liveScale, livePos, liveAng, WristHand())
	elseif not m.freeFloat and not m.grabHand then
		if not m.scaleLocked then m.scale = liveScale end
		m.pos, m.ang = livePos, liveAng
		m.cubeMenu, m.attachment, m.attachHand = true, true, WristHand()
	end

	local focused = (g_VR.menuFocus == UID)
	local mx, my = g_VR.menuCursorX or -1, g_VR.menuCursorY or -1
	if vrmod.MenuShouldRepaint and not vrmod.MenuShouldRepaint(UID) then return end
	rebuildButtons()

	if VRUtilMenuRenderStart(UID) == false then return end
	local okPaint, errPaint = pcall(function()
		surface.SetDrawColor(Theme().bg)
		surface.DrawRect(0, 0, W, H)
		surface.SetDrawColor(Theme().headerDim)
		surface.DrawRect(0, 0, W, HEADER)
		surface.SetDrawColor(Theme().header)
		surface.DrawRect(0, HEADER - 3, W, 3)

		draw.SimpleText("AVATAR", "DermaLarge", PAD, 8, Theme().header)
		draw.SimpleText(focused and "LASER LOCK" or "point laser · Cube custom", "DermaDefault", PAD, 32, focused and Theme().ok or Theme().muted)

		local closeHot = focused and mx >= W - 64 and mx <= W - 8 and my >= 4 and my <= 48
		drawBtn(W - 64, 4, 56, 44, "X", closeHot, false)

		local n = #TAB_NAMES
		local tw = (W - PAD * 2) / n
		for i, name in ipairs(TAB_NAMES) do
			local x = PAD + (i - 1) * tw
			local hot = focused and mx >= x and mx < x + tw - 3 and my >= HEADER and my < HEADER + TAB_H
			drawBtn(x, HEADER, tw - 3, TAB_H, name, hot, i == tab)
		end

		local y0 = HEADER + TAB_H + 10
		local s = sess()

		if tab == 1 then
			local sc = g_VR.scale or 1
			draw.SimpleText(string.format("world scale  %.2f", sc), "DermaLarge", W * 0.5, y0 + 8, Theme().text, TEXT_ALIGN_CENTER)
			draw.SimpleText("POINT RH place · R grip twist = rotate · L grip = distance", "DermaDefault", W * 0.5, y0 + 32, Theme().muted, TEXT_ALIGN_CENTER)
			local bw = (W - PAD * 2 - 16) / 3
			drawBtn(PAD, y0 + 50, bw, 48, "+", focused and my >= y0 + 50 and my <= y0 + 98, false)
			drawBtn(PAD + bw + 8, y0 + 50, bw, 48, "AUTO", focused and my >= y0 + 50 and my <= y0 + 98, false)
			drawBtn(PAD + (bw + 8) * 2, y0 + 50, bw, 48, "-", focused and my >= y0 + 50 and my <= y0 + 98, false)
			drawBtn(PAD, y0 + 110, (W - PAD * 2 - 8) / 2, 48, seated() and "SEATED ON" or "SEATED OFF", false, seated())
			drawBtn(PAD + (W - PAD * 2 - 8) / 2 + 8, y0 + 110, (W - PAD * 2 - 8) / 2, 48, "OFFSET", false, false)
			local dist = s and s.distance or 40
			local yaw = s and (s.freeYaw or (s.standAng and s.standAng.yaw)) or 180
			drawBtn(PAD, y0 + 170, W - PAD * 2, 40, "RESET PLACE (face me)", false, false)
			drawBtn(PAD, y0 + 218, (W - PAD * 2 - 8) / 2, 40, "DIST −", false, false)
			drawBtn(PAD + (W - PAD * 2 - 8) / 2 + 8, y0 + 218, (W - PAD * 2 - 8) / 2, 40, string.format("DIST %.0f", dist), false, false)
			drawBtn(PAD, y0 + 266, (W - PAD * 2 - 8) / 2, 40, "YAW ↺", false, false)
			drawBtn(PAD + (W - PAD * 2 - 8) / 2 + 8, y0 + 266, (W - PAD * 2 - 8) / 2, 40, string.format("YAW %.0f°", yaw % 360), false, false)
		elseif tab == 2 then
			draw.SimpleText("select playermodel · twin updates live", "DermaDefault", PAD, y0 - 2, Theme().muted)
			local vis = 8
			local cur = s and s.model or ""
			for i = 1, vis do
				local idx = modelScroll + i
				local item = modelList[idx]
				if item then
					local y = y0 + 14 + (i - 1) * (ROW_H + 4)
					local hot = focused and mx >= PAD and mx <= W - PAD - 48 and my >= y and my < y + ROW_H
					local on = (item.path == cur)
					drawBtn(PAD, y, W - PAD * 2 - 48, ROW_H, item.name, hot, on)
				end
			end
			drawBtn(W - PAD - 40, y0 + 14, 36, 40, "▲", false, false)
			drawBtn(W - PAD - 40, y0 + 214, 36, 40, "▼", false, false)
			drawBtn(PAD, H - 120, W - PAD * 2, 40, "USE MY PLAYER MODEL", false, false)
			drawBtn(PAD, H - 70, W - PAD * 2, 48, "SAVE TO PLAYER", false, false)
		elseif tab == 3 then
			local ent = s and s:GetEntity()
			if not IsValid(ent) then
				draw.SimpleText("open twin first…", "DermaDefault", W * 0.5, y0 + 40, Theme().muted, TEXT_ALIGN_CENTER)
			else
				draw.SimpleText("bodygroups · skins", "DermaDefault", PAD, y0 - 2, Theme().muted)
				local nbg = ent:GetNumBodyGroups() or 0
				local vis = 7
				for i = 1, vis do
					local bg = bodyScroll + i - 1
					if bg >= 0 and bg < nbg then
						local y = y0 + 16 + (i - 1) * (ROW_H + 6)
						local name = ent:GetBodygroupName(bg) or ("bg" .. bg)
						local val = ent:GetBodygroup(bg) or 0
						local cnt = ent:GetBodygroupCount(bg) or 1
						drawBtn(PAD, y, 48, ROW_H, "−", false, false)
						surface.SetDrawColor(Theme().row)
						surface.DrawRect(PAD + 52, y, W - PAD * 2 - 104, ROW_H)
						draw.SimpleText(string.format("%s  %d/%d", name, val, math.max(0, cnt - 1)), "DermaDefaultBold", W * 0.5, y + ROW_H * 0.5, Theme().text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
						drawBtn(W - PAD - 48, y, 48, ROW_H, "+", false, false)
					end
				end
				local sk = ent:GetSkin() or 0
				local nsk = ent:SkinCount() or 1
				drawBtn(PAD, H - 120, (W - PAD * 2 - 8) / 2, 40, "SKIN −", false, false)
				drawBtn(PAD + (W - PAD * 2 - 8) / 2 + 8, H - 120, (W - PAD * 2 - 8) / 2, 40, string.format("SKIN %d/%d", sk, math.max(0, nsk - 1)), false, false)
				drawBtn(PAD, H - 70, W - PAD * 2, 48, "SAVE TO PLAYER", false, false)
			end
		elseif tab == 4 then
			local s2 = sess()
			local hh = s2 and s2.hideHead
			local hh2 = s2 and s2.hideHands
			local tr = s2 and s2.showHandTrackers
			local lp = s2 and s2.laserPickBones
			local hoverName = s2 and s2.hoverBoneName
			local nHide = 0
			if s2 and s2.customHidden then
				for _ in pairs(s2.customHidden) do nHide = nHide + 1 end
			end
			draw.SimpleText("point laser at twin bone · trigger = hide/show", "DermaDefault", PAD, y0 - 4, Theme().muted)
			drawBtn(PAD, y0 + 8, W - PAD * 2, 40, hh and "HEAD HIDDEN" or "HIDE HEAD", false, hh)
			drawBtn(PAD, y0 + 54, W - PAD * 2, 40, hh2 and "HANDS HIDDEN" or "HIDE HANDS", false, hh2)
			drawBtn(PAD, y0 + 100, W - PAD * 2, 40, tr and "HAND TRACKERS ON" or "HAND TRACKERS", false, tr)
			drawBtn(PAD, y0 + 146, W - PAD * 2, 40, lp and "LASER PICK ON" or "LASER PICK OFF", false, lp)
			drawBtn(PAD, y0 + 192, W - PAD * 2, 40, "CLEAR HIDDEN (" .. nHide .. ")", false, false)
			drawBtn(PAD, y0 + 238, W - PAD * 2, 40, "RESTART TWIN", false, false)
			drawBtn(PAD, y0 + 284, W - PAD * 2, 40, "SAVE TO PLAYER", false, false)
			if hoverName then
				draw.SimpleText("aim: " .. hoverName, "DermaDefaultBold", W * 0.5, H - 36, Theme().hot, TEXT_ALIGN_CENTER)
			end
		end

		if statusMsg ~= "" and CurTime() < statusUntil then
			draw.SimpleText(statusMsg, "DermaDefaultBold", W * 0.5, H - 22, Theme().ok, TEXT_ALIGN_CENTER)
		end

		if focused and mx >= 0 then
			surface.SetDrawColor(Theme().hot)
			surface.DrawRect(mx - 2, my - 12, 4, 24)
			surface.DrawRect(mx - 12, my - 2, 24, 4)
		end
	end)
	VRUtilMenuRenderEnd()
	if not okPaint and vrmod.logger then
		vrmod.logger.Debug("avatar paint: %s", tostring(errPaint))
	end
end

local function doSave()
	local s = sess()
	if not s or not s.ApplyToPlayer then
		statusMsg = "no twin to save"
		statusUntil = CurTime() + 3
		return
	end
	local ok, info = s:ApplyToPlayer()
	if ok then
		statusMsg = "APPLIED · IK reload · " .. tostring(info)
		statusUntil = CurTime() + 5
		-- Second nudge: ensure character system + twin snap after timers fire
		timer.Simple(0.25, function()
			if vrmod.character and vrmod.character.ForceLocalIKAndPublish then
				pcall(vrmod.character.ForceLocalIKAndPublish)
			end
		end)
	else
		statusMsg = "apply failed · " .. tostring(info)
		statusUntil = CurTime() + 4
	end
end

local function activate(mx, my)
	rebuildButtons() -- hitboxes must match last layout
	mx, my = tonumber(mx) or 0, tonumber(my) or 0
	for _, btn in ipairs(buttons) do
		if mx < btn.x or mx > btn.x + btn.w or my < btn.y or my > btn.y + btn.h then
			-- skip
		else
		local k = btn.kind
		if k == "close" then
			vrmod.AvatarMenu_Close()
			return
		elseif k == "tab" then
			tab = btn.index
			return
		elseif k == "h_plus" then
			g_VR.scale = (g_VR.scale or 32) + 0.5
			if convars and convars.vrmod_scale then convars.vrmod_scale:SetFloat(g_VR.scale) end
		elseif k == "h_minus" then
			g_VR.scale = math.max(1, (g_VR.scale or 32) - 0.5)
			if convars and convars.vrmod_scale then convars.vrmod_scale:SetFloat(g_VR.scale) end
		elseif k == "h_auto" then
			AutoScale()
		elseif k == "h_seated" then
			if convars and convars.vrmod_seated then
				convars.vrmod_seated:SetBool(not seated())
			end
		elseif k == "h_offset" then
			vrmod.AutoSeatedOffset()
		elseif k == "reset_place" then
			local s = sess()
			if s then
				if s.SetMode then s:SetMode("free") end
				s.freeInited = false
				s.freeYaw = nil
			end
		elseif k == "dist_minus" then
			local s = sess()
			if s and s.SetDistance then s:SetDistance((s.distance or 40) - 4) end
		elseif k == "dist_plus" then
			local s = sess()
			if s and s.SetDistance then s:SetDistance((s.distance or 40) + 4) end
		elseif k == "yaw_ccw" then
			local s = sess()
			if s then
				s.freeYaw = (s.freeYaw or (s.standAng and s.standAng.yaw) or 0) + 15
				s.standAng = Angle(0, s.freeYaw, 0)
			end
		elseif k == "yaw_cw" then
			local s = sess()
			if s then
				s.freeYaw = (s.freeYaw or (s.standAng and s.standAng.yaw) or 0) - 15
				s.standAng = Angle(0, s.freeYaw, 0)
			end
		elseif k == "model" and modelList[btn.index] then
			local s = sess()
			if s and s.SetModel then
				-- Preview only (no archive) + IK refresh
				s:SetModel(modelList[btn.index].path, { persist = false })
				statusMsg = "preview · " .. tostring(modelList[btn.index].name or "")
				statusUntil = CurTime() + 2
			end
		elseif k == "model_up" then
			modelScroll = math.max(0, modelScroll - 1)
		elseif k == "model_dn" then
			modelScroll = math.min(math.max(0, #modelList - 8), modelScroll + 1)
		elseif k == "model_player" then
			local s = sess()
			local ply = LocalPlayer()
			if s and s.SetModel and IsValid(ply) then
				s:SetModel(ply.vrmod_pm or ply:GetModel(), { persist = false, keepLooks = true })
				statusMsg = "twin = live player model"
				statusUntil = CurTime() + 2
			end
		elseif k == "model_save" then
			doSave()
		elseif k == "bg_prev" then
			local s = sess()
			if s and s.CycleBodygroup then s:CycleBodygroup(btn.bg, -1) end
		elseif k == "bg_next" then
			local s = sess()
			if s and s.CycleBodygroup then s:CycleBodygroup(btn.bg, 1) end
		elseif k == "body_up" then
			bodyScroll = math.max(0, bodyScroll - 1)
		elseif k == "body_dn" then
			bodyScroll = bodyScroll + 1
		elseif k == "skin_prev" then
			local s = sess()
			local ent = s and s:GetEntity()
			if s and IsValid(ent) then
				local sk = (ent:GetSkin() or 0) - 1
				if sk < 0 then sk = math.max(0, (ent:SkinCount() or 1) - 1) end
				s:SetSkin(sk)
			end
		elseif k == "skin_next" then
			local s = sess()
			local ent = s and s:GetEntity()
			if s and IsValid(ent) then
				local n = ent:SkinCount() or 1
				s:SetSkin(((ent:GetSkin() or 0) + 1) % math.max(1, n))
			end
		elseif k == "toggle_head" then
			local s = sess()
			if s and s.SetHideHead then s:SetHideHead(not s.hideHead) end
		elseif k == "toggle_hands" then
			local s = sess()
			if s and s.SetHideHands then s:SetHideHands(not s.hideHands) end
		elseif k == "toggle_trackers" then
			local s = sess()
			if s then s.showHandTrackers = not s.showHandTrackers end
		elseif k == "toggle_laser_pick" then
			local s = sess()
			if s then s.laserPickBones = not s.laserPickBones end
		elseif k == "clear_hidden_bones" then
			local s = sess()
			if s and s.ClearCustomHidden then
				s:ClearCustomHidden()
				statusMsg = "cleared custom hidden bones"
				statusUntil = CurTime() + 3
			end
		elseif k == "restart_twin" then
			StartTwin()
		end
		return
		end -- hit box
	end
end

function vrmod.AvatarMenu_Close()
	-- Always force-clean even if open flag desynced (stuck menu)
	local wasOpen = open
	open = false
	StopTwin()
	hook.Remove("PreRender", "avatar_menu_paint")
	hook.Remove("VRMod_Input", "avatar_menu_input")
	hook.Remove("VRMod_Exit", "avatar_menu_exit")
	hook.Remove("VRMod_OpenQuickMenu", "avatar_menu_qm")
	hook.Remove("VRMod_Input", "vrmodheightmenuinput")
	hook.Remove("PreRender", "vrmodheightmenuplace")
	if g_VR and g_VR.menus then
		if g_VR.menus[UID] then
			g_VR.menus[UID].closeFunc = nil
			g_VR.menus[UID].grabHand = nil
			g_VR.menus[UID].freeFloat = false
		end
		if g_VR.menus.heightmenu then
			g_VR.menus.heightmenu.closeFunc = nil
			if isfunction(VRUtilMenuClose) then VRUtilMenuClose("heightmenu") end
		end
	end
	if isfunction(VRUtilMenuClose) then VRUtilMenuClose(UID) end
	g_VR.menuGrabActive = false
	if not wasOpen and vrmod.logger then
		vrmod.logger.Debug("[Avatar] close forced (flag was already false)")
	end
end

function vrmod.AvatarMenu_Open()
	if not (g_VR and g_VR.active) then
		if vrmod.logger then vrmod.logger.Warn("[Avatar] not in VR") end
		return
	end
	if open then
		vrmod.AvatarMenu_Close()
		return
	end
	if not isfunction(VRUtilMenuOpen) then
		if vrmod.logger then vrmod.logger.Warn("[Avatar] VRUtilMenuOpen missing") end
		return
	end

	-- Close competing hand menus so focus/laser works
	if g_VR.menus then
		for _, uid in ipairs({ "miscmenu", "heightmenu", "cube_settings", "cubeui_main" }) do
			if g_VR.menus[uid] and isfunction(VRUtilMenuClose) then
				g_VR.menus[uid].closeFunc = nil
				VRUtilMenuClose(uid)
			end
		end
	end
	hook.Remove("VRMod_Input", "vrmodheightmenuinput")
	hook.Remove("PreRender", "vrmodheightmenuplace")
	hook.Remove("PreRender", "vrutil_hook_renderigm")

	open = true
	tab = 1
	modelScroll = 0
	bodyScroll = 0
	modelList = (vrmod.avatar and vrmod.avatar.ListPlayerModels and vrmod.avatar.ListPlayerModels()) or {}
	livePos, liveAng, liveScale = WristPose()

	pcall(StartTwin)

	VRUtilMenuOpen(UID, W, H, nil, true, livePos, liveAng, liveScale, true, function()
		open = false
		StopTwin()
		hook.Remove("PreRender", "avatar_menu_paint")
		hook.Remove("VRMod_Input", "avatar_menu_input")
		hook.Remove("VRMod_OpenQuickMenu", "avatar_menu_qm")
	end)

	if not (g_VR.menus and g_VR.menus[UID] and g_VR.menus[UID].rt) then
		open = false
		StopTwin()
		if vrmod.logger then vrmod.logger.Warn("[Avatar] menu open failed (no RT)") end
		return
	end
	if vrmod.MenuApplyHandAnchor then
		vrmod.MenuApplyHandAnchor(g_VR.menus[UID], liveScale, livePos, liveAng, WristHand())
	else
		local am = g_VR.menus[UID]
		if not am.scaleLocked then am.scale = liveScale end
		am.pos = livePos
		am.ang = liveAng
		am.cubeMenu = true
		am.attachment = true
		am.attachHand = WristHand()
	end

	paint()

	hook.Add("PreRender", "avatar_menu_paint", function()
		if not open then
			hook.Remove("PreRender", "avatar_menu_paint")
			return
		end
		if not (g_VR.menus and g_VR.menus[UID] and g_VR.menus[UID].rt) then
			open = false
			return
		end
		if vrmod.MenuApplyHandAnchor then
			vrmod.MenuApplyHandAnchor(g_VR.menus[UID], liveScale, livePos, liveAng, WristHand())
		elseif not g_VR.menus[UID].freeFloat and not g_VR.menus[UID].grabHand then
			local am = g_VR.menus[UID]
			if not am.scaleLocked then am.scale = liveScale end
			am.pos = livePos
			am.ang = liveAng
			am.attachment = true
		am.attachHand = WristHand()
			am.cubeMenu = true
		end
		paint()
	end)

	hook.Add("VRMod_Input", "avatar_menu_input", function(action, pressed)
		if not open then return end
		-- B / secondary / chat / use always closes (even if laser focus lost)
		if pressed and (
			action == "boolean_secondaryfire"
			or action == "boolean_chat"
			or action == "boolean_use"
			or action == "boolean_changeweapon"
		) then
			vrmod.AvatarMenu_Close()
			return
		end
		if not pressed then return end
		if not (vrmod.IsMenuPrimaryClick and vrmod.IsMenuPrimaryClick(action)) then return end

		-- Always try UI hit-test if menu exists (don't require menuFocus — free-float lag)
		local cx, cy = g_VR.menuCursorX, g_VR.menuCursorY
		if (g_VR.menuFocus == UID or g_VR.menus and g_VR.menus[UID]) and cx and cy then
			-- Prefer close if cursor is in header corner even without perfect focus
			if cx >= W - 64 and cy <= 48 then
				vrmod.AvatarMenu_Close()
				return
			end
			if g_VR.menuFocus == UID then
				activate(cx, cy)
				return
			end
		end

		local s = sess()
		if s and s.laserPickBones and s.ToggleCustomBone then
			s:UpdateLaserHover()
			local id = s.hoverBoneId
			if id then
				local ok, name, hidden = s:ToggleCustomBone(id)
				if ok then
					statusMsg = (hidden and "HID " or "SHOW ") .. tostring(name)
					statusUntil = CurTime() + 2.5
				end
			end
		end
	end)

	local t0 = CurTime()
	hook.Add("VRMod_OpenQuickMenu", "avatar_menu_qm", function()
		if not open then return end
		if CurTime() - t0 < 0.5 then return end
		timer.Simple(0, function()
			if open then vrmod.AvatarMenu_Close() end
		end)
	end)

	hook.Add("VRMod_Exit", "avatar_menu_exit", function()
		vrmod.AvatarMenu_Close()
	end)

	if vrmod.logger then
		vrmod.logger.Info("[Avatar] open · models=%d · focus uid=%s", #modelList, UID)
	end
end

function vrmod.AvatarMenu_IsOpen()
	return open
end

-- Legacy height entry → full Avatar experience
function VRUtilOpenHeightMenu()
	vrmod.AvatarMenu_Open()
end

concommand.Add("vrmod_avatar", function()
	vrmod.AvatarMenu_Open()
end)

concommand.Add("vrmod_avatar_close", function()
	vrmod.AvatarMenu_Close()
end)
