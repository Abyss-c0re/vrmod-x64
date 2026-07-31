-- =============================================================================
-- vrmod.SettingsCatalog — single source of truth for Settings UI
--
-- Used by:
--   • Desktop / non-VR: VRUtilOpenMenu (Derma) via cl_settings.lua
--   • VR: Cube hand settings via cl_cube_settings.lua
--
-- Row kinds:
--   bool    { label, cvar [, default] }
--   slider  { label, cvar, min, max, decimals }
--   combo   { label, cvar, choices = { {text, value}, ... } }  -- value = convar string/int
--   color   { label, cvar }  -- "r,g,b,a" string (UI beam / weapon laser)
--   action  { label, cmd = "concommand" }  OR  { label, action_id = "..." }
--   header  { label }
--   help    { label }
--
-- action_id is resolved by the host UI (apply_offsets, reset_offsets, open_avatar, …)
-- so VR and desktop share the same catalog without embedding closures.
-- =============================================================================
if SERVER then
	-- shared file: still AddCSLuaFile via loader; no runtime data needed on server
end

vrmod = vrmod or {}

--- @type table[] categories
vrmod.SettingsCatalog = {
	{
		id = "controls",
		title = "Controls",
		icon = "icon16/controller.png",
		rows = {
			{ kind = "bool", label = "Smooth turning", cvar = "vrmod_smoothturn" },
			{ kind = "slider", label = "Smooth turn rate", cvar = "vrmod_smoothturnrate", min = 1, max = 1000, decimals = 0 },
			{ kind = "bool", label = "Teleportation (Server)", cvar = "vrmod_allow_teleport" },
			{ kind = "bool", label = "Teleportation (Client)", cvar = "vrmod_allow_teleport_client" },
			{ kind = "bool", label = "Teleport with left hand", cvar = "vrmod_teleport_use_left" },
			{ kind = "slider", label = "Teleport max distance", cvar = "vrmod_teleport_maxdist", min = 0, max = 1000, decimals = 0 },
			{ kind = "bool", label = "Alternative head angles", cvar = "vrmod_althead" },
			{ kind = "help", label = "Less precise — jigglebone compatibility" },
			{ kind = "action", label = "Edit controller actions", cmd = "vrmod_actioneditor" },
			{ kind = "header", label = "Controller offsets" },
			{ kind = "slider", label = "Offset X", cvar = "vrmod_controlleroffset_x", min = -30, max = 30, decimals = 0 },
			{ kind = "slider", label = "Offset Y", cvar = "vrmod_controlleroffset_y", min = -30, max = 30, decimals = 0 },
			{ kind = "slider", label = "Offset Z", cvar = "vrmod_controlleroffset_z", min = -30, max = 30, decimals = 0 },
			{ kind = "slider", label = "Offset Pitch", cvar = "vrmod_controlleroffset_pitch", min = -180, max = 180, decimals = 0 },
			{ kind = "slider", label = "Offset Yaw", cvar = "vrmod_controlleroffset_yaw", min = -180, max = 180, decimals = 0 },
			{ kind = "slider", label = "Offset Roll", cvar = "vrmod_controlleroffset_roll", min = -180, max = 180, decimals = 0 },
			{ kind = "action", label = "Apply offsets", action_id = "apply_offsets" },
			{ kind = "action", label = "Reset offsets", action_id = "reset_offsets" },
			{ kind = "bool", label = "Floating hands", cvar = "vrmod_floatinghands" },
			{ kind = "bool", label = "Laser pointer on tools/weapons", cvar = "vrmod_laserpointer" },
			{ kind = "bool", label = "Show height/avatar menu on start", cvar = "vrmod_heightmenu" },
			{ kind = "bool", label = "Seated offset", cvar = "vrmod_seated" },
			{ kind = "help", label = "Adjust seated offset from Avatar menu" },
			{ kind = "bool", label = "Autostart VR after map load", cvar = "vrmod_autostart" },
			{ kind = "bool", label = "Climbing mechanics", cvar = "vrmod_climbing" },
			{ kind = "bool", label = "Door use mechanics", cvar = "vrmod_doors" },
			{ kind = "action", label = "Reset all settings", cmd = "vrmod_reset" },
		},
	},
	{
		id = "rendering",
		title = "Rendering",
		icon = "icon16/monitor.png",
		rows = {
			{ kind = "combo", label = "Desktop view", cvar = "vrmod_desktopview", choices = {
				{ text = "none", value = 1 },
				{ text = "left eye", value = 2 },
				{ text = "right eye", value = 3 },
			}},
			{ kind = "bool", label = "Engine post-processing", cvar = "vrmod_postprocess" },
			{ kind = "bool", label = "Auto render offset", cvar = "vrmod_renderoffset" },
			{ kind = "help", label = "Disable if rendering glitches" },
			{ kind = "bool", label = "3D Skybox", cvar = "vrmod_skybox" },
			{ kind = "help", label = "Disable for more FPS" },
			{ kind = "bool", label = "Swap eyes", cvar = "vrmod_swap_eyes" },
			{ kind = "slider", label = "View scale", cvar = "vrmod_viewscale", min = 0.1, max = 2.0, decimals = 2 },
			{ kind = "help", label = "Higher = world looks smaller" },
			{ kind = "slider", label = "Supersample", cvar = "vrmod_supersample", min = 0.5, max = 2.0, decimals = 2 },
			{ kind = "help", label = "1.0 native · 1.5 crisp · restart VR after change" },
			{ kind = "slider", label = "FOV scale X", cvar = "vrmod_fovscale_x", min = 0.1, max = 2.0, decimals = 2 },
			{ kind = "slider", label = "FOV scale Y", cvar = "vrmod_fovscale_y", min = 0.1, max = 2.0, decimals = 2 },
			{ kind = "slider", label = "ZNear", cvar = "vrmod_znear", min = -3.0, max = 3.0, decimals = 2 },
			{ kind = "slider", label = "Eye distance offset", cvar = "vrmod_eyescale", min = 0.0, max = 1.0, decimals = 2 },
			{ kind = "slider", label = "Scale factor", cvar = "vrmod_scalefactor", min = 0.05, max = 4.0, decimals = 2 },
			{ kind = "slider", label = "Vertical offset", cvar = "vrmod_verticaloffset", min = -1.0, max = 1.0, decimals = 2 },
			{ kind = "slider", label = "Horizontal offset", cvar = "vrmod_horizontaloffset", min = -1.0, max = 1.0, decimals = 2 },
			{ kind = "action", label = "Border calibrate", cmd = "vrmod_border_calibrate" },
			{ kind = "action", label = "Load border profile", cmd = "vrmod_border_profile_load" },
			{ kind = "action", label = "Reset vision defaults", action_id = "reset_vision" },
		},
	},
	{
		id = "gameplay",
		title = "Gameplay",
		icon = "icon16/joystick.png",
		rows = {
			{ kind = "bool", label = "Disable pickup (Client)", cvar = "vr_pickup_disable_client" },
			{ kind = "bool", label = "Disable pickup prop physics (Server)", cvar = "vrmod_pickup_no_phys" },
			{ kind = "bool", label = "Wall collisions (Client)", cvar = "vrmod_collisions" },
			{ kind = "bool", label = "Prop collisions (Server)", cvar = "vrmod_collison_proxy" },
			{ kind = "bool", label = "Flashlight on left hand", cvar = "vrmod_flashlight_attachment" },
			{ kind = "bool", label = "Drop weapon on grip release", cvar = "vrmod_weapondrop_enable" },
			{ kind = "bool", label = "Manual item pickup", cvar = "vrmod_manualpickups" },
			{ kind = "bool", label = "Interactive buttons", cvar = "vrmod_interactive_buttons" },
			{ kind = "bool", label = "Replace weapons with ArcVR", cvar = "vrmod_weapon_swap" },
			{ kind = "bool", label = "Pickup weight limit (Server)", cvar = "vrmod_pickup_limit" },
			{ kind = "bool", label = "Pickup NPCs (Server)", cvar = "vrmod_pickup_npcs" },
			{ kind = "bool", label = "Show pickup halos", cvar = "vrmod_pickup_halos" },
			{ kind = "slider", label = "Wall collision push", cvar = "vrmod_hand_collision_push", min = 0, max = 8, decimals = 2 },
			{ kind = "slider", label = "Pickup weight (Server)", cvar = "vrmod_pickup_weight", min = 1, max = 10000, decimals = 0 },
			{ kind = "slider", label = "Pickup range (Server)", cvar = "vrmod_pickup_range", min = 0, max = 10, decimals = 1 },
			{ kind = "action", label = "Adjust weapons", cmd = "vrmod_weaponconfig" },
			{ kind = "action", label = "Reset gameplay defaults", action_id = "reset_gameplay" },
		},
	},
	{
		id = "character",
		title = "Character",
		icon = "icon16/user.png",
		rows = {
			{ kind = "header", label = "Animation" },
			{ kind = "bool", label = "Character IK", cvar = "vrmod_characterik" },
			{ kind = "bool", label = "Arm stretcher", cvar = "vrmod_armstretcher" },
			{ kind = "header", label = "Calibration" },
			{ kind = "slider", label = "Eye height", cvar = "vrmod_charactereyeheight", min = 30, max = 100, decimals = 1 },
			{ kind = "slider", label = "Head to HMD distance", cvar = "vrmod_characterheadtohmddist", min = 0, max = 20, decimals = 1 },
			{ kind = "action", label = "Open Avatar menu", action_id = "open_avatar" },
			{ kind = "action", label = "Auto height", action_id = "auto_height" },
			{ kind = "action", label = "Auto seated offset", action_id = "auto_seated" },
			{ kind = "action", label = "Restore character defaults", action_id = "reset_character" },
		},
	},
	{
		id = "hud",
		title = "HUD/UI",
		icon = "icon16/layers.png",
		rows = {
			{ kind = "bool", label = "Enable HUD", cvar = "vrmod_hud" },
			{ kind = "slider", label = "HUD curve", cvar = "vrmod_hudcurve", min = -100, max = 100, decimals = 0 },
			{ kind = "slider", label = "HUD distance", cvar = "vrmod_huddistance", min = 1, max = 100, decimals = 0 },
			{ kind = "slider", label = "HUD scale", cvar = "vrmod_hudscale", min = 0.01, max = 0.1, decimals = 2 },
			{ kind = "slider", label = "HUD transparency", cvar = "vrmod_hudtestalpha", min = 0, max = 255, decimals = 0 },
			{ kind = "bool", label = "HUD only with menu key", cvar = "vrmod_hud_visible_quickmenukey" },
			{ kind = "bool", label = "Menu & UI red outline", cvar = "vrmod_ui_outline" },
			{ kind = "header", label = "Pointer colors (same as classic Derma)" },
			{ kind = "color", label = "UI beam color", cvar = "vrmod_beam_color" },
			{ kind = "color", label = "Weapon laser color", cvar = "vrmod_laser_color" },
			{ kind = "action", label = "UI reset", cmd = "vrmod_vgui_reset" },
			{ kind = "action", label = "HUD/UI defaults", action_id = "reset_hud" },
		},
	},
	{
		id = "melee",
		title = "Melee",
		icon = "icon16/asterisk_orange.png",
		rows = {
			{ kind = "bool", label = "Melee (client)", cvar = "cl_vrmod_melee" },
			{ kind = "bool", label = "Melee (server)", cvar = "sv_vrmod_melee" },
			{ kind = "slider", label = "Velocity threshold", cvar = "vrmod_melee_velthreshold", min = 0.1, max = 10, decimals = 1 },
			{ kind = "slider", label = "Damage", cvar = "vrmod_melee_damage", min = 0, max = 10, decimals = 0 },
			{ kind = "slider", label = "Delay", cvar = "vrmod_melee_delay", min = 0.01, max = 1, decimals = 2 },
			{ kind = "slider", label = "Speed scale", cvar = "vrmod_melee_speedscale", min = 0.001, max = 0.05, decimals = 3 },
			{ kind = "action", label = "Reset melee defaults", action_id = "reset_melee" },
		},
	},
	{
		id = "driving",
		title = "Driving",
		icon = "icon16/car.png",
		rows = {
			{ kind = "slider", label = "Pitch sensitivity", cvar = "vrmod_sens_pitch", min = 0, max = 5, decimals = 2 },
			{ kind = "slider", label = "Pitch smooth", cvar = "vrmod_sens_pitch_smooth", min = 0, max = 1, decimals = 2 },
			{ kind = "slider", label = "Yaw sensitivity", cvar = "vrmod_sens_yaw", min = 0, max = 5, decimals = 2 },
			{ kind = "slider", label = "Yaw smooth", cvar = "vrmod_sens_yaw_smooth", min = 0, max = 1, decimals = 2 },
			{ kind = "slider", label = "Roll sensitivity", cvar = "vrmod_sens_roll", min = 0, max = 5, decimals = 2 },
			{ kind = "slider", label = "Roll smooth", cvar = "vrmod_sens_roll_smooth", min = 0, max = 1, decimals = 2 },
			{ kind = "slider", label = "Car steer sensitivity", cvar = "vrmod_sens_steer_car", min = 0, max = 5, decimals = 2 },
			{ kind = "slider", label = "Car steer smooth", cvar = "vrmod_sens_steer_car_smooth", min = 0, max = 1, decimals = 2 },
			{ kind = "slider", label = "Car rotation range", cvar = "vrmod_rot_range_car", min = 0, max = 1080, decimals = 0 },
			{ kind = "slider", label = "Moto steer sensitivity", cvar = "vrmod_sens_steer_motorcycle", min = 0, max = 5, decimals = 2 },
			{ kind = "slider", label = "Moto steer smooth", cvar = "vrmod_sens_steer_motorcycle_smooth", min = 0, max = 1, decimals = 2 },
			{ kind = "slider", label = "Moto rotation range", cvar = "vrmod_rot_range_motorcycle", min = 0, max = 1080, decimals = 0 },
			{ kind = "action", label = "Reset driving defaults", action_id = "reset_driving" },
		},
	},
	{
		id = "debug",
		title = "Debug",
		icon = "icon16/bug.png",
		rows = {
			{ kind = "combo", label = "Console log level", cvar = "vrmod_log_console", choices = {
				{ text = "OFF", value = 0 },
				{ text = "ERROR", value = 1 },
				{ text = "WARN", value = 2 },
				{ text = "INFO", value = 3 },
				{ text = "DEBUG", value = 4 },
			}},
			{ kind = "combo", label = "File log level", cvar = "vrmod_log_file", choices = {
				{ text = "OFF", value = 0 },
				{ text = "ERROR", value = 1 },
				{ text = "WARN", value = 2 },
				{ text = "INFO", value = 3 },
				{ text = "DEBUG", value = 4 },
			}},
			{ kind = "bool", label = "Visible wall collision", cvar = "vrmod_debug_collisions" },
			{ kind = "bool", label = "Redirect server prints to VR", cvar = "vrmod_console_redirect" },
			{ kind = "help", label = "Subsystem debug toggles: use desktop menu if missing here" },
		},
	},
	{
		id = "session",
		title = "Session",
		icon = "icon16/disconnect.png",
		rows = {
			{ kind = "action", label = "Start / Restart VR", action_id = "restart_vr" },
			{ kind = "action", label = "Exit VR", action_id = "exit_vr" },
			{ kind = "action", label = "Close settings", action_id = "close_settings" },
		},
	},
}

