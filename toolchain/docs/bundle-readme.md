# AviSynth Delogo x64

This archive is generated from the pinned sources and SHA-256 values in `toolchain.lock.json`.

From PowerShell, dot-source the activation script before running AviSynth-aware tools:

```powershell
. .\activate.ps1
pwsh -File .\verify-toolchain.ps1 -ToolchainRoot $env:AVISYNTH_DELOGO_ROOT
.\Start-AvsPmod.cmd
```

Activation adds the portable AviSynth+ runtime, AvsPmod, FFmpeg, and FFprobe to the current process `PATH`. Root-level `ffmpeg.exe` and `ffprobe.exe` intentionally sit beside `AviSynth.dll`, allowing bundled FFmpeg to load AviSynth without a system-wide installation or a duplicate DLL. Verification checks all three hashes and renders a one-frame `BlankClip()` on Windows.

The runtime layout is intentionally flat: AvsPmod is under `AvsPmod`, and x64 AviSynth+ plugins are directly under `Plugins`. There is no `Tools` or nested `plugins64+` directory.

Use `Start-AvsPmod.cmd`, including when launching from Explorer. It starts `AvsPmod\AvsPmod.exe` with relative portable settings and configures the current user's AviSynth+ `PluginDir+` registry value for `Plugins`. Launching `AvsPmod.exe` directly bypasses that setup.

Both `InpaintDelogo()` and the faster, lower-quality `DoomDelogo()` alternative are included directly under `Plugins`.

If Windows reports missing Microsoft Visual C++ runtime DLLs, install the [latest supported official x64 Redistributable](https://aka.ms/vc14/vc_redist.x64.exe).

Set source and mask paths inside each `.avs` script. The archive contains no source media, masks, rendered output, credentials, or machine-specific paths.
