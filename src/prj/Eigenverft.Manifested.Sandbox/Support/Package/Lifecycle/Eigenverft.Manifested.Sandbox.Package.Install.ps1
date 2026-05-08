<#
    Eigenverft.Manifested.Sandbox.Package.Install
    Set-PackageAssignedState orchestration only. Fragment scripts are dot-sourced from
    Eigenverft.Manifested.Sandbox.psm1 (and Eigenverft.Manifested.Sandbox.TestImports.ps1)
    in dependency order immediately before this file.
#>

function Set-PackageAssignedState {
<#
.SYNOPSIS
Assigns the selected package (install or reuse per assigned.kind).

.DESCRIPTION
Reuses or adopts a valid existing install when the earlier ownership/policy
decision allows it, otherwise executes the configured install kind and attaches
the assigned-state result to the Package result object.

.PARAMETER PackageResult
The Package result object to enrich.

.EXAMPLE
Set-PackageAssignedState -PackageResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $package = $PackageResult.Package
    $install = Get-PackageEffectiveReleaseAssignedBlock -Release $package
    if (-not $install -or -not $install.PSObject.Properties['kind']) {
        throw "Package release '$($package.id)' does not define assigned.kind."
    }

    if ([string]::Equals([string]$PackageResult.InstallOrigin, 'AlreadySatisfied', [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-PackageExecutionMessage -Message "[ACTION] Skipped installer because machine prerequisite is already satisfied."
        return $PackageResult
    }

    if ($PackageResult.ExistingPackage -and $PackageResult.ExistingPackage.Decision -eq 'ReusePackageOwned') {
        $PackageResult.InstallDirectory = $PackageResult.ExistingPackage.InstallDirectory
        $PackageResult.InstallOrigin = 'PackageReused'
        $PackageResult.Assigned = [pscustomobject]@{
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
        $PackageResult.Assigned = [pscustomobject]@{
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
            Write-PackageExecutionMessage -Message ("[ACTION] Assigning package archive into '{0}'." -f $PackageResult.InstallDirectory)
            $PackageResult.Assigned = Install-PackageArchive -PackageResult $PackageResult
        }
        'placePackageFile' {
            Write-PackageExecutionMessage -Message ("[ACTION] Placing package file into '{0}'." -f $PackageResult.InstallDirectory)
            $PackageResult.Assigned = Install-PackagePackageFile -PackageResult $PackageResult
        }
        'runInstaller' {
            $targetKind = Get-PackageInstallTargetKind -Package $package
            $targetText = if ([string]::IsNullOrWhiteSpace([string]$PackageResult.InstallDirectory)) { '<machine prerequisite>' } else { [string]$PackageResult.InstallDirectory }
            Write-PackageExecutionMessage -Message ("[ACTION] Running installer for target '{0}'." -f $targetText)
            $installerResult = Invoke-PackageInstallerProcess -PackageResult $PackageResult
            $PackageResult.Assigned = [pscustomobject]@{
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
            $PackageResult.Assigned = [pscustomobject]@{
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
            $PackageResult.Assigned = Install-PackageNpmPackage -PackageResult $PackageResult
        }
        default {
            throw "Unsupported Package assigned.kind '$($install.kind)'."
        }
    }

    $PackageResult.InstallOrigin = if ([string]::Equals((Get-PackageInstallTargetKind -Package $package), 'machinePrerequisite', [System.StringComparison]::OrdinalIgnoreCase)) {
        'PackageApplied'
    }
    else {
        'PackageInstalled'
    }
    Write-PackageExecutionMessage -Message ("[ACTION] Completed Package-owned assign with status '{0}'." -f $PackageResult.Assigned.Status)
    return $PackageResult
}
