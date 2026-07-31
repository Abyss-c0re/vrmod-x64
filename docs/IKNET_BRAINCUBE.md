# IK Network → Braincube NPC Mimic

**Law:** one frame schema · one charik apply path · cube nonverbal training.

## Energy path

```
VR tracking / net tick
  → absolute frame (sh_network schema)
  → FrameToRelative(feet+yaw)          # retargetable
  → iknet buffer / plate export
  → BrainDecide(bits → algocube digit + payload)
  → FrameToAbsolute(NPC stand)
  → charik.Init + Update + ApplyMatrices   # same as player/twin
```

| Consumer | Role |
|----------|------|
| Player | `cl_character` + net `lerpedFrame` |
| Twin | pose snap / charik TransformFrame |
| **NPC** | `vrmod.iknet.mimic` (this module) |
| Braincube | `ExportPlate` → `data/vrmod/iknet/*.ndjson` |

## Files

| File | Side | Role |
|------|------|------|
| `utils/sh_frames.lua` | SH | `FrameToRelative` / `FrameToAbsolute` / `FrameOrigin` |
| `utils/sh_iknet.lua` | SH | Pack, buffer, features, bits, `BrainDecide`, plate export |
| `utils/cl_iknet_mimic.lua` | CL | Record + NPC/ClientsideModel mimic |
| `network/sv_iknet.lua` | SV | Bind/spawn NPC, net relay to clients |

## Player present

```
// client — record while in VR
vrmod_iknet_record_start
// … move arms …
vrmod_iknet_record_stop
vrmod_iknet_record_save my_session

// server (admin)
vrmod_iknet_spawn train
// or aim at NPC:
vrmod_iknet_bind <ent> STEAM_0:x:y train

// client playback onto aimed NPC
vrmod_iknet_playback
vrmod_iknet_status
```

## Without player (server autotest)

```
// rcon / server console
vrmod_iknet_spawn
// binds npc_citizen; clients with addon apply when a VR source exists
// without VR, bind still registers; mimic no-ops until frames appear
```

Headless log gates (deploy cycle):

1. Server print `[iknet] server ready`
2. After spawn: `[iknet] spawned mimic ent=`
3. Client: `vrmod_iknet_status` → sessions list
4. Training files: `garrysmod/data/vrmod/iknet/*.ndjson`

## Braincube plate

Each sample:

- `feat` — float feature vector  
- `bits` — 256-bit string for SMX/matrix  
- `digit` / `payload` — algocube DECIDE  
- `frame` — packed relative IK  

Feed external braincube / cubalc samples with `bits` + `digit` as teacher signal; playback uses `frame` only (pose truth), not prose.

## Smoke

1. VR start → record 10s → save  
2. `vrmod_iknet_spawn train` in front of you  
3. NPC arms track your hands (retargeted to NPC origin)  
4. `vrmod_iknet_status` shows `brain digit=`  
5. Raise right hand → NPC right hand (live, no L↔R)  
