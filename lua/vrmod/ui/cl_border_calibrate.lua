-- Video / border calibration (scale → V → H → eye → FOV → lens → save)
-- G40 / W1: pure BorderLaw_* owns defaults, clamps, guided path.
-- Start preserves live cvars until Use (or Secondary = factory baseline on intro).
if SERVER then return end

vrmod = vrmod or {}
local U = vrmod.utils or {}
local Cal = {
	active = false,
	step = 1,
	steps = {
		{
			id = "reset",
			title = "VIDEO CAL",
			hint = "Live settings kept. Use = begin. Secondary = factory defaults. Grip = cancel.",
		},
		{
			id = "scale",
			cvar = "vrmod_scalefactor",
			title = "SCALE · BOUNDS",
			hint = "Black borders? Trigger = tighter (−). Secondary = looser (+). Use = next.",
			step = (U.BorderLaw_ScaleStep and U.BorderLaw_ScaleStep()) or 0.02,
			min = (U.BorderLaw_ScaleMin and U.BorderLaw_ScaleMin()) or 0.05,
			max = (U.BorderLaw_ScaleMax and U.BorderLaw_ScaleMax()) or 4.0,
			clamp = "scale",
		},
		{
			id = "vertical",
			cvar = "vrmod_verticaloffset",
			title = "VERTICAL OFFSET",
			hint = "Top/bottom. Trigger = −, Secondary = +. Use = next.",
			step = (U.BorderLaw_OffsetStep and U.BorderLaw_OffsetStep()) or 0.02,
			min = (U.BorderLaw_OffsetMin and U.BorderLaw_OffsetMin()) or -1.0,
			max = (U.BorderLaw_OffsetMax and U.BorderLaw_OffsetMax()) or 1.0,
			clamp = "offset",
		},
		{
			id = "horizontal",
			cvar = "vrmod_horizontaloffset",
			title = "HORIZONTAL OFFSET",
			hint = "Left/right (both eyes). Trigger = −, Secondary = +. Use = next.",
			step = (U.BorderLaw_OffsetStep and U.BorderLaw_OffsetStep()) or 0.02,
			min = (U.BorderLaw_OffsetMin and U.BorderLaw_OffsetMin()) or -1.0,
			max = (U.BorderLaw_OffsetMax and U.BorderLaw_OffsetMax()) or 1.0,
			clamp = "offset",
		},
		{
			id = "eye",
			cvar = "vrmod_eyescale",
			title = "EYE DISTANCE · IPD",
			hint = "Stereo depth. 1.0 = full headset IPD. Trigger = −, Secondary = +. Use = next.",
			step = (U.BorderLaw_EyeStep and U.BorderLaw_EyeStep()) or 0.05,
			min = 0.0,
			max = 1.0,
			soft_refresh = true,
		},
		{
			id = "fov_x",
			cvar = "vrmod_fovscale_x",
			title = "FOV · X",
			hint = "Horizontal FOV scale. Trigger = −, Secondary = +. Use = next.",
			step = (U.BorderLaw_FovStep and U.BorderLaw_FovStep()) or 0.02,
			min = 0.1,
			max = 2.0,
			soft_refresh = true,
			clamp = "fov",
		},
		{
			id = "fov_y",
			cvar = "vrmod_fovscale_y",
			title = "FOV · Y",
			hint = "Vertical FOV scale. Trigger = −, Secondary = +. Use = next.",
			step = (U.BorderLaw_FovStep and U.BorderLaw_FovStep()) or 0.02,
			min = 0.1,
			max = 2.0,
			soft_refresh = true,
			clamp = "fov",
		},
		{
			id = "lens",
			cvar = "vrmod_lens_bend",
			title = "LENS BEND",
			hint = "Map eye to lens (+ = pull in, − = push out). Trigger = −, Secondary = +. Use = save.",
			step = (U.BorderLaw_LensStep and U.BorderLaw_LensStep()) or 0.02,
			min = (U.BorderLaw_LensMin and U.BorderLaw_LensMin()) or -0.5,
			max = (U.BorderLaw_LensMax and U.BorderLaw_LensMax()) or 0.5,
			clamp = "lens",
		},
		{
			id = "done",
			title = "SAVED",
			hint = "Profile written. Trigger or Use = close.",
		},
	},
	msg = "",
	msgUntil = 0,
}

local PROFILE = (U.BorderLaw_ProfilePath and U.BorderLaw_ProfilePath()) or "vrmod/border_profile.txt"
local PROFILE_DIR = "vrmod"

local function cvf(name)
	local c = GetConVar(name)
	return c and c:GetFloat() or 0
end

local function cvb(name)
	local c = GetConVar(name)
	return c and c:GetBool() or false
end

