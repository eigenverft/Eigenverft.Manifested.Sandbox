<#
    Eigenverft.Manifested.Sandbox.Package.Install
    Install-PackagePackage orchestration only. Fragment scripts are dot-sourced from
    Eigenverft.Manifested.Sandbox.psm1 (and Eigenverft.Manifested.Sandbox.TestImports.ps1)
    in dependency order immediately before this file.
#>

function Install-PackagePackage {
<#
.SYNOPSIS
Installs or reuses the selected package.

.DESCRIPTION
Reuses or adopts a valid existing install when the earlier ownership/policy
decision allows it, otherwise executes the configured install kind and attaches
the install result to the Package result object.

.PARAMETER PackageResult
The Package result object to enrich.

.EXAMPLE
Install-PackagePackage -PackageResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $package = $PackageResult.Package
    $install = $package.install
    if (-not $install -or -not $install.PSObject.Properties['kind']) {
        throw "Package release '$($package.id)' does not define install.kind."
    }

    if ([string]::Equals([string]$PackageResult.InstallOrigin, 'AlreadySatisfied', [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-PackageExecutionMessage -Message "[ACTION] Skipped installer because machine prerequisite is already satisfied."
        return $PackageResult
    }

    if ($PackageResult.ExistingPackage -and $PackageResult.ExistingPackage.Decision -eq 'ReusePackageOwned') {
        $PackageResult.InstallDirectory = $PackageResult.ExistingPackage.InstallDirectory
        $PackageResult.InstallOrigin = 'PackageReused'
        $PackageResult.Install = [pscustomobject]@{
            Status           = 'ReusedPackageOwned'
            InstallKind      = 'existingInstall'
            InstallDirectory = $PackageResult.ExistingPackage.InstallDirectory
            ReusedExisting   = $true
            CandidatePath    = $PackageResult.ExistingPackage.CandidatePath
        }
        $PackageResult.Validation = $PackageResult.ExistingPackage.Validation
        Write-PackageExecutionMessage -Message ("[ACTION] Reused Package-owned install '{0}'." -f $PackageResult.ExistingPackage.InstallDirectory)
        return $PackageResult
    }

    if ($PackageResult.ExistingPackage -and $PackageResult.ExistingPackage.Decision -eq 'AdoptExternal') {
        $PackageResult.InstallDirectory = $PackageResult.ExistingPackage.InstallDirectory
        $PackageResult.InstallOrigin = 'AdoptedExternal'
        $PackageResult.Install = [pscustomobject]@{
            Status           = 'AdoptedExternal'
            InstallKind      = 'existingInstall'
            InstallDirectory = $PackageResult.ExistingPackage.InstallDirectory
            ReusedExisting   = $true
            CandidatePath    = $PackageResult.ExistingPackage.CandidatePath
        }
        $PackageResult.Validation = $PackageResult.ExistingPackage.Validation
        Write-PackageExecutionMessage -Message ("[ACTION] Adopted external install '{0}'." -f $PackageResult.ExistingPackage.InstallDirectory)
        return $PackageResult
    }

    if ([string]::Equals([string]$install.kind, 'reuseExisting', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Package release '$($package.id)' requires an existing install, but no reusable install passed validation."
    }

    if ($PackageResult.PackageFilePreparation -and -not $PackageResult.PackageFilePreparation.Success) {
        throw $PackageResult.PackageFilePreparation.ErrorMessage
    }

    switch -Exact ([string]$install.kind) {
        'expandArchive' {
            Write-PackageExecutionMessage -Message ("[ACTION] Installing package archive into '{0}'." -f $PackageResult.InstallDirectory)
            $PackageResult.Install = Install-PackageArchive -PackageResult $PackageResult
        }
        'placePackageFile' {
            Write-PackageExecutionMessage -Message ("[ACTION] Placing package file into '{0}'." -f $PackageResult.InstallDirectory)
            $PackageResult.Install = Install-PackagePackageFile -PackageResult $PackageResult
        }
        'runInstaller' {
            $targetKind = Get-PackageInstallTargetKind -Package $package
            $targetText = if ([string]::IsNullOrWhiteSpace([string]$PackageResult.InstallDirectory)) { '<machine prerequisite>' } else { [string]$PackageResult.InstallDirectory }
            Write-PackageExecutionMessage -Message ("[ACTION] Running installer for target '{0}'." -f $targetText)
            $installerResult = Invoke-PackageInstallerProcess -PackageResult $PackageResult
            $PackageResult.Install = [pscustomobject]@{
                Status           = Get-PackageOwnedInstallStatus -PackageResult $PackageResult
                InstallKind      = 'runInstaller'
                TargetKind       = $targetKind
                InstallDirectory = $PackageResult.InstallDirectory
                ReusedExisting   = $false
                Installer        = $installerResult
            }
        }
        'nsisInstaller' {
            Write-PackageExecutionMessage -Message ("[ACTION] Running NSIS installer for target '{0}'." -f $PackageResult.InstallDirectory)
            $installerResult = Invoke-PackageNsisInstallerProcess -PackageResult $PackageResult
            $PackageResult.Install = [pscustomobject]@{
                Status           = Get-PackageOwnedInstallStatus -PackageResult $PackageResult
                InstallKind      = 'nsisInstaller'
                TargetKind       = Get-PackageInstallTargetKind -Package $package
                InstallDirectory = $PackageResult.InstallDirectory
                ReusedExisting   = $false
                Installer        = $installerResult
            }
        }
        'npmGlobalPackage' {
            Write-PackageExecutionMessage -Message ("[ACTION] Installing npm global package into '{0}'." -f $PackageResult.InstallDirectory)
            $PackageResult.Install = Install-PackageNpmPackage -PackageResult $PackageResult
        }
        default {
            throw "Unsupported Package install kind '$($install.kind)'."
        }
    }

    $PackageResult.InstallOrigin = if ([string]::Equals((Get-PackageInstallTargetKind -Package $package), 'machinePrerequisite', [System.StringComparison]::OrdinalIgnoreCase)) {
        'PackageApplied'
    }
    else {
        'PackageInstalled'
    }
    Write-PackageExecutionMessage -Message ("[ACTION] Completed Package-owned install with status '{0}'." -f $PackageResult.Install.Status)
    return $PackageResult
}
