# Workshop monitor — 3442302711

**Fire:** 2026-08-01 ~06:40 local (EEST)  
**Law:** commit every fix · workshop only after smoke · mat_queue=1 · cube_is_source_of_truth · no dual-truth pose · primary-hand SoT (not dual lasers)

## Sources
- Comments: **1253** (+2: Benzo praise; author WIP reply)
- Bugs thread ctp=24: still **349** — #346 fly-away · #347 black HMD · #348 focus flicker · #349 HUD ghost
- Research: Cube maintenance (pose/IK energy) + UX watchlist W1–W12
- Local tip: `1d479be` primary hand SoT · `b197894` dual-hand revert · W3/W6/W7 toasts

## Hot user signals → status

| Report | Who | Verdict in tree | Notes |
|--------|-----|-----------------|-------|
| Menu open crash ~2s | **jddudeman** (1h) | **Fixed** `2e8e759` RT paint before stereo | **Ship bar:** needs smoke >5s spawn/settings/QM |
| Hands stuck / PM glitch | **Galaxynex**; Cookie | **Fixed** hands + foregrip `98dc91b`+ | Screenshot pending from Galaxynex |
| Black rect + hands tied (Quest 2) | Cookie | Same hands path + HUD plate | Smoke |
| HUD ghost / black menus / hitmarkers pile / spawn cut-off | Bugs **#349** Buggie (13h) | **Fixed** single-plate HUD + RT clear + panel2vr | Smoke then workshop |
| Focus flicker / skybox when focused | **#348** WhangaTy (21h) | **Fixed** `mat_queue_mode=1` pin | Smoke |
| Glide no throttle/steer | Sobik349; Vasya; older | **W3 partial** stick-primary + seat recheck + toast `5c29986` | Controller bindings still Glide/SteamVR side |
| Borders / FOV right lens | Bruticus09; Mykell | **W1** Vision guide — residual research | Not pure Lua quick fix |
| Left-handed mode missing | **cavik** | **Done** `vrmod_primary_hand` + Cube HUD/UI combo `1d479be` | Primary laser+click; wrist = other hand |
| Worldmodels | chipgaming | **W10** backlog single draw path | Not this fire |
| Hand collision soft | bulkmoerls | **W9** partial | Backlog |
| Aim / shoot wrong place | green_century70 | Weapon offset / laser attach | Smoke weapon laser path |
| Black HMD / PC OK | **#347** | **W7** toast + ShareTexture size log in tree | Module/driver if still black |
| Fly away + dead buttons | **#346** | **W12** origin/action-set | Module/calib |
| VR_Init 108 PSVR2 | older bugs | **W11** platform | Module |
| OpenXR / Linux WiVRn | Fonera | Long-horizon module | Hold |
| Sit in car | jddudeman | User resolved | — |

## Research incorporate (Cube energy)

### Keep intact (already law-aligned)
- Frame order: poses → modifiers → input → net → stereo → submit OUT only  
- HUD default PaintVitals one plate (`vrmod_hud_engine` 0)  
- `frameik` → `charik` shim only  
- Primary hand SoT (one laser, not dual free-for-all)

### Debt (do not thrash mid-ship)
| Pri | Item | Action |
|-----|------|--------|
| P0 | Parallel IK in gVRMod/Nexus vs x64 charik | Cross-tree only when shipping those addons |
| P1 | FBT vs charik fork | Intentional — no merge without FBT smoke |
| P1 | Floating hands `tracking` vs body `lerpedFrame` | Keep foregrip dual-stamp contract |
| P2 | AlgoCube demoted, multi-face cubeui demo, web2vr aliases | Quarantine when call-sites gone |
| P2 | Twin dead IK init vs snap-paste | Strip after avatar smoke |

### Watchlist map (this fire)
| ID | Theme | Tree status |
|----|-------|-------------|
| W1 | FOV / borders | Open research; Experience guide is UX |
| W2 | Blocked cvars | Done |
| W3 | Glide input | **Partial** stick SoT + toast |
| W6 | Action manifest | **Partial** rewrite + toast |
| W7 | HMD black | **Partial** RT/share toast + self-test |
| W9–W12 | hands/worldmodel/init/fly | Backlog / module |

## Actions this fire
1. Re-fetched comments (1253) + bugs last page (still 349).  
2. Mapped **cavik left-hand** → primary-hand setting (already landed).  
3. Mapped **jddudeman menu crash** + **#349 HUD ghost** → fixed in tree, **not on Workshop yet**.  
4. Incorporated maintenance research into backlog (no high-risk IK merge this fire).  
5. **No gmpublish** until smoke.

## Pending smoke (before workshop)
1. Open spawn / settings / QM **>5s** — no crash (jddudeman)  
2. HUD single plate + no ghost / no hitmarker pile (#349)  
3. Hands L/R separate + foregrip (Galaxynex/Cookie)  
4. `mat_queue_mode=1` — no focus skybox flicker (#348)  
5. **Primary hand** left + right: laser + QM wrist on opposite hand (cavik)  
6. Glide: stick drive toast + throttle without wheel grab (Sobik)  
7. Optional: black-HMD path shows toast if ShareTexture fails (W7)

## Local commits ready (ahead of origin)
- `1d479be` Primary hand SoT  
- `b197894` Dual-hand ambidextrous revert  
- W3/W6/W7 toasts + Glide stick  
- Menu crash / HUD / hands / lights stacks from prior days  

## Next loop
- Only new **actionable Lua** after smoke.  
- If jddudeman still crashes post-publish → re-open menu RT stack.  
- Maintenance: dead UI quarantine only after ship bar clears.
