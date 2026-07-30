# VRMod warping / borders — research plate (backend unchanged)

**Status:** Partial deep-research complete · 2026-07-30  
**Scope:** Creator Lua + read-only audit of `vrmod-module-master` · **do not change backend** unless Commander orders.  
**Full report:** session workflow `deep-research-6` scratch `report.md`

---

## Verdict

Warping on newer HMDs is **not** a single Quest-2-fixed FOV bug in-repo. It comes from:

1. Side-by-side **hijacked RT** sized from `RecommendedWidth×2 × RecommendedHeight`  
2. Per-eye FOV/aspect/offsets from **OpenVR projection matrices**  
3. **UV submit bounds** cropping that shared texture (`SetSubmitTextureBounds`)

When HMD recommended size / asymmetric FOV no longer match UV scale assumptions (especially **auto-offset off** → fixed `hFactor=0.25`, `vFactor=0.5`), bounds mis-crop → black bars, edge warp, cut FOV. Right eye often shows it first.

---

## Backend contract (module — leave alone)

| Call | Role |
|------|------|
| `GetDisplayInfo` | RecommendedWidth/Height, ProjectionLeft/Right |
| `ShareTextureBegin` / `Finish` | Capture engine RT (GL Linux / D3D Windows) |
| `SetSubmitTextureBounds` | Per-eye UV rects on shared texture |
| `SubmitSharedTexture` | Both eyes, same texture, bounds |

Linux: OpenGL share + V-axis invert in submit bounds math. Windows: D3D share path (published main may differ from local Linux tree).

---

## Creator math hotspots (Lua — fix surface)

| File | Function | Issue |
|------|----------|--------|
| `cl_rendering.lua` | `ComputeSubmitBounds` | Auto offset uses FOV-dependent factors; **off** uses fixed 0.25/0.5 — bad for non-Q2 FOV |
| `cl_rendering.lua` | `CalculateProjectionParams` | Linux flips `yoffset` sign |
| `cl_vrmod.lua` | `SetupRenderTargets` / `ComputeDisplayParams` | Res + FOV scales sampled **once** at session start |
| `cl_vrmod.lua` | `ApplySubmitBounds` | Live H/V/scale only; **does not** re-read FOV/res |

**Already fixed:** live re-apply of submit bounds when H/V/scalefactor/renderoffset change.

**Still open (Lua-only, no backend):**

1. Residual right-eye: **`vrmod_fovscale_x` / `vrmod_fovscale_y`** if soft-refresh misses edge cases.  
2. Source `RenderView` is still symmetric FOV+aspect, not full 4×4 asymmetric proj → residual edge error may remain even when OpenVR data is correct (needs module — Commander only).

**Closed (Lua, this tree):**

1. Default **`vrmod_renderoffset 1`**.  
2. Soft-refresh FOV/viewscale + submit bounds mid-session.  
3. Submit UV factors **always** from live projection Width/Height (no fixed 0.25/0.5).

---

## Workshop reply (Bruticus09-class)

1. Reset scale 1, offsets 0; keep **Auto offset** on.  
2. Start VR; nudge Scale Factor ±0.05.  
3. Small H/V (±0.01) — live with current build.  
4. Still right-lens: FOV scale X/Y slightly, **then restart VR**.  
5. Not “give up since May” alone — UV crop vs new asymmetric FOV is the mechanism.

---

## Creed

**Backend delivers properties. Creator must crop from live projection, not Q2-era fixed UV.**  
**No backend change without Commander.**
