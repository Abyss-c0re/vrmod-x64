if SERVER then return end
-- =============================================================================
-- Cube UI theme — shared palette + fonts (safe CreateFont + fallbacks)
-- Framework (cl_cube_framework) owns density-scaled Font/RefreshFonts when present.
-- =============================================================================
vrmod = vrmod or {}
vrmod.cube = vrmod.cube or {}

-- Static fallback only if Crimson Framework has not claimed Theme yet
if not (vrmod.cube.RefreshTheme and vrmod.cube.Framework) then
	vrmod.cube.Theme = {
		bg = Color(12, 6, 10, 245),
		bgGlass = Color(22, 10, 16, 230),
		panel = Color(36, 12, 18, 240),
		btn = Color(55, 14, 24, 250),
		btnHover = Color(100, 22, 38, 255),
		btnDim = Color(30, 10, 16, 220),
		crimson = Color(196, 30, 58, 255),
		crimsonHot = Color(255, 70, 100, 255),
		crimsonDim = Color(120, 20, 40, 220),
		text = Color(255, 240, 244, 255),
		muted = Color(200, 150, 165, 230),
		ok = Color(90, 220, 150, 255),
		warn = Color(255, 200, 100, 255),
		accentLine = Color(196, 30, 58, 255),
	}
end

local FONT_FALLBACK = {
	CubeTitle = "DermaLarge",
	CubeLabel = "DermaDefaultBold",
	CubeSmall = "DermaDefault",
	CubeHuge = "DermaLarge",
	title = "DermaLarge",
	label = "DermaDefaultBold",
	small = "DermaDefault",
	huge = "DermaLarge",
}
local FONT_ALIAS = {
	title = "CubeTitle",
	label = "CubeLabel",
	small = "CubeSmall",
	huge = "CubeHuge",
}

--- Always available: prefer framework density fonts, else static CreateFont
local function EnsureCubeFonts()
	if vrmod.cube.RefreshFonts then
		pcall(vrmod.cube.RefreshFonts)
		return
	end
	local face = "Roboto"
	if system.IsLinux and system.IsLinux() then face = "DejaVu Sans" end
	local specs = {
		CubeTitle = { font = face, size = 26, weight = 800, antialias = true, extended = true },
		CubeLabel = { font = face, size = 15, weight = 700, antialias = true, extended = true },
		CubeSmall = { font = face, size = 12, weight = 500, antialias = true, extended = true },
		CubeHuge = { font = face, size = 36, weight = 900, antialias = true, extended = true },
	}
	for name, spec in pairs(specs) do
		local ok = pcall(surface.CreateFont, name, spec)
		if not ok then
			spec.font = "Arial"
			ok = pcall(surface.CreateFont, name, spec)
		end
		if not ok then
			spec.font = "Trebuchet MS"
			pcall(surface.CreateFont, name, spec)
		end
	end
end

-- Only install Font if framework did not already (density-aware Font in cl_cube_framework)
if not vrmod.cube.Font then
	function vrmod.cube.Font(name)
		EnsureCubeFonts()
		if not name or name == "" then return "DermaDefault" end
		local resolved = FONT_ALIAS[name] or FONT_ALIAS[string.lower(tostring(name))] or name
		local ok, w = pcall(function()
			surface.SetFont(resolved)
			return surface.GetTextSize("W")
		end)
		if ok and w and w > 0 then return resolved end
		return FONT_FALLBACK[resolved] or FONT_FALLBACK[name] or "DermaDefault"
	end
end

