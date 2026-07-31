# Workshop monitor — 3442302711

**Interval:** 30m (scheduled task)  
**Law:** commit every fix · workshop only after smoke · mat_queue=1

## Seed scan (2026-07-31)

### Hot comments
| Report | Status |
|--------|--------|
| Hands stuck / tied together / PM glitch | **Fixed** `8514387` — identity heal + raw unstick + frame clones |
| Black rectangle + hands tied (Quest 2) | Same glue path + black UI was prior PROPHECY (additive HUD) |
| Flicker / skybox when focused | **Fixed** mat_queue=1 pin (local; confirm smoke before WS) |
| DrawModel nil cl_character | **Fixed** `a26a750` |
| Avatar menu / twin mirror | In progress charik SoT — local only |
| Glide steer/throttle | Earlier fix in tree — confirm still OK vs Glide updates |
| Flying away / no buttons | Needs repro (locomotion / focus) |
| VR black / desktop OK | Module/runtime / share texture — not pure Lua |
| Fisheye / one eye | Border / stereo submit — separate track |

### Deploy
Local addons rsync'd. **No workshop** until headset smoke.

### Next loop
Re-fetch comments + bugs thread; implement only new actionable Lua bugs.
