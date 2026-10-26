# Project instructions for AI agents

## Paths and example data

This repository is public. Nothing in it (code, scripts, docs, the skill, tests, CI output, commit messages, tags and release notes) may point back to the machine it was worked on, the person working on it, or the videos they work on:

- Paths are relative to the repository or the bundle (`toolchain\bundle\`, `.\input.mp4`), or built from `$PSScriptRoot` and `$env:AVISYNTH_DELOGO_ROOT`. Never an absolute path from this machine: no user profile, home folder, WSL mount or local drive folder, and no user name, computer name or folder name taken from one.
- Example media uses generic names such as `source-video.mp4`, `input.mp4`, `input.avs`, `logo-mask.bmp` and `output-delogo.mp4`. Nothing describes a real video: no titles, channels, logos, timestamps, frame numbers, crops or settings copied from one.
- Source media, masks, previews, renders, indexes and logs stay out of Git: keep each video's work outside the checkout or in the ignored `.scratch/`.

Testing on real videos locally is fine; describe such runs generically ("a 1080p clip with a corner logo").

`mise run validate` rejects generic personal paths. Names specific to this machine go in the ignored `.scratch/prohibited.txt`, one regular expression per line, never in the script. Check every commit, tag message and release note before it leaves the machine.
