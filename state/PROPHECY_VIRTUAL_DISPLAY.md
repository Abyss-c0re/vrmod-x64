# Prophecy: Virtual Display → Full OpenXR Immersive Launcher

**Status:** Phase 1 manifested (module driver + shared Lua pipeline)  
**Law:** One surface pipeline for launcher and in-game pause. Never `ActivateGameUI` in VR.

## The prophecy

> Start full VR launcher (OpenXR immersive), add a C++ module **virtual display** driver, project pause/main UI into a VR panel reusable between launcher and game, passed as a real display to GMod.

## Architecture (what ships)

```
┌─────────────────────────────────────────────────────────────┐
│  OpenXR session (HMD primary) + tiny desktop window         │
│  (launcher: gvrmod_launcher.sh 720×480 windowed)            │
└───────────────────────────┬─────────────────────────────────┘
                            │
     ┌──────────────────────▼──────────────────────┐
     │  vrmod.VirtualDisplay  (Lua — reusable API)   │
     │  sessions: "launcher" | "pause" | custom      │
     │  modes: native | vgui | capture | delegate    │
     └───────────┬──────────────────┬────────────────┘
                 │                  │
     ┌───────────▼────────┐  ┌──────▼──────────────────────┐
     │ panel2vr / hub     │  │ C++ VDisplay (module v45+)   │
     │ PaintManual RT     │  │ GL FBO + color tex           │
     │ laser → clicks     │  │ CaptureWindow (desktop blit) │
     └────────────────────┘  └─────────────────────────────┘
```

| Layer | Role |
|-------|------|
| **Launcher** | OpenXR immersive start, menu-first, full map optional |
| **VirtualDisplay Lua** | Single Present/Close for launcher + pause |
| **panel2vr** | VGUI/native RT → 3D surface + laser |
| **C++ VDisplay** | Module-owned “monitor” (FBO). CaptureWindow = real window → virtual buffer |
| **Cube hub** | Safe pause UI (no GameUI freeze) via `PresentPause` delegate |

## API (Lua)

```lua
-- Shared present
vrmod.VirtualDisplay.Present("launcher"|"pause"|name, {
  mode = "native"|"vgui"|"capture"|"delegate",
  place = "hand"|"cinema"|"float",
  panel = somePanel,       -- vgui
  drawFn = function(w,h,f) end, -- native
  openFn = function(session) end, -- delegate (hub)
  capture = true,          -- tick module CaptureWindow
  width = 720, height = 560,
})

vrmod.VirtualDisplay.PresentLauncher({ panel = mainMenu })
vrmod.VirtualDisplay.PresentPause()
vrmod.VirtualDisplay.Close("pause")
vrmod.VirtualDisplay.MapPointer("pause", u, v) → x, y

-- Console
vrmod_vdisplay_status
vrmod_vdisplay_capture [name]
```

## API (module / C++)

```
VRMOD_VirtualDisplayIsSupported() → bool
VRMOD_VirtualDisplayCreate(w, h [, slotHint]) → id | false, err
VRMOD_VirtualDisplayResize(id, w, h)
VRMOD_VirtualDisplayDestroy([id])  -- 0/nil = all
VRMOD_VirtualDisplayGetInfo(id) → { id, width, height, glTexture, glFBO, hasCapture }
VRMOD_VirtualDisplayCaptureWindow(id)  -- blit default FB → FBO
VRMOD_VirtualDisplayClear(id, r,g,b,a)
```

Linux: real GL FBO. Windows: slot registry stub (engine RT path still used).

## “Passed as real display to GMod” — honesty + path

| Claim | Phase 1 (now) | Phase 2 | Phase 3 |
|-------|----------------|---------|---------|
| Fixed virtual resolution for UI | Yes — Present sizes panels | Force `-w/-h` = virtual size | OS virtual monitor (DRM/X) |
| GPU-backed virtual buffer | Yes — module FBO | Sample into engine material | OpenXR **quad layer** from FBO |
| Desktop window capture | Yes — CaptureWindow | Live mirror material on panel | Zero-copy share |
| Stock GameUI as pause | **No** (SP freeze) | Optional safe path if engine fixed | — |
| Launcher + pause same code | **Yes** | — | — |

GMod still opens a real SDL/GLX window (required for GLX + OpenXR bind). The **display of truth for VR UI** is the VirtualDisplay session, not the desktop chrome.

## Files

| Path | Role |
|------|------|
| `src/rendering/vdisplay/vdisplay.{h,cpp}` | C++ driver |
| `src/lua/lua_interface.cpp` | Lua exports (module v45) |
| `lua/vrmod/utils/cl_virtual_display.lua` | Shared Present/Close |
| `lua/vrmod/utils/cl_gameui_project.lua` | VGUI bind → VirtualDisplay |
| `lua/vrmod/ui/cl_vr_mainmenu.lua` | Launcher → PresentLauncher |
| `lua/vrmod/ui/cl_vr_pausemenu.lua` | Pause → PresentPause |

## Smoke checklist

1. Rebuild module (`build.sh` / install to `lua/bin`).
2. `vrmod_status` / module version **45+**.
3. Launcher: hub or main-menu panel opens via VirtualDisplay.
4. In map: ESC → Cube hub; `vrmod_vdisplay_status` shows `pause`.
5. `vrmod_vdisplay_capture launcher` after VR start → hasCapture when GL ready.
6. World stays **unpaused** (no GameUI trap).

## Non-goals (this phase)

- Kernel/DRM virtual monitor for GMod
- Re-enabling `ActivateGameUI` projection
- True zero-display headless client
