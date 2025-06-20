if CLIENT then return end
-- a modernized take on j2b2's ArcVR HL2 weapon giver, with (hopefully cleaner) code that properly removes the flatscreen weapons when you get your VR weapons
-- also with the feature of removing the VR weapons and giving you back the flatscreen weapons when exiting VR
-- Now with VJ and CSS weapons.
VRWeps = {}
VRWeps.Replacer = {
    ["weapon_crowbar"] = "vr_crowbar",
    ["weapon_pistol"] = "arcticvr_hl2_pistol",
    ["weapon_357"] = "arcticvr_hl2_357",
    ["weapon_smg1"] = "arcticvr_hl2_smg1",
    ["weapon_ar2"] = "arcticvr_hl2_ar2",
    ["weapon_shotgun"] = "arcticvr_hl2_shotgun",
    ["weapon_crossbow"] = "arcticvr_hl2_crossbow",
    ["weapon_rpg"] = "arcticvr_hl2_rpg",
    --VJ
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
    --CSS
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
    --random
    ["weapon_haax"] = "weapon_haax_vr",
}

-- replacing flatscreen weapons with vr weapons on vr startup
hook.Add("VRMod_Start", "WeaponReplacerVR", function(ply)
    for k, v in pairs(ply:GetWeapons()) do
        local WeaponType = v:GetClass()
        local VRWeaponType = VRWeps.Replacer[WeaponType]
        if VRWeaponType then
            ply:Give(VRWeaponType, true)
            if engine.ActiveGamemode() ~= "lambda" then ply:StripWeapon(WeaponType) end
        end
    end
end)

-- restoring flatscreen weapons when exiting vr
hook.Add("VRMod_Exit", "WeaponRestorerFlat", function(ply)
    for k, v in pairs(ply:GetWeapons()) do
        local WeaponType = v:GetClass()
        local VRWeaponType = table.KeyFromValue(VRWeps.Replacer, WeaponType)
        if VRWeaponType then
            ply:Give(VRWeaponType, true)
            ply:StripWeapon(WeaponType)
        end
    end
end)

hook.Add("PlayerInitialSpawn", "WeaponReplacerInitialState", function(ply) if IsValid(ply) then PlayerVR = false end end)
hook.Add("VRMod_Exit", "WeaponReplacerDeActivator", function(ply) if IsValid(ply) then PlayerVR = false end end)
hook.Add("VRMod_Start", "WeaponReplacerActivator", function(ply) if IsValid(ply) then PlayerVR = true end end)
-- replacing flatscreen weapons with vr weapons in realtime while playing vr
hook.Add("VRMod_Pickup", "WeaponPickupReplacerVR", function(ply, weapon)
    if PlayerVR == true then
        local Wepper = weapon:GetClass()
        local WepperVR = VRWeps.Replacer[Wepper]
        if WepperVR and engine.ActiveGamemode() ~= "lambda" then
            ply:StripWeapon(Wepper)
            ply:Give(WepperVR, true)
            ply:SelectWeapon(WepperVR)
        end
    end
end)