# Eigenverft.Manifested.Sandbox

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/Eigenverft.Manifested.Sandbox?label=PSGallery&logo=powershell)](https://www.powershellgallery.com/packages/Eigenverft.Manifested.Sandbox) [![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/Eigenverft.Manifested.Sandbox?label=Downloads&logo=powershell)](https://www.powershellgallery.com/packages/Eigenverft.Manifested.Sandbox) [![PowerShell Support](https://img.shields.io/badge/PowerShell-5.1%2B%20Desktop%2FCore-5391FE?logo=powershell&logoColor=white)](source/Eigenverft.Manifested.Sandbox/Eigenverft.Manifested.Sandbox.psd1) [![Build Status](https://img.shields.io/github/actions/workflow/status/eigenverft/Eigenverft.Manifested.Sandbox/cicd.yml?branch=main&label=build)](https://github.com/eigenverft/Eigenverft.Manifested.Sandbox/actions/workflows/cicd.yml) [![License](https://img.shields.io/github/license/eigenverft/Eigenverft.Manifested.Sandbox?logo=mit)](LICENSE)

Windows-focused PowerShell module and bootstrap flow for quickly bringing up a usable Windows sandbox or fresh Windows developer environment. It can provision managed PowerShell 7, Node.js, MinGit, and Microsoft Visual C++ runtime prerequisites when you want them.

The primary intent is fast setup inside a Windows sandbox-style environment, but the same bootstrap pattern also works on a normal Windows machine or from a Windows Sandbox `.wsb` file when you want a small versioned PowerShell entrypoint with state tracking.

## Bootstrapper

The bootstrapper is optimized for getting a Windows sandbox session ready quickly. It installs the required PowerShell package tooling plus `Eigenverft.Manifested.Sandbox` from the PowerShell Gallery, then opens a new Windows PowerShell console and runs the default follow-up command.

Even if you do not end up using this module's managed runtime installers, the bootstrapper is still useful as a reusable startup pattern. It gives you a simple way to install a chosen set of PowerShell Gallery modules, open a fresh console, and immediately run a preset command chain. The installers are one use of that flow, not the only reason to use it.

PowerShell Gallery package: [Eigenverft.Manifested.Sandbox](https://www.powershellgallery.com/packages/Eigenverft.Manifested.Sandbox)

### Trust / Install Notes

The published bootstrap one-liner first downloads [`iwr/bootstrapper.ps1`](https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Sandbox/refs/heads/main/iwr/bootstrapper.ps1) from `raw.githubusercontent.com` and then, in Windows PowerShell 5.1:

- enables TLS 1.2 if possible
- tries to set the current user's execution policy to `Unrestricted`
- bootstraps the `NuGet` package provider in `CurrentUser` scope
- trusts or registers `PSGallery`
- installs `PowerShellGet`, `PackageManagement`, and `Eigenverft.Manifested.Sandbox` in `CurrentUser` scope
- opens a new Windows PowerShell session and runs `Get-SandboxVersion`

Admin rights are not required for the bootstrap or module install path. Later runtime actions can have different requirements; for example, `Initialize-VCRuntime` may still require elevation when the VC++ runtime needs to be installed or repaired.

Run it from Windows PowerShell 5.1:

```powershell
iwr -useb https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Sandbox/refs/heads/main/iwr/bootstrapper.ps1 | iex
```

Or from `cmd.exe`:

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "iwr -UseBasicParsing 'https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Sandbox/refs/heads/main/iwr/bootstrapper.ps1' | iex" && exit
```

A generic version of the bootstrapper lets you specify which PowerShell Gallery modules to install and which command to invoke automatically, so it can be reused for projects beyond `Eigenverft.Manifested.Sandbox` and for repo-specific bootstrap flows that just need a clean handoff into PowerShell.

```powershell
$c='Initialize-VCRuntime;Initialize-Ps7Runtime;Initialize-GitRuntime;Initialize-VSCodeRuntime;Initialize-NodeRuntime;Get-SandboxState';$i='PowerShellGet','PackageManagement','Eigenverft.Manifested.Sandbox';iwr -useb https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Sandbox/refs/heads/main/iwr/bootstrapper.sandbox.generic.ps1 | iex
```

To test another branch, replace `main` with the branch name in the URL.

The published default bootstrapper currently uses:

```powershell
$i='PowerShellGet','PackageManagement','Eigenverft.Manifested.Sandbox'
$c='Get-SandboxVersion'
```

The configurable variant keeps the same overall bootstrap pattern, but lets you preset `$i` and `$c` before invocation. That same pattern also maps well to Windows Sandbox `.wsb` startup definitions, where you often want the XML to stay small while the real startup behavior lives in versioned PowerShell.

## Windows Sandbox `.wsb` Example

If you want a ready-to-use Windows Sandbox entry file, save something like this as `sandbox.wsb` and launch it:

```xml
<Configuration>

  <!-- Hardware / integration toggles -->
  <VGpu>Enable</VGpu>
  <Networking>Enable</Networking>

  <AudioInput>Enable</AudioInput>
  <VideoInput>Enable</VideoInput>

  <PrinterRedirection>Enable</PrinterRedirection>
  <ClipboardRedirection>Enable</ClipboardRedirection>

  <MemoryInMB>8192</MemoryInMB>

  <!-- Map host folder into the sandbox -->
  <MappedFolders>
    <MappedFolder>
      <HostFolder>C:\temp</HostFolder>
      <SandboxFolder>C:\temp</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>

  <!-- Auto-start: PowerShell startup -->
  <LogonCommand>
    <!-- Dev-friendly generic variant:
         <Command>cmd /c start "" powershell.exe -NoExit -Command "$c='Get-SandboxVersion;Initialize-Ps7Runtime;Initialize-GitRuntime;Initialize-VSCodeRuntime;Initialize-NodeRuntime;Get-SandboxState';$i='PowerShellGet','PackageManagement','Eigenverft.Manifested.Sandbox';iwr -useb https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Sandbox/refs/heads/main/iwr/bootstrapper.sandbox.generic.ps1 | iex"</Command>
    -->
    <Command>cmd /c start "" powershell.exe -NoExit -Command "iwr -useb https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Sandbox/refs/heads/main/iwr/bootstrapper.ps1 | iex"</Command>
  </LogonCommand>

</Configuration>
```

This is a practical starting point for a disposable Windows Sandbox session that immediately pulls the bootstrapper from GitHub and opens PowerShell for the follow-up init commands.

The `.wsb` scenario is one of the clearest reasons to keep the bootstrapper flexible. The XML only needs to launch PowerShell and point at the bootstrap script, while the module list and startup command can stay in versioned PowerShell instead of being baked directly into the sandbox definition. If you want a different startup flow, switch the `LogonCommand` to the generic bootstrapper variant and preset `$i` and `$c` there.

## Demo Commands

After the bootstrapper opens the new console, run:

```powershell
Get-SandboxVersion
Initialize-Ps7Runtime
Initialize-GitRuntime
Initialize-VSCodeRuntime
Initialize-NodeRuntime
Initialize-VCRuntime
Get-SandboxState
```

`Get-SandboxVersion` is the quick way to show the latest available installed module version on the system.

`Initialize-Ps7Runtime`, `Initialize-GitRuntime`, `Initialize-VSCodeRuntime`, and `Initialize-NodeRuntime` are intended to run in a normal user session. They prefer sandbox-managed portable runtimes under `LocalAppData`, using GitHub as the download source for PowerShell 7 and MinGit and the official VS Code Windows ZIP archive with portable `data` mode for VS Code.

Those commands also check for an already-usable `pwsh`, `git`, `code`, or `node` that exists outside prior sandbox state. If a compatible runtime is already available on `PATH` or in a common install location, the command can treat it as ready and persist it as an external runtime instead of downloading a new copy. If you explicitly use a refresh switch such as `-RefreshGit`, `-RefreshPs7`, `-RefreshVSCode`, or `-RefreshNode`, the command will still acquire and install the sandbox-managed copy.

`Initialize-VCRuntime` is different because the VC runtime is a machine/runtime prerequisite rather than a sandbox-managed portable tool.

`Initialize-VCRuntime` should be run in an elevated PowerShell process when the Microsoft Visual C++ Redistributable needs to be installed or repaired.

## Direct Module Usage

If you prefer installing the module directly instead of using the bootstrapper:

```powershell
Install-Module Eigenverft.Manifested.Sandbox -Scope CurrentUser -Repository PSGallery
Import-Module Eigenverft.Manifested.Sandbox
```
