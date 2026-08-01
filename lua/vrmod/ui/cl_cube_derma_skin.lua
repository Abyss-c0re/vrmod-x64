if SERVER then return end
-- =============================================================================
-- Cube Derma Skin — ThemeLive chrome for Spawn / Context / VGUI
--
-- VR-ONLY: never restyle desktop sandbox menus. Apply on VR session only;
-- restore Default skin + stock layout on VRMod_Exit (no non-VR regression).
-- =============================================================================

vrmod = vrmod or {}
vrmod.cube = vrmod.cube or {}

local SKIN_NAME = "Cube"
local DEFAULT_SKIN = "Default"
local cv_enable = CreateClientConVar("vrmod_cube_spawnmenu", "1", true, FCVAR_ARCHIVE,
	"Theme sandbox spawn/context menus with Cube UI while in VR (0=off, 1=on)")

--- True only during an active VR session when theming is enabled
function vrmod.cube.ShouldThemeDerma()
	if not cv_enable:GetBool() then return false end
	return g_VR and g_VR.active and true or false
end

local function shouldTheme()
	return vrmod.cube.ShouldThemeDerma()
end

local function T()
	if vrmod.cube.ThemeLive then return vrmod.cube.ThemeLive() end
	return vrmod.cube.Theme or {
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
	}
end

local function fill(col)
	surface.SetDrawColor(col.r, col.g, col.b, col.a or 255)
end

local function rect(x, y, w, h, col)
	fill(col)
	surface.DrawRect(x, y, w, h)
end

local function outline(x, y, w, h, col, thick)
	fill(col)
	surface.DrawOutlinedRect(x, y, w, h, thick or 2)
end

local function slot(x, y, w, h, hovered, selected, enabled)
	local th = T()
	if enabled == false then
		rect(x, y, w, h, th.btnDim or th.btn)
	elseif selected or hovered then
		rect(x, y, w, h, th.btnHover or th.btn)
	else
		rect(x, y, w, h, th.btn or th.panel)
	end
	outline(x, y, w, h, (selected or hovered) and (th.crimsonHot or th.crimson) or (th.crimsonDim or th.crimson), (selected or hovered) and 3 or 2)
	if hovered or selected then
		rect(x, y, 4, h, th.crimson)
	end
end

