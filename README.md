# Eigenverft.Manifested.Sandbox

Windows-focused PowerShell module for initializing managed Node.js and Microsoft Visual C++ runtime prerequisites.

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
Initialize-NodeRuntime
Initialize-VCRuntime
```

## Direct Module Usage

If you prefer installing the module directly instead of using the bootstrapper:

```powershell
Install-Module Eigenverft.Manifested.Sandbox -Scope CurrentUser -Repository PSGallery
Import-Module Eigenverft.Manifested.Sandbox
```

