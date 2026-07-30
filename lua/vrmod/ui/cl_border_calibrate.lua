-- Tier C: user-in-loop border calibration (scale → V → H → save profile)
if SERVER then return end

vrmod = vrmod or {}
local Cal = {
	active = false,
	step = 1,
	steps = {
		{
			id = "reset",
			title = "BORDER CAL",
			hint = "Look straight ahead. Trigger = start. Grip = cancel.",
		},
		{
			id = "scale",
			cvar = "vrmod_scalefactor",
			title = "STEP 1 · SCALE",
			hint = "Black borders? Trigger = tighter (-). Secondary = looser (+). Menu = next.",
			step = 0.02,
			min = 0.05,
			max = 4.0,
		},
		{
			id = "vertical",
			cvar = "vrmod_verticaloffset",
			title = "STEP 2 · VERTICAL",
			hint = "Top/bottom edges. Trigger = -, Secondary = +. Menu = next.",
			step = 0.01,
			min = -1.0,
			max = 1.0,
		},
		{
			id = "horizontal",
			cvar = "vrmod_horizontaloffset",
			title = "STEP 3 · HORIZONTAL",
			hint = "Left/right edges (both eyes). Trigger = -, Secondary = +. Menu = save.",
			step = 0.01,
			min = -1.0,
			max = 1.0,
		},
		{
			id = "done",
			title = "SAVED",
			hint = "Profile written. Trigger or Menu = close.",
		},
	},
	msg = "",
	msgUntil = 0,
}

local PROFILE = "vrmod/border_profile.txt"
local PROFILE_DIR = "vrmod"

local function cvf(name)
	local c = GetConVar(name)
	return c and c:GetFloat() or 0
end

local function setf(name, v)
	RunConsoleCommand(name, string.format("%.4f", v))
end

local function toast(s, t)
	Cal.msg = s
	Cal.msgUntil = CurTime() + (t or 2.5)
	notification.AddLegacy("[VRMod] " .. s, NOTIFY_GENERIC, t or 2)
end

function vrmod.BorderCal_SaveProfile()
	file.CreateDir(PROFILE_DIR)
	local lines = {
		"v1",
		"renderoffset=" .. (GetConVar("vrmod_renderoffset"):GetBool() and "1" or "0"),
		"scalefactor=" .. string.format("%.4f", cvf("vrmod_scalefactor")),
		"verticaloffset=" .. string.format("%.4f", cvf("vrmod_verticaloffset")),
		"horizontaloffset=" .. string.format("%.4f", cvf("vrmod_horizontaloffset")),
		"fovscale_x=" .. string.format("%.4f", cvf("vrmod_fovscale_x")),
		"fovscale_y=" .. string.format("%.4f", cvf("vrmod_fovscale_y")),
		"ts=" .. tostring(os.time()),
	}
	file.Write(PROFILE, table.concat(lines, "\n"))
	toast("Border profile saved", 3)
	return true
end

function vrmod.BorderCal_LoadProfile()
	if not file.Exists(PROFILE, "DATA") then return false end
	local raw = file.Read(PROFILE, "DATA") or ""
	local map = {
		renderoffset = "vrmod_renderoffset",
		scalefactor = "vrmod_scalefactor",
		verticaloffset = "vrmod_verticaloffset",
		horizontaloffset = "vrmod_horizontaloffset",
		fovscale_x = "vrmod_fovscale_x",
		fovscale_y = "vrmod_fovscale_y",
	}
	for line in string.gmatch(raw, "[^\r\n]+") do
		local k, v = string.match(line, "^([%w_]+)=([%-%d%.]+)$")
		if k and map[k] then
			RunConsoleCommand(map[k], v)
		end
	end
	toast("Border profile loaded", 2)
	return true
end

local function nudge(delta)
	local st = Cal.steps[Cal.step]
	if not st or not st.cvar then return end
	local v = math.Clamp(cvf(st.cvar) + delta * st.step, st.min, st.max)
	setf(st.cvar, v)
	toast(string.format("%s = %.3f", st.id, v), 1.2)
