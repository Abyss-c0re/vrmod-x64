# Workshop monitor — 3442302711

**Fire:** 2026-08-01 ~00:11 local (EEST)  
**Law:** commit every fix · workshop only after smoke · mat_queue=1 · cube_is_source_of_truth · no dual-truth pose

## Sources
- Comments: **1250** — no new (jddudeman car how-to; Galaxynex screenshot still pending; Cookie black rect)
- Bugs ctp=24: still **349** — #349 Buggie HUD ghost (~6h); #348 WhangaTy flicker (~15h)

## Hot / actionable

| Report | Source | Verdict |
|--------|--------|---------|
| HUD ghost / black menus / hitmarkers pile / spawn cut-off | Bugs #349 | **Already fixed** `41fffb5` + `234586f`/`96708ed` + `0d7a6bf` — needs smoke then workshop |
| Hands stuck / PM glitch | Galaxynex; Cookie | **Already fixed** `8514387` — needs smoke then workshop |
| Focus flicker / skybox | #348 | **Already fixed** mat_queue=1 `2bfbfc6` — needs smoke then workshop |
| DrawModel nil | prior | **Already fixed** `a26a750` |
| Avatar / iknet / HUD WIP | author local | Dirty HUD/UI/avatar/frames + untracked iknet/vision — **not workshop** |
| Glide / fly / black VR / OpenXR | older | Hold / module / ignore |
| Sit in car / controls | jddudeman | Ignore — how-to |

## Actions this fire
- Re-fetched comments + bugs last page (ctp=24).
- **No new Lua fix from workshop** — no new repro.
- Local tree ahead **34** (`0d7a6bf` latest); author WIP dirty/untracked continues.
- Steam addons symlink live; **no gmpublish.**

## Pending smoke (before workshop)
1. HUD paint + no ghost/hitmarker pile (`41fffb5`+`96708ed`+`0d7a6bf`)  
2. Weapon wheel / hand menus alpha OK  
3. Hands L/R independent (`8514387`)  
4. mat_queue=1 under focus (`2bfbfc6`)  
5. Optional: quick-menu calibration (author ask)

## Next loop
Galaxynex screenshot if posted; only code new actionable Lua.
