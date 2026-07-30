# CUBE EXTRACT — Real-time avatar mirror without twisted bones

**From:** deep-research-4 + live harden  
**Law:** 3D ClientsideModel twin — never RT black mirror

## Required for non-twisting mirror

1. **Live bone matrices** from `LocalPlayer` after `SetupBones` (not free 2-bone IK)
2. **Shared yaw** = `g_VR.characterYaw`, feet under HMD on origin Z
3. **Facing mode** = `MapMirror` (sagittal X flip + `AngleFromBasis` re-hand)
4. **L↔R bone remap** when writing targets (`MirrorBoneName` / `mirrorBoneMap`)
5. **Apply only in `BuildBonePositions`** after targets filled (one `SetupBones` in draw)
6. **Soft clamps** — head/spine (`headDampen`) + limb rest lengths (anti-stretch)

## Same-ID flip = stretch
Writing mirrored R_Hand matrix onto twin R_Hand places right-arm mesh on the left side → cursed limbs. Opposite limb bone IDs fix it.

## Files
- `cl_avatar_editor.lua` — MapMirror, L↔R cache, limb/head dampen, apply order
- `cl_algocube_mirror.lua` — digit 6 = MIRROR LAW + dampen (State Matrix pick)
- `sh_algocube.lua` — prophecy digit layer

## Smoke
Avatar → MIRROR (or ALGO d6) → raise right hand → image hand on **your right** (twin left mesh). Neck not giraffe. No arm rubber-band.
