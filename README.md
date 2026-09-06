# avisynth-delogo

A portable Windows x64 toolchain for removing logos and watermarks with AviSynth+ and InpaintDelogo. The repository contains the pinned inputs, bundle files, build scripts, and a repeatable process for comparing and validating each video's result. DoomDelogo is included as a last-resort rectangular concealment fallback.

## Quick start

1. Download the Windows x64 ZIP and its `.sha256` file from the [latest release](https://github.com/lordsilver/avisynth-delogo/releases/latest).
2. Compare `Get-FileHash .\avisynth-delogo-x64-<version>.zip -Algorithm SHA256` with the checksum, then extract the ZIP.
3. Open PowerShell 7 in the extracted folder and activate and verify the toolchain:

```powershell
. .\activate.ps1
pwsh -NoProfile -File .\verify-toolchain.ps1 -ToolchainRoot $env:AVISYNTH_DELOGO_ROOT
.\Start-AvsPmod.cmd
```

The launcher configures the current user's AviSynth+ plugin directory and starts the bundled AvsPmod. FFmpeg and FFprobe sit beside `AviSynth.dll` so Windows can load the portable runtime. Release consumers do not need mise.

Follow the [getting started guide](docs/getting-started.md), compare configurations on the same exact frames and motion intervals using the [testing workflow](docs/testing-workflow.md), then render to a new output file and validate it:

```powershell
pwsh -NoProfile -File .\validate-render.ps1 -SourcePath .\input.mp4 -OutputPath .\output-delogo.mp4 -ToolchainRoot $env:AVISYNTH_DELOGO_ROOT
```

Keep the source unchanged. Every video needs its own mask, region, and comparison; representative crops from the final output still need visual inspection.

## Documentation

| Guide                                                   | Contents                                                                 |
| ------------------------------------------------------- | ------------------------------------------------------------------------ |
| [Getting started](docs/getting-started.md)              | Source setup, masks, candidate configurations, and FFmpeg exports        |
| [Testing workflow](docs/testing-workflow.md)            | Exact frames, comparison matrix, temporal previews, and final validation |
| [Filter reference](docs/reference.md)                   | Parameters, troubleshooting, examples, and upstream dependencies         |
| [Maintenance](docs/maintaining.md)                      | Repository layout, tasks, reproducible builds, and release checks        |
| [Third-party notices](toolchain/THIRD-PARTY-NOTICES.md) | Redistribution notices and provenance                                    |

## Repository layout

```text
.github/workflows/      Build and release CI; scheduled upstream checks
docs/                   User guides and maintenance instructions
scripts/                Repository validation, source collection, and builds
tests/                  Generated-media and release-archive regression tests
toolchain/
  bundle/               Portable files laid out exactly as they ship
  source-bundle/        Source archive README
  manifests/            Pinned files, hashes, and upstream catalog
  THIRD-PARTY-NOTICES.md
skills/                 Distributable agent guidance for video work
mise.toml               Pinned development tools and task entry points
```

## Development

Install the tools declared in [mise.toml](mise.toml), then run the local checks:

```powershell
mise install
mise run check
```

`check` runs formatting, workflow and manifest checks, PowerShell syntax checks, local documentation-link checks, secret scanning, and generated-media regression tests. [Release validation](docs/maintaining.md#build-and-verify-release-archives) additionally checks both built ZIPs and executes the bundled AviSynth/FFmpeg runtime on Windows.

Build outputs live in ignored `dist/`; source caches and reports live in ignored `.scratch/`. Source media, masks, and rendered videos stay outside version control. See [maintenance](docs/maintaining.md) for the complete source collection and build sequence.
