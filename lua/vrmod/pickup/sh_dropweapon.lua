local blacklist_path = "vrmod/vrmod_drop_blacklist.txt"
-- Shared blacklist check
local function InBlackList(weaponClass)
    if weaponClass == "weapon_vrmod_empty" then
        return true
    end
    if not file.Exists(blacklist_path, "DATA") then return false end
    local content = file.Read(blacklist_path, "DATA") or ""
    for line in string.gmatch(content, "[^\r\n]+") do
        if string.Trim(line) == weaponClass then return true end
    end
    return false
end

if SERVER then
    -- Create blacklist file with defaults if missing
    if not file.Exists(blacklist_path, "DATA") then
        local default_blacklist = {"weapon_fists", "piss_swep", "weapon_bsmod_punch", "weapon_vrmod_empty", "weapon_haax_vr", "alex_matrix_stopbullets", "blink", "spartan_kick", "arcticvr_nade_frag", "arcticvr_nade_flash", "arcticvr_nade_smoke"}
        file.Write(blacklist_path, table.concat(default_blacklist, "\n"))
    end

    util.AddNetworkString("ChangeWeapon")
    util.AddNetworkString("DropWeapon")
    util.AddNetworkString("SelectEmptyWeapon")
    net.Receive("ChangeWeapon", function(_, ply)
        local weaponClass = net.ReadString()
        if weaponClass and isstring(weaponClass) then ply:SelectWeapon(weaponClass) end
    end)

    net.Receive("SelectEmptyWeapon", function(_, ply) ply:SelectWeapon("weapon_vrmod_empty") end)
    net.Receive("DropWeapon", function(_, ply)
        local dropAsWeapon = net.ReadBool()
        local rhandvel = net.ReadVector()
        local rhandangvel = net.ReadVector()
        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) or wep.undroppable or ply:InVehicle() or InBlackList(wep:GetClass()) then return end
        local modelname = wep:GetModel()
        local guninhandpos = vrmod.GetRightHandPos(ply)
        local guninhandang = vrmod.GetRightHandAng(ply)
        local dropEnt
        if dropAsWeapon then
            dropEnt = ents.Create(wep:GetClass())
        else
            dropEnt = ents.Create("prop_physics")
        end

        -- Restore some ammo into dropped weapon if applicable
        local ammoType = wep:GetPrimaryAmmoType()
        local ammoCount = ply:GetAmmoCount(ammoType)
        local clipSize = wep:GetMaxClip1()
        local currentClip = wep:Clip1()
        if ammoCount > 0 and currentClip < clipSize then
            local ammoNeeded = clipSize - currentClip
            local ammoToGive = math.min(ammoNeeded, ammoCount)
            wep:SetClip1(currentClip + ammoToGive)
            ply:RemoveAmmo(ammoToGive, ammoType)
        end

        ply:Give("weapon_vrmod_empty")
        ply:SelectWeapon("weapon_vrmod_empty")
        local boneID = ply:LookupBone("ValveBiped.Bip01_R_Hand")
        local boneAng = boneID and select(2, ply:GetBonePosition(boneID)) or guninhandang
        dropEnt:SetModel(modelname)
        dropEnt:SetPos(guninhandpos + boneAng:Forward() * 10 + boneAng:Right() * 4)
        dropEnt:SetAngles(guninhandang)
        dropEnt:Spawn()
        local phys = dropEnt:GetPhysicsObject()
        if IsValid(phys) then
            phys:Wake()
            phys:SetMass(99)
            phys:SetVelocity(ply:GetVelocity() + rhandvel)
            phys:AddAngleVelocity(-phys:GetAngleVelocity() + phys:WorldToLocalVector(rhandangvel))
        end

        if dropAsWeapon then ply:StripWeapon(wep:GetClass()) end
        timer.Simple(3, function() if IsValid(dropEnt) and dropEnt:GetClass() == "prop_physics" then dropEnt:Remove() end end)
    end)

    concommand.Add("vrmod_toggle_blacklist", function(ply)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) then
            ply:ChatPrint("[VRMod] No active weapon to toggle in blacklist.")
            return
        end

        local class = wep:GetClass()
        local lines = {}
        if file.Exists(blacklist_path, "DATA") then
            for line in string.gmatch(file.Read(blacklist_path, "DATA") or "", "[^\r\n]+") do
                table.insert(lines, string.Trim(line))
            end
        end

        for i, v in ipairs(lines) do
            if v == class then
                table.remove(lines, i)
                file.Write(blacklist_path, table.concat(lines, "\n"))
                ply:ChatPrint("[VRMod] Removed '" .. class .. "' from blacklist.")
                return
            end
        end

        table.insert(lines, class)
        file.Write(blacklist_path, table.concat(lines, "\n"))
        ply:ChatPrint("[VRMod] Added '" .. class .. "' to blacklist.")
    end)
end

if CLIENT then
    local dropenable = CreateClientConVar("vrmod_weapondrop_enable", 1, true, FCVAR_ARCHIVE, "", 0, 1)
    hook.Add("VRMod_Input", "Weapon_Drop", function(action, state)
        if not dropenable:GetBool() then return end
        if action == "boolean_right_pickup" and not state then
            net.Start("DropWeapon")
            net.WriteBool(true)
            net.WriteVector(vrmod.GetRightHandVelocity() * 2.5)
            net.WriteVector(vrmod.GetRightHandAngularVelocity() * 2.5)
            net.SendToServer()
        end
    end)
end