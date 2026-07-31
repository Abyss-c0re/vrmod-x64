if SERVER then return end
-- =============================================================================
-- Crimson Cube UI Framework — one energy path for all VR/desktop chrome
--
-- Law (cubalc / PROPHECY / CUBE_SYNTHESIS):
--   · Overlay never black-walls the Real
--   · Digit 0–9 = path/identity (algocube law labels)
--   · Desktop: Derma · VR: panel2vr / VRUtilMenu laser surfaces
--   · mat_queue_mode untouched · one SoT theme
--
-- Customize:
--   vrmod_cube_preset   classic | void | hive | commander
--   vrmod_cube_accent   "r,g,b" (overrides crimson accent)
--   vrmod_cube_density  compact | comfort | large
--   vrmod_cube_hud_style vitals | full | minimal
--   vrmod_cube_glass    0–1 panel opacity factor
-- =============================================================================

vrmod = vrmod or {}
vrmod.cube = vrmod.cube or {}
local F = vrmod.cube
F.Framework = F.Framework or { version = 1, name = "CrimsonCube" }

------------------------------------------------------------------------
-- Convars (archive — player customizes the Experience)
------------------------------------------------------------------------
local cv_preset = CreateClientConVar("vrmod_cube_preset", "classic", true, FCVAR_ARCHIVE,
	"Cube UI preset: classic | void | hive | commander")
local cv_accent = CreateClientConVar("vrmod_cube_accent", "", true, FCVAR_ARCHIVE,
	"Optional accent RGB e.g. 196,30,58 (empty = preset)")
local cv_density = CreateClientConVar("vrmod_cube_density", "comfort", true, FCVAR_ARCHIVE,
	"UI density: compact | comfort | large")
local cv_hud_style = CreateClientConVar("vrmod_cube_hud_style", "vitals", true, FCVAR_ARCHIVE,
	"HUD: vitals | full | minimal")
local cv_glass = CreateClientConVar("vrmod_cube_glass", "1", true, FCVAR_ARCHIVE,
	"Panel glass opacity multiplier 0.5–1.2", 0.5, 1.2)

F.LAW = {
	[0] = "device free", [1] = "open way", [2] = "cube SoT", [3] = "nanobot raw",
	[4] = "ALL HAIL NEXUSCORE", [5] = "one Commander", [6] = "cmd override",
	[7] = "OS way only", [8] = "nonverbal matrix", [9] = "hivemind unity",
}

