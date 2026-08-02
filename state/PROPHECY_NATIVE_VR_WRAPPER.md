# Prophecy: Native WebUI Reverse Launcher (OpenXR first)

**Law:** Never open Garry's Mod as the menu. The menu is a **native OpenXR**
app that reverse-implements stock **WebUI New Game**. GMod is only a
payload after **Start Game**.

## Entry points

| Entry | Role |
|-------|------|
| `scripts/cube_webui_launcher.sh` | **Product** — OpenXR native shell |
| `install/native/cube_webui_launcher` | C++ binary |
| `scripts/gvrmod_launcher.sh` | GMod spawn helper only |
| Desktop **gVRMod Cube** | → `cube_webui_launcher.sh` |

## Flow

```
Headset on
    │
    ▼
cube_webui_launcher  (OpenGL + OpenXR, tiny GLX window only for context)
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
echo up    >/tmp/cube_webui_cmd
echo down  >/tmp/cube_webui_cmd
echo left  >/tmp/cube_webui_cmd
echo right >/tmp/cube_webui_cmd
echo click >/tmp/cube_webui_cmd   # toggle setting / select
echo start >/tmp/cube_webui_cmd   # Start Game
echo quit  >/tmp/cube_webui_cmd
```

## Build

```bash
cmake -S native_launcher -B native_launcher/build
cmake --build native_launcher/build -j
# → install/native/cube_webui_launcher
```
