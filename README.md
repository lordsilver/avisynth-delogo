# avisynth-delogo

A reproducible Windows toolchain and testing guide for removing logos, watermarks, and other unwanted graphics from videos using AviSynth+ with InpaintDelogo and DoomDelogo. Every video must be evaluated independently; the repository does not store per-video configurations, source media, or unchecked local toolchain dumps.

## Table of Contents

1. [Reproducible Toolchain](#reproducible-toolchain)
2. [Quick Start Guide](#quick-start-guide)
3. [Command Reference](#command-reference)
4. [Common Parameters](#common-parameters)
5. [Workflow for New Projects](#workflow-for-new-projects)
6. [Exact-frame Testing](#exact-frame-testing)
7. [Troubleshooting](#troubleshooting)
8. [FFmpeg Export Commands](#ffmpeg-export-commands)
9. [Downloads & Dependencies](#downloads--dependencies)
10. [Maintenance Notes](#maintenance-notes)

## Reproducible Toolchain

The repository pins required Windows files in `toolchain/manifests/toolchain.lock.json`. The lock records each installed file's relative path, component and version, architecture, source or release asset, SHA-256, license project, and required status.

Repository maintainers can let mise install the pinned PowerShell, 7-Zip, formatting, validation, and GitHub tooling, then use the same task entry points locally and in CI:

```powershell
mise install
mise run bootstrap:toolchain -- -ToolchainRoot $toolchainRoot -OfflineCacheRoot $offlineCacheRoot
mise run verify:toolchain -- -ToolchainRoot $toolchainRoot
mise run build:toolchain -- -OutputDirectory .\dist -Version 2026.08.25
mise run build:sources -- -SourceDirectory .\source-assets -OutputDirectory .\dist -Version 2026.08.25
```

The standalone PowerShell commands below remain supported so release consumers do not need mise after downloading the repository or release bundle.

The release remains a standard Windows-compatible ZIP. The builder places the pinned `ffmpeg.exe` and `ffprobe.exe` at the toolchain root beside `AviSynth.dll`, where Windows can resolve FFmpeg's dynamically loaded AviSynth runtime without a system-wide installation or a duplicate DLL. AvsPmod is installed directly under `AvsPmod`, and all x64 AviSynth+ plugins are installed directly under `Plugins`; the portable bundle has no redundant `Tools` or `plugins64+` wrapper directories. Installed-file hashes are locked and Windows verification renders a one-frame `BlankClip()` through the bundled FFmpeg. FFplay, FFmpeg HTML documentation, and FFmpeg presets are excluded because the delogo workflow requires only FFmpeg and FFprobe.

Bootstrap into a predictable root:

```powershell
$toolchainRoot = Join-Path $env:LOCALAPPDATA "avisynth-delogo"
$offlineCacheRoot = Read-Host "Path to the copied or archived toolchain cache"
pwsh -File .\toolchain\scripts\bootstrap-toolchain.ps1 -ToolchainRoot $toolchainRoot -OfflineCacheRoot $offlineCacheRoot
```

Verify installed hashes and AviSynth+/FFmpeg/FFprobe availability:

```powershell
pwsh -File .\toolchain\scripts\verify-toolchain.ps1 -ToolchainRoot $toolchainRoot
```

The lock is generated from the supplied x64 toolchain. `toolchain/manifests/sources.yaml` records the upstream comparison made on August 25, 2026, including components that were upgraded and legacy binaries for which no newer official build was found.

GitHub Actions rebuilds the ready-to-use x64 ZIP from pinned sources on pull requests, `v*` tags, and manual dispatches. At 00:00 UTC on the first day of each month, the scheduled run checks only upstream versions and creates or refreshes the toolchain-update issue when newer inputs are available. A version tag downloads and verifies each pinned input once, builds from that local cache, then publishes `avisynth-delogo-x64-<version>.zip` and a matching `avisynth-delogo-sources-<version>.zip`, each with a checksum. The aggregate sources ZIP contains every unchanged upstream input, including the pinned InpaintDelogo and DoomDelogo `.avsi` files, along with the lock, source catalog, notices, and archive documentation. The binary ZIP also keeps `THIRD-PARTY-NOTICES.md`, `toolchain.lock.json`, and `sources.yaml` so a standalone download still carries license and source provenance. Binaries remain out of Git history.

After extracting a release, activate it in PowerShell:

```powershell
. .\activate.ps1
pwsh -File .\verify-toolchain.ps1 -ToolchainRoot $env:AVISYNTH_DELOGO_ROOT
```

Launch AvsPmod through `Start-AvsPmod.cmd`. The launcher uses the bundled relative AviSynth path and configures the current user's AviSynth+ plugin autoload directory before starting AvsPmod; launching the nested `AvsPmod.exe` directly bypasses that portable setup.

| Component                               | Selected version           | Upstream status                                                         |
| --------------------------------------- | -------------------------- | ----------------------------------------------------------------------- |
| AviSynth+                               | 3.7.5                      | Latest stable                                                           |
| AvsPmod GPo                             | 2.7.9.7                    | Upgraded from 2.7.9.4                                                   |
| InpaintDelogo                           | 3.7 at commit `a6cc5d7`    | Active file matches upstream                                            |
| DoomDelogo                              | 1.0 at commit `cfed253`    | Included as the faster alternative                                      |
| FFT3DFilter                             | 2.12                       | Upgraded from 2.11                                                      |
| L-SMASH-Works                           | 1310.0.0.0                 | Upgraded from 1266.0.0.0                                                |
| Neo FFT3D                               | r14                        | Upgraded from r11                                                       |
| AvsInpaint / MaskTools2 / FFMS2 / GRunT | 1.3 / 2.2.30 / 5.0 / 1.0.2 | Latest stable assets                                                    |
| FrameSel / RT_Stats                     | 2.20 / 2.00Beta12          | Preserved author archives recovered from AviSynth Wiki archive links    |
| FFTW single-precision runtime           | 3.3.5                      | Latest official precompiled Windows DLL; Neo FFT3D loads it dynamically |

## Quick Start Guide

### Basic Workflow

1. **Import video** using `LWLibAvVideoSource()`
2. **Locate and isolate logo** using `Crop()` to select ONLY the logo area
3. **Generate base mask** with `InpaintDelogo()` and `Automask=1`
4. **Remove the crop line** and run `InpaintDelogo()` again with `Automask=0`
5. **Export with FFmpeg**

### Essential AviSynth Commands

```python
# Import video
sourcePath = "path/to/source-video.mp4"
maskPath = "path/to/logo-mask.bmp"
LWLibAvVideoSource(sourcePath)

# Define the region once as left, top, width, height.
# InpaintDelogo requires every Loc value to be even.
regionX = 1500
regionY = 880
regionW = 320
regionH = 180
regionLoc = String(regionX) + "," + String(regionY) + "," + String(regionW) + "," + String(regionH)

# Preview the exact region.
Crop(regionX, regionY, regionW, regionH)

# Or preview Loc through InpaintDelogo's own coordinate helper.
InpaintLoc(Loc=regionLoc)

# After removing the Crop line, generate or use the mask with the same region.
InpaintDelogo(Loc=regionLoc, mask=maskPath, Automask=1, Analyze=2)
InpaintDelogo(Loc=regionLoc, mask=maskPath)

# Alternative: DoomDelogo (faster, lower quality)
DoomDelogo(regionX, regionY, regionW, regionH)
```

`Crop()` and `Loc` accept the same two forms: `left, top, width, height`, or `left, top, -rightTrim, -bottomTrim`. Prefer the positive width/height form because names such as `-w` and `-h` are misleading: negative values are edge trims, not the selected width and height.

## Command Reference

| Function               | Purpose                                     | Example                          |
| ---------------------- | ------------------------------------------- | -------------------------------- |
| `LWLibAvVideoSource()` | Import video file                           | `LWLibAvVideoSource(sourcePath)` |
| `InpaintDelogo()`      | Advanced logo removal                       | See parameters below             |
| `DoomDelogo()`         | Simple logo removal (faster, lower quality) | `DoomDelogo(50, 50, -100, -100)` |
| `Crop()`               | Preview logo area                           | `Crop(50, 50, -100, -100)`       |

### InpaintDelogo Parameters

#### Essential Parameters

| Parameter  | Values                                                           | Description                                           |
| ---------- | ---------------------------------------------------------------- | ----------------------------------------------------- |
| `Loc`      | `"left,top,width,height"` or `"left,top,-rightTrim,-bottomTrim"` | Crop coordinates; every value must be even            |
| `mask`     | `maskPath`                                                       | Path variable for the full-frame mask                 |
| `Automask` | 0, 1                                                             | 1=Generate mask, 0=Use existing mask                  |
| `Mode`     | "Inpaint", "Deblend", "Both"                                     | Removal method; defaults to Inpaint for a normal mask |
| `Analyze`  | -4 to 3                                                          | Forced to 0 for Inpaint; defaults to 2 otherwise      |
| `aMix`     | -50 to 6                                                         | Mask thickness adjustment used only with `Automask=1` |

#### Advanced Parameters

| Parameter | Default | Range   | Description                                     |
| --------- | ------- | ------- | ----------------------------------------------- |
| `Inflate` | 1       | 0-2     | Expand mask by pixels                           |
| `Deep`    | 3       | 1-5     | Multi-pass processing                           |
| `Interp`  | 2       | 0-4     | Interpolation for artifacts                     |
| `dPP`     | -3      | -8 to 8 | Blur or denoise applied to the deblended area   |
| `oPP`     | -5      | -8 to 8 | Blur or denoise applied to the inpainted area   |
| `Turbo`   | 0       | -2 to 3 | Speed versus quality preset, including UHD `-1` |

#### Analysis Parameters

| Parameter   | Description                         |
| ----------- | ----------------------------------- |
| `FrB`       | Frame number with dark background   |
| `FrW`       | Frame number with bright background |
| `FrS`       | Extended frame sequences (0-3)      |
| `ReAnalyze` | Force re-analysis on script load    |

## Common Parameters

### Logo Removal Modes

- **Inpaint**: Default for normal masks; use for opaque/solid logos
- **Deblend**: For transparent/semi-transparent logos
- **Both**: For logos with mixed transparency

These are starting points, not reusable presets. Test representative frames from each background type in the current video, and tune the mask, region, analysis, and post-processing for that video before rendering.

### Analysis Methods

- **`Analyze=1`**: Smart automatic frame selection using pixels around the base-mask edges; intended for Deblend/Both and unavailable while `Automask=1`
- **`Analyze=2`**: Smart automatic frame selection using pixels around the `Loc` edges; recommended for `Automask=1`
- **`Analyze=3`**: Analyze every frame without frame selection
- **`Analyze=-1` and `Analyze=-2`**: Deprecated deblend methods corresponding roughly to the positive automatic methods
- **`Analyze=-3`**: Deprecated manual analysis using `FrB` and `FrW`
- **`Analyze=-4`**: Deprecated manual white-logo method using `FrB`; acceptable for some automasks but generally not recommended for delogo

Only analyze frames where the logo is present and not animated. Do not use `Prefetch()` during analysis.

### Quality vs Speed Settings

```python
# High Quality (slow)
Turbo=0, Deep=5, Analyze=3

# Balanced
Turbo=0, Deep=3, Analyze=1

# Fast (lower quality)
Turbo=2, Deep=1, Analyze=1
```

## Workflow for New Projects

### Step 1: Project Setup

```python
# Create new .avs file
sourcePath = "path/to/source-video.mp4"
maskPath = "path/to/logo-mask.bmp"
LWLibAvVideoSource(sourcePath)

# Keep these values even and reuse them everywhere.
regionX = 1500
regionY = 880
regionW = 320
regionH = 180
regionLoc = String(regionX) + "," + String(regionY) + "," + String(regionW) + "," + String(regionH)
```

### Step 2: Locate and Isolate Logo

```python
# Include 10-20 pixels around the logo; 18 or more is recommended for HD/UHD.
Crop(regionX, regionY, regionW, regionH)
```

### Step 3: Generate Base Mask

```python
# Comment out the Crop line
# Crop(regionX, regionY, regionW, regionH)

# Generate the mask using the same region.
InpaintDelogo(Loc=regionLoc, mask=maskPath, Automask=1, Analyze=2, aMix=-2)
```

### Step 4: Fine-tune Mask (if needed)

- Check generated mask.bmp file
- Edit manually in image editor if needed
- Adjust `aMix` and regenerate if necessary

### Step 5: Perform Logo Removal

```python
# Keep Crop commented out and process the full video.
# Automask=0 and Mode="Inpaint" are the defaults for a normal BMP mask.
InpaintDelogo(Loc=regionLoc, mask=maskPath)
```

In Inpaint mode, InpaintDelogo forces `Analyze=0`, so setting `Analyze=-4` has no effect. `aMix` is used only while `Automask=1`, so it also has no effect during this removal step.

### Step 6: Post-Processing Options

```python
# Better quality (complex logos)
Mode="Both", Deep=5, Interp=3

# Faster processing
Turbo=2

# Very transparent logos; analyze every eligible frame
Mode="Deblend", Analyze=3
```

## Exact-frame Testing

Use exact zero-based frame numbers and preserve each filter's analysis requirements. For pure inpaint, trim before filtering so only the target frame is processed:

```python
sourcePath = "path/to/source-video.mp4"
maskPath = "path/to/logo-mask.bmp"
targetFrame = 1000
regionLoc = "1500,880,320,180"

source = LWLibAvVideoSource(sourcePath).Trim(targetFrame, targetFrame)
source.InpaintDelogo(Loc=regionLoc, mask=maskPath, Automask=0, Mode="Inpaint", Turbo=-1, oPP=-5)
```

For analysis-dependent deblend or `Both` tests, filter the source timeline and trim afterward:

```python
sourcePath = "path/to/source-video.mp4"
maskPath = "path/to/logo-mask.bmp"
targetFrame = 1000
regionLoc = "1500,880,320,180"

source = LWLibAvVideoSource(sourcePath)
processed = source.InpaintDelogo(Loc=regionLoc, mask=maskPath, Automask=0, Mode="Deblend", Analyze=2, AnalyzeTh=30, TriggerDynamic=1, Interp=0, dPP=-5)
processed.Trim(targetFrame, targetFrame)
```

Compare the original and processed full frame, then create a nearest-neighbor enlarged crop of the logo region:

```powershell
New-Item -ItemType Directory -Force .\.scratch | Out-Null
ffmpeg -i .\processed-frame.avs -frames:v 1 .\.scratch\processed-f1000.png
ffmpeg -i .\.scratch\processed-f1000.png -vf "crop=320:180:1500:880,scale=640:360:flags=neighbor" .\.scratch\processed-f1000-crop-2x.png
```

Test black bars, flat or gray areas, clothing or people, high-detail texture, and motion. See `docs/testing-workflow.md` for the complete procedure.

## Troubleshooting

### Common Issues and Solutions

| Problem                      | Solution                                                                        |
| ---------------------------- | ------------------------------------------------------------------------------- |
| Logo remnants visible        | Increase `Deep`, try `Mode="Both"`                                              |
| Artifacts around logo        | Adjust `Interp`, increase `dPP`                                                 |
| Mask too thick/thin          | Adjust `aMix` value                                                             |
| Poor mask generation         | Use `Automask=1, Analyze=2`, then adjust `aMix`                                 |
| Processing too slow          | Use `Turbo=1-3`, decrease `Deep`                                                |
| `Use even numbers for "Loc"` | Make all four `Loc` values even, including width/height or negative trims       |
| Mask preview is black        | Confirm that `Loc` overlaps the white logo and that logo pixels are exactly 255 |

### Coordinate Semantics

For a `1920x1080` clip, these two regions are equivalent:

```python
Crop(1500, 880, 320, 180)
Crop(1500, 880, -100, -20)
```

The negative values mean “remove 100 pixels from the right” and “remove 20 pixels from the bottom.” They do not mean width `100` and height `20`.

Define the region once and reuse it:

```python
sourcePath = "path/to/source-video.mp4"
maskPath = "path/to/logo-mask.bmp"
LWLibAvVideoSource(sourcePath)

regionX = 1500
regionY = 880
regionW = 320
regionH = 180
regionLoc = String(regionX) + "," + String(regionY) + "," + String(regionW) + "," + String(regionH)

InpaintDelogo(Loc=regionLoc, mask=maskPath, Mode="Deblend", Analyze=1, AnalyzeTh=45, dPP=-5)
```

### File Mask Diagnostics

A file-based mask must have the same resolution as the full video frame. InpaintDelogo crops both the video and mask with `Loc`, then applies a strict threshold where only full-white pixels survive.

Check the exact mask region InpaintDelogo will use:

```python
maskPath = "path/to/logo-mask.bmp"
ImageSource(maskPath, 0, 0).Greyscale.ConvertToRGB32.Crop(regionX, regionY, regionW, regionH).Levels(254, 1, 255, 0, 255)
```

- If this is black but the unthresholded crop contains the logo, the white pixels are below 255.
- If both crops are black, the mask and `Loc` do not overlap or their resolutions differ.
- If the thresholded crop shows the white logo, the base mask is valid and the next step is analysis/deblend tuning.
- Changing `Analyze` does not repair an empty base mask; Deblend analysis still requires the mask.

### Quality Settings Examples

```python
# Best Quality (slowest)
InpaintDelogo(Loc=regionLoc, mask="mask.bmp", Mode="Both", Deep=5, Analyze=3, Interp=4, dPP=-5)

# Balanced Quality
InpaintDelogo(Loc=regionLoc, mask="mask.bmp", Mode="Deblend", Analyze=1, AnalyzeTh=45, Interp=2)

# Fast Preview
InpaintDelogo(Loc=regionLoc, mask="mask.bmp", Mode="Inpaint", Deep=1, Turbo=2)
```

## FFmpeg Export Commands

### Lossless Export

```bash
ffmpeg -i input.avs -c:v libx264 -preset ultrafast -qp 0 -pix_fmt yuv420p output.mp4
```

### High Quality Export

```bash
ffmpeg -i input.avs -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p output.mp4
```

### Quick Preview Export

```bash
ffmpeg -i input.avs -c:v libx264 -preset ultrafast -crf 23 -t 30 preview.mp4
```

### Full Render with Source Audio

Render video to a new file, then map audio from the untouched source:

```powershell
ffmpeg -i .\input.avs -i .\input.mp4 -map 0:v:0 -map 1:a? -c:v libx264 -preset slow -crf 18 -c:a copy .\output-delogo.mp4
```

Always render a short preview first and never reuse the source path as the output path.

### Specific Codec Options

```bash
# H.264 High Quality
ffmpeg -i input.avs -c:v libx264 -preset veryslow -crf 16 -pix_fmt yuv420p output.mp4

# H.265 (smaller files)
ffmpeg -i input.avs -c:v libx265 -preset medium -crf 20 -pix_fmt yuv420p output.mp4

# Lossless with custom settings
ffmpeg -i input.avs -c:v libx264 -preset ultrafast -qp 0 -range pc -colorspace bt709 output.mp4
```

## Example Scripts

### Complete Example - Transparent Logo

```python
sourcePath = "path/to/source-video.mp4"
maskPath = "path/to/logo-mask.bmp"
LWLibAvVideoSource(sourcePath)
InpaintDelogo(Loc="1570,904,-28,-58", mask=maskPath, Mode="Deblend", Analyze=1, AnalyzeTh=45, dPP=-5)
```

### Complete Example - Opaque Logo

```python
sourcePath = "path/to/source-video.mp4"
maskPath = "path/to/logo-mask.bmp"
LWLibAvVideoSource(sourcePath)
InpaintDelogo(Loc="1540,870,-70,-30", mask=maskPath, Mode="Inpaint", Inflate=2, oPP=6)
```

### Complete Example - Complex Logo

```python
sourcePath = "path/to/source-video.mp4"
maskPath = "path/to/logo-mask.bmp"
LWLibAvVideoSource(sourcePath)
InpaintDelogo(Loc="1590,910,-10,0", mask=maskPath, Mode="Both", Deep=5, Analyze=3, Interp=3, dPP=-5, oPP=6)
```

## Downloads & Dependencies

| Component                         | Type    | Download Link                                                          | Description                                                                          |
| --------------------------------- | ------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| **AviSynth+**                     | Runtime | [GitHub](https://github.com/AviSynth/AviSynthPlus)                     | Required runtime environment                                                         |
| **AvsPmod GPo**                   | Editor  | [GitHub](https://github.com/gispos/AvsPmod)                            | Maintained AviSynth script editor build                                              |
| **AvsInpaint**                    | Plugin  | [GitHub](https://github.com/pinterf/AvsInpaint)                        | Core inpainting plugin (v1.3+)                                                       |
| **DoomDelogo**                    | Plugin  | [GitHub](https://github.com/Purfview/DoomDelogo)                       | Faster logo removal alternative                                                      |
| **FFT3DFilter**                   | Plugin  | [AviSynth Wiki](http://avisynth.nl/index.php/FFT3DFilter)              | Denoising filter                                                                     |
| **ffms2**                         | Plugin  | [GitHub](https://github.com/FFMS/ffms2)                                | Alternative video source                                                             |
| **FrameSel**                      | Plugin  | [AviSynth Wiki](https://avisynth.nl/index.php/FrameSel)                | Required by InpaintDelogo and included in the toolchain release                      |
| **GRunT**                         | Plugin  | [GitHub](https://github.com/pinterf/GRunT)                             | Runtime functions                                                                    |
| **InpaintDelogo**                 | Plugin  | [GitHub](https://github.com/Purfview/InpaintDelogo)                    | Advanced logo removal                                                                |
| **L-SMASH-Works**                 | Plugin  | [GitHub](https://github.com/HomeOfAviSynthPlusEvolution/L-SMASH-Works) | Video source (LWLibAvVideoSource)                                                    |
| **MaskTools2**                    | Plugin  | [GitHub](https://github.com/pinterf/masktools)                         | Mask operations                                                                      |
| **RT_Stats**                      | Plugin  | [AviSynth Wiki](https://avisynth.nl/index.php/RT_Stats)                | Required by InpaintDelogo and included in the toolchain release                      |
| **FFTW single-precision runtime** | Runtime | [Official Windows binaries](https://fftw.org/install/windows.html)     | Loaded dynamically by Neo FFT3D; the exact DLL and source archive are SHA-256 pinned |

### Installation Notes

- Install **AviSynth+** first, then **AvsPmod** for editing
- Place plugin DLLs directly in `Plugins` under the configured toolchain root
- **Always use 64-bit versions of plugins** - extract x64 DLLs if multiple versions are provided
- If Windows reports missing Microsoft Visual C++ runtime DLLs, install the [latest supported official x64 Redistributable](https://aka.ms/vc14/vc_redist.x64.exe)
- For AviSynth v2.6: Rename .avsi files to .avs and load manually with `GImport()`

## Reference Links

- [InpaintDelogo GitHub](https://github.com/Purfview/InpaintDelogo) - Advanced delogo plugin
- [DoomDelogo GitHub](https://github.com/Purfview/DoomDelogo) - Faster alternative
- [InpaintDelogo Forum Thread](https://forum.doom9.org/showthread.php?t=176860) - Main discussion & support
- [AviSynth+ Download](https://github.com/AviSynth/AviSynthPlus) - Required runtime
- [AvsInpaint Plugin](https://github.com/pinterf/AvsInpaint) - Required dependency

## Maintenance Notes

This repository is maintained as a reproducible handoff and release bundle, not as a general open contribution workflow.

When changing generic testing guidance, document the background types, parameters, and artifacts that support the recommendation without adding a per-video preset. Keep local source media, masks, rendered videos, FFMS indexes, InpaintDelogo analysis caches, temporary images, logs, editor backups, credentials, and machine-specific absolute paths out of Git.

Run the toolchain bootstrap in a clean directory, run verification, review exact-frame comparisons, confirm no black-bar restoration is selected for colored scenes, and render a short preview before opening a draft pull request. Do not force-push or merge the review branch automatically.
