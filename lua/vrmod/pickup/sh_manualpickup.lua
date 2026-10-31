local vrmod_manualpickup = CreateConVar("vrmod_manualpickups", 1, {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "vrmod manual pickup toggle")
-- Per-player states
local PickupDisabled = {}
local PickupDisabledWeapons = {}
-- Initialize pickup states on spawn
hook.Add("PlayerSpawn", "SpawnSetPickupState", function(ply)
	local id = ply:EntIndex()
	PickupDisabled[id] = true
	PickupDisabledWeapons[id] = true
end)

-- Set player as VR when entering VRMod
hook.Add("VRMod_Start", "VRModPickupStartState", function(ply)
	ply:SetNWBool("IsVR", true)
	local id = ply:EntIndex()
	PickupDisabled[id] = true
	PickupDisabledWeapons[id] = true
end)

-- Clear VR state when exiting VRMod
hook.Add("VRMod_Exit", "VRModPickupResetState", function(ply)
	ply:SetNWBool("IsVR", false)
	local id = ply:EntIndex()
	PickupDisabled[id] = nil
	PickupDisabledWeapons[id] = nil
end)

-- Fix VR state loss after respawn
timer.Create("VRModManualPickup_RespawnFixTimer", 1, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() and ply:GetNWBool("IsVR", false) then
			local id = ply:EntIndex()
			if PickupDisabled[id] == nil then
				PickupDisabled[id] = true
				PickupDisabledWeapons[id] = true
			end
		end
	end
end)

-- Handle item drop to allow manual pickup
hook.Add("VRMod_Drop", "ManualItemPickupDropHook", function(ply, ent)
	if not IsValid(ent) then return end
	if ent:GetClass() == "prop_physics" then return end
	local id = ply:EntIndex()
	PickupDisabled[id] = false
	timer.Simple(0.3, function() if IsValid(ply) then PickupDisabled[id] = true end end)
end)

-- Handle weapon pickup by hand.
-- Server only. ply.PickupWeapon is never set, so a guard on it skipped the
-- whole restore and the dropped mag never came back.
hook.Add("VRMod_Pickup", "ManualWeaponPickupHook", function(ply, ent)
	if not SERVER then return end
	if not IsValid(ply) or not ply:IsPlayer() then return end
	if not IsValid(ent) or not ent:IsWeapon() then return end
	-- Copy before ReplaceWeapon / Remove. The ground entity is gone next tick.
	local U = vrmod.utils
	local snap = nil
	if ent.ArcticVR and U then
		snap = (U.ArcVrDrop_CloneState and U.ArcVrDrop_CloneState(ent.avrSnapshot))
			or (U.ArcVrDrop_CopyState and U.ArcVrDrop_CopyState(ent))
	end
	local wepClass = ent:GetClass()
	-- Temporarily disable pickup protection
	hook.Call("VRMod_Drop", nil, ply, ent)
	-- Try to replace with VR weapon
	local replacement = U and U.ReplaceWeapon and U.ReplaceWeapon(ply, ent)
	if replacement then wepClass = replacement end

	local function push()
		if not IsValid(ply) or not snap then return end
		do
			local mag = snap.Magazine
			if type(mag) ~= "string" then mag = "" end
			local firemode = math.floor(tonumber(snap.Firemode) or 0)
			if firemode < -128 then firemode = -128 elseif firemode > 127 then firemode = 127 end
			net.Start("vrmod_arcvr_restore")
			net.WriteString(mag)
			net.WriteString(wepClass)
			net.WriteUInt(math.min(math.floor(tonumber(snap.LoadedRounds) or 0), 65535), 16)
			net.WriteUInt(math.min(math.floor(tonumber(snap.Chambered) or 0), 255), 8)
			net.WriteUInt(math.min(math.floor(tonumber(snap.EmptyChambered) or 0), 255), 8)
			net.WriteBool(snap.SlideLockedBack and true or false)
			net.WriteInt(firemode, 8)
			net.Send(ply)
		end
		local newWep = ply:GetWeapon(wepClass)
		if not IsValid(newWep) or not newWep.ArcticVR then return end
		if U and U.ArcVrDrop_ApplyState then
			U.ArcVrDrop_ApplyState(newWep, snap)
		else
			newWep.LoadedRounds = snap.LoadedRounds
			newWep.Chambered = snap.Chambered
			newWep.Magazine = snap.Magazine
		end
		if newWep.SendWeapon then pcall(newWep.SendWeapon, newWep, true, true) end
	end

	if ply:HasWeapon(wepClass) then
		if not snap and IsValid(ent) then
			local ammoType = ent:GetPrimaryAmmoType()
			local clip = ent:Clip1()
			if ammoType >= 0 and clip > 0 then ply:GiveAmmo(clip, ammoType, true) end
		end
		ply:SelectWeapon(wepClass)
	else
		-- Touch-pickup ban also rejects Player:Give when the new SWEP is not
		-- yet at the player's feet. This give is the hand equip.
		ply._vrmodForceWeaponGive = true
		ply:Give(wepClass, true)
		ply._vrmodForceWeaponGive = nil
		timer.Simple(0, function() if IsValid(ply) then ply:SelectWeapon(wepClass) end end)
	end

	push()
	timer.Simple(0, push)
	timer.Simple(0.25, push)
	-- Entity may not exist on the client for the first sends.
	timer.Simple(1, push)

	if IsValid(ent) and ent:GetOwner() ~= ply then ent:Remove() end
	-- Equipped. Do not also physics-hold the entity we just removed.
	return false
end)

-- Disable touch-based item pickup
hook.Add("PlayerCanPickupItem", "ItemTouchPickupDisablerVR", function(ply, item)
	local id = ply:EntIndex()
	if vrmod_manualpickup:GetBool() and item:GetClass() ~= "item_suit" and PickupDisabled[id] and ply:GetNWBool("IsVR", false) then return false end
	return true
end)

-- Disable touch-based weapon pickup
hook.Add("PlayerCanPickupWeapon", "WeaponTouchPickupDisablerVR", function(ply, wep)
	if ply._vrmodForceWeaponGive then return true end
	local id = ply:EntIndex()
	if vrmod_manualpickup:GetBool() and wep:GetPos() ~= ply:GetPos() and PickupDisabledWeapons[id] and ply:GetNWBool("IsVR", false) then return false end
end)