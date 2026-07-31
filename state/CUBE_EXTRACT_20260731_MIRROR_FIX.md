# Cube Extract — 20260731 proper mirror (no twist)

## Law
3D ClientsideModel twin — never RT black mirror.
facing = sagittal MapPose + L↔R swap **before** ProcessArm.
Head = **angle-only** on existing SetupBones translation (cl_character BoneCallback).

## Fix (this drop)
| Issue | Cause | Fix |
|-------|--------|-----|
| Giraffe neck | frameik invented head pos (`parent.up*6` / `ent+Z64`); head not in boneinfo so path was inconsistent | Angle-only on live head matrix; soft pitch clamp |
| Twisted limbs | Same-ID write after flip; or armStretcher scale on twin | TransformFrame L↔R before IK; `ik.noStretch=true` + reach cap |
| Dampen dead | `headDampen` / `ClampBoneDist` never called after frameik rewrite | `_softenTargets()` after Apply |
| Real hands desync | twin called NetUpdateLocalPly | read-only frame (already) |

## SoT path
`ReadLocalVRFrame` → `TransformFrame(facing)` → `Apply(noStretch,headDampen)` → `_softenTargets` → `BuildBonePositions`

## Smoke
Avatar → MIRROR → raise **right** hand → image hand on **your right** (twin left mesh). Neck not giraffe. No arm rubber-band.
