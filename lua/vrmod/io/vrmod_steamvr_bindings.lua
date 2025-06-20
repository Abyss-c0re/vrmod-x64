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
			"name": "/actions/main/in/boolean_left_primaryfire",
			"type": "boolean"
		},
		{
			"name": "/actions/main/in/vector1_left_primaryfire",
			"type": "vector1"
		},
		{
			"name": "/actions/main/in/boolean_left_secondaryfire",
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
			"name": "/actions/main/in/boolean_turnleft",
			"type": "boolean"
		},
		{
			"name": "/actions/main/in/boolean_turnright",
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
			"name": "/actions/main/in/boolean_forword",
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
			"name": "/actions/main/in/boolean_slot1",
			"type": "boolean"
		},
		
		{
			"name": "/actions/main/in/boolean_slot2",
			"type": "boolean"
		},
		{
			"name": "/actions/main/in/boolean_slot3",
			"type": "boolean"
		},
		{
			"name": "/actions/main/in/boolean_slot4",
			"type": "boolean"
		},
		{
			"name": "/actions/main/in/boolean_slot5",
			"type": "boolean"
		},
		{
			"name": "/actions/main/in/boolean_slot6",
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
			"name": "/actions/main/in/boolean_lefthandmode",
			"type": "boolean"
		},
		{
			"name": "/actions/main/in/boolean_righthandmode",
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
			"/actions/main/in/boolean_turnleft" : "Snap Turn Left",
			"/actions/main/in/boolean_turnright" : "Snap Turn Right",
			"/actions/main/in/vector2_smoothturn" : "Smooth Turn",
			"/actions/main/in/boolean_chat" : "chat",
			"/actions/main/in/boolean_reload" : "Reload",
			"/actions/main/in/boolean_jump" : "Jump",
			"/actions/main/in/boolean_crouch" : "Crouch",
			"/actions/main/in/boolean_left_pickup" : "Left Pickup",
			"/actions/main/in/boolean_right_pickup" : "Right Pickup",
			"/actions/main/in/boolean_undo" : "Undo",
			"/actions/main/in/boolean_sprint" : "Sprint",
			"/actions/main/in/boolean_forword" : "Forword",
			"/actions/main/in/boolean_back" : "Back",
			"/actions/main/in/boolean_left" : "Left",
			"/actions/main/in/boolean_right" : "Right",
			"/actions/main/in/boolean_walkkey" : "walkkey",
			"/actions/main/in/boolean_slot1" : "slot1",			
			"/actions/main/in/boolean_slot2" : "slot2",
			"/actions/main/in/boolean_slot3" : "slot3",			
			"/actions/main/in/boolean_slot4" : "slot4",			
			"/actions/main/in/boolean_slot5" : "slot5",			
			"/actions/main/in/boolean_slot6" : "slot6",			
			"/actions/main/in/boolean_teleport" : "teleport",			
			"/actions/main/in/boolean_menucontext" : "context menu",
			"/actions/main/in/boolean_lefthandmode" : "lefthandmode",
			"/actions/main/in/boolean_righthandmode" : "righthandmode",


			"/actions/driving/in/vector1_forward" : "Forward",
			"/actions/driving/in/vector1_reverse" : "Reverse",
			"/actions/driving/in/vector2_steer" : "Steer",
			"/actions/driving/in/boolean_turbo" : "Turbo",
			"/actions/driving/in/boolean_handbrake" : "Handbrake",
			"/actions/driving/in/boolean_turret" : "Turret",
			"/actions/driving/in/boolean_exit" : "Exit Vehicle",
			"/actions/driving/in/boolean_spawnmenu" : "Quickmenu",
			"/actions/driving/in/boolean_left_pickup" : "Left Pickup",
			"/actions/driving/in/boolean_right_pickup" : "Right Pickup"
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
   "app_key" : "system.generated.gmod.exe",
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
                     "output" : "/actions/main/in/boolean_changeweapon"
                  },
                  "east" : {
                     "output" : "/actions/main/in/boolean_turnright"
                  },
                  "north" : {
                     "output" : "/actions/main/in/boolean_secondaryfire"
                  },
                  "south" : {
                     "output" : "/actions/main/in/boolean_flashlight"
                  },
                  "west" : {
                     "output" : "/actions/main/in/boolean_turnleft"
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
      "app_key" : "system.generated.gmod.exe",
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
                     [ "/user/hand/right/input/trigger", "click" ],
                     [ "/user/hand/left/input/trigger", "click" ]
                  ],
                  "output" : "/actions/driving/in/boolean_turret"
               },
               {
                  "inputs" : [
                  [ "/user/hand/left/input/x", "click" ],
                  [ "/user/hand/left/input/y", "click" ]
                  ],
                  "output" : "/actions/driving/in/boolean_exit"
               },
               {
                  "inputs" : [
                     [ "/user/hand/right/input/a", "click" ],
                     [ "/user/hand/right/input/b", "click" ]
                  ],
                  "output" : "/actions/driving/in/boolean_exit"
               }
            ],
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
                     "click" : {
                        "output" : "/actions/driving/in/vector1_reverse"
                     }
                  },
                  "mode" : "trigger",
                  "path" : "/user/hand/left/input/trigger"
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
                        "output" : "/actions/driving/in/boolean_spawnmenu"
                     }
                  },
                  "mode" : "button",
                  "path" : "/user/hand/left/input/y"
               },
               {
                  "inputs" : {
                     "click" : {
                        "output" : "/actions/driving/in/boolean_handbrake"
                     }
                  },
                  "mode" : "button",
                  "path" : "/user/hand/left/input/x"
               },
               {
                  "inputs" : {},
                  "mode" : "trigger",
                  "path" : "/user/hand/left/input/grip"
               },
               {
                  "inputs" : {
                     "position" : {
                        "output" : "/actions/driving/in/vector2_steer"
                     }
                  },
                  "mode" : "joystick",
                  "path" : "/user/hand/right/input/joystick"
               },
               {
                  "inputs" : {},
                  "mode" : "trigger",
                  "path" : "/user/hand/right/input/grip"
               }
            ]
         },
         "/actions/main" : {
            "chords" : [
               {
                  "inputs" : [
                     [ "/user/hand/left/input/y", "click" ],
                     [ "/user/hand/right/input/joystick", "east" ]
                  ],
                  "output" : "/actions/main/in/boolean_slot2"
               },
               {
                  "inputs" : [
                     [ "/user/hand/left/input/y", "click" ],
                     [ "/user/hand/right/input/joystick", "north" ]
                  ],
                  "output" : "/actions/main/in/boolean_slot3"
               },
               {
                  "inputs" : [
                     [ "/user/hand/left/input/y", "click" ],
                     [ "/user/hand/right/input/joystick", "west" ]
                  ],
                  "output" : "/actions/main/in/boolean_slot6"
               },
               {
                  "inputs" : [
                     [ "/user/hand/left/input/y", "click" ],
                     [ "/user/hand/right/input/joystick", "south" ]
                  ],
                  "output" : "/actions/main/in/boolean_slot4"
               },
               {
                  "inputs" : [
                     [ "/user/hand/right/input/joystick", "click" ],
                     [ "/user/hand/left/input/y", "click" ]
                  ],
                  "output" : "/actions/main/in/boolean_slot1"
               },
               {
                  "inputs" : [
                     [ "/user/hand/left/input/joystick", "click" ],
                     [ "/user/hand/right/input/joystick", "click" ]
                  ],
                  "output" : "/actions/main/in/boolean_chat"
               },
               {
                 "inputs" : [
                    [ "/user/hand/left/input/joystick", "click" ],
                    [ "/user/hand/right/input/joystick", "click" ]
                 ],
                 "output" : "/actions/main/in/boolean_flashlight"
              },
               {
                  "inputs" : [
                     [ "/user/hand/left/input/y", "click" ],
                     [ "/user/hand/left/input/x", "click" ]
                  ],
                  "output" : "/actions/main/in/boolean_use"
               },
               {
                  "inputs" : [
                     [ "/user/hand/right/input/b", "click" ],
                     [ "/user/hand/right/input/a", "click" ]
                  ],
                  "output" : "/actions/main/in/boolean_use"
               },
              {
                 "inputs" : [
                    [ "/user/hand/left/input/x", "single" ],
                    [ "/user/hand/left/input/y", "single" ]
                 ],
                 "output" : "/actions/main/in/boolean_menucontext"
              },
              {
                 "inputs" : [
                    [ "/user/hand/left/input/trigger", "single" ],
                    [ "/user/hand/left/input/grip", "single" ],
                    [ "/user/hand/right/input/a", "single" ]
                 ],
                 "output" : "/actions/main/in/boolean_foregrip"
               }
            ],
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
                  "path" : "/user/hand/left/input/grip"
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
                        "output" : "/actions/main/in/boolean_turnright"
                     },
                     "north" : {
                        "output" : "/actions/main/in/boolean_sprint"
                     },
                     "south" : {
                        "output" : "/actions/main/in/boolean_walkkey"
                     },
                     "west" : {
                        "output" : "/actions/main/in/boolean_turnleft"
                     }
                  },
                  "mode" : "dpad",
                  "parameters" : {
                     "sticky" : "true",
                     "sub_mode" : "touch"
                  },
                  "path" : "/user/hand/right/input/joystick"
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
                        "output" : "/actions/main/in/boolean_left_primaryfire"
                     }
                  },
                  "mode" : "button",
                  "path" : "/user/hand/left/input/trigger"
               },
               {
                  "inputs" : {
                     "click" : {
                        "output" : "/actions/main/in/boolean_changeweapon"
                     },
                     "touch" : {
                        "output" : "/actions/main/in/lweaponmenu"
                     }
                  },
                  "mode" : "button",
                  "path" : "/user/hand/left/input/y"
               },
               {
                  "inputs" : {
                     "click" : {
                        "output" : "/actions/main/in/boolean_reload"
                     }
                  },
                  "mode" : "button",
                  "path" : "/user/hand/right/input/b"
               },
               {
                  "inputs" : {
                     "click" : {
                        "output" : "/actions/main/in/boolean_secondaryfire"
                     },
                     "touch" : {
                        "output" : "/actions/main/in/dummy"
                     }
                  },
                  "mode" : "button",
                  "path" : "/user/hand/right/input/a"
               },
               {
                  "inputs" : {
                     "click" : {
                        "output" : "/actions/main/in/boolean_sprint"
                     }
                  },
                  "mode" : "button",
                  "parameters" : {
                     "force_input" : "click",
                     "touchy_click" : "false"
                  },
                  "path" : "/user/hand/right/input/joystick"
               },
               {
                  "inputs" : {
                     "click" : {
                        "output" : "/actions/main/in/boolean_jump"
                     }
                  },
                  "mode" : "button",
                  "path" : "/user/hand/left/input/joystick"
               },
               {
                  "inputs" : {
                     "east" : {
                        "output" : "/actions/main/in/boolean_right"
                     },
                     "north" : {
                        "output" : "/actions/main/in/boolean_forword"
                     },
                     "south" : {
                        "output" : "/actions/main/in/boolean_back"
                     },
                     "west" : {
                        "output" : "/actions/main/in/boolean_left"
                     }
                  },
                  "mode" : "dpad",
                  "parameters" : {
                     "sub_mode" : "touch"
                  },
                  "path" : "/user/hand/left/input/joystick"
               },
               {
                  "inputs" : {
                     "position" : {
                        "output" : "/actions/main/in/vector2_smoothturn"
                     }
                  },
                  "mode" : "joystick",
                  "path" : "/user/hand/right/input/joystick"
               },
               {
                  "inputs" : {
                     "touch" : {
                        "output" : "/actions/main/in/boolean_walk"
                     }
                  },
                  "mode" : "button",
                  "path" : "/user/hand/left/input/joystick"
               },
               {
                  "inputs" : {
                     "click" : {
                        "output" : "/actions/main/in/boolean_use"
                     }
                  },
                  "mode" : "button",
                  "path" : "/user/hand/left/input/x"
               },
                            {
                  "inputs" : {
                     "click" : {
                        "output" : "/actions/main/in/boolean_spawnmenu"
                     }
                  },
                  "mode" : "button",
                  "path" : "/user/hand/left/input/y"
               },
               {
                  "inputs" : {
                     "click" : {
                        "output" : "/actions/main/in/boolean_left_secondaryfire"
                     }
                  },
                  "mode" : "button",
                  "path" : "/user/hand/left/input/y"
              },
              {
                 "inputs" : {
                    "center" : {
                       "output" : "/actions/main/in/boolean_teleport"
                    }
                 },
                 "mode" : "dpad",
                 "parameters" : {
                    "sub_mode" : "click"
                 },
                 "path" : "/user/hand/right/input/joystick"
               }
            ]
         }
      },
      "category" : "steamvr_input",
      "controller_type" : "oculus_touch",
      "description" : "[Y] WEAPON MENU + QUICK Menu \n[X]USE\n--\n[L Stick] Move\n[L Stick PUSH] Jump\n--\n[R Stick PUSH] Sprint\n[R Stick Left Right] Turn\n[R Stick Down] Walk\n[R Stick Up] Sprint\n--\n[R Trigger] Primary Fire / Accel\n[A]RELOAD / HandBrake\n[B]SecondaryFire / Turbo\n[L Trigger] (Left_Primary_fire) / Brake\n--\n[L Grip] Lefthand Pickup\n[R Grip] Righthand Pickup\n--\n[R Stick PUSH] + [L Stick PUSH] Flashlight\n[R Stick PUSH] + [L Stick PUSH] (Chatbutton)",
      "interaction_profile" : "",
      "name" : "Gmod-SemiOffcialVersionKeyConfig(Ver6.0)",
      "options" : {
         "simulated_controller_type" : "oculus_touch"
      },
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
   "action_manifest_version" : 0,
   "alias_info" : {},
   "app_key" : "system.generated.gmod.exe",
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
                     "output" : "/actions/main/in/boolean_changeweapon"
                  },
                  "east" : {
                     "output" : "/actions/main/in/boolean_turnright"
                  },
                  "north" : {
                     "output" : "/actions/main/in/boolean_secondaryfire"
                  },
                  "south" : {
                     "output" : "/actions/main/in/boolean_flashlight"
                  },
                  "west" : {
                     "output" : "/actions/main/in/boolean_turnleft"
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
   "controller_type" : "vive_controller",
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
g_VR.bindings_knuckles = [[
{
   "action_manifest_version" : 0,
   "alias_info" : {},
   "app_key" : "system.generated.gmod.exe",
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
                  "position" : {
                     "output" : "/actions/driving/in/vector2_steer"
                  }
               },
               "mode" : "joystick",
               "path" : "/user/hand/left/input/thumbstick"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/driving/in/boolean_turret"
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
               "path" : "/user/hand/left/input/b"
            }
         ]
      },
      "/actions/main" : {
         "sources" : [
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
                  "click" : {
                     "output" : "/actions/main/in/boolean_changeweapon"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/right/input/trackpad"
            },
            {
               "inputs" : {
                  "east" : {
                     "output" : "/actions/main/in/boolean_turnright"
                  },
                  "north" : {
                     "output" : "/actions/main/in/boolean_secondaryfire"
                  },
                  "south" : {
                     "output" : "/actions/main/in/boolean_flashlight"
                  },
                  "west" : {
                     "output" : "/actions/main/in/boolean_turnleft"
                  }
               },
               "mode" : "dpad",
               "parameters" : {
	       "deadzone_pct" : "90",
                  "overlap_pct" : "0",
                  "sub_mode" : "touch"
               },
               "path" : "/user/hand/right/input/thumbstick"
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
               "parameters" : {
                  "force_input" : "force",
	       "click_activate_threshold": "0.45",
	       "click_deactivate_threshold": "0.4"
               },
               "path" : "/user/hand/right/input/grip"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_use"
                  }
               },
               "mode" : "button",
               "parameters" : {
                  "force_input" : "force",
	       "click_activate_threshold": "0.45",
	       "click_deactivate_threshold": "0.4",
                  "haptic_amplitude" : "0"
               },
               "path" : "/user/hand/right/input/grip"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_chat"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/left/input/trackpad"
            },
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
               "path" : "/user/hand/left/input/thumbstick"
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
                  "force_input" : "position",
                  "haptic_amplitude" : "0"
               },
               "path" : "/user/hand/left/input/thumbstick"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_left_pickup"
                  }
               },
               "mode" : "button",
               "parameters" : {
                  "force_input" : "force",
	       "click_activate_threshold": "0.45",
	       "click_deactivate_threshold": "0.4"
               },
               "path" : "/user/hand/left/input/grip"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_use"
                  }
               },
               "mode" : "button",
               "parameters" : {
                  "force_input" : "force",
	       "click_activate_threshold": "0.45",
	       "click_deactivate_threshold": "0.4",
                  "haptic_amplitude" : "0"
               },
               "path" : "/user/hand/left/input/grip"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_sprint"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/left/input/thumbstick"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_reload"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/left/input/b"
            },
            {
               "inputs" : {
                  "click" : {
                     "output" : "/actions/main/in/boolean_undo"
                  }
               },
               "mode" : "button",
               "path" : "/user/hand/left/input/a"
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
               "path" : "/user/hand/right/input/thumbstick"
            }
         ]
      }
   },
   "category" : "steamvr_input",
   "controller_type" : "knuckles",
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
g_VR.bindings_cosmos = [[

{
   "action_manifest_version" : 0,
   "alias_info" : {},
   "app_key" : "system.generated.gmod.exe",
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
                     "output" : "/actions/main/in/boolean_turnright"
                  },
                  "north" : {
                     "output" : "/actions/main/in/boolean_secondaryfire"
                  },
                  "south" : {
                     "output" : "/actions/main/in/boolean_flashlight"
                  },
                  "west" : {
                     "output" : "/actions/main/in/boolean_turnleft"
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
   "app_key" : "system.generated.gmod.exe",
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
   "app_key" : "system.generated.gmod.exe",
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
   "app_key" : "system.generated.gmod.exe",
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
local function WriteBindingFiles()
   if not file.Exists("vrmod", "DATA") then file.CreateDir("vrmod") end
   file.Write("vrmod/vrmod_action_manifest.txt", g_VR.action_manifest)
   file.Write("vrmod/vrmod_bindings_holographic_controller.txt", g_VR.bindings_holographic)
   file.Write("vrmod/vrmod_bindings_oculus_touch.txt", g_VR.bindings_touch)
   file.Write("vrmod/vrmod_bindings_vive_controller.txt", g_VR.bindings_vive)
   file.Write("vrmod/vrmod_bindings_knuckles.txt", g_VR.bindings_knuckles)
   file.Write("vrmod/vrmod_bindings_vive_cosmos_controller.txt", g_VR.bindings_cosmos)
   file.Write("vrmod/vrmod_bindings_vive_tracker_left_foot.txt", g_VR.bindings_vive_tracker_left_foot)
   file.Write("vrmod/vrmod_bindings_vive_tracker_right_foot.txt", g_VR.bindings_vive_tracker_right_foot)
   file.Write("vrmod/vrmod_bindings_vive_tracker_waist.txt", g_VR.bindings_vive_tracker_waist)
end

local cv_bindingVersion = CreateClientConVar("vrmod_bindingversion", "0", true, false)
if cv_bindingVersion:GetInt() < 16 then
   cv_bindingVersion:SetInt(16)
   WriteBindingFiles()
end

hook.Add("VRMod_Reset", "vrmod_reset_bindings", function() WriteBindingFiles() end)