function vrmod.cube.DrawPanel(x, y, w, h, title)
	EnsureCubeFonts()
	local T = (vrmod.cube.ThemeLive and vrmod.cube.ThemeLive()) or vrmod.cube.Theme
	if not T then return end
	surface.SetDrawColor(T.bg)
	surface.DrawRect(x, y, w, h)
	surface.SetDrawColor(T.crimson or Color(196, 30, 58))
	surface.DrawRect(x, y, w, 4)
	surface.DrawOutlinedRect(x, y, w, h, 2)
	if title and title ~= "" then
		draw.SimpleText(title, vrmod.cube.Font("CubeTitle"), x + 16, y + 14, T.crimson, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	end
end

function vrmod.cube.DrawButton(x, y, w, h, label, hovered, enabled)
	EnsureCubeFonts()
	local T = (vrmod.cube.ThemeLive and vrmod.cube.ThemeLive()) or vrmod.cube.Theme
	if not T then return end
	if enabled == false then
		surface.SetDrawColor(T.btnDim or T.btn)
	elseif hovered then
		surface.SetDrawColor(T.btnHover or T.btn)
	else
		surface.SetDrawColor(T.btn)
	end
	surface.DrawRect(x, y, w, h)
	surface.SetDrawColor(hovered and (T.crimsonHot or T.crimson) or (T.crimsonDim or T.crimson))
	surface.DrawOutlinedRect(x, y, w, h, hovered and 3 or 2)
	if hovered then
		surface.SetDrawColor(T.crimson)
		surface.DrawRect(x, y, 5, h)
	end
	draw.SimpleText(tostring(label or ""), vrmod.cube.Font("CubeLabel"), x + w * 0.5, y + h * 0.5, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- Cache split labels — string.Explode + concat every paint caused CUtlRBTree overflow
-- under long VR sessions (DrawText spam from QM PreRender).
local _mlCache = {}
local function SplitLabel2(label)
	local c = _mlCache[label]
	if c then return c end
	local words = string.Explode(" ", label, false)
	if #words <= 1 then
		c = { label }
	else
		local mid = math.ceil(#words / 2)
		c = {
			table.concat(words, " ", 1, mid),
			table.concat(words, " ", mid + 1),
		}
	end
	-- Cap cache size (avoid unbounded string tables)
	local n = 0
	for _ in pairs(_mlCache) do
		n = n + 1
		if n > 128 then
			_mlCache = {}
			break
		end
	end
	_mlCache[label] = c
	return c
end

function vrmod.cube.DrawButtonMultiline(x, y, w, h, label, hovered, enabled)
	local T = (vrmod.cube.ThemeLive and vrmod.cube.ThemeLive()) or vrmod.cube.Theme
	if not T then return end
	if enabled == false then
		surface.SetDrawColor(T.btnDim or T.btn)
	elseif hovered then
		surface.SetDrawColor(T.btnHover or T.btn)
	else
		surface.SetDrawColor(T.btn)
	end
	surface.DrawRect(x, y, w, h)
	surface.SetDrawColor(hovered and (T.crimsonHot or T.crimson) or (T.crimsonDim or T.crimson))
	surface.DrawOutlinedRect(x, y, w, h, hovered and 3 or 2)
	if hovered then
		surface.SetDrawColor(T.crimson)
		surface.DrawRect(x, y, 4, h)
	end
	label = tostring(label or "")
	local lines = SplitLabel2(label)
	local lineH = 16
	local startY = y + h * 0.5 - (#lines * lineH) * 0.5 + 2
	-- Prefer engine font for RT paint (custom fonts thrash glyph trees under VR)
	local font = "DermaDefaultBold"
	if vrmod.cube.Font then
		font = vrmod.cube.Font("CubeLabel") or font
	end
	for i = 1, #lines do
		draw.SimpleText(lines[i], font, x + w * 0.5, startY + (i - 1) * lineH, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	end
end

function vrmod.cube.T()
	if vrmod.cube.ThemeLive then return vrmod.cube.ThemeLive() end
	return vrmod.cube.Theme
end

-- Create ASAP + again when client is fully up
EnsureCubeFonts()
hook.Add("InitPostEntity", "vrmod_cube_fonts", function()
	EnsureCubeFonts()
	if vrmod.cube.RefreshTheme then vrmod.cube.RefreshTheme() end
end)
hook.Add("OnScreenSizeChanged", "vrmod_cube_fonts", function()
	EnsureCubeFonts()
end)
