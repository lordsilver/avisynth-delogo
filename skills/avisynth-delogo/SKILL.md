---
name: avisynth-delogo
description: Remove a burned-in logo or watermark from a user-supplied video with the portable Windows AviSynth+ InpaintDelogo toolchain, including mask alignment, configuration comparisons, previews, rendering, and validation. Use for one-video removal jobs or configuration tests, not unrelated video editing.
---

# AviSynth Delogo

Use the verified portable toolchain rather than an unverified system AviSynth installation. When the project checkout is available, verify `toolchain/manifests/toolchain.lock.json` and run `toolchain/scripts/verify-toolchain.ps1` natively on Windows before processing. Stop if required files are missing, hashes differ, or the bundled FFmpeg cannot render the smoke-test script.

Never overwrite or commit source media, generated media, indexes, masks, previews, or per-video work logs.

Inspect the source resolution, frame rate, duration, frame count, color metadata, and audio streams. Search the source for a frame where the logo sits on black, preferably pure black for a bright opaque logo, or another plain, uniform background. Prefer extracting and thresholding the logo from that frame because it separates the logo from scene content directly. Crop to the logo area as a temporary working view when that helps isolate it, but pad the result back to a full-frame mask at the original coordinates. A black frame can hide a dark outline or shadow, so also inspect a plain colored frame when the logo has one. Use `Automask=1` or a manually prepared reference only when no clean source frame exists.

Build a full-frame binary mask for the current video. Compare several threshold candidates when the logo has antialiased or soft edges, select the lowest threshold that captures the whole logo without including background pixels, and compare no dilation with the smallest useful dilation values when the threshold alone leaves an edge fringe or hidden shadow. Keep the least dilation that removes those remnants on difficult reference frames. Verify the mask overlaid on the source at native resolution; account for display scaling when the supplied logo reference is a screen capture. Reject any mask that includes unrelated text, UI, scenery, or padding as foreground.

Use even values for every `Loc` component. Include at least 18 pixels of usable picture around the nonzero mask bounds for HD or UHD sources, and do not include black bars in the region.

Use `Trim(n,n)` before pure inpaint filters. For analysis-dependent deblend or `Both` tests, filter the source timeline and trim afterward so the filter retains the frames needed for analysis.

Treat DoomDelogo only as a last-resort fallback when InpaintDelogo cannot be used. DoomDelogo synthesizes the whole selected rectangle from its borders, making its contents unreadable; it conceals rather than reconstructs and must not appear in the normal quality comparison matrix.

Choose 3–10 exact reference frames distributed across the entire video, including early, middle, and late sections. Favor frames where removal is hardest: flat colors, gradients, edges or text crossing the logo, high-detail texture, and motion. Use the same mask, `Loc`, and exact reference frames for every candidate. At minimum compare a default Inpaint baseline, `oPP=0`, relevant `Turbo` quality presets, and `Inflate=0` versus mask inflation when the edge coverage is uncertain. Test Deblend or Both only when the watermark is genuinely transparent or mixed; an opaque watermark normally belongs in pure Inpaint mode.

For every candidate, compare the original and processed full frame plus a nearest-neighbor enlarged crop of the logo region. Reject visible remnants, unnecessary softening, mask-edge halos, rectangular damage outside the mask, and temporal flicker. Metrics can verify that changes stay localized and consistent, but they cannot prove that hidden pixels were reconstructed correctly.

Record exact parameters, frames, background classes, output paths, results, and qualitative artifacts in a local work log for the current video. Do not assume that coordinates, masks, or final settings transfer to another video.

Do not accept a configuration after testing only one filter setup or one easy frame. Rank the candidates using the complete shared reference set, reduce the matrix to the best candidates, render the same short motion interval for each, and inspect them side by side before selecting one final configuration. Render the full video only after that winner passes both the 3–10-frame comparison and temporal preview. Do not apply a black-bar restoration to colored content.

Render to a new output path while preserving the source frame rate and color metadata. Re-encode the filtered video and stream-copy the original audio when compatible. Do not use `-shortest` when it would discard a longer final audio packet; verify audio packet counts or compare hashes of extracted elementary audio streams.

Validate the delivered file with a full decode, exact video frame count, stream metadata, and representative crops from the actual output.

When working from the project checkout, use `docs/testing-workflow.md` for command examples and trimming details.
