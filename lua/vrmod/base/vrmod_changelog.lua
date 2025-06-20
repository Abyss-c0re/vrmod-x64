if SERVER then return end
local changelog = [[

Version 200 - Gmod 64 Edition:
- Re-organized the project structure
- Integrated UI changes (attach to hand) from semi-official (Pescorr)
- Integrated fixed manual item pick up, simple hads physics and melee
- Drop and pickup weapons - Pescorr
- Integrated flat to vr weapon replacer
- Fixed rendering issues on x64 Linux Native build
- Adapted image for Quest 3 and Quest 2
- Replaced icons with text on weapon selector due to the missing icons on custom weapons

Version 133:
-fixed teleport beam not stopping at playerclips
-fixed voice permission popup appearing for all players in multiplayer when someone enters vr

Version 132:
-updated voice chat to use new permission system introduced in a gmod update

Version 131:
-adjusted default values for vrmod_net_ convars, this should also fix an issue some people had with vr player animations getting stuck on listen servers
-added vrmod_info concmd which can be used to provide some details for troubleshooting

Version 130:
-fixed vr player location freezing while buffering for more network data

Version 129:
-added "reset vehicle view" button to quickmenu
-removed seated mode toggle from quickmenu and moved it to the vrmod settings panel so it can be toggled on/off permanently,
also added seated mode offset adjustment to height menu

Version 128:
-playermodel no longer flips when looking down past 90 degrees
-added scale multiplier adjustment to flex binding interface
-networked face/eye tracking
-potentially fixed incorrect player eye movement direction and eyes disappearing when closing one eye

Version 127:
-added experimental support for vive pro eye tracking and the vive facial tracker,
including an interface for editing binding of facial tracker data to player flexes
-fixed 3 lua errors
-its now possible to exit fbt mode by restarting vrmod

Version 126:
-removed waiting for tracking screen
-fixed other vr players body rotation getting messed up in multiplayer sometimes

Version 125:
-added option to enable hud, and convars for adjusting it (vrmod_hud*)

Version 124:
-derma popup menus now automatically show up in vr, dropdowns are now also usable
-vrmod_start waits until game is unpaused
-added back vrmod_showonstartup that got accidentally removed in a previous update

Version 123:
-made the vrmod menu more modular
-added changelog to vrmod menu
-added flashlight attachment point option (vrmod_flashlight_attachment convar)
-fixed vr flashlight not being removed when exiting vr
-vr flashlight can no longer be used if flashlight usage is blocked on desktop
-added left hand fire binds for lefthanded weapon support
-better lua loading order management
-fixed a lua error when opening vr chat on servers with some custom chat addons

Version 122:
-added seated mode
-added crouch bind
-added support for wip linux module

Version 121:
-fixed bug where player would move around uncontrollably on its own in multiplayer when the users ping is high and fps is low

Version 120:
-added option to open doors by grabbing the handle
-added limits to netmessages

Version 119:
-updated locomotion system to prevent physical player location from getting desynchronized from the view
-locomotion settings can now be changed realtime without a vrmod restart
-fixed smooth turn rate slider not working and creating lua errors
-fixed a bunch of lua errors that could be created by triggering various controller inputs without controller tracking data
-added serverside cvar vrmod_allow_teleport

Version 118:
-blocked running vrmod_exit if not in vr
-blocked running vrmod_start if no module
-fixed inf positions when losing tracking causing player limbs to disappear and lua errors
-fixed lua error when exiting vr after trying to use an incompatible pm
-fixed fbt system not checking pm compatibility for other players
-fixed a bunch of errors related to changing playermodels
-fixed random lua errors when trying to walk while dead while using fbt
-fixed random lua errors while using fbt while other players are joining

Version 117:
-blocked running vrmod_start if already in vr, this used to cause problems like some convars not getting restored properly upon exiting vr
-fixed lua error in multiplayer when a prop that has a halo gets removed
-fixed lua error in multiplayer when a prop that has a worldtip gets removed
-fixed serverside lua error when trying to pick up a prop that is already being held by another vr user
-fixed weird behaviour when multiple vr users are holding props

Version 116:
-fixed root cause behind at least 3 different lua errors that could happen randomly in multiplayer
-fixed some error spam related to pac3
-fixed 2 errors related to disconnecting while in vr
-pac outfits are now automatically rendered in both eyes when in vr

Version 115:
-adds support for (and requires) module version 20. The changes to the module are:
-GetPoses/GetActions now re-use most tables instead of creating new ones every time.
This should be better for performance and also allows creating direct references to poses
in lua without having to access them through multiple tables every time.
-Removed string comparisons from GetPoses/GetActions as a micro optimization.
-GetActions now additionally returns a table of changed boolean actions. This is to avoid
having to loop thru every action on the lua side to manually check for changes and makes
checking for presses/releases easier in general.
-GetDisplayInfo now takes nearz/farz values as arguments instead of using hardcoded values

Version 114:
-adds support for (and requires) module version 19. This version moves rendering related calculations from the module to the addon. This makes it possible to do rendering experiments and things like native offset projection and support for canted displays without reprojection in the future without requiring additional module updates. Also added error code display to vr_init errors

Version 113:
-fixed floating hands randomly not working

Version 112:
-added option to enable engine postprocessing (such as bloom or color correction built into maps)
-fixed bug that would break the game if you died while hovering over a weapon icon with the VR weapon menu open
-fixed vr menu system cursor focusing on the wrong layer when there are overlapping menus (such as settings window in front of height adjustment window)
-added haptics to grip binds for default index controller binds and reduced grip force threshold by 20%. There used to be a bug in SteamVR where haptics would always be triggered on the index controllers at a certain grip force even if it was disabled in the binds or when the grips weren't used at all. The old default binds were designed around this bug by matching the force threshold in the binds to this unwanted haptic feedback. It seems like this was fixed in some SteamVR update which left index users with no haptic feedback for the default vrmod grip binds.
-fixed bug where viewmodel muzzle position would get warped based on head angle for some users depending on their gmod settings (noticeable with the weapon laserpointer option enabled). Also fixed a similiar bug where this would always happen with the toolgun.

Version 111:
-fixed errors in multiplayer introduced by 110

Version 110:
-added support for worldtips (such as those that appear when aiming at thrusters)
-added support for halos, this fixes issues such as the view going blurry with the physgun pickup halo, or other halos only rendering in one eye

Version 109:
-players arms no longer get messed up when the player is tilted too much in a chair
-fixed head not moving properly while in a chair
-fixed controls not working when starting vr while in a vehicle
-fixed view stuck in ground sometimes after exiting vr
-fixed height mirror not following view properly sometimes
-height mirror is no longer rendered in reflections
-player is now fullbright in height mirror

Version 108:
-potentially fixed error messages not displaying in vrmod menu for some people
-fixed lua error when enabling climbing system in unsupported maps
-updated module version display to the actual latest version
-added detection for error case where module is installed but not initializing
-removed vrmod_update concommand (which was used to display module update script location) as a recent gmod update removed the function it relied on

Version 107:
-added wip climbing system, which is currently limited to ladders in HL2 maps in single player
-vr flashlight is now affected by r_flashlightfar and r_flashlightfov convars
-added vrmod_version convar which should be visible in server queries, making it easier to search for vrmod enabled servers

Version 106:
-fixed pickup system bug which could result in being unable to spawn ammo while using arcvr guns

Version 105:
-fixed menu clicks registering multiple times on some controller bindings, most commonly causing vive users to not be able to press the chat keyboard button

Version 104:
-picking up a prop no longer resets some of its physical properties (for example gravity and welds), this also fixes a bug where plugging in the teleporter in kleiners lab would crash the game sometimes
-added convar for adjusting crouch height threshold: vrmod_crouchthreshold

Version 103:
-a new module version is available which fixes the "CreateDevice failed" error and some others

Version 102:
-added noclip to quickmenu

Version 101:
-added improved teleport locomotion inspired by steamvr home. it can be accessed using the previously unused "chat" controller bind
-removed old teleport tool

Version 100:
-removed vr hands from player models
-replaced "hide player model" option with "use floating hands". This is also usable in multiplayer unlike the previous single-player only playermodel, as this keeps your original player model. Currently only supports a single hand model, but the plan is to support all stock viewmodel hands in the future as well as addon hand models
-fixed glitched looking hand when using weapons that don't have a hand pose (caused by a previous update)
-added some lua api functions:
vrmod.GetTrackedDeviceNames() (requires module update)
vrmod.GetLeftEyePos()
vrmod.GetRightEyePos()
vrmod.GetEyePos()
vrmod.SetOriginPos()
vrmod.SetOriginAng()

Version 99.4:
-improved fbt playermodel compatibility

Version 99.3:
-fixed voice button displaying incorrect state caused by a previous update

Version 99.2:
-fixed map browser broken by a previous update

Version 99.1:
-fixed selecting weapons being broken on some player models caused by previous update

Version 99:
-added support for 6-point full-body tracking. a button to enter calibration will appear in the in-game vr quickmenu if 3 vive trackers are connected with the roles "waist", "left foot" and "right foot". When entering calibration your player model will go into a t-pose and you should line up your head, waist and feet with the player model and press the "reload" bind to finish calibration
-improved camera transition when entering/exiting vehicles
-hdr no longer affects menus to improve visibility
-fixed teleport tool lua error caused by a previous update
-fixed misaligned hands sometimes in vehicles caused by a previous update
-fixed player disappearing while waiting for tracking in multiplayer caused by a previous update
-fixed vr players not appearing to be in vr to players joining later caused by a previous update
-renamed hooks to not use the old VRUtil* naming scheme. A backwards compatibility system is temporarily in place so most compatible addons should still work
-added lua api function vrmod.RemoveInGameMenuItem( name )
-added hook "VRMod_OpenQuickMenu"
-adding a quickmenu item with existing name overwrites instead of adding a new one
-more small changes behind the scenes that will most likely break stuff

Version 98:
-fixed eye deflection limits not working (eyes going backwards when aiming a gun backwards)

Version 97.1:
-fixed bug when trying to open spawn/context menu if they don't exist

Version 97:
-removed vrmod menu from sandbox spawn menu utilities. It can now be accessed using the new "vrmod" console command instead, this makes it possible to access it everywhere, not just in sandbox.
-renamed vrutil_* convars to vrmod_*
-added concommand "vrmod_showonstartup" which could be used to start vrmod via the steamvr desktop
-the spawn menu button now opens a menu that can be used to access multiple things, it currently contains map browser, chat, spawn menu, context menu, vrmod menu
-chat no longer uses a separate input
-removed map browser from context menu
-added "Reset settings to default" button to vrmod menu
-added Lua API function vrmod.AddInGameMenuItem( name, slot, slotpos, func, reopenfunc )

Version 96:
-made the locomotion system modular, this makes it easier to add more locomotion options in the future as well as makes it easier for addons to add new locomotion types and take control of the player
-added following functions to Lua API:
vrmod.AddLocomotionOption( name, startFunc, stopFunc, buildCPanelFunc )
vrmod.StartLocomotion()
vrmod.StopLocomotion()
vrmod.GetOriginPos()
vrmod.GetOriginAng()
vrmod.GetOrigin()
vrmod.SetOrigin( pos, ang )

Version 95.2:
-desktop view defaults to right eye
-added more functions to Lua API:
vrmod.UsingEmptyHands( ply )
vrmod.GetHMDPose( ply )
vrmod.GetHMDVelocity()
vrmod.GetHMDAngularVelocity()
vrmod.GetHMDVelocities()
vrmod.GetLeftHandPose( ply )
vrmod.GetLeftHandVelocity()
vrmod.GetLeftHandAngularVelocity()
vrmod.GetLeftHandVelocities()
vrmod.GetRightHandPose( ply )
vrmod.GetRightHandVelocity()
vrmod.GetRightHandAngularVelocity()
vrmod.GetRightHandVelocities()
vrmod.GetDefaultLeftHandOpenFingerAngles()
vrmod.GetDefaultLeftHandClosedFingerAngles()
vrmod.GetDefaultRightHandOpenFingerAngles()
vrmod.GetDefaultRightHandClosedFingerAngles()
vrmod.GetLeftHandFingerAnglesFromModel( modelName, sequenceNumber )
vrmod.GetRightHandFingerAnglesFromModel( modelName, sequenceNumber )
vrmod.GetLeftHandPoseFromModel( modelName, sequenceNumber, refBoneName )
vrmod.GetRightHandPoseFromModel( modelName, sequenceNumber, refBoneName )
vrmod.GetLerpedFingerAngles( fraction, from, to )
vrmod.GetLerpedHandPose( fraction, fromPos, fromAng, toPos, toAng )
vrmod.SetViewModelOffsetForWeaponClass( classname, pos, ang )

Version 95.1:
-"show height adjustment menu" defaults to enabled

Version 95:
-added better height adjustment system, removed height slider
-added Lua API
-an optional module update is available, it fixes a bug which could lead to controller input not working

Version 94.2:
-fixed chat glitching out when spamming messages to it every frame

Version 94.1:
-action editor no longer allows creating actions with invalid names and breaking all controller input as a result

Version 94:
-added custom input action editor which can be used to add new controller binds that run console commands

Version 93:
-fixed jumping out of water not working
-fixed not being able to get onto ladders by walking at them

Version 92.3:
-potentially fixed player collisions never updating when using custom controller binds with incorrectly bound boolean_walk action

Version 92.2:
-fixed incorrect hand positions being sent to server while using some viewmodels
-server now stores latest received frame which makes it easier to get vr players tracking info serverside

Version 92.1:
-fixed error spam when dead caused by previous update

Version 92:
-added support for view entity overriding, this means the camera tool and some map cutscenes work properly now
-added dropdown for selecting which eye to use for desktop view
-moved vr prerender hooks so that they're actually called right before rendering, this makes it easier to read the position of the view that is about to be rendered, also stopped using the same prerender hook internally to update local players net frame (it gets updated earlier now) which makes it easier to override visual hand positions from the prerender hook without a race condition

Version 91:
-playermodel now gets oriented in a way which provides optimal arm reach
-added convar "vrutil_oldcharacteryaw" which can be used to switch to the old behaviour

Version 90.1:
-fixed crouching not working properly caused by previous update
-potentially fixed finger tracking sometimes breaking when re-entering vr

Version 90:
-optimized playermodel ik calculations to run only once per frame (previous worst case it could run up to 10 times/frame)
-added run and jump animations
-slightly reduced vr player network bandwidth usage (~5%)
-vr players visual location no longer lags behind physical location in multiplayer, also fixed arms lagging behind when being moved in a seat
-updated cardboard mode to work with latest module
-fixed getting stuck in a teleporting loop
-being flung through the air works better now
-locomotion is slightly smoother
-fixed viewmodel being rendered in mirrors (and player also getting rendered twice)
-fixed weapon menu not working if other menus were open at the same time
-fixed chat not scrolling to end after opening
-fixed a pickup hook bug
-increased nametag range

Version 89:
-reduced vr player network bandwidth usage by around 35% by increasing compression (8.5 to 5.5 kbit/s/player)
-improved networking to better handle packets that were dropped, received out of order, or received at unstable intervals
-better tolerance for high ping
-switched vr networking ticks over to unreliable networking layer to avoid overflowing reliable layer
-improved vr player animation/buffering control
-reduced default lerp delay/buffer from 500ms to 300ms
-added visual networking debugger that can be toggled with "vrutil_net_debug" console command
-added convars for adjusting networking related parameters: vrutil_net_tickrate, vrutil_net_delay, vrutil_net_delaymax, vrutil_net_storedframes

Version 88:
-added "VR Hands" player model, available in singleplayer (floating hands with extended reach)

Version 87:
-added analog smooth turn bind for better smooth turning
-added "Copy module update script location to clipboard" button which appears if the module is outdated to aid people who are having a hard time trying to update the module
-changed default znear to 1 to reduce objects clipping with player view

Version 86:
-the player head is now hidden in first person to avoid visibility problems

Version 85:
-fixed entities disappearing when sticking weapon muzzle through a wall
-fixed a bug in prop pickup permission check

Version 84:
-added smooth turning option

Version 83:
-a new module version is available which should fix some visual glitches such as flickering when using high amounts of supersampling in SteamVR settings.

Version 82:
-rendering using the VR resolution is now always enabled thanks to the gmod march 2020 update

Version 81:
-fixed some vr projection issues caused by display asymmetries in some vr headsets
-added installed/latest module version display to utility menu
this update requires a module update

Version 80.2:
-"Render using VR target resolution" option now works on all beta branches

Version 80.1:
-added hook VRUtilEventPreRenderRight

Version 80:
-added "Restart VR" button to the VRMod Utility menu which appears when in VR
-"Render using VR target resolution" option can no longer be selected when using an unsupported branch of GMod
For developers:
-added hook VRUtilEventPostRender
-vr rendertarget is now globally accessible using g_VR.rt

Version 79:
-skybox is no longer blacked out when the "Render using VR target resolution" option is checked as related issues should now be fixed on GMod's dev, chromium, and x86-64 branches.

Version 78:
-added in-game map browser (available through the context menu)

Version 77:
-added vrutil_znear convar for adjusting near clipping plane distance

For developers:
-view parameters are now globally accessible: g_VR.view
-left and right eye positions are now available: g_VR.eyePosLeft, g_VR.eyePosRight

Version 76.2:
-fixed chat bind not working

Version 76.1:
-adjusted default vive binds

Version 76:
-Updated default binds: pickup/use has been moved from trigger to grip, so they don't conflict with primaryfire. added separate right pickup bind instead of it being connected to primaryfire. added analog trigger bind for use by 3rd party addons. added separated driving controls. actions now have user friendly names in the binding editor.
Existing custom bindings are incompatible with the new version.

For developers:
-VRUtilEventInput hook now includes action and state parameters and it gets called separately for each action that had a state change
-added clientside VRUtilAllowDefaultAction(string action) hook that can be used to block default action behaviour. Removed old inputBlacklist system
-added VRUtilEventTracking() hook that is called after tracking data has been updated but before it is used anywhere so that it can be overridden.
-pickup/drop functions are now global, VRUtilPickup(bool leftHand) VRUtilDrop(bool leftHand)
-getting viewmodel bone positions while in vr (using getbonematrix etc) should work better now
-added VRUtilEventPickup(ply, ent) and VRUtilEventDrop(ply, ent) hooks on both client and server. Returning false in the pickup hook on the server will block pickup.

Version 75:
-new weapon menu that is easier and quicker to use, and it now also displays alt ammo count
-spawnmenu now follows the player
-fixed menus sometimes not rendering on top, also removed the option as its better to have it always enabled
-performance optimization: fixed some things being rendered twice as many times as they should, such as playermodel, viewmodel, menus

Version 74:
-teleport tool now requires noclip permissions
-picking up stuff while seated works again (was broken by previous update)
-fixed weird finger behaviour when using controllers that don't support skeletal input

Version 73:
-vehicle mounted guns are now usable
-vehicle boost and handbrake are now usable
-added workaround for not being able to climb out of water at a spot in hl2 canals
-autostart should work more reliably in cases where you don't have a valid playermodel right at the start of the game (such as when using the Lambda Framework gamemode)

Version 72.7:
-fixed playermodel disappearing and teleporting towards center of map after dying

Version 72.6
-reduced requirements for player model compatibility
-"incompatible player model" error message now includes a reason for the incompatibility

Version 72.5
-fixed medkit viewmodel offset
-fixed flashlight not working when using worldmodels

Version 72.4
-fixed weapons being completely broken when using a playermodel without fully modeled fingers
-more robust fix for white menus bug
-removed vrutil_autostartsystime convar to simplify enabling autostart via console

Version 72.3
-fixed bug where menus would appear white on the x64 chromium beta branch

Version 72.2
-updated cardboard mode to work with newest module version

Version 72.1
-fixed crowbar hit pos being way off caused by previous update
-fixed flashlight broken by previous update

Version 72:
-viewmodel animations are now always enabled. This is still a work in progress so currently the players hand will glitch out with many weapons
-removed alternative scale option for better compatibility, the player model is now always regular size
-removed finger tracking option, it is now always enabled
-removed advanced display options since the display parameters are calculated automatically

Version 71.1
-fixed bug related to exiting vr in single player caused by previous update
-added compatibility for new module version. updating to it is optional, it only adds better error handling so that in the event of an error the game doesn't freeze and you no longer get spammed with multiple buggy error popups, instead it will throw a single relevant error to the console.

Version 71:
-fixed issue where players would get spammed by lua errors on servers with ulib installed when someone disconnects while in VR
]]
hook.Add("VRMod_Menu", "changelog", function(frame)
	local panel = vgui.Create("DPanel", frame.DPropertySheet)
	frame.DPropertySheet:AddSheet("Changelog", panel)
	local richtext = vgui.Create("RichText", panel)
	richtext:Dock(FILL)
	richtext:InsertColorChange(0, 0, 0, 255)
	richtext:AppendText(changelog)
	richtext.PerformLayout = function(self)
		richtext:SetBGColor(255, 255, 255, 255)
		richtext:SetFGColor(0, 0, 0, 255)
		richtext:SetFontInternal("DermaDefault")
	end
end)