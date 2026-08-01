if SERVER then return end
-- =============================================================================
-- Quick Menu layout — pages + visibility (client save, VR UX only)
-- Layout file: data/vrmod/quickmenu_layout.json
-- Does not change non-VR UI. Desktop users never open this menu.
-- =============================================================================

vrmod = vrmod or {}
vrmod.QuickMenu = vrmod.QuickMenu or {}
local QM = vrmod.QuickMenu

local LAYOUT_FILE = "vrmod/quickmenu_layout.json"
local MAX_PAGES = 6
local COLS = 6
local MAX_ROWS = 4

-- Stable ids for built-ins (name → id). Addon items get sanitized names.
local NAME_TO_ID = {
	["Spawn Menu"] = "spawn",
	["Context Menu"] = "context",
	["Chat"] = "chat",
	["Numpad"] = "numpad",
	["Avatar"] = "avatar",
	["Settings"] = "settings",
	["Flashlight"] = "flashlight",
	["Laser pointer"] = "laser",
	["Weapon VR"] = "weapon_vr",
	["Toggle Noclip"] = "noclip",
	["Undo"] = "undo",
	["Cleanup"] = "cleanup",
	["Admin Cleanup"] = "admin_cleanup",
	["Reset Vehicle View"] = "vehicle_view",
	["UI Reset"] = "ui_reset",
	["Border Cal"] = "border_cal",
	["Toggle blacklist weapon"] = "blacklist",
	["Map Browser"] = "map",
	["RESPAWN"] = "respawn",
	["VR EXIT"] = "vr_exit",
	["DISCONNECT"] = "disconnect",
	["Calibrate Full-body Tracking"] = "fbt_calibrate",
	["Disable Full-body Tracking"] = "fbt_disable",
}

-- Default multi-page layout (cols 0-5, rows 0+)
local function DefaultLayout()
	return {
		version = 1,
		pages = {
			{
				name = "Main",
				items = {
					{ id = "spawn", col = 0, row = 0 },
					{ id = "context", col = 1, row = 0 },
					{ id = "chat", col = 2, row = 0 },
					{ id = "numpad", col = 3, row = 0 },
					{ id = "avatar", col = 4, row = 0 },
					{ id = "settings", col = 5, row = 0 },
					{ id = "flashlight", col = 0, row = 1 },
					{ id = "laser", col = 1, row = 1 },
					{ id = "weapon_vr", col = 2, row = 1 },
					{ id = "noclip", col = 3, row = 1 },
					{ id = "undo", col = 4, row = 1 },
					{ id = "cleanup", col = 5, row = 1 },
				},
			},
			{
				name = "System",
				items = {
					{ id = "admin_cleanup", col = 0, row = 0 },
					{ id = "vehicle_view", col = 1, row = 0 },
					{ id = "ui_reset", col = 2, row = 0 },
					{ id = "border_cal", col = 3, row = 0 },
					{ id = "blacklist", col = 4, row = 0 },
					{ id = "map", col = 5, row = 0 },
					{ id = "respawn", col = 0, row = 1 },
					{ id = "vr_exit", col = 1, row = 1 },
					{ id = "disconnect", col = 2, row = 1 },
					{ id = "fbt_calibrate", col = 3, row = 1 },
					{ id = "fbt_disable", col = 4, row = 1 },
				},
			},
		},
		-- ids explicitly hidden (not shown on any page)
		hidden = {},
	}
end

local layout = nil
local currentPage = 1 -- 1-based while menu open

function QM.IdFromName(name)
	if not name then return "item" end
	if NAME_TO_ID[name] then return NAME_TO_ID[name] end
	local id = string.lower(tostring(name)):gsub("%s+", "_"):gsub("[^%w_]", "")
	if id == "" then id = "item" end
	return id
end

function QM.RegisterName(id, name)
	if id and name then NAME_TO_ID[name] = id end
end

local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local n = {}
	for k, v in pairs(t) do
		n[k] = deepCopy(v)
	end
	return n
end

function QM.GetDefaultLayout()
	return DefaultLayout()
end

