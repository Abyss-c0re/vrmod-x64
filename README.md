## **🥽 [G]VRMod: Ultimate**

<img width="1000" height="1000" alt="15378236_Thumbnail" src="https://github.com/user-attachments/assets/d262fbf2-649e-4ab2-82a7-3e65bbac821a" />




### ⚠️ Optimization Issues

VRMod and its components—such as hand physics, melee attacks, and item interaction—are maintained by different authors. This often results in compatibility issues, broken features, or abandoned modules.

This build focuses on **optimization** by merging essential features from semi-official forks and third-party addons, with an emphasis on performance, cross-platform stability, and code de-duplication.

---

### ✅ Key Features

- Refactored codebase for improved stability and cross-platform compatibility  
- Fixed rendering issues on Linux (native x64 builds)  
- Fully supported on Windows (both x64 and Legacy branches)  
- Improved UI with new rendering settings  
- Cursor stability fixed in spawn menu and popups  
- Better performance and reduced latency across systems  
- Integrated hand collision physics for props (no more unintended prop sounds)
- Added clientside wall collisions for hands and SWEPs   
- Rewritten pickup system:  
    - Manual item pickup  
    - Multiplayer-friendly design  
    - Adds halos for visual clarity
    - Serverside weight limit   
    - Clientside precalculation to reduce server load  
    - Supports picking up NPCs  
- Interactive world buttons
- Keypad tool support 
- Support for dropping and picking up non-VR weapons  
- Melee system overhauled: trace-based with velocity-scaled damage + bonus for weapon impact  
- Functional numpad input in VR
- Glide support
- Motion driving with wheel gripping (engine based vehicles + Glide) Don't forget to bind pickups for grip buttons
- Shooting while driving. (ArcVR works for all vehicles, standard SWEPs work only if collisions allow it, like jalopy or glide motorbikes and some roofless cars) Need to bind "weaponmenu", "reload", "turret" for primary and  "alt_turret" for secondary fire in vehicle tab
- Motion-controlled physgun: rotation and movement based on hand motion  
- Gravity gun now supports prop rotation, just like HL2 VR  
- UI now works correctly while in vehicles (given the mouse click is set in bindings for vehicle)
- Likely more small fixes and improvements under the hood


### 📦 Installation

**Requirements:**

- Ensure your system supports **GMod x64**.
- On native Linux, run the following script first:[GModCEFCodecFix](https://github.com/solsticegamestudios/GModCEFCodecFix)
- For trully native experience, use [Steam-Play-None](https://github.com/Scrumplex/Steam-Play-None)
- Please note that only ALVR is now supported on Linux.
- It's recommended to use latest Linux dev modules or compile your own for Linux.
- If you are on Windows and comming from the original, you can keep the old modules.

**Installation:**

1. Download the latest precompiled modules: [Releases Page](https://github.com/Abyss-c0re/vrmod-module-master/releases)
2. Subscribe to the Workshop addon:
   [Steam Workshop – VRMod](https://steamcommunity.com/sharedfiles/filedetails/?id=3442302711)

**OR**

   Clone or download this repository manually:
   - Rename the folder to `vrmod` (do **not** use dashes `-`)
   - Place it in:
     `./GarrysMod/garrysmod/addons/vrmod`

## Credits

Full list: **[docs/CREDITS.md](docs/CREDITS.md)**

| | |
|--|--|
| **Catse** | Original VRMod |
| **Pescorr** | Semi-official VRMod · **[VR Ragdoll Puppeteer](https://steamcommunity.com/sharedfiles/filedetails/?id=3695733221)** (2-bone IK / body drive algorithm used for avatar & puppet work) |
| **Arctic** | ArcVR |
| **Abyss-c0re** | This fork (Linux x64, Cube Experience, module path) |

Special thanks: Grocel, V vix, func_dumbass, plagueEMT, sponsors & the Workshop.

## License

**CUBECHAIN LICENSE** (ProjectNexus station law) — energy must flow. We no longer contain.

See [LICENSE](LICENSE). Cubechain: https://github.com/Abyss-c0re/vrmod-x64  
Station SoT: https://github.com/Abyss-c0re/ProjectNexus