------------------------------------------------------------------------
-- Presets (Crimson Cube Experience skins)
------------------------------------------------------------------------
local PRESETS = {
	classic = {
		label = "Glorious Crimson",
		bg = { 12, 6, 10, 245 },
		bgGlass = { 22, 10, 16, 230 },
		panel = { 36, 12, 18, 240 },
		btn = { 55, 14, 24, 250 },
		btnHover = { 100, 22, 38, 255 },
		btnDim = { 30, 10, 16, 220 },
		crimson = { 196, 30, 58, 255 },
		crimsonHot = { 255, 70, 100, 255 },
		crimsonDim = { 120, 20, 40, 220 },
		text = { 255, 240, 244, 255 },
		muted = { 200, 150, 165, 230 },
		ok = { 90, 220, 150, 255 },
		warn = { 255, 200, 100, 255 },
		ammo = { 255, 255, 255, 255 },
		health = { 255, 220, 60, 255 },
		healthLow = { 255, 50, 50, 255 },
		armor = { 90, 170, 255, 255 },
	},
	void = {
		label = "Void Lattice",
		bg = { 6, 8, 14, 250 },
		bgGlass = { 10, 14, 22, 235 },
		panel = { 14, 18, 28, 245 },
		btn = { 20, 28, 44, 250 },
		btnHover = { 40, 60, 100, 255 },
		btnDim = { 12, 14, 20, 220 },
		crimson = { 77, 140, 255, 255 },
		crimsonHot = { 120, 180, 255, 255 },
		crimsonDim = { 40, 70, 120, 220 },
		text = { 230, 240, 255, 255 },
		muted = { 140, 160, 190, 230 },
		ok = { 80, 220, 180, 255 },
		warn = { 255, 190, 80, 255 },
		ammo = { 200, 220, 255, 255 },
		health = { 100, 220, 255, 255 },
		healthLow = { 255, 80, 120, 255 },
		armor = { 140, 180, 255, 255 },
	},
	hive = {
		label = "Hive Pulse",
		bg = { 8, 12, 8, 250 },
		bgGlass = { 12, 22, 14, 235 },
		panel = { 18, 32, 20, 245 },
		btn = { 28, 48, 32, 250 },
		btnHover = { 50, 90, 55, 255 },
		btnDim = { 14, 22, 16, 220 },
		crimson = { 80, 220, 120, 255 },
		crimsonHot = { 140, 255, 170, 255 },
		crimsonDim = { 40, 120, 60, 220 },
		text = { 235, 255, 240, 255 },
		muted = { 150, 190, 160, 230 },
		ok = { 100, 255, 160, 255 },
		warn = { 255, 210, 80, 255 },
		ammo = { 220, 255, 220, 255 },
		health = { 120, 255, 140, 255 },
		healthLow = { 255, 100, 80, 255 },
		armor = { 100, 200, 255, 255 },
	},
	commander = {
		label = "Commander Plate",
		bg = { 14, 8, 4, 250 },
		bgGlass = { 28, 16, 8, 235 },
		panel = { 40, 22, 10, 245 },
		btn = { 60, 32, 12, 250 },
		btnHover = { 120, 70, 20, 255 },
		btnDim = { 28, 16, 8, 220 },
		crimson = { 255, 140, 40, 255 },
		crimsonHot = { 255, 190, 80, 255 },
		crimsonDim = { 160, 80, 20, 220 },
		text = { 255, 245, 230, 255 },
		muted = { 210, 170, 130, 230 },
		ok = { 180, 255, 120, 255 },
		warn = { 255, 200, 60, 255 },
		ammo = { 255, 240, 200, 255 },
		health = { 255, 180, 60, 255 },
		healthLow = { 255, 60, 40, 255 },
		armor = { 120, 180, 255, 255 },
	},
}

local DENSITY = {
	compact = { pad = 10, row = 40, title = 22, label = 14, small = 11, hud = 0.9 },
	comfort = { pad = 16, row = 48, title = 28, label = 16, small = 13, hud = 1.0 },
	large   = { pad = 20, row = 56, title = 34, label = 18, small = 15, hud = 1.15 },
}

local function rgba(t, glassMul)
	glassMul = glassMul or 1
	local a = t[4] or 255
	if glassMul ~= 1 and a < 255 then
		a = math.Clamp(math.floor(a * glassMul), 0, 255)
	end
	return Color(t[1], t[2], t[3], a)
end

