if SERVER then return end
g_VR = g_VR or {}
g_VR.action_manifest = [[
{
	"default_bindings": [
		{
			"controller_type": "vive_controller",
			"binding_url": "vrmod_bindings_vive_controller.txt"
		},
		{
			"controller_type": "oculus_touch",
			"binding_url": "vrmod_bindings_oculus_touch.txt"
		},
		{
			"controller_type": "holographic_controller",
			"binding_url": "vrmod_bindings_holographic_controller.txt"
		},
		{
			"controller_type": "knuckles",
			"binding_url": "vrmod_bindings_knuckles.txt"
		},
		{
			"controller_type": "vive_cosmos_controller",
			"binding_url": "vrmod_bindings_vive_cosmos_controller.txt"
		},
		{
			"controller_type": "vive_tracker_left_foot",
			"binding_url": "vrmod_bindings_vive_tracker_left_foot.txt"
		},
		{
			"controller_type": "vive_tracker_right_foot",
			"binding_url": "vrmod_bindings_vive_tracker_right_foot.txt"
		},
		{
			"controller_type": "vive_tracker_waist",
			"binding_url": "vrmod_bindings_vive_tracker_waist.txt"
		}
	], 
	
	"actions": [

		{
			"name": "/actions/base/in/pose_lefthand",
			"type": "pose"
		},
		{
			"name": "/actions/base/in/pose_righthand",
			"type": "pose"
		},
		{
			"name": "/actions/base/in/pose_leftfoot",
			"type": "pose"
		},
		{
			"name": "/actions/base/in/pose_rightfoot",
			"type": "pose"
		},
		{
			"name": "/actions/base/in/pose_waist",
			"type": "pose"
		},
		{
			"name": "/actions/base/in/skeleton_lefthand",
			"type": "skeleton",
			"skeleton": "/skeleton/hand/left"
		},
		{
			"name": "/actions/base/in/skeleton_righthand",
			"type": "skeleton",
			"skeleton": "/skeleton/hand/right"
		},
		{
			"name": "/actions/base/out/vibration_left",
			"type": "vibration"
		},
		{
			"name": "/actions/base/out/vibration_right",
			"type": "vibration"
		},

		{
			"name": "/actions/main/in/boolean_primaryfire",
			"type": "boolean"
		},
		{
			"name": "/actions/main/in/vector1_primaryfire",
			"type": "vector1"
		},
		{
			"name": "/actions/main/in/boolean_secondaryfire",
			"type": "boolean"
		},
		{
			"name": "/actions/main/in/boolean_changeweapon",
			"type": "boolean"
		},
		{
			"name": "/actions/main/in/boolean_use",
			"type": "boolean"
		},
		{
			"name": "/actions/main/in/boolean_spawnmenu",
			"type": "boolean"
		},
		{
			"name": "/actions/main/in/vector2_walkdirection",
			"type": "vector2"
		},
		{
			"name": "/actions/main/in/boolean_walk",
			"type": "boolean"
		},
		{
			"name": "/actions/main/in/boolean_flashlight",
			"type": "boolean"
		},
		{
			"name": "/actions/main/in/vector2_smoothturn",
			"type": "vector2"
		},
		{
			"name": "/actions/main/in/boolean_chat",
			"type": "boolean"
		},
		{
			"name": "/actions/main/in/boolean_reload",
			"type": "boolean"
		},
		{
			"name": "/actions/main/in/boolean_jump",
			"type": "boolean"
		},
		{
			"name": "/actions/main/in/boolean_crouch",
			"type": "boolean"
		},
		{
			"name": "/actions/main/in/boolean_left_pickup",
			"type": "boolean"
		},
		{
			"name": "/actions/main/in/boolean_right_pickup",
			"type": "boolean"
		},
		{
			"name": "/actions/main/in/boolean_undo",
			"type": "boolean"
		},
		{
			"name": "/actions/main/in/boolean_sprint",
			"type": "boolean"
		},
		
		{
			"name": "/actions/main/in/boolean_forward",
			"type": "boolean"
		},
		
		{
			"name": "/actions/main/in/boolean_back",
			"type": "boolean"
		},

		{
			"name": "/actions/main/in/boolean_left",
			"type": "boolean"
		},

		{
			"name": "/actions/main/in/boolean_right",
			"type": "boolean"
		},
		
		{
			"name": "/actions/main/in/boolean_walkkey",
			"type": "boolean"
		},
		
		{
			"name": "/actions/main/in/boolean_teleport",
			"type": "boolean"
		},		
		{
			"name": "/actions/main/in/boolean_menucontext",
			"type": "boolean"
		},
	
		{
			"name": "/actions/driving/in/vector1_forward",
			"type": "vector1"
		},
		{
			"name": "/actions/driving/in/vector1_reverse",
			"type": "vector1"
		},
		{
			"name": "/actions/driving/in/boolean_turbo",
			"type": "boolean"
		},
		{
			"name": "/actions/driving/in/vector2_steer",
			"type": "vector2"
		},
		{
			"name": "/actions/driving/in/boolean_handbrake",
			"type": "boolean"
		},
		{
			"name": "/actions/driving/in/boolean_exit",
			"type": "boolean"
		},
		{
			"name": "/actions/driving/in/boolean_turret",
			"type": "boolean"
		},
      {
			"name": "/actions/driving/in/boolean_alt_turret",
			"type": "boolean"
		},
       {
			"name": "/actions/driving/in/boolean_switch_weapon",
			"type": "boolean"
		},
		{
			"name": "/actions/driving/in/boolean_spawnmenu",
			"type": "boolean"
		},
		{
			"name": "/actions/driving/in/boolean_left_pickup",
			"type": "boolean"
		},
		{
			"name": "/actions/driving/in/boolean_right_pickup",
			"type": "boolean"
		},
      {
			"name": "/actions/driving/in/boolean_car_mouse_left",
			"type": "boolean"
		},
      {
			"name": "/actions/driving/in/boolean_car_mouse_right",
			"type": "boolean"
		},
      {
			"name": "/actions/driving/in/boolean_shift_up",
			"type": "boolean"
		},
      {
			"name": "/actions/driving/in/boolean_shift_down",
			"type": "boolean"
		},
      {
			"name": "/actions/driving/in/boolean_shift_neutral",
			"type": "boolean"
		},
      {
			"name": "/actions/driving/in/boolean_siren",
			"type": "boolean"
		},
      {
			"name": "/actions/driving/in/boolean_lights",
			"type": "boolean"
		},
      {
			"name": "/actions/driving/in/boolean_horn",
			"type": "boolean"
		},
      {
			"name": "/actions/driving/in/boolean_signal_left",
			"type": "boolean"
		},
      {
			"name": "/actions/driving/in/boolean_signal_right",
			"type": "boolean"
		},
      {
			"name": "/actions/driving/in/boolean_toggle_engine",
			"type": "boolean"
		},
      {
			"name": "/actions/driving/in/detach_trailer",
			"type": "boolean"
		}
	],

	"action_sets": [
		{
			"name": "/actions/base",
			"usage": "leftright"
		},
		{
			"name": "/actions/main",
			"usage": "leftright"
		},
		{
			"name": "/actions/driving",
			"usage": "leftright"
		}
	],

	"localization" : [
		{
			"language_tag": "en_us",

			"/actions/base" : "Base",
			"/actions/main" : "On Foot",
			"/actions/driving" : "In Vehicle",

			"/actions/base/in/pose_lefthand" : "Left Hand Pose",
			"/actions/base/in/pose_righthand" : "Right Hand Pose",
			"/actions/base/in/skeleton_lefthand" : "Left Hand Skeleton",
			"/actions/base/in/skeleton_righthand" : "Right Hand Skeleton",
			"/actions/base/out/vibration_left" : "Left Haptic Feedback",
			"/actions/base/out/vibration_right" : "Right Haptic Feedback",
			
			"/actions/main/in/boolean_primaryfire" : "Primary Fire",
			"/actions/main/in/vector1_primaryfire" : "Primary Fire (Analog)",
			"/actions/main/in/boolean_secondaryfire" : "Secondary Fire",
			"/actions/main/in/boolean_changeweapon" : "Weapon Menu",
			"/actions/main/in/boolean_use" : "Use",
			"/actions/main/in/boolean_spawnmenu" : "Quickmenu",
			"/actions/main/in/vector2_walkdirection" : "Walk Direction",
			"/actions/main/in/boolean_walk" : "Enable Walking",
			"/actions/main/in/boolean_flashlight" : "Flashlight",
			"/actions/main/in/vector2_smoothturn" : "Smooth Turn",
			"/actions/main/in/boolean_chat" : "chat",
			"/actions/main/in/boolean_reload" : "Reload",
			"/actions/main/in/boolean_jump" : "Jump",
			"/actions/main/in/boolean_crouch" : "Crouch",
			"/actions/main/in/boolean_left_pickup" : "Left Pickup",
			"/actions/main/in/boolean_right_pickup" : "Right Pickup",
			"/actions/main/in/boolean_undo" : "Undo",
			"/actions/main/in/boolean_sprint" : "Sprint",
			"/actions/main/in/boolean_forward" : "Forward",
			"/actions/main/in/boolean_back" : "Back",
			"/actions/main/in/boolean_left" : "Left",
			"/actions/main/in/boolean_right" : "Right",
			"/actions/main/in/boolean_walkkey" : "walkkey",			
			"/actions/main/in/boolean_teleport" : "teleport",			
			"/actions/main/in/boolean_menucontext" : "context menu",

			"/actions/driving/in/vector1_forward" : "Forward",
			"/actions/driving/in/vector1_reverse" : "Reverse",
			"/actions/driving/in/vector2_steer" : "Steer",
			"/actions/driving/in/boolean_turbo" : "Turbo",
			"/actions/driving/in/boolean_handbrake" : "Handbrake",
         "/actions/driving/in/boolean_toggle_engine" : "Toggle Engine",
         "/actions/driving/in/boolean_shift_up" : "Shift Up",
         "/actions/driving/in/boolean_shift_down" : "Shift Down",
         "/actions/driving/in/boolean_shift_neutral" : "Shift Neutral",
			"/actions/driving/in/boolean_turret" : "Turret",
         "/actions/driving/in/boolean_alt_turret" : "Alt Turret",
         "/actions/driving/in/boolean_switch_weapon" : "Switch Weapon",
         "/actions/driving/in/boolean_lights" : "Lights",
         "/actions/driving/in/boolean_siren" : "Siren",
         "/actions/driving/in/boolean_signal_left" : "Signal Left / Landing Gear",
         "/actions/driving/in/boolean_signal_right" : "Signal Right / Countermeasures",
         "/actions/driving/in/boolean_horn" : "Horn",
         "/actions/driving/in/detach_trailer" : "Detach Trailer",
			"/actions/driving/in/boolean_exit" : "Exit Vehicle",
			"/actions/driving/in/boolean_spawnmenu" : "Quickmenu",
			"/actions/driving/in/boolean_left_pickup" : "Left Pickup",
			"/actions/driving/in/boolean_right_pickup" : "Right Pickup",
         "/actions/driving/in/boolean_car_mouse_right" : "Right mouse click",
         "/actions/driving/in/boolean_car_mouse_left" : "Left mouse click"
		}
	]
}
]]
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
g_VR.bindings_holographic = [[

{
   "action_manifest_version" : 0,
   "alias_info" : {},
   "app_key" : "steam.app.4000",
   "bindings" : {
      "/actions/base" : {
         "chords" : [],
         "haptics" : [
            {
               "output" : "/actions/base/out/vibration_left",
               "path" : "/user/hand/left/output/haptic"
            },
            {
               "output" : "/actions/base/out/vibration_right",
               "path" : "/user/hand/right/output/haptic"
            }
         ],
         "poses" : [
            {
               "output" : "/actions/base/in/pose_lefthand",
               "path" : "/user/hand/left/pose/raw"
            },
            {
               "output" : "/actions/base/in/pose_righthand",
               "path" : "/user/hand/right/pose/raw"
            }
         ],
         "skeleton" : [
            {
               "output" : "/actions/base/in/skeleton_lefthand",
               "path" : "/user/hand/left/input/skeleton/left"
            },
            {
               "output" : "/actions/base/in/skeleton_righthand",
               "path" : "/user/hand/right/input/skeleton/right"
            }
         ],
         "sources" : []
      },
      "/actions/driving" : {
         "sources" : [
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/driving/in/boolean_turbo"
                  },
                  "pull" : {
                     "output" : "/actions/driving/in/vector1_forward"
                  }
               },
               "mode" : "trigger",
               "path" : "/user/hand/right/input/trigger"
            },
            {
               "inputs" : {
                  "pull" : {
                     "output" : "/actions/driving/in/vector1_reverse"
                  }
               },
               "mode" : "trigger",
               "path" : "/user/hand/left/input/trigger"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/driving/in/boolean_turret"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/right/input/trackpad"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/driving/in/boolean_exit"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/right/input/application_menu"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/driving/in/boolean_handbrake"
                  },
                  "position" : {
                     "output" : "/actions/driving/in/vector2_steer"
                  }
               },
               "mode" : "trackpad",
               "path" : "/user/hand/left/input/trackpad"
            }
         ]
      },
      "/actions/main" : {
         "sources" : [
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_chat"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/left/input/application_menu"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_jump"
                  },
                  "position" : {
                     "output" : "/actions/main/in/vector2_walkdirection"
                  },
                  "touch" : {
                     "output" : "/actions/main/in/boolean_walk"
                  }
               },
               "mode" : "trackpad",
               "path" : "/user/hand/left/input/trackpad"
            },
            {
               "inputs" : {
                   "center" : {
                     "output" : "/actions/main/in/boolean_flashlight"
                  },
                  "east" : {
                     "output" : "/actions/main/in/boolean_changeweapon"
                  },
                  "north" : {
                     "output" : "/actions/main/in/boolean_jump"
                  },
                  "south" : {
                     "output" : "/actions/main/in/boolean_crouch"
                  },
                  "west" : {
                     "output" : "/actions/main/in/boolean_spawnmenu"
                  }
               },
               "mode" : "dpad",
               "parameters" : {
                  "deadzone_pct" : "70",
                  "overlap_pct" : "0",
                  "sub_mode" : "click"
               },
               "path" : "/user/hand/right/input/trackpad"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_spawnmenu"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/right/input/application_menu"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_use"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/right/input/grip"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_reload"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/left/input/grip"
            },
            {
               "inputs" : {
                  "pull" : {
                     "output" : "/actions/main/in/vector1_primaryfire"
                  }
               },
               "mode" : "trigger",
               "path" : "/user/hand/right/input/trigger"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_primaryfire"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/right/input/trigger"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_left_pickup"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/left/input/trigger"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_sprint"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/left/input/grip"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_right_pickup"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/right/input/trigger"
            },
            {
               "inputs" : {
                  "position" : {
                     "output" : "/actions/main/in/vector2_smoothturn"
                  }
               },
               "mode" : "trackpad",
               "parameters" : {
                  "deadzone_pct" : "70"
               },
               "path" : "/user/hand/right/input/trackpad"
            }
         ]
      }
   },
   "category" : "steamvr_input",
   "controller_type" : "holographic_controller",
   "description" : "default vrmod bindings",
   "name" : "default vrmod bindings",
   "options" : {},
   "simulated_actions" : []
}

]]
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
g_VR.bindings_touch = [[
{
   "action_manifest_version" : 0,
   "alias_info" : {},
   "app_key" : "steam.app.4000",
   "bindings" : {
      "/actions/base" : {
         "chords" : [],
         "haptics" : [
            {
               "output" : "/actions/base/out/vibration_left",
               "path" : "/user/hand/left/output/haptic"
            },
            {
               "output" : "/actions/base/out/vibration_right",
               "path" : "/user/hand/right/output/haptic"
            }
         ],
         "poses" : [
            {
               "output" : "/actions/base/in/pose_lefthand",
               "path" : "/user/hand/left/pose/raw"
            },
            {
               "output" : "/actions/base/in/pose_righthand",
               "path" : "/user/hand/right/pose/raw"
            }
         ],
         "skeleton" : [
            {
               "output" : "/actions/base/in/skeleton_lefthand",
               "path" : "/user/hand/left/input/skeleton/left"
            },
            {
               "output" : "/actions/base/in/skeleton_righthand",
               "path" : "/user/hand/right/input/skeleton/right"
            }
         ],
         "sources" : []
      },
      "/actions/driving" : {
         "chords" : [
            {
               "inputs" : [
                  [ "/user/hand/left/input/grip", "click" ],
                  [ "/user/hand/right/input/joystick", "center" ]
               ],
               "output" : "/actions/driving/in/boolean_toggle_engine"
            },
            {
               "inputs" : [
                  [ "/user/hand/right/input/grip", "click" ],
                  [ "/user/hand/right/input/joystick", "center" ]
               ],
               "output" : "/actions/driving/in/boolean_alt_turret"
            },
            {
               "inputs" : [
                  [ "/user/hand/left/input/thumbrest", "touch" ],
                  [ "/user/hand/right/input/thumbrest", "touch" ]
               ],
               "output" : "/actions/driving/in/boolean_switch_weapon"
            },
            {
               "inputs" : [
                  [ "/user/hand/left/input/grip", "click" ],
                  [ "/user/hand/right/input/joystick", "west" ]
               ],
               "output" : "/actions/driving/in/boolean_signal_left"
            },
            {
               "inputs" : [
                  [ "/user/hand/left/input/grip", "click" ],
                  [ "/user/hand/right/input/joystick", "east" ]
               ],
               "output" : "/actions/driving/in/boolean_signal_right"
            }
         ],
         "poses" : [],
         "skeleton" : [],
         "sources" : [
            {
               "inputs" : {
                  "pull" : {
                     "output" : "/actions/driving/in/vector1_forward"
                  }
               },
               "mode" : "trigger",
               "parameters" : {},
               "path" : "/user/hand/right/input/trigger"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/driving/in/vector1_reverse"
                  }
               },
               "mode" : "trigger",
               "parameters" : {},
               "path" : "/user/hand/left/input/trigger"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/driving/in/boolean_horn"
                  },
                  "position" : {
                     "output" : "/actions/driving/in/vector2_steer"
                  }
               },
               "mode" : "joystick",
               "parameters" : {},
               "path" : "/user/hand/left/input/joystick"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/driving/in/boolean_turbo"
                  }
               },
               "mode" : "button",
               "parameters" : {},
               "path" : "/user/hand/right/input/b"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/driving/in/boolean_handbrake"
                  }
               },
               "mode" : "button",
               "parameters" : {},
               "path" : "/user/hand/right/input/a"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/driving/in/boolean_spawnmenu"
                  }
               },
               "mode" : "button",
               "parameters" : {},
               "path" : "/user/hand/left/input/y"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/driving/in/boolean_exit"
                  }
               },
               "mode" : "button",
               "parameters" : {},
               "path" : "/user/hand/left/input/x"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/driving/in/boolean_handbrake"
                  }
               },
               "mode" : "trigger",
               "parameters" : {},
               "path" : "/user/hand/left/input/grip"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/driving/in/boolean_turret"
                  }
               },
               "mode" : "trigger",
               "parameters" : {},
               "path" : "/user/hand/right/input/grip"
            },
            {
               "inputs" : {
                  "center" : {
                     "output" : "/actions/driving/in/boolean_shift_neutral"
                  },
                  "east" : {
                     "output" : "/actions/driving/in/boolean_lights"
                  },
                  "north" : {
                     "output" : "/actions/driving/in/boolean_shift_up"
                  },
                  "south" : {
                     "output" : "/actions/driving/in/boolean_shift_down"
                  },
                  "west" : {
                     "output" : "/actions/driving/in/boolean_siren"
                  }
               },
               "mode" : "dpad",
               "parameters" : {
                  "sub_mode" : "touch"
               },
               "path" : "/user/hand/right/input/joystick"
            },
            {
               "inputs" : {},
               "mode" : "toggle_button",
               "parameters" : {},
               "path" : "/user/hand/left/input/thumbrest"
            },
            {
               "inputs" : {},
               "mode" : "button",
               "parameters" : {},
               "path" : "/user/hand/right/input/thumbrest"
            }
         ]
      },
      "/actions/main" : {
         "chords" : [
            {
               "inputs" : [
                  [ "/user/hand/left/input/thumbrest", "touch" ],
                  [ "/user/hand/right/input/thumbrest", "touch" ]
               ],
               "output" : "/actions/main/in/boolean_reload"
            },
            {
               "inputs" : [
                  [ "/user/hand/left/input/joystick", "held" ],
                  [ "/user/hand/right/input/thumbrest", "touch" ]
               ],
               "output" : "/actions/main/in/boolean_teleport"
            }
         ],
         "poses" : [],
         "skeleton" : [],
         "sources" : [
            {
               "inputs" : {
                  "position" : {
                     "output" : "/actions/main/in/vector2_walkdirection"
                  }
               },
               "mode" : "joystick",
               "parameters" : {
                  "deadzone_pct" : "10"
               },
               "path" : "/user/hand/left/input/joystick"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_left_pickup"
                  },
                  "touch" : {
                     "output" : "/actions/main/in/dummy"
                  }
               },
               "mode" : "button",
               "parameters" : {},
               "path" : "/user/hand/left/input/grip"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_primaryfire"
                  }
               },
               "mode" : "button",
               "parameters" : {},
               "path" : "/user/hand/right/input/trigger"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_right_pickup"
                  }
               },
               "mode" : "button",
               "parameters" : {},
               "path" : "/user/hand/right/input/grip"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_secondaryfire"
                  }
               },
               "mode" : "button",
               "parameters" : {},
               "path" : "/user/hand/left/input/trigger"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_spawnmenu"
                  },
                  "touch" : {
                     "output" : "/actions/main/in/lweaponmenu"
                  }
               },
               "mode" : "button",
               "parameters" : {},
               "path" : "/user/hand/left/input/y"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_jump"
                  }
               },
               "mode" : "button",
               "parameters" : {},
               "path" : "/user/hand/right/input/b"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_crouch"
                  },
                  "touch" : {
                     "output" : "/actions/main/in/dummy"
                  }
               },
               "mode" : "button",
               "parameters" : {},
               "path" : "/user/hand/right/input/a"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_sprint"
                  }
               },
               "mode" : "button",
               "parameters" : {},
               "path" : "/user/hand/left/input/joystick"
            },
            {
               "inputs" : {
                  "position" : {
                     "output" : "/actions/main/in/vector2_smoothturn"
                  }
               },
               "mode" : "joystick",
               "parameters" : {},
               "path" : "/user/hand/right/input/joystick"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_use"
                  }
               },
               "mode" : "button",
               "parameters" : {},
               "path" : "/user/hand/left/input/x"
            },
            {
               "inputs" : {},
               "mode" : "button",
               "parameters" : {},
               "path" : "/user/hand/left/input/thumbrest"
            },
            {
               "inputs" : {},
               "mode" : "button",
               "parameters" : {},
               "path" : "/user/hand/right/input/thumbrest"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_changeweapon"
                  }
               },
               "mode" : "button",
               "parameters" : {},
               "path" : "/user/hand/right/input/joystick"
            }
         ]
      }
   },
   "category" : "steamvr_input",
   "controller_type" : "oculus_touch",
   "description" : "--- On Foot ---\n\nTeleport () - Right Joystick + Right Thumb Rest\nReload - Left Thumb Rest + Right Thumb Rest\nWeapon menu - Right Joystick\nQuick menu - Y\nUse - X\nSprint - Left Joystick\nSecondary fire - Left Trigger\nCrouch - A\nJump - B\n\n--- In Vehicle ---\n\nForward - Right Trigger\nReverse - Left Trigger\nHand Break - A \nTurbo - B\nTurret - Right Joystick\nQuick menu - Y\nExit - X",
   "interaction_profile" : "",
   "name" : "VRMOD x64 for Quest 3 with Glide",
   "options" : {},
   "simulated_actions" : []
}


      
]]
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
g_VR.bindings_vive = [[
{
   "action_manifest_version": 0,
   "alias_info": {},
   "app_key": "steam.app.4000",
   "bindings": {
      "/actions/base": {
         "chords": [],
         "haptics": [
            {
               "output": "/actions/base/out/vibration_left",
               "path": "/user/hand/left/output/haptic"
            },
            {
               "output": "/actions/base/out/vibration_right",
               "path": "/user/hand/right/output/haptic"
            }
         ],
         "poses": [
            {
               "output": "/actions/base/in/pose_lefthand",
               "path": "/user/hand/left/pose/raw"
            },
            {
               "output": "/actions/base/in/pose_righthand",
               "path": "/user/hand/right/pose/raw"
            }
         ],
         "skeleton": [
            {
               "output": "/actions/base/in/skeleton_lefthand",
               "path": "/user/hand/left/input/skeleton/left"
            },
            {
               "output": "/actions/base/in/skeleton_righthand",
               "path": "/user/hand/right/input/skeleton/right"
            }
         ],
         "sources": []
      },
      "/actions/driving": {
         "sources": [
            {
               "inputs": {
                  "click": {
                     "output": "/actions/driving/in/boolean_turbo"
                  },
                  "pull": {
                     "output": "/actions/driving/in/vector1_forward"
                  }
               },
               "mode": "trigger",
               "path": "/user/hand/right/input/trigger"
            },
            {
               "inputs": {
                  "pull": {
                     "output": "/actions/driving/in/vector1_reverse"
                  }
               },
               "mode": "trigger",
               "path": "/user/hand/left/input/trigger"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/driving/in/boolean_turret"
                  }
               },
               "mode": "button",
               "path": "/user/hand/right/input/trackpad"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/driving/in/boolean_exit"
                  }
               },
               "mode": "button",
               "path": "/user/hand/right/input/application_menu"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/driving/in/boolean_handbrake"
                  },
                  "position": {
                     "output": "/actions/driving/in/vector2_steer"
                  }
               },
               "mode": "trackpad",
               "path": "/user/hand/left/input/trackpad",
               "parameters": {
                  "deadzone_pct": "20"
               }
            }
         ]
      },
      "/actions/main": {
         "sources": [
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_chat"
                  }
               },
               "mode": "button",
               "path": "/user/hand/left/input/application_menu"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_jump"
                  },
                  "position": {
                     "output": "/actions/main/in/vector2_walkdirection"
                  },
                  "touch": {
                     "output": "/actions/main/in/boolean_walk"
                  }
               },
               "mode": "trackpad",
               "path": "/user/hand/left/input/trackpad",
               "parameters": {
                  "deadzone_pct": "20"
               }
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_flashlight"
                  }
               },
               "mode": "button",
               "path": "/user/hand/right/input/grip"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_changeweapon"
                  }
               },
               "mode": "button",
               "path": "/user/hand/right/input/application_menu"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_crouch"
                  }
               },
               "mode": "button",
               "path": "/user/hand/left/input/grip"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_spawnmenu"
                  }
               },
               "mode": "button",
               "path": "/user/hand/right/input/application_menu"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_use"
                  }
               },
               "mode": "button",
               "path": "/user/hand/right/input/grip"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_reload"
                  }
               },
               "mode": "button",
               "path": "/user/hand/left/input/grip"
            },
            {
               "inputs": {
                  "pull": {
                     "output": "/actions/main/in/vector1_primaryfire"
                  }
               },
               "mode": "trigger",
               "path": "/user/hand/right/input/trigger"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_primaryfire"
                  }
               },
               "mode": "button",
               "path": "/user/hand/right/input/trigger"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_left_pickup"
                  }
               },
               "mode": "button",
               "path": "/user/hand/left/input/trigger"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_sprint"
                  }
               },
               "mode": "button",
               "path": "/user/hand/left/input/grip"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_right_pickup"
                  }
               },
               "mode": "button",
               "path": "/user/hand/right/input/trigger"
            },
            {
               "inputs": {
                  "position": {
                     "output": "/actions/main/in/vector2_smoothturn"
                  }
               },
               "mode": "trackpad",
               "path": "/user/hand/right/input/trackpad",
               "parameters": {
                  "deadzone_pct": "20",
                  "sensitivity": "0.5"
               }
            }
         ]
      }
   },
   "category": "steamvr_input",
   "controller_type": "vive_controller",
   "description": "Optimized Vive bindings for walk direction and smooth turn",
   "name": "Optimized Vive Bindings",
   "options": {},
   "simulated_actions": []
}

]]
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
g_VR.bindings_knuckles = [[
{
   "action_manifest_version": 0,
   "alias_info": {},
   "app_key": "steam.app.4000",
   "bindings": {
      "/actions/base": {
         "chords": [],
         "haptics": [
            {
               "output": "/actions/base/out/vibration_left",
               "path": "/user/hand/left/output/haptic"
            },
            {
               "output": "/actions/base/out/vibration_right",
               "path": "/user/hand/right/output/haptic"
            }
         ],
         "poses": [
            {
               "output": "/actions/base/in/pose_lefthand",
               "path": "/user/hand/left/pose/raw"
            },
            {
               "output": "/actions/base/in/pose_righthand",
               "path": "/user/hand/right/pose/raw"
            }
         ],
         "skeleton": [
            {
               "output": "/actions/base/in/skeleton_lefthand",
               "path": "/user/hand/left/input/skeleton/left"
            },
            {
               "output": "/actions/base/in/skeleton_righthand",
               "path": "/user/hand/right/input/skeleton/right"
            }
         ],
         "sources": []
      },
      "/actions/driving": {
         "sources": [
            {
               "inputs": {
                  "click": {
                     "output": "/actions/driving/in/boolean_turbo"
                  },
                  "pull": {
                     "output": "/actions/driving/in/vector1_forward"
                  }
               },
               "mode": "trigger",
               "path": "/user/hand/right/input/trigger"
            },
            {
               "inputs": {
                  "pull": {
                     "output": "/actions/driving/in/vector1_reverse"
                  }
               },
               "mode": "trigger",
               "path": "/user/hand/left/input/trigger"
            },
            {
               "inputs": {
                  "position": {
                     "output": "/actions/driving/in/vector2_steer"
                  }
               },
               "mode": "joystick",
               "path": "/user/hand/left/input/thumbstick",
               "parameters": {
                  "deadzone_pct": "20"
               }
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/driving/in/boolean_turret"
                  }
               },
               "mode": "button",
               "path": "/user/hand/right/input/b"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/driving/in/boolean_handbrake"
                  }
               },
               "mode": "button",
               "path": "/user/hand/right/input/a"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/driving/in/boolean_exit"
                  }
               },
               "mode": "button",
               "path": "/user/hand/left/input/b"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/driving/in/boolean_spawnmenu"
                  }
               },
               "mode": "button",
               "path": "/user/hand/left/input/a"
            }
         ]
      },
      "/actions/main": {
         "chords": [
            {
               "inputs": [
                  ["/user/hand/right/input/thumbstick", "position"],
                  ["/user/hand/right/input/a", "click"]
               ],
               "output": "/actions/main/in/boolean_spawnmenu"
            }
         ],
         "sources": [
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_primaryfire"
                  },
                  "pull": {
                     "output": "/actions/main/in/vector1_primaryfire"
                  }
               },
               "mode": "trigger",
               "path": "/user/hand/right/input/trigger"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_changeweapon"
                  }
               },
               "mode": "button",
               "path": "/user/hand/right/input/b"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_jump"
                  }
               },
               "mode": "button",
               "path": "/user/hand/right/input/a"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_crouch"
                  }
               },
               "mode": "button",
               "path": "/user/hand/left/input/b"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_right_pickup"
                  }
               },
               "mode": "button",
               "parameters": {
                  "force_input": "force",
                  "click_activate_threshold": "0.45",
                  "click_deactivate_threshold": "0.4"
               },
               "path": "/user/hand/right/input/grip"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_use"
                  }
               },
               "mode": "button",
               "parameters": {
                  "force_input": "force",
                  "click_activate_threshold": "0.45",
                  "click_deactivate_threshold": "0.4",
                  "haptic_amplitude": "0"
               },
               "path": "/user/hand/right/input/grip"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_chat"
                  }
               },
               "mode": "button",
               "path": "/user/hand/left/input/trackpad"
            },
            {
               "inputs": {
                  "position": {
                     "output": "/actions/main/in/vector2_walkdirection"
                  },
                  "click": {
                     "output": "/actions/main/in/boolean_walk"
                  }
               },
               "mode": "joystick",
               "parameters": {
                  "deadzone_pct": "20",
                  "click_activate_threshold": "0.1",
                  "click_deactivate_threshold": "0.05",
                  "force_input": "position"
               },
               "path": "/user/hand/left/input/thumbstick"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_left_pickup"
                  }
               },
               "mode": "button",
               "parameters": {
                  "force_input": "force",
                  "click_activate_threshold": "0.45",
                  "click_deactivate_threshold": "0.4"
               },
               "path": "/user/hand/left/input/grip"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_sprint"
                  }
               },
               "mode": "button",
               "path": "/user/hand/left/input/a"
            },
            {
               "inputs": {
                  "click": {
                     "output": "/actions/main/in/boolean_reload"
                  }
               },
               "mode": "button",
               "path": "/user/hand/left/input/b"
            },
            {
               "inputs": {
                  "position": {
                     "output": "/actions/main/in/vector2_smoothturn"
                  }
               },
               "mode": "joystick",
               "parameters": {
                  "deadzone_pct": "20",
                  "sensitivity": "0.5"
               },
               "path": "/user/hand/right/input/thumbstick"
            }
         ]
      }
   },
   "category": "steamvr_input",
   "controller_type": "knuckles",
   "description": "Optimized Knuckles bindings with spawn menu on right thumbstick rotation + A click, aligned with Quest bindings",
   "name": "Optimized Knuckles Bindings",
   "options": {},
   "simulated_actions": []
}
]]
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
g_VR.bindings_cosmos = [[

{
   "action_manifest_version" : 0,
   "alias_info" : {},
   "app_key" : "steam.app.4000",
   "bindings" : {
      "/actions/base" : {
         "chords" : [],
         "haptics" : [
            {
               "output" : "/actions/base/out/vibration_left",
               "path" : "/user/hand/left/output/haptic"
            },
            {
               "output" : "/actions/base/out/vibration_right",
               "path" : "/user/hand/right/output/haptic"
            }
         ],
         "poses" : [
            {
               "output" : "/actions/base/in/pose_lefthand",
               "path" : "/user/hand/left/pose/raw"
            },
            {
               "output" : "/actions/base/in/pose_righthand",
               "path" : "/user/hand/right/pose/raw"
            }
         ],
         "skeleton" : [
            {
               "output" : "/actions/base/in/skeleton_lefthand",
               "path" : "/user/hand/left/input/skeleton/left"
            },
            {
               "output" : "/actions/base/in/skeleton_righthand",
               "path" : "/user/hand/right/input/skeleton/right"
            }
         ],
         "sources" : []
      },
      "/actions/driving" : {
         "sources" : [
            {
               "inputs" : {
                  "pull" : {
                     "output" : "/actions/driving/in/vector1_forward"
                  }
               },
               "mode" : "trigger",
               "path" : "/user/hand/right/input/trigger"
            },
            {
               "inputs" : {
                  "pull" : {
                     "output" : "/actions/driving/in/vector1_reverse"
                  }
               },
               "mode" : "trigger",
               "path" : "/user/hand/left/input/trigger"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/driving/in/boolean_turret"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/right/input/grip"
            },
            {
               "inputs" : {
                  "position" : {
                     "output" : "/actions/driving/in/vector2_steer"
                  }
               },
               "mode" : "joystick",
               "path" : "/user/hand/left/input/joystick"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/driving/in/boolean_turbo"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/right/input/b"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/driving/in/boolean_handbrake"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/right/input/a"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/driving/in/boolean_exit"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/left/input/y"
            }
         ]
      },
      "/actions/main" : {
         "sources" : [
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_sprint"
                  },
                  "position" : {
                     "output" : "/actions/main/in/vector2_walkdirection"
                  }
               },
               "mode" : "joystick",
               "parameters" : {
                  "deadzone_pct" : "10"
               },
               "path" : "/user/hand/left/input/joystick"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_left_pickup"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/left/input/grip"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_use"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/left/input/grip"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_walk"
                  }
               },
               "mode" : "button",
               "parameters" : {
                  "click_activate_threshold" : "0.1",
                  "click_deactivate_threshold" : "0.05",
                  "force_input" : "position"
               },
               "path" : "/user/hand/left/input/joystick"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_primaryfire"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/right/input/trigger"
            },
            {
               "inputs" : {
                  "pull" : {
                     "output" : "/actions/main/in/vector1_primaryfire"
                  }
               },
               "mode" : "trigger",
               "path" : "/user/hand/right/input/trigger"
            },
            {
               "inputs" : {
                  "east" : {
                     "output" : "/actions/main/in/boolean_changeweapon"
                  },
                  "north" : {
                     "output" : "/actions/main/in/boolean_jump"
                  },
                  "south" : {
                     "output" : "/actions/main/in/boolean_crouch"
                  },
                  "west" : {
                     "output" : "/actions/main/in/boolean_spawnmenu"
                  }
               },
               "mode" : "dpad",
               "parameters" : {
                  "deadzone_pct" : "90",
                  "overlap_pct" : "0",
                  "sub_mode" : "touch"
               },
               "path" : "/user/hand/right/input/joystick"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_spawnmenu"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/right/input/b"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_jump"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/right/input/a"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_right_pickup"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/right/input/grip"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_use"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/right/input/grip"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_changeweapon"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/right/input/joystick"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_reload"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/left/input/trigger"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_chat"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/left/input/y"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_undo"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/left/input/x"
            },
            {
               "inputs" : {
                  "position" : {
                     "output" : "/actions/main/in/vector2_smoothturn"
                  }
               },
               "mode" : "joystick",
               "parameters" : {
                  "deadzone_pct" : "10"
               },
               "path" : "/user/hand/right/input/joystick"
            }
         ]
      }
   },
   "category" : "steamvr_input",
   "controller_type" : "vive_cosmos_controller",
   "description" : "default vrmod bindings",
   "name" : "default vrmod bindings",
   "options" : {},
   "simulated_actions" : []
}
]]
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
g_VR.bindings_vive_tracker_left_foot = [[
{
   "action_manifest_version" : 0,
   "alias_info" : {},
   "app_key" : "steam.app.4000",
   "bindings" : {
      "/actions/base" : {
         "chords" : [],
         
         "poses" : [
            {
               "output" : "/actions/base/in/pose_leftfoot",
               "path" : "/user/foot/left/pose/raw"
            }
         ],
        
         "sources" : []
      }
      
   },
   "category" : "steamvr_input",
   "controller_type" : "vive_tracker_left_foot",
   "description" : "default vrmod bindings",
   "name" : "default vrmod bindings",
   "options" : {},
   "simulated_actions" : []
}
]]
g_VR.bindings_vive_tracker_right_foot = [[
{
   "action_manifest_version" : 0,
   "alias_info" : {},
   "app_key" : "steam.app.4000",
   "bindings" : {
      "/actions/base" : {
         "chords" : [],
         
         "poses" : [
            {
               "output" : "/actions/base/in/pose_rightfoot",
               "path" : "/user/foot/right/pose/raw"
            }
         ],
        
         "sources" : []
      }
      
   },
   "category" : "steamvr_input",
   "controller_type" : "vive_tracker_right_foot",
   "description" : "default vrmod bindings",
   "name" : "default vrmod bindings",
   "options" : {},
   "simulated_actions" : []
}
]]
g_VR.bindings_vive_tracker_waist = [[
{
   "action_manifest_version" : 0,
   "alias_info" : {},
   "app_key" : "steam.app.4000",
   "bindings" : {
      "/actions/base" : {
         "chords" : [],
         
         "poses" : [
            {
               "output" : "/actions/base/in/pose_waist",
               "path" : "/user/waist/pose/raw"
            }
         ],
        
         "sources" : []
      }
      
   },
   "category" : "steamvr_input",
   "controller_type" : "vive_tracker_waist",
   "description" : "default vrmod bindings",
   "name" : "default vrmod bindings",
   "options" : {},
   "simulated_actions" : []
}
]]
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
--##############################################################################
local function WriteActionManifest()
   if not file.Exists("vrmod", "DATA") then file.CreateDir("vrmod") end
   file.Write("vrmod/vrmod_action_manifest.txt", g_VR.action_manifest)