function QM.ValidateLayout(L)
	if type(L) ~= "table" then return DefaultLayout() end
	if type(L.pages) ~= "table" or #L.pages < 1 then
		L.pages = DefaultLayout().pages
	end
	while #L.pages > MAX_PAGES do
		table.remove(L.pages)
	end
	for pi, page in ipairs(L.pages) do
		page.name = tostring(page.name or ("Page " .. pi))
		page.items = page.items or {}
		local cleaned = {}
		local used = {}
		for _, it in ipairs(page.items) do
			if type(it) == "table" and it.id then
				local col = math.Clamp(math.floor(tonumber(it.col) or 0), 0, COLS - 1)
				local row = math.Clamp(math.floor(tonumber(it.row) or 0), 0, MAX_ROWS - 1)
				local key = col .. ":" .. row
				if not used[key] then
					used[key] = true
					cleaned[#cleaned + 1] = { id = tostring(it.id), col = col, row = row }
				end
			end
		end
		page.items = cleaned
	end
	if type(L.hidden) ~= "table" then L.hidden = {} end
	-- normalize hidden list → set
	local hid = {}
	if L.hidden[1] ~= nil then
		for _, id in ipairs(L.hidden) do hid[tostring(id)] = true end
	else
		for id, v in pairs(L.hidden) do
			if v then hid[tostring(id)] = true end
		end
	end
	L.hidden = hid
	L.version = 1
	return L
end

function QM.Load()
	local raw = file.Read(LAYOUT_FILE, "DATA")
	if raw and raw ~= "" then
		local ok, decoded = pcall(util.JSONToTable, raw)
		if ok and type(decoded) == "table" then
			layout = QM.ValidateLayout(decoded)
			return layout
		end
	end
	layout = DefaultLayout()
	return layout
end

function QM.Save()
	if not layout then layout = DefaultLayout() end
	layout = QM.ValidateLayout(layout)
	-- serialize hidden as array for cleaner JSON
	local out = deepCopy(layout)
	local arr = {}
	for id, v in pairs(layout.hidden or {}) do
		if v then arr[#arr + 1] = id end
	end
	table.sort(arr)
	out.hidden = arr
	file.CreateDir("vrmod")
	file.Write(LAYOUT_FILE, util.TableToJSON(out, true) or "{}")
	return true
end

function QM.GetLayout()
	if not layout then QM.Load() end
	return layout
end

function QM.ResetLayout()
	layout = DefaultLayout()
	QM.Save()
	currentPage = 1
	hook.Run("VRMod_QuickMenuLayoutChanged")
	return layout
end

function QM.GetPageCount()
	local L = QM.GetLayout()
	return math.max(1, #(L.pages or {}))
end

function QM.GetCurrentPage()
	return math.Clamp(currentPage, 1, QM.GetPageCount())
end

function QM.SetCurrentPage(p)
	currentPage = math.Clamp(math.floor(tonumber(p) or 1), 1, QM.GetPageCount())
	return currentPage
end

function QM.NextPage()
	local n = QM.GetPageCount()
	currentPage = currentPage >= n and 1 or (currentPage + 1)
	return currentPage
end

function QM.PrevPage()
	local n = QM.GetPageCount()
	currentPage = currentPage <= 1 and n or (currentPage - 1)
	return currentPage
end

function QM.GetPageName(pi)
	local L = QM.GetLayout()
	local page = L.pages[pi or QM.GetCurrentPage()]
	return page and page.name or ("Page " .. tostring(pi))
end

function QM.SetPageName(pi, name)
	local L = QM.GetLayout()
	pi = math.Clamp(math.floor(tonumber(pi) or 1), 1, #L.pages)
	L.pages[pi].name = string.sub(tostring(name or L.pages[pi].name), 1, 24)
	QM.Save()
	hook.Run("VRMod_QuickMenuLayoutChanged")
end

function QM.AddPage(name)
	local L = QM.GetLayout()
	if #L.pages >= MAX_PAGES then return false, "max pages" end
	L.pages[#L.pages + 1] = {
		name = name or ("Page " .. (#L.pages + 1)),
		items = {},
	}
	QM.Save()
	hook.Run("VRMod_QuickMenuLayoutChanged")
	return true
end

function QM.RemovePage(pi)
	local L = QM.GetLayout()
	if #L.pages <= 1 then return false, "need one page" end
	pi = math.Clamp(math.floor(tonumber(pi) or #L.pages), 1, #L.pages)
	-- Move items from removed page onto previous page free slots
	local removed = table.remove(L.pages, pi)
	local target = L.pages[math.max(1, pi - 1)]
	if removed and removed.items then
		for _, it in ipairs(removed.items) do
			QM.PlaceItemOnPage(target, it.id, it.col, it.row)
		end
	end
	if currentPage > #L.pages then currentPage = #L.pages end
	QM.Save()
	hook.Run("VRMod_QuickMenuLayoutChanged")
	return true
end

function QM.PlaceItemOnPage(page, id, col, row)
	if not page or not id then return end
	page.items = page.items or {}
	-- remove existing placement of this id from this page
	for i = #page.items, 1, -1 do
		if page.items[i].id == id then table.remove(page.items, i) end
	end
	col = math.Clamp(math.floor(tonumber(col) or 0), 0, COLS - 1)
	row = math.Clamp(math.floor(tonumber(row) or 0), 0, MAX_ROWS - 1)
	-- clear occupant of target cell
	for i = #page.items, 1, -1 do
		if page.items[i].col == col and page.items[i].row == row then
			table.remove(page.items, i)
		end
	end
	page.items[#page.items + 1] = { id = id, col = col, row = row }
end

--- Find which page an id is on (or nil if hidden / missing)
function QM.FindItem(id)
	local L = QM.GetLayout()
	if L.hidden[id] then return nil, nil, true end
	for pi, page in ipairs(L.pages) do
		for _, it in ipairs(page.items or {}) do
			if it.id == id then return pi, it, false end
		end
	end
	return nil, nil, false
end

function QM.IsHidden(id)
	local L = QM.GetLayout()
	return L.hidden[id] == true
end

function QM.SetHidden(id, hidden)
	local L = QM.GetLayout()
	id = tostring(id)
	if hidden then
		L.hidden[id] = true
		-- remove from all pages
		for _, page in ipairs(L.pages) do
			for i = #page.items, 1, -1 do
				if page.items[i].id == id then table.remove(page.items, i) end
			end
		end
	else
		L.hidden[id] = nil
		-- if not on any page, put on last free cell of page 1
		local pi, _ = QM.FindItem(id)
		if not pi then
			QM.AssignToPage(id, 1)
		end
	end
	QM.Save()
	hook.Run("VRMod_QuickMenuLayoutChanged")
end

function QM.AssignToPage(id, pageIndex, col, row)
	local L = QM.GetLayout()
	id = tostring(id)
	L.hidden[id] = nil
	-- strip from all pages
	for _, page in ipairs(L.pages) do
		for i = #page.items, 1, -1 do
			if page.items[i].id == id then table.remove(page.items, i) end
		end
	end
	pageIndex = math.Clamp(math.floor(tonumber(pageIndex) or 1), 1, #L.pages)
	local page = L.pages[pageIndex]
	if col == nil or row == nil then
		-- first free cell
		local used = {}
		for _, it in ipairs(page.items) do
			used[it.col .. ":" .. it.row] = true
		end
		local placed = false
		for r = 0, MAX_ROWS - 1 do
			for c = 0, COLS - 1 do
				if not used[c .. ":" .. r] then
					col, row = c, r
					placed = true
					break
				end
			end
			if placed then break end
		end
		col = col or 0
		row = row or 0
	end
	QM.PlaceItemOnPage(page, id, col, row)
	QM.Save()
	hook.Run("VRMod_QuickMenuLayoutChanged")
end

--- Cycle: hidden → page1 → page2 → ... → hidden
function QM.CycleItemPage(id)
	local L = QM.GetLayout()
	id = tostring(id)
	local pi, _, hid = QM.FindItem(id)
	if hid or not pi then
		-- currently hidden or missing → page 1
		QM.AssignToPage(id, 1)
		return 1
	end
	if pi >= #L.pages then
		QM.SetHidden(id, true)
		return 0 -- hidden
	end
	QM.AssignToPage(id, pi + 1)
	return pi + 1
end

function QM.NudgeItem(id, dcol, drow)
	local pi, it = QM.FindItem(id)
	if not pi or not it then return false end
	local L = QM.GetLayout()
	local page = L.pages[pi]
	local ncol = math.Clamp(it.col + (dcol or 0), 0, COLS - 1)
	local nrow = math.Clamp(it.row + (drow or 0), 0, MAX_ROWS - 1)
	QM.PlaceItemOnPage(page, id, ncol, nrow)
	QM.Save()
	hook.Run("VRMod_QuickMenuLayoutChanged")
	return true
end

function QM.GetItemStatusLabel(id, name)
	local pi, it, hid = QM.FindItem(id)
	if hid then return string.format("%s · OFF", name or id) end
	if not pi then return string.format("%s · unassigned", name or id) end
	local pname = QM.GetPageName(pi)
	return string.format("%s · %s · (%d,%d)", name or id, pname, it.col, it.row)
end

--- Map menuItems → entries for a page: { menuIndex, id, name, col, row, func, hint }
function QM.BuildPageEntries(pageIndex)
	local L = QM.GetLayout()
	pageIndex = math.Clamp(math.floor(tonumber(pageIndex) or 1), 1, #L.pages)
	local page = L.pages[pageIndex]
	local byId = {}
	for idx, item in ipairs(g_VR.menuItems or {}) do
		local id = item.id or QM.IdFromName(item.name)
		byId[id] = byId[id] or {}
		byId[id][#byId[id] + 1] = { index = idx, item = item, id = id }
	end

	local entries = {}
	local placed = {}
	for _, slot in ipairs(page.items or {}) do
		local bucket = byId[slot.id]
		if bucket and #bucket > 0 then
			local pick = table.remove(bucket, 1)
			placed[slot.id] = true
			entries[#entries + 1] = {
				menuIndex = pick.index,
				id = slot.id,
				name = pick.item.name,
				hint = pick.item.hint,
				func = pick.item.func,
				col = slot.col,
				row = slot.row,
			}
		end
	end

	-- Orphans: registered items not in layout and not hidden → append last page only
	if pageIndex == #L.pages then
		local used = {}
		for _, e in ipairs(entries) do
			used[e.col .. ":" .. e.row] = true
		end
		for id, bucket in pairs(byId) do
			if L.hidden[id] then continue end
			local onLayout = false
			for _, pg in ipairs(L.pages) do
				for _, it in ipairs(pg.items or {}) do
					if it.id == id then onLayout = true break end
				end
				if onLayout then break end
			end
			if not onLayout then
				for _, pick in ipairs(bucket) do
					local col, row = 0, 0
					local found = false
					for r = 0, MAX_ROWS - 1 do
						for c = 0, COLS - 1 do
							if not used[c .. ":" .. r] then
								col, row = c, r
								found = true
								break
							end
						end
						if found then break end
					end
					if found then
						used[col .. ":" .. row] = true
						entries[#entries + 1] = {
							menuIndex = pick.index,
							id = id,
							name = pick.item.name,
							hint = pick.item.hint,
							func = pick.item.func,
							col = col,
							row = row,
						}
					end
				end
			end
		end
	end

	return entries
end

--- Known customizable ids (built-ins + currently registered menu items)
function QM.ListCustomizableItems()
	local seen = {}
	local list = {}
	local function add(id, name)
		if seen[id] then return end
		seen[id] = true
		list[#list + 1] = { id = id, name = name or id }
	end
	-- Prefer stable name map order
	local order = {
		"spawn", "context", "chat", "numpad", "avatar", "settings",
		"flashlight", "laser", "noclip", "undo", "cleanup", "admin_cleanup",
		"vehicle_view", "ui_reset", "border_cal", "blacklist", "map",
		"respawn", "vr_exit", "disconnect", "fbt_calibrate", "fbt_disable",
	}
	local idToName = {}
	for name, id in pairs(NAME_TO_ID) do idToName[id] = name end
	for _, id in ipairs(order) do
		add(id, idToName[id] or id)
	end
	for _, item in ipairs(g_VR.menuItems or {}) do
		local id = item.id or QM.IdFromName(item.name)
		add(id, item.name)
	end
	return list
end

function QM.BuildSettingsRows()
	local rows = {
		{ kind = "help", label = "VR quick menu only — does not affect desktop" },
		{ kind = "help", label = string.format("Pages: %d · layout: data/%s", QM.GetPageCount(), LAYOUT_FILE) },
		{ kind = "action", label = "Reset layout (defaults)", action_id = "qm_reset" },
		{ kind = "action", label = "Add page", action_id = "qm_add_page" },
		{ kind = "action", label = "Remove last page", action_id = "qm_remove_page" },
		{ kind = "header", label = "Items · tap to cycle page / OFF" },
	}
	for _, it in ipairs(QM.ListCustomizableItems()) do
		rows[#rows + 1] = {
			kind = "action",
			label = QM.GetItemStatusLabel(it.id, it.name),
			action_id = "qm_cycle_" .. it.id,
		}
		rows[#rows + 1] = {
			kind = "action",
			label = "  ↳ nudge ← → ↑ ↓  (" .. it.name .. ")",
			action_id = "qm_nudge_" .. it.id,
		}
	end
	rows[#rows + 1] = { kind = "help", label = "In VR: use ◀ ▶ on quick menu to change pages" }
	return rows
end

-- Load on client start
timer.Simple(0, function() QM.Load() end)
hook.Add("InitPostEntity", "vrmod_qm_layout_load", function() QM.Load() end)

concommand.Add("vrmod_quickmenu_reset", function()
	QM.ResetLayout()
	print("[vrmod] quick menu layout reset")
end)

concommand.Add("vrmod_quickmenu_status", function()
	local L = QM.GetLayout()
	print(string.format("[vrmod] quick menu pages=%d file=%s", #L.pages, LAYOUT_FILE))
	for pi, page in ipairs(L.pages) do
		print(string.format("  page %d %q items=%d", pi, page.name, #(page.items or {})))
	end
end)
