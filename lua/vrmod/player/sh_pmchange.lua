--[[

	this is a shitty temporary workaround for some addons breaking player:GetModel() on the client
	
	for example, clear a pac3 outfit that changed your player model, then change your pm normally using the default gmod player model selector
	and player:GetModel() will always return the old model no matter how many times you change pm

--]]
local cv_allowpmchg = CreateClientConVar("vrmod_pmchange", 1, true, FCVAR_ARCHIVE)
if CLIENT then
	if cv_allowpmchg:GetBool() then
		net.Receive("vrmod_pmchange", function()
			local ply = player.GetBySteamID(net.ReadString())
			local model = net.ReadString()
			if ply then ply.vrmod_pm = model end
		end)
	elseif SERVER then
		if cv_allowpmchg:GetBool() then
			util.AddNetworkString("vrmod_pmchange")
			hook.Add("InitPostEntity", "vrmod_pmchange", function()
				local og = getmetatable(Entity(0)).SetModel
				getmetatable(Entity(0)).SetModel = function(...)
					local args = {...}
					og(unpack(args))
					if args[1]:IsPlayer() then
						net.Start("vrmod_pmchange")
						net.WriteString(args[1]:SteamID())
						net.WriteString(args[2])
						net.Broadcast()
					end
				end
			end)
		end
	end
end