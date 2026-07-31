if SERVER then return end
-- =============================================================================
-- Cube UI theme — shared palette + fonts (safe CreateFont + fallbacks)
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

-- Fallbacks if CreateFont fails or file loads before surface is ready
local FONT_FALLBACK = {
	CubeTitle = "DermaLarge",
	CubeLabel = "DermaDefaultBold",
	CubeSmall = "DermaDefault",
	CubeHuge = "DermaLarge",
}

local fontsReady = false

local function EnsureCubeFonts()
	if fontsReady then return end
	-- Tahoma is often missing on Linux → silent bad font; prefer cross-platform faces
	local face = "Roboto"
	if system.IsLinux and system.IsLinux() then
		face = "DejaVu Sans"
	end
	local specs = {
		CubeTitle = { font = face, size = 28, weight = 800, antialias = true, extended = true },
		CubeLabel = { font = face, size = 16, weight = 700, antialias = true, extended = true },
		CubeSmall = { font = face, size = 13, weight = 500, antialias = true, extended = true },
		CubeHuge = { font = face, size = 36, weight = 900, antialias = true, extended = true },
	}
	for name, spec in pairs(specs) do
		-- Try preferred face, then Arial, then Trebuchet MS
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
	fontsReady = true
end

--- Resolve a Cube font name; never returns an unregistered font
function vrmod.cube.Font(name)
	EnsureCubeFonts()
	if not name then return "DermaDefault" end
	-- surface.SetFont does not error on missing fonts; measure width instead
	local ok, w = pcall(function()
		surface.SetFont(name)
		return surface.GetTextSize("W")
	end)
	if ok and w and w > 0 then return name end
	return FONT_FALLBACK[name] or "DermaDefault"
end

function vrmod.cube.DrawPanel(x, y, w, h, title)
	EnsureCubeFonts()
	local T = vrmod.cube.Theme
	surface.SetDrawColor(T.bg)
	surface.DrawRect(x, y, w, h)
	surface.SetDrawColor(T.crimson)
	surface.DrawRect(x, y, w, 4)
	surface.DrawOutlinedRect(x, y, w, h, 2)
	if title and title ~= "" then
		draw.SimpleText(title, vrmod.cube.Font("CubeTitle"), x + 16, y + 14, T.crimson, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	end
end

function vrmod.cube.DrawButton(x, y, w, h, label, hovered, enabled)
	EnsureCubeFonts()
	local T = vrmod.cube.Theme
	if enabled == false then
		surface.SetDrawColor(T.btnDim)
	elseif hovered then
		surface.SetDrawColor(T.btnHover)
	else
		surface.SetDrawColor(T.btn)
	end
	surface.DrawRect(x, y, w, h)
	surface.SetDrawColor(hovered and T.crimsonHot or T.crimsonDim)
	surface.DrawOutlinedRect(x, y, w, h, hovered and 3 or 2)
	if hovered then
		surface.SetDrawColor(T.crimson)
		surface.DrawRect(x, y, 5, h)
	end
	draw.SimpleText(tostring(label or ""), vrmod.cube.Font("CubeLabel"), x + w * 0.5, y + h * 0.5, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

function vrmod.cube.DrawButtonMultiline(x, y, w, h, label, hovered, enabled)
	EnsureCubeFonts()
	local T = vrmod.cube.Theme
	if enabled == false then
		surface.SetDrawColor(T.btnDim)
	elseif hovered then
		surface.SetDrawColor(T.btnHover)
	else
		surface.SetDrawColor(T.btn)
	end
	surface.DrawRect(x, y, w, h)
	surface.SetDrawColor(hovered and T.crimsonHot or T.crimsonDim)
	surface.DrawOutlinedRect(x, y, w, h, hovered and 3 or 2)
	if hovered then
		surface.SetDrawColor(T.crimson)
		surface.DrawRect(x, y, 4, h)
	end
	label = tostring(label or "")
	local words = string.Explode(" ", label, false)
	local lines = {}
	if #words <= 1 then
		lines = { label }
	else
		local mid = math.ceil(#words / 2)
		lines[1] = table.concat(words, " ", 1, mid)
		lines[2] = table.concat(words, " ", mid + 1)
	end
	local lineH = 16
	local startY = y + h * 0.5 - (#lines * lineH) * 0.5 + 2
	local font = vrmod.cube.Font("CubeLabel")
	for i, line in ipairs(lines) do
		draw.SimpleText(line, font, x + w * 0.5, startY + (i - 1) * lineH, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	end
end

-- Create ASAP + again when client is fully up
EnsureCubeFonts()
hook.Add("InitPostEntity", "vrmod_cube_fonts", function()
	EnsureCubeFonts()
	if vrmod.cube.RefreshTheme then vrmod.cube.RefreshTheme() end
end)
hook.Add("OnScreenSizeChanged", "vrmod_cube_fonts", function()
	fontsReady = false
	EnsureCubeFonts()
end)

-- Draw helpers prefer framework Theme when live
function vrmod.cube.T()
	if vrmod.cube.ThemeLive then return vrmod.cube.ThemeLive() end
	return vrmod.cube.Theme
end
