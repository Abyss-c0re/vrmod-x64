# VRMod render quality ladder (Cube standards)

**Status:** Implemented from deep-research-8 (2026-07-30)  
**Compat law:** **No new module Lua exports.** Quality runs on existing APIs + internal C++ only. Module version stays **23**.

---

## Creed (Cube)

1. Single downward energy: raw → tracking SoT → modifiers → cyclopean view → dual eyes → Submit.  
2. Submit ASAP after WaitGetPoses (Lua: input/net after Submit).  
3. Never skip a stereo eye.  
4. No new `vrmod` table functions that older binaries lack.  
5. Truthful fail: dual RGBA8 OUT only (no raw eng Submit / 105).

---

## Backend (module — internal, same Lua surface)

| Behavior | Where |
|----------|--------|
| `glFlush` after dual Submit + PostPresentHandoff | `SubmitFrames` |
| Quality tick after `WaitGetPoses` | `UpdatePosesAndActions` → `TickRenderQualityLadder` |
| `ShouldApplicationReduceRenderingWork` + frame drops | internal → `ForceInterleavedReprojectionOn` |
| Pose prediction seconds | `GetPoseActionDataRelativeToNow(..., predSec)` in existing `GetPoses` |
| HMD position micro-smooth | internal `SmoothHmdPoseIfEnabled` on HMD only in `GetPoses` |
| Linear filter on submit OUT | existing `AllocRGBA8` |

**Not exported:** no `ShouldReduceRenderingWork` / `GetFrameTiming` / version bump.

---

## Creator Lua (optional, works with any v23 module)

| Behavior | Convar / path |
|----------|----------------|
| Frame order: track → modifiers → view → eyes → Submit → input/net | `BindRenderSceneHook` |
| Skip desktop mirror when `FrameTime() > 14ms` | `vrmod_render_adaptive` |
| Optional extra HMD smooth (default off; backend already smooths) | `vrmod_hmd_smooth` |
| `mat_queue_mode = 1` pinned in VR | `PERFORMANCE_CONVARS` / `NEVER_RESTORE` |
| Live UV crop from projection | `ComputeSubmitBounds` / soft refresh |

---

## Explicit non-goals

- New module Lua functions  
- Module version > 23 for this work  
- MSAA / HAM / depth submit  
- Skipping one stereo eye  