end

local function WriteBindingFiles()
   if not file.Exists("vrmod", "DATA") then file.CreateDir("vrmod") end
   WriteActionManifest()
   file.Write("vrmod/vrmod_bindings_holographic_controller.txt", g_VR.bindings_holographic)
   file.Write("vrmod/vrmod_bindings_oculus_touch.txt", g_VR.bindings_touch)
   file.Write("vrmod/vrmod_bindings_vive_controller.txt", g_VR.bindings_vive)
   file.Write("vrmod/vrmod_bindings_knuckles.txt", g_VR.bindings_knuckles)
   file.Write("vrmod/vrmod_bindings_vive_cosmos_controller.txt", g_VR.bindings_cosmos)
   file.Write("vrmod/vrmod_bindings_vive_tracker_left_foot.txt", g_VR.bindings_vive_tracker_left_foot)
   file.Write("vrmod/vrmod_bindings_vive_tracker_right_foot.txt", g_VR.bindings_vive_tracker_right_foot)
   file.Write("vrmod/vrmod_bindings_vive_tracker_waist.txt", g_VR.bindings_vive_tracker_waist)
end

-- local cv_bindingVersion = CreateClientConVar("vrmod_bindingversion", "0", true, false)
-- if cv_bindingVersion:GetInt() < 22 then
--    cv_bindingVersion:SetInt(22)
--    WriteBindingFiles()
-- end
WriteActionManifest()
WriteBindingFiles()
hook.Add("VRMod_Reset", "vrmod_reset_bindings", function() WriteBindingFiles() end)