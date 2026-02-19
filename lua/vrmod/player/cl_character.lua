if CLIENT then
	g_VR = g_VR or {}
	g_VR.characterYaw = 0
	local convars, convarValues = vrmod.GetConvars()
	-- Constants
	local NUM_FINGER_BONES = 30
	local ZERO_VEC = Vector()
	local ZERO_ANG = Angle()
	local RIGHT_HAND_OFFSET = Angle(0, 0, 180)
	local zeroVec, zeroAng = ZERO_VEC, ZERO_ANG

	------------------------------------------------------------------------
	-- CONVARS
	------------------------------------------------------------------------
	vrmod.AddCallbackedConvar("vrmod_charactereyeheight", "characterEyeHeight", "66.8", FCVAR_ARCHIVE, "Character eye height", 30, 100, tonumber)
	vrmod.AddCallbackedConvar("vrmod_characterheadtohmddist", "characterHeadToHmdDist", "6.3", FCVAR_ARCHIVE, "Head to HMD distance", 0, 20, tonumber)
	vrmod.AddCallbackedConvar("vrmod_characterik", "characterIK", "1", FCVAR_ARCHIVE, "Enable character IK", nil, nil, tobool)
	vrmod.AddCallbackedConvar("vrmod_armstretcher", "armStretcher", "0", FCVAR_ARCHIVE, "Enable arm stretching", nil, nil, tobool)

	------------------------------------------------------------------------
	-- SPAWN MENU
	------------------------------------------------------------------------
function CreateCharacterPanel(panel)
    panel:ClearControls()
    panel:SetName("VR Character Animations")
    panel:Help("Controls for VR character animations, arm stretching, and model calibration.")
    panel:ControlHelp("\n--- Animation System ---")
    local animCheckbox = panel:CheckBox("Disable Animations")
    animCheckbox:SetChecked(not GetConVar("vrmod_characterik"):GetBool())
    function animCheckbox:OnChange(val)
        RunConsoleCommand("vrmod_characterik", val and "0" or "1")
    end
    panel:Help("When checked, the player model stays in place without animations.")
    panel:CheckBox("Enable Arm Stretcher", "vrmod_armstretcher")
    panel:Help("Stretches arm bones to reach targets beyond the model's natural arm length.")
    panel:ControlHelp("\n--- Model Calibration ---")
    panel:NumSlider("Eye Height", "vrmod_charactereyeheight", 30, 100, 1)
    panel:Help("Character eye height in source units. Default 66.8. Affects crouching and body position.")
    panel:NumSlider("Head to HMD Distance", "vrmod_characterheadtohmddist", 0, 20, 1)
    panel:Help("Distance from HMD to head bone. Default 6.3.")
    panel:ControlHelp("\n")
    local restoreBtn = panel:Button("Restore Defaults")
    restoreBtn.DoClick = function()
        RunConsoleCommand("vrmod_characterik", "1")
        RunConsoleCommand("vrmod_armstretcher", "0")
        RunConsoleCommand("vrmod_charactereyeheight", "66.8")
        RunConsoleCommand("vrmod_characterheadtohmddist", "6.3")
        chat.AddText(Color(100, 255, 100), "[VR Character] ", Color(255, 255, 255), "Settings reset to defaults!")
    end
