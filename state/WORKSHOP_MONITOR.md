# Workshop monitor — 3442302711

**Fire:** 2026-08-02 ~01:31 local (EEST)  
**Law:** commit every fix · workshop only after smoke · mat_queue=1 · cube_is_source_of_truth · no dual-truth pose · primary-hand SoT

## Sources
- Comments: **1259** (unchanged) — top still Doom Slayer author reply · Батон Bindings/menu · Kriminull sprint
- Bugs ctp=24: still **349** — #346 fly · #347 black HMD · #348 flicker · #349 HUD ghost
- Questions: **104** — not re-paged
- GitHub open: #27 edges · #31 Pimax left black · #29 eye angles · #21 Proton body · #19 2D tutorial

## Hot / actionable

| Report | Source | Verdict |
|--------|--------|---------|
| Author: no Discord; use GitHub | Doom Slayer | **Ignore** — author policy reply, not a bug |
| **Bindings tab gone** | Батон | **Fixed in tree** (`35c1b17`) — Settings catalog Bindings tab — **needs smoke** |
| New menu inconvenient / Discord? | Батон | **Help/ignore** — UX opinion; author answered |
| Forced walk / cannot sprint | Kriminull | **Fixed in tree** (`938b093`) — **needs smoke** |
| Menu open crash (~2s) | jddudeman | **Already fixed** RT + QM harden — smoke |
| Hands stuck / PM glitch | Galaxynex; Cookie | **Already fixed** hands + stock FG — smoke |
| HUD ghost / black menus | #349 | **Already fixed** — smoke |
| Focus flicker / skybox | #348 | **Already fixed** mat_queue=1 — smoke |
| Glide no input | Sobik349+ | **Partial** stick-primary — hold |
| Black HMD / fly-away | #347 #346 | Module/driver/calib — not pure Lua |

## Actions this fire
- Re-fetched comments (**1259**) + bugs last page (349) + GH open issues.
- **No new signals** — zero delta vs 01:01 fire; no new fixable Lua.
- **No gmpublish** (smoke not verified).

## Pending smoke (before workshop)
1. Enter VR → full stick = sprint (no button) · stick-click still sprints  
2. Sprint not blocked by shallow height-duck; button crouch still blocks (#10)  
3. Spawn / settings / QM **>5s** — no crash  
4. Settings shows **Bindings** tab · action editor opens  
5. HUD single plate + no ghost  
6. Hands L/R + stock foregrip  
7. mat_queue=1 focus  
8. QM 3× reset + attach modes  
9. Glide stick drive  

## Watch loop
Recurring scheduler re-scans comments + bugs ctp=24 + GH; autofix actionable Lua only; push; workshop only post-smoke.

## Next loop
Only new actionable Lua after smoke; ship bar = smoke of fixed stack + sprint + Bindings tab.
