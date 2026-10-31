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

-- Handle weapon pickup by hand. Server only.
hook.Add("VRMod_Pickup", "ManualWeaponPickupHook", function(ply, ent)
	if not SERVER then return end
	if not IsValid(ply) or not ply:IsPlayer() then return end
	if not IsValid(ent) or not ent:IsWeapon() then return end

	-- Same entity that was dropped. Give() would spawn a blank gun and delete this one.
	if ent.ArcticVR or ent.ArcticVRNade then
		local class = ent:GetClass()
		if ply:HasWeapon(class) and ply:GetWeapon(class) ~= ent then return end
		ply._vrmodForceWeaponGive = true
		ply:PickupWeapon(ent)
		ply._vrmodForceWeaponGive = nil
		if ent:GetOwner() ~= ply then return end
		timer.Simple(0, function()
			if IsValid(ply) and IsValid(ent) then ply:SelectWeapon(class) end
		end)
		return false
	end

	local U = vrmod.utils
	local wepClass = ent:GetClass()
	hook.Call("VRMod_Drop", nil, ply, ent)
	local replacement = U and U.ReplaceWeapon and U.ReplaceWeapon(ply, ent)
	if replacement then wepClass = replacement end

	if ply:HasWeapon(wepClass) then
		if IsValid(ent) then
			local ammoType = ent:GetPrimaryAmmoType()
			local clip = ent:Clip1()
			if ammoType >= 0 and clip > 0 then ply:GiveAmmo(clip, ammoType, true) end
		end
		ply:SelectWeapon(wepClass)
	else
		ply._vrmodForceWeaponGive = true
		ply:Give(wepClass, true)
		ply._vrmodForceWeaponGive = nil
		timer.Simple(0, function() if IsValid(ply) then ply:SelectWeapon(wepClass) end end)
	end

	if IsValid(ent) and ent:GetOwner() ~= ply then ent:Remove() end
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