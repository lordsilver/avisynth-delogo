# Delogo Testing Workflow

Use this workflow to compare logo-removal configurations without changing source media or turning one successful frame into a universal recommendation.

## Prerequisites

Run the toolchain verification before testing:

```powershell
$toolchainRoot = Join-Path $env:LOCALAPPDATA "avisynth-delogo"
pwsh -File .\toolchain\scripts\verify-toolchain.ps1 -ToolchainRoot $toolchainRoot
```

Inspect the source before choosing frames:

```powershell
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate,nb_frames,duration -of json .\input.mp4
```

Confirm that the mask dimensions match the full source and that every `Loc` value is even. For HD and UHD sources, include at least 18 pixels of usable picture around the nonzero mask bounds and keep black bars out of the region. Keep source, mask, and output paths in variables or use paths relative to the working directory.

## Build the mask from the source

Search the source for a frame where the watermark sits on black, preferably pure black for a bright opaque watermark, or another plain, uniform background. Extracting the watermark from that frame is preferred because the mask can be separated from scene content directly. Crop to the watermark area as a temporary working view when that helps isolate it, then pad the finished mask back to the full source dimensions at the original coordinates. A black frame can hide a dark outline or drop shadow, so also inspect a plain colored frame when the watermark has one. If there is no clean frame, use `Automask=1` or prepare the mask manually from the best available reference.

Generate several binary threshold candidates when the watermark has soft or antialiased edges. Select the lowest threshold that covers the whole watermark without selecting background pixels. If the undilated mask leaves an edge fringe or a shadow that the mask-source background concealed, compare no dilation with the smallest useful dilation values and retain the least amount that removes those remnants on difficult reference frames. Do not use dilation as a substitute for choosing a correct threshold.

Keep saved-mask dilation and InpaintDelogo's `Inflate` parameter distinct in filenames and test records. A mask saved after a two-pixel morphological dilation with `Inflate=0` is not automatically interchangeable with the undilated mask and `Inflate=2`; compare them on the same exact frames before treating their results as equivalent.

The final mask must be full-frame, exactly match the source dimensions, and contain only the watermark as white foreground. Overlay it on a native-resolution source frame and reject it if unrelated text, UI, scenery, or rectangular padding is selected. Derive `Loc` from the nonzero bounds of the validated mask, round all four values to even numbers, and retain at least 18 pixels of usable picture around the mask for HD or UHD sources.

Do not begin filter tuning until this mask-alignment check passes. A filter comparison made with a contaminated or incomplete mask is invalid.

## Exact-frame tests

For pure inpaint tests, trim before the filter so only the requested frame is processed:

```python
sourcePath = "path/to/source-video.mp4"
maskPath = "path/to/logo-mask.bmp"
targetFrame = 1000
regionLoc = "1500,880,320,180"

source = LWLibAvVideoSource(sourcePath).Trim(targetFrame, targetFrame)
source.InpaintDelogo(Loc=regionLoc, mask=maskPath, Automask=0, Mode="Inpaint", Turbo=-1, oPP=-5)
```

For deblend or another analysis-dependent mode, run the filter on the source timeline and trim afterward so analysis can inspect the required neighboring frames:

```python
sourcePath = "path/to/source-video.mp4"
maskPath = "path/to/logo-mask.bmp"
targetFrame = 1000
regionLoc = "1500,880,320,180"

source = LWLibAvVideoSource(sourcePath)
processed = source.InpaintDelogo(Loc=regionLoc, mask=maskPath, Automask=0, Mode="Deblend", Analyze=2, AnalyzeTh=30, TriggerDynamic=1, Interp=0, dPP=-5)
processed.Trim(targetFrame, targetFrame)
```

Use DoomDelogo only as a last-resort fallback when InpaintDelogo cannot be used. It synthesizes the entire selected rectangle from its borders, making content inside unreadable rather than reconstructing the covered picture. Do not include it as a normal quality candidate:

```python
source = LWLibAvVideoSource(sourcePath).Trim(targetFrame, targetFrame)
source.DoomDelogo(1500, 880, 320, 180)
```

Extract the original and processed full frames losslessly:

```powershell
New-Item -ItemType Directory -Force .\.scratch | Out-Null
ffmpeg -i .\original-frame.avs -frames:v 1 .\.scratch\original-f1000.png
ffmpeg -i .\processed-frame.avs -frames:v 1 .\.scratch\processed-f1000.png
```

Create a nearest-neighbor enlarged crop for inspection:

```powershell
ffmpeg -i .\.scratch\processed-f1000.png -vf "crop=320:180:1500:880,scale=640:360:flags=neighbor" .\.scratch\processed-f1000-crop-2x.png
```

## Fixed comparison matrix

Choose 3–10 exact reference frames distributed across the full timeline, including early, middle, and late sections. Favor difficult backgrounds: flat colors, gradients, edges or text crossing the watermark, high-detail texture, and motion. Test every candidate on this same reference set with the same validated mask and `Loc`.

For an opaque watermark, the minimum useful matrix is:

- A default Inpaint baseline.
- The same configuration with `oPP=0` to expose post-processing softness.
- Relevant `Turbo` quality presets with other parameters held constant.
- Undilated and minimally dilated saved-mask revisions when edge coverage is uncertain.
- Filter-time `Inflate` only as a separately labeled comparison with the saved mask held constant.

Test Deblend or Both only when the watermark is genuinely transparent or mixed. These modes are not automatic upgrades for an opaque watermark.

For every candidate, compare the original and processed full frame and a nearest-neighbor enlarged crop. Reject visible remnants, unnecessary softening, mask-edge halos, rectangular damage outside the mask, and temporal inconsistency. Difference metrics can confirm that changes stay localized and consistent, but they are not a ground-truth score for pixels hidden by an opaque watermark.

Record the frame number, timeline position, background class, exact parameters, output paths, visual result, and artifacts in a local work log for the current video. Rank candidates only after every configuration has been rendered against the complete shared reference set. Do not accept a configuration after testing only one filter setup or one easy frame.

Treat earlier settings only as starting points. Determine the region, mask, and final parameters again for every video, and never apply a black-bar restoration patch to colored content.

## Preview and render

Reduce the fixed-frame matrix to the best candidates, then render the same short motion interval for each:

```powershell
ffmpeg -i .\preview.avs -c:v libx264 -preset ultrafast -crf 23 -t 30 .\preview.mp4
```

Inspect the candidate previews side by side for flicker, crawling edges, intermittent remnants, and detail loss. Select one final configuration only after it passes both the shared 3–10-frame comparison and temporal preview.

Only after that acceptance gate, render the entire video to a new output path. Never overwrite the source video.

Re-encode the filtered video and stream-copy the original audio when the output container supports it. Avoid `-shortest` when the source audio is slightly longer than the video because it can discard the last compressed audio packet.

Run the deterministic final checks from the checkout:

```powershell
pwsh -File .\toolchain\scripts\validate-render.ps1 `
  -SourcePath .\input.mp4 `
  -OutputPath .\output-delogo.mp4 `
  -ToolchainRoot $toolchainRoot
```

The validator counts every source and output video frame, compares dimensions, frame rate, pixel format, color metadata, chapters, and non-muxer format tags, hashes each stream-copied compressed audio payload, and fully decodes the delivered file. It intentionally ignores muxer-dependent tags such as `encoder` and `compatible_brands`. Use `-SkipAudioIdentity` only when audio transcoding was intentional.

Finally, extract representative crops from the actual delivered file and inspect them. Automated checks can prove structural integrity and audio identity, but they cannot judge the synthesized picture behind an opaque watermark.
