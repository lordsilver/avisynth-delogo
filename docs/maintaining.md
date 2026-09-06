# Maintenance

[Home](../README.md) · [Getting started](getting-started.md) · [Testing workflow](testing-workflow.md)

This repository is maintained as a reproducible handoff and release bundle. Keep the PowerShell build and verification commands usable directly as well as through mise.

## Where files belong

| Path                                     | Responsibility                                                                 |
| ---------------------------------------- | ------------------------------------------------------------------------------ |
| `docs/`                                  | Guides for video work and repository maintenance                               |
| `scripts/`                               | Maintainer commands; these are not copied into the portable release            |
| `tests/`                                 | Regression tests with generated fixtures and checks of the actual release ZIPs |
| `toolchain/bundle/`                      | First-party portable files; paths mirror the extracted Windows bundle          |
| `toolchain/source-bundle/`               | Files copied into the aggregate source archive                                 |
| `toolchain/manifests/`                   | The installed-file lock and dated upstream source catalog                      |
| `toolchain/THIRD-PARTY-NOTICES.md`       | Shared notice copied into both archives                                        |
| `skills/`                                | Distributable agent guidance for processing videos                             |
| `.github/workflows/toolchain.yml`        | Validation, Windows builds, archive tests, and tagged releases                 |
| `.github/workflows/upstream-updates.yml` | Monthly or manual upstream checks and update issue maintenance                 |
| `dist/`                                  | Generated ZIPs and checksums; ignored by Git                                   |
| `.scratch/`                              | Generated source cache, collected assets, and update reports; ignored by Git   |

The builder overlays `toolchain/bundle/` on the verified upstream files. For example, `toolchain/bundle/AvsPmod/options.dat` becomes `AvsPmod/options.dat`, and `toolchain/bundle/validate-render.ps1` becomes the standalone `validate-render.ps1`. Add portable files at their intended destination within this directory. Build and test code belongs outside it.

The Windows bundle keeps `AviSynth.dll`, `ffmpeg.exe`, and `ffprobe.exe` together at its root. AvsPmod lives directly under `AvsPmod/`, and x64 plugins live directly under `Plugins/`. Windows verification renders a one-frame `BlankClip()` with the bundled FFmpeg to check runtime loading. FFplay, FFmpeg HTML documentation, and FFmpeg presets are not included.

## Local checks

The exact tool versions in [mise.toml](../mise.toml) keep formatter, validator, archive, and media-test behavior consistent. Update pins deliberately after reviewing compatibility. The [lockfile](../toolchain/manifests/toolchain.lock.json) governs shipped Windows files independently of the development tools.

```powershell
mise install
mise run check
```