end

local function nextStep()
	Cal.step = Cal.step + 1
	if Cal.step > #Cal.steps then
		vrmod.BorderCal_Stop(true)
		return
	end
	local st = Cal.steps[Cal.step]
	if st.id == "done" then
		-- ensure auto offset stayed on
		RunConsoleCommand("vrmod_renderoffset", "1")
		vrmod.BorderCal_SaveProfile()
	end
	toast(st.title, 2)
end

function vrmod.BorderCal_IsActive()
	return Cal.active and true or false
end

function vrmod.BorderCal_Stop(completed)
	if not Cal.active then return end
	Cal.active = false
	hook.Remove("VRMod_Input", "vrmod_border_cal")
	hook.Remove("HUDPaint", "vrmod_border_cal_hud")
	hook.Remove("PostDrawTranslucentRenderables", "vrmod_border_cal_3d")
	hook.Remove("Think", "vrmod_border_cal_keys")
	hook.Remove("PlayerButtonDown", "vrmod_border_cal_keys")
	toast(completed and "Vision locked in" or "Border cal ended", 2)
	-- completed=true when user finished the path (saved profile); false on cancel
	hook.Run("VRMod_BorderCalEnded", completed and true or false)
end

function vrmod.BorderCal_Start()
	if not g_VR or not g_VR.active then
		toast("Start VR first", 3)
		return
	end
	if Cal.active then
		vrmod.BorderCal_Stop()
	end
	Cal.active = true
	Cal.step = 1
	-- clean baseline for guided path
	RunConsoleCommand("vrmod_renderoffset", "1")
	RunConsoleCommand("vrmod_scalefactor", "1.0")
	RunConsoleCommand("vrmod_verticaloffset", "0")
	RunConsoleCommand("vrmod_horizontaloffset", "0")
	toast("Border cal · look center · Trigger start", 4)

	hook.Add("VRMod_Input", "vrmod_border_cal", function(action, pressed)
		if not pressed or not Cal.active then return end
		local st = Cal.steps[Cal.step]
		if not st then return end

		-- cancel
		if action == "boolean_secondaryfire" and st.id == "reset" then
			vrmod.BorderCal_Stop()
			return
		end
		if action == "boolean_chat" or action == "boolean_menucontext" then
			-- some bindings
		end

		if st.id == "reset" then
			if action == "boolean_primaryfire" or action == "boolean_use" or action == "boolean_changeweapon" then
				nextStep()
			end
			return
		end

		if st.id == "done" then
			if action == "boolean_primaryfire" or action == "boolean_use" or action == "boolean_changeweapon" then
				vrmod.BorderCal_Stop(true)
			end
			return
		end

		-- adjust
		if action == "boolean_primaryfire" or action == "boolean_car_mouse_left" then
			nudge(-1)
			return
		end
		if action == "boolean_secondaryfire" or action == "boolean_car_mouse_right" then
			nudge(1)
			return
		end
		-- next / save
		if action == "boolean_use" or action == "boolean_changeweapon" or action == "boolean_flashlight" then
			nextStep()
			return
		end
		-- grip cancel
		if action == "boolean_left_pickup" or action == "boolean_right_pickup" then
			vrmod.BorderCal_Stop()
		end
	end)

	-- keyboard fallback (desktop / debug)
	hook.Add("Think", "vrmod_border_cal_keys", function()
		if not Cal.active then return end
		if input.IsKeyDown(KEY_ESCAPE) then
			vrmod.BorderCal_Stop()
			return
		end
	end)

	hook.Add("PlayerButtonDown", "vrmod_border_cal_keys", function(ply, btn)
		if not Cal.active or ply ~= LocalPlayer() then return end
		if btn == KEY_LEFT or btn == MOUSE_LEFT then
			nudge(-1)
		elseif btn == KEY_RIGHT or btn == MOUSE_RIGHT then
			nudge(1)
		elseif btn == KEY_ENTER or btn == KEY_SPACE then
			nextStep()
		elseif btn == KEY_BACKSPACE then
			vrmod.BorderCal_Stop()
		end
	end)

	hook.Add("HUDPaint", "vrmod_border_cal_hud", function()
		if not Cal.active then return end
		-- skip 2D clutter in stereo if desired; still useful on desktop mirror
		local st = Cal.steps[Cal.step]
		if not st then return end
		local y = ScrH() * 0.12
		draw.SimpleTextOutlined(st.title, "DermaLarge", ScrW() * 0.5, y, Color(220, 50, 50), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
		draw.SimpleTextOutlined(st.hint, "DermaDefault", ScrW() * 0.5, y + 36, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
		if st.cvar then
			draw.SimpleTextOutlined(
				string.format("%s = %.3f", st.cvar, cvf(st.cvar)),
				"DermaDefaultBold",
				ScrW() * 0.5,
				y + 58,
				Color(255, 200, 200),
				TEXT_ALIGN_CENTER,
				TEXT_ALIGN_TOP,
				1,
				color_black
			)
		end
		if Cal.msgUntil > CurTime() then
			draw.SimpleTextOutlined(Cal.msg, "DermaDefault", ScrW() * 0.5, y + 80, Color(180, 255, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
		end
		draw.SimpleTextOutlined(
			"Trigger:-  Secondary:+  Use:next  Grip:cancel  |  Keys: ← → Enter Backspace",
			"DermaDefault",
			ScrW() * 0.5,
			y + 100,
			Color(200, 200, 200),
			TEXT_ALIGN_CENTER,
			TEXT_ALIGN_TOP,
			1,
			color_black
		)
	end)

	-- world-space panel in front of HMD so Creator sees it in headset
	hook.Add("PostDrawTranslucentRenderables", "vrmod_border_cal_3d", function(depth, sky)
		if depth or sky or not Cal.active or not g_VR.active then return end
		local st = Cal.steps[Cal.step]
		if not st then return end
		local hmd = g_VR.tracking and g_VR.tracking.hmd
		if not hmd or not hmd.pos then return end
		local ang = hmd.ang or Angle()
		local pos = hmd.pos + ang:Forward() * 40 - ang:Up() * 5
		local a = Angle(ang.p, ang.y, ang.r)
		a:RotateAroundAxis(a:Right(), 90)
		a:RotateAroundAxis(a:Up(), -90)
		cam.Start3D2D(pos, a, 0.05)
			surface.SetDrawColor(0, 0, 0, 180)
			surface.DrawRect(-200, -60, 400, 140)
			draw.SimpleText(st.title, "DermaLarge", 0, -45, Color(220, 60, 60), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			draw.SimpleText(st.hint, "DermaDefault", 0, -10, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			if st.cvar then
				draw.SimpleText(string.format("%.3f", cvf(st.cvar)), "DermaLarge", 0, 25, Color(255, 180, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			end
			draw.SimpleText("− trigger   + secondary   next: use", "DermaDefault", 0, 55, Color(180, 180, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		cam.End3D2D()
	end)
end

concommand.Add("vrmod_border_calibrate", function()
	vrmod.BorderCal_Start()
end)

concommand.Add("vrmod_border_profile_save", function()
	vrmod.BorderCal_SaveProfile()
end)

concommand.Add("vrmod_border_profile_load", function()
	vrmod.BorderCal_LoadProfile()
end)

hook.Add("VRMod_Start", "vrmod_border_profile_autoload", function()
	timer.Simple(1.0, function()
		if not g_VR or not g_VR.active then return end
		-- First-run experience owns vision cal; do not preload over the guided baseline
		if vrmod.Experience_ShouldRun and vrmod.Experience_ShouldRun() then return end
		if file.Exists(PROFILE, "DATA") then
			vrmod.BorderCal_LoadProfile()
		end
	end)
end)

hook.Add("VRMod_Exit", "vrmod_border_cal_exit", function()
	vrmod.BorderCal_Stop()
end)
