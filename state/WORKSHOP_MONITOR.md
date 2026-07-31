# Workshop monitor — 3442302711

**Fire:** 2026-08-01 ~02:11 local (EEST)  
**Law:** commit every fix · workshop only after smoke · mat_queue=1 · cube_is_source_of_truth · no dual-truth pose

## Sources
- Comments: **1250** — no new (jddudeman car how-to ~4h; Galaxynex screenshot still pending; Cookie black rect / hands)
- Bugs ctp=24: still **349** — #349 Buggie HUD ghost (~8h); #348 WhangaTy flicker (~17h)

## Hot / actionable

| Report | Source | Verdict |
|--------|--------|---------|
| HUD ghost / black menus / hitmarkers pile / spawn cut-off | Bugs #349 | **Already fixed** `41fffb5` + single-plate `784e757` + theme/HUD ship `2b5f92a`/`810282f` — needs smoke then workshop |
| Hands stuck / PM glitch | Galaxynex; Cookie | **Already fixed** `8514387` — needs smoke then workshop |
| Focus flicker / skybox | #348 | **Already fixed** mat_queue=1 `2bfbfc6` — needs smoke then workshop |
| DrawModel nil | prior | **Already fixed** `a26a750` |
| Theme / cube UI / avatar / FBT / menus | author local WIP | Head `d147a88`; **dirty** large tree + new `cl_autoshot.lua`, `cl_cube_derma_skin.lua`, `cl_quick_menu_layout.lua` — **not workshop** |
| Glide / fly / black VR / OpenXR | older | Hold / module / ignore |
| Sit in car / controls | jddudeman | Ignore — how-to |

## Actions this fire
- Re-fetched comments + bugs last page (ctp=24).
- **No new Lua fix from workshop** — no new posts/repro.
- Local: **main == origin** at `d147a88`; dirty WIP growing (UI/api/character/FBT) — left uncommitted by monitor.
- **No gmpublish.**

## Pending smoke (before workshop)
1. HUD single plate + no ghost/hitmarker pile (`784e757` + prior RT clear)  
2. Weapon wheel / hand menus alpha OK  
3. Hands L/R independent (`8514387`)  
4. mat_queue=1 under focus (`2bfbfc6`)  
5. Optional: quick-menu calibration; aim crosshair `b79abf2`

## Next loop
Galaxynex screenshot if posted; only code new actionable Lua.
