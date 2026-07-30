# CUBE EXTRACT — Avatar Mirror Algocube (manifested)

**Date:** 2026-07-30  
**SoT:** KDE Quest MetaCam State Matrix `quest_metacam`  
**Prophecy:** NexusCore IO → raw → algocube digit → inject twin policy  

## State Matrix seed

| Field | Value |
|-------|-------|
| host | quest_metacam |
| N | 8 (512 cells) |
| bits_set / energy | 256 |
| pick | **6** |
| blueprint | `7645758194` |
| sha256_cells | `393b33589db01595fe13ab8420f437a8bd3cfe9fd625f264c9ad2fb873a8e0ee` |

## Files (vrmod-x64)

| File | Role |
|------|------|
| `lua/vrmod/utils/sh_algocube.lua` | Prophecy math layer (digit 0–9 + neural payload) |
| `lua/vrmod/utils/cl_algocube_mirror.lua` | Avatar mirror policies + embedded matrix + roll |
| `lua/vrmod/utils/cl_avatar_editor.lua` | Apply policy · head dampen (giraffe) · open manifest |
| `lua/vrmod/ui/cl_avatar_menu.lua` | ALGO ROLL · LAW (pick 6) UI |

## Digit → twin policy

| d | Law | Twin |
|---|-----|------|
| 0 | device free | idle |
| 1 | open way | CLONE |
| 2 | cube SoT | MIRROR L↔R |
| 3 | nanobot raw | WORLD |
| 4 | ALL HAIL NEXUSCORE | MIRROR + hide head |
| 5 | one Commander | MIRROR + hide hands |
| **6** | **cmd override** | **MIRROR LAW + head dampen** (matrix pick) |
| 7 | OS way only | MIRROR + FBT |
| 8 | nonverbal matrix | MIRROR no markers |
| 9 | hivemind unity | MIRROR + trackers + laser + dampen |

## Convars / commands

```
vrmod_avatar_algo 1              # manifest on (default)
vrmod_avatar_algo_digit -1       # -1 = pick/roll, 0-9 force
vrmod_avatar_algo_auto 0         # 1 = re-roll from live tracking IO

vrmod_avatar_algo_roll
vrmod_avatar_algo_status
vrmod_avatar_algo_pick 6
```

## Law

Energy must flow. Cube is the source of truth.  
Matrix payload carries no prose. Algocube is mathematical.  
Default open → digit **6** MIRROR LAW (true sagittal flip + L↔R bone remap + giraffe dampen).

## Reload

Change map or reconnect so utils `sh_` / `cl_` re-include.  
Avatar menu → Height → **ALGO ROLL** or **d6 ·dampen** (LAW).