end

	------------------------------------------------------------------------
	-- VR MIRROR: Separate panel that appears when heightmenu is open
	------------------------------------------------------------------------
	local charIKMenuOpen = false

	local function OpenCharIKPanel()
		if charIKMenuOpen then return end
		if not VRUtilIsMenuOpen("heightmenu") then return end
		charIKMenuOpen = true

		VRUtilMenuOpen("charik", 200, 200, nil, nil, Vector(), Angle(), 0.1, true, function()
			hook.Remove("PreRender", "VRModCharIK_RenderPanel")
			hook.Remove("VRMod_Input", "VRModCharIK_PanelInput")
			charIKMenuOpen = false
		end)

		local buttons = {}

		local function rebuildButtons()
			buttons = {
				{ x = 0,   y = 5,   w = 55, h = 35, text = "Eye +",  font = "Trebuchet18", text_x = 27, text_y = 8,
					fn = function() RunConsoleCommand("vrmod_charactereyeheight", tostring(math.Clamp((convarValues.characterEyeHeight or 66.8) + 1, 30, 100))) end },
				{ x = 0,   y = 45,  w = 55, h = 35, text = "Eye -",  font = "Trebuchet18", text_x = 27, text_y = 8,
					fn = function() RunConsoleCommand("vrmod_charactereyeheight", tostring(math.Clamp((convarValues.characterEyeHeight or 66.8) - 1, 30, 100))) end },
				{ x = 60,  y = 5,   w = 55, h = 35, text = "HMD +",  font = "Trebuchet18", text_x = 27, text_y = 8,
					fn = function() RunConsoleCommand("vrmod_characterheadtohmddist", tostring(math.Clamp((convarValues.characterHeadToHmdDist or 6.3) + 0.5, 0, 20))) end },
				{ x = 60,  y = 45,  w = 55, h = 35, text = "HMD -",  font = "Trebuchet18", text_x = 27, text_y = 8,
					fn = function() RunConsoleCommand("vrmod_characterheadtohmddist", tostring(math.Clamp((convarValues.characterHeadToHmdDist or 6.3) - 0.5, 0, 20))) end },
				{ x = 120, y = 5,   w = 75, h = 35, text = "Auto\nEye",  font = "Trebuchet18", text_x = 37, text_y = 1,
					fn = function()
						if g_VR and g_VR.tracking and g_VR.tracking.hmd and g_VR.origin then
							local h = (g_VR.tracking.hmd.pos.z - g_VR.origin.z)
							if g_VR.scale then h = h / g_VR.scale end
							h = math.Clamp(math.Round(h, 1), 30, 100)
							RunConsoleCommand("vrmod_charactereyeheight", tostring(h))
						end
					end },
				{ x = 120, y = 45,  w = 75, h = 35, text = convarValues.characterIK and "Anim: ON" or "Anim: OFF", font = "Trebuchet18", text_x = 37, text_y = 8,
					fn = function() RunConsoleCommand("vrmod_characterik", convarValues.characterIK and "0" or "1") end },
				{ x = 0,   y = 90,  w = 95, h = 35, text = convarValues.armStretcher and "Stretch: ON" or "Stretch: OFF", font = "Trebuchet18", text_x = 47, text_y = 8,
					fn = function() RunConsoleCommand("vrmod_armstretcher", convarValues.armStretcher and "0" or "1") end },
				{ x = 100, y = 90,  w = 95, h = 35, text = "Defaults",  font = "Trebuchet18", text_x = 47, text_y = 8,
					fn = function()
						RunConsoleCommand("vrmod_charactereyeheight", "66.8")
						RunConsoleCommand("vrmod_characterheadtohmddist", "6.3")
						RunConsoleCommand("vrmod_characterik", "1")
						RunConsoleCommand("vrmod_armstretcher", "0")
					end },
			}
		end

		rebuildButtons()

		local lastEyeH, lastHmdD, lastIK, lastStretch = -1, -1, nil, nil

		hook.Add("PreRender", "VRModCharIK_RenderPanel", function()
			if not VRUtilIsMenuOpen("charik") then return end
			-- Only redraw if values changed
			local eyeH = convarValues.characterEyeHeight or 66.8
			local hmdD = convarValues.characterHeadToHmdDist or 6.3
			local ik = convarValues.characterIK
			local stretch = convarValues.armStretcher
			if eyeH == lastEyeH and hmdD == lastHmdD and ik == lastIK and stretch == lastStretch then return end
			lastEyeH, lastHmdD, lastIK, lastStretch = eyeH, hmdD, ik, stretch
			rebuildButtons()

			VRUtilMenuRenderStart("charik")
			-- Labels
			draw.DrawText(string.format("Eye: %.1f  HMD: %.1f", eyeH, hmdD), "Trebuchet18", 3, 135, color_white, TEXT_ALIGN_LEFT)
			draw.DrawText("Character Animations", "Trebuchet18", 3, 155, Color(150, 200, 255), TEXT_ALIGN_LEFT)
			-- Buttons
			for _, btn in ipairs(buttons) do
				surface.SetDrawColor(0, 0, 0, 220)
				surface.DrawRect(btn.x, btn.y, btn.w, btn.h)
				draw.DrawText(btn.text, btn.font, btn.x + btn.text_x, btn.y + btn.text_y, color_white, TEXT_ALIGN_CENTER)
			end
			VRUtilMenuRenderEnd()
		end)

		hook.Add("VRMod_Input", "VRModCharIK_PanelInput", function(action, pressed)
			if g_VR.menuFocus ~= "charik" then return end
			if action ~= "boolean_primaryfire" or not pressed then return end
			for _, btn in ipairs(buttons) do
				if g_VR.menuCursorX > btn.x and g_VR.menuCursorX < btn.x + btn.w and g_VR.menuCursorY > btn.y and g_VR.menuCursorY < btn.y + btn.h then
					btn.fn()
					-- Force redraw
					lastEyeH = -1
				end
			end
		end)

		-- Position panel near the height menu (slightly to the right and below)
		-- The height menu positions itself dynamically; we piggyback off its transform
		hook.Add("PreDrawTranslucentRenderables", "VRModCharIK_PositionPanel", function()
			if not VRUtilIsMenuOpen("heightmenu") or not VRUtilIsMenuOpen("charik") then
				if charIKMenuOpen then
					VRUtilMenuClose("charik")
				end
				hook.Remove("PreDrawTranslucentRenderables", "VRModCharIK_PositionPanel")
				return
			end
			if g_VR.menus and g_VR.menus.heightmenu and g_VR.menus.charik then
				local hm = g_VR.menus.heightmenu
				-- Place below the height menu
				g_VR.menus.charik.pos = hm.pos + hm.ang:Up() * -20
				g_VR.menus.charik.ang = hm.ang
			end
		end)
	end

	-- Auto-open our panel when the height menu opens, auto-close when it closes
	hook.Add("Think", "VRModCharIK_WatchHeightMenu", function()
		if not g_VR or not g_VR.active then
			if charIKMenuOpen then VRUtilMenuClose("charik") end
			return
		end
		if VRUtilIsMenuOpen and VRUtilIsMenuOpen("heightmenu") then
			if not charIKMenuOpen then OpenCharIKPanel() end
		elseif charIKMenuOpen then
			VRUtilMenuClose("charik")
		end
	end)

	------------------------------------------------------------------------
	-- HAND ANGLES
	------------------------------------------------------------------------
	g_VR.zeroHandAngles = {}
	for i = 1, NUM_FINGER_BONES do
		g_VR.zeroHandAngles[i] = Angle(0, 0, 0)
	end

	g_VR.defaultOpenHandAngles = {
		Angle(5, 10, 0), Angle(0, -20, 5), Angle(0, -10, 0),
		Angle(0, -3, 1), Angle(0, -2, 0), Angle(0, -1, 0),
		Angle(0, 0, 0), Angle(0, -2, 0), Angle(0, -1, 0),
		Angle(0, 2, -1), Angle(0, -1, 0), Angle(0, 0, 0),
		Angle(0, 4, -1), Angle(0, 0, 0), Angle(0, 0, 0),
		Angle(5, -10, 0), Angle(0, -20, -5), Angle(0, -10, 0),
		Angle(0, 3, -1), Angle(0, -2, 0), Angle(0, -1, 0),
		Angle(0, 0, 0), Angle(0, -2, 0), Angle(0, -1, 0),
		Angle(0, -2, 1), Angle(0, -1, 0), Angle(0, 0, 0),
		Angle(0, -4, 1), Angle(0, 0, 0), Angle(0, 0, 0),
	}

	g_VR.defaultClosedHandAngles = {
		Angle(30, 0, 0), Angle(0, 0, 0), Angle(0, 30, 0),
		Angle(0, -50, -10), Angle(0, -90, 0), Angle(0, -70, 0),
		Angle(0, -35.8, 0), Angle(0, -80, 0), Angle(0, -70, 0),
		Angle(0, -26.5, 4.8), Angle(0, -70, 0), Angle(0, -70, 0),
		Angle(0, -30, 12.7), Angle(0, -70, 0), Angle(0, -70, 0),
		Angle(-30, 0, 0), Angle(0, 0, 0), Angle(0, 30, 0),
		Angle(0, -50, 10), Angle(0, -90, 0), Angle(0, -70, 0),
		Angle(0, -35.8, 0), Angle(0, -80, 0), Angle(0, -70, 0),
		Angle(0, -26.5, -4.8), Angle(0, -70, 0), Angle(0, -70, 0),
		Angle(0, -30, -12.7), Angle(0, -70, 0), Angle(0, -70, 0),
	}

	g_VR.openHandAngles = g_VR.defaultOpenHandAngles
	g_VR.closedHandAngles = g_VR.defaultClosedHandAngles

	----------------------------------------------------------------------------------------------------------------------------------------------------
	-- CHARACTER SYSTEM
	----------------------------------------------------------------------------------------------------------------------------------------------------
	local prevFrameNumber = 0
	local characterInfo = {}
	local activePlayers = {}
	local updatedPlayers = {}

	local function RecursiveBoneTable2(ent, parentbone, infotab, ordertab, notfirst)
		local bones = notfirst and ent:GetChildBones(parentbone) or {parentbone}
		for k, v in pairs(bones) do
			local n = ent:GetBoneName(v)
			local boneparent = ent:GetBoneParent(v)
			local parentmat = ent:GetBoneMatrix(boneparent)
			local childmat = ent:GetBoneMatrix(v)
			local parentpos, parentang = parentmat:GetTranslation(), parentmat:GetAngles()
			local childpos, childang = childmat:GetTranslation(), childmat:GetAngles()
			local relpos, relang = WorldToLocal(childpos, childang, parentpos, parentang)
			infotab[v] = {
				name = n,
				pos = Vector(0, 0, 0),
				ang = Angle(0, 0, 0),
				parent = boneparent,
				relativePos = relpos,
				relativeAng = relang,
				offsetAng = Angle(0, 0, 0)
			}
			ordertab[#ordertab + 1] = v
		end
		for k, v in pairs(bones) do
			RecursiveBoneTable2(ent, v, infotab, ordertab, true)
		end
	end

	local function UpdateIK(ply)
		local steamid = ply:SteamID()
		local net = g_VR.net[steamid]
		local charinfo = characterInfo[steamid]
		local boneinfo = charinfo.boneinfo
		local bones = charinfo.bones
		local frame = net.lerpedFrame
		local inVehicle = ply:InVehicle()
		local plyAng = inVehicle and ply:GetVehicle():GetAngles() or Angle(0, frame.characterYaw, 0)
		if inVehicle then _, plyAng = LocalToWorld(zeroVec, Angle(0, 90, 0), zeroVec, plyAng) end

		-- Read from convars every frame (reactive to slider changes)
		local eyeHeight = convarValues.characterEyeHeight or 66.8
		local headToHmdDist = convarValues.characterHeadToHmdDist or 6.3

		-- Alt head
		if net.characterAltHead then
			local _, tmp2 = WorldToLocal(zeroVec, frame.hmdAng, zeroVec, Angle(0, frame.characterYaw, 0))
			ply:ManipulateBoneAngles(bones.b_head, Angle(-tmp2.roll, -tmp2.pitch, tmp2.yaw))
		end

		-- Crouching
		if not inVehicle then
			local headHeight = frame.hmdPos.z + (frame.hmdAng:Forward() * -3).z
			local cutAmount = math.Clamp(charinfo.preRenderPos.z + eyeHeight - headHeight, 0, 40)
			local spineLen = eyeHeight - charinfo.spineZ
			local spineTargetLen = spineLen - cutAmount * 0.5
			local a1 = math.acos(math.Clamp(spineTargetLen / spineLen, -1, 1))
			charinfo.horizontalCrouchOffset = math.sin(a1) * spineLen
			ply:ManipulateBoneAngles(bones.b_spine, Angle(0, math.deg(a1), 0))
			charinfo.verticalCrouchOffset = cutAmount * 0.5
			local legTargetLen = charinfo.upperLegLen + charinfo.lowerLegLen - charinfo.verticalCrouchOffset * 0.8
			local cosA1 = (charinfo.upperLegLen * charinfo.upperLegLen + legTargetLen * legTargetLen - charinfo.lowerLegLen * charinfo.lowerLegLen) / (2 * charinfo.upperLegLen * legTargetLen)
			local cosA23 = (charinfo.lowerLegLen * charinfo.lowerLegLen + legTargetLen * legTargetLen - charinfo.upperLegLen * charinfo.upperLegLen) / (2 * charinfo.lowerLegLen * legTargetLen)
			local a1 = math.deg(math.acos(math.Clamp(cosA1, -1, 1)))
			local a23 = 180 - a1 - math.deg(math.acos(math.Clamp(cosA23, -1, 1)))
			if a1 ~= a1 or a23 ~= a23 then a1 = 0 a23 = 180 end
			ply:ManipulateBoneAngles(bones.b_leftCalf, Angle(0, -(a23 - 180), 0))
			ply:ManipulateBoneAngles(bones.b_leftThigh, Angle(0, -a1, 0))
			ply:ManipulateBoneAngles(bones.b_rightCalf, Angle(0, -(a23 - 180), 0))
			ply:ManipulateBoneAngles(bones.b_rightThigh, Angle(0, -a1, 0))
			ply:ManipulateBoneAngles(bones.b_leftFoot, Angle(0, -a1, 0))
			ply:ManipulateBoneAngles(bones.b_rightFoot, Angle(0, -a1, 0))
		else
			ply:ManipulateBoneAngles(bones.b_spine, Angle(0, 0, 0))
			ply:ManipulateBoneAngles(bones.b_leftCalf, Angle(0, 0, 0))
			ply:ManipulateBoneAngles(bones.b_leftThigh, Angle(0, 0, 0))
			ply:ManipulateBoneAngles(bones.b_rightCalf, Angle(0, 0, 0))
			ply:ManipulateBoneAngles(bones.b_rightThigh, Angle(0, 0, 0))
			ply:ManipulateBoneAngles(bones.b_leftFoot, Angle(0, 0, 0))
			ply:ManipulateBoneAngles(bones.b_rightFoot, Angle(0, 0, 0))
		end

		-- LEFT ARM
		local L_TargetPos = frame.lefthandPos
		local L_TargetAng = frame.lefthandAng
		local mtx = ply:GetBoneMatrix(bones.b_leftClavicle)
		local L_ClaviclePos = mtx and mtx:GetTranslation() or Vector()
		charinfo.L_ClaviclePos = L_ClaviclePos
		local tmp1 = L_ClaviclePos + plyAng:Right() * -charinfo.clavicleLen
		local tmp2 = tmp1 + (L_TargetPos - tmp1) * 0.15
		local L_ClavicleTargetAng
		if not inVehicle then
			L_ClavicleTargetAng = (tmp2 - L_ClaviclePos):Angle()
		else
			_, L_ClavicleTargetAng = LocalToWorld(Vector(), WorldToLocal(tmp2 - L_ClaviclePos, zeroAng, zeroVec, plyAng):Angle(), zeroVec, plyAng)
		end
		L_ClavicleTargetAng:RotateAroundAxis(L_ClavicleTargetAng:Forward(), 90)
		local L_UpperarmPos = LocalToWorld(boneinfo[bones.b_leftUpperarm].relativePos, boneinfo[bones.b_leftUpperarm].relativeAng, L_ClaviclePos, L_ClavicleTargetAng)
		local L_TargetVec = L_TargetPos - L_UpperarmPos
		local L_TargetVecLen = L_TargetVec:Length()
		local L_TargetVecAng, L_TargetVecAngLocal
		if not inVehicle then
			L_TargetVecAng = L_TargetVec:Angle()
		else
			L_TargetVecAngLocal = WorldToLocal(L_TargetVec, zeroAng, zeroVec, plyAng):Angle()
			_, L_TargetVecAng = LocalToWorld(Vector(), L_TargetVecAngLocal, zeroVec, plyAng)
		end
		local L_UpperarmTargetAng = Angle(L_TargetVecAng.pitch, L_TargetVecAng.yaw, L_TargetVecAng.roll)
		local tmp
		if not inVehicle then tmp = Angle(L_TargetVecAng.pitch, frame.characterYaw, -90)
		else _, tmp = LocalToWorld(Vector(), Angle(L_TargetVecAngLocal.pitch, 0, -90), zeroVec, plyAng) end
		local _, tang = WorldToLocal(zeroVec, tmp, zeroVec, L_TargetVecAng)
		L_UpperarmTargetAng:RotateAroundAxis(L_UpperarmTargetAng:Forward(), tang.roll)
		local L_totalArmLen = charinfo.upperArmLen + charinfo.lowerArmLen
		local L_armStretchScale = 1
		local L_effUpper, L_effLower = charinfo.upperArmLen, charinfo.lowerArmLen
		if convarValues.armStretcher and L_TargetVecLen > L_totalArmLen * 0.98 then
			L_armStretchScale = L_TargetVecLen / (L_totalArmLen * 0.98)
			L_effUpper = charinfo.upperArmLen * L_armStretchScale
			L_effLower = charinfo.lowerArmLen * L_armStretchScale
		end
		charinfo.L_armStretchScale = L_armStretchScale
		local a1 = math.deg(math.acos(math.Clamp((L_effUpper * L_effUpper + L_TargetVecLen * L_TargetVecLen - L_effLower * L_effLower) / (2 * L_effUpper * L_TargetVecLen), -1, 1)))
		if a1 == a1 then L_UpperarmTargetAng:RotateAroundAxis(L_UpperarmTargetAng:Up(), a1) end
		local test
		if not inVehicle then test = ((L_TargetPos.z - L_UpperarmPos.z) + 20) * 1.5
		else test = ((L_TargetPos - L_UpperarmPos):Dot(plyAng:Up()) + 20) * 1.5 end
		if test < 0 then test = 0 end
		L_UpperarmTargetAng:RotateAroundAxis(L_TargetVec:GetNormalized(), 30 + test)
		local L_ForearmTargetAng = Angle(L_UpperarmTargetAng.pitch, L_UpperarmTargetAng.yaw, L_UpperarmTargetAng.roll)
		local a23 = 180 - a1 - math.deg(math.acos(math.Clamp((L_effLower * L_effLower + L_TargetVecLen * L_TargetVecLen - L_effUpper * L_effUpper) / (2 * L_effLower * L_TargetVecLen), -1, 1)))
		if a23 == a23 then L_ForearmTargetAng:RotateAroundAxis(L_ForearmTargetAng:Up(), 180 + a23) end
		local tmp = Angle(L_TargetAng.pitch, L_TargetAng.yaw, L_TargetAng.roll - 90)
		local _, tang = WorldToLocal(zeroVec, tmp, zeroVec, L_ForearmTargetAng)
		local L_WristTargetAng = Angle(L_ForearmTargetAng.pitch, L_ForearmTargetAng.yaw, L_ForearmTargetAng.roll)
		L_WristTargetAng:RotateAroundAxis(L_WristTargetAng:Forward(), tang.roll)
		local L_UlnaTargetAng = LerpAngle(0.5, L_ForearmTargetAng, L_WristTargetAng)

		-- RIGHT ARM
		local R_TargetPos = frame.righthandPos
		local R_TargetAng = frame.righthandAng
		local mtx = ply:GetBoneMatrix(bones.b_rightClavicle)
		local R_ClaviclePos = mtx and mtx:GetTranslation() or Vector()
		charinfo.R_ClaviclePos = R_ClaviclePos
		local tmp1 = R_ClaviclePos + plyAng:Right() * charinfo.clavicleLen
		local tmp2 = tmp1 + (R_TargetPos - tmp1) * 0.15
		local R_ClavicleTargetAng
		if not inVehicle then
			R_ClavicleTargetAng = (tmp2 - R_ClaviclePos):Angle()
		else
			_, R_ClavicleTargetAng = LocalToWorld(Vector(), WorldToLocal(tmp2 - R_ClaviclePos, zeroAng, zeroVec, plyAng):Angle(), zeroVec, plyAng)
		end
		R_ClavicleTargetAng:RotateAroundAxis(R_ClavicleTargetAng:Forward(), 90)
		local R_UpperarmPos = LocalToWorld(boneinfo[bones.b_rightUpperarm].relativePos, boneinfo[bones.b_rightUpperarm].relativeAng, R_ClaviclePos, R_ClavicleTargetAng)
		local R_TargetVec = R_TargetPos - R_UpperarmPos
		local R_TargetVecLen = R_TargetVec:Length()
		local R_TargetVecAng, R_TargetVecAngLocal
		if not inVehicle then
			R_TargetVecAng = R_TargetVec:Angle()
		else
			R_TargetVecAngLocal = WorldToLocal(R_TargetVec, zeroAng, zeroVec, plyAng):Angle()
			_, R_TargetVecAng = LocalToWorld(Vector(), R_TargetVecAngLocal, zeroVec, plyAng)
		end
		local R_UpperarmTargetAng = Angle(R_TargetVecAng.pitch, R_TargetVecAng.yaw, R_TargetVecAng.roll)
		R_UpperarmTargetAng:RotateAroundAxis(R_TargetVec, 180)
		local tmp
		if not inVehicle then tmp = Angle(R_TargetVecAng.pitch, frame.characterYaw, 90)
		else _, tmp = LocalToWorld(Vector(), Angle(R_TargetVecAngLocal.pitch, 0, 90), zeroVec, plyAng) end
		local _, tang = WorldToLocal(zeroVec, tmp, zeroVec, R_TargetVecAng)
		R_UpperarmTargetAng:RotateAroundAxis(R_UpperarmTargetAng:Forward(), tang.roll)
		local R_totalArmLen = charinfo.upperArmLen + charinfo.lowerArmLen
		local R_armStretchScale = 1
		local R_effUpper, R_effLower = charinfo.upperArmLen, charinfo.lowerArmLen
		if convarValues.armStretcher and R_TargetVecLen > R_totalArmLen * 0.98 then
			R_armStretchScale = R_TargetVecLen / (R_totalArmLen * 0.98)
			R_effUpper = charinfo.upperArmLen * R_armStretchScale
			R_effLower = charinfo.lowerArmLen * R_armStretchScale
		end
		charinfo.R_armStretchScale = R_armStretchScale
		local a1 = math.deg(math.acos(math.Clamp((R_effUpper * R_effUpper + R_TargetVecLen * R_TargetVecLen - R_effLower * R_effLower) / (2 * R_effUpper * R_TargetVecLen), -1, 1)))
		if a1 == a1 then R_UpperarmTargetAng:RotateAroundAxis(R_UpperarmTargetAng:Up(), a1) end
		local test
		if not inVehicle then test = ((R_TargetPos.z - R_UpperarmPos.z) + 20) * 1.5
		else test = ((R_TargetPos - R_UpperarmPos):Dot(plyAng:Up()) + 20) * 1.5 end
		if test < 0 then test = 0 end
		R_UpperarmTargetAng:RotateAroundAxis(R_TargetVec:GetNormalized(), -(30 + test))
		local R_ForearmTargetAng = Angle(R_UpperarmTargetAng.pitch, R_UpperarmTargetAng.yaw, R_UpperarmTargetAng.roll)
		local a23 = 180 - a1 - math.deg(math.acos(math.Clamp((R_effLower * R_effLower + R_TargetVecLen * R_TargetVecLen - R_effUpper * R_effUpper) / (2 * R_effLower * R_TargetVecLen), -1, 1)))
		if a23 == a23 then R_ForearmTargetAng:RotateAroundAxis(R_ForearmTargetAng:Up(), 180 + a23) end
		local tmp = Angle(R_TargetAng.pitch, R_TargetAng.yaw, R_TargetAng.roll - 90)
		local _, tang = WorldToLocal(zeroVec, tmp, zeroVec, R_ForearmTargetAng)
		local R_WristTargetAng = Angle(R_ForearmTargetAng.pitch, R_ForearmTargetAng.yaw, R_ForearmTargetAng.roll)
		R_WristTargetAng:RotateAroundAxis(R_WristTargetAng:Forward(), tang.roll)
		local R_UlnaTargetAng = LerpAngle(0.5, R_ForearmTargetAng, R_WristTargetAng)

		-- Override angles
		boneinfo[bones.b_leftClavicle].overrideAng = L_ClavicleTargetAng
		boneinfo[bones.b_leftUpperarm].overrideAng = L_UpperarmTargetAng
		boneinfo[bones.b_leftHand].overrideAng = L_TargetAng
		boneinfo[bones.b_rightClavicle].overrideAng = R_ClavicleTargetAng
		boneinfo[bones.b_rightUpperarm].overrideAng = R_UpperarmTargetAng
		boneinfo[bones.b_rightHand].overrideAng = R_TargetAng + Angle(0, 0, 180)
		-- Hand position override for stretching
		charinfo.L_HandTargetPos = (charinfo.L_armStretchScale ~= 1) and L_TargetPos or nil
		charinfo.R_HandTargetPos = (charinfo.R_armStretchScale ~= 1) and R_TargetPos or nil
		if bones.b_leftWrist and boneinfo[bones.b_leftWrist] and bones.b_leftUlna and boneinfo[bones.b_leftUlna] then
			boneinfo[bones.b_leftForearm].overrideAng = L_ForearmTargetAng
			boneinfo[bones.b_leftWrist].overrideAng = L_WristTargetAng
			boneinfo[bones.b_leftUlna].overrideAng = L_UlnaTargetAng
			boneinfo[bones.b_rightForearm].overrideAng = R_ForearmTargetAng
			boneinfo[bones.b_rightWrist].overrideAng = R_WristTargetAng
			boneinfo[bones.b_rightUlna].overrideAng = R_UlnaTargetAng
		else
			boneinfo[bones.b_leftForearm].overrideAng = L_UlnaTargetAng
			boneinfo[bones.b_rightForearm].overrideAng = R_UlnaTargetAng
		end
		-- Fingers
		for k, v in pairs(bones.fingers) do
			if not boneinfo[v] then continue end
			boneinfo[v].offsetAng = LerpAngle(frame["finger" .. math.floor((k - 1) / 3 + 1)], g_VR.openHandAngles[k], g_VR.closedHandAngles[k])
		end
		-- Target matrices (fresh Matrix each frame to prevent scale accumulation)
		for i = 1, #charinfo.boneorder do
			local bone = charinfo.boneorder[i]
			local bd = boneinfo[bone]
			local wpos, wang
			if bd.name == "ValveBiped.Bip01_L_Clavicle" then wpos = charinfo.L_ClaviclePos
			elseif bd.name == "ValveBiped.Bip01_R_Clavicle" then wpos = charinfo.R_ClaviclePos
			else wpos, wang = LocalToWorld(bd.relativePos, bd.relativeAng + bd.offsetAng, boneinfo[bd.parent].pos, boneinfo[bd.parent].ang) end
			if bd.overrideAng ~= nil then wang = bd.overrideAng end
			if charinfo.L_HandTargetPos and bd.name == "ValveBiped.Bip01_L_Hand" then wpos = charinfo.L_HandTargetPos
			elseif charinfo.R_HandTargetPos and bd.name == "ValveBiped.Bip01_R_Hand" then wpos = charinfo.R_HandTargetPos end
			local mat = Matrix()
			mat:Translate(wpos)
			mat:Rotate(wang)
			if charinfo.L_armStretchScale ~= 1 and (bd.name == "ValveBiped.Bip01_L_UpperArm" or bd.name == "ValveBiped.Bip01_L_Forearm") then
				mat:Scale(Vector(charinfo.L_armStretchScale, 1, 1))
			end
			if charinfo.R_armStretchScale ~= 1 and (bd.name == "ValveBiped.Bip01_R_UpperArm" or bd.name == "ValveBiped.Bip01_R_Forearm") then
				mat:Scale(Vector(charinfo.R_armStretchScale, 1, 1))
			end
			bd.targetMatrix = mat
			bd.pos = wpos
			bd.ang = wang
		end
	end

	------------------------------------------------------------------------
	local function CharacterInit(ply)
		local steamid = ply:SteamID()
		local pmname = ply:GetModel()
		if characterInfo[steamid] and characterInfo[steamid].modelName == pmname then return end
		if ply == LocalPlayer() then
			timer.Create("vrutil_timer_validatefingertracking", 0.1, 0, function()
				if g_VR.tracking.pose_lefthand and g_VR.tracking.pose_righthand and g_VR.tracking.pose_lefthand.simulatedPos == nil and g_VR.tracking.pose_righthand.simulatedPos == nil then
					timer.Remove("vrutil_timer_validatefingertracking")
					for i = 1, 2 do
						for k, v in pairs(i == 1 and g_VR.input.skeleton_lefthand.fingerCurls or g_VR.input.skeleton_righthand.fingerCurls) do
							if v < 0 or v > 1 or (k == 3 and v == 0.75) then
								g_VR.defaultOpenHandAngles = g_VR.zeroHandAngles
								g_VR.defaultClosedHandAngles = g_VR.zeroHandAngles
								g_VR.openHandAngles = g_VR.zeroHandAngles
								g_VR.closedHandAngles = g_VR.zeroHandAngles
								break
							end
						end
					end
				end
			end)
		end

		characterInfo[steamid] = {
			preRenderPos = Vector(0, 0, 0),
			renderPos = Vector(0, 0, 0),
			bones = {},
			boneinfo = {},
			boneorder = {},
			player = ply,
			boneCallback = 0,
			verticalCrouchOffset = 0,
			horizontalCrouchOffset = 0,
		}

		ply:SetLOD(0)
		local cm = ClientsideModel(pmname)
		cm:SetPos(LocalPlayer():GetPos())
		cm:SetAngles(Angle(0, 0, 0))
		cm:SetupBones()
		RecursiveBoneTable2(cm, cm:LookupBone("ValveBiped.Bip01_L_Clavicle"), characterInfo[steamid].boneinfo, characterInfo[steamid].boneorder)
		RecursiveBoneTable2(cm, cm:LookupBone("ValveBiped.Bip01_R_Clavicle"), characterInfo[steamid].boneinfo, characterInfo[steamid].boneorder)

		local boneNames = {
			b_leftClavicle = "ValveBiped.Bip01_L_Clavicle", b_leftUpperarm = "ValveBiped.Bip01_L_UpperArm",
			b_leftForearm = "ValveBiped.Bip01_L_Forearm", b_leftHand = "ValveBiped.Bip01_L_Hand",
			b_leftWrist = "ValveBiped.Bip01_L_Wrist", b_leftUlna = "ValveBiped.Bip01_L_Ulna",
			b_leftCalf = "ValveBiped.Bip01_L_Calf", b_leftThigh = "ValveBiped.Bip01_L_Thigh",
			b_leftFoot = "ValveBiped.Bip01_L_Foot", b_rightClavicle = "ValveBiped.Bip01_R_Clavicle",
			b_rightUpperarm = "ValveBiped.Bip01_R_UpperArm", b_rightForearm = "ValveBiped.Bip01_R_Forearm",
			b_rightHand = "ValveBiped.Bip01_R_Hand", b_rightWrist = "ValveBiped.Bip01_R_Wrist",
			b_rightUlna = "ValveBiped.Bip01_R_Ulna", b_rightCalf = "ValveBiped.Bip01_R_Calf",
			b_rightThigh = "ValveBiped.Bip01_R_Thigh", b_rightFoot = "ValveBiped.Bip01_R_Foot",
			b_head = "ValveBiped.Bip01_Head1", b_spine = "ValveBiped.Bip01_Spine",
		}

		characterInfo[steamid].bones = {
			fingers = {
				cm:LookupBone("ValveBiped.Bip01_L_Finger0") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger01") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger02") or -1,
				cm:LookupBone("ValveBiped.Bip01_L_Finger1") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger11") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger12") or -1,
				cm:LookupBone("ValveBiped.Bip01_L_Finger2") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger21") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger22") or -1,
				cm:LookupBone("ValveBiped.Bip01_L_Finger3") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger31") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger32") or -1,
				cm:LookupBone("ValveBiped.Bip01_L_Finger4") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger41") or -1, cm:LookupBone("ValveBiped.Bip01_L_Finger42") or -1,
				cm:LookupBone("ValveBiped.Bip01_R_Finger0") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger01") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger02") or -1,
				cm:LookupBone("ValveBiped.Bip01_R_Finger1") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger11") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger12") or -1,
				cm:LookupBone("ValveBiped.Bip01_R_Finger2") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger21") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger22") or -1,
				cm:LookupBone("ValveBiped.Bip01_R_Finger3") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger31") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger32") or -1,
				cm:LookupBone("ValveBiped.Bip01_R_Finger4") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger41") or -1, cm:LookupBone("ValveBiped.Bip01_R_Finger42") or -1,
			}
		}

		if ply == LocalPlayer() then g_VR.errorText = "" end
		for k, v in pairs(boneNames) do
			local bone = cm:LookupBone(v) or -1
			characterInfo[steamid].bones[k] = bone
			if bone == -1 and not string.find(k, "Wrist") and not string.find(k, "Ulna") then
				if ply == LocalPlayer() then g_VR.errorText = "Incompatible player model. Missing bone " .. v end
				cm:Remove()
				g_VR.StopCharacterSystem(steamid)
				vrmod.logger.Err("CharacterInit failed for " .. steamid)
				return false
			end
		end

		characterInfo[steamid].modelName = pmname
		local claviclePos = cm:GetBonePosition(characterInfo[steamid].bones.b_leftClavicle)
		local upperPos = cm:GetBonePosition(characterInfo[steamid].bones.b_leftUpperarm)
		local lowerPos = cm:GetBonePosition(characterInfo[steamid].bones.b_leftForearm)
		local handPos = cm:GetBonePosition(characterInfo[steamid].bones.b_leftHand)
		local thighPos = cm:GetBonePosition(characterInfo[steamid].bones.b_leftThigh)
		local calfPos = cm:GetBonePosition(characterInfo[steamid].bones.b_leftCalf)
		local footPos = cm:GetBonePosition(characterInfo[steamid].bones.b_leftFoot)
		local spinePos = cm:GetBonePosition(characterInfo[steamid].bones.b_spine)
		characterInfo[steamid].clavicleLen = claviclePos:Distance(upperPos)
		characterInfo[steamid].upperArmLen = upperPos:Distance(lowerPos)
		characterInfo[steamid].lowerArmLen = lowerPos:Distance(handPos)
		characterInfo[steamid].upperLegLen = thighPos:Distance(calfPos)
		characterInfo[steamid].lowerLegLen = calfPos:Distance(footPos)
		characterInfo[steamid].spineZ = spinePos.z - cm:GetPos().z
		cm:Remove()
	end

	------------------------------------------------------------------------
	local function BoneCallbackFunc(ply, numbones)
		local steamid = ply:SteamID()
		if not activePlayers[steamid] or not g_VR.net[steamid].lerpedFrame or (ply:InVehicle() and ply:GetVehicle():GetClass() ~= "prop_vehicle_prisoner_pod") then return end
		if ply:GetBoneMatrix(characterInfo[steamid].bones.b_rightHand) then
			ply:SetBonePosition(characterInfo[steamid].bones.b_rightHand, g_VR.net[steamid].lerpedFrame.righthandPos, g_VR.net[steamid].lerpedFrame.righthandAng + RIGHT_HAND_OFFSET)
		end
		if not g_VR.net[steamid].characterAltHead then
			local _, targetAng = LocalToWorld(zeroVec, Angle(-80, 0, 90), zeroVec, g_VR.net[steamid].lerpedFrame.hmdAng)
			local mtx = ply:GetBoneMatrix(characterInfo[steamid].bones.b_head)
			if mtx then
				mtx:SetAngles(targetAng)
				ply:SetBoneMatrix(characterInfo[steamid].bones.b_head, mtx)
			end
		end
	end

	------------------------------------------------------------------------
	local up = Vector(0, 0, 1)
	local function PreRenderFunc()
		if convars.vrmod_oldcharacteryaw:GetBool() then
			local _, relativeAng = WorldToLocal(zeroVec, Angle(0, g_VR.tracking.hmd.ang.yaw, 0), zeroVec, Angle(0, g_VR.characterYaw, 0))
			if relativeAng.yaw > 45 then g_VR.characterYaw = g_VR.characterYaw + relativeAng.yaw - 45
			elseif relativeAng.yaw < -45 then g_VR.characterYaw = g_VR.characterYaw + relativeAng.yaw + 45 end
			if g_VR.input.boolean_walk or g_VR.input.boolean_turnleft or g_VR.input.boolean_turnright then g_VR.characterYaw = g_VR.tracking.hmd.ang.yaw end
			return
		end
		local leftPos, rightPos, hmdPos, hmdAng = g_VR.tracking.pose_lefthand.pos, g_VR.tracking.pose_righthand.pos, g_VR.tracking.hmd.pos, g_VR.tracking.hmd.ang
		local NA, Clamp, RealFT = math.NormalizeAngle, math.Clamp, RealFrameTime()
		local lpos_local = WorldToLocal(leftPos, zeroAng, hmdPos, hmdAng)
		local rpos_local = WorldToLocal(rightPos, zeroAng, hmdPos, hmdAng)
		if lpos_local.y > rpos_local.y then
			local handYaw = NA(math.deg(math.atan2(rightPos.y - leftPos.y, rightPos.x - leftPos.x)) + 90)
			local fwd = hmdAng:Forward() fwd.z = 0
			if fwd:LengthSqr() < 1e-6 then fwd = Angle(0, hmdAng.yaw, 0):Forward() end
			local forwardYaw = fwd:Angle().yaw
			local targetYaw = forwardYaw + Clamp(NA(handYaw - forwardYaw), -45, 45)
			g_VR.characterYaw = NA(g_VR.characterYaw + NA(targetYaw - g_VR.characterYaw) * 8 * RealFT)
		end
		if g_VR.input.boolean_walk or g_VR.input.boolean_turnleft or g_VR.input.boolean_turnright then g_VR.characterYaw = g_VR.tracking.hmd.ang.yaw end
	end

	------------------------------------------------------------------------
	local function PrePlayerDrawFunc(ply)
		if not IsValid(ply) then return end
		local steamid = ply:SteamID()
		if not activePlayers[steamid] or not g_VR.net[steamid] or not g_VR.net[steamid].lerpedFrame then return end
		if not characterInfo or not characterInfo[steamid] or not characterInfo[steamid].bones then return end
		local headToHmdDist = convarValues.characterHeadToHmdDist or 6.3
		if ply == LocalPlayer() then
			local ep = EyePos()
			local hide = (ep == g_VR.eyePosLeft or ep == g_VR.eyePosRight) and ply:GetViewEntity() == ply
			ply:ManipulateBoneScale(characterInfo[steamid].bones.b_head, hide and zeroVec or Vector(1, 1, 1))
		end
		characterInfo[steamid].preRenderPos = ply:GetPos()
		if not ply:InVehicle() then
			characterInfo[steamid].renderPos = g_VR.net[steamid].lerpedFrame.hmdPos + up:Cross(g_VR.net[steamid].lerpedFrame.hmdAng:Right()) * -headToHmdDist + Angle(0, g_VR.net[steamid].lerpedFrame.characterYaw, 0):Forward() * -characterInfo[steamid].horizontalCrouchOffset * 0.8
			characterInfo[steamid].renderPos.z = ply:GetPos().z - characterInfo[steamid].verticalCrouchOffset
			ply:SetPos(characterInfo[steamid].renderPos)
			ply:SetRenderAngles(Angle(0, g_VR.net[steamid].lerpedFrame.characterYaw, 0))
		end
		ply:SetupBones()
		if prevFrameNumber ~= FrameNumber() then prevFrameNumber = FrameNumber() updatedPlayers = {} end
		if not updatedPlayers[steamid] then UpdateIK(ply) updatedPlayers[steamid] = 1 end
		if ply:InVehicle() and ply:GetVehicle():GetClass() ~= "prop_vehicle_prisoner_pod" then return end
		if characterInfo[steamid].boneorder and characterInfo[steamid].boneinfo then
			for i = 1, #characterInfo[steamid].boneorder do
				local bone = characterInfo[steamid].boneorder[i]
				if ply:GetBoneMatrix(bone) and characterInfo[steamid].boneinfo[bone] and characterInfo[steamid].boneinfo[bone].targetMatrix then
					ply:SetBoneMatrix(bone, characterInfo[steamid].boneinfo[bone].targetMatrix)
				end
			end
		end
	end

	local function PostPlayerDrawFunc(ply)
		if not IsValid(ply) then return end
		local steamid = ply:SteamID()
		if not activePlayers[steamid] or not g_VR.net or not g_VR.net[steamid] or not g_VR.net[steamid].lerpedFrame then return end
		if not characterInfo or not characterInfo[steamid] then return end
		if ply:InVehicle() then return end
		ply:SetPos(characterInfo[steamid].preRenderPos)
	end

	------------------------------------------------------------------------
	local function CalcMainActivityFunc(ply, vel)
		if not activePlayers[ply:SteamID()] or ply:InVehicle() then return end
		-- When animations are disabled, force idle standing pose
		if not convarValues.characterIK then
			ply:SetPlaybackRate(0)
			ply:SetPoseParameter("move_yaw", 0)
			ply:SetPoseParameter("move_x", 0)
			ply:SetPoseParameter("move_y", 0)
			return ACT_HL2MP_IDLE, -1
		end
		local act = ACT_HL2MP_IDLE
		if ply.m_bJumping then
			act = ACT_HL2MP_JUMP_PASSIVE
			if CurTime() - ply.m_flJumpStartTime > 0.2 and ply:OnGround() then ply.m_bJumping = false end
		else
			local l = vel:Length2DSqr()
			if l > 22500 then act = ACT_HL2MP_RUN elseif l > 0.25 then act = ACT_HL2MP_WALK end
		end
		return act, -1
	end

	local function DoAnimationEventFunc(ply, evt, data)
		if not activePlayers[ply:SteamID()] or ply:InVehicle() then return end
		-- Block all animation events when animations are disabled
		if not convarValues.characterIK then return ACT_INVALID end
		if evt ~= PLAYERANIMEVENT_JUMP then return ACT_INVALID end
	end

	------------------------------------------------------------------------
	function g_VR.StartCharacterSystem(ply)
		if not IsValid(ply) then return end
		local steamid = ply:SteamID()
		if CharacterInit(ply) == false then return end
		if not g_VR.net or not g_VR.net[steamid] then return end
		if characterInfo and characterInfo[steamid] then
			if characterInfo[steamid].boneCallback then ply:RemoveCallback("BuildBonePositions", characterInfo[steamid].boneCallback) end
			characterInfo[steamid].boneCallback = ply:AddCallback("BuildBonePositions", BoneCallbackFunc)
			if ply == LocalPlayer() then
				hook.Remove("VRMod_PreRender", "vrutil_hook_calcplyrenderpos")
				hook.Add("VRMod_PreRender", "vrutil_hook_calcplyrenderpos", PreRenderFunc)
			end
			hook.Remove("PrePlayerDraw", "vrutil_hook_preplayerdraw")
			hook.Add("PrePlayerDraw", "vrutil_hook_preplayerdraw", PrePlayerDrawFunc)
			hook.Remove("PostPlayerDraw", "vrutil_hook_postplayerdraw")
			hook.Add("PostPlayerDraw", "vrutil_hook_postplayerdraw", PostPlayerDrawFunc)
			hook.Remove("CalcMainActivity", "vrutil_hook_calcmainactivity")
			hook.Add("CalcMainActivity", "vrutil_hook_calcmainactivity", CalcMainActivityFunc)
			hook.Remove("DoAnimationEvent", "vrutil_hook_doanimationevent")
			hook.Add("DoAnimationEvent", "vrutil_hook_doanimationevent", DoAnimationEventFunc)
			activePlayers[steamid] = true
		end
	end

	function g_VR.StopCharacterSystem(steamid)
		if not activePlayers[steamid] then return end
		local ply = player.GetBySteamID(steamid)
		if characterInfo[steamid] and IsValid(ply) then
			for k, v in pairs(characterInfo[steamid].bones) do
				if not isnumber(v) then continue end
				ply:ManipulateBoneAngles(v, Angle(0, 0, 0))
			end
			ply:RemoveCallback("BuildBonePositions", characterInfo[steamid].boneCallback)
			if ply == LocalPlayer() then
				hook.Remove("VRMod_PreRender", "vrutil_hook_calcplyrenderpos")
				ply:ManipulateBoneScale(characterInfo[steamid].bones.b_head, Vector(1, 1, 1))
			end
		end
		activePlayers[steamid] = nil
		characterInfo[steamid] = nil
		if table.Count(activePlayers) == 0 then
			hook.Remove("PrePlayerDraw", "vrutil_hook_preplayerdraw")
			hook.Remove("PostPlayerDraw", "vrutil_hook_postplayerdraw")
			hook.Remove("UpdateAnimation", "vrutil_hook_updateanimation")
			hook.Remove("CalcMainActivity", "vrutil_hook_calcmainactivity")
			hook.Remove("DoAnimationEvent", "vrutil_hook_doanimationevent")
		end
		vrmod.logger.Info("Stopped character system for " .. steamid)
	end

	hook.Add("VRMod_Start", "vrmod_characterstart", function(ply) g_VR.StartCharacterSystem(ply) end)
	hook.Add("VRMod_Exit", "vrmod_characterstop", function(ply, steamid) g_VR.StopCharacterSystem(steamid) end)
end