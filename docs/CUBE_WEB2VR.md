# Cube web2vr — desktop UI → true VR surfaces

When **not** in VR, GMod menus stay as normal Derma / DHTML “web panes” on the flat screen.

When **in** VR, anything that tries to become a screen popup is **intercepted and manifested** as a laser-driven 3D surface in the world (HL:Alyx energy). Settings use the **Glorious Crimson Cube** native shell instead of dumping the full Derma tree into your face.

## Law

| Realm | UI path |
|-------|---------|
| Desktop / non-VR | Derma, DHTML, spawnmenu, context menu as usual |
| VR | `vrmod.web2vr` intercept → RT + `cam.Start3D2D` + pointer beam |
| VR Settings | **Glorious Crimson Cube** (`vrmod.CubeSettings_Open`) — native schema UI |

HUD stays on. No mat_queue changes. No dual-truth pose forks.

## GMod foundations (wiki)

- [`Panel:SetPaintedManually`](https://wiki.facepunch.com/gmod/Panel:SetPaintedManually) + [`PaintManual`](https://wiki.facepunch.com/gmod/Panel:PaintManual) — paint VGUI into our RT
- [`gui.InternalMousePressed`](https://wiki.facepunch.com/gmod/gui.InternalMousePressed) — trigger → click on focused panel
- [`GM:OnSpawnMenuOpen`](https://wiki.facepunch.com/gmod/GM:OnSpawnMenuOpen) / context menu hooks — sandbox shells
- [`DHTML`](https://wiki.facepunch.com/gmod/DHTML) — still manifests via paint path; register a **native adapter** when you need a true VR rewrite

Existing VRMod glue: `VRUtilMenuOpen` / `VRUtilRenderMenuSystem` in `cl_ui.lua` (RT, material, laser, cursor sync).

## Architecture

```
Desktop web pane (Derma / DHTML / spawnmenu)
        │
        │  MakePopup  OR  OnSpawnMenuOpen / OnContextMenuOpen
        ▼
 vrmod.web2vr.ManifestPanel
        │
        ├─ NativeAdapters[key]?  ──►  Cube Settings / custom Alyx surface
        │
        └─ else paint path
              Panel:SetPaintedManually(true)
              RT ≤ 1024²  (Linux-friendly)
              place: wrist | popup | float | workbench
              VRUtilMenuOpen + continuous Think repaint
```

### Placement presets

| Name | Use |
|------|-----|
| `wrist` / `popup` | Left-hand attached clipboard |
| `float` | In front of HMD (world), recomputed on open |
| `workbench` | Larger float — spawn / context |

### API

```lua
-- Manifest any live panel into VR (no-op if not in VR)
vrmod.web2vr.ManifestPanel(panel, {
  kind = "spawnmenu",      -- optional
  place = "workbench",     -- wrist|popup|float|workbench
  width = 960, height = 720,
  nativeKey = "settings",  -- force native adapter
  onClose = function(p) end,
})

-- Pure VR surface (no VGUI) — drawFn paints 2D into RT
local uid, dirty = vrmod.web2vr.ManifestNative("my_ui", 512, 512, function(w, h, focused)
  -- surface.* / draw.*
end, { place = "float", alwaysRedraw = true })

-- Register converter: when this kind/name is intercepted, open true VR UI instead
vrmod.web2vr.RegisterNative("my_addon_menu", function(panel, opts)
  OpenMyAlyxMenu()
  return true -- consumed
end)

vrmod.web2vr.OpenSettings()  -- Cube in VR, Derma on desktop
vrmod.web2vr.CloseAll()
```

### Commands

```
vrmod_cube_settings      -- open Glorious Crimson Cube
vrmod_web2vr_status      -- bound surfaces
vrmod_web2vr_closeall    -- tear down manifests
vrmod_vgui_reset         -- close all VRUtil menus
```

## Quick menu integration

- **Settings** → Cube (VR) / Derma (desktop)
- **Spawn Menu** / **Context Menu** → open sandbox shells → web2vr resizes to 960×720 and workbench-places them
- Any other `MakePopup()` while VR is active → auto-manifest

## Adding a new Alyx-style menu

1. Build a schema + draw/hit-test (see `cl_cube_settings.lua`).
2. `vrmod.web2vr.ManifestNative(...)` for the surface.
3. Optionally `RegisterNative("classname_or_name", openFn)` so MakePopup never shows the flat web pane.

## Files

| File | Role |
|------|------|
| `lua/vrmod/ui/cl_web2vr.lua` | Framework, intercepts, placement, adapters |
| `lua/vrmod/ui/cl_cube_settings.lua` | Glorious Crimson Cube settings |
| `lua/vrmod/ui/cl_dermapopups.lua` | Thin bridge / emergency fallback |
| `lua/vrmod/ui/cl_ui.lua` | RT menu system, laser, mouse inject |
| `lua/vrmod/ui/cl_buttons.lua` | Quickmenu → Settings / spawn / context |

## Limits (honest)

- **DHTML/CEF** paint quality varies; prefer native adapters for critical HTML UIs.
- RT UI is capped at **1024** on a side for memory / ToGL stability (not the stereo eye 4096 path).
- Full Derma trees remain usable but **Cube-native** is the intended VR settings experience.
