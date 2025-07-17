if SERVER then
    util.AddNetworkString("VRWeps_Notify")
    VRWeps = {}
    VRWeps.Replacer = {}
    local datafile = "vrmod/vrmod_weapon_replacement.txt"
    local convar_enabled = CreateConVar("vrmod_weapon_swap", "1", FCVAR_ARCHIVE, "Enable or disable VR weapon replacement logic")
    -- Default list used if file doesn't exist
    local defaultWeaponPairs = {
        ["weapon_crowbar"] = "arcticvr_hl2_crowbar",
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


    -- Load from file or generate default
    function VRWeps.LoadPairs()
        if not file.Exists(datafile, "DATA") then
            print("[VRWeps] No file found — generating default list.")
            file.CreateDir("vrmod") -- ensure directory exists
            file.Write(datafile, util.TableToJSON(defaultWeaponPairs, true))
        end

        local content = file.Read(datafile, "DATA")
        local decoded = util.JSONToTable(content) or {}
        VRWeps.Replacer = decoded
        print("[VRWeps] Loaded", table.Count(VRWeps.Replacer), "weapon replacement pairs.")
    end

    -- Save current table
    function VRWeps.SavePairs()
        file.Write(datafile, util.TableToJSON(VRWeps.Replacer, true))
    end

    -- Add new pair via code or concommand
    function VRWeps.AddPair(flat, vr)
        VRWeps.Replacer[flat] = vr
        VRWeps.SavePairs()
        print("[VRWeps] Added:", flat, "→", vr)
    end

    -- ConCommand to add a replacement pair
    concommand.Add("vrweps_addreplace", function(ply, cmd, args)
        if IsValid(ply) and not ply:IsAdmin() then
            ply:ChatPrint("You must be admin to use this.")
            return
        end

        if #args < 2 then
            print("Usage: vrweps_addreplace <flat_weapon> <vr_weapon>")
            return
        end

        VRWeps.AddPair(args[1], args[2])
    end)

    -- Replace all weapons on VR start
    hook.Add("VRMod_Start", "VRWeps_ReplaceOnVRStart", function(ply)
        if not IsValid(ply) or not convar_enabled:GetBool() then return end
        timer.Simple(0.1, function()
            if not IsValid(ply) then return end
            for _, wep in pairs(ply:GetWeapons()) do
                local class = wep:GetClass()
                local vrClass = VRWeps.Replacer[class]
                if vrClass and weapons.GetStored(vrClass) then
                    ply:Give(vrClass, true)
                    if engine.ActiveGamemode() ~= "lambda" then ply:StripWeapon(class) end
                elseif vrClass then
                    print("[VRWeps] Missing VR weapon:", vrClass, "for", class)
                end
            end
        end)
    end)

    -- Restore flatscreen weapons on VR exit
    hook.Add("VRMod_Exit", "VRWeps_RestoreOnVRExit", function(ply)
        if not IsValid(ply) or not convar_enabled:GetBool() then return end
        for _, wep in pairs(ply:GetWeapons()) do
            local class = wep:GetClass()
            local flatClass = table.KeyFromValue(VRWeps.Replacer, class)
            if flatClass and weapons.GetStored(flatClass) then
                ply:Give(flatClass, true)
                ply:StripWeapon(class)
            elseif flatClass then
                print("[VRWeps] Missing flat weapon:", flatClass, "to restore from", class)
            end
        end
    end)

    function VRWeps.ReplaceWeaponEntity(ply, wep)
        if not IsValid(ply) or not IsValid(wep) then return false end
        if not convar_enabled:GetBool() then return false end
        if not vrmod.IsPlayerInVR(ply) then return false end
        local class = wep:GetClass()
        local vrClass = VRWeps.Replacer[class]
        if not vrClass then return false end
        if not weapons.GetStored(vrClass) then
            print("[VRWeps] Missing VR weapon:", vrClass, "for", class)
            return false
        end

        local given = ply:Give(vrClass, true)
        if IsValid(given) then
            wep:Remove()
            ply:SelectWeapon(vrClass)
            print("[VRWeps] Replaced weapon:", class, "→", vrClass)
            return true
        else
            -- Retry give in 0.3s if something failed
            timer.Simple(0.3, function()
                if not IsValid(ply) then return end
                local retried = ply:Give(vrClass, true)
                if IsValid(retried) then
                    if IsValid(wep) then wep:Remove() end
                    ply:SelectWeapon(vrClass)
                    print("[VRWeps] Gave VR weapon on retry:", vrClass)
                else
                    print("[VRWeps] Failed to give VR weapon:", vrClass, "for", class)
                end
            end)
            return false
        end
    end

    -- On init, load weapon pairs
    hook.Add("Initialize", "VRWeps_LoadPairsOnStartup", function() VRWeps.LoadPairs() end)
end
-- if SERVER