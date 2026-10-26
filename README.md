# avisynth-delogo

A portable Windows toolkit for removing burned-in logos and watermarks from videos. It bundles AviSynth+ with the InpaintDelogo filter, the AvsPmod editor and FFmpeg, ready to run from one folder, together with guides for building a mask, comparing settings and checking the final render.

## What's in the download

AviSynth+, InpaintDelogo and the plugins it needs, AvsPmod, FFmpeg and FFprobe, all pinned to exact versions and checked against SHA-256 hashes. DoomDelogo is included as a last-resort fallback that conceals a rectangle instead of reconstructing it. `toolchain.lock.json` in the download lists every component, its version and where it comes from.

## Requirements

- Windows 10 or 11, x64.
- [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows) (`winget install Microsoft.PowerShell`).
- The [Microsoft Visual C++ x64 runtime](https://aka.ms/vc14/vc_redist.x64.exe), if Windows reports missing DLLs.

## Quick start

1. Download `avisynth-delogo-x64-<version>.zip` and its `.sha256` file from the [latest release](https://github.com/lordsilver/avisynth-delogo/releases/latest).
2. In PowerShell 7, check the download and unblock it before extracting, so Windows does not block the scripts inside:

   ```powershell
   (Get-FileHash .\avisynth-delogo-x64-<version>.zip -Algorithm SHA256).Hash   # compare with the .sha256 file
   Unblock-File .\avisynth-delogo-x64-<version>.zip
   Expand-Archive .\avisynth-delogo-x64-<version>.zip -DestinationPath .
   ```

3. Activate the toolkit, check it, and open AvsPmod:

   ```powershell
   cd .\avisynth-delogo-x64-<version>
   . .\activate.ps1
   pwsh -NoProfile -File .\verify-toolchain.ps1
   .\Start-AvsPmod.cmd
   ```

### What activation changes

Activation puts the toolkit's AviSynth+, FFmpeg and AvsPmod first on the `PATH` of the current PowerShell session and sets `AVISYNTH_DELOGO_ROOT`. It also points AviSynth+ at the toolkit's plugins by setting the `PluginDir+` value under `HKCU\Software\AviSynth`, which stays after the session ends and also applies to an AviSynth+ installed separately. To undo it:

```powershell
Remove-ItemProperty HKCU:\Software\AviSynth -Name PluginDir+
```

## Removing a logo

Keep each video in its own folder, and never overwrite the source.

1. Find a frame where the logo sits on a plain background and build a mask from it.
2. Locate the logo region and try a few InpaintDelogo settings.
3. Compare them on the same frames and the same short motion clip.
4. Render the chosen settings to a new file.
5. Check the render, then look at a few crops yourself:

   ```powershell
   & "$env:AVISYNTH_DELOGO_ROOT\validate-render.ps1" -SourcePath .\input.mp4 -OutputPath .\output-delogo.mp4
   ```

The validator counts and decodes every frame, compares the video and container metadata, and confirms that copied audio is unchanged.

## Documentation

| Guide                                        | Contents                                                                 |
| -------------------------------------------- | ------------------------------------------------------------------------ |
| [Getting started](docs/getting-started.md)   | Source setup, masks, candidate configurations, and FFmpeg exports        |
| [Testing workflow](docs/testing-workflow.md) | Exact frames, comparison matrix, temporal previews, and final validation |
| [Filter reference](docs/reference.md)        | Parameters, troubleshooting, examples, and upstream dependencies         |

To build the bundle yourself, see [maintenance](docs/maintaining.md).
