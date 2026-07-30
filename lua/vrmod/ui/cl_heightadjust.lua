if SERVER then return end

-- Height / seated calibration UI + live 3D avatar (same PM as player, tracks VR poses).
-- Replaces the old RT mirror (doubled / blocky). Cube: avatar is truth of your body in the Real.

local convars, convarValues = vrmod.GetConvars()
local avatar -- ClientsideModel
local avatarActive = false

local function AutoScale()
	if not g_VR.tracking or not g_VR.tracking.hmd then return end
	local eyeH = g_VR.tracking.hmd.pos.z - g_VR.origin.z
	if eyeH < 8 then eyeH = 66.8 end
	g_VR.scale = 66.8 / (eyeH / math.max(g_VR.scale, 0.01))
	convars.vrmod_scale:SetFloat(g_VR.scale)
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
	convars.vrmod_seatedoffset:SetFloat(offset)
	convars.vrmod_seated:SetBool(true)
	return true, offset
end

local function DestroyAvatar()
	avatarActive = false
	hook.Remove("PostDrawTranslucentRenderables", "vrmod_height_avatar")
	hook.Remove("Think", "vrmod_height_avatar_mdl")
	if IsValid(avatar) then
		avatar:Remove()
	end
	avatar = nil
end

local function CopyPlayerLooks(dst, src)
	if not IsValid(dst) or not IsValid(src) then return end
	dst:SetSkin(src:GetSkin() or 0)
	local n = src:GetNumBodyGroups() or 0
	for i = 0, n - 1 do
		dst:SetBodygroup(i, src:GetBodygroup(i))
	end
	if dst.SetPlayerColor and src.GetPlayerColor then
		pcall(function() dst:SetPlayerColor(src:GetPlayerColor()) end)
	end
end

local function SetBoneWorld(ent, bone, pos, ang)
	if not bone or bone < 0 or not pos or not ang then return end
	local m = Matrix()
	m:SetTranslation(pos)
	m:SetAngles(ang)
	ent:SetBoneMatrix(bone, m)
end