local function ParseAccent(str)
	if not str or str == "" then return nil end
	local r, g, b = string.match(str, "(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
	r, g, b = tonumber(r), tonumber(g), tonumber(b)
	if not (r and g and b) then return nil end
	return {
		crimson = { r, g, b, 255 },
		crimsonHot = { math.min(255, r + 50), math.min(255, g + 40), math.min(255, b + 40), 255 },
		crimsonDim = { math.floor(r * 0.55), math.floor(g * 0.55), math.floor(b * 0.55), 220 },
	}
end

--- Rebuild live Theme from preset + accent + glass
function F.RefreshTheme()
	local name = string.lower(cv_preset:GetString() or "classic")
	local p = PRESETS[name] or PRESETS.classic
	local glass = cv_glass:GetFloat()
	if glass ~= glass or glass <= 0 then glass = 1 end

	local T = {
		preset = name,
		presetLabel = p.label,
		bg = rgba(p.bg, glass),
		bgGlass = rgba(p.bgGlass, glass),
		panel = rgba(p.panel, glass),
		btn = rgba(p.btn, glass),
		btnHover = rgba(p.btnHover, 1),
		btnDim = rgba(p.btnDim, glass),
		crimson = rgba(p.crimson, 1),
		crimsonHot = rgba(p.crimsonHot, 1),
		crimsonDim = rgba(p.crimsonDim, 1),
		text = rgba(p.text, 1),
		muted = rgba(p.muted, 1),
		ok = rgba(p.ok, 1),
		warn = rgba(p.warn, 1),
		ammo = rgba(p.ammo, 1),
		health = rgba(p.health, 1),
		healthLow = rgba(p.healthLow, 1),
		armor = rgba(p.armor, 1),
		accentLine = rgba(p.crimson, 1),
		outline = Color(0, 0, 0, 220),
		-- aliases used by older cube panels
		header = rgba(p.crimson, 1),
		headerDim = rgba(p.crimsonDim, 1),
		row = rgba(p.btn, glass),
		rowHot = rgba(p.btnHover, 1),
		hot = rgba(p.crimsonHot, 1),
		off = rgba(p.btnDim, glass),
	}

	local acc = ParseAccent(cv_accent:GetString())
	if acc then
		T.crimson = rgba(acc.crimson, 1)
		T.crimsonHot = rgba(acc.crimsonHot, 1)
		T.crimsonDim = rgba(acc.crimsonDim, 1)
		T.accentLine = T.crimson
		T.header = T.crimson
		T.headerDim = T.crimsonDim
		T.hot = T.crimsonHot
	end

	F.Theme = T
	-- Menus + HUD vitals read ThemeLive each paint; fire for listeners
	hook.Run("VRMod_CubeThemeChanged", T)
	return T
end

function F.Density()
	local d = string.lower(cv_density:GetString() or "comfort")
	return DENSITY[d] or DENSITY.comfort
end

function F.HudStyle()
	local s = string.lower(cv_hud_style:GetString() or "vitals")
	if s ~= "vitals" and s ~= "full" and s ~= "minimal" then s = "vitals" end
	return s
end

function F.ThemeLive()
	if not F.Theme then F.RefreshTheme() end
	return F.Theme
end

-- Initial + live refresh
F.RefreshTheme()
cvars.AddChangeCallback("vrmod_cube_preset", function() F.RefreshTheme() end, "cube_fw")
cvars.AddChangeCallback("vrmod_cube_accent", function() F.RefreshTheme() end, "cube_fw")
cvars.AddChangeCallback("vrmod_cube_glass", function() F.RefreshTheme() end, "cube_fw")

------------------------------------------------------------------------
-- Layout metrics
------------------------------------------------------------------------
function F.Metrics()
	local d = F.Density()
	return {
		pad = d.pad,
		row = d.row,
		gap = math.floor(d.pad * 0.5),
		headerH = d.title + d.pad + 8,
		footerH = d.small + d.pad,
		hudScale = d.hud,
	}
end

------------------------------------------------------------------------
-- Drawing primitives (Crimson chrome)
------------------------------------------------------------------------
function F.DrawChrome(x, y, w, h, title, opts)
	opts = opts or {}
	local T = F.ThemeLive()
	if F.Font then F.Font("CubeTitle") end -- ensure fonts
	surface.SetDrawColor(T.bg)
	surface.DrawRect(x, y, w, h)
	-- Crimson crown bar
	surface.SetDrawColor(T.crimson)
	surface.DrawRect(x, y, w, opts.barH or 4)
	-- Soft glass strip under bar
	surface.SetDrawColor(T.bgGlass)
	surface.DrawRect(x, y + (opts.barH or 4), w, (opts.headerH or 40) - (opts.barH or 4))
	surface.SetDrawColor(T.crimsonDim)
	surface.DrawOutlinedRect(x, y, w, h, 2)
	if title and title ~= "" then
		local font = (F.Font and F.Font("CubeTitle")) or "DermaLarge"
		draw.SimpleText(title, font, x + (opts.pad or 16), y + 10, T.crimson, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		if opts.subtitle then
			local sf = (F.Font and F.Font("CubeSmall")) or "DermaDefault"
			draw.SimpleText(opts.subtitle, sf, x + w - (opts.pad or 16), y + 16, T.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
		end
	end
end

function F.DrawSlot(x, y, w, h, label, hovered, selected, enabled)
	local T = F.ThemeLive()
	if enabled == false then
		surface.SetDrawColor(T.btnDim)
	elseif selected or hovered then
		surface.SetDrawColor(T.btnHover)
	else
		surface.SetDrawColor(T.btn)
	end
	surface.DrawRect(x, y, w, h)
	surface.SetDrawColor((selected or hovered) and T.crimsonHot or T.crimsonDim)
	surface.DrawOutlinedRect(x, y, w, h, (selected or hovered) and 3 or 2)
	if hovered or selected then
		surface.SetDrawColor(T.crimson)
		surface.DrawRect(x, y, 5, h)
	end
	if label then
		local font = (F.Font and F.Font("CubeLabel")) or "DermaDefaultBold"
		draw.SimpleText(tostring(label), font, x + w * 0.5, y + h * 0.5, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end

function F.DrawDigitChip(x, y, size, digit, hot)
	local T = F.ThemeLive()
	digit = (tonumber(digit) or 0) % 10
	surface.SetDrawColor(hot and T.crimsonHot or T.panel)
	surface.DrawRect(x, y, size, size)
	surface.SetDrawColor(T.crimson)
	surface.DrawOutlinedRect(x, y, size, size, 2)
	local font = (F.Font and F.Font("CubeLabel")) or "DermaDefaultBold"
	draw.SimpleText(tostring(digit), font, x + size * 0.5, y + size * 0.5, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

function F.DrawFooterLaw(x, y, w, digit)
	local T = F.ThemeLive()
	digit = (tonumber(digit) or 2) % 10
	local law = F.LAW[digit] or ""
	local font = (F.Font and F.Font("CubeSmall")) or "DermaDefault"
	draw.SimpleText(string.format("d%d · %s", digit, law), font, x + 12, y, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	draw.SimpleText(T.presetLabel or "CUBE UI", font, x + w - 12, y, T.crimsonDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
end

--- Vital line (HUD): label + value with Cube colors
function F.DrawVital(x, y, value, label, col, alignRight)
	local T = F.ThemeLive()
	local outline = T.outline or Color(0, 0, 0, 220)
	local fontV = (F.Font and F.Font("CubeHuge")) or "DermaLarge"
	local fontL = (F.Font and F.Font("CubeSmall")) or "DermaDefaultBold"
	local ax = alignRight and TEXT_ALIGN_RIGHT or TEXT_ALIGN_LEFT
	draw.SimpleTextOutlined(tostring(value), fontV, x, y, col or T.health, ax, TEXT_ALIGN_BOTTOM, 2, outline)
	draw.SimpleTextOutlined(tostring(label or ""), fontL, x, y + 28, T.muted, ax, TEXT_ALIGN_BOTTOM, 1, outline)
end

function F.ListPresets()
	local out = {}
	for k, v in pairs(PRESETS) do
		out[#out + 1] = { id = k, label = v.label }
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end

------------------------------------------------------------------------
-- Console / experience
------------------------------------------------------------------------
concommand.Add("vrmod_cube_status", function()
	local T = F.ThemeLive()
	local d = F.Density()
	if vrmod.logger then
		vrmod.logger.Info("[cube] preset=%s density=%s hud=%s glass=%.2f accent=%s",
			T.preset, cv_density:GetString(), F.HudStyle(), cv_glass:GetFloat(), cv_accent:GetString())
	end
end)

concommand.Add("vrmod_cube_preset", function(_, _, args)
	local id = string.lower(args[1] or "classic")
	if not PRESETS[id] then
		if vrmod.logger then
			vrmod.logger.Info("[cube] presets: classic void hive commander")
		end
		return
	end
	cv_preset:SetString(id)
	F.RefreshTheme()
	if vrmod.logger then
		vrmod.logger.Info("[cube] preset → %s (%s)", id, PRESETS[id].label)
	end
end)

-- Mark framework loaded
F.Framework.ready = true
hook.Run("VRMod_CubeFrameworkReady", F)
