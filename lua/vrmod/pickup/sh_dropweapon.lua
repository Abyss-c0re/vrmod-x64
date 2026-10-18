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

local function WriteClientArcSnap(snap)
    local list = {}
    for i, name in pairs(snap.AttInstalled or {}) do
        if isnumber(i) and i >= 0 and i <= 255 then
            list[#list + 1] = { i, name or "" }
        end
    end
    table.sort(list, function(a, b) return a[1] < b[1] end)
    local n = #list
    if n > 64 then n = 64 end
    net.WriteUInt(math.min(snap.LoadedRounds or 0, 65535), 16)
    net.WriteUInt(math.min(snap.Chambered or 0, 255), 8)
    net.WriteUInt(math.min(snap.EmptyChambered or 0, 255), 8)
    net.WriteString(snap.Magazine or "")
    net.WriteBool(snap.SlideLockedBack and true or false)
    net.WriteInt(snap.Firemode or 0, 8)
    net.WriteUInt(n, 8)
    for i = 1, n do
        net.WriteUInt(list[i][1], 8)
        net.WriteString(list[i][2] or "")
    end
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

    -- Client ammo is what the player sees. Read it before any early return
    -- so a rejected drop still consumes the message.
    local function ReadClientArcSnap()
        if not net.ReadBool() then return nil end
        local snap = {
            LoadedRounds = net.ReadUInt(16),
            Chambered = net.ReadUInt(8),
            EmptyChambered = net.ReadUInt(8),
            Magazine = net.ReadString(),
            SlideLockedBack = net.ReadBool(),
            Firemode = net.ReadInt(8),
            AttInstalled = {},
        }
        if snap.Magazine == "" then snap.Magazine = nil end
        local n = net.ReadUInt(8)
        for i = 1, n do
            local idx = net.ReadUInt(8)
            local name = net.ReadString()
            if i <= 64 then snap.AttInstalled[idx] = name end
        end
        if vrmod.utils and vrmod.utils.ArcVrDrop_CloneState then
            return vrmod.utils.ArcVrDrop_CloneState(snap)
        end
        return snap
    end

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
        local clientSnap = ReadClientArcSnap()
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
        -- ArcVR ammo is LoadedRounds, not Clip1. Stuffing reserve into Clip1
        -- on drop deletes those rounds when the weapon is stripped.
        local refillClip = true
        if vrmod.utils and vrmod.utils.ArcVrDrop_ShouldRefillClip then
            refillClip = vrmod.utils.ArcVrDrop_ShouldRefillClip(wep)
        elseif wep.ArcticVR or wep.ArcticVRNade then
            refillClip = false
        end
        if refillClip then
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

        -- Prefer the client's live mag. Server fields lag rack/chamber.
        local avrSnapshot
        if dropAsWeapon and (wep.ArcticVR or clientSnap) then
            if clientSnap then
                avrSnapshot = clientSnap
            elseif vrmod.utils and vrmod.utils.ArcVrDrop_CopyState then
                avrSnapshot = vrmod.utils.ArcVrDrop_CopyState(wep)
            end
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
        -- Spawn/Initialize zeroes LoadedRounds. Write the mag onto the entity
        -- itself so a later pickup still has it after the table is cloned.
        if avrSnapshot and vrmod.utils and vrmod.utils.ArcVrDrop_ApplyState then
            vrmod.utils.ArcVrDrop_ApplyState(dropEnt, avrSnapshot)
            dropEnt.ArcticVR = true
        elseif avrSnapshot then
            dropEnt.ArcticVR = true
            dropEnt.avrSnapshot = avrSnapshot
            dropEnt.LoadedRounds = avrSnapshot.LoadedRounds or 0
            dropEnt.Chambered = avrSnapshot.Chambered or 0
            dropEnt.Magazine = avrSnapshot.Magazine
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
            if vrmod.RestoreDefaultHandAngles then vrmod.RestoreDefaultHandAngles() end
            local wep = LocalPlayer():GetActiveWeapon()
            local snap = vrmod.utils and vrmod.utils.ArcVrDrop_CopyState and vrmod.utils.ArcVrDrop_CopyState(wep) or nil
            net.Start("DropWeapon")
            net.WriteBool(true)
            net.WriteVector(vrmod.GetRightHandVelocity() * 2.5)
            net.WriteVector(vrmod.GetRightHandAngularVelocity() * 2.5)
            net.WriteBool(snap ~= nil)
            if snap then WriteClientArcSnap(snap) end
            net.SendToServer()
        end
    end)
end
