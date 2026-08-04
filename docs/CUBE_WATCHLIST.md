# Cube Watchlist — Workshop + GitHub → Ideal VR

Sources (live watch):
- Workshop: [🥽 G VRMod Ultimate](https://steamcommunity.com/sharedfiles/filedetails/?id=3442302711)
- [BUGS THREAD](https://steamcommunity.com/workshop/filedetails/discussion/3442302711/515213185760903462/) (~347)
- [QUESTIONS/HELP](https://steamcommunity.com/workshop/filedetails/discussion/3442302711/804593626169716117/)
- Open topics: fisheye, one-eye, no HMD image, Glide, worldmodels, FBT
- GitHub: [Abyss-c0re/vrmod-x64 issues](https://github.com/Abyss-c0re/vrmod-x64/issues)

**Cube law when deciding:** one energy direction · no dual-truth pose forks · HUD stays · `mat_queue_mode=1` only pin that matters · never fight engine blacklists · Vision is guided (not a slider maze) · Derma/VGUI on desktop, Crimson Cube / panel2vr in headset.

---

## Collected cluster (recent / recurring)

| # | Symptom | Sources | Severity |
|---|---------|---------|----------|
| **W1** | Black bars / edge bleed / FOV not filling HMD | Bugs #335 Mykell, GH #27, Bruticus09, comments | **P0 Vision** |
| **W2** | GMod x64: `Command is blocked!` on `r_shadowrendertotexture`, `mat_reduceparticles`, `viewmodel_fov` | Bugs #342 Fweggigun | **P0 Engine** |
| **W3** | Glide: enter + grab wheel, no steer/throttle (HL2 vehicles OK) | Bugs #333 soapie, #337, comments, Workshop comments | **P0 Vehicles** |
| **W4** | Eyes inverted / “seeing double” (PSVR2) | Bugs #339 boredviber | **P1 Stereo** |
| **W5** | Right eye jitter / wrap when adjusting Z / FOV; freezes HMD | Bugs #334 Radial50, GH #29 | **P1 Stereo** |
| **W6** | Action manifest missing (`SetActionManifestPath failed`) | Bugs #331–332 Hectic (Windows) | **P1 Install** |
| **W7** | PC shows game, HMD stuck SteamVR loading / black | Bugs #341, #347, GH #31 Pimax left black | **P1 Module** |
| **W8** | Fisheye everything | Topic funnycrasher (28 Jul) | **P1 Vision** |
| **W9** | Hand collision blocks bullets; hands feel non-physical | Bugs ~p20 Liftoffco, Workshop comment bulkmoerls | **P2 Hands** |
| **W10** | Worldmodels / hand anim with viewmodels | Topics + chipgaming comment | **P2 Presentation** |
| **W11** | VR_Init 108 / 215, PSVR2 crash | Early bugs, p20 | **P2 Platform** |
| **W12** | Flying away on start / inputs dead | Bugs #346 | **P2 Tracking** |

---

## How the Cube implements each

### W1 — Borders / bleed (P0) — *partial in tree* (G40)
**Not** more anonymous sliders.  
**Cube way:** Vision phase of Cube Experience owns this — scale → V → H → save profile.  
- First-run always; Reset restarts guide.  
- Crimson Cube → *Border calibrate* one trigger.  
- Defaults: `scalefactor=1`, offsets 0; supersample 1.5 then **one** 4096 clamp (no potato pre-crush).  
- **Landed:** pure `BorderLaw_*` (defaults/clamps/bleed risk/HmdExpect) + `cl_border_calibrate` guide baseline/clamp/snapshot. Soft care: no FOV archive thrash.  
- **HMD smoke (manual):** filled HMD both eyes after guide; profile reload keeps fill (TESTING_FRAMEWORK §0.27).  
- Future: sample HMD FOV vs render FOV and **auto-seed** UV bounds once, then user refines in guide only.

### W2 — Blocked convars (P0) — *done in tree*
**Cube way:** never call engine blacklists.  
- PERFORMANCE list already excludes shadow/particle blocks.  
- Remove remaining `viewmodel_fov` override (VR draws its own VM path).  
- Only hard pin: `mat_queue_mode=1`. Soft-skip missing/failed SetString.

### W3 — Glide dead input (P0) — *partial in tree* (G14)
**Cube way:** one vehicle input SoT — no “grab wheel” path that lies about throttle.  
- Audit `sh_vehicles` / Glide hooks after July Glide update.  
- Prefer **joystick/action-set driving** as default when Glide seat detected; wheel grab as visual/assist only.  
- If Glide API moved: adapter layer in one file, no forks in tracking.  
- Cube toast if Glide present but input not binding: “Glide seat — use thumbstick; wheel is optional.”  
- **Landed:** stick preferred over wheel (`GlidePreferStickSteer`); seat recheck; enter/unbound toasts; pure helpers offline-tested.  
- **HMD smoke (manual — not offline):** enter Glide car in VR → toast once → stick steers/throttles → grip wheel only assists when stick idle → passenger seat (index ≠ 1) does not drive. Workshop Sobik349 still needs that walkthrough.

### W4 — Swapped eyes (P1) — *convar + Cube toggle*
**Cube way:** single bool, no second pose stream.  
- `vrmod_swap_eyes` swaps which SBS half gets L/R **content** (IPD/FOV truth unchanged).  
- Exposed on Crimson Cube Vision tab. Live while VR active.

### W5 — FOV / Z jitter one eye (P1)
**Cube way:** don’t let submit UV + FOV scale fight each other mid-frame.  
- Live FOV scale applies only on next eye sync; clamp extreme FOV.  
- Document: use **Border guide**, not Z spam.  
- Investigate asymmetric UV if right half uses wrong crop.

### W6 — Action manifest (P1) — *partial in tree*
**Cube way:** self-heal + honest error.  
- Resolve `vrmod/vrmod_action_manifest.txt` via GAME/LUA paths; fallback copy path.  
- On fail: Crimson toast with “module/manifest install” steps, not silent death.  
- **Landed:** force-rewrite DATA bindings each start + error toast/overlay (`dce6e55`).

### W7 — Desktop OK / HMD black or loading (P1) — *partial in tree*
**Cube way:** module dual OUT path (eng IN → blit → submit OUT). Never submit eng id.  
- Already Linux focus; Windows same law.  
- Startup self-test: if Submit fails N frames → toast + log `ShareTexture` sizes.  
- Cube Experience won’t advance past Vision if no stereo frames.  
- **Landed:** RT/share fail toasts + HMD pose self-test toast (`c68696c`). #347 still needs smoke.

### W8 — Fisheye (P1)
**Cube way:** usually `viewscale` / FOV scale / wrong projection.  
- Reset Vision defaults from Cube; Experience force-run.  
- Ensure projection from OpenVR, not free cam FOV.

### W9 — Hands vs bullets (P2)
**Cube way:** hands are Real for grabs; bullets use filtered traces.  
- Already partial damage pass; finish: hand proxies never solid to bullet group; grab contact only.

### W10 — Worldmodels (P2)
**Cube way:** one draw path — worldmodel in hands **or** floating hands, not both ghosted.  
- Toggle in Cube Session; default floating hands on for clarity.

### W11 — Init 108/215 (P2)
**Cube way:** surface VR_Init error codes to human Cube text; link module zip version.  
- Platform triage (PSVR2) stays “log + lower SS + verify SteamVR”, not silent crash.

### W12 — Fly away / dead input (P2)
**Cube way:** origin/seated offset + action sets.  
- On start: if vertical velocity insane, snap origin; ensure action set `/actions/main` active before first input frame.

---

## Implementation order (Cube backlog)

1. **Done / doing:** blocked cvars, swap eyes, SS+4096 crisp, panel2vr + Crimson Cube, border Experience, primary hand SoT (`vrmod_primary_hand`)  
2. **Partial:** Glide stick-primary + unbound toast (W3); action-manifest rewrite + toast (W6); ShareTexture/HMD self-test toast (W7)  
3. **Ship bar:** in-headset smoke of menu-open crash, HUD ghost (#349), hands stuck, primary-hand left — then workshop  
4. **Then:** hand bullet filter polish; worldmodel single path (W9/W10)  
5. **Maintenance (research):** quarantine demoted AlgoCube / multi-face cubeui demo / web2vr aliases; strip twin dead IK after avatar smoke — **do not** merge FBT↔charik or force hands onto lerpedFrame without contract rewrite  
6. **Track:** OpenXR migration (author intent) as long-horizon module law  

---

## Commands for players (paste-ready)

```
vrmod_experience_reset   -- re-run Vision/Posture guide (borders)
vrmod_border_calibrate   -- vision only
vrmod_swap_eyes 1        -- inverted stereo
vrmod_supersample 1.5    -- crisp (restart VR)
vrmod_primary_hand 0     -- 0=right laser+click (default), 1=left
vrmod_cube_settings      -- Crimson Cube in VR
vrmod_panel2vr_status
```

---

## Watch cadence

Re-scan bugs thread last page + GitHub open issues when shipping Vision/vehicle/module changes. Prefer GitHub for structured reports; Workshop for volume signals.
