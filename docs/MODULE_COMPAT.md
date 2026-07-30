# Module ↔ Lua compatibility

## Law

1. **Lua never hard-requires brand-new C exports** for everyday VR start.  
2. **New module features use optional args or higher version**, not renamed functions that crash old binaries.  
3. **Engine RT size must match module OUT** — if the module cannot take eye W/H, do not supersample the RT.

## Versions

| Module `GetVersion()` | Behavior |
|----------------------|----------|
| **&lt; 20** | Hard refuse (too ancient / broken contract) |
| **20–22** | **Legacy path** — `ShareTextureBegin()` no args; `vrmod_supersample` size ignored (log once); full Lua features that are pure-Lua still work (panel2vr, Cube settings, swap eyes, Experience) |
| **≥ 23** | **Crisp path** — raw HMD rec, `ShareTextureBegin(eyeW, eyeH)`, SS + 4096 clamp, OUT realloc on size change |

Addon soft-warns when module &lt; recommended (23) but still starts.

## Safe call patterns (Lua)

```lua
-- Optional export
if isfunction(VRMOD_SetSubmitTextureBounds) then
  VRMOD_SetSubmitTextureBounds(...)
end

-- Optional ShareTexture args (v23+)
if (g_VR.moduleVersion or 0) >= 23 then
  VRMOD_ShareTextureBegin(eyeW, eyeH)
else
  VRMOD_ShareTextureBegin()
end
```

## Module change rules

When changing **vrmod-module-master**:

- Prefer **optional Lua arguments** on existing functions (see `ShareTextureBegin`).  
- Do **not** remove or rename existing exports.  
- Bump `GetVersion()` when behavior that Lua gates on changes.  
- Keep default path (zero-arg Begin) working so ancient Lua + new module still boots.

## Pure-Lua features (no module bump)

- panel2vr / Crimson Cube settings  
- Cube Experience / border cal  
- `vrmod_swap_eyes`  
- Blocked-cvar soft skip  
