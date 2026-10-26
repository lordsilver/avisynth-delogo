# Filter reference

[Home](../README.md) · [Getting started](getting-started.md) · [Testing workflow](testing-workflow.md)

Parameters, coordinate and mask diagnostics, example scripts, and upstream projects for the pinned toolchain. The [source catalog](../toolchain/manifests/sources.yaml) records the dated upstream comparison; it is not a live latest-version report.

## Command Reference

| Function               | Purpose                          | Example                          |
| ---------------------- | -------------------------------- | -------------------------------- |
| `LWLibAvVideoSource()` | Import video file                | `LWLibAvVideoSource(sourcePath)` |
| `InpaintDelogo()`      | Advanced logo removal            | See parameters below             |
| `DoomDelogo()`         | Rectangular concealment fallback | `DoomDelogo(50, 50, -100, -100)` |
| `Crop()`               | Preview logo area                | `Crop(50, 50, -100, -100)`       |

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

| Parameter | Default | Range   | Description                                                         |
| --------- | ------- | ------- | ------------------------------------------------------------------- |
| `Inflate` | 1       | 0-2     | Filter-time mask expansion; test separately from a pre-dilated mask |
| `Deep`    | 3       | 1-5     | Multi-pass processing                                               |
| `Interp`  | 2       | 0-4     | Interpolation for artifacts                                         |
| `dPP`     | -3      | -8 to 8 | Blur or denoise applied to the deblended area                       |
| `oPP`     | -5      | -8 to 8 | Blur or denoise applied to the inpainted area                       |
| `Turbo`   | 0       | -2 to 3 | Speed versus quality preset, including UHD `-1`                     |

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

These are starting points, not reusable presets. First build the mask from a black, preferably pure-black for a bright opaque watermark, or plain-background source frame when possible and verify that it selects only the watermark. A temporary crop can help isolate it, but the final mask must be restored to full-frame dimensions. Because black can conceal a dark outline or drop shadow, also verify the mask on a plain colored frame and add only the smallest tested dilation that removes any fringe. Record saved-mask dilation and the filter's `Inflate` value separately: a mask saved after two-pixel dilation with `Inflate=0` is not automatically equivalent to an undilated mask with `Inflate=2`. Then test a fixed matrix on the same 3–10 exact frames distributed across the full timeline, compare the best candidates over the same motion interval, and tune the region, mask, analysis, and post-processing for that video before rendering.

### Analysis Methods

- **`Analyze=1`**: Smart automatic frame selection using pixels around the base-mask edges; intended for Deblend/Both and unavailable while `Automask=1`
- **`Analyze=2`**: Smart automatic frame selection using pixels around the `Loc` edges; recommended for `Automask=1`
- **`Analyze=3`**: Analyze every frame without frame selection
- **`Analyze=-1` and `Analyze=-2`**: Deprecated deblend methods corresponding roughly to the positive automatic methods
- **`Analyze=-3`**: Deprecated manual analysis using `FrB` and `FrW`
- **`Analyze=-4`**: Deprecated manual white-logo method using `FrB`; acceptable for some automasks but generally not recommended for delogo

Only analyze frames where the logo is present and not animated. Do not use `Prefetch()` during analysis.

### Candidate Settings

```python
# Opaque Inpaint baseline; exposes post-processing softness
Mode="Inpaint", Turbo=0, Inflate=0, oPP=0

# Faster preview of the same opaque-logo mode
Mode="Inpaint", Turbo=2, Inflate=0, oPP=0

# Transparent-logo candidate only
Mode="Deblend", Analyze=1, AnalyzeTh=45
```

These are comparison starting points, not a quality ladder. `Analyze` is ignored in pure Inpaint mode, while Deblend and Both require a genuinely transparent or mixed watermark.

## Troubleshooting

### Common Issues and Solutions

