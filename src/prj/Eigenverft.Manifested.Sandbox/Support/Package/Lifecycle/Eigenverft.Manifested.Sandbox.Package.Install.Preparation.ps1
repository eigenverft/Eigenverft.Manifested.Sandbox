<#
    Eigenverft.Manifested.Sandbox.Package.Install — install-target metadata, elevation plan, machine-prerequisite short-circuit.
    Dot-sourced from Eigenverft.Manifested.Sandbox.psm1 (mirrored in TestImports.ps1) before Package.Install.ps1.
#>

function Get-PackageOwnedInstallStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    if ($PackageResult.ExistingPackage) {
        switch -Exact ([string]$PackageResult.ExistingPackage.Decision) {
            'ExistingInstallValidationFailed' {
                if ([string]::Equals([string]$PackageResult.ExistingPackage.SearchKind, 'packageTargetInstallPath', [System.StringComparison]::OrdinalIgnoreCase)) {
                    return 'RepairedPackageOwnedInstall'
                }
            }
            'ReplacePackageOwnedInstall' { return 'ReplacedPackageOwnedInstall' }
            'UpgradeAdoptedInstall' { return 'ReplacedAdoptedInstall' }
        }
    }

    return 'Installed'
}

function Get-PackageInstallTargetKind {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Package
    )

    if ($Package.install -and $Package.install.PSObject.Properties['targetKind'] -and
        -not [string]::IsNullOrWhiteSpace([string]$Package.install.targetKind)) {
        return [string]$Package.install.targetKind
    }

    return 'directory'
}

function Get-PackageInstallerElevationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $install = $PackageResult.Package.install
    $mode = if ($install.PSObject.Properties['elevation'] -and -not [string]::IsNullOrWhiteSpace([string]$install.elevation)) {
        ([string]$install.elevation).ToLowerInvariant()
    }
    else {
        'none'
    }
    $processIsElevated = Test-ProcessElevation
    $shouldElevate = ($mode -in @('required', 'auto')) -and (-not $processIsElevated)

    return [pscustomobject]@{
        Mode              = $mode
        ProcessIsElevated = $processIsElevated
        ShouldElevate     = $shouldElevate
    }
}

function Resolve-PackagePreInstallSatisfaction {
<#
.SYNOPSIS
Checks whether a machine-prerequisite package is already satisfied.

.DESCRIPTION
Runs validation before acquisition/install for prerequisite-style packages that
do not own an install directory. When validation succeeds, later acquisition
and installer steps are skipped.

.PARAMETER PackageResult
The Package result object to enrich.

.EXAMPLE
Resolve-PackagePreInstallSatisfaction -PackageResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $package = $PackageResult.Package
    if (-not $package -or -not $package.install) {
        return $PackageResult
    }

    $installKind = if ($package.install.PSObject.Properties['kind']) { [string]$package.install.kind } else { $null }
    $targetKind = Get-PackageInstallTargetKind -Package $package
    if (-not [string]::Equals($installKind, 'runInstaller', [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($targetKind, 'machinePrerequisite', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $PackageResult
    }

    $PackageResult = Test-PackageInstalledPackage -PackageResult $PackageResult
    if ($PackageResult.Validation -and $PackageResult.Validation.Accepted) {
        $PackageResult.InstallOrigin = 'AlreadySatisfied'
        $PackageResult.Install = [pscustomobject]@{
            Status           = 'AlreadySatisfied'
            InstallKind      = 'runInstaller'
            TargetKind       = 'machinePrerequisite'
            InstallDirectory = $null
            ReusedExisting   = $true
        }
        Write-PackageExecutionMessage -Message "[DECISION] Machine prerequisite is already satisfied; skipping acquisition and installer execution."
    }
    else {
        $failedCount = if ($PackageResult.Validation) {
            @(
                @($PackageResult.Validation.Files) +
                @($PackageResult.Validation.Directories) +
                @($PackageResult.Validation.Commands) +
                @($PackageResult.Validation.MetadataFiles) +
                @($PackageResult.Validation.Signatures) +
                @($PackageResult.Validation.FileDetails) +
                @($PackageResult.Validation.Registry) |
                    Where-Object { $_.Status -ne 'Ready' }
            ).Count
        }
        else {
            0
        }
        Write-PackageExecutionMessage -Message ("[STATE] Machine prerequisite is not satisfied yet; failedChecks={0}." -f $failedCount)
        $PackageResult.Validation = $null
    }

    return $PackageResult
}
