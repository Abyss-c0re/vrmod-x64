# Workshop monitor — 3442302711

**Fire:** 2026-08-01 ~22:01 local (EEST)  
**Law:** commit every fix · workshop only after smoke · mat_queue=1 · cube_is_source_of_truth · no dual-truth pose · primary-hand SoT

## Sources
- Comments: **1258** (+2 vs 1256) — **Батон** Bindings tab missing; **Батон** new menu UX + Discord ask; Kriminull sprint still top-ish
- Bugs ctp=24: still **349** — #346 fly · #347 black HMD · #348 flicker · #349 HUD ghost
- Questions: **104** — not re-paged (bugs/comments were the delta)
- GitHub open: #27 edges · #31 Pimax left black · #29 eye angles · #21 Proton body · #19 2D tutorial

## Hot / actionable

| Report | Source | Verdict |
|--------|--------|---------|
| **Bindings tab gone** | **Батон** (~24m) | **Fixed this fire** — restore Settings catalog tab `Bindings` + action editor; Controls points there |
| New menu inconvenient / Discord? | Батон (~19m) | **Help/ignore** — UX opinion + product ask, not pure-Lua bug |
| Forced walk / cannot sprint | Kriminull | **Fixed in tree** (`938b093`) — **needs smoke** |
| Menu open crash (~2s) | jddudeman | **Already fixed** RT + QM harden — smoke |
| Hands stuck / PM glitch | Galaxynex; Cookie | **Already fixed** hands + stock FG — smoke |
| HUD ghost / black menus | #349 | **Already fixed** — smoke |
| Focus flicker / skybox | #348 | **Already fixed** mat_queue=1 — smoke |
| Glide no input | Sobik349+ | **Partial** stick-primary — hold |
| Black HMD / fly-away | #347 #346 | Module/driver/calib — not pure Lua |

## Actions this fire
- Re-fetched comments (**1258**) + bugs last page (349) + GH open issues.
- **Code fix:** Settings catalog — dedicated **Bindings** tab (`vrmod_actioneditor` + SteamVR help); Controls no longer buries the only entry.
- Commit + **push origin/main**.
- **No gmpublish** until smoke of pending stack (+ Bindings tab findable).

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
