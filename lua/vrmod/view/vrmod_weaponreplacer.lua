if SERVER then
    util.AddNetworkString("VRWeps_Notify")
    local replacer = {}
    local originalWeapons = {}
    local datafile = "vrmod/vrmod_weapon_replacement.txt"
    local convar_enabled = CreateConVar("vrmod_weapon_swap", "1", FCVAR_ARCHIVE, "Enable or disable VR weapon replacement logic")
    local defaultWeaponPairs = {
        ["weapon_crowbar"] = "arcticvr_hl2_crowbar",
        ["weapon_stunstick"] = "arcticvr_hl2_stunstick",
        ["weapon_pistol"] = "arcticvr_hl2_pistol",
        ["weapon_357"] = "arcticvr_hl2_357",
        ["weapon_smg1"] = "arcticvr_hl2_smg1",
        ["weapon_ar2"] = "arcticvr_hl2_ar2",
        ["weapon_shotgun"] = "arcticvr_hl2_shotgun",
        ["weapon_crossbow"] = "arcticvr_hl2_crossbow",
        ["weapon_rpg"] = "arcticvr_hl2_rpg",
        ["weapon_vj_9mmpistol"] = "arcticvr_hl2_pistol",
        ["weapon_vj_357"] = "arcticvr_hl2_357",
        ["weapon_vj_hlr2_alyxgun"] = "arcticvr_hl2_alyxgun",
        ["weapon_vj_hlr2_csniper"] = "arcticvr_hl2_cmbsniper",
        ["weapon_vj_smg1q"] = "arcticvr_hl2_smg1",
        ["weapon_vj_ar2"] = "arcticvr_hl2_ar2",
        ["weapon_vj_spas12"] = "arcticvr_hl2_shotgun",
        ["weapon_vj_ak47"] = "arcticvr_ak47",
        ["weapon_vj_senassault"] = "arcticvr_ak47",
        ["weapon_vj_rpg"] = "arcticvr_rpg",
        ["weapon_vj_glock17"] = "arcticvr_aniv_glock",
        ["weapon_vj_senpistol"] = "arcticvr_aniv_glock",
        ["weapon_vj_senpistolcopgloc"] = "arcticvr_aniv_glock",
        ["weapon_vj_m16a1"] = "arcticvr_m4a1",
        ["weapon_vj_sendeagle"] = "arcticvr_aniv_deagle",
        ["weapon_vj_sensmg"] = "arcticvr_aniv_mac10",
        ["weapon_vj_sensmgcop"] = "arcticvr_mp5",
        ["css_aug"] = "arcticvr_aug",
        ["css_awp"] = "arcticvr_awm",
        ["css_ak47"] = "arcticvr_ak47",
        ["css_deagle"] = "arcticvr_aniv_deagle",
        ["css_dualellites"] = "arcticvr_aniv_m9",
        ["css_famas"] = "arcticvr_famas",
        ["css_57"] = "arcticvr_fiveseven",
        ["css_g3sg1"] = "arcticvr_g3sg1",
        ["css_galil"] = "arcticvr_galil",
        ["css_glock"] = "arcticvr_aniv_glock",
        ["css_knife"] = "arcticvr_knife",
        ["css_m4a1"] = "arcticvr_m4a1",
        ["css_mac10"] = "arcticvr_aniv_mac10",
        ["css_mp5"] = "arcticvr_mp5",
        ["css_p90"] = "arcticvr_p90",
        ["css_scout"] = "arcticvr_scout",
        ["css_sg550"] = "arcticvr_sg552q",
        ["css_sg552"] = "arcticvr_sg552",
        ["css_m3"] = "arcticvr_shorty",
        ["css_tmp"] = "arcticvr_aniv_tmp",
        ["css_ump45"] = "arcticvr_ump45",
        ["css_usp"] = "arcticvr_aniv_usptactical",
        ["css_xm1014"] = "arcticvr_m1014",
        ["weapon_haax"] = "weapon_haax_vr"
    }

    local function SavePairs()
        file.Write(datafile, util.TableToJSON(replacer, true))
    end

    local function LoadPairs()
        if not file.Exists(datafile, "DATA") then
            print("[VRWeps] No file found — writing default table.")
            file.Write(datafile, util.TableToJSON(defaultWeaponPairs, true))
            replacer = table.Copy(defaultWeaponPairs)
            return
        end

        local raw = file.Read(datafile, "DATA")
        local tbl = util.JSONToTable(raw) or {}
        for flat, vr in pairs(defaultWeaponPairs) do
            if not tbl[flat] then
                print("[VRWeps] Adding missing default pair:", flat, "→", vr)
                tbl[flat] = vr
            end
        end

        replacer = tbl
        SavePairs()
        print("[VRWeps] Loaded", table.Count(replacer), "weapon pairs.")
    end

    local function AddPair(flat, vr)
        replacer[flat] = vr
        SavePairs()
        print("[VRWeps] Added pair:", flat, "→", vr)
    end

    local function ReplaceAllWeapons(ply)
        if not IsValid(ply) or not convar_enabled:GetBool() then return end
        if not vrmod.IsPlayerInVR(ply) then return end
        originalWeapons[ply:SteamID()] = {} -- track original weapons
        for _, wep in ipairs(ply:GetWeapons()) do
            local class = wep:GetClass()
            local vrClass = replacer[class]
            if vrClass and weapons.GetStored(vrClass) then
                table.insert(originalWeapons[ply:SteamID()], {
                    from = vrClass,
                    to = class
                })

                ply:Give(vrClass, true)
                if engine.ActiveGamemode() ~= "lambda" then ply:StripWeapon(class) end
            elseif vrClass then
                print("[VRWeps] Missing VR weapon:", vrClass, "for", class)
            end
        end
    end

    local function RestoreFlatWeapons(ply)
        if not IsValid(ply) or not convar_enabled:GetBool() then return end
        local sid = ply:SteamID()
        local stored = originalWeapons[sid]
        if not stored then return end
        for _, info in ipairs(stored) do
            if ply:HasWeapon(info.from) then
                ply:Give(info.to, true)
                ply:StripWeapon(info.from)
                print("[VRWeps] Restored:", info.to, "←", info.from)
            else
                print("[VRWeps] Player doesn't have VR weapon:", info.from)
            end
        end

        originalWeapons[sid] = nil
    end

    concommand.Add("vrweps_addreplace", function(ply, cmd, args)
        if IsValid(ply) and not ply:IsAdmin() then
            ply:ChatPrint("You must be admin to use this.")
            return
        end

        if #args < 2 then
            print("Usage: vrweps_addreplace <flat_weapon> <vr_weapon>")
            return
        end

        AddPair(args[1], args[2])
    end)

    -- Replace on VR start
    hook.Add("VRMod_Start", "VRWeps_ReplaceOnStart", function(ply) timer.Simple(0.1, function() ReplaceAllWeapons(ply) end) end)
    -- Restore on VR exit
    hook.Add("VRMod_Exit", "VRWeps_RestoreOnExit", function(ply) timer.Simple(0.1, function() RestoreFlatWeapons(ply) end) end)
    -- Replace on respawn
    hook.Add("PlayerSpawn", "VRWeps_ReplaceOnRespawn", function(ply) timer.Simple(0.1, function() ReplaceAllWeapons(ply) end) end)
    -- Load replacements at startup
    hook.Add("Initialize", "VRWeps_LoadPairs", function() LoadPairs() end)
end