local function SpawnAvatar()
	DestroyAvatar()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local mdl = ply.vrmod_pm or ply:GetModel()
	if not mdl or mdl == "" then mdl = "models/player/kleiner.mdl" end

	avatar = ClientsideModel(mdl, RENDERGROUP_BOTH)
	if not IsValid(avatar) then
		avatar = nil
		return
	end
	avatar:SetNoDraw(true)
	avatar:DrawShadow(true)
	avatar:SetIK(false)
	CopyPlayerLooks(avatar, ply)
	avatar:ResetSequence(ply:LookupSequence("idle_all_01") >= 0 and ply:LookupSequence("idle_all_01") or 0)
	avatar:SetCycle(0)
	avatar:SetPlaybackRate(0)
	avatar:SetupBones()
	avatarActive = true

	-- Hot-swap if playermodel changes mid-menu
	hook.Add("Think", "vrmod_height_avatar_mdl", function()
		if not avatarActive or not IsValid(avatar) then return end
		local p = LocalPlayer()
		if not IsValid(p) then return end
		local want = p.vrmod_pm or p:GetModel()
		if want and want ~= "" and avatar:GetModel() ~= want then
			avatar:SetModel(want)
			CopyPlayerLooks(avatar, p)
			avatar:SetupBones()
		end
	end)

	-- Map a world pose from the player's body frame into the avatar's body frame.
	-- Avatar faces the player (mirror layout): left/right are flipped so raise-left looks correct.
	local function MapPoseToAvatar(worldPos, worldAng, playerFeet, playerYaw, avatarFeet, avatarYaw)
		local relPos, relAng = WorldToLocal(worldPos, worldAng, playerFeet, playerYaw)
		-- Mirror across sagittal plane (Source local: y = right)
		relPos.y = -relPos.y
		relAng.y = -relAng.y
		relAng.r = -relAng.r
		return LocalToWorld(relPos, relAng, avatarFeet, avatarYaw)
	end

	hook.Add("PostDrawTranslucentRenderables", "vrmod_height_avatar", function(depth, sky)
		if depth or sky or not avatarActive then return end
		if not g_VR.active or not g_VR.menus or not g_VR.menus.heightmenu then return end
		if not IsValid(avatar) or not g_VR.tracking or not g_VR.tracking.hmd then return end
		if EyePos() ~= g_VR.eyePosLeft and EyePos() ~= g_VR.eyePosRight then return end

		local hmd = g_VR.tracking.hmd
		local left = g_VR.tracking.pose_lefthand
		local right = g_VR.tracking.pose_righthand
		local yaw = hmd.ang.yaw
		local playerYaw = Angle(0, yaw, 0)
		local playerFeet = Vector(hmd.pos.x, hmd.pos.y, g_VR.origin.z)

		-- Avatar stands in front of you, facing you (height reference twin)
		local standPos = playerFeet + playerYaw:Forward() * 48
		local standAng = Angle(0, yaw + 180, 0)

		g_VR.menus.heightmenu.pos = standPos + Vector(0, 0, 52) + standAng:Right() * -18
		g_VR.menus.heightmenu.ang = Angle(0, standAng.y + 90, 90)

		avatar:SetPos(standPos)
		avatar:SetAngles(standAng)
		avatar:InvalidateBoneCache()
		avatar:SetupBones()

		local headBone = avatar:LookupBone("ValveBiped.Bip01_Head1")
		local lHand = avatar:LookupBone("ValveBiped.Bip01_L_Hand")
		local rHand = avatar:LookupBone("ValveBiped.Bip01_R_Hand")
		local lFore = avatar:LookupBone("ValveBiped.Bip01_L_Forearm")
		local rFore = avatar:LookupBone("ValveBiped.Bip01_R_Forearm")
		local lUpper = avatar:LookupBone("ValveBiped.Bip01_L_UpperArm")
		local rUpper = avatar:LookupBone("ValveBiped.Bip01_R_UpperArm")

		-- Head follows HMD (mirrored into avatar space)
		if headBone and headBone >= 0 then
			local hp, ha = MapPoseToAvatar(hmd.pos + hmd.ang:Forward() * -2, hmd.ang, playerFeet, playerYaw, standPos, standAng)
			SetBoneWorld(avatar, headBone, hp, ha)
		end

		-- Hands: swap L/R because we mirrored (player left → avatar right side of mesh facing you)
		if left and left.pos and rHand and rHand >= 0 then
			local p, a = MapPoseToAvatar(left.pos, left.ang, playerFeet, playerYaw, standPos, standAng)
			SetBoneWorld(avatar, rHand, p, a)
		end
		if right and right.pos and lHand and lHand >= 0 then
			local p, a = MapPoseToAvatar(right.pos, right.ang, playerFeet, playerYaw, standPos, standAng)
			SetBoneWorld(avatar, lHand, p, a)
		end

		-- Aim upper arms / forearms toward hands for a coherent silhouette
		local function AimChain(upperId, foreId, handPos)
			if not handPos then return end
			if upperId and upperId >= 0 then
				local m = avatar:GetBoneMatrix(upperId)
				if m then
					local o = m:GetTranslation()
					local dir = (handPos - o)
					if dir:LengthSqr() > 1 then
						local ang = dir:GetNormalized():Angle()
						ang:RotateAroundAxis(ang:Right(), 90)
						SetBoneWorld(avatar, upperId, o, ang)
					end
				end
			end
			if foreId and foreId >= 0 then
				local m = avatar:GetBoneMatrix(foreId)
				if m then
					local o = m:GetTranslation()
					local dir = (handPos - o)
					if dir:LengthSqr() > 1 then
						local ang = dir:GetNormalized():Angle()
						ang:RotateAroundAxis(ang:Right(), 90)
						SetBoneWorld(avatar, foreId, o, ang)
					end
				end
			end
		end

		if left and left.pos then
			local p = MapPoseToAvatar(left.pos, left.ang or Angle(), playerFeet, playerYaw, standPos, standAng)
			AimChain(rUpper, rFore, p) -- mirrored → right arm chain
		end
		if right and right.pos then
			local p = MapPoseToAvatar(right.pos, right.ang or Angle(), playerFeet, playerYaw, standPos, standAng)
			AimChain(lUpper, lFore, p)
		end

		avatar:DrawModel()
	end)
end

