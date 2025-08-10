---
name: avisynth-delogo-testing
description: Test AviSynth+ InpaintDelogo or DoomDelogo configurations for one video using exact frames, representative backgrounds, masks, and reproducible evidence. Use for logo-removal evaluation, not for committing source media or reusable per-video presets.
---

# AviSynth Delogo Testing

Verify `toolchain/manifests/toolchain.lock.json` and run `toolchain/scripts/verify-toolchain.ps1` before testing. Stop if required files are missing or hashes differ.

Inspect the source resolution, frame rate, duration, and frame count. Confirm the full-frame mask and the even-valued `Loc` region before rendering.

Use `Trim(n,n)` before pure inpaint filters. For analysis-dependent deblend or `Both` tests, filter the source timeline and trim afterward so the filter retains the frames needed for analysis.

Test representative black bars, flat or gray areas, clothing or people, high-detail texture, and motion. Compare original and processed full frames plus a nearest-neighbor enlarged crop of the logo region.

Record exact parameters, frames, background classes, output paths, results, and qualitative artifacts in a local work log for the current video. Do not assume that coordinates, masks, or final settings transfer to another video.

Never overwrite source media, commit generated media or caches, or apply a black-bar restoration to colored content. Render and inspect a short preview before a full-length video.

Use `docs/testing-workflow.md` for command examples and trimming details.
