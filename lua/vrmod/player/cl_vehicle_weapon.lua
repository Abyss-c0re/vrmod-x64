-- Vehicle gun keep (client): rebind viewmodel only — never SelectWeapon
-- (reselect redeploys ArcVR → CS mag wipe + model flash).
if SERVER then return end

local function RebindActiveGun()
	local ply = LocalPlayer()
	if not IsValid(ply) or not g_VR or not g_VR.active then return end
	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) then return end
	local c = wep:GetClass()
	if not c or c == "" or c == "weapon_vrmod_empty" then return end
	wep:SetNoDraw(true)
	local vm = ply:GetViewModel()
	if IsValid(vm) then
		vm:SetNoDraw(false)
		g_VR.viewModel = vm
	end
	if vrmod.utils and vrmod.utils.UpdateViewModelPos then
		pcall(vrmod.utils.UpdateViewModelPos)
	end
end

hook.Add("VRMod_EnterVehicle", "vrmod_vehicle_weapon", function()
	-- antiDrop is set in cl_input before action sets; only rebind pose here
	timer.Simple(0.3, RebindActiveGun)
	timer.Simple(0.8, RebindActiveGun)
end)

hook.Add("VRMod_ExitVehicle", "vrmod_vehicle_weapon", function()
	-- Cleanup already sets antiDrop before action-set switch
	timer.Simple(0.25, RebindActiveGun)
	timer.Simple(0.7, RebindActiveGun)
end)
