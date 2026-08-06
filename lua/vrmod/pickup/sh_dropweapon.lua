local blacklist_path = "vrmod/vrmod_drop_blacklist.txt"
-- Shared blacklist check
local function InBlackList(weaponClass)
    if weaponClass == "weapon_vrmod_empty" then return true end
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
        local default_blacklist = {"weapon_fists", "piss_swep", "weapon_bsmod_punch", "weapon_vrmod_empty", "weapon_haax_vr", "alex_matrix_stopbullets", "blink", "spartan_kick", "arcticvr_nade_frag", "arcticvr_nade_flash", "arcticvr_nade_smoke", "arcticvr_ins2_m84", "arcticvr_ins2_m18", "arcticvr_ins2_m67"}
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
    -- Block drops around vehicle enter/exit (action-set switch fires grip-release → gun becomes a prop)
    local vehicleDropBlockUntil = {}
    local function BlockVehicleDrop(ply, secs)
        if not IsValid(ply) then return end
        vehicleDropBlockUntil[ply] = CurTime() + (secs or 2)
    end
    hook.Add("PlayerEnteredVehicle", "vrmod_block_drop_vehicle", function(ply)
        BlockVehicleDrop(ply, 3)
    end)
    hook.Add("PlayerLeaveVehicle", "vrmod_block_drop_vehicle", function(ply)
        BlockVehicleDrop(ply, 2)
    end)

    net.Receive("DropWeapon", function(_, ply)
        local dropAsWeapon = net.ReadBool()
        local rhandvel = net.ReadVector()
        local rhandangvel = net.ReadVector()
        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) or wep.undroppable or InBlackList(wep:GetClass()) then return end
        if ply:InVehicle() then return end
        if ply.GlideGetVehicle then
            local ok, veh = pcall(function() return ply:GlideGetVehicle() end)
            if ok and IsValid(veh) then return end
        end
        local blockUntil = vehicleDropBlockUntil[ply]
        if blockUntil and CurTime() < blockUntil then return end
        local modelname = wep:GetModel()
        local guninhandpos = vrmod.GetRightHandPos(ply)
        local guninhandang = vrmod.GetRightHandAng(ply)
        local dropEnt
        if dropAsWeapon then
            dropEnt = ents.Create(wep:GetClass())
        else
            dropEnt = ents.Create("prop_physics")
        end

        if not IsValid(dropEnt) then return end
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

        -- ── ArcticVR snapshot ─────────────────────────
        local avrSnapshot
        if dropAsWeapon and wep.ArcticVR then
            avrSnapshot = {
                LoadedRounds = wep.LoadedRounds or 0,
                Chambered = wep.Chambered or 0,
                Magazine = wep.Magazine or nil,
                Attachments = wep.Attachments or nil
            }
        end

        -- ─────────────────────────────────────────────
        ply:Give("weapon_vrmod_empty")
        ply:SelectWeapon("weapon_vrmod_empty")
        local boneID = ply:LookupBone("ValveBiped.Bip01_R_Hand")
        local boneAng = boneID and select(2, ply:GetBonePosition(boneID)) or guninhandang
        dropEnt:SetModel(modelname)
        dropEnt:SetPos(guninhandpos + boneAng:Forward() * 10 + boneAng:Right() * 4)
        dropEnt:SetAngles(guninhandang)
        dropEnt:Spawn()
        -- ── Apply ArcticVR state AFTER spawn ─────────
        if avrSnapshot then
            dropEnt.ArcticVR = true
            dropEnt.avrSnapshot = avrSnapshot
        end

        -- ─────────────────────────────────────────────
        local phys = dropEnt:GetPhysicsObject()
        if IsValid(phys) then
            phys:Wake()
            phys:SetMass(99)
            phys:SetVelocity(ply:GetVelocity() + rhandvel)
            phys:AddAngleVelocity(-phys:GetAngleVelocity() + phys:WorldToLocalVector(rhandangvel))
        end

        if dropAsWeapon then ply:StripWeapon(wep:GetClass()) end
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
        if not dropenable:GetBool() or g_VR.antiDrop then return end
        -- Never drop while seated / transitioning (action sets spam grip edges)
        if g_VR.vehicle and (g_VR.vehicle.inside or g_VR.vehicle.driving) then return end
        local ply = LocalPlayer()
        if IsValid(ply) and ply:InVehicle() then return end
        if action == "boolean_right_pickup" and not state then
            net.Start("DropWeapon")
            net.WriteBool(true)
            net.WriteVector(vrmod.GetRightHandVelocity() * 2.5)
            net.WriteVector(vrmod.GetRightHandAngularVelocity() * 2.5)
            net.SendToServer()
        end
    end)

    hook.Add("Think", "ArcticVR_Drop_AttachmentCleanup", function()
        for _, wep in ipairs(ents.FindByClass("arcticvr_*")) do
            if IsValid(wep) and wep.ArcticVR and not IsValid(wep:GetOwner()) then
                wep:VRHolster()
                if wep.RebuildAttModels then wep:RebuildAttModels() end
            end
        end
    end)
end