AddCSLuaFile()

local files = {
    
    "vrmod/core/vrmod_api.lua",
    "vrmod/utils/vrmod_utils.lua",
    "vrmod/core/vrmod_startup.lua",
    "vrmod/core/vrmod.lua",
    "vrmod/core/vrmod_network.lua",
    "vrmod/utils/vrmod_weaponreplacer.lua",
    "vrmod/io/vrmod_locomotion.lua",
    "vrmod/io/vrmod_climbing.lua",
    "vrmod/io/vrmod_doors.lua",
    "vrmod/view/vrmod_viewmodeledit.lua",
    "vrmod/io/vrmod_dropweapon.lua",
    "vrmod/io/vrmod_flashlight.lua",
    "vrmod/io/vrmod_input.lua",
    "vrmod/io/vrmod_manualpickup.lua",
    "vrmod/io/vrmod_melee_global.lua",
    "vrmod/io/vrmod_physhands.lua",
    "vrmod/io/vrmod_pickup.lua",
    "vrmod/io/vrmod_pickup_arcvr.lua",
    "vrmod/io/vrmod_seated.lua",
    "vrmod/io/vrmod_steamvr_bindings.lua",
    "vrmod/io/vrmod_gravity_and_physgun.lua",
    "vrmod/io/vrmod_buttons.lua",
    "vrmod/io/vrmod_keypad.lua",
    "vrmod/io/vrmod_glide.lua",
    "vrmod/view/vrmod_character.lua",
    "vrmod/view/vrmod_character_hands.lua",
    "vrmod/view/vrmod_pmchange.lua",
    "vrmod/view/vrmod_laser_pointer.lua",
    "vrmod/ui/vrmod_actioneditor.lua",
    "vrmod/ui/vrmod_dermapopups.lua",
    "vrmod/ui/vrmod_halos.lua",
    "vrmod/ui/vrmod_hud.lua",
    "vrmod/ui/vrmod_mapbrowser.lua",
    "vrmod/ui/vrmod_ui.lua",
    "vrmod/ui/vrmod_ui_chat.lua",
    "vrmod/ui/vrmod_ui_heightadjust.lua",
    "vrmod/ui/vrmod_ui_quickmenu.lua",
    "vrmod/ui/vrmod_ui_weaponselect.lua",
    "vrmod/ui/vrmod_ui_numpad.lua",
    "vrmod/ui/vrmod_worldtips.lua",
    "vrmod/ui/vrmod_settings.lua",
    "vrmod/ui/vrmod_ui_buttons.lua"
}

for _, path in ipairs(files) do
    AddCSLuaFile(path)
    include(path)
end