`check` groups independent validation and test tasks through [mise task dependencies](https://mise.jdx.dev/tasks/). Both can run on Linux or Windows. Native AviSynth loading and execution of the bundled Windows FFmpeg require Windows.

| Command                                                                 | Purpose                                                                                                                       |
| ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `mise run check`                                                        | Repository validation and generated-media tests                                                                               |
| `mise run validate`                                                     | Formatting, all workflows, manifests, PowerShell syntax, local documentation links, secrets, and machine-specific path checks |
| `mise run format`                                                       | Format Markdown, JSON, YAML, and TOML while preserving prose wrapping                                                         |
| `mise run format:check`                                                 | Check formatting without edits                                                                                                |
| `mise run test`                                                         | Run local regression tests                                                                                                    |
| `mise run test:validate-render`                                         | Generate copied-audio and transcoded-audio media and test the render validator                                                |
| `mise run collect:sources`                                              | Verify pinned inputs into `.scratch/source-cache/` and copy source assets to `.scratch/source-assets/`                        |
| `mise run bootstrap:toolchain -- -ToolchainRoot <directory>`            | Install locked runtime files only; this does not assemble the full portable bundle                                            |
| `mise run verify:toolchain -- -ToolchainRoot <directory>`               | Verify a complete extracted bundle, including AvsPmod and its launcher                                                        |
| `mise run build:toolchain`                                              | Assemble and verify the portable Windows ZIP in `dist/`                                                                       |
| `mise run build:sources`                                                | Package collected upstream inputs into a sources ZIP in `dist/`                                                               |
| `mise run test:release -- -ToolchainArchive <zip> -SourceArchive <zip>` | Check both ZIPs, their checksums and contents, and the bundled runtime on Windows                                             |
| `mise run check:updates`                                                | Compare selected upstream versions and write `.scratch/update-report.json`                                                    |

Append PowerShell parameters after `--`. Use `mise tasks` to discover the current task list. Formatters and repository source checks exclude ignored media and generated directories. PowerShell parsing is part of validation; executable regression tests also run because syntax checks alone cannot detect runtime failures.

## Build and verify release archives

Run this from the checkout root. Source collection verifies each download by SHA-256 and deduplicates the cache used by the binary build:

```powershell
$releaseVersion = Get-Date -Format "yyyy.MM.dd"
mise run collect:sources
mise run build:toolchain -- -OfflineCacheRoot .\.scratch\source-cache -Version $releaseVersion
mise run build:sources -- -Version $releaseVersion
mise run test:release -- -ToolchainArchive ".\dist\avisynth-delogo-x64-$releaseVersion.zip" -SourceArchive ".\dist\avisynth-delogo-sources-$releaseVersion.zip"
```

`collect:sources` also accepts `-OfflineCacheRoot` (or `AVISYNTH_DELOGO_OFFLINE_CACHE_ROOT`) for an existing cache. `-CacheDirectory`, `-OutputDirectory`, and the builders' output parameters can relocate generated files. The source builder defaults to `.scratch/source-assets/`; both archive builders default to `dist/` and a date-based version.

The source archive contains the unchanged upstream inputs, including the pinned InpaintDelogo and DoomDelogo `.avsi` files. Both archives carry `toolchain.lock.json`, `sources.yaml`, and `THIRD-PARTY-NOTICES.md`. The release tests compare these with the checkout, verify every source asset against the lock, and test the validator extracted from the binary ZIP on Windows. The generated-media suite covers copied audio, intentionally transcoded audio, chapters, and rejection of an unexpected audio change.

To run directly without mise, invoke the corresponding script with PowerShell 7. For example:

```powershell
pwsh -NoProfile -File .\scripts\build-release.ps1 -OfflineCacheRoot .\.scratch\source-cache -Version $releaseVersion
pwsh -NoProfile -File .\toolchain\bundle\verify-toolchain.ps1 -ToolchainRoot $toolchainRoot
```

Direct invocation still requires the external tools used by that command. `bootstrap-toolchain.ps1` installs the files in the lock; use `build:toolchain` for a complete portable release with AvsPmod, configuration, launchers, documentation, and manifests.

FrameSel and RT_Stats use preserved author archive URLs in the lock. If an upstream or Internet Archive download is unavailable, supply a verified offline cache; source collection does not automatically fall back to a GitHub source release. A matching aggregate source ZIP preserves these inputs, but its flat `assets/` directory must be mapped to each entry's `cache_path` before being used as an offline cache.

## CI and releases

The toolchain workflow runs on pull requests to `main`, pushes to `main`, `v*` tags, and manual dispatches. Linux runs the same `mise run check` command used locally. Windows collects sources once, builds both archives, verifies the extracted portable runtime, and exercises the bundled render validator. Non-tag builds upload both ZIPs and their checksums as the `avisynth-delogo-bundles` artifact.

A version tag such as `vYYYY.MM.DD` publishes the Windows bundle and a matching `sources-vYYYY.MM.DD` release. Inspect the actual release assets and checksums before treating publication as complete. Non-tag builds use a `ci-<run-number>` artifact version so branch names cannot become archive paths.

The separate upstream update workflow runs at 00:00 UTC on the first day of each month and supports manual dispatch. It reports upstream changes and creates or refreshes the update issue. Review compatibility and refresh both the source catalog and lock hashes before rebuilding; the dated catalog is not a claim that its versions are still the latest upstream releases.

## Working files and review

Keep local source media, masks, renders, FFMS indexes, InpaintDelogo analysis caches, images, logs, editor backups, credentials, and machine-specific paths out of Git. Use `.scratch/` for repository-local experiments or keep each video's work outside the checkout. Root-level `inputs/`, `masks/`, `previews/`, `comparisons/`, `analysis/`, `renders/`, and `outputs/` are also ignored for existing video workflows.

When changing testing guidance, record the background types, parameters, and artifacts behind the recommendation without committing a per-video preset. For runtime changes, verify a clean bundle and inspect exact-frame comparisons and a short preview using the [testing workflow](testing-workflow.md). Do not force-push or merge the review branch automatically.
