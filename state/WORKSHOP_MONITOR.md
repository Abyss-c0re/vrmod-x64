# Workshop monitor — 3442302711

**Fire:** 2026-08-02 ~02:01 local (EEST)  
**Law:** commit every fix · workshop only after smoke · mat_queue=1 · cube_is_source_of_truth · no dual-truth pose · primary-hand SoT

## Sources
- Comments: **1261** (+2 vs 1259) — **please, Doctor!** module version / stale link; prior: Doom Slayer · Батон · Kriminull
- Bugs ctp=24: still **349** — #346 fly · #347 black HMD · #348 flicker · #349 HUD ghost
- Questions: **104** — not re-paged
- GitHub open: #27 edges · #31 Pimax left black · #29 eye angles · #21 Proton body · #19 2D tutorial

## Hot / actionable

| Report | Source | Verdict |
|--------|--------|---------|
| **Module “need newer” / old link** | please, Doctor! (~15m) | **Partial fix in tree** — in-game error now points GitHub releases (not Workshop). User self-note: Workshop desc left old module link → **human: update Workshop description link** to `vrmod-module-master/releases` (or `linux_dev_0.2` for Linux). Not a runtime Lua bug. |
| Author: no Discord; use GitHub | Doom Slayer | **Ignore** — author policy reply, not a bug |
| **Bindings tab gone** | Батон | **Fixed in tree** (`35c1b17`) — **needs smoke** |
| New menu inconvenient / Discord? | Батон | **Help/ignore** — UX opinion; author answered |
| Forced walk / cannot sprint | Kriminull | **Fixed in tree** (`938b093`) — **needs smoke** |
| Menu open crash (~2s) | jddudeman | **Already fixed** RT + QM harden — smoke |
| Hands stuck / PM glitch | Galaxynex; Cookie | **Already fixed** hands + stock FG — smoke |
| HUD ghost / black menus | #349 | **Already fixed** — smoke |
| Focus flicker / skybox | #348 | **Already fixed** mat_queue=1 — smoke |
| Glide no input | Sobik349+ | **Partial** stick-primary — hold |
| Black HMD / fly-away | #347 #346 | Module/driver/calib — not pure Lua |

## Actions this fire
- Re-fetched comments (**1261**, +2) + bugs last page (349) + GH open issues.
- **Lua:** `cl_api.lua` module missing/outdated errors → canonical GitHub releases URL (Workshop is not the module host).
- **No gmpublish** (smoke not verified). Workshop **description link** still needs human edit on Steam.

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
Human: fix Workshop page module download link. Ship bar still smoke of fixed stack + sprint + Bindings.
