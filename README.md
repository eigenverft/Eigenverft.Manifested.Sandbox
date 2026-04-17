# Eigenverft.Manifested.Sandbox

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/Eigenverft.Manifested.Sandbox?label=PSGallery&logo=powershell)](https://www.powershellgallery.com/packages/Eigenverft.Manifested.Sandbox) [![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/Eigenverft.Manifested.Sandbox?label=Downloads&logo=powershell)](https://www.powershellgallery.com/packages/Eigenverft.Manifested.Sandbox) [![PowerShell Support](https://img.shields.io/badge/PowerShell-5.1%2B%20Desktop%2FCore-5391FE?logo=powershell&logoColor=white)](src/prj/Eigenverft.Manifested.Sandbox/Eigenverft.Manifested.Sandbox.psd1) [![Build Status](https://img.shields.io/github/actions/workflow/status/eigenverft/Eigenverft.Manifested.Sandbox/cicd.yml?branch=main&label=build)](https://github.com/eigenverft/Eigenverft.Manifested.Sandbox/actions/workflows/cicd.yml) [![License](https://img.shields.io/github/license/eigenverft/Eigenverft.Manifested.Sandbox?logo=mit)](LICENSE)

Windows-focused PowerShell module and repository-shipped Windows Sandbox profile for quickly turning a fresh Windows Sandbox session into a usable development environment. The primary user entrypoint is the downloadable `.wsb` file in this repo, backed by a PowerShell module that can provision managed Python, PowerShell 7, Node.js, OpenCode CLI, Gemini CLI, Qwen CLI, Codex CLI, GitHub CLI, MinGit, VS Code, and Microsoft Visual C++ runtime prerequisites when you want them.

The primary intent is fast, repeatable setup inside Windows Sandbox. The same module can also run on a normal Windows machine, but that is a secondary use case rather than the main focus of this repo.

🚀 **Key Features:**
- Ready-to-download Windows Sandbox profile in the repo for repeatable bring-up
- Managed runtime provisioning for `python`, `pip`, `pwsh`, `git`, `gh`, `code`, `node`, `npm`, `opencode`, `gemini`, `qwen`, `codex`, and VC++ prerequisites
- Runtime discovery that can reuse compatible external installs or refresh to sandbox-owned managed copies
- Persisted command results plus live runtime snapshots through `Get-SandboxState`
- Managed npm ownership under the sandbox Node runtime, including proxy-aware npm configuration when Windows resolves the npm registry through a proxy
- Proxy-aware startup and download handling for managed or corporate Windows environments
- Compacted embedded startup helpers so the `.wsb` `LogonCommand` fits within the practical 8 KB command-line limit
- PowerShell 5.1-first sandbox startup path with normal Windows machine support as a secondary workflow

## 🧭 Motivation

Windows Sandbox is ideal for disposable setup checks: bootstrap a repo, validate installer behavior, and test fresh-machine assumptions without touching your main workstation.

The problem is that a blank `.wsb` session still takes manual work to become useful, and in many corporate environments the first outbound connection is the hard part. Proxy discovery, proxy authentication, certificate friction, and Windows PowerShell bootstrap work often show up before the real task starts. This project packages that repeated startup story into a versioned `.wsb` profile plus a supporting PowerShell module so the environment is quick to reuse instead of tedious to rebuild.

## 🖥️ Host Requirements

Windows Sandbox on the host requires Windows 10/11 `1903+`, Pro/Enterprise/Education/Pro Education/SE, virtualization enabled, 4 GB RAM, 1 GB free disk, 2 CPU cores, and the `Windows Sandbox` feature enabled.

## 🖼️ Preview

![Windows Sandbox preview showing the repo-provided sandbox profile opening PowerShell and a follow-up runtime command](resources/screenshots/windows-sandbox-bootstrap-preview.png)

Example Windows Sandbox session after the repository's `.wsb` profile opens PowerShell and the follow-up runtime commands are available.

---

## 🚀 Quick Start

1. Download the sandbox profile: [Eigenverft.Manifested.Sandbox.wsb](src/wrk/Eigenverft.Manifested.Sandbox/Eigenverft.Manifested.Sandbox.wsb) or [raw .wsb download](https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Sandbox/refs/heads/main/src/wrk/Eigenverft.Manifested.Sandbox/Eigenverft.Manifested.Sandbox.wsb)
2. Before first launch, edit the file for your environment, especially the integration/security toggles, optional mapped folders, and startup defaults shown below.
3. Launch the `.wsb` file from Windows.
4. When the sandbox opens PowerShell, run the follow-up runtime commands you want.

### 🔧 Customize the `.wsb`

This is the main pre-launch customization point. Most users only need to review the integration toggles, decide whether they want any host folder mapping, and edit the four startup defaults inside `LogonCommand`.

```powershell
$dprx='http://test.corp.com:8080'
$duprx=''
$c='Get-SandboxVersion'
$i='PackageManagement','PowerShellGet','Eigenverft.Manifested.Sandbox'
```

| Setting | Default | What it controls |
| --- | --- | --- |
| `$dprx` | `http://test.corp.com:8080` | Default manual proxy address shown if startup resolves to a manual-proxy-required path. |
| `$duprx` | `''` | Prefills the proxy user field so a manual proxy prompt can require less typing. |
| `$c` | `Get-SandboxVersion` | Post-bootstrap command or semicolon-separated command chain executed in the fresh PowerShell window. |
| `$i` | `PackageManagement`, `PowerShellGet`, `Eigenverft.Manifested.Sandbox` | Module list requested by the embedded bootstrap step. It currently matches the built-in default inside `Initialize-Bootstrap`, so most users can leave it unchanged. |

### 🔐 Security Notes for the `.wsb`

This shipped `.wsb` is a convenience and testing profile first, not a hardened security-analysis profile.

A useful sandbox always needs some transfer path for content to come in and results to go back out. In practice that usually means `Networking`, `MappedFolders`, `ClipboardRedirection`, or some combination of them. This profile keeps `Networking` enabled because bootstrap, proxy resolution, and package download are the main use case.

`MappedFolders` is commented out by default. If you enable it, prefer a dedicated staging folder and keep `<ReadOnly>true</ReadOnly>` unless sandbox write-back is actually required. Writable mappings expose real host files to whatever runs inside the sandbox.

`ClipboardRedirection`, `PrinterRedirection`, `AudioInput`, `VideoInput`, and `VGpu` are convenience features. Turn off anything you do not need for the current run. `ProtectedClient` is enabled as an extra hardening layer, but it can restrict some host interaction flows.

If startup falls back to a manual proxy prompt, the resolved proxy profile is stored at `%LOCALAPPDATA%\Programs\ProxyAccessProfile\ProxyAccessProfile.clixml`. It is written with `Export-Clixml`, so on Windows the `PSCredential` stays bound to that sandbox user and sandbox instance. This is useful across in-sandbox restarts, but the whole sandbox is discarded when it is closed.

⚠ **Important:** If you entered manual proxy credentials and then want to continue with suspicious or unknown payload testing in the same sandbox, delete `%LOCALAPPDATA%\Programs\ProxyAccessProfile\ProxyAccessProfile.clixml` first. If the later test phase no longer needs the stored proxy/bootstrap state, an even tighter option is to run that phase in a fresh sandbox instance.

For most users, these are the only startup values worth touching. Leave the embedded helper payload alone unless you are intentionally maintaining the startup chain itself.

### 💡 Common `$c` Recipes

Use `$c` when you want startup to do more than just show the module version.

```powershell
# Simple sanity check after bootstrap
$c='Get-SandboxVersion'

# Bootstrap, then prepare a fuller sandbox toolset
$c='Get-SandboxVersion; Initialize-VCRuntime; Initialize-PythonRuntime; Initialize-Ps7Runtime; Initialize-GitRuntime; Get-SandboxState'

# Bootstrap, then download and run another script
$c='Invoke-WebRequestEx -Uri ''https://example.org/setup.ps1'' -OutFile ""$env:TEMP\setup.ps1""; powershell -ExecutionPolicy Bypass -File ""$env:TEMP\setup.ps1""'
```

### 🧠 Why the Startup Logic Is Embedded

The original bootstrapper approach was useful groundwork, but the more practical onboarding artifact in this repository is now the ready `.wsb` file.

The embedded startup chain exists because many managed corporate environments do not have a reliable first outbound connection. Proxy discovery, proxy authentication, certificate friction, and resilient download behavior are the real hurdles before any runtime install work begins.

`Initialize-ProxyCompact` in the `.wsb` is a highly compacted form of nearly the same proxy-resolution logic as `Initialize-ProxyAccessProfile`, and `Invoke-WebRequestEx` is the readable download-side reference in the module. `Initialize-Bootstrap` is still part of the embedded startup chain, but it is background implementation rather than the recommended public entrypoint.

When manual proxy entry is required, that resolved proxy profile stays inside the current sandbox instance and can survive in-sandbox restarts, but it is still discarded when the sandbox is closed.

The startup helpers are compacted and compressed so the Windows Sandbox `LogonCommand` stays within the practical 8 KB command-line limit. The tracked `.wsb` file in this repository is the authoritative version to download and edit, so the README intentionally does not reproduce the full embedded command blob.

---

## 📌 Current State

The module currently exports these public commands:

- `Get-SandboxState`
- `Get-SandboxVersion`
- `Initialize-CodexRuntime`
- `Initialize-GeminiRuntime`
- `Initialize-GHCliRuntime`
- `Initialize-GitRuntime`
- `Initialize-NodeRuntime`
- `Initialize-OpenCodeRuntime`
- `Initialize-ProxyAccessProfile`
- `Initialize-Ps7Runtime`
- `Initialize-PythonRuntime`
- `Initialize-QwenRuntime`
- `Initialize-VCRuntime`
- `Initialize-VSCodeRuntime`
- `Invoke-WebRequestEx`

There is not yet a single combined `Initialize-Sandbox` command. The current model is a set of small init commands that each read real state, plan from that state, perform bounded repair or install work, and persist the observed result.

---

## 🧪 Demo Commands

After the repository's `.wsb` profile opens the new console, run:

```powershell
Get-SandboxVersion
Initialize-PythonRuntime
Initialize-Ps7Runtime
Initialize-GitRuntime
Initialize-GHCliRuntime
Initialize-VSCodeRuntime
Initialize-NodeRuntime
Initialize-OpenCodeRuntime
Initialize-GeminiRuntime
Initialize-QwenRuntime
Initialize-CodexRuntime
Initialize-VCRuntime
Get-SandboxState
```

- `Get-SandboxVersion` is the quick way to show user-facing module info for the current session, including the resolved module version and the full exported command list in alphabetical order.
- `Get-SandboxState` exposes both the persisted command document and live runtime snapshots, so it is the easiest way to see what the module believes is managed, external, missing, partial, or blocked right now.
- `Initialize-PythonRuntime`, `Initialize-Ps7Runtime`, `Initialize-GitRuntime`, `Initialize-GHCliRuntime`, `Initialize-VSCodeRuntime`, `Initialize-NodeRuntime`, `Initialize-OpenCodeRuntime`, `Initialize-GeminiRuntime`, `Initialize-QwenRuntime`, and `Initialize-CodexRuntime` are intended to run in a normal user session. They prefer sandbox-managed portable runtimes under `LocalAppData`, using python.org for the CPython embeddable ZIP, GitHub as the download source for PowerShell 7, MinGit, and GitHub CLI, the official VS Code Windows ZIP archive with portable `data` mode for VS Code, and npm-based managed installs for OpenCode, Gemini, Qwen, and Codex.
- Those commands also check for an already-usable `python`, `pwsh`, `git`, `gh`, `code`, `node`, `opencode`, `gemini`, `qwen`, or `codex` that exists outside prior sandbox state. If a compatible runtime is already available on `PATH` or in a common install location, the command can treat it as ready and persist it as an external runtime instead of downloading or installing a new copy. If you explicitly use a refresh switch such as `-RefreshPython`, `-RefreshGit`, `-RefreshGHCli`, `-RefreshPs7`, `-RefreshVSCode`, `-RefreshNode`, `-RefreshOpenCode`, `-RefreshGemini`, `-RefreshQwen`, or `-RefreshCodex`, the command will still acquire and install the sandbox-managed copy.
- `Initialize-PythonRuntime` installs the official CPython Windows embeddable package into a sandbox-managed tools root, enables `import site`, bootstraps `pip`, and exposes `python`, `python.exe`, `pip.cmd`, and `pip3.cmd` from the managed runtime directory. When Windows resolves the package index through a proxy, it keeps proxy settings in a runtime-local `pip.ini` instead of writing to a machine-wide or user-wide pip config.
- `Initialize-GHCliRuntime` installs a managed `gh.exe` from the official GitHub CLI Windows ZIP release and validates the package against GitHub's published checksum asset before making that runtime active on `PATH`.
- `Initialize-NodeRuntime` installs the managed Node.js runtime and owns the sandbox-managed npm configuration. When Windows resolves the active npm registry through a proxy, it writes `proxy` and `https-proxy` into the managed runtime's global `npmrc`; when the route is direct, it leaves npm config unchanged.
- `Initialize-OpenCodeRuntime`, `Initialize-GeminiRuntime`, `Initialize-QwenRuntime`, and `Initialize-CodexRuntime` install `opencode-ai`, `@google/gemini-cli`, `@qwen-code/qwen-code`, and `@openai/codex` into sandbox-managed tool roots and inherit the managed npm global config when they are using the sandbox-owned Node/npm runtime.
- `Initialize-OpenCodeRuntime` installs `opencode-ai` and exposes `opencode` / `opencode.cmd` from the managed tool root when refreshed or newly installed.
- `Initialize-GeminiRuntime` installs `@google/gemini-cli` into the sandbox-managed tool root and prefers that managed copy when refreshed. Gemini CLI's official docs currently recommend Node.js `20.0.0+` and Windows 11 `24H2+`; this module follows a best-effort Windows policy and ensures a compatible Node runtime before managed install when needed.
- `Initialize-QwenRuntime` installs `@qwen-code/qwen-code` into the sandbox-managed tool root and prefers that managed copy when refreshed. Qwen Code's official quickstart currently requires Node.js `20+`; this module follows that requirement and ensures a compatible Node runtime before managed install when needed.
- `Initialize-CodexRuntime` installs `@openai/codex` into the sandbox-managed tool root and prefers that managed copy when refreshed. It always ensures the VC runtime prerequisite before install, and if no usable Node/npm is available yet it also ensures the required Node runtime first.
- `Initialize-VCRuntime` is different because the VC runtime is a machine/runtime prerequisite rather than a sandbox-managed portable tool.
- `Initialize-VCRuntime` should be run in an elevated PowerShell process when the Microsoft Visual C++ Redistributable needs to be installed or repaired.

## 📦 Direct Module Usage

If you prefer installing the module directly instead of using the `.wsb` profile:

This path assumes working access to `PSGallery` and the `NuGet` package provider. If first-connection proxy, authentication, or trust-chain setup is still the main hurdle, prefer the `.wsb` path above.

```powershell
Install-Module Eigenverft.Manifested.Sandbox -Scope CurrentUser -Repository PSGallery
Import-Module Eigenverft.Manifested.Sandbox
```

## 📝 Usage Tips

- Use the refresh switches when you want the sandbox-managed runtime even if a compatible tool already exists elsewhere on the machine.
- `Initialize-PythonRuntime` keeps pip cache and proxy state under the sandbox root, so it is a good fit for disposable or corporate-proxy sandbox sessions where you do not want pip config leaking into the wider user profile.
- OpenCode, Gemini, Qwen, and Codex are all opt-in in the example command chains; add the specific runtime init commands you want for a given sandbox profile.
- The npm-based CLIs share the managed Node runtime when needed. If `Initialize-NodeRuntime` detects that the npm registry routes through a system proxy, it persists that proxy into the sandbox-owned npm config; if the route is direct, it makes no npm proxy changes.
- To test another branch, swap `main` in the raw `.wsb` download URL before launching the sandbox.
- If you are working from a local checkout instead of the raw download, edit the tracked `.wsb` file directly and launch that local copy.
- Keep `.wsb` files small and let versioned PowerShell own the real startup logic whenever you want a more maintainable sandbox launch path.
- Run `Get-SandboxState` after a bootstrap chain when you want the quickest view of managed vs external runtimes and persisted command outcomes.
- Run `Initialize-VCRuntime` in an elevated PowerShell session if the Microsoft Visual C++ Redistributable needs installation or repair.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📫 Contact & Support

For questions and support:
- 🐛 Open an [issue](https://github.com/eigenverft/Eigenverft.Manifested.Sandbox/issues) in this repository
- 🤝 Submit a [pull request](https://github.com/eigenverft/Eigenverft.Manifested.Sandbox/pulls) with improvements

---

<div align="center">
Made with ❤️ by Eigenverft
</div>
