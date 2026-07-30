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
vrmod.avatar.OpenHeightCal("heightmenu")  -- mirror twin + hands/head
vrmod.avatar.OpenFBTCal()                 -- world idle + tracker boxes
```

## Modes

| Mode | Placement | Facing | Use |
|------|-----------|--------|-----|
| `mirror` | Ahead of HMD | Toward player (L/R flip) | Height cal twin |
| `clone` | Ahead of HMD | Same as player | Third-person preview |
| `world` | Under HMD feet | HMD yaw | FBT calibration pose |

## Consumers

- `cl_heightadjust.lua` → `OpenHeightCal`
- `sh_character_fbt.lua` → `OpenFBTCal` (reload to commit offsets)

## Tracking map

| Tracking | Bone(s) |
|----------|---------|
| `hmd` | Head1 |
| `pose_lefthand` / `righthand` | L/R Hand (+ upper arm aim) |
| `pose_waist` | Pelvis |
| `pose_leftfoot` / `rightfoot` | L/R Foot (+ thigh/calf aim) |
