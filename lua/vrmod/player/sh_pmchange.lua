--[[
	Track playermodel changes so VR character IK + avatar twin rebuild without respawn.

	Also works around addons that break client player:GetModel() (e.g. PAC3) by
	storing the last known path on ply.vrmod_pm.
]]

if SERVER then
	util.AddNetworkString("vrmod_pmchange")
	util.AddNetworkString("vrmod_pmapply")

	local function NotifyPM(ply, model)
		if not IsValid(ply) or not ply:IsPlayer() then return end
		model = tostring(model or "")
		if model == "" then return end
		net.Start("vrmod_pmchange")
		net.WriteString(ply:SteamID())
		net.WriteString(model)
		net.Broadcast()
	end

	-- Avatar SAVE/APPLY: cl_playermodel only takes effect on spawn. Without a
	-- server SetModel the client flashes the new PM then snaps back to the
	-- old mesh (empty bone tables) until respawn.
	local _pmApplyAt = {}
	net.Receive("vrmod_pmapply", function(_, ply)
		if not IsValid(ply) or not ply:IsPlayer() then return end
		local path = tostring(net.ReadString() or "")
		local name = tostring(net.ReadString() or "")
		local skin = net.ReadUInt(8) or 0
		local bodyStr = tostring(net.ReadString() or "")
		if path == "" or #path > 260 then return end
		if not string.match(path, "^[Mm]odels/.+%.mdl$") then return end
		local now = CurTime()
		if (_pmApplyAt[ply] or 0) + 0.35 > now then return end
		_pmApplyAt[ply] = now
		pcall(util.PrecacheModel, path)
		if name ~= "" and player_manager and player_manager.SetPlayerModel then
			pcall(player_manager.SetPlayerModel, ply, name)
		end
		pcall(function() ply:SetModel(path) end)
		if ply:GetModel() ~= path then return end
		ply.vrmod_pm = path
		pcall(function() ply:SetSkin(skin) end)
		if bodyStr ~= "" then
			for pair in string.gmatch(bodyStr, "[^;]+") do
				local a, b = string.match(pair, "(%d+):(%d+)")
				if a then pcall(function() ply:SetBodygroup(tonumber(a), tonumber(b)) end) end
			end
		end
		NotifyPM(ply, path)
	end)

	-- Reliable when GMod/server sets the player model
	hook.Add("PlayerSetModel", "vrmod_pmchange", function(ply)
		if not IsValid(ply) then return end
		-- Model may not be applied until after hook returns
		timer.Simple(0, function()
			if not IsValid(ply) then return end
			NotifyPM(ply, ply:GetModel())
		end)
	end)

	-- Catch Entity:SetModel on players (some menus / addons)
	hook.Add("InitPostEntity", "vrmod_pmchange_setmodel", function()
		local meta = FindMetaTable("Entity")
		if not meta or meta._vrmod_SetModelWrapped then return end
		local og = meta.SetModel
		if not isfunction(og) then return end
		meta._vrmod_SetModelWrapped = true
		function meta:SetModel(model)
			og(self, model)
			if IsValid(self) and self:IsPlayer() then
				NotifyPM(self, model)
			end
		end
	end)
end

