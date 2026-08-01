# Workshop monitor — 3442302711

**Fire:** 2026-08-01 ~19:01 local (EEST)  
**Law:** commit every fix · workshop only after smoke · mat_queue=1 · cube_is_source_of_truth · no dual-truth pose · primary-hand SoT

## Sources
- Comments: **1256** (unchanged) — top still Kriminull forced walk / no sprint; author Cube prophecy; Батон praise; Benzo praise; jddudeman menu crash
- Bugs ctp=24: still **349** — #346 fly · #347 black HMD · #348 flicker · #349 HUD ghost
- Questions: **104** — first page only (old help); no new last-page signal
- GitHub open: #27 edges · #31 Pimax left black · #29 eye angles · #21 Proton body · #19 2D tutorial

## Hot / actionable

| Report | Source | Verdict |
|--------|--------|---------|
| **Forced walk / cannot sprint** | **Kriminull** (~2h at last fire) | **Fixed in tree** (`938b093`) — speed SoT + auto-sprint + clear stuck +walk + Knuckles/Cosmos stick-click → sprint — **needs smoke** |
| Menu open crash (~2s) | jddudeman | **Already fixed** RT + QM harden — needs smoke then workshop |
| Hands stuck / PM glitch | Galaxynex; Cookie | **Already fixed** hands + stock FG — needs smoke |
| HUD ghost / black menus / hitmarkers | #349 | **Already fixed** single-plate + RT clear — smoke |
| Focus flicker / skybox | #348 | **Already fixed** mat_queue=1 — smoke |
| Glide no input | Sobik349+ | **Partial** stick-primary — bindings hold |
| Left-handed / QM attach | cavik | **Done** primary hand + QM L/R/float + 3× reset |
| Black HMD / fly-away | #347 #346 | Module/driver/calib — not pure Lua |
| OpenXR / worldmodels / soft collision | older | Hold / backlog |

## Actions this fire
- Re-fetched comments (1256) + bugs last page (349) + QUESTIONS (104) + GH open issues.
- **No new Workshop/GH signals** vs prior fire (~18:30).
- **No code change** — Kriminull sprint already on `main` (`938b093`); remaining hot items smoke-gated or non-Lua.
- **No gmpublish** (smoke not verified this session).

## Pending smoke (before workshop)
1. Enter VR → full stick = sprint (no button) · stick-click still sprints  
2. Sprint not blocked by shallow height-duck; button crouch still blocks (#10)  
3. Spawn / settings / QM **>5s** — no crash  
4. HUD single plate + no ghost  
5. Hands L/R + stock foregrip  
6. mat_queue=1 focus  
7. QM 3× reset + attach modes  
8. Glide stick drive  

## Watch loop
Recurring scheduler re-scans comments + bugs ctp=24 + GH; autofix actionable Lua only; push; workshop only post-smoke.

## Next loop
Only new actionable Lua after smoke; ship bar remains smoke of fixed stack + sprint fix (`938b093`).
