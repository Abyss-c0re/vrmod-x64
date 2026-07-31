# Crimson Cube UI Framework

**Experience of a lifetime** — one chrome SoT for HUD, Quick Menu, Weapon wheel, Settings, Avatar.

## Law

| Pillar | Rule |
|--------|------|
| **One energy** | `vrmod.cube` theme + framework — not ad-hoc black boxes |
| **Cubalc digit** | Presets map to identity paths (classic / void / hive / commander) |
| **Real first** | HUD never black-walls the world (`hudtestalpha 0`) |
| **VR aim** | No plate-center crosshair — hands / laser / muzzle |
| **Desktop** | Derma/VGUI · **VR** | panel2vr + laser menus |
| **mat_queue** | Untouched (`1`) |

## Files

| File | Role |
|------|------|
| `cl_cube_theme.lua` | Fonts + DrawButton / DrawPanel |
| `cl_cube_framework.lua` | Presets, density, HUD style, DrawChrome / Slot / Footer / Vital |
| `cl_hud.lua` | World HUD vitals (Cube colors + fonts) |
| `cl_quickmenu.lua` | Crimson Quick Menu |
| `cl_weaponselect.lua` | Crimson weapon radial |
| `cl_cube_settings.lua` | Glorious Crimson Cube settings shell |
| `sh_settings_catalog.lua` | **Crimson Cube** tab (customize) |

## Customize (in headset)

Quick Menu → **Settings** → **Crimson Cube** tab:

| Control | Cvar / action |
|---------|----------------|
| Preset classic / void / hive / commander | `vrmod_cube_preset` |
| Glass opacity | `vrmod_cube_glass` |
| Density compact / comfort / large | `vrmod_cube_density` |
| HUD vitals / full / minimal | `vrmod_cube_hud_style` |
| Accent RGB | `vrmod_cube_accent` e.g. `196,30,58` |

Console:

```
vrmod_cube_preset classic
vrmod_cube_status
vrmod_hud_rebind
```

## API (for new menus)

```lua
local C = vrmod.cube
local T = C.ThemeLive()
C.DrawChrome(0, 0, W, H, "TITLE", { subtitle = T.presetLabel })
C.DrawSlot(x, y, w, h, "Label", hovered, selected, true)
C.DrawButtonMultiline(...)
C.DrawFooterLaw(0, H - 20, W, 2)
C.Font("CubeTitle") -- CubeLabel · CubeSmall · CubeHuge
```

## Smoke

1. `vrmod_start`  
2. Quick Menu — crimson header, cube buttons  
3. Weapon wheel — crimson ring, cube vitals chips  
4. HUD plate — HEALTH / AMMO (no crosshair)  
5. Settings → Crimson Cube → switch **void** / **hive** — colors update  

**All Hail Cube.**
