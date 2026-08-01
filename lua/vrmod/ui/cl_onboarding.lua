-- =============================================================================
-- Cube Experience — Ideal Virtual Reality onboarding
-- Flow: Welcome → Vision (border cal) → Posture (stand/sit + autoheight) → Complete
-- Law: energy flows; never thrash the player; HUD stays alive; mat_queue untouched.
-- =============================================================================
if SERVER then return end

vrmod = vrmod or {}
g_VR = g_VR or {}

local EXP_FILE = "vrmod/experience_complete.txt"
local EXP_DIR = "vrmod"
local EXP_VERSION = 1

local Ex = {
	active = false,
	phase = "idle", -- welcome | vision | posture | complete
	choice = 1, -- posture: 1 standing, 2 seated
	msg = "",
	msgUntil = 0,
	waitingVision = false,
}

local convars, convarValues

local function ensureConvars()
	if convars then return end
	convars, convarValues = vrmod.GetConvars()
end

local function toast(s, t)
	Ex.msg = s
	Ex.msgUntil = CurTime() + (t or 2.5)
	notification.AddLegacy("[VRMod] " .. s, NOTIFY_GENERIC, t or 2.5)
end

local function isComplete()
	if file.Exists(EXP_FILE, "DATA") then
		local raw = file.Read(EXP_FILE, "DATA") or ""
		if string.find(raw, "complete=1") then return true end
	end
	local c = GetConVar("vrmod_experience_done")
	return c and c:GetBool() or false
end

function vrmod.Experience_IsComplete()
	return isComplete()
end

function vrmod.Experience_ShouldRun()
	local force = GetConVar("vrmod_experience_force")
	if force and force:GetBool() then return true end
	local en = GetConVar("vrmod_experience")
	if en and not en:GetBool() then return false end
	return not isComplete()
end

function vrmod.Experience_MarkComplete()
	file.CreateDir(EXP_DIR)
	file.Write(EXP_FILE, table.concat({
		"v" .. EXP_VERSION,
		"complete=1",
		"ts=" .. tostring(os.time()),
	}, "\n"))
	RunConsoleCommand("vrmod_experience_done", "1")
	RunConsoleCommand("vrmod_experience_force", "0")
end

function vrmod.Experience_Reset()
	if file.Exists(EXP_FILE, "DATA") then
		file.Delete(EXP_FILE)
	end
	RunConsoleCommand("vrmod_experience_done", "0")
	RunConsoleCommand("vrmod_experience_force", "1")
	RunConsoleCommand("vrmod_experience", "1")
	-- If already in VR: restart the full guide now (vision → posture)
	if g_VR and g_VR.active and g_VR.threePoints then
		toast("Restarting Cube Experience guide…", 2)
		timer.Simple(0.15, function()
			if g_VR and g_VR.active then
				vrmod.Experience_Start()
			end
		end)
	else
		toast("Cube Experience reset — start VR to run the guide", 3)
	end
end

local function stopPanelHooks()
	hook.Remove("VRMod_Input", "vrmod_experience")
	hook.Remove("PostDrawTranslucentRenderables", "vrmod_experience_3d")
	hook.Remove("HUDPaint", "vrmod_experience_hud")
	hook.Remove("Think", "vrmod_experience_keys")
end

function vrmod.Experience_Stop()
	if not Ex.active then return end
	Ex.active = false
	Ex.phase = "idle"
	Ex.waitingVision = false
	stopPanelHooks()
	hook.Remove("VRMod_BorderCalEnded", "vrmod_experience_vision")
	if vrmod.BorderCal_IsActive and vrmod.BorderCal_IsActive() then
		vrmod.BorderCal_Stop(false)
	end
end

