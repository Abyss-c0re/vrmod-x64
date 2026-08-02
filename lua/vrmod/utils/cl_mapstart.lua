if SERVER then return end
-- =============================================================================
-- vrmod.MapStart — shared map / host start logic for VR + desktop menus
--
-- Proven path (original VR map browser): vrmod_autostart + changelevel.
-- maxplayers is blocked mid-session on the client; only attempt when free,
-- otherwise changelevel keeps current slot count (still loads the map).
-- =============================================================================

vrmod = vrmod or {}
vrmod.MapStart = vrmod.MapStart or {}

local MS = vrmod.MapStart

function MS.IsBlocked(cmd)
	if not cmd or cmd == "" then return false end
	if IsConCommandBlocked then
		local ok, blocked = pcall(IsConCommandBlocked, cmd)
		if ok and blocked then return true end
	end
	return false
end

--- Run a console command if not blocked. Returns false if blocked / failed.
function MS.Run(cmd, ...)
	if not cmd then return false end
	if MS.IsBlocked(cmd) then
		-- Host-only fallback (often still blocked for maxplayers)
		if game and game.ConsoleCommand then
			local line = cmd
			for i = 1, select("#", ...) do
				line = line .. " " .. tostring(select(i, ...))
			end
			local ok = pcall(game.ConsoleCommand, line .. "\n")
			return ok
		end
		return false
	end
	local ok = pcall(RunConsoleCommand, cmd, ...)
	return ok
end

function MS.InGame()
	if isfunction(IsInGame) then return IsInGame() end
	local ply = LocalPlayer()
	return IsValid(ply)
end

--- Apply optional host / gamemode settings (skips blocked cmds).
-- @param opts table
function MS.ApplyHostSettings(opts)
	opts = opts or {}
	if opts.gamemode and opts.gamemode ~= "" then
		MS.Run("gamemode", tostring(opts.gamemode))
	end
	local mp = tonumber(opts.maxplayers)
	if mp and mp > 1 then
		MS.Run("sv_cheats", "0")
	end
	if opts.hostname and opts.hostname ~= "" then
		MS.Run("hostname", tostring(opts.hostname))
	end
	if opts.sv_lan ~= nil then
		MS.Run("sv_lan", opts.sv_lan and "1" or "0")
	end
	if opts.p2p_enabled ~= nil then
		MS.Run("p2p_enabled", opts.p2p_enabled and "1" or "0")
	end
	if opts.p2p_friendsonly ~= nil then
		MS.Run("p2p_friendsonly", opts.p2p_friendsonly and "1" or "0")
	end
	-- Gamemode settings rows: { { name=, value=, type= }, ... }
	if istable(opts.settings) then
		for _, row in ipairs(opts.settings) do
			if row and row.name then
				local v = row.value
				if row.type == "checkbox" then
					v = tobool(v) and "1" or "0"
				end
				MS.Run(tostring(row.name), tostring(v))
			end
		end
	end
end

--- Load a map. Primary path mirrors original VR map browser.
-- @param opts { map, gamemode, maxplayers, hostname, sv_lan, p2p_*, settings, keepVR, delay }
-- @return ok, msg
function MS.Load(opts)
	opts = opts or {}
	local mapName = opts.map or opts.mapName
	if not mapName or mapName == "" then
		return false, "no map"
	end
	mapName = string.Trim(tostring(mapName))
	-- strip .bsp if present
	mapName = string.gsub(mapName, "%.bsp$", "")

	if opts.keepVR ~= false then
		MS.Run("vrmod_autostart", "1")
	end
	MS.Run("progress_enable")
	MS.ApplyHostSettings(opts)

	local mp = tonumber(opts.maxplayers)
	local mpApplied = true
	if mp and mp >= 1 then
		mpApplied = MS.Run("maxplayers", tostring(mp))
	end

	local delay = tonumber(opts.delay) or 0.2
	local inGame = MS.InGame()

	timer.Simple(delay, function()
		-- Original VR map menu: always changelevel when already playing
		if inGame then
			-- changelevel is the reliable in-session map switch (listen host)
			if not MS.Run("changelevel", mapName) then
				-- last resort
				MS.Run("map", mapName)
			end
		else
			if mp and not mpApplied then
				MS.Run("maxplayers", tostring(mp))
			end
			if not MS.Run("map", mapName) then
				MS.Run("changelevel", mapName)
			end
		end
	end)

	local msg
	if not mpApplied and mp and mp > 1 then
		msg = "map load (slot count unchanged — maxplayers blocked in-session)"
	else
		msg = "map load scheduled"
	end
	return true, msg
end

--- Convenience: start map keeping VR (used by New Game / map browser).
function MS.StartFromVR(mapName, opts)
	opts = opts or {}
	opts.map = mapName or opts.map
	opts.keepVR = true
	if vrmod.VRUnpauseWorld then pcall(vrmod.VRUnpauseWorld) end
	local ok, msg = MS.Load(opts)
	if ok and vrmod.Toast then
		local gm = opts.gamemode or "?"
		local mp = opts.maxplayers or game.MaxPlayers and game.MaxPlayers() or "?"
		vrmod.Toast(string.format("%s · %s · %sp", opts.map, gm, mp), 3, "hint")
	end
	return ok, msg
end

concommand.Add("vrmod_mapstart", function(_, _, args)
	local map = args[1]
	if not map then
		print("[gVRMod] usage: vrmod_mapstart <map> [gamemode]")
		return
	end
	MS.StartFromVR(map, { gamemode = args[2] or engine.ActiveGamemode() })
end)
