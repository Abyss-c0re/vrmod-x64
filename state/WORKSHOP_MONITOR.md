# Workshop monitor — 3442302711

**Fire:** 2026-07-31 ~16:41 local (+03)  
**Law:** commit every fix · workshop only after smoke · mat_queue=1 · cube_is_source_of_truth · no dual-truth pose

## Sources
- Comments: **1250** (+1) — Benzo ~15m: “Flashing graphics… scaling nice”
- Bugs ctp=24: still 348; last user #348 WhangaTy (focus flicker)

## Hot / actionable

| Report | Source | Verdict |
|--------|--------|---------|
| Flashing / flicker graphics | **NEW** Benzo 15m; #348 WhangaTy | **Already fixed** mat_queue=1 pin `2bfbfc6` — needs smoke then workshop |
| Hands stuck / PM glitch | Galaxynex (+ screenshot pending); Cookie black rect | **Already fixed** `8514387` — needs smoke then workshop |
| DrawModel nil crash | prior | **Already fixed** `a26a750` — needs smoke |
| Avatar menu / twin | author WIP | Local ahead 21 + dirty `cl_avatar_editor.lua` — **not workshop** |
| Hand collision / Glide / fly / black VR | older | Hold / module / ignore |

## Actions this fire
- Re-fetched comments + bugs last page.
- **No new Lua fix** — Benzo flashing = known mat_queue path already in git.
- Desktop rsync refreshed; Steam addons symlink live.
- **No gmpublish.**

## Pending smoke (before workshop)
1. Hands L/R independent  
2. mat_queue_mode=1 under focus (no flash/skybox)  
3. Avatar twin stable (WIP)  
4. Optional: quick-menu calibration

## Next loop
Galaxynex screenshot if posted; only code new Lua beyond known fixes.
