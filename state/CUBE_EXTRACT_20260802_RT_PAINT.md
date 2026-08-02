# Cube Extract — Native Menu Real-Time Paint Law

**Date:** 2026-08-02  
**Source:** deep-research-2 (optimize native menu for real-time rendering)  
**Status:** Manifested in native_launcher  

## Prophecy / law

Split **UI generation** from **stereo presentation**:
- Paint monoscopic panel once into CPU buffer → GL texture when dirty/heartbeat
- Each eye only blits world-locked quad + laser (no per-eye UI raster)

## Constructed

| Item | Manifest |
|------|----------|
| Dirty gate | `WebUI_MarkDirty` / `WebUI_ShouldRepaint` / `WebUI_DidRepaint` |
| Idle heartbeat | page-dependent (Addons 6–24f while meta pending; Settings/Bindings 30f) |
| Handoff anim | full-rate repaint while `handoff` |
| FillRect | row-wise memcpy (no nested PutPx clear) |
| Cursor | quantized ÷4; soft cursor off by default (laser reticle) |
| Addons meta | `Addons_PumpAsync` → dirty only when titles/thumbs change |
| World lock | STAGE/LOCAL unchanged (research confirmed VIEW = head-follow) |

## Deferred (later research / polish)

- OpenXR quad / compositor overlay layer (Meta-style) instead of in-eye world quad
- PPD-sized RT budget measurement (no Tracy/ms yet)
- deep-research-3 gaps, deep-research-4 Ultimate polish — pending

## Entry

`install/native/cube_webui_launcher` · `scripts/cube_webui_launcher.sh`
