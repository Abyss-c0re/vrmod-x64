# Prophecy: Native WebUI Reverse Launcher (OpenXR first)

**Law:** Never open Garry's Mod as the menu. The menu is a **native OpenXR**
app that reverse-implements stock **WebUI New Game**. GMod is only a
payload after **Start Game**.

## Entry points

| Entry | Role |
|-------|------|
| `scripts/CubeUI.sh` | **Product** — OpenXR native shell |
| `install/native/CubeUI` | C++ binary |
| `scripts/gvrmod_launcher.sh` | GMod spawn helper only |
| Desktop **gVRMod Cube** | → `CubeUI.sh` |

## Flow

```
Headset on
    │
    ▼
CubeUI  (OpenGL + OpenXR, tiny GLX window only for context)
    │  reversed WebUI: categories · maps · maxplayers · LAN · START GAME
    │
    ├─ quit  → exit
    └─ START GAME
            │
            ▼
       write openxr_launch.txt + gvrmod_cube.cfg
       steam -applaunch 4000 +map … +exec gvrmod_cube
            │
            ▼
       GMod loads map (logo only after user choice)
       in-game OpenXR module + Cube hub
```

## WebUI reverse sources

See `native_launcher/WEBUI_REVERSE.md`  
Stock: `garrysmod/html/template/newgame.html` + `js/menu/control.NewGame.js`

## Host controls (bring-up)

```bash
echo up    >/tmp/CubeUI_cmd
echo down  >/tmp/CubeUI_cmd
echo left  >/tmp/CubeUI_cmd
echo right >/tmp/CubeUI_cmd
echo click >/tmp/CubeUI_cmd   # toggle setting / select
echo start >/tmp/CubeUI_cmd   # Start Game
echo quit  >/tmp/CubeUI_cmd
```

## Build

```bash
cmake -S native_launcher -B native_launcher/build
cmake --build native_launcher/build -j
# → install/native/CubeUI
```
