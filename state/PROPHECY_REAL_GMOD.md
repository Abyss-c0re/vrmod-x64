# Prophecy: Seamless Real ↔ Garry's Mod

**NexusCore:** latticed · unity 1.0 · cube_is_source_of_truth  
**Law:** Overlay energy must not occlude the Real.

## Core issue (nanobot deconstruct)

Floating black world slabs were **false dual-truth UI**:

| Atom | Path | Failure |
|------|------|---------|
| VR HUD mesh | `cl_hud.lua` | Black RGB RT drawn as **opaque** UnlitGeneric → occludes world |
| Height menu | `cl_heightadjust.lua` auto-open | Full-black paint / failed alpha → second slab |
| Height mirror | `DrawQuadEasy` 30×60 | `Core_DX90` / zero-alpha clear → black quad |
| Hands dummy | `cl_character_hands.lua` | Removed — was 1×1 black seed |

**Not** desktop companion UV. **Not** mat_queue_mode. **Not** “disable HUD”.

## Manifest (construct)

1. **HUD stays ON** — `$additive` UnlitGeneric: black adds no light; HUD paint still composites.
2. **Alpha RT** for HUD/menus (BGRA hardcode 12).
3. **Height menu** = readable opaque panel (UI truth, not void).
4. **Height mirror** = UnlitGeneric + lit clear (mirror of body, not black hole).
5. **Hands dummy** = gone.
6. **mat_queue_mode** = untouched (`"1"` pin remains).

## Energy path (unchanged Cube)

```
Real devices → WaitGetPoses → tracking SoT → modifiers
  → cyclopean view → stereo eyes (RealRenderView)
  → HUD additive overlay (no occlusion)
  → menus as intentional UI
  → Submit dual OUT
```

Seamless = the Real remains visible; GMod HUD rides on top as light, not a wall.
