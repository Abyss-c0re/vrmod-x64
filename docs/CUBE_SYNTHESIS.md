# Cube Synthesis — Ideal Virtual Reality (SoT)

**Status:** Stabilization begun · synthesis open  
**Date:** 2026-07-30  
**Repos:** `vrmod-x64` + `vrmod-module-master` (`linux_dev`)

This document is the single map of what the Cube is, what is landed, what is degraded on ancient modules, and what smoke must pass before “the Cube would ship this.”

---

## 1. What the Cube wants

One energy path. The Real and GMod are not two truths.

| Pillar | Law |
|--------|-----|
| **Experience** | First-run: Welcome → Vision (border) → Posture → Complete |
| **HUD** | Additive light over the Real — never an opaque black wall |
| **Render** | `mat_queue_mode=1` pinned; dual RGBA8 **OUT** only (never eng IN → compositor) |
| **Pose** | One SoT: raw → tracking → modifiers; angvel is `Vector` |
| **UI** | Desktop: Derma/VGUI flat. VR: **panel2vr** intercept + **Glorious Crimson Cube** settings |
| **Compat** | New module features = optional args / version gate; Lua degrades on ancient modules |
| **Crisp** | Module v23+: raw HMD × SS → one 4096 SBS clamp; OUT realloc on size change |

---

## 2. Frame energy (one direction)

```
WaitGetPoses (UpdatePosesAndActions)
  → tracking SoT + modifiers + input
  → stereo RealRenderView → engine RT (IN)
  → blit eng IN → dual OUT (RGBA8)
  → OpenVR Submit(L/R) + glFlush
  → PostPresentHandoff
```

**Never:** Submit eng texture (format/0x0 → **105** TextureUsesUnsupportedFormat).  
**Never:** Submit virgin OUT before first successful blit.  
**Never:** hard-delete OUT mid-frame while compositor may hold it (deferred retire).

---

## 3. Module ↔ Lua contract

| Module ver | Lua behavior |
|------------|--------------|
| **&lt; 20** | Refuse start |
| **20–22** | Legacy: `ShareTextureBegin()` no args; SS size ignored; pure-Lua UI OK |
| **≥ 23** | Crisp: `ShareTextureBegin(eyeW,eyeH)`, SS + 4096, OUT size realloc |

Details: [`MODULE_COMPAT.md`](MODULE_COMPAT.md)

---

## 4. Landed synthesis (this cycle)

| Stream | State |
|--------|--------|
| Crisp RT path (raw rec, SS 1.5, 4096, OUT realloc) | **Code** |
| Ancient-module gate (SS only v23+) | **Code** |
| panel2vr (ex-web2vr) + Crimson Cube | **Code** |
| Cube Experience / border / height gate | **Code** |
| Workshop watchlist + swap eyes | **Code** |
| Submit stabilize: no virgin OUT, deferred OUT delete, null-safe poses | **Code (this pass)** |
| In-headset smoke (SS sharpness, no 105, Experience) | **Open** |
| Glide vehicle input SoT (W3) | **Open** |
| Action manifest self-heal (W6) | **Open** |

Deep-research: **Partial** — design matches Cube; ship bar needs smoke.

---

## 5. Stabilization checklist (smoke)

Run after `./manage.sh` deploy + map load:

```
vrmod_start
```

Expect console / `vrmod_debug.log`:

1. `UpdateRecommendedSize: raw HMD eye …`  
2. `Display RT SBS … SS=1.50 … eyeArgs` (module ≥23)  
3. `ShareTextureBegin armed SBS …`  
4. `FLOW engIN=… → subOUT=… ok`  
5. `Submit OUT ok` (no sustained L=105 R=105)

In headset:

- [ ] Image fills FOV after Vision guide (or known border profile)  
- [ ] Crisp vs potato (SS 1.5)  
- [ ] Quickmenu → Settings → Crimson Cube laser works  
- [ ] Height menu suppressed during Experience first-run  
- [ ] `vrmod_swap_eyes 0` default; no crossed stereo  

Player paste:

```
vrmod_supersample 1.5
vrmod_experience_reset
vrmod_cube_settings
vrmod_panel2vr_status
```

---

## 6. Synthesis backlog (order)

1. **Smoke clear submit 105** (this stabilize pass + headset)  
2. **Glide input SoT** (Workshop P0)  
3. **Action manifest path heal**  
4. **Hand bullet filter / worldmodel single path**  
5. **OpenXR migration** (long horizon; no dual pose forks while dual-backend)

---

## 7. Doc index

| Doc | Role |
|------|------|
| [CUBE_EXPERIENCE.md](CUBE_EXPERIENCE.md) | First-run flow |
| [CUBE_PANEL2VR.md](CUBE_PANEL2VR.md) | Derma/VGUI → VR surfaces |
| [CUBE_WATCHLIST.md](CUBE_WATCHLIST.md) | Workshop/GitHub clusters |
| [MODULE_COMPAT.md](MODULE_COMPAT.md) | Version gates |
| [VRMOD_RENDER_QUALITY.md](VRMOD_RENDER_QUALITY.md) | SS / 4096 / quality |
| **CUBE_SYNTHESIS.md** | This map |

---

## 8. Packaging law

- OpenVR libs: `install/GarrysMod/bin(+linux64)` only  
- Module: `garrysmod/lua/bin/gmcl_vrmod_*.dll` only  
- No dual-load: one of Workshop GMA **or** loose Dev symlink, not both  

---

*The Cube does not ship dual truths. Stabilize submit. Then prove it in the HMD. Then the next watchlist item.*