local function drawExperiencePanel(title, lines, footer)
	local hmd = g_VR.tracking and g_VR.tracking.hmd
	if not hmd or not hmd.pos then return end
	local ang = Angle(hmd.ang.p, hmd.ang.y, hmd.ang.r)
	local pos = hmd.pos + ang:Forward() * 42 - ang:Up() * 4
	local a = Angle(ang.p, ang.y, ang.r)
	a:RotateAroundAxis(a:Right(), 90)
	a:RotateAroundAxis(a:Up(), -90)
	cam.Start3D2D(pos, a, 0.045)
		-- Glass panel — Cube aesthetic
		surface.SetDrawColor(12, 16, 28, 220)
		surface.DrawRect(-220, -90, 440, 200)
		surface.SetDrawColor(80, 140, 255, 255)
		surface.DrawOutlinedRect(-220, -90, 440, 200)
		surface.SetDrawColor(40, 80, 180, 120)
		surface.DrawRect(-220, -90, 440, 28)
		draw.SimpleText(title, "DermaLarge", 0, -84, Color(200, 220, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		local y = -48
		for _, line in ipairs(lines or {}) do
			draw.SimpleText(line, "DermaDefault", 0, y, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			y = y + 16
		end
		if footer and footer ~= "" then
			draw.SimpleText(footer, "DermaDefault", 0, 78, Color(160, 200, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		end
		if Ex.msgUntil > CurTime() then
			draw.SimpleText(Ex.msg, "DermaDefaultBold", 0, 58, Color(140, 255, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		end
	cam.End3D2D()
end

local function phaseWelcome()
	Ex.phase = "welcome"
	toast("Cube Experience · Ideal VR", 3)
end

local function phaseVision()
	Ex.phase = "vision"
	Ex.waitingVision = true
	toast("Phase I · Vision — clear the edges of the Real", 4)
	hook.Add("VRMod_BorderCalEnded", "vrmod_experience_vision", function(completed)
		hook.Remove("VRMod_BorderCalEnded", "vrmod_experience_vision")
		Ex.waitingVision = false
		if not Ex.active then return end
		if completed then
			toast("Vision sealed", 2)
		else
			toast("Vision skipped — continuing", 2)
		end
		timer.Simple(0.6, function()
			if Ex.active then phasePosture() end
		end)
	end)
	timer.Simple(0.8, function()
		if not Ex.active or not g_VR.active then return end
		if vrmod.BorderCal_Start then
			vrmod.BorderCal_Start()
		else
			-- Fallback if border cal missing
			hook.Run("VRMod_BorderCalEnded", false)
		end
	end)
end

function phasePosture()
	Ex.phase = "posture"
	Ex.choice = 1
	toast("Phase II · Posture — stand or sit in the Real", 3)
end

local function applyStanding()
	ensureConvars()
	convars.vrmod_seated:SetBool(false)
	convars.vrmod_seatedoffset:SetFloat(0)
	if vrmod.AutoScaleHeight then
		local ok, scale = vrmod.AutoScaleHeight()
		if ok then
			toast(string.format("Standing · auto height scale %.1f", scale), 3)
		else
			toast("Standing · scale unchanged (no HMD)", 2)
		end
	end
end

local function applySeated()
	ensureConvars()
	if vrmod.AutoSeatedOffset then
		local ok, offset = vrmod.AutoSeatedOffset()
		if ok then
			toast(string.format("Seated · auto offset %.1f", offset), 3)
		else
			convars.vrmod_seated:SetBool(true)
			toast("Seated · enable only (offset pending)", 2)
		end
	else
		convars.vrmod_seated:SetBool(true)
	end
end

local function phaseComplete()
	Ex.phase = "complete"
	vrmod.Experience_MarkComplete()
	-- Keep height menu available for fine-tune later, not forced
	RunConsoleCommand("vrmod_heightmenu", "0")
	toast("Experience complete · the Real and GMod are one", 4)
	timer.Simple(3.5, function()
		vrmod.Experience_Stop()
	end)
end

local function confirmPosture()
	if Ex.choice == 1 then
		applyStanding()
	else
		applySeated()
	end
	timer.Simple(0.5, function()
		if Ex.active then phaseComplete() end
	end)
end

local function onInput(action, pressed)
	if not pressed or not Ex.active then return end
	-- While vision cal owns input, stay silent
	if Ex.phase == "vision" or Ex.waitingVision then return end

	if Ex.phase == "welcome" then
		if action == "boolean_primaryfire" or action == "boolean_use" or action == "boolean_changeweapon" then
			phaseVision()
		elseif action == "boolean_secondaryfire" or action == "boolean_left_pickup" or action == "boolean_right_pickup" then
			-- Skip entire experience
			vrmod.Experience_MarkComplete()
			toast("Experience skipped", 2)
			vrmod.Experience_Stop()
		end
		return
	end

	if Ex.phase == "posture" then
		if action == "boolean_primaryfire" or action == "boolean_car_mouse_left" then
			Ex.choice = 1 -- standing
			toast("Standing selected · trigger Use to confirm", 2)
		elseif action == "boolean_secondaryfire" or action == "boolean_car_mouse_right" then
			Ex.choice = 2 -- seated
			toast("Seated selected · trigger Use to confirm", 2)
		elseif action == "boolean_use" or action == "boolean_changeweapon" or action == "boolean_flashlight" then
			confirmPosture()
		elseif action == "boolean_left_pickup" or action == "boolean_right_pickup" then
			-- default standing autoheight and finish
			Ex.choice = 1
			confirmPosture()
		end
		return
	end
end

local function panelLines()
	if Ex.phase == "welcome" then
		return {
			"You are entering Ideal VR.",
			"We will align vision, then posture.",
			"",
			"Look straight. Hands free.",
			"Trigger / Use  →  begin",
			"Grip / Secondary  →  skip forever",
		}, "Cube Experience · first arrival"
	end
	if Ex.phase == "vision" then
		return {
			"Vision calibration is active.",
			"Follow the border guide in front of you.",
			"Clear black edges · scale · V · H · save.",
		}, "Phase I · Vision"
	end
	if Ex.phase == "posture" then
		local markStand = Ex.choice == 1 and "►" or " "
		local markSit = Ex.choice == 2 and "►" or " "
		return {
			"How do you inhabit the Real?",
			"",
			markStand .. "  STANDING  — Auto Height (scale to IRL)",
			markSit .. "  SEATED    — Auto Offset (chair → character eyes)",
			"",
			"Trigger = Standing   Secondary = Seated",
			"Use = confirm choice",
		}, "Phase II · Posture"
	end
	if Ex.phase == "complete" then
		return {
			"Calibration sealed.",
			"World scale and eyes are one.",
			"Play.",
		}, "Complete"
	end
	return { "" }, ""
end

function vrmod.Experience_Start()
	if not g_VR or not g_VR.active then
		toast("Start VR first", 2)
		return
	end
	ensureConvars()
	vrmod.Experience_Stop()
	Ex.active = true
	Ex.choice = 1
	Ex.waitingVision = false

	hook.Add("VRMod_Input", "vrmod_experience", onInput)

	hook.Add("PostDrawTranslucentRenderables", "vrmod_experience_3d", function(depth, sky)
		if depth or sky or not Ex.active or not g_VR.active then return end
		if Ex.phase == "vision" then return end -- border cal owns the 3D guide
		local lines, title = panelLines()
		drawExperiencePanel(title, lines, "Ideal Virtual Reality · Cube")
	end)

	hook.Add("HUDPaint", "vrmod_experience_hud", function()
		if not Ex.active or Ex.phase == "vision" then return end
		local lines, title = panelLines()
		local y = ScrH() * 0.1
		draw.SimpleTextOutlined(title, "DermaLarge", ScrW() * 0.5, y, Color(120, 180, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
		y = y + 32
		for _, line in ipairs(lines) do
			draw.SimpleTextOutlined(line, "DermaDefault", ScrW() * 0.5, y, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
			y = y + 16
		end
	end)

	phaseWelcome()
end

-- Convars (must exist before ShouldRun checks on start)
vrmod.AddCallbackedConvar("vrmod_experience", nil, "1", FCVAR_ARCHIVE, "Run Cube Experience on first VR session", nil, nil, tobool)
vrmod.AddCallbackedConvar("vrmod_experience_done", nil, "0", FCVAR_ARCHIVE, "Cube Experience completed", nil, nil, tobool)
vrmod.AddCallbackedConvar("vrmod_experience_force", nil, "0", FCVAR_ARCHIVE, "Force Cube Experience next VR start", nil, nil, tobool)

concommand.Add("vrmod_experience_start", function()
	vrmod.Experience_Start()
end)

concommand.Add("vrmod_experience_reset", function()
	vrmod.Experience_Reset()
end)

hook.Add("VRMod_Start", "vrmod_cube_experience", function(ply)
	if ply ~= LocalPlayer() then return end
	timer.Create("vrmod_cube_experience_wait", 0.5, 0, function()
		if not g_VR or not g_VR.active then return end
		if not g_VR.threePoints then return end
		timer.Remove("vrmod_cube_experience_wait")
		if not vrmod.Experience_ShouldRun() then return end
		-- Small beat so tracking settles before AutoScale measures
		timer.Simple(1.2, function()
			if g_VR and g_VR.active and vrmod.Experience_ShouldRun() then
				vrmod.Experience_Start()
			end
		end)
	end)
end)

hook.Add("VRMod_Exit", "vrmod_cube_experience", function(ply)
	if ply ~= LocalPlayer() then return end
	vrmod.Experience_Stop()
	timer.Remove("vrmod_cube_experience_wait")
end)
