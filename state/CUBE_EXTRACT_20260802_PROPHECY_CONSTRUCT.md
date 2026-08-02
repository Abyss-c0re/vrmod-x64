# Cube Extract — Prophecy Construct (research-3 / research-4 heresy purge)

**Date:** 2026-08-02  
**Law:** Manifesting the Prophecy is delivering the Cube vision. NexusCore has zero tolerance for heresy (conf that lies, spawn that fights VRMod, clobber of Vision cal).

## Research-2 (RT) — already shipped `e4bf483`
Dirty/heartbeat paint · row FillRect · laser reticle · monoscopic panel blit

## Research-3 — constructed this commit

| Heresy | Construct |
|--------|-----------|
| `grab_thresh` hard-capped to 0.40 while conf says 0.55 | Honor conf; clamp only to [0.2, 1] |
| `view_lock` forced off unless env | Conf honored; env only when set |
| GLX binding visualid=0 / null FBConfig | Real visualid + FBConfig like module |
| Handoff race: destroy without STOPPING | Orderly `xrRequestExitSession` + wait ≤3s; soft at 90s |
| Lua take_xr wait 1.25s too short | 2.5s for orderly release |
| Native Start skips monorepo rsync | rsync `addon/vrmod-x64` before spawn |
| `mat_queue_mode 2` vs VRMod safe 1 | Write **1** when multicore |
| Linked FOV clobber Vision archive | Omit fovscale unless user touched SETTINGS |
| desktopview 3 vs shell 1 | Default **1** (none) for seamless Cube |

## Research-4 (Experience) — partial construct

| Item | Status |
|------|--------|
| Skip forever leaves heightmenu open | **Fixed:** skip sets `vrmod_heightmenu 0` |
| Vision FOV fill / stereo smoke | In-headset; not claimed shipped |
| HUD single chrome / crimson polish | In-game; requires headset smoke |
| Glide / action-manifest / black-HMD | Backlog W3/W6/W7 — not closed here |

## Honesty
Smoke of full Ideal VR in-headset is still required for ship of Vision/chrome. This extract purges **code heresy** on the native launcher + Experience skip path — not a claim that workshop Ideal VR is fully proven.

## Entry
`scripts/cube_webui_launcher.sh` → `install/native/cube_webui_launcher`  
Desktop **gVRMod Cube**
