if SERVER then return end
-- =============================================================================
-- Cube UI theme — shared palette for menus worth dying for
-- Used by: quickmenu, weapon select, height, settings surfaces
-- =============================================================================
vrmod = vrmod or {}
vrmod.cube = vrmod.cube or {}

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

surface.CreateFont("CubeTitle", {
	font = "Tahoma",
	size = 28,
	weight = 800,
	antialias = true,
})
surface.CreateFont("CubeLabel", {
	font = "Tahoma",
	size = 16,
	weight = 700,
	antialias = true,
})
surface.CreateFont("CubeSmall", {
	font = "Tahoma",
	size = 13,
	weight = 500,
	antialias = true,
})
surface.CreateFont("CubeHuge", {
	font = "Tahoma",
	size = 36,
	weight = 900,
	antialias = true,
})

function vrmod.cube.DrawPanel(x, y, w, h, title)
	local T = vrmod.cube.Theme
	surface.SetDrawColor(T.bg)
	surface.DrawRect(x, y, w, h)
	surface.SetDrawColor(T.crimson)
	surface.DrawRect(x, y, w, 4)
	surface.DrawOutlinedRect(x, y, w, h, 2)
	if title and title ~= "" then
		draw.SimpleText(title, "CubeTitle", x + 16, y + 14, T.crimson, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	end
end

function vrmod.cube.DrawButton(x, y, w, h, label, hovered, enabled)
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
	draw.SimpleText(tostring(label or ""), "CubeLabel", x + w * 0.5, y + h * 0.5, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

--- Word-wrap label into button
function vrmod.cube.DrawButtonMultiline(x, y, w, h, label, hovered, enabled)
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
	for i, line in ipairs(lines) do
		draw.SimpleText(line, "CubeLabel", x + w * 0.5, startY + (i - 1) * lineH, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	end
end
