if SERVER then return end
-- =============================================================================
-- Cube UI Framework — customizable + extensible per-element theme
--
-- Every UI atom is a registered element (id → color/token/font/visible).
-- Presets fill defaults; per-element overrides persist; addons RegisterElement.
--
--   F.El("hud.health")           → Color
--   F.RegisterElement(id, def)   → extend
--   F.SetElementColor(id, col)   → customize
--   F.ListElements()             → Theme settings / tools
--
-- Global: vrmod_cube_preset | accent | density | glass
-- Elements: data/vrmod/cube_elements.json + optional vrmod_cube_el_* cvars
-- =============================================================================

vrmod = vrmod or {}
vrmod.cube = vrmod.cube or {}
local F = vrmod.cube
F.Framework = F.Framework or { version = 2, name = "CubeTheme" }

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
-- Presets (Cube theme skins)
------------------------------------------------------------------------
local PRESETS = {
	classic = {
		label = "Classic",
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
		-- HUD vitals share crimson accent (health + ammo match)
		ammo = { 255, 80, 110, 255 },
		health = { 255, 80, 110, 255 },
		healthLow = { 255, 45, 70, 255 },
		armor = { 200, 150, 165, 255 },
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
		ammo = { 100, 220, 255, 255 },
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
		ammo = { 120, 255, 140, 255 },
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
		ammo = { 255, 180, 60, 255 },
		health = { 255, 180, 60, 255 },
		healthLow = { 255, 60, 40, 255 },
		armor = { 210, 170, 130, 255 },
	},
}