--- Immediate float set + live UV / eye apply (do not rely on deferred RunConsoleCommand alone).
local function setf(name, v)
	local c = GetConVar(name)
	local s = string.format("%.4f", v)
	if c and c.SetFloat then
		c:SetFloat(v)
	end
	-- Also poke engine convar string so ChangeCallback / archive see it
	RunConsoleCommand(name, s)
	-- Submit UV path (scale / V / H / lens)
	if vrmod.ForceApplySubmitBounds then
		pcall(vrmod.ForceApplySubmitBounds)
	end
	-- FOV / viewscale need SoftRefresh when available
	if name == "vrmod_fovscale_x" or name == "vrmod_fovscale_y" or name == "vrmod_viewscale" then
		if vrmod.SoftRefreshDisplayParams then
			pcall(vrmod.SoftRefreshDisplayParams)
		elseif isfunction(VRMOD_GetDisplayInfo) then
			-- Fallback: trigger convar callback path via re-set
			RunConsoleCommand(name, s)
		end
	end
	-- IPD (eyescale) is read every stereo frame — no extra force needed
end

local function toast(s, t)
	Cal.msg = s
	Cal.msgUntil = CurTime() + (t or 2.5)
	notification.AddLegacy("[VRMod] " .. s, NOTIFY_GENERIC, t or 2)
end

local function borderSnapshot(extra)
	local u = vrmod.utils
	if not u or not u.BorderLaw_Decide then return end
	local opts = {
		scalefactor = cvf("vrmod_scalefactor"),
		verticaloffset = cvf("vrmod_verticaloffset"),
		horizontaloffset = cvf("vrmod_horizontaloffset"),
		lens_bend = cvf("vrmod_lens_bend"),
		guide_active = Cal.active and true or false,
		profile_loaded = extra and extra.profile_loaded or false,
	}
	if extra then
		for k, v in pairs(extra) do opts[k] = v end
	end
	local d = u.BorderLaw_Decide(opts)
	g_VR = g_VR or {}
	g_VR._borderLaw = d
	g_VR._borderLawLabel = u.BorderLaw_StatusLabel and u.BorderLaw_StatusLabel(d) or nil
	g_VR._borderLawHmdExpect = u.BorderLaw_HmdExpect and u.BorderLaw_HmdExpect(d) or nil
end

local function applyFactoryBaseline()
	local base = (vrmod.utils and vrmod.utils.BorderLaw_GuideBaseline and vrmod.utils.BorderLaw_GuideBaseline())
		or {
			scalefactor = 1.0,
			verticaloffset = 0,
			horizontaloffset = 0,
			renderoffset = 1,
			eyescale = 1.0,
			fovscale_x = 1.0,
			fovscale_y = 1.0,
			lens_bend = 0.0,
		}
	RunConsoleCommand("vrmod_renderoffset", tostring(base.renderoffset or 1))
	setf("vrmod_scalefactor", base.scalefactor or 1)
	setf("vrmod_verticaloffset", base.verticaloffset or 0)
	setf("vrmod_horizontaloffset", base.horizontaloffset or 0)
	setf("vrmod_eyescale", base.eyescale or 1)
	setf("vrmod_fovscale_x", base.fovscale_x or 1)
	setf("vrmod_fovscale_y", base.fovscale_y or 1)
	setf("vrmod_lens_bend", base.lens_bend or 0)
	-- swap eyes deprecated — force off on factory reset
	RunConsoleCommand("vrmod_swap_eyes", "0")
	toast("Factory video defaults applied", 2)
	borderSnapshot({ guide_active = true })
end

function vrmod.BorderCal_SaveProfile()
	file.CreateDir(PROFILE_DIR)
	local lines = {
		"v1",
		"renderoffset=" .. (cvb("vrmod_renderoffset") and "1" or "0"),
		"scalefactor=" .. string.format("%.4f", cvf("vrmod_scalefactor")),
		"verticaloffset=" .. string.format("%.4f", cvf("vrmod_verticaloffset")),
		"horizontaloffset=" .. string.format("%.4f", cvf("vrmod_horizontaloffset")),
		"fovscale_x=" .. string.format("%.4f", cvf("vrmod_fovscale_x")),
		"fovscale_y=" .. string.format("%.4f", cvf("vrmod_fovscale_y")),
		"eyescale=" .. string.format("%.4f", cvf("vrmod_eyescale")),
		"lens_bend=" .. string.format("%.4f", cvf("vrmod_lens_bend")),
		"ts=" .. tostring(os.time()),
	}
	file.Write(PROFILE, table.concat(lines, "\n"))
	toast("Video calibration saved", 3)
	borderSnapshot({ profile_loaded = true, guide_active = false })
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
		eyescale = "vrmod_eyescale",
		lens_bend = "vrmod_lens_bend",
	}
	local u = vrmod.utils
	for line in string.gmatch(raw, "[^\r\n]+") do
		local k, v = string.match(line, "^([%w_]+)=([%-%d%.]+)$")
		if k and map[k] then
			if u and k == "scalefactor" and u.BorderLaw_ClampScale then
				v = string.format("%.4f", u.BorderLaw_ClampScale(tonumber(v)))
			elseif u and (k == "verticaloffset" or k == "horizontaloffset") and u.BorderLaw_ClampOffset then
				v = string.format("%.4f", u.BorderLaw_ClampOffset(tonumber(v)))
			elseif u and k == "lens_bend" and u.BorderLaw_ClampLens then
				v = string.format("%.4f", u.BorderLaw_ClampLens(tonumber(v)))
			end
			local c = GetConVar(map[k])
			local num = tonumber(v)
			if c and c.SetFloat and num then
				c:SetFloat(num)
			end
			RunConsoleCommand(map[k], v)
		end
	end
	if vrmod.ForceApplySubmitBounds then
		pcall(vrmod.ForceApplySubmitBounds)
	end
	toast("Video calibration loaded", 2)
	borderSnapshot({ profile_loaded = true, guide_active = false })
	return true
