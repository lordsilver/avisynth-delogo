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

Confirm that the mask dimensions match the full source and that every `Loc` value is even. Keep source, mask, and output paths in variables or use paths relative to the working directory.

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

For a faster, simpler alternative, test DoomDelogo with the same crop coordinates:

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

## Representative backgrounds

Test black bars, flat or gray areas, clothing or people, high-detail texture, and motion. Record the frame number, background class, exact parameters, output paths, visual result, and artifacts in a local work log for the current video.

Treat earlier settings only as starting points. Determine the region, mask, and final parameters again for every video, and never apply a black-bar restoration patch to colored content.

## Preview and render

Render a short preview before starting a full-length encode:

```powershell
ffmpeg -i .\preview.avs -c:v libx264 -preset ultrafast -crf 23 -t 30 .\preview.mp4
```

After reviewing representative frames and the preview, render to a new output path. Never overwrite the source video.
