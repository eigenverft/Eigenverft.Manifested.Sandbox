# PROJECT TODO

## Priority Legend
- [P0] Blocker
- [P1] Critical
- [P2] High
- [P3] Normal
- [P4] Low
- [P5] Backlog / Nice-to-have
- [P6] Pixelperfect / optional polish

## Open

### [P0] Blocker

### [P1] Critical
#### Trust

### [P2] High
#### Bootstrap
#### Release

### [P3] Normal
#### Tooling
- Add a managed .NET bootstrap path so the sandbox has the baseline local tooling needed for Codex-assisted build and repo tasks.
  Still open: the current repo surface and `README.md` do not yet expose a managed .NET bootstrap command or documented .NET bootstrap path.
- Add a managed Python bootstrap and cache flow so the sandbox has a common scripting baseline for Codex-assisted build and repo tasks.
  Still open: the current repo surface and `README.md` do not yet expose a managed Python bootstrap or cache flow.
#### Visual polish

### [P4] Low

### [P5] Backlog / Nice-to-have

### [P6] Pixelperfect / optional polish

## Review / Questions
- Decide which .NET version should be pinned for the Codex-oriented sandbox baseline.
- Decide which Python version should be pinned for the Codex-oriented sandbox baseline.

## Closed
- [P2] Bootstrap - 2026-03-17: Added low-overhead first-bootstrap-request proxy handling for the published GitHub `iwr ... | iex` entrypoints by explicitly using the discovered system proxy with default credentials when the URL is not bypassed. Updated `README.md` and both `iwr` bootstrapper script comments.
- [P3] Visual polish - 2026-03-13: Added a README screenshot that shows the Windows Sandbox result and expected terminal output for first-time visitors.
- [P2] Release - 2026-03-13: Created the first proper GitHub Release so the project now has a stable public release target for sharing and discovery.
- [P2] Release - 2026-03-13: Moved the public versioning signal from `0.x` to `1.x`, including published tag and manifest version `1.20261.31334`.
- [P2] Trust - 2026-03-13: Enabled GitHub private vulnerability reporting and updated `SECURITY.md` to use it as the primary private disclosure path.
- [P1] Trust - 2026-03-13: Added a PSGallery link near the install section and a bootstrap trust note that explains what the bootstrap downloads, where it installs, and whether admin rights are required.
- [P1] Trust - 2026-03-13: Added `SECURITY.md` with public vulnerability reporting guidance and a private email fallback.
- [P1] Trust - 2026-03-13: Added top-of-README trust badges for PowerShell support, PSGallery version, PSGallery downloads, build status, and license.
- [P3] Tooling - 2026-03-13: Added managed MinGit bootstrap, cache, and extraction flow.
- [P3] Tooling - 2026-03-13: Added managed PowerShell 7 bootstrap and cache flow.
