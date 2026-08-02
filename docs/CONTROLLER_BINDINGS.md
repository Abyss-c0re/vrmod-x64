# Controller bindings — SteamVR binding UI replacement

## Law

On the **OpenXR** path (gVRMod / WiVRn / Monado / Quest), this system **is** the binding UI.  
Do **not** open SteamVR’s “Configure Controller” for VRMod rebinds.

| Old (SteamVR) | New (VRMod) |
|---------------|-------------|
| SteamVR binding UI | Hand panel `vrmod_controller_bindings` (+ desktop Derma) |
| `vrmod_bindings_oculus_touch.txt` consumed by SteamVR | C++ suggest + Lua `DefaultMap` (Quest gold) |
| SteamVR chords | Lua `mode=all` + conflict detector |
| Action sets main / driving | On foot / Vehicle tabs |

SteamVR binding JSON files are still **written** for dual-install / legacy OpenVR modules. OpenXR does **not** use them for rebind.

## What you get

- **Quest 3 / Touch defaults** — zero setup.
- **VR:** hand surface — **On foot / Vehicle**, Bind / Chord / Def, live sources, conflicts.
- **Desktop:** Derma (same model). Never float Derma into the HMD.

## Open

| Path | Command |
|------|---------|
| Quick menu | Bindings |
| Settings → Bindings | Controller rebind |
| Console | `vrmod_controller_bindings` |

## Engine

- `vrmod.bindings` — map, apply, chords (`mode=all` needs 2+ buttons)
- `DetectConflicts` — hard / soft
- Persist: `data/vrmod/vrmod_openxr_bindings.json` (merge over defaults)
