# Cube Experience — Ideal Virtual Reality

First-run guided flow. Energy moves one way. The Real and GMod align.

## Flow

```
VR Start (first time)
  → Welcome (Trigger begin / Grip skip forever)
  → Phase I · Vision   (border cal: scale → V → H → save profile)
  → Phase II · Posture
        Standing → Auto Height (scale to IRL eye height)
        Seated   → Auto Offset (chair → character ~66.8)
  → Complete (mark done · play)
```

## Persistence

| Key | Role |
|-----|------|
| `data/vrmod/experience_complete.txt` | First-run gate |
| `vrmod_experience` | Master enable (default 1) |
| `vrmod_experience_done` | Archive flag |
| `vrmod_experience_force` | Force again next start |

## Commands

```
vrmod_experience_start   -- run now (in VR)
vrmod_experience_reset   -- clear gate; next start guides again
vrmod_border_calibrate   -- vision only
```

## Integration

- Suppresses raw height-menu auto-open while experience should run
- Suppresses border-profile preload so guided vision owns the baseline
- On vision complete: `VRMod_BorderCalEnded(true)` advances posture
- API: `vrmod.AutoScaleHeight()`, `vrmod.AutoSeatedOffset()`

## Law

- HUD stays on  
- `mat_queue_mode` untouched  
- No dual-truth pose forks  
- Overlay never becomes a black wall of the Real  

## Synthesis

Master map: [`CUBE_SYNTHESIS.md`](CUBE_SYNTHESIS.md).

## Settings & menus in VR

After first-run, everyday UI uses **panel2vr** (see [`CUBE_PANEL2VR.md`](CUBE_PANEL2VR.md)):

- **Desktop / non-VR** — flat Derma/VGUI (`VRUtilOpenMenu`)
- **VR Settings** — **Glorious Crimson Cube** (`vrmod_cube_settings` / Quickmenu → Settings)
- **Spawn / Context / any MakePopup** — intercepted live into 3D laser surfaces
