--[[
	Track playermodel changes so VR character IK + avatar twin rebuild without respawn.

	Also works around addons that break client player:GetModel() (e.g. PAC3) by
	storing the last known path on ply.vrmod_pm.
]]

if SERVER then
	util.AddNetworkString("vrmod_pmchange")

	local function NotifyPM(ply, model)
		if not IsValid(ply) or not ply:IsPlayer() then return end
		model = tostring(model or "")
		if model == "" then return end
		net.Start("vrmod_pmchange")
		net.WriteString(ply:SteamID())
		net.WriteString(model)
		net.Broadcast()
	end

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
		-- Refuse incomplete skeletons — keep last good VR model if available
		if model ~= "" and vrmod.character and vrmod.character.ValidatePlayerModel then
			local okPm, _miss, why = vrmod.character.ValidatePlayerModel(model)
			if not okPm then
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
		ply.vrmod_pm = model
		if ply == LocalPlayer() then
			ReloadLocalPM(ply, model, "pmchange_net")
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
