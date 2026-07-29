g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}
vrmod.suppressViewModelUpdates = false
-- WEP UTILS
function vrmod.utils.CreateWorldModelVM(class, vmi)
    if not IsValid(g_VR.worldModelVM) then
        local model = vmi and vmi.modelOverride
        if not model then
            local wep = LocalPlayer():GetActiveWeapon()
            if IsValid(wep) then
                model = wep:GetModel()
            end
        end
        if not model or model == "" then return end

        g_VR.worldModelVM = ClientsideModel(model)
        if not IsValid(g_VR.worldModelVM) then return end
        g_VR.worldModelVM:SetNoDraw(false)
        local vm = LocalPlayer():GetViewModel()
        if IsValid(vm) then
            g_VR.worldModelVM:SetParent(vm) -- temporary parent
        end
        g_VR.worldModelVM:DrawShadow(false)
    end

    g_VR.viewModel = g_VR.worldModelVM
end

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
    if not c then return false end
    if ent:IsWeapon() or c:find("weapon_") then return true end
    -- Safe check for weapon models on prop_physics
    if c == "prop_physics" then
        local mdl = ent:GetModel()
        if mdl and mdl:find("w_") then return true end
    end
    return false
end

function vrmod.utils.WepInfo(wep)
    local class, vm = vrmod.utils.IsValidWep(wep, true)
    if class and vm then return class, vm end
end

--- Viewmodel is a pure slave of the (already modifier-resolved) right-hand pose.
--- Do NOT run a separate weapon pushout here — that was detaching the gun from the hand.
function vrmod.utils.UpdateViewModelPos(pos, ang, override)
    local ply = LocalPlayer()
    if vrmod.suppressViewModelUpdates and not override then
        vrmod.utils.UpdateViewModel()
        return
    end

    if not IsValid(ply) or not g_VR.active then return end
    if not ply:Alive() then return end
    local currentvmi = g_VR.currentvmi
    if not currentvmi then return end

    -- Prefer live tracking if caller forgot to pass post-modifier poses
    if (not pos or not ang) and g_VR.tracking and g_VR.tracking.pose_righthand then
        pos = g_VR.tracking.pose_righthand.pos
        ang = g_VR.tracking.pose_righthand.ang
    end
    if not pos or not ang then return end

    local offsetPos, offsetAng = LocalToWorld(currentvmi.offsetPos or Vector(), currentvmi.offsetAng or Angle(), pos, ang)
    g_VR.viewModelPos = offsetPos
    g_VR.viewModelAng = offsetAng
    vrmod.utils.UpdateViewModel()
end

function vrmod.utils.UpdateViewModel()
    local vm = g_VR.viewModel
    local vmi = g_VR.currentvmi
    if not IsValid(vm) then return end
    if vmi and vmi.useWorldModel then
        -- Always from final tracking (post wall/weapon modifiers)
        local handPos, handAng = vrmod.GetRightHandPose()
        local pos = handPos + handAng:Forward() * vmi.offsetPos.x + handAng:Right() * vmi.offsetPos.y + handAng:Up() * vmi.offsetPos.z
        local ang = handAng + vmi.offsetAng
        vm:SetPos(pos)
        vm:SetAngles(ang)
        vm:SetupBones()
    else
        vm:SetPos(g_VR.viewModelPos)
        vm:SetAngles(g_VR.viewModelAng)
        vm:SetupBones()
    end

    g_VR.viewModelMuzzle = vm:GetAttachment(1)
end