function VRUtilOpenHeightMenu()
	if not g_VR.threePoints or VRUtilIsMenuOpen("heightmenu") then return end
	SpawnAvatar()
	VRUtilMenuOpen("heightmenu", 300, 512, nil, nil, Vector(), Angle(), 0.1, true, function()
		DestroyAvatar()
		hook.Remove("VRMod_Input", "vrmodheightmenuinput")
	end)

	local buttons, renderControls
	buttons = {
		{
			x = 250, y = 0, w = 50, h = 50,
			text = "X", font = "Trebuchet24", text_x = 25, text_y = 15, enabled = true,
			fn = function()
				VRUtilMenuClose("heightmenu")
				convars.vrmod_heightmenu:SetBool(false)
			end
		},
		{
			x = 250, y = 200, w = 50, h = 50,
			text = "+", font = "Trebuchet24", text_x = 25, text_y = 15,
			enabled = not convarValues.vrmod_seated,
			fn = function()
				g_VR.scale = g_VR.scale + 0.5
				convars.vrmod_scale:SetFloat(g_VR.scale)
			end
		},
		{
			x = 250, y = 255, w = 50, h = 50,
			text = "Auto\nScale", font = "Trebuchet24", text_x = 25, text_y = 0,
			enabled = not convarValues.vrmod_seated,
			fn = function() AutoScale() end
		},
		{
			x = 250, y = 310, w = 50, h = 50,
			text = "-", font = "Trebuchet24", text_x = 25, text_y = 15,
			enabled = not convarValues.vrmod_seated,
			fn = function()
				g_VR.scale = g_VR.scale - 0.5
				convars.vrmod_scale:SetFloat(g_VR.scale)
			end
		},
		{
			x = 0, y = 200, w = 50, h = 50,
			text = convarValues.vrmod_seated and "Disable\nSeated\nOffset" or "Enable\nSeated\nOffset",
			font = "Trebuchet18", text_x = 25, text_y = -2, enabled = true,
			fn = function()
				local newState = not convarValues.vrmod_seated
				convars.vrmod_seated:SetBool(newState)
				buttons[5].text = newState and "Disable\nSeated\nOffset" or "Enable\nSeated\nOffset"
				buttons[2].enabled = not newState
				buttons[3].enabled = not newState
				buttons[4].enabled = not newState
				buttons[6].enabled = newState
				renderControls()
			end
		},
		{
			x = 0, y = 255, w = 50, h = 50,
			text = "Auto\nOffset", font = "Trebuchet18", text_x = 25, text_y = 5,
			enabled = convarValues.vrmod_seated,
			fn = function()
				vrmod.AutoSeatedOffset()
			end
		}
	}

	renderControls = function()
		VRUtilMenuRenderStart("heightmenu")
		surface.SetDrawColor(30, 34, 48, 255)
		surface.DrawRect(0, 0, 300, 512)
		surface.SetDrawColor(80, 90, 120, 255)
		surface.DrawOutlinedRect(0, 0, 300, 512)
		draw.DrawText("Your avatar mirrors your body.\nStand IRL · Auto Scale for height.\nSeated: enable then Auto Offset.", "Trebuchet18", 3, 4, color_white, TEXT_ALIGN_LEFT)
		for _, btn in ipairs(buttons) do
			surface.SetDrawColor(btn.enabled and 70 or 40, btn.enabled and 80 or 45, btn.enabled and 110 or 55, 255)
			surface.DrawRect(btn.x, btn.y, btn.w, btn.h)
			draw.DrawText(btn.text, btn.font, btn.x + btn.text_x, btn.y + btn.text_y, color_white, TEXT_ALIGN_CENTER)
		end
		VRUtilMenuRenderEnd()
	end

	renderControls()
	hook.Add("VRMod_Input", "vrmodheightmenuinput", function(action, pressed)
		if g_VR.menuFocus == "heightmenu" and action == "boolean_primaryfire" and pressed then
			for _, btn in ipairs(buttons) do
				if btn.enabled and g_VR.menuCursorX > btn.x and g_VR.menuCursorX < btn.x + btn.w and g_VR.menuCursorY > btn.y and g_VR.menuCursorY < btn.y + btn.h then
					btn.fn()
				end
			end
		end
	end)
end

hook.Add("VRMod_Start", "vrmod_OpenHeightMenuOnStartup", function(ply)
	if ply ~= LocalPlayer() then return end
	if vrmod.Experience_ShouldRun and vrmod.Experience_ShouldRun() then return end
	if not convars.vrmod_heightmenu:GetBool() then return end
	timer.Create("vrmod_HeightMenuStartupWait", 1, 0, function()
		if g_VR.threePoints then
			timer.Remove("vrmod_HeightMenuStartupWait")
			VRUtilOpenHeightMenu()
		end
	end)
end)

hook.Add("VRMod_Exit", "vrmod_height_avatar_cleanup", function(ply)
	if ply ~= LocalPlayer() then return end
	DestroyAvatar()
end)