------------------------------------------------------------------------
-- Build skin (inherit Default for tex + any unhandled paints)
------------------------------------------------------------------------
local function buildSkin()
	local base = derma.GetNamedSkin("Default")
	local SKIN = {}
	if base then
		setmetatable(SKIN, { __index = base })
		-- shallow-copy palette fields we replace so Default is not mutated
		SKIN.Colours = table.Copy(base.Colours or {})
	else
		SKIN.Colours = {}
	end

	SKIN.PrintName = "Cube"
	SKIN.Author = "VRMod Cube Experience"
	SKIN.DermaVersion = 1
	SKIN.GwenTexture = base and base.GwenTexture or nil
	SKIN.tex = base and base.tex or {}

	local th = T()
	SKIN.bg_color = th.bg
	SKIN.bg_color_sleep = th.bgGlass or th.bg
	SKIN.bg_color_dark = th.panel
	SKIN.bg_color_bright = th.btnHover
	SKIN.frame_border = th.crimsonDim or th.crimson
	SKIN.control_color = th.btn
	SKIN.control_color_highlight = th.btnHover
	SKIN.control_color_active = th.crimson
	SKIN.control_color_bright = th.crimsonHot
	SKIN.control_color_dark = th.btnDim
	SKIN.bg_alt1 = th.panel
	SKIN.bg_alt2 = th.bgGlass or th.panel
	SKIN.listview_hover = th.btnHover
	SKIN.listview_selected = th.crimson
	SKIN.text_bright = th.text
	SKIN.text_normal = th.muted or th.text
	SKIN.text_dark = th.bg
	SKIN.text_highlight = th.crimsonHot
	SKIN.colPropertySheet = th.panel
	SKIN.colTab = th.btn
	SKIN.colTabInactive = th.btnDim
	SKIN.colTabShadow = Color(0, 0, 0, 180)
	SKIN.colTabText = th.text
	SKIN.colTabTextInactive = th.muted
	SKIN.colCollapsibleCategory = th.panel
	SKIN.colCategoryText = th.text
	SKIN.colCategoryTextInactive = th.muted
	SKIN.colTextEntryBG = th.bgGlass or th.panel
	SKIN.colTextEntryBorder = th.crimsonDim
	SKIN.colTextEntryText = th.text
	SKIN.colTextEntryTextHighlight = th.crimsonHot
	SKIN.colTextEntryTextCursor = th.crimson
	SKIN.colTextEntryTextPlaceholder = th.muted
	SKIN.colMenuBG = th.bg
	SKIN.colMenuBorder = th.crimsonDim
	SKIN.colButtonText = th.text
	SKIN.colButtonTextDisabled = th.muted
	SKIN.colButtonBorder = th.crimsonDim
	SKIN.fontFrame = "DermaDefaultBold"
	SKIN.fontTab = "DermaDefaultBold"
	SKIN.fontCategoryHeader = "DermaDefaultBold"

	-- Scheme colours used by DLabel / tabs / tree
	local function setCol(path, col)
		local t = SKIN.Colours
		for i = 1, #path - 1 do
			t[path[i]] = t[path[i]] or {}
			t = t[path[i]]
		end
		t[path[#path]] = col
	end

	setCol({ "Window", "TitleActive" }, th.crimson)
	setCol({ "Window", "TitleInactive" }, th.muted)
	setCol({ "Button", "Normal" }, th.text)
	setCol({ "Button", "Hover" }, th.text)
	setCol({ "Button", "Down" }, th.text)
	setCol({ "Button", "Disabled" }, th.muted)
	setCol({ "Tab", "Active", "Normal" }, th.text)
	setCol({ "Tab", "Active", "Hover" }, th.text)
	setCol({ "Tab", "Active", "Down" }, th.text)
	setCol({ "Tab", "Active", "Disabled" }, th.muted)
	setCol({ "Tab", "Inactive", "Normal" }, th.muted)
	setCol({ "Tab", "Inactive", "Hover" }, th.text)
	setCol({ "Tab", "Inactive", "Down" }, th.text)
	setCol({ "Tab", "Inactive", "Disabled" }, th.muted)
	setCol({ "Label", "Default" }, th.text)
	setCol({ "Label", "Bright" }, th.text)
	setCol({ "Label", "Dark" }, th.muted)
	setCol({ "Label", "Highlight" }, th.crimsonHot)
	setCol({ "Tree", "Lines" }, th.crimsonDim)
	setCol({ "Tree", "Normal" }, th.text)
	setCol({ "Tree", "Hover" }, th.crimsonHot)
	setCol({ "Tree", "Selected" }, th.crimson)
	setCol({ "Category", "Header" }, th.crimson)
	setCol({ "Category", "Header_Closed" }, th.muted)
	setCol({ "Category", "Line", "Text" }, th.text)
	setCol({ "Category", "Line", "Text_Hover" }, th.crimsonHot)
	setCol({ "Category", "Line", "Text_Selected" }, th.text)
	setCol({ "Category", "Line", "Button" }, th.btn)
	setCol({ "Category", "Line", "Button_Hover" }, th.btnHover)
	setCol({ "Category", "Line", "Button_Selected" }, th.crimson)
	setCol({ "Category", "LineAlt", "Text" }, th.muted)
	setCol({ "Category", "LineAlt", "Text_Hover" }, th.text)
	setCol({ "Category", "LineAlt", "Text_Selected" }, th.text)
	setCol({ "Category", "LineAlt", "Button" }, th.panel)
	setCol({ "Category", "LineAlt", "Button_Hover" }, th.btnHover)
	setCol({ "Category", "LineAlt", "Button_Selected" }, th.crimson)
	SKIN.Colours.TooltipText = th.text

	local function glassCol(th, a)
		local c = th.bgGlass or th.panel or th.bg or Color(22, 10, 16, 200)
		return Color(c.r, c.g, c.b, a or math.min(c.a or 200, 180))
	end

	function SKIN:PaintPanel(panel, w, h)
		if panel.m_bBackground == false then return end
		local th = T()
		-- Prefer translucent glass (spawn left tree was a solid brick)
		local bg = panel.m_bgColor
		if bg and bg.a and bg.a > 200 and bg.r > 200 then
			-- stock light-grey DTree — replace with glass
			bg = glassCol(th, 140)
		end
		rect(0, 0, w, h, bg or glassCol(th, 150))
	end

	function SKIN:PaintShadow(panel, w, h)
		rect(0, 0, w, h, Color(0, 0, 0, 60))
	end

	function SKIN:PaintFrame(panel, w, h)
		local th = T()
		rect(0, 0, w, h, glassCol(th, 220))
		rect(0, 0, w, 4, th.crimson)
		rect(0, 4, w, 28, glassCol(th, 180))
		outline(0, 0, w, h, th.crimsonDim or th.crimson, 2)
	end

	function SKIN:PaintButton(panel, w, h)
		if panel.m_bBackground == false then return end
		local enabled = panel:IsEnabled()
		local hot = panel.Hovered or panel.Depressed or panel:IsSelected() or panel:GetToggle()
		local down = panel.Depressed or panel:IsSelected() or panel:GetToggle()
		slot(0, 0, w, h, hot, down, enabled)
	end

	function SKIN:PaintTree(panel, w, h)
		if panel.m_bBackground == false then return end
		local th = T()
		-- Translucent left rail — not opaque grey / solid panel brick
		local bg = panel.m_bgColor
		if not bg or (bg.r and bg.r > 180) then
			bg = glassCol(th, 130)
		else
			bg = Color(bg.r, bg.g, bg.b, math.min(bg.a or 255, 150))
		end
		rect(0, 0, w, h, bg)
		outline(0, 0, w, h, th.crimsonDim or th.crimson, 1)
	end

	function SKIN:PaintCheckBox(panel, w, h)
		local th = T()
		local s = math.min(w, h)
		local x, y = math.floor((w - s) * 0.5), math.floor((h - s) * 0.5)
		slot(x, y, s, s, panel.Hovered, panel:GetChecked(), panel:IsEnabled())
		if panel:GetChecked() then
			fill(th.ok or th.crimson)
			surface.DrawRect(x + 4, y + 4, s - 8, s - 8)
		end
	end

	function SKIN:PaintRadioButton(panel, w, h)
		self:PaintCheckBox(panel, w, h)
	end

	function SKIN:PaintExpandButton(panel, w, h)
		local th = T()
		slot(0, 0, w, h, panel.Hovered, panel:GetExpanded(), true)
		draw.SimpleText(panel:GetExpanded() and "−" or "+", "DermaDefaultBold",
			w * 0.5, h * 0.5, th.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	function SKIN:PaintTextEntry(panel, w, h)
		local th = T()
		if panel.m_bBackground ~= false then
			rect(0, 0, w, h, th.bgGlass or th.panel)
			outline(0, 0, w, h, panel:HasFocus() and (th.crimsonHot or th.crimson) or (th.crimsonDim or th.crimson), panel:HasFocus() and 2 or 1)
		end
		if panel.GetPlaceholderText and panel:GetPlaceholderText() and panel:GetPlaceholderText():Trim() ~= ""
			and (not panel:GetText() or panel:GetText() == "") then
			local str = panel:GetPlaceholderText()
			if string.sub(str, 1, 1) == "#" then str = string.sub(str, 2) end
			str = language.GetPhrase(str)
			local old = panel:GetText()
			panel:SetText(str)
			panel:DrawTextEntryText(th.muted or th.text, th.crimsonHot or th.crimson, th.crimson)
			panel:SetText(old)
			return
		end
		panel:DrawTextEntryText(th.text, th.crimsonHot or th.crimson, th.crimson)
	end

	function SKIN:PaintMenu(panel, w, h)
		local th = T()
		rect(0, 0, w, h, th.bg)
		outline(0, 0, w, h, th.crimsonDim or th.crimson, 2)
	end

	function SKIN:PaintMenuSpacer(panel, w, h)
		local th = T()
		rect(0, 0, w, h, th.crimsonDim or Color(0, 0, 0, 100))
	end

	function SKIN:PaintMenuOption(panel, w, h)
		local th = T()
		if panel.m_bBackground and not panel:IsEnabled() then
			rect(0, 0, w, h, th.btnDim)
		end
		if panel.m_bBackground and panel:IsEnabled() and (panel.Hovered or panel.Highlight) then
			rect(0, 0, w, h, th.btnHover)
			rect(0, 0, 4, h, th.crimson)
		end
		if panel:GetChecked() then
			draw.SimpleText("✓", "DermaDefaultBold", 10, h * 0.5, th.ok or th.crimson, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end

	function SKIN:PaintMenuRightArrow(panel, w, h)
		local th = T()
		draw.SimpleText("▸", "DermaDefaultBold", w * 0.5, h * 0.5, th.muted or th.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	function SKIN:PaintPropertySheet(panel, w, h)
		local th = T()
		local active = panel:GetActiveTab()
		local offset = active and (active:GetTall() - 4) or 0
		rect(0, offset, w, h - offset, th.panel or th.bg)
		outline(0, offset, w, h - offset, th.crimsonDim or th.crimson, 2)
		if offset > 0 then
			rect(0, offset, w, 3, th.crimson)
		end
	end

	function SKIN:PaintTab(panel, w, h)
		if panel:IsActive() then
			return self:PaintActiveTab(panel, w, h)
		end
		local th = T()
		rect(0, 4, w, h - 4, th.btnDim or th.btn)
		outline(0, 4, w, h - 4, th.crimsonDim or th.crimson, 1)
	end

	function SKIN:PaintActiveTab(panel, w, h)
		local th = T()
		rect(0, 0, w, h, th.btnHover or th.btn)
		rect(0, 0, w, 3, th.crimson)
		outline(0, 0, w, h, th.crimsonHot or th.crimson, 2)
	end

	function SKIN:PaintWindowCloseButton(panel, w, h)
		if panel.m_bBackground == false then return end
		slot(0, 0, w, h, panel.Hovered, panel.Depressed, panel:IsEnabled())
		draw.SimpleText("X", "DermaDefaultBold", w * 0.5, h * 0.5, T().text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	function SKIN:PaintWindowMinimizeButton(panel, w, h)
		if panel.m_bBackground == false then return end
		slot(0, 0, w, h, panel.Hovered, panel.Depressed, panel:IsEnabled())
		draw.SimpleText("–", "DermaDefaultBold", w * 0.5, h * 0.5, T().text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	function SKIN:PaintWindowMaximizeButton(panel, w, h)
		if panel.m_bBackground == false then return end
		slot(0, 0, w, h, panel.Hovered, panel.Depressed, panel:IsEnabled())
		draw.SimpleText("□", "DermaDefaultBold", w * 0.5, h * 0.5, T().text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	function SKIN:PaintVScrollBar(panel, w, h)
		local th = T()
		rect(0, 0, w, h, th.bgGlass or th.panel)
	end

	function SKIN:PaintHScrollBar(panel, w, h)
		local th = T()
		rect(0, 0, w, h, th.bgGlass or th.panel)
	end

	function SKIN:PaintScrollBarGrip(panel, w, h)
		slot(0, 0, w, h, panel.Hovered, panel.Depressed, true)
	end

	function SKIN:PaintButtonDown(panel, w, h)
		slot(0, 0, w, h, panel.Hovered, panel.Depressed, panel:IsEnabled())
		draw.SimpleText("▼", "DermaDefault", w * 0.5, h * 0.5, T().text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	function SKIN:PaintButtonUp(panel, w, h)
		slot(0, 0, w, h, panel.Hovered, panel.Depressed, panel:IsEnabled())
		draw.SimpleText("▲", "DermaDefault", w * 0.5, h * 0.5, T().text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	function SKIN:PaintButtonLeft(panel, w, h)
		slot(0, 0, w, h, panel.Hovered, panel.Depressed, panel:IsEnabled())
		draw.SimpleText("◀", "DermaDefault", w * 0.5, h * 0.5, T().text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	function SKIN:PaintButtonRight(panel, w, h)
		slot(0, 0, w, h, panel.Hovered, panel.Depressed, panel:IsEnabled())
		draw.SimpleText("▶", "DermaDefault", w * 0.5, h * 0.5, T().text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	function SKIN:PaintComboDownArrow(panel, w, h)
		draw.SimpleText("▼", "DermaDefault", w * 0.5, h * 0.5, T().muted or T().text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	function SKIN:PaintComboBox(panel, w, h)
		if panel.m_bBackground == false then return end
		slot(0, 0, w, h, panel.Hovered or panel:IsMenuOpen(), false, panel:IsEnabled())
	end

	function SKIN:PaintListBox(panel, w, h)
		local th = T()
		rect(0, 0, w, h, th.bgGlass or th.panel)
		outline(0, 0, w, h, th.crimsonDim or th.crimson, 1)
	end

	function SKIN:PaintNumberUp(panel, w, h)
		self:PaintButtonUp(panel, w, h)
	end

	function SKIN:PaintNumberDown(panel, w, h)
		self:PaintButtonDown(panel, w, h)
	end

	function SKIN:PaintTreeNode(panel, w, h)
		-- lines only when selected/hovered; base may use tex
		if not panel.m_bDrawBackground then return end
		local th = T()
		if panel:IsSelected() then
			rect(0, 0, w, h, th.crimsonDim or th.btn)
		elseif panel.Hovered then
			rect(0, 0, w, h, th.btn)
		end
	end

	function SKIN:PaintTreeNodeButton(panel, w, h)
		local th = T()
		if panel:IsSelected() then
			rect(0, 0, w, h, th.btnHover)
			rect(0, 0, 4, h, th.crimson)
		elseif panel.Hovered then
			rect(0, 0, w, h, th.btn)
		end
	end

	function SKIN:PaintSelection(panel, w, h)
		local th = T()
		rect(0, 0, w, h, Color(th.crimson.r, th.crimson.g, th.crimson.b, 80))
		outline(0, 0, w, h, th.crimson, 1)
	end

	function SKIN:PaintSliderKnob(panel, w, h)
		slot(0, 0, w, h, panel.Hovered, panel.Depressed, panel:IsEnabled())
	end

	function SKIN:PaintNumSlider(panel, w, h)
		local th = T()
		rect(0, math.floor(h * 0.5) - 2, w, 4, th.btnDim or th.panel)
		rect(0, math.floor(h * 0.5) - 2, w * (panel:GetSlideX() or 0), 4, th.crimson)
	end

	function SKIN:PaintProgress(panel, w, h)
		local th = T()
		rect(0, 0, w, h, th.btnDim or th.panel)
		local frac = panel:GetFraction() or 0
		rect(0, 0, w * frac, h, th.crimson)
		outline(0, 0, w, h, th.crimsonDim or th.crimson, 1)
	end

	function SKIN:PaintCollapsibleCategory(panel, w, h)
		local th = T()
		rect(0, 0, w, 20, th.btn)
		rect(0, 0, 4, 20, th.crimson)
		if panel:GetExpanded() then
			rect(0, 20, w, h - 20, th.bgGlass or th.panel)
		end
		outline(0, 0, w, h, th.crimsonDim or th.crimson, 1)
	end

	function SKIN:PaintCategoryList(panel, w, h)
		local th = T()
		rect(0, 0, w, h, th.bgGlass or th.panel)
		outline(0, 0, w, h, th.crimsonDim or th.crimson, 1)
	end

	function SKIN:PaintCategoryButton(panel, w, h)
		local th = T()
		if panel:IsSelected() then
			rect(0, 0, w, h, th.btnHover)
			rect(0, 0, 4, h, th.crimson)
		elseif panel.Hovered then
			rect(0, 0, w, h, th.btn)
		elseif panel.AltLine then
			rect(0, 0, w, h, th.panel)
		end
	end

	function SKIN:PaintListViewLine(panel, w, h)
		local th = T()
		if panel:IsSelected() then
			rect(0, 0, w, h, th.btnHover)
			rect(0, 0, 4, h, th.crimson)
		elseif panel.Hovered then
			rect(0, 0, w, h, th.btn)
		elseif panel.m_bAlt then
			rect(0, 0, w, h, Color(th.panel.r, th.panel.g, th.panel.b, 120))
		end
	end

	function SKIN:PaintListView(panel, w, h)
		if panel.m_bBackground == false then return end
		local th = T()
		rect(0, 0, w, h, th.bgGlass or th.panel)
		outline(0, 0, w, h, th.crimsonDim or th.crimson, 1)
	end

	function SKIN:PaintTooltip(panel, w, h)
		local th = T()
		rect(0, 0, w, h, th.bg)
		outline(0, 0, w, h, th.crimson, 2)
	end

	function SKIN:PaintMenuBar(panel, w, h)
		local th = T()
		rect(0, 0, w, h, th.panel)
		rect(0, h - 2, w, 2, th.crimson)
	end

	derma.DefineSkin(SKIN_NAME, "Cube — spawn & VGUI", SKIN)
	return SKIN
end

local cubeSkin = nil

function vrmod.cube.RefreshDermaSkin()
	cubeSkin = buildSkin()
	return cubeSkin
end

function vrmod.cube.GetDermaSkinName()
	return SKIN_NAME
end

------------------------------------------------------------------------
-- Apply skin to panel tree (spawn creates children lazily) — VR only
------------------------------------------------------------------------
local function applySkinRecursive(panel, skinName, depth)
	if not IsValid(panel) or (depth or 0) > 40 then return end
	if panel.SetSkin then
		pcall(function() panel:SetSkin(skinName) end)
	end
	-- ApplySchemeSettings on every node is expensive — root + one level is enough
	if (depth or 0) <= 1 and panel.ApplySchemeSettings then
		pcall(function() panel:ApplySchemeSettings() end)
	end
	for _, child in ipairs(panel:GetChildren() or {}) do
		applySkinRecursive(child, skinName, (depth or 0) + 1)
	end
end

function vrmod.cube.ApplyDermaSkin(panel, force)
	-- Desktop must stay stock Default — no skin swap outside VR
	if not shouldTheme() then return end
	if not cubeSkin then vrmod.cube.RefreshDermaSkin() end
	if not IsValid(panel) then return end
	-- Full tree walk only once per open cycle (Cube: no UI thrash)
	if panel._cubeThemed and panel._cubeSkinApplied and not force then
		return
	end
	panel._cubeThemed = true
	panel._cubeSkinApplied = true
	applySkinRecursive(panel, SKIN_NAME, 0)
	-- Future children (lazy tabs) — skin the child only, not re-walk the whole shell
	if not panel._cubeSkinHooked then
		panel._cubeSkinHooked = true
		local old = panel.OnChildAdded
		panel.OnChildAdded = function(self, child)
			if old then old(self, child) end
			if not IsValid(child) or not shouldTheme() or not self._cubeThemed then return end
			if child.SetSkin then pcall(function() child:SetSkin(SKIN_NAME) end) end
		end
	end
end

--- Restore Default skin after VR so desktop spawn looks stock again
function vrmod.cube.RestoreDermaSkin(panel)
	if not IsValid(panel) then return end
	panel._cubeThemed = false
	panel._cubeSkinApplied = false
	panel._cubeWorkbenchReady = false
	applySkinRecursive(panel, DEFAULT_SKIN, 0)
	if panel.InvalidateLayout then panel:InvalidateLayout(false) end
end

------------------------------------------------------------------------
-- Spawn / context root chrome (window frame + close X)
------------------------------------------------------------------------
local TITLE_H = 32

local CLOSE_W, CLOSE_H = 52, 32 -- large enough for VR laser hit

local function placeCloseButton(btn, panel)
	if not IsValid(btn) or not IsValid(panel) then return end
	local pw = math.max(panel:GetWide(), 64)
	btn:SetSize(CLOSE_W, CLOSE_H)
	btn:SetPos(math.max(4, pw - CLOSE_W - 6), 2)
	btn:SetZPos(32767)
	btn:MoveToFront()
	btn:SetMouseInputEnabled(true)
	-- Visible whenever VR theming is on (do not require flaky _cubeThemed re-checks)
	local show = shouldTheme()
	if panel._cubeThemed == false then show = false end
	btn:SetVisible(show)
end

local function installCloseButton(panel, which)
	if not IsValid(panel) then return end
	if IsValid(panel._cubeCloseBtn) then
		panel._cubeCloseBtn._cubeShell = which or panel._cubeCloseBtn._cubeShell or "spawn"
		placeCloseButton(panel._cubeCloseBtn, panel)
		return
	end
	local btn = vgui.Create("DButton", panel)
	panel._cubeCloseBtn = btn
	btn:SetText("")
	btn:SetSize(CLOSE_W, CLOSE_H)
	btn:SetZPos(32767)
	btn:SetMouseInputEnabled(true)
	btn:SetCursor("hand")
	btn._cubeShell = which or "spawn"
	function btn:Think()
		if not IsValid(panel) then
			if IsValid(self) then self:Remove() end
			return
		end
		placeCloseButton(self, panel)
	end
	function btn:Paint(w, h)
		-- Always paint when visible (even if theme flag briefly lags)
		local th = T()
		local hot = self:IsHovered()
		local bg = hot and (th.btnHover or th.crimson) or Color(120, 20, 40, 255)
		rect(0, 0, w, h, bg)
		outline(0, 0, w, h, hot and (th.crimsonHot or Color(255, 70, 100)) or Color(196, 30, 58), hot and 3 or 2)
		draw.SimpleText("X", "DermaLarge", w * 0.5, h * 0.5, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	function btn:DoClick()
		local shell = self._cubeShell or "spawn"
		if vrmod.panel2vr and vrmod.panel2vr.CloseSandboxShell then
			vrmod.panel2vr.CloseSandboxShell(shell)
		elseif shell == "context" and IsValid(g_ContextMenu) and g_ContextMenu.Close then
			g_ContextMenu:Close()
		elseif IsValid(g_SpawnMenu) and g_SpawnMenu.Close then
			g_SpawnMenu:Close()
		end
	end
	placeCloseButton(btn, panel)
end

local function installRootChrome(panel, title, which)
	if not IsValid(panel) then return end
	if not panel._cubeChrome then
		panel._cubeChrome = true
		panel._cubePaintOrig = panel.Paint
		panel._cubeChromeTitle = title
		panel._cubeShellWhich = which or "spawn"
		panel.Paint = function(self, w, h)
			-- Only draw Cube chrome during VR; desktop keeps stock (usually no paint)
			if shouldTheme() and self._cubeThemed then
				local th = T()
				local ttl = self._cubeChromeTitle or "SPAWN"
				local bg = th.bg or Color(12, 6, 10, 245)
				-- Window body
				rect(0, 0, w, h, Color(bg.r, bg.g, bg.b, math.min(bg.a or 245, 210)))
				-- Title bar
				rect(0, 0, w, TITLE_H, Color((th.bgGlass or bg).r, (th.bgGlass or bg).g, (th.bgGlass or bg).b, 200))
				rect(0, 0, w, 3, th.crimson)
				rect(0, TITLE_H - 1, w, 1, th.crimsonDim or th.crimson)
				outline(0, 0, w, h, th.crimsonDim or th.crimson, 2)
				local fnt = (vrmod.cube.Font and vrmod.cube.Font("CubeTitle")) or "DermaLarge"
				draw.SimpleText(ttl, fnt, 12, math.floor(TITLE_H * 0.5), th.crimson, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				-- Preset left of close button
				local preset = th.presetLabel or "CUBE"
				local sf = (vrmod.cube.Font and vrmod.cube.Font("CubeSmall")) or "DermaDefault"
				draw.SimpleText(preset, sf, w - 56, math.floor(TITLE_H * 0.5), th.muted or th.crimsonDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			end
			if self._cubePaintOrig then return self._cubePaintOrig(self, w, h) end
		end
	else
		panel._cubeChromeTitle = title or panel._cubeChromeTitle
		panel._cubeShellWhich = which or panel._cubeShellWhich
	end
	installCloseButton(panel, which or panel._cubeShellWhich or "spawn")
end

local function polishSpawnTreePanels(root)
	if not IsValid(root) then return end
	local th = T()
	local glass = Color(
		(th.bgGlass or th.panel or th.bg).r,
		(th.bgGlass or th.panel or th.bg).g,
		(th.bgGlass or th.panel or th.bg).b,
		130
	)
	local function walk(p, depth)
		if not IsValid(p) or (depth or 0) > 28 then return end
		local cls = string.lower(tostring(p.ClassName or p:GetClassName() or ""))
		-- Left category tree: kill solid 240,240,240 brick
		if cls:find("dtree", 1, true) then
			if p.SetBackgroundColor then p:SetBackgroundColor(glass) end
			if p.SetPaintBackground then p:SetPaintBackground(true) end
		end
		-- Nested props divider: tree rail fixed width so it sits inside chrome
		if cls:find("dhorizontaldivider", 1, true) then
			local cookie = p.GetCookieName and p:GetCookieName() or ""
			if tostring(cookie):find("CreationMenu", 1, true) or (depth or 0) >= 2 then
				if p.SetLeftWidth then p:SetLeftWidth(200) end
				if p.SetLeftMin then p:SetLeftMin(140) end
				if p.SetRightMin then p:SetRightMin(260) end
			end
		end
		-- Hide desktop tips that float wrong under hand UI
		if cls:find("dlabel", 1, true) and p.GetText then
			local t = tostring(p:GetText() or "")
			if t:find("Hold", 1, true) and t:find("C", 1, true) then
				if p.SetVisible then p:SetVisible(false) end
			end
		end
		for _, ch in ipairs(p:GetChildren() or {}) do
			walk(ch, (depth or 0) + 1)
		end
	end
	walk(root, 0)
end

--- Context menu stock layout uses ScrW/ScrH — content sits OFF the VR RT.
local function layoutContextForVR(panel)
	if not IsValid(panel) then return end
	-- World clicker steals focus for "shoot world through UI" — kills VR laser clicks
	if panel.SetWorldClicker then panel:SetWorldClicker(false) end
	if panel.SetMouseInputEnabled then panel:SetMouseInputEnabled(true) end
	-- Stock ContextMenu: Dock FILL + DesktopWidgets Dock LEFT — undock into RT box
	if panel.Dock then panel:Dock(NODOCK) end
	-- Prefer VR eye metrics when available (keeps layout in sync with RT)
	local mw, mh
	if vrmod.GetVRUIPanelMetrics then
		mw, mh = vrmod.GetVRUIPanelMetrics("contextmenu")
	end
	local pw = math.max(panel:GetWide(), mw or 320, 320)
	local ph = math.max(panel:GetTall(), mh or 240, 240)
	if mw and mh and (panel:GetWide() ~= mw or panel:GetTall() ~= mh) then
		panel:SetSize(mw, mh)
		pw, ph = mw, mh
	end
	panel:SetPos(0, 0)
	if panel.DockPadding then
		panel:DockPadding(4, TITLE_H + 2, 4, 4)
	end
	-- Tool control panel lives on Canvas (DCategoryList)
	if IsValid(panel.Canvas) then
		if panel.Canvas.Dock then panel.Canvas:Dock(NODOCK) end
		if panel.Canvas.SetWorldClicker then panel.Canvas:SetWorldClicker(false) end
		local acp = spawnmenu and spawnmenu.ActiveControlPanel and spawnmenu.ActiveControlPanel()
		if IsValid(acp) then
			pcall(function() acp:InvalidateLayout(true) end)
			local tall = math.min((acp.GetTall and acp:GetTall() or 400) + 10, ph - TITLE_H - 24)
			local wide = math.min(math.floor(pw * 0.88), math.max(220, pw - 24))
			panel.Canvas:SetVisible(true)
			panel.Canvas:SetSize(wide, math.max(120, tall))
			panel.Canvas:SetPos(12, TITLE_H + 8)
			if panel.Canvas.InvalidateLayout then panel.Canvas:InvalidateLayout(true) end
		else
			panel.Canvas:SetVisible(panel.Canvas:IsVisible())
			if panel.Canvas:IsVisible() then
				panel.Canvas:SetSize(math.max(200, pw - 24), math.max(120, ph - TITLE_H - 24))
				panel.Canvas:SetPos(12, TITLE_H + 8)
			end
		end
	end
	-- DesktopWidgets (DIconLayout) — undock and keep inside frame
	if IsValid(panel.DesktopWidgets) then
		if panel.DesktopWidgets.Dock then panel.DesktopWidgets:Dock(NODOCK) end
		if panel.DesktopWidgets.SetWorldClicker then panel.DesktopWidgets:SetWorldClicker(false) end
		local y0 = TITLE_H + 8
		if IsValid(panel.Canvas) and panel.Canvas:IsVisible() then
			y0 = panel.Canvas:GetY() + panel.Canvas:GetTall() + 8
		end
		-- Icons row under tool panel (or fill if no tool)
		local ih = math.max(40, math.min(100, ph - y0 - 12))
		if not (IsValid(panel.Canvas) and panel.Canvas:IsVisible()) then
			ih = math.max(80, ph - y0 - 12)
		end
		panel.DesktopWidgets:SetPos(12, y0)
		panel.DesktopWidgets:SetSize(math.max(100, pw - 24), ih)
		if panel.DesktopWidgets.InvalidateLayout then panel.DesktopWidgets:InvalidateLayout(true) end
	end
end

local function themeWorkbench(panel, title, which)
	if not IsValid(panel) or not shouldTheme() then return end
	if not cubeSkin then vrmod.cube.RefreshDermaSkin() end
	local isContext = (which == "context" or which == "contextmenu")
	local first = not panel._cubeWorkbenchReady

	-- Heavy path once: skin walk + chrome install
	if first then
		vrmod.cube.ApplyDermaSkin(panel, true)
		installRootChrome(panel, title, which or "spawn")
		panel._cubeWorkbenchReady = true
	else
		-- Light reopen: chrome + close X only
		installRootChrome(panel, title, which or "spawn")
	end

	local function applyMargins(full)
		if not IsValid(panel) or not shouldTheme() then return end
		if panel.DockPadding then
			panel:DockPadding(4, TITLE_H + 2, 4, 4)
		end
		if IsValid(panel._cubeCloseBtn) then
			placeCloseButton(panel._cubeCloseBtn, panel)
		else
			installCloseButton(panel, which or panel._cubeShellWhich or "spawn")
		end

		if isContext then
			layoutContextForVR(panel)
		else
			local div = panel.HorizontalDivider
			if IsValid(div) then
				if div.DockMargin then
					div:DockMargin(8, TITLE_H + 4, 8, 8)
				end
				local tw = panel:GetWide()
				if tw < 100 then tw = 1024 end
				if div.SetRightMin then div:SetRightMin(math.floor(tw * 0.28)) end
				if div.SetLeftMin then div:SetLeftMin(math.floor(tw * 0.42)) end
				if div.SetLeftWidth then div:SetLeftWidth(math.floor(tw * 0.62)) end
				if div.SetDividerWidth then div:SetDividerWidth(4) end
			end
			-- Tree polish only on first open or explicit full pass
			if full and not panel._cubePolishDone then
				polishSpawnTreePanels(panel)
				panel._cubePolishDone = true
			end
		end
		if IsValid(panel._cubeCloseBtn) then
			placeCloseButton(panel._cubeCloseBtn, panel)
		end
	end

	applyMargins(first)

	if not panel._cubeLayoutHooked then
		panel._cubeLayoutHooked = true
		panel._cubeLayoutOrig = panel.PerformLayout
		panel.PerformLayout = function(self, ...)
			if isContext and shouldTheme() and self._cubeThemed then
				-- NEVER run stock ScrW/ScrH layout — parks Canvas off the VR RT
				applyMargins(false)
				return
			end
			if self._cubeLayoutOrig then self._cubeLayoutOrig(self, ...) end
			if shouldTheme() then
				applyMargins(false)
			end
		end
	end

	-- One forced layout on first theme only (InvalidateLayout true freezes VR)
	if first and panel.InvalidateLayout then
		panel:InvalidateLayout(true)
	end
	-- Single deferred pass for close X after lazy children — not 3 full restyles
	if not panel._cubeOneShotMargin then
		panel._cubeOneShotMargin = true
		timer.Simple(0.06, function()
			panel._cubeOneShotMargin = nil
			if not IsValid(panel) or not shouldTheme() then return end
			installCloseButton(panel, which or "spawn")
			applyMargins(false)
			if g_VR and g_VR.menus then
				for uid, m in pairs(g_VR.menus) do
					if m and m.panel == panel then m.dirty = true end
				end
			end
		end)
	end
end

function vrmod.cube.ThemeSpawnMenu(panel)
	if not shouldTheme() then return end
	themeWorkbench(panel or g_SpawnMenu, "SPAWN MENU", "spawn")
end

function vrmod.cube.ThemeContextMenu(panel)
	if not shouldTheme() then return end
	themeWorkbench(panel or g_ContextMenu, "CONTEXT", "context")
end

--- Undo VR workbench theming (Default skin, stock layout path)
function vrmod.cube.RestoreWorkbench(panel)
	if not IsValid(panel) then return end
	panel._cubeWorkbenchReady = false
	panel._cubePolishDone = false
	panel._cubeOneShotMargin = nil
	vrmod.cube.RestoreDermaSkin(panel)
	if IsValid(panel._cubeCloseBtn) then
		panel._cubeCloseBtn:SetVisible(false)
	end
	if panel.InvalidateLayout then panel:InvalidateLayout(false) end
end

function vrmod.cube.RestoreAllWorkbench()
	if IsValid(g_SpawnMenu) then vrmod.cube.RestoreWorkbench(g_SpawnMenu) end
	if IsValid(g_ContextMenu) then vrmod.cube.RestoreWorkbench(g_ContextMenu) end
end

------------------------------------------------------------------------
-- ContentIcon: cube border only under VR-themed spawn/context
------------------------------------------------------------------------
local contentIconPatched = false

local function patchContentIcon()
	if contentIconPatched then return end
	local ct = vgui.GetControlTable and vgui.GetControlTable("ContentIcon")
	if not ct or not ct.Paint then return end
	contentIconPatched = true
	local oldPaint = ct.Paint
	ct.Paint = function(self, w, h)
		oldPaint(self, w, h)
		-- Never draw Cube chrome on desktop / non-VR
		if not shouldTheme() then return end
		local underSpawn = IsValid(g_SpawnMenu) and g_SpawnMenu._cubeThemed
			and self.HasParent and self:HasParent(g_SpawnMenu)
		local underCtx = IsValid(g_ContextMenu) and g_ContextMenu._cubeThemed
			and self.HasParent and self:HasParent(g_ContextMenu)
		if not underSpawn and not underCtx then return end
		local th = T()
		local hot = self:IsHovered() or self.Depressed or self:IsSelected()
		outline(0, 0, w, h, hot and (th.crimsonHot or th.crimson) or (th.crimsonDim or th.crimson), hot and 3 or 2)
		if hot then
			rect(0, 0, 4, h, th.crimson)
		end
	end
end

------------------------------------------------------------------------
-- Hooks — restore on exit only.
-- Theme apply is owned by panel2vr preparePanelForVR (one-energy; no open thrash).
------------------------------------------------------------------------
hook.Remove("OnSpawnMenuOpen", "vrmod_cube_spawn_skin")
hook.Remove("OnContextMenuOpen", "vrmod_cube_spawn_skin")

hook.Add("VRMod_Start", "vrmod_cube_spawn_skin", function()
	-- Skin table ready; actual apply waits for spawn open
	if vrmod.cube.RefreshDermaSkin then vrmod.cube.RefreshDermaSkin() end
end)

hook.Add("VRMod_Exit", "vrmod_cube_spawn_skin", function()
	-- Critical: leave desktop with Default Derma, not Cube
	if vrmod.cube.RestoreAllWorkbench then
		vrmod.cube.RestoreAllWorkbench()
	end
end)

hook.Add("InitPostEntity", "vrmod_cube_derma_skin", function()
	-- Register skin only — never apply to g_SpawnMenu here
	vrmod.cube.RefreshDermaSkin()
	patchContentIcon()
end)

hook.Add("VRMod_CubeFrameworkReady", "vrmod_cube_derma_skin", function()
	vrmod.cube.RefreshDermaSkin()
end)

cvars.AddChangeCallback("vrmod_cube_preset", function()
	if vrmod.cube.RefreshDermaSkin then vrmod.cube.RefreshDermaSkin() end
end, "cube_derma")
cvars.AddChangeCallback("vrmod_cube_accent", function()
	if vrmod.cube.RefreshDermaSkin then vrmod.cube.RefreshDermaSkin() end
end, "cube_derma")
cvars.AddChangeCallback("vrmod_cube_glass", function()
	if vrmod.cube.RefreshDermaSkin then vrmod.cube.RefreshDermaSkin() end
end, "cube_derma")

-- Register skin definition early (DefineSkin only — no panel mutation)
timer.Simple(0, function()
	vrmod.cube.RefreshDermaSkin()
	patchContentIcon()
end)

concommand.Add("vrmod_cube_spawnmenu_refresh", function()
	if not shouldTheme() then
		print("[cube] spawn theme is VR-only (not in VR session)")
		return
	end
	vrmod.cube.RefreshDermaSkin()
	if IsValid(g_SpawnMenu) then vrmod.cube.ThemeSpawnMenu(g_SpawnMenu) end
	if IsValid(g_ContextMenu) then vrmod.cube.ThemeContextMenu(g_ContextMenu) end
	print("[cube] spawn/context derma skin refreshed (VR)")
end)
