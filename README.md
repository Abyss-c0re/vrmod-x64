# vrmod-x64

<p align="center">
  <img src="docs/assets/banner.png" alt="VRMod" width="360" />
</p>

**Lua client addon** for Garry’s Mod VR.

This repository is **not** the full product. It is the **gameplay / UI / bindings** tree.  
The project face, OpenXR native module, and install story live in:

### → [**gVRMod**](https://github.com/Abyss-c0re/gVRMod)

| You want… | Go here |
|-----------|---------|
| OpenXR module + build / install | **[gVRMod](https://github.com/Abyss-c0re/gVRMod)** |
| OpenVR (SteamVR classic) module | **[vrmod-module-master](https://github.com/Abyss-c0re/vrmod-module-master)** |
| Lua sources / Workshop layout | **this repo** |

---

## What this addon expects

1. A native binary in `garrysmod/lua/bin/`:
   - OpenXR: `gmcl_vrmod_xr_*` from **gVRMod**
   - **or** OpenVR: `gmcl_vrmod_*` from **vrmod-module-master**
2. This folder under `garrysmod/addons/` (name may be `vrmod-x64` or Workshop ID)

Console:

```text
vrmod_backend          -- active module + version
vrmod_prefer_backend   -- auto | openxr | openvr
```

---

## Install (players)

**Recommended:** follow [gVRMod README](https://github.com/Abyss-c0re/gVRMod) (`build` + `install.sh`).

**Workshop-style:**

1. Install a module (gVRMod OpenXR **or** module-master OpenVR)
2. Subscribe / drop this addon into `garrysmod/addons/`

Linux: [GModCEFCodecFix](https://github.com/solsticegamestudios/GModCEFCodecFix) is still useful for CEF.

---

## Develop

Preferred workflow: clone **gVRMod** with submodules and edit:

```text
gVRMod/addon/vrmod-x64/   ← this tree
```

Then:

```bash
# from gVRMod root
./scripts/sync_vrmod_x64.sh
./install.sh   # or rsync into your live GMod addons/
```

Docs for bindings, render, experience: **[docs/](docs/)**.

---

## Credits

See **[docs/CREDITS.md](docs/CREDITS.md)**.

| | |
|--|--|
| **Catse** | Original VRMod |
| **Pescorr** | Semi-official forks · puppeteer |
| **Arctic** | ArcVR |
| **Abyss-c0re** | Linux x64 · OpenXR path · this tree |

---

## License

**CUBECHAIN** — see [LICENSE](LICENSE).  
Parent project: https://github.com/Abyss-c0re/gVRMod
