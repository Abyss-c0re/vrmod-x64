AddCSLuaFile()
if SERVER then
    local blacklist_path = "vrmod_blacklist.txt"
    -- Default blacklist values
    local default_blacklist = {"weapon_fists", "piss_swep", "weapon_bsmod_punch", "weapon_vrmod_empty", "weapon_haax_vr", "alex_matrix_stopbullets", "blink", "spartan_kick", "arcticvr_nade_frag", "arcticvr_nade_flash", "arcticvr_nade_smoke"}
    -- Ensure file exists and load blacklist
    local blacklist = {}
    if not file.Exists(blacklist_path, "DATA") then
        file.Write(blacklist_path, table.concat(default_blacklist, "\n"))
        blacklist = default_blacklist
    else
        local content = file.Read(blacklist_path, "DATA") or ""
        for line in string.gmatch(content, "[^\r\n]+") do
            table.insert(blacklist, string.Trim(line))
        end
    end

    -- Lookup function
    local function InBlackList(weaponClass)
        local path = blacklist_path
        if not file.Exists(path, "DATA") then return false end
        local content = file.Read(path, "DATA") or ""
        for line in string.gmatch(content, "[^\r\n]+") do
            if string.Trim(line) == weaponClass then return true end
        end
        return false
    end

    util.AddNetworkString("ChangeWeapon")
    util.AddNetworkString("DropWeapon")
    util.AddNetworkString("SelectEmptyWeapon")
    net.Receive("ChangeWeapon", function(len, ply)
        local weaponClass = net.ReadString(8)
        ply:SelectWeapon(weaponClass)
    end)

    net.Receive("SelectEmptyWeapon", function(len, ply) ply:SelectWeapon("weapon_vrmod_empty") end)
    net.Receive("DropWeapon", function(len, ply)
        local wepdropmode = net.ReadBool()
        local rhandvel = net.ReadVector()
        local rhandangvel = net.ReadVector()
        local wep = ply:GetActiveWeapon()
        if IsValid(wep) and not ply:InVehicle() and not InBlackList(wep:GetClass()) then
            local modelname = wep:GetModel()
            local guninhandpos = vrmod.GetRightHandPos(ply)
            local guninhandang = vrmod.GetRightHandAng(ply)
            wep.VR_Pickup_Tag = false
            if wepdropmode then
                Wwep = ents.Create(wep:GetClass())
            else
                Wwep = ents.Create("prop_physics")
            end

            local wep = ply:GetActiveWeapon()
            if wep:IsValid() then
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
            end

            ply:Give("weapon_vrmod_empty")
            Wwep:SetModel(modelname)
            ply:LookupBone("ValveBiped.Bip01_R_Hand")
            local Bon, BonAng = ply:GetBonePosition(11)
            Wwep:SetPos(guninhandpos + BonAng:Forward() * 10 - BonAng:Up() * 0 + BonAng:Right() * 4)
            Wwep:SetAngles(guninhandang)
            Wwep:SetModel(wep:GetModel())
            Wwep:Spawn()
            local phys = Wwep:GetPhysicsObject()
            if phys and phys:IsValid() then
                phys:Wake()
                phys:SetMass(99)
                phys:SetVelocity(ply:GetVelocity() + rhandvel)
                phys:AddAngleVelocity(-phys:GetAngleVelocity() + phys:WorldToLocalVector(rhandangvel))
            end

            if wepdropmode then ply:StripWeapon(ply:GetActiveWeapon():GetClass()) end
            ply:Give("weapon_vrmod_empty")
            ply:SelectWeapon("weapon_vrmod_empty")
            timer.Simple(3, function() if IsValid(Wwep) and Wwep:GetClass() == "prop_physics" then Wwep:Remove() end end)
        end
    end)
end

concommand.Add("vrmod_toggle_blacklist", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then
        ply:ChatPrint("[VRMod] No active weapon to toggle in blacklist.")
        return
    end

    local class = wep:GetClass()
    local path = "vrmod_blacklist.txt"
    -- Read file lines into a table
    local lines = {}
    if file.Exists(path, "DATA") then
        for line in string.gmatch(file.Read(path, "DATA") or "", "[^\r\n]+") do
            table.insert(lines, string.Trim(line))
        end
    end

    -- Determine action
    for i, v in ipairs(lines) do
        if v == class then
            table.remove(lines, i)
            file.Write(path, table.concat(lines, "\n"))
            ply:ChatPrint("[VRMod] Removed '" .. class .. "' from blacklist.")
            return
        end
    end

    -- If not found, add
    table.insert(lines, class)
    file.Write(path, table.concat(lines, "\n"))
    ply:ChatPrint("[VRMod] Added '" .. class .. "' to blacklist.")
end)

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
            return
        end
    end)
end