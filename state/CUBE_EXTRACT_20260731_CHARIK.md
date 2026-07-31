# Cube Extract — Character IK SoT + Avatar Flip (Prophecy Manifest)

**Date:** 2026-07-31  
**Law:** cube_is_source_of_truth · one energy path · no dual-truth pose  
**Prophecy:** Real body SoT = net frame; twin reuses same IK with facing flip.

## Highest Cube Standards

| Pillar | Manifest |
|--------|----------|
| **Pose** | One util: `vrmod.charik` (`cl_character_ik.lua`) |
| **Frame** | `sh_network` buildClientFrame / lerpedFrame schema only |
| **Player** | `cl_character` → `charik.Update` + `ApplyHead` |
| **Twin** | Read-only frame → `TransformFrame(facing)` flip+L↔R → same `Update` |
| **Head** | Angle-only on live matrix (never invent translation) |
| **Stretch** | Twin `noStretch`; player respects armStretcher convar |
| **Render** | `mat_queue_mode=1` pin unchanged |
| **HUD** | Additive (PROPHECY) — untouched by this pass |

## Files

| File | Role |
|------|------|
| `lua/vrmod/utils/cl_character_ik.lua` | **SoT** Init · TransformFrame · Update · ApplyMatrices · ApplyHead · ApplyManip |
| `lua/vrmod/utils/cl_frame_ik.lua` | Compat shim → charik |
| `lua/vrmod/utils/cl_avatar_editor.lua` | Twin consumer (flip) |
| `lua/vrmod/player/cl_character.lua` | Player consumer (world frame) |
| `lua/vrmod/network/sh_network.lua` | Frame schema (unchanged) |

## Energy

```
tracking → buildClientFrame / lerpedFrame
  → [player] charik.Update(world)
  → [twin]   charik.TransformFrame(facing) → charik.Update(twin space)
  → SetBoneMatrix / ManipulateBoneAngles
```

## Smoke

1. VR start: own arms/fingers/head match controllers (player path).  
2. Avatar MIRROR: raise right hand → image on your right (twin left mesh).  
3. Neck not giraffe; crouch bends spine/legs on twin.  
4. Real hands not desynced (twin never NetUpdateLocalPly).
