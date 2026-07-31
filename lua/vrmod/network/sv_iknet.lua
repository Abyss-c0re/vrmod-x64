-- =============================================================================
-- vrmod.iknet server — bind NPC entities to VR player IK stream (clients apply)
--
-- Server does not run charik (client SoT). It only:
--   • authorizes mimic binds
--   • relays ent + source steamid to clients
--   • optional: mark NW for autotest without player
-- =============================================================================
if CLIENT then return end

util.AddNetworkString("vrmod_iknet_bind")

vrmod = vrmod or {}
vrmod.iknet = vrmod.iknet or {}
local binds = {} -- [entIndex] = { source = steamid|"local", train = bool }

local function BroadcastBind(ent, source, train)
	if not IsValid(ent) then return end
	net.Start("vrmod_iknet_bind")
	net.WriteEntity(ent)
	net.WriteString(source or "stop")
	net.WriteBool(train and true or false)
	net.Broadcast()
end

function vrmod.iknet.BindNPC(ent, source, train)
	if not IsValid(ent) then return false, "bad ent" end
	source = source or "local"
	binds[ent:EntIndex()] = { source = source, train = train and true or false, ent = ent }
	ent:SetNWString("vrmod_iknet_src", source)
	ent:SetNWBool("vrmod_iknet_train", train and true or false)
	BroadcastBind(ent, source, train)
	return true
end

function vrmod.iknet.UnbindNPC(ent)
	if not IsValid(ent) then return end
	binds[ent:EntIndex()] = nil
	ent:SetNWString("vrmod_iknet_src", "")
	ent:SetNWBool("vrmod_iknet_train", false)
	BroadcastBind(ent, "stop", false)
end

--- Spawn a citizen and bind to first VR player (or steamid).
function vrmod.iknet.SpawnMimic(ply, steamid, train)
	local pos = IsValid(ply) and (ply:GetPos() + ply:GetForward() * 80) or Vector(0, 0, 0)
	local ang = IsValid(ply) and ply:GetAngles() or Angle()
	ang.p, ang.r = 0, 0
	local npc = ents.Create("npc_citizen")
	if not IsValid(npc) then return nil end
	npc:SetPos(pos + Vector(0, 0, 10))
	npc:SetAngles(ang)
	npc:Spawn()
	npc:Activate()
	npc:SetNPCState(NPC_STATE_IDLE)
	if npc.SetSchedule then npc:SetSchedule(SCHED_IDLE_STAND) end
	-- Prefer freeze locomotion so IK owns upper body
	npc:SetMoveType(MOVETYPE_NONE)
	local src = steamid
	if not src or src == "" then
		if IsValid(ply) then
			src = ply:SteamID()
		else
			src = "local"
		end
	end
	vrmod.iknet.BindNPC(npc, src, train)
	return npc
end

concommand.Add("vrmod_iknet_bind", function(ply, cmd, args)
	if IsValid(ply) and not ply:IsSuperAdmin() and not game.SinglePlayer() then return end
	local idx = tonumber(args[1] or "")
	local source = args[2] or (IsValid(ply) and ply:SteamID() or "local")
	local train = args[3] == "1" or args[3] == "train"
	local ent = idx and Entity(idx) or nil
	if not IsValid(ent) and IsValid(ply) then
		ent = ply:GetEyeTrace().Entity
	end
	if not IsValid(ent) then
		if IsValid(ply) then ply:ChatPrint("[iknet] aim NPC or pass entindex") end
		return
	end
	vrmod.iknet.BindNPC(ent, source, train)
	if IsValid(ply) then
		ply:ChatPrint(string.format("[iknet] bound %s → %s train=%s", ent:EntIndex(), source, tostring(train)))
	end
	vrmod.logger.Info("[iknet] bind ent=%s src=%s train=%s", ent:EntIndex(), source, train)
end)

concommand.Add("vrmod_iknet_unbind", function(ply, cmd, args)
	if IsValid(ply) and not ply:IsSuperAdmin() and not game.SinglePlayer() then return end
	local idx = tonumber(args[1] or "")
	local ent = idx and Entity(idx) or (IsValid(ply) and ply:GetEyeTrace().Entity)
	if IsValid(ent) then
		vrmod.iknet.UnbindNPC(ent)
		vrmod.logger.Info("[iknet] unbound %s", ent:EntIndex())
	end
end)

concommand.Add("vrmod_iknet_spawn", function(ply, cmd, args)
	if IsValid(ply) and not ply:IsSuperAdmin() and not game.SinglePlayer() then return end
	local train = args[1] == "train" or args[1] == "1"
	local src = args[2]
	local npc = vrmod.iknet.SpawnMimic(ply, src, train)
	if IsValid(npc) then
		local msg = "[iknet] spawned mimic ent=" .. npc:EntIndex()
		vrmod.logger.Info("%s", msg)
		if IsValid(ply) then ply:ChatPrint(msg) end
	end
end)

-- Re-broadcast binds to late joiners
hook.Add("PlayerInitialSpawn", "vrmod_iknet_rebind", function(ply)
	timer.Simple(3, function()
		if not IsValid(ply) then return end
		for _, b in pairs(binds) do
			if IsValid(b.ent) then
				net.Start("vrmod_iknet_bind")
				net.WriteEntity(b.ent)
				net.WriteString(b.source or "stop")
				net.WriteBool(b.train)
				net.Send(ply)
			end
		end
	end)
end)

hook.Add("EntityRemoved", "vrmod_iknet_cleanup", function(ent)
	if binds[ent:EntIndex()] then
		binds[ent:EntIndex()] = nil
	end
end)

vrmod.logger.Info("[iknet] server ready — vrmod_iknet_spawn [train] [steamid]")