| Problem                      | Solution                                                                                                 |
| ---------------------------- | -------------------------------------------------------------------------------------------------------- |
| Logo remnants visible        | Recheck threshold and edge coverage; compare minimal saved-mask dilation and filter `Inflate` separately |
| Opaque result looks blurry   | Compare `oPP=0` and relevant `Turbo` values before adding post-processing                                |
| Transparent-logo residue     | After confirming transparency, compare Deblend or Both on the shared frame set                           |
| Mask too thick/thin          | Regenerate or edit a manual mask; use `aMix` only while generating an automask                           |
| Poor mask generation         | Prefer extraction from a clean black/plain frame; use `Automask=1, Analyze=2` only as a fallback         |
| Processing too slow          | Use `Turbo=1-3` for previews, then verify the final-quality candidate separately                         |
| `Use even numbers for "Loc"` | Make all four `Loc` values even, including width/height or negative trims                                |
| Mask preview is black        | Confirm that `Loc` overlaps the white logo and that logo pixels are exactly 255                          |

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

### Mode-Specific Candidate Examples

```python
# Opaque-logo baseline with a validated mask
InpaintDelogo(Loc=regionLoc, mask="mask.bmp", Mode="Inpaint", Turbo=0, Inflate=0, oPP=0)

# Transparent-logo candidate
InpaintDelogo(Loc=regionLoc, mask="mask.bmp", Mode="Deblend", Analyze=1, AnalyzeTh=45, Interp=2)

# Mixed-transparency candidate only after confirming that classification
InpaintDelogo(Loc=regionLoc, mask="mask.bmp", Mode="Both", Analyze=1, Interp=2, dPP=-3, oPP=0)
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
InpaintDelogo(Loc="1540,870,-70,-30", mask=maskPath, Mode="Inpaint", Turbo=0, Inflate=0, oPP=0)
```

### Complete Example - Confirmed Mixed-Transparency Logo

```python
sourcePath = "path/to/source-video.mp4"
maskPath = "path/to/logo-mask.bmp"
LWLibAvVideoSource(sourcePath)
InpaintDelogo(Loc="1590,910,-10,0", mask=maskPath, Mode="Both", Analyze=1, Interp=2, dPP=-3, oPP=0)
```

## Downloads & Dependencies

| Component                         | Type    | Download Link                                                          | Description                                                                          |
| --------------------------------- | ------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| **AviSynth+**                     | Runtime | [GitHub](https://github.com/AviSynth/AviSynthPlus)                     | Required runtime environment                                                         |
| **AvsPmod GPo**                   | Editor  | [GitHub](https://github.com/gispos/AvsPmod)                            | Maintained AviSynth script editor build                                              |
| **AvsInpaint**                    | Plugin  | [GitHub](https://github.com/pinterf/AvsInpaint)                        | Core inpainting plugin (v1.3+)                                                       |
| **DoomDelogo**                    | Plugin  | [GitHub](https://github.com/Purfview/DoomDelogo)                       | Last-resort rectangular concealment fallback                                         |
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

- Prefer the verified portable release described in the [quick start](../README.md#quick-start); the upstream links above are for component maintenance and manual setups
- Place plugin DLLs directly in `Plugins` under the configured toolchain root
- **Always use 64-bit versions of plugins** - extract x64 DLLs if multiple versions are provided
- If Windows reports missing Microsoft Visual C++ runtime DLLs, install the [latest supported official x64 Redistributable](https://aka.ms/vc14/vc_redist.x64.exe)
- For AviSynth v2.6: Rename .avsi files to .avs and load manually with `GImport()`

## Reference Links

- [InpaintDelogo GitHub](https://github.com/Purfview/InpaintDelogo) - Advanced delogo plugin
- [DoomDelogo GitHub](https://github.com/Purfview/DoomDelogo) - Rectangular concealment fallback
- [InpaintDelogo Forum Thread](https://forum.doom9.org/showthread.php?t=176860) - Main discussion & support
- [AviSynth+ Download](https://github.com/AviSynth/AviSynthPlus) - Required runtime
- [AvsInpaint Plugin](https://github.com/pinterf/AvsInpaint) - Required dependency
