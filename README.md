# Eigenverft.Manifested.Sandbox

Windows-focused PowerShell module for initializing managed PowerShell 7, Node.js, MinGit, and Microsoft Visual C++ runtime prerequisites.

## Bootstrapper

The bootstrapper installs the required PowerShell package tooling plus `Eigenverft.Manifested.Sandbox` from the PowerShell Gallery, then opens a new Windows PowerShell console for using the module.

Run it from Windows PowerShell 5.1:

```powershell
iwr -useb https://raw.githubusercontent.com/eigenverft/Eigenverft.Manifested.Sandbox/refs/heads/main/iwr/bootstrapper.ps1 | iex
```

To test another branch, replace `main` with the branch name in the URL.

## Demo Commands

After the bootstrapper opens the new console, run:

```powershell
Initialize-Ps7Runtime
Initialize-GitRuntime
Initialize-NodeRuntime
Initialize-VCRuntime
Get-SandboxState
```

`Initialize-Ps7Runtime`, `Initialize-GitRuntime`, and `Initialize-NodeRuntime` are intended to run in a normal user session. They prefer sandbox-managed portable runtimes under `LocalAppData`, using GitHub as the download source for PowerShell 7 and MinGit.

Those three commands also check for an already-usable `pwsh`, `git`, or `node` that exists outside prior sandbox state. If a compatible runtime is already available on `PATH` or in a common install location, the command can treat it as ready and persist it as an external runtime instead of downloading a new copy. If you explicitly use a refresh switch such as `-RefreshGit`, `-RefreshPs7`, or `-RefreshNode`, the command will still acquire and install the sandbox-managed copy.

`Initialize-VCRuntime` is different because the VC runtime is a machine/runtime prerequisite rather than a sandbox-managed portable tool.

`Initialize-VCRuntime` should be run in an elevated PowerShell process when the Microsoft Visual C++ Redistributable needs to be installed or repaired.

## Direct Module Usage

If you prefer installing the module directly instead of using the bootstrapper:

```powershell
Install-Module Eigenverft.Manifested.Sandbox -Scope CurrentUser -Repository PSGallery
Import-Module Eigenverft.Manifested.Sandbox
```