if CLIENT then
	local cv_allow = CreateClientConVar("vrmod_pmchange", "1", true, FCVAR_ARCHIVE,
		"Reload VR character IK + avatar twin when playermodel changes (no respawn)")

	local function ReloadLocalPM(ply, model, reason)
		if not cv_allow:GetBool() then return end
		if not IsValid(ply) or ply ~= LocalPlayer() then return end
		if not (g_VR and g_VR.active) then return end
		model = tostring(model or ply:GetModel() or "")
		local applyPath = g_VR._avatarApplyPath
		local inApply = applyPath and applyPath ~= "" and CurTime() < (g_VR._avatarApplyUntil or 0)
		-- Server still on the old PM until vrmod_pmapply lands — do not adopt it.
		if inApply and model ~= applyPath then
			ply.vrmod_pm = applyPath
			pcall(function() ply:SetModel(applyPath) end)
			return
		end
		local trusted = vrmod.character and vrmod.character.IsTrustedPlayerModel
			and vrmod.character.IsTrustedPlayerModel(model)
		-- Apply already queued ReloadCharacterSystem — net/poll must not Stop+restart.
		if trusted and (reason == "pmchange_net" or reason == "pmchange_poll") then
			ply.vrmod_pm = model
			return
		end
		local okPm, _miss, why
		if model ~= "" and not trusted and vrmod.character and vrmod.character.ValidatePlayerModel then
			okPm, _miss, why = vrmod.character.ValidatePlayerModel(model)
		end
		local law
		if vrmod.utils and vrmod.utils.AvatarApplyLaw_Decide then
			law = vrmod.utils.AvatarApplyLaw_Decide({
				phase = "reload_local",
				live_path = model,
				last_good = g_VR._lastGoodPlayerModel,
				trusted = trusted == true,
				probe_ok = okPm,
				apply_path = applyPath,
				from_net = reason == "pmchange_net" or reason == "pmchange_poll",
			})
		end
		local doRevert = law and law.revert
		if not law and okPm == false then doRevert = true end
		if doRevert then
			local msg = "VR: playermodel blocked · " .. tostring(why or "missing bones")
			if vrmod.Toast then vrmod.Toast(msg, 6, "warn") end
			if vrmod.logger then
				vrmod.logger.Warn("[pmchange] blocked %s: %s", model, tostring(why))
			end
			local good = g_VR._lastGoodPlayerModel
			if good and good ~= "" and good ~= model then
				ply.vrmod_pm = good
				if vrmod.avatar and vrmod.avatar.SyncAllToPlayer then
					timer.Simple(0.05, function()
						pcall(vrmod.avatar.SyncAllToPlayer)
					end)
				end
				if vrmod.Toast then
					vrmod.Toast("VR: kept previous compatible model", 4, "hint")
				end
			end
			return
		end
		if model ~= "" then
			ply.vrmod_pm = model
		end
		if g_VR.ReloadCharacterSystem then
			pcall(g_VR.ReloadCharacterSystem, ply, reason or "pmchange")
		elseif g_VR.StartCharacterSystem then
			pcall(g_VR.StartCharacterSystem, ply, true)
		end
		-- Twin: sync mesh + full bone map after player skeleton rebuilds
		timer.Simple(0.15, function()
			if not (g_VR and g_VR.active) then return end
			if vrmod.avatar and vrmod.avatar.SyncAllToPlayer then
				pcall(vrmod.avatar.SyncAllToPlayer)
			elseif vrmod.avatar and vrmod.avatar.ReloadAllIK then
				pcall(vrmod.avatar.ReloadAllIK)
			end
		end)
		timer.Simple(0.35, function()
			if not (g_VR and g_VR.active) then return end
			if vrmod.character and vrmod.character.ForceLocalIKAndPublish then
				pcall(vrmod.character.ForceLocalIKAndPublish)
			end
		end)
	end

	net.Receive("vrmod_pmchange", function()
		local sid = net.ReadString()
		local model = net.ReadString()
		local ply = player.GetBySteamID(sid)
		if not IsValid(ply) then return end
		if ply == LocalPlayer() then
			ReloadLocalPM(ply, model, "pmchange_net")
		else
			ply.vrmod_pm = model
		end
	end)

	-- Backup: some clients change PM without server SetModel (or net lost).
	-- Poll while VR is active; only fire on real path change.
	local lastPM = ""
	timer.Create("vrmod_pmchange_poll", 0.5, 0, function()
		if not cv_allow:GetBool() then return end
		if not (g_VR and g_VR.active) then
			lastPM = ""
			return
		end
		local ply = LocalPlayer()
		if not IsValid(ply) then return end
		local m = ply.vrmod_pm or ply:GetModel() or ""
		if g_VR._avatarApplyPath and CurTime() < (g_VR._avatarApplyUntil or 0) then
			m = g_VR._avatarApplyPath
		end
		if m == "" or m == lastPM then return end
		-- First sample after VR start: seed only
		if lastPM == "" then
			lastPM = m
			return
		end
		lastPM = m
		ReloadLocalPM(ply, m, "pmchange_poll")
	end)
end
