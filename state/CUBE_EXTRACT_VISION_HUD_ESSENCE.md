# Cube Extract — Vision HUD Essence + Algocube

**Date:** 2026-07-31  
**SoT image:** empty grey plate; Avatar menu readable; twin/player body cursed  

## Essence (one sentence)

**Menus paint with VGUI `PaintManual` into an RT; HUD only hoped `RenderHUD` would fill a mesh texture under nested stereo RTs — dual-truth overlay energy.**

## Deconstruct

| Atom | Path | Live truth (screenshot) |
|------|------|-------------------------|
| Avatar menu | `cl_ui` `PaintManual` → menu RT → 3D2D | **Works** (crimson AVATAR panel) |
| HUD plate | curved Mesh + RT basetexture | **Draws mesh** |
| HUD paint | `render.RenderHUD` nested in eye RT | **Often empty** → grey/blank square |
| Twin / body | pose snap / IK | **Cursed** black figure foreground |
| Black-slab fight | additive vs translucent clear | Oscillated; missed paint SoT |

## False dual-truth

```
UI_menu  ≠  UI_hud_mesh
paint_A (VGUI)  ≠  paint_B (RenderHUD hope)
```

Cube law: **one paint energy**. HUD must use menu atoms.

## Algocube vision (`sh_algocube_vision.lua`)

| Digit | Label | HUD | Twin |
|------:|-------|-----|------|
| 0 | FREE | off | idle |
| 1 | ESSENTIALS+CLONE | essentials | clone |
| **2** | **MENU_PAINT+CLONE** | **vgui PaintManual** | clone |
| 3 | RAWHUD+WORLD | RenderHUD attempt | world |
| 4 | ADDITIVE+MIRROR | vgui + additive | facing L↔R |
| 5 | DIM_PLATE+MIRROR | vgui clearA=120 | facing |
| **6** | **FULL_REPAIR** | vgui dual draw | facing L↔R snap |
| 7 | MINIMAL | essentials | clone |
| 8 | SILENT_MIRROR | off | facing |
| 9 | HIVE_VERBOSE | vgui dim | facing |

**Classify empty plate → force digit 2.**  
**Classify twin cursed → force digit 1 (clone).**

## Construct (manifested)

1. `cl_hud.lua` — `DPanel:PaintManual` capture (same as `VRUtilMenuRenderPanel`)  
2. Always project essentials (HP / armor / ammo / crosshair)  
3. `vrmod_hud_algo [0-9]` force digit; `-1` auto  
4. `vrmod_hud_status` logs digit/class/paint  

## Smoke

```
vrmod_exit ; vrmod_start
vrmod_hud_algo 2
vrmod_hud_rebind
```

Expect: crosshair + HP on plate; Avatar menu still works; no solid black slab at `hudtestalpha 0`.