end

local function nudge(delta)
	local st = Cal.steps[Cal.step]
	if not st or not st.cvar then return end
	local raw = cvf(st.cvar) + delta * st.step
	local u = vrmod.utils
	local v
	if st.clamp == "scale" and u and u.BorderLaw_ClampScale then
		v = u.BorderLaw_ClampScale(raw)
	elseif st.clamp == "offset" and u and u.BorderLaw_ClampOffset then
		v = u.BorderLaw_ClampOffset(raw)
	elseif st.clamp == "lens" and u and u.BorderLaw_ClampLens then
		v = u.BorderLaw_ClampLens(raw)
	elseif st.clamp == "fov" and u and u.FovZLaw_ClampFovScale then
		v = u.FovZLaw_ClampFovScale(raw)
	else
		v = math.Clamp(raw, st.min or -1, st.max or 1)
	end
	setf(st.cvar, v)
	toast(string.format("%s = %.3f", st.id, v), 1.2)
	borderSnapshot({ guide_active = true })
end

local function nextStep()
	Cal.step = Cal.step + 1
	if Cal.step > #Cal.steps then
		vrmod.BorderCal_Stop(true)
		return
	end
	local st = Cal.steps[Cal.step]
	if st.id == "done" then
		-- keep auto offset on for stable submit
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
	toast(completed and "Vision locked in" or "Video calibration ended", 2)
	borderSnapshot({ guide_active = false, profile_loaded = completed and true or false })
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
	-- Do NOT reset live settings on open. Use begins dialing; Secondary on intro = factory.
	toast("Video cal · live settings kept · Use to begin", 4)
	borderSnapshot({ guide_active = true })

	hook.Add("VRMod_Input", "vrmod_border_cal", function(action, pressed)
		if not pressed or not Cal.active then return end
		local st = Cal.steps[Cal.step]
		if not st then return end

		if st.id == "reset" then
			-- Secondary on intro only: factory defaults (explicit user choice)
			if action == "boolean_secondaryfire" or action == "boolean_car_mouse_right" then
				applyFactoryBaseline()
				return
			end
			if action == "boolean_primaryfire" or action == "boolean_use" or action == "boolean_changeweapon" then
				nextStep()
			end
			if action == "boolean_left_pickup" or action == "boolean_right_pickup" then
				vrmod.BorderCal_Stop()
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

	hook.Add("Think", "vrmod_border_cal_keys", function()
		if not Cal.active then return end
		if input.IsKeyDown(KEY_ESCAPE) then
			vrmod.BorderCal_Stop()
			return
		end
	end)

	hook.Add("PlayerButtonDown", "vrmod_border_cal_keys", function(ply, btn)
		if not Cal.active or ply ~= LocalPlayer() then return end
		local st = Cal.steps[Cal.step]
		if st and st.id == "reset" then
			if btn == KEY_R then
				applyFactoryBaseline()
			elseif btn == KEY_ENTER or btn == KEY_SPACE then
				nextStep()
			elseif btn == KEY_BACKSPACE then
				vrmod.BorderCal_Stop()
			end
			return
		end
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
		else
			draw.SimpleTextOutlined(
				string.format(
					"scale=%.2f V=%.2f H=%.2f eye=%.2f FOV=%.2f/%.2f lens=%.2f",
					cvf("vrmod_scalefactor"),
					cvf("vrmod_verticaloffset"),
					cvf("vrmod_horizontaloffset"),
					cvf("vrmod_eyescale"),
					cvf("vrmod_fovscale_x"),
					cvf("vrmod_fovscale_y"),
					cvf("vrmod_lens_bend")
				),
				"DermaDefault",
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
			"Trigger:−  Secondary:+  Use:next  Grip:cancel  |  Keys: ← → Enter Backspace (R=defaults on intro)",
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
			surface.DrawRect(-220, -70, 440, 160)
			draw.SimpleText(st.title, "DermaLarge", 0, -55, Color(220, 60, 60), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			draw.SimpleText(st.hint, "DermaDefault", 0, -18, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			if st.cvar then
				draw.SimpleText(string.format("%.3f", cvf(st.cvar)), "DermaLarge", 0, 20, Color(255, 180, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
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
