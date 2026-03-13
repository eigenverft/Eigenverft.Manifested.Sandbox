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
- Add low-overhead first-bootstrap-request proxy handling for the published GitHub `iwr ... | iex` entrypoints by explicitly using the discovered system proxy with default credentials when the URL is not bypassed, and review `README.md` plus both `iwr` bootstrapper scripts so home/private, corporate, and Windows Sandbox flows stay aligned.
  Still open: `README.md` still publishes plain `iwr ... | iex` entrypoints, and both `iwr` bootstrapper scripts only set `DefaultWebProxy` after the bootstrap script has already been downloaded from `raw.githubusercontent.com`, which is too late to fix the initial fetch.
  Preserve this sample in the item details because it captures the intended first-request behavior and the environments the change needs to keep working in:

  ```powershell
  # Explicitly use the discovered system proxy with default credentials for the first bootstrap
  # request. This avoids initial Invoke-WebRequest failures in corporate environments,
  # especially inside Windows Sandbox, where proxy auth is not always applied automatically.
  # Typically works on home/private clients and sandboxes, normal corporate clients, and
  # corporate sandboxes when the proxy is discoverable and accepts DefaultCredentials.
  $u='https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Sandbox/refs/heads/main/iwr/bootstrapper.ps1';try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12}catch{};$p=[System.Net.WebRequest]::GetSystemWebProxy();if(-not $p.IsBypassed($u)){iwr $u -Proxy ($p.GetProxy($u).AbsoluteUri) -ProxyUseDefaultCredentials -UseBasicParsing|iex}else{iwr $u -UseBasicParsing|iex}
  ```
#### Release
- Create the first proper GitHub Release so the project has a stable public release target for sharing and discovery.
  Still open as of 2026-03-13: the public GitHub releases page still shows no releases, so tags alone are not enough to close this item.
- Decide whether the public versioning signal should stay on `0.x` while the project is still evolving or move to `1.0` when it is solid enough for broader visibility.
  Still open as of 2026-03-13: the public tags still signal `0.x`, but the todo does not yet record an explicit decision to stay on `0.x` or define the condition for moving to `1.0`.

### [P3] Normal
#### Tooling
- Add a managed .NET bootstrap path so the sandbox has the baseline local tooling needed for Codex-assisted build and repo tasks.
  Still open: the current repo surface and `README.md` do not yet expose a managed .NET bootstrap command or documented .NET bootstrap path.
- Add a managed Python bootstrap and cache flow so the sandbox has a common scripting baseline for Codex-assisted build and repo tasks.
  Still open: the current repo surface and `README.md` do not yet expose a managed Python bootstrap or cache flow.
#### Visual polish
- Add one screenshot or short GIF that shows the sandbox result or expected terminal output for first-time visitors.
  Still open: the current `README.md` does not yet include a screenshot or GIF reference.

### [P4] Low

### [P5] Backlog / Nice-to-have

### [P6] Pixelperfect / optional polish

## Review / Questions
- Decide which .NET version should be pinned for the Codex-oriented sandbox baseline.
- Decide which Python version should be pinned for the Codex-oriented sandbox baseline.

## Closed
- [P2] Trust - 2026-03-13: Enabled GitHub private vulnerability reporting and updated `SECURITY.md` to use it as the primary private disclosure path.
- [P1] Trust - 2026-03-13: Added a PSGallery link near the install section and a bootstrap trust note that explains what the bootstrap downloads, where it installs, and whether admin rights are required.
- [P1] Trust - 2026-03-13: Added `SECURITY.md` with public vulnerability reporting guidance and a private email fallback.
- [P1] Trust - 2026-03-13: Added top-of-README trust badges for PowerShell support, PSGallery version, PSGallery downloads, build status, and license.
- [P3] Tooling - 2026-03-13: Added managed MinGit bootstrap, cache, and extraction flow.
- [P3] Tooling - 2026-03-13: Added managed PowerShell 7 bootstrap and cache flow.
