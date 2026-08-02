# Prophecy: Shared VR Keyboard (module driver)

**Status:** Manifested (module v46+)  
**Law:** One keyboard pipeline for OpenXR launcher and in-game GMod.

## Architecture

```
Caller (chat | actions | newgame | mapbrowser | launcher form)
        │
        ▼
 vrmod.VRKeyboard_Open / AttachTextEntry / BindPanel
        │
        ├─ paint + laser (Lua panel2vr / VRUtilMenu)
        │
        ▼
 Module VRMOD_Keyboard*  (src/input/vkeyboard.cpp)
        text buffer · QWERTY layout · hit-test · shift
```

| Layer | Owns |
|-------|------|
| **C++ driver** | Session slots, text (512), key rects, PointerClick, shift layout |
| **Lua shell** | Surface paint, focus, onDone/onCancel/filter, placement |
| **Call sites** | Policy only (chat say, action name filter, hostname) |

## Roles → module slots

| Role | Slot | Use |
|------|------|-----|
| `default` | 1 | General / test |
| `launcher` | 2 | New game hostname, launcher forms |
| `chat` | 3 | Chat / console |
| `form` | 4 | Map browser TextEntry fields |

## Module API

```
VRMOD_KeyboardIsSupported() → true
VRMOD_KeyboardSystemAvailable() → false  (XR soft-KB reserved)
VRMOD_KeyboardOpen(title, text, w, h, slotHint) → id
VRMOD_KeyboardClose(id)
VRMOD_KeyboardIsOpen([id])
VRMOD_KeyboardGetInfo(id) → { text, upper, keys meta… }
VRMOD_KeyboardGetText / SetText / Append / Backspace
VRMOD_KeyboardGetShift / SetShift
VRMOD_KeyboardHitTest(id, x, y) → keyIndex|-1
VRMOD_KeyboardPointerClick(id, x, y) → action, text, lastChar
VRMOD_KeyboardGetKeys(id) → { {x,y,w,h,label,action,special}, … }
```

Actions: `1=CHAR 2=BACKSPACE 3=DONE 4=CANCEL 5=SHIFT 6=CLOSE 7=SPACE`

## Lua API

```lua
vrmod.VRKeyboard_Open({ title, text, onDone, onCancel, filter, role, place })
vrmod.VRKeyboard_OpenLauncher(opts)
vrmod.VRKeyboard_Close(commit)
vrmod.VRKeyboard_IsOpen()
vrmod.VRKeyboard_GetText()
vrmod.VRKeyboard_AttachTextEntry(panel, opts)
vrmod.VRKeyboard_BindPanel(panel, opts)  -- laser click → keyboard
```

## Wired call sites

- Chat panel → shared keyboard (`role=chat`)
- Actions panel → already `VRKeyboard_Open`
- New Game → hostname edit (`role=launcher`)
- Map browser → search / hostname / settings TextEntries

## Console

```
vrmod_keyboard_status
vrmod_keyboard_test
```

## Phase 2 (optional)

- OpenXR / Meta virtual keyboard when runtime exposes it (`KeyboardSystemAvailable`)
- UTF-8 multi-byte backspace
- OpenXR quad-layer keyboard surface
