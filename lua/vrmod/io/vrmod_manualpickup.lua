print ("running vrmod manual item pickup") 	-- tells me that the script is running so i can sleep at night
											-- there are going to be comments everywhere
											-- this is a different take on the same addon, now with hopefully cleaner and more efficient code
local vrmod_manualpickup = CreateConVar( "vrmod_manualpickups", 1, { FCVAR_ARCHIVE,FCVAR_REPLICATED }, "vrmod manual pickup toggle" ) -- creates the convar so it can be turned on or off (default on)


IsVR = false -- bugfix breaks after respawn
hook.Add ("PlayerSpawn", "SpawnSetPickupState", function (ply)		-- sets the initial state of the addon, aswell as excluding non-VR players from being affected
	PickupDisabled = true
	PickupDisabledWeapons = true
	
end)

hook.Add ("VRMod_Start", "VRModPickupStartState", function (ply)	-- this gets called when a player enters VR, so this addon only affects VR players (important in multiplayer)
		IsVR = true
end)

hook.Add ("VRMod_Exit", "VRModPickupResetState", function (ply)		-- returns a player's status back to non-VR when exiting VRMod
		IsVR = false
end)

hook.Add ( "VRMod_Drop", "ManualItemPickupDropHook", function (ply, ent)
	if not IsValid(ent) then return end		-- the heart of the addon; sets 'PickupDisabled' to 'false' when releasing an item, thus picking it up instantly
	if ent:GetClass() == "prop_physics" then return end							-- then returns the value back to its base state of 'true'
		PickupDisabled = false
		timer.Simple (0.3, function() print ("here point five")

		PickupDisabled = true

	end)
end)

hook.Add ( "VRMod_Pickup", "ManualWeaponPickupHook", function (ply, ent)
	if not IsValid(ent) then return end		-- this is the same thing as above, but for weapons, and one small difference - it's triggered immediately upon touching the weapon, rather then dropping it
	if ent:IsWeapon() == true then												-- this was requested by a user in the addon comments, and i agree that it seems better to pick a weapon up as soon as you grab it rather than releasing it
		equipgun = ent:GetClass()
		hook.Call("VRMod_Drop", nil, ply, ent) -- bugfix: picking up weapons with prop togther
		if not IsValid(ent) then return end
		ply:PickupWeapon(ent)
	ply:SelectWeapon(equipgun)
	
	end
	end)


hook.Add ("PlayerCanPickupItem", "ItemTouchPickupDisablerVR", function( ply, item )												-- this hook is important - it controls if a player can pickup items by touching them
if vrmod_manualpickup:GetBool() and item:GetClass() != "item_suit" and PickupDisabled == true and IsVR == true then				-- this part turns it off - the 'GetBool' part checks if the console corresponding convar is true (boolean means true or false) 
	return false																												-- if it's true, touch-item pickup is disabled (thats what return false does)
else return true 																												-- another note; 'item:GetClass() != "item_suit"' means if the item is an HEV suit, then it doesn't count - so you can still pick it up by touching
end																																																					-- because manually picking up an HEV suit wouldn't make sense
end)

hook.Add ( "PlayerCanPickupWeapon", "WeaponTouchPickupDisablerVR", function( ply, wep )											--does the same thing for weapons as for items
	if vrmod_manualpickup:GetBool() and wep:GetPos() != ply:GetPos() and PickupDisabledWeapons == true and IsVR == true then
	return false
end
end)