local DENSITY = {
	compact = { id = "compact", pad = 8,  row = 36, title = 20, label = 13, small = 11, hud = 0.88, bar = 3 },
	comfort = { id = "comfort", pad = 14, row = 46, title = 26, label = 15, small = 12, hud = 1.0,  bar = 4 },
	large   = { id = "large",   pad = 20, row = 56, title = 34, label = 18, small = 15, hud = 1.18, bar = 5 },
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
		-- HUD vitals share accent — health + ammo identical, armor muted
		T.health = T.crimsonHot
		T.ammo = T.crimsonHot
		T.healthLow = Color(
			math.min(255, T.crimson.r + 40),
			math.max(0, math.floor(T.crimson.g * 0.4)),
			math.max(0, math.floor(T.crimson.b * 0.45)),
			255
		)
		T.armor = Color(
			math.min(255, math.floor(T.crimsonHot.r * 0.85 + 40)),
			math.min(255, math.floor(T.crimsonHot.g * 0.7 + 50)),
			math.min(255, math.floor(T.crimsonHot.b * 0.75 + 50)),
			255
		)
	end

	F.Theme = T
	-- Menus + HUD vitals read ThemeLive each paint; fire for listeners
	hook.Run("VRMod_CubeThemeChanged", T)
	return T
end

function F.DensityId()
	local d = string.lower(cv_density:GetString() or "comfort")
	if not DENSITY[d] then d = "comfort" end
	return d
end

function F.Density()
	return DENSITY[F.DensityId()] or DENSITY.comfort
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

------------------------------------------------------------------------
-- Density-aware fonts (CreateFont same names → resize)
------------------------------------------------------------------------
local fontsDensityId = nil

function F.RefreshFonts()
	local d = F.Density()
	-- Prefer faces that don't emit FreeType "bitmap.width is 0 for ch:32" on Linux
	local faces = { "Roboto", "Arial", "Tahoma", "Verdana", "Trebuchet MS", "DejaVu Sans", "Liberation Sans" }
	if system.IsLinux and system.IsLinux() then
		faces = { "Liberation Sans", "DejaVu Sans", "FreeSans", "Arial", "Trebuchet MS", "Roboto" }
	end
	local specs = {
		CubeTitle = { size = math.max(12, d.title or 22), weight = 800, antialias = true, extended = true },
		CubeLabel = { size = math.max(10, d.label or 15), weight = 700, antialias = true, extended = true },
		CubeSmall = { size = math.max(9, d.small or 12), weight = 500, antialias = true, extended = true },
		CubeHuge  = { size = math.max(14, math.floor((d.title or 22) * 1.4 + 4)), weight = 900, antialias = true, extended = true },
	}
	for name, spec in pairs(specs) do
		local ok = false
		for _, face in ipairs(faces) do
			spec.font = face
			ok = pcall(surface.CreateFont, name, spec)
			if ok then break end
		end
		if not ok then
			spec.font = "Trebuchet MS"
			pcall(surface.CreateFont, name, spec)
		end
	end
	fontsDensityId = d.id
	-- Sync legacy theme font helper
	if vrmod.cube then vrmod.cube._fontsDensityId = d.id end
	hook.Run("VRMod_CubeDensityChanged", d)
	return d
end

-- Short aliases used by menus (never pass these to surface.SetFont raw)
local FONT_ALIAS = {
	title = "CubeTitle",
	label = "CubeLabel",
	small = "CubeSmall",
	huge = "CubeHuge",
	CubeTitle = "CubeTitle",
	CubeLabel = "CubeLabel",
	CubeSmall = "CubeSmall",
	CubeHuge = "CubeHuge",
}
local FONT_ENGINE = {
	CubeTitle = "DermaLarge",
	CubeLabel = "DermaDefaultBold",
	CubeSmall = "DermaDefault",
	CubeHuge = "DermaLarge",
}

function F.Font(name)
	local id = F.DensityId()
	if fontsDensityId ~= id then F.RefreshFonts() end
	if not name or name == "" then return "DermaDefault" end
	-- Resolve alias first so we never SetFont("label") / SetFont("title")
	local resolved = FONT_ALIAS[name] or FONT_ALIAS[string.lower(tostring(name))] or name
	local ok, w = pcall(function()
		surface.SetFont(resolved)
		return surface.GetTextSize("W")
	end)
	if ok and w and w > 0 then return resolved end
	return FONT_ENGINE[resolved] or "DermaDefault"
end

function F.ApplyDensity(id)
	id = string.lower(tostring(id or "comfort"))
	if not DENSITY[id] then id = "comfort" end
	cv_density:SetString(id)
	F.RefreshFonts()
	F.RefreshTheme()
	if vrmod.RefreshHUD then vrmod.RefreshHUD() end
	return id
end

-- Initial + live refresh
F.RefreshTheme()
timer.Simple(0, function()
	if F.RefreshFonts then F.RefreshFonts() end
end)
cvars.AddChangeCallback("vrmod_cube_preset", function() F.RefreshTheme() end, "cube_fw")
cvars.AddChangeCallback("vrmod_cube_accent", function() F.RefreshTheme() end, "cube_fw")
cvars.AddChangeCallback("vrmod_cube_glass", function() F.RefreshTheme() end, "cube_fw")
cvars.AddChangeCallback("vrmod_cube_density", function(_, _, new)
	if F.RefreshFonts then F.RefreshFonts() end
	if F.RefreshTheme then F.RefreshTheme() end
	if vrmod.RefreshHUD then vrmod.RefreshHUD() end
	if vrmod.logger then
		vrmod.logger.Info("[cube] density → %s", tostring(new))
	end
end, "cube_fw_density")

------------------------------------------------------------------------
-- Layout metrics
------------------------------------------------------------------------
function F.Metrics()
	local d = F.Density()
	return {
		id = d.id,
		pad = d.pad,
		row = d.row,
		gap = math.floor(d.pad * 0.5),
		headerH = d.title + d.pad + 10,
		footerH = d.small + d.pad,
		hudScale = d.hud,
		title = d.title,
		label = d.label,
		small = d.small,
		bar = d.bar or 4,
	}
end

------------------------------------------------------------------------
-- Drawing primitives (Crimson chrome)
------------------------------------------------------------------------
function F.DrawChrome(x, y, w, h, title, opts)
	opts = opts or {}
	local T = F.ThemeLive()
	local M = F.Metrics()
	if F.Font then F.Font("CubeTitle") end
	local barH = opts.barH or M.bar
	local headerH = opts.headerH or M.headerH
	local pad = opts.pad or M.pad
	surface.SetDrawColor(T.bg)
	surface.DrawRect(x, y, w, h)
	surface.SetDrawColor(T.crimson)
	surface.DrawRect(x, y, w, barH)
	surface.SetDrawColor(T.bgGlass)
	surface.DrawRect(x, y + barH, w, math.max(0, headerH - barH))
	surface.SetDrawColor(T.crimsonDim)
	surface.DrawOutlinedRect(x, y, w, h, 2)
	if title and title ~= "" then
		local font = (F.Font and F.Font("CubeTitle")) or "DermaLarge"
		draw.SimpleText(title, font, x + pad, y + math.floor(barH + 4), T.crimson, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		if opts.subtitle and opts.subtitle ~= "" then
			local sf = (F.Font and F.Font("CubeSmall")) or "DermaDefault"
			draw.SimpleText(opts.subtitle, sf, x + w - pad, y + math.floor(barH + 8), T.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
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

--- Geometric chevron (no unicode tofu boxes). dir: left|right|up|down
function F.DrawChevron(cx, cy, size, dir, col)
	dir = string.lower(tostring(dir or "right"))
	size = math.max(6, tonumber(size) or 12)
	local c = col or Color(255, 240, 244, 255)
	local s = size * 0.5
	local poly
	if dir == "left" then
		poly = {
			{ x = cx + s * 0.55, y = cy - s },
			{ x = cx - s * 0.75, y = cy },
			{ x = cx + s * 0.55, y = cy + s },
		}
	elseif dir == "up" then
		poly = {
			{ x = cx, y = cy - s * 0.75 },
			{ x = cx + s, y = cy + s * 0.55 },
			{ x = cx - s, y = cy + s * 0.55 },
		}
	elseif dir == "down" then
		poly = {
			{ x = cx - s, y = cy - s * 0.55 },
			{ x = cx + s, y = cy - s * 0.55 },
			{ x = cx, y = cy + s * 0.75 },
		}
	else
		poly = {
			{ x = cx - s * 0.55, y = cy - s },
			{ x = cx + s * 0.75, y = cy },
			{ x = cx - s * 0.55, y = cy + s },
		}
	end
	draw.NoTexture()
	surface.SetDrawColor(c.r, c.g, c.b, c.a or 255)
	surface.DrawPoly(poly)
end

--- Arrow button with drawn chevron (not unicode). dir: left|right|up|down
function F.DrawArrowBtn(x, y, w, h, dir, hovered, enabled)
	local T = F.ThemeLive()
	if enabled == false then
		surface.SetDrawColor(T.btnDim or T.btn)
	elseif hovered then
		surface.SetDrawColor(T.btnHover or T.btn)
	else
		surface.SetDrawColor(T.btn or T.panel)
	end
	surface.DrawRect(x, y, w, h)
	surface.SetDrawColor(hovered and (T.crimsonHot or T.crimson) or (T.crimsonDim or T.crimson))
	surface.DrawOutlinedRect(x, y, w, h, hovered and 3 or 2)
	if hovered then
		surface.SetDrawColor(T.crimson)
		if dir == "left" then
			surface.DrawRect(x, y, 5, h)
		elseif dir == "right" then
			surface.DrawRect(x + w - 5, y, 5, h)
		elseif dir == "up" then
			surface.DrawRect(x, y, w, 4)
		else
			surface.DrawRect(x, y + h - 4, w, 4)
		end
	end
	local col = T.text or color_white
	if enabled == false then
		col = T.muted or Color(col.r, col.g, col.b, 120)
	end
	F.DrawChevron(x + w * 0.5, y + h * 0.5, math.min(w, h) * 0.34, dir, col)
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
