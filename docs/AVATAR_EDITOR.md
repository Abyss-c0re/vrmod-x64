# `vrmod.avatar` — unified avatar editor

One ClientsideModel utility for **height cal** and **FBT**. Same playermodel, same ValveBiped bone map, same tracking source (`g_VR.tracking`).

## Module

`lua/vrmod/utils/cl_avatar_editor.lua` (loads with **utils**, before player/ui)

## API

```lua
-- Open session
local s = vrmod.avatar.Open({
  id = "height",              -- unique session id
  mode = "mirror",            -- "mirror" | "clone" | "world"
  distance = 48,
  follow = { hmd=true, hands=true, waist=false, feet=false },
  showTrackers = false,       -- FBT waist/feet boxes
  showHandTrackers = false,
  idleOnly = false,           -- no bone follow (FBT T-pose measure)
  hideLocalPlayer = false,
  menuUid = "heightmenu",
  menuAnchor = function(standPos, standAng, session) return pos, ang end,
  onClose = function(session) end,
})

s:GetEntity()
s:GetStand()       -- pos, ang
s:IsValid()
s:Close()

vrmod.avatar.Close(id)
vrmod.avatar.CloseAll()
vrmod.avatar.Get(id)
vrmod.avatar.IsOpen(id)

-- Presets
vrmod.avatar.OpenHeightCal("heightmenu")  -- mirror twin; FBT auto if sixPoints
vrmod.avatar.OpenFBTCal()                 -- world full-body copy + tracker boxes
```

## Modes

| Mode | Placement | Facing | Use |
|------|-----------|--------|-----|
| `mirror` | Ahead of HMD | Toward player (L/R flip) | Height / mirror twin |
| `clone` | Ahead of HMD | Same as player | Third-person preview |
| `world` | Under HMD feet | HMD yaw | FBT cal / underfoot twin |

## FBT (when on)

The Cube uses **one util**. If `g_VR.sixPoints` or waist+feet trackers live:

| 3-point | FBT |
|---------|-----|
| Pelvis ≈ HMD − offset | Pelvis = **waist** tracker |
| Arms: 2-bone IK → hands | Same |
| Legs: idle bind | Legs: **2-bone IK → feet** |
| No tracker boxes | Optional waist/feet boxes |

Algo lineage: Pescorr puppeteer (2-bone IK) — see `docs/CREDITS.md`.

## Consumers

- `cl_heightadjust.lua` → `OpenHeightCal`
- `sh_character_fbt.lua` → `OpenFBTCal` (reload to commit offsets)

## Tracking map

| Tracking | Bone(s) |
|----------|---------|
| `hmd` | Head1 (+ spine/pelvis estimate) |
| `pose_lefthand` / `righthand` | Full arm chain (IK) |
| `pose_waist` | Pelvis (FBT) |
| `pose_leftfoot` / `rightfoot` | Full leg chain (FBT IK) |
