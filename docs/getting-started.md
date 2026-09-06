# Getting started

[Home](../README.md) · [Filter reference](reference.md) · [Testing workflow](testing-workflow.md)

Start with the verified [portable release](https://github.com/lordsilver/avisynth-delogo/releases/latest), activate it as described in the [README](../README.md#quick-start), and keep each video's source, scripts, masks, and renders in its own working directory. Commands below run from that video directory after activation. Commands with repository paths run from the checkout root.

The examples show candidate settings; compare the same exact frames and motion intervals using the [testing workflow](testing-workflow.md) before choosing a final configuration.

## Quick Start Guide

### Basic Workflow

1. **Inspect the source** and find a frame where the logo sits on black or another plain background
2. **Build and validate a full-frame mask** from that frame; use `Automask=1` only when no clean frame exists
3. **Locate the mask** with an even-valued `Loc` that includes enough usable picture around it
4. **Compare Inpaint configurations** on the same 3–10 exact frames spread across the video and the same short motion interval
5. **Render the accepted configuration** with `Automask=0`, then validate the complete output

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

# Last resort: DoomDelogo conceals the whole rectangle
DoomDelogo(regionX, regionY, regionW, regionH)
```

`Crop()` and `Loc` accept the same two forms: `left, top, width, height`, or `left, top, -rightTrim, -bottomTrim`. Prefer the positive width/height form because names such as `-w` and `-h` are misleading: negative values are edge trims, not the selected width and height.

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
- If edge coverage is uncertain, save separately named dilated mask revisions and compare them with `Inflate=0`
- Test filter-time `Inflate` separately with the saved mask held constant

### Step 5: Perform Logo Removal

```python
# Keep Crop commented out and process the full video.
# Automask=0 and Mode="Inpaint" are the defaults for a normal BMP mask.
InpaintDelogo(Loc=regionLoc, mask=maskPath)
```

In Inpaint mode, InpaintDelogo forces `Analyze=0`, so setting `Analyze=-4` has no effect. `aMix` is used only while `Automask=1`, so it also has no effect during this removal step.

### Step 6: Compare Candidate Options

```python
# Opaque-logo baseline
Mode="Inpaint", Turbo=0, Inflate=0, oPP=0

# Faster preview of the same mode
Mode="Inpaint", Turbo=2, Inflate=0, oPP=0

# Very transparent logos; analyze every eligible frame
Mode="Deblend", Analyze=3
```

Do not promote Deblend or Both as a quality upgrade for an opaque watermark. Change one decision at a time and compare every candidate on the same reference frames.

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
ffmpeg -f avisynth -i .\input.avs -i .\input.mp4 -map 0:v:0 -map 1:a? -map_metadata 1 -map_chapters 1 -c:v libx264 -preset slow -crf 18 -c:a copy -movflags +faststart .\output-delogo.mp4
```

Always render a short preview first and never reuse the source path as the output path.

Validate the complete render from the repository checkout:

```powershell
pwsh -File .\toolchain\bundle\validate-render.ps1 -SourcePath .\input.mp4 -OutputPath .\output-delogo.mp4 -ToolchainRoot $toolchainRoot
```

This checks every frame, fully decodes the output, compares relevant video and container metadata, and verifies each stream-copied compressed audio payload by SHA-256. Representative output crops still require visual inspection.

### Specific Codec Options

```bash
# H.264 High Quality
ffmpeg -i input.avs -c:v libx264 -preset veryslow -crf 16 -pix_fmt yuv420p output.mp4

# H.265 (smaller files)
ffmpeg -i input.avs -c:v libx265 -preset medium -crf 20 -pix_fmt yuv420p output.mp4

# Lossless with custom settings
ffmpeg -i input.avs -c:v libx264 -preset ultrafast -qp 0 -range pc -colorspace bt709 output.mp4
```
