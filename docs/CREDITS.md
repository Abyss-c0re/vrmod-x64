# Credits

**🥽 [G]VRMod: Ultimate** (`vrmod-x64`) stands on work by many people. Energy flows; credit is where credit is due.

---

## Core lineage

| Project | Author | Notes |
|---------|--------|--------|
| [**Original VRMod**](https://steamcommunity.com/workshop/filedetails/?id=1678408548) | **Catse** | Foundation — tracking, stereo, UI, character systems |
| [**Semi-official VRMod**](https://steamcommunity.com/sharedfiles/filedetails/?id=2780083257) | **Pescorr** | Ideas and patterns reimplemented / integrated here |
| [**gVRMod / this fork**](https://github.com/Abyss-c0re/vrmod-x64) | **Abyss-c0re (Doom Slayer)** | Linux x64, Cube Experience, crisp path, panel2vr |

Module backend: [vrmod-module-master](https://github.com/Abyss-c0re/vrmod-module-master) — OpenVR shared-texture path, dual OUT submit.

---

## Body / avatar algorithm (height twin · FBT · puppet)

| Project | Author | Workshop | What we learn from |
|---------|--------|----------|---------------------|
| **[VRMOD] VR Ragdoll Puppeteer** | **Pescorr** | [3695733221](https://steamcommunity.com/sharedfiles/filedetails/?id=3695733221) | 2-bone IK (`SolveTwoBoneIK`), pelvis-from-HMD offset, shoulder width, arm/leg chain lengths from bind pose, driven vs physics bones, head hide modes |

> Local extract for study (not redistributed as a copy of the Workshop GMA):  
> `Dev/GMod/downloads/vrmod_ragdoll_puppeteer_3695733221/`

Avatar mirror / height cal / FBT utilities in this tree should credit that algorithm lineage when they drive limbs from VR tracking (not raw `SetBoneWorld` stretch).

---

## Related VR / combat ecosystem

| Project | Author | Role |
|---------|--------|------|
| [**ArcVR**](https://steamcommunity.com/sharedfiles/filedetails/?id=1985324827) | **Arctic** | VR weapon base (forks / packs used with this mod) |
| ArcVR HL2 / INS2 packs | community | Weapon content (see Workshop collections) |
| [**Glide**](https://steamcommunity.com/sharedfiles/filedetails/?id=3389728250) | Styled et al. | Vehicle base integration |
| VR Climbing / VR Swimming | Workshop authors | Locomotion addons (optional) |

---

## Special thanks

- **Grocel** — Pro tips and being a real OG  
- **V vix** — Thumbnail  
- **func_dumbass** — Video tutorial  
- **plagueEMT** — Contributor (lineage / merge work; credit where due)  
- Workshop players who filed bugs (borders, Glide, hands, submit)  

### Sponsors & supporters

wsBoogie · RatBoggles · Lunascape · Littlcatzilla  

[Patreon](https://patreon.com/Abyss_c0re) · [Ko-fi](https://ko-fi.com/abyssc0re)

---

## Community

- Workshop: [🥽 G VRMod Ultimate](https://steamcommunity.com/sharedfiles/filedetails/?id=3442302711)  
- Group: [The VRMod Cult](https://steamcommunity.com/groups/gvrmod_x64)  

---

## License note

This addon is under the **CUBECHAIN LICENSE** (see root `LICENSE`). Third-party Workshop works remain their authors’ property; we cite algorithms and ideas, we do not claim their Workshop listings as ours.

---

*If your name should be here and isn’t, open an issue or PR.*