------------------------------------------------------------------------
-- Color helpers — "r,g,b,a" strings (vrmod_beam_color / vrmod_laser_color)
------------------------------------------------------------------------
function vrmod.SettingsParseColor(str, fallback)
	fallback = fallback or Color(255, 0, 0, 255)
	if not str or str == "" then return Color(fallback.r, fallback.g, fallback.b, fallback.a) end
	local r, g, b, a = string.match(tostring(str), "(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
	if not r then
		r, g, b = string.match(tostring(str), "(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
		a = 255
	end
	if not r then return Color(fallback.r, fallback.g, fallback.b, fallback.a) end
	return Color(tonumber(r) or 255, tonumber(g) or 0, tonumber(b) or 0, tonumber(a) or 255)
end

function vrmod.SettingsFormatColor(col)
	if not col then return "255,0,0,255" end
	return string.format("%d,%d,%d,%d",
		math.Clamp(math.floor(col.r or 255), 0, 255),
		math.Clamp(math.floor(col.g or 0), 0, 255),
		math.Clamp(math.floor(col.b or 0), 0, 255),
		math.Clamp(math.floor(col.a or 255), 0, 255))
end

function vrmod.SettingsGetColor(cvar, fallback)
	local c = GetConVar(cvar)
	return vrmod.SettingsParseColor(c and c:GetString() or nil, fallback)
end

function vrmod.SettingsSetColor(cvar, col)
	if not cvar or not col then return end
	RunConsoleCommand(cvar, vrmod.SettingsFormatColor(col))
end

--- Shared action handlers (VR + desktop). Host may wrap close.
function vrmod.SettingsRunAction(action_id, ctx)
	ctx = ctx or {}
	if action_id == "apply_offsets" then
		local function f(n, d)
			local c = GetConVar(n)
			return c and c:GetFloat() or d
		end
		local x, y, z = f("vrmod_controlleroffset_x", -10), f("vrmod_controlleroffset_y", -5), f("vrmod_controlleroffset_z", 10)
		local p, yw, r = f("vrmod_controlleroffset_pitch", 50), f("vrmod_controlleroffset_yaw", 0), f("vrmod_controlleroffset_roll", 0)
		if g_VR then
			g_VR.rightControllerOffsetPos = Vector(x, y, z)
			g_VR.leftControllerOffsetPos = Vector(x, -y, z)
			g_VR.rightControllerOffsetAng = Angle(p, yw, r)
			g_VR.leftControllerOffsetAng = g_VR.rightControllerOffsetAng
		end
		return true
	end
	if action_id == "reset_offsets" then
		RunConsoleCommand("vrmod_controlleroffset_x", "-10")
		RunConsoleCommand("vrmod_controlleroffset_y", "-5")
		RunConsoleCommand("vrmod_controlleroffset_z", "10")
		RunConsoleCommand("vrmod_controlleroffset_pitch", "50")
		RunConsoleCommand("vrmod_controlleroffset_yaw", "0")
		RunConsoleCommand("vrmod_controlleroffset_roll", "0")
		if g_VR then
			g_VR.rightControllerOffsetPos = Vector(-15, -1, 5)
			g_VR.leftControllerOffsetPos = Vector(-15, 1, 5)
			g_VR.rightControllerOffsetAng = Angle(50, 0, 0)
			g_VR.leftControllerOffsetAng = Angle(50, 0, 0)
		end
		return true
	end
	if action_id == "reset_vision" then
		RunConsoleCommand("vrmod_postprocess", "0")
		RunConsoleCommand("vrmod_skybox", "0")
		RunConsoleCommand("vrmod_renderoffset", "1")
		RunConsoleCommand("vrmod_viewscale", "1.0")
		RunConsoleCommand("vrmod_supersample", "1.5")
		RunConsoleCommand("vrmod_fovscale_x", "1.0")
		RunConsoleCommand("vrmod_fovscale_y", "1.0")
		RunConsoleCommand("vrmod_znear", "1.0")
		RunConsoleCommand("vrmod_eyescale", "0.5")
		RunConsoleCommand("vrmod_scalefactor", "1.0")
		RunConsoleCommand("vrmod_verticaloffset", "0")
		RunConsoleCommand("vrmod_horizontaloffset", "0")
		if vrmod.Experience_Reset then
			vrmod.Experience_Reset()
		else
			RunConsoleCommand("vrmod_experience_reset")
		end
		return true
	end
	if action_id == "reset_gameplay" then
		RunConsoleCommand("vrmod_allow_teleport_client", "0")
		RunConsoleCommand("vr_pickup_disable_client", "0")
		RunConsoleCommand("vrmod_pickup_no_phys", "0")
		RunConsoleCommand("vrmod_weapondrop_enable", "1")
		RunConsoleCommand("vrmod_manualpickups", "1")
		RunConsoleCommand("vrmod_interactive_buttons", "1")
		RunConsoleCommand("vrmod_weapon_swap", "1")
		RunConsoleCommand("vrmod_pickup_weight", "150")
		RunConsoleCommand("vrmod_pickup_range", "3.5")
		RunConsoleCommand("vrmod_pickup_limit", "1")
		RunConsoleCommand("vrmod_pickup_npcs", "1")
		RunConsoleCommand("vrmod_pickup_halos", "1")
		RunConsoleCommand("vrmod_collisions", "1")
		RunConsoleCommand("vrmod_collison_proxy", "1")
		return true
	end
	if action_id == "reset_character" then
		RunConsoleCommand("vrmod_characterik", "1")
		RunConsoleCommand("vrmod_armstretcher", "0")
		RunConsoleCommand("vrmod_charactereyeheight", "66.8")
		RunConsoleCommand("vrmod_characterheadtohmddist", "6.3")
		return true
	end
	if action_id == "reset_hud" then
		RunConsoleCommand("vrmod_hud", "1")
		RunConsoleCommand("vrmod_hudcurve", "60")
		RunConsoleCommand("vrmod_huddistance", "60")
		RunConsoleCommand("vrmod_hudscale", "0.05")
		RunConsoleCommand("vrmod_hudtestalpha", "0")
		RunConsoleCommand("vrmod_hudblacklist", "")
		RunConsoleCommand("vrmod_hud_visible_quickmenukey", "0")
		RunConsoleCommand("vrmod_beam_color", "255,0,0,255")
		RunConsoleCommand("vrmod_laser_color", "255,0,0,255")
		return true
	end
	if action_id == "reset_melee" then
		RunConsoleCommand("cl_vrmod_melee", "1")
		RunConsoleCommand("sv_vrmod_melee", "1")
		RunConsoleCommand("vrmod_melee_velthreshold", "1.5")
		RunConsoleCommand("vrmod_melee_damage", "3")
		RunConsoleCommand("vrmod_melee_delay", "0.45")
		RunConsoleCommand("vrmod_melee_speedscale", "0.030")
		RunConsoleCommand("vrmod_melee_fist_collisionmodel", "models/props_junk/PopCan01a.mdl")
		return true
	end
	if action_id == "reset_driving" then
		RunConsoleCommand("vrmod_sens_pitch", "1.5")
		RunConsoleCommand("vrmod_sens_pitch_smooth", "0.1")
		RunConsoleCommand("vrmod_sens_yaw", "1.25")
		RunConsoleCommand("vrmod_sens_yaw_smooth", "0.1")
		RunConsoleCommand("vrmod_sens_roll", "0.15")
		RunConsoleCommand("vrmod_sens_roll_smooth", "0.1")
		RunConsoleCommand("vrmod_sens_steer_car", "0.75")
		RunConsoleCommand("vrmod_sens_steer_car_smooth", "0.15")
		RunConsoleCommand("vrmod_rot_range_car", "900")
		RunConsoleCommand("vrmod_sens_steer_motorcycle", "0.30")
		RunConsoleCommand("vrmod_sens_steer_motorcycle_smooth", "0.15")
		RunConsoleCommand("vrmod_rot_range_motorcycle", "360")
		return true
	end
	if action_id == "open_avatar" then
		if vrmod.AvatarMenu_Open then
			vrmod.AvatarMenu_Open()
		elseif VRUtilOpenHeightMenu then
			VRUtilOpenHeightMenu()
		else
			RunConsoleCommand("vrmod_avatar")
		end
		return true
	end
	if action_id == "auto_height" then
		if vrmod.AutoScaleHeight then vrmod.AutoScaleHeight() end
		return true
	end
	if action_id == "auto_seated" then
		if vrmod.AutoSeatedOffset then vrmod.AutoSeatedOffset() end
		return true
	end
	if action_id == "restart_vr" then
		if g_VR and g_VR.active then
			VRUtilClientExit()
			timer.Simple(1, function() VRUtilClientStart() end)
		else
			VRUtilClientStart()
		end
		return true
	end
	if action_id == "exit_vr" then
		RunConsoleCommand("vrmod_exit")
		return true
	end
	if action_id == "close_settings" then
		if ctx.close then ctx.close() end
		return true
	end
	return false
end

--- Unified open: VR → cube hand panel; desktop → Derma. Same catalog either way.
function vrmod.Settings_Open()
	if CLIENT and g_VR and g_VR.active and isfunction(vrmod.CubeSettings_Open) then
		vrmod.CubeSettings_Open()
		return "vr"
	end
	if CLIENT and isfunction(VRUtilOpenMenu) then
		return VRUtilOpenMenu()
	end
	return nil
end

function vrmod.Settings_Close()
	if CLIENT and vrmod.CubeSettings_IsOpen and vrmod.CubeSettings_IsOpen() then
		vrmod.CubeSettings_Close()
	end
	-- Derma frame is closed by user / Remove; no global handle required
end
