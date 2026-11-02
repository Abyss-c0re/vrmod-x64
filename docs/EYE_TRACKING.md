# Eye tracking on the player frame

Eye gaze is optional on both sides. The client convar `vrmod_eyetracking` defaults to **0**. The server convar `vrmod_sv_eyetracking` is archived and replicated and defaults to **1** (allow). A server that does not have that convar is treated as allow, so an older server does not look like a ban.

Character eyes still use `g_VR.tracking.pose_gaze` locally and the older `vrmod_eye_gaze` net message. The frame tail is the shared API. An older sender that only speaks `vrmod_eye_gaze` still moves remote character eyes. `vrmod.GetEyeGaze` reads the frame (or the live local sample), not that older message.

## When a sample is sent

All of these must hold:

- Server allow is not an explicit off (`0` / `false`). Missing convar allows.
- Client `vrmod_eyetracking` is on.
- `g_VR.tracking.pose_gaze` and the HMD angle exist and are finite.

Otherwise the tick is the same bytes as a build with no eye tracking at all. Turning gaze off changes the frame, so the next tick is still sent and remotes drop the sample.

The server strips the tail before it stores or relays the tick when allow is off. Turning the server convar off also pushes one stripped tick for players who currently have a sample. The legacy `vrmod_eye_gaze` message is answered with `active = false` and is not forwarded.

## Wire

`vrutil_net_tick` is unchanged through the waist block (the same optional full-body block as before).

After that block, only if gaze is on:

| Field | Type | Meaning |
| --- | --- | --- |
| magic | uint8 | `225` (`0xE1`) |
| pitch | uint16 | HMD-relative pitch, degrees |
| yaw | uint16 | HMD-relative yaw, degrees |

40 bits, 5 bytes. Pitch is clamped to [-89, 89]. Yaw is wrapped to [-180, 180]. The uint16 span is 65536 steps over 360 degrees. 0° is exact. +180° and -180° are the same direction.

The integers are already relative to the HMD. `FrameToRelative` / `FrameToAbsolute` copy them. They are not run through `WorldToLocal` again.

A reader stops after the waist bool when `net.BytesLeft()` is under 5. That is an older tick, or this client has gaze off. A first byte that is not `225` is ignored and nothing after it is read.

An older reader that stops after the waist block never looks at the tail. GMod messages are length-prefixed, so the extra bytes do not shift the next message. An older server re-serializes with its own writer and therefore drops the tail on relay. Very old servers also cap `vrutil_net_tick` at **1200 bits**. A full-body tick plus this tail can exceed that and be dropped. New servers accept up to **2048 bits**. Gaze off stays inside the old size, because nothing is appended.

World gaze for a remote player is the HMD position plus the local pitch/yaw composed onto the world HMD angle. The local flashlight does not use that quantized sample. It uses `vrmod.GetEyeGaze(LocalPlayer())`, which is the live `pose_gaze`.

## API

| Call | Realm | Result |
| --- | --- | --- |
| `vrmod.EyeTrackingEnabled()` | both | Client convar. Missing convar falls back to `g_VR.eyeTracking.enabled`. |
| `vrmod.EyeTrackingAllowed()` | both | Server convar. Missing means allow. |
| `vrmod.GetEyeGaze(ply)` | both | `pos, ang`, or `nil` when off / disallowed / no sample. |
| `vrmod.GetEyeGazeActive(ply)` | both | `true` when `GetEyeGaze` has a pose. |
| `vrmod.GetEyeGazeLocal(ply)` | both | HMD-relative pitch, yaw in degrees, or `nil`. |

On the client, the local player returns the live sample. Another player returns the lerped frame. On the server, both come from that player's latest tick. `nil` means "no gaze". It is not a zero vector.

`vrmod.GetEyePos` is still the stereo camera. It is not gaze.

## Look target

`vrmod.utils.LookTarget_Select` turns a trace into the entity and the exact hit point. `vrmod.utils.LookTarget_Query(ply, maxDist)` runs that trace from `vrmod.GetEyeGaze`. World and sky return the point and no object. A miss returns the point at `maxDist` along the look.

## Pickup

Gameplay → **Pickup source** (`vrmod_pickup_source`): hand proximity `0` or eye gazing `1`. **Hand trigger distance** (`vrmod_pickup_hand_range`, default 3.5) and **Eye trigger distance** (`vrmod_pickup_eye_range`, default 12) are client-only and use the same scale as the server pickup range. Eye gazing drives either grip from the look ray. If that mode is selected and there is no gaze sample, selection falls back to hand proximity. The only override is a hand touching the prop (6 units to the surface). A hand held in front of the body is not a touch, so it does not blank the other hand. Menu grab, foregrip, and pickup disable still run before the grab. The right hand still will not take a second copy of the weapon it is holding.

## Flashlight

Gameplay settings:

- **Flashlight aim** (`vrmod_flashlight_aim`): Right hand `0`, Left hand `1`, HMD `2`, Eye tracking `3`. Default `0`.
- **Flashlight fallback hand** (`vrmod_flashlight_eye_fallback`): Right `0`, Left `1`. Default `0`.

Aim `3` uses gaze only when the client convar is on, the server allows it, and there is a live sample. If gaze is selected but off, or the sample is missing that frame, the beam uses the fallback hand. Right hand still follows the weapon muzzle when a viewmodel muzzle exists. The old `vrmod_flashlight_attachment` convar (0..2) is copied into aim once, then left alone. The settings checkbox that used to write it is gone, because a bool cannot represent four aims.

## What offline tests cover

`tests/lua/unit/eye_frame_test.lua` locks the pure helpers in `lua/vrmod/utils/sh_eye_frame_law.lua`:

- server missing vs explicit off, client `"0"` (Lua-truthy but off), no pose, NaN, both-off reason order
- pack/unpack clamp, yaw wrap, +180/-180, hostile uint16
- no bytes written when gaze is off; short tail not read; bad magic consumes one byte; round-trip of the 40-bit tail
- `FramesAreEqual` both directions so gaze-off still sends; relative/absolute copy does not rebase the uints
- compose onto the HMD, including yaw 90° plus a downward pitch
- reused world-pose table cleared when the next tick has no eye; server `false` and `"0"` strip; `nil` allow keeps it
- flashlight aim matrix, including invalid aim/fallback clamped to the right hand
- settings rows: aim combo, hand-only fallback, server allow bool

Those tests do not open a headset or an OpenXR session.
