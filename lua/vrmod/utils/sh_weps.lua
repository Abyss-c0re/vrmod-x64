g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}
vrmod.suppressViewModelUpdates = false
-- WEP UTILS
function vrmod.utils.IsValidWep(wep, get)
    if not IsValid(wep) then return false end
    local class = wep:GetClass()
    local vm
    vm = wep:GetWeaponViewModel()
    if class == "weapon_vrmod_empty" or vm == "" or vm == "models/weapons/c_arms.mdl" then return false end
    if get then
        return class, vm
    else
        return true
    end
end

function vrmod.utils.IsWeaponEntity(ent)
    if not IsValid(ent) then return false end
    local c = ent:GetClass()
    return ent:IsWeapon() or c:find("weapon_") or c == "prop_physics" and ent:GetModel():find("w_")
end

function vrmod.utils.WepInfo(wep)
    local class, vm = vrmod.utils.IsValidWep(wep, true)
    if class and vm then return class, vm end
end

function vrmod.utils.UpdateViewModelPos(pos, ang, override)
    local ply = LocalPlayer()
    if vrmod.suppressViewModelUpdates and not override then
        vrmod.utils.UpdateViewModel()
        return
    end

    pos, ang = vrmod.utils.CheckWeaponPushout(pos, ang)
    if not IsValid(ply) or not g_VR.active then return end
    if not ply:Alive() or ply:InVehicle() then return end
    local currentvmi = g_VR.currentvmi
    local modelPos = pos
    if currentvmi then
        local collisionShape = vrmod._collisionShapeByHand and vrmod._collisionShapeByHand.right
        if collisionShape and collisionShape.isClipped and collisionShape.pushOutPos then
            modelPos = collisionShape.pushOutPos
            vrmod.logger.Debug("[VRMod] Applying collision-corrected pos for viewmodel:", modelPos)
        end

        local offsetPos, offsetAng = LocalToWorld(currentvmi.offsetPos, currentvmi.offsetAng, modelPos, ang)
        g_VR.viewModelPos = offsetPos
        g_VR.viewModelAng = offsetAng
        vrmod.utils.UpdateViewModel()
    end
end

function vrmod.utils.UpdateViewModel()
    local vm = g_VR.viewModel
    if IsValid(vm) then
        if not g_VR.usingWorldModels then
            vm:SetPos(g_VR.viewModelPos)
            vm:SetAngles(g_VR.viewModelAng)
            vm:SetupBones()
        end

        g_VR.viewModelMuzzle = vm:GetAttachment(1)
    end
end