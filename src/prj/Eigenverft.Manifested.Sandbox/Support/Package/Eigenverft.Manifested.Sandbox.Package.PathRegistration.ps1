<#
    Eigenverft.Manifested.Sandbox.Package.PathRegistration
#>

function Get-PackagePathRegistrationSourcePath {
<#
.SYNOPSIS
Resolves the raw source path for PATH registration.

.DESCRIPTION
Interprets the configured pathRegistration source and returns the concrete file
or directory path for the requested install directory.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult,

        [string]$InstallDirectoryOverride
    )

    $install = $PackageResult.Package.install
    if (-not $install -or -not $install.PSObject.Properties['pathRegistration'] -or $null -eq $install.pathRegistration) {
        return $null
    }

    $pathRegistration = $install.pathRegistration
    if (-not $pathRegistration.PSObject.Properties['source'] -or $null -eq $pathRegistration.source) {
        return $null
    }

    $source = $pathRegistration.source
    $sourceKind = if ($source.PSObject.Properties['kind']) { [string]$source.kind } else { $null }
    $sourceValue = if ($source.PSObject.Properties['value']) { [string]$source.value } else { $null }
    if ([string]::IsNullOrWhiteSpace($sourceKind) -or [string]::IsNullOrWhiteSpace($sourceValue)) {
        throw "Package pathRegistration requires source.kind and source.value when pathRegistration.mode is not 'none'."
    }

    $baseInstallDirectory = if (-not [string]::IsNullOrWhiteSpace($InstallDirectoryOverride)) {
        $InstallDirectoryOverride
    }
    else {
        $PackageResult.InstallDirectory
    }

    switch -Exact ($sourceKind) {
        'commandEntryPoint' {
            foreach ($entryPoint in @($PackageResult.PackageConfig.Definition.providedTools.commands)) {
                if ([string]::Equals([string]$entryPoint.name, $sourceValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return (Join-Path $baseInstallDirectory (([string]$entryPoint.relativePath) -replace '/', '\'))
                }
            }
            throw "Package pathRegistration source commandEntryPoint '$sourceValue' was not found in providedTools.commands."
        }
        'appEntryPoint' {
            foreach ($entryPoint in @($PackageResult.PackageConfig.Definition.providedTools.apps)) {
                if ([string]::Equals([string]$entryPoint.name, $sourceValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return (Join-Path $baseInstallDirectory (([string]$entryPoint.relativePath) -replace '/', '\'))
                }
            }
            throw "Package pathRegistration source appEntryPoint '$sourceValue' was not found in providedTools.apps."
        }
        'installRelativeDirectory' {
            return (Join-Path $baseInstallDirectory (($sourceValue) -replace '/', '\'))
        }
        'shim' {
            throw "Package pathRegistration source kind 'shim' is reserved but not implemented yet."
        }
        default {
            throw "Unsupported Package pathRegistration source kind '$sourceKind'."
        }
    }
}

function Test-PackageShouldApplyPathRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    return ([string]$PackageResult.InstallOrigin) -in @('PackageInstalled', 'PackageReused')
}

function Get-PackagePathRegistrationCleanupDirectories {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $currentInstallDirectory = Get-NormalizedPathEntry -PathEntry ([string]$PackageResult.InstallDirectory)
    $cleanupDirectories = New-Object System.Collections.Generic.List[string]
    $candidateInstallDirectories = New-Object System.Collections.Generic.List[string]

    if ($PackageResult.ExistingPackage -and
        [string]::Equals([string]$PackageResult.ExistingPackage.Classification, 'PackageOwned', [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::IsNullOrWhiteSpace([string]$PackageResult.ExistingPackage.InstallDirectory)) {
        $candidateInstallDirectories.Add([string]$PackageResult.ExistingPackage.InstallDirectory) | Out-Null
    }

    if ($PackageResult.Ownership -and
        $PackageResult.Ownership.OwnershipRecord -and
        $PackageResult.Ownership.OwnershipRecord.PSObject.Properties['installDirectory'] -and
        -not [string]::IsNullOrWhiteSpace([string]$PackageResult.Ownership.OwnershipRecord.installDirectory)) {
        $candidateInstallDirectories.Add([string]$PackageResult.Ownership.OwnershipRecord.installDirectory) | Out-Null
    }

    foreach ($candidateInstallDirectory in @($candidateInstallDirectories.ToArray())) {
        $normalizedCandidateInstallDirectory = Get-NormalizedPathEntry -PathEntry $candidateInstallDirectory
        if ([string]::IsNullOrWhiteSpace($normalizedCandidateInstallDirectory) -or
            [string]::Equals($normalizedCandidateInstallDirectory, $currentInstallDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $candidateSourcePath = Get-PackagePathRegistrationSourcePath -PackageResult $PackageResult -InstallDirectoryOverride $candidateInstallDirectory
        $candidateSourceKind = if ($PackageResult.Package.install.pathRegistration.source.PSObject.Properties['kind']) {
            [string]$PackageResult.Package.install.pathRegistration.source.kind
        }
        else {
            $null
        }
        $candidateRegisteredDirectory = Resolve-PathRegistrationDirectory -SourcePath $candidateSourcePath -SourceKind $candidateSourceKind
        $normalizedCandidateRegisteredDirectory = Get-NormalizedPathEntry -PathEntry $candidateRegisteredDirectory
        if ([string]::IsNullOrWhiteSpace($normalizedCandidateRegisteredDirectory)) {
            continue
        }

        if ($normalizedCandidateRegisteredDirectory -notin @($cleanupDirectories.ToArray())) {
            $cleanupDirectories.Add($normalizedCandidateRegisteredDirectory) | Out-Null
        }
    }

    return @($cleanupDirectories.ToArray())
}

function Register-PackagePath {
<#
.SYNOPSIS
Applies Package PATH registration for a validated install.

.DESCRIPTION
Updates process and persisted PATH scopes according to install.pathRegistration.
User mode updates Process and User PATH. Machine mode updates Process and
Machine PATH. None skips registration. Package only writes PATH entries
for Package-owned outcomes and only cleans stale Package-owned paths
for the same install slot.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $install = $PackageResult.Package.install
    $pathRegistration = if ($install -and $install.PSObject.Properties['pathRegistration']) { $install.pathRegistration } else { $null }
    $mode = if ($pathRegistration -and $pathRegistration.PSObject.Properties['mode'] -and -not [string]::IsNullOrWhiteSpace([string]$pathRegistration.mode)) {
        ([string]$pathRegistration.mode).ToLowerInvariant()
    }
    else {
        'none'
    }

    $source = if ($pathRegistration -and $pathRegistration.PSObject.Properties['source']) { $pathRegistration.source } else { $null }
    $sourceKind = if ($source -and $source.PSObject.Properties['kind']) { [string]$source.kind } else { $null }
    $sourceValue = if ($source -and $source.PSObject.Properties['value']) { [string]$source.value } else { $null }

    if ($mode -eq 'none') {
        $pathRegistrationResult = [pscustomobject]@{
            Status             = 'Skipped'
            Mode               = 'none'
            SourceKind         = $sourceKind
            SourceValue        = $sourceValue
            SourcePath         = $null
            RegisteredPath     = $null
            CleanupDirectories = @()
            CleanedTargets     = @()
            UpdatedTargets     = @()
        }
        if ($PackageResult.PSObject.Properties['PathRegistration']) {
            $PackageResult.PathRegistration = $pathRegistrationResult
        }
        else {
            $PackageResult | Add-Member -MemberType NoteProperty -Name PathRegistration -Value $pathRegistrationResult
        }
        Write-PackageExecutionMessage -Message '[STATE] PATH registration skipped because mode is none.'
        return $PackageResult
    }

    if ($mode -notin @('user', 'machine')) {
        throw "Unsupported Package pathRegistration.mode '$mode'."
    }

    if (-not (Test-PackageShouldApplyPathRegistration -PackageResult $PackageResult)) {
        $pathRegistrationResult = [pscustomobject]@{
            Status             = 'SkippedNotPackageOwned'
            Mode               = $mode
            SourceKind         = $sourceKind
            SourceValue        = $sourceValue
            SourcePath         = $null
            RegisteredPath     = $null
            CleanupDirectories = @()
            CleanedTargets     = @()
            UpdatedTargets     = @()
        }
        if ($PackageResult.PSObject.Properties['PathRegistration']) {
            $PackageResult.PathRegistration = $pathRegistrationResult
        }
        else {
            $PackageResult | Add-Member -MemberType NoteProperty -Name PathRegistration -Value $pathRegistrationResult
        }

        Write-PackageExecutionMessage -Message ("[STATE] PATH registration skipped because installOrigin '{0}' is not Package-owned." -f [string]$PackageResult.InstallOrigin)
        return $PackageResult
    }

    $sourcePath = Get-PackagePathRegistrationSourcePath -PackageResult $PackageResult
    if ([string]::IsNullOrWhiteSpace($sourcePath) -or -not (Test-Path -LiteralPath $sourcePath)) {
        throw "Package PATH registration source path '$sourcePath' was not found."
    }

    $registeredPath = Resolve-PathRegistrationDirectory -SourcePath $sourcePath -SourceKind $sourceKind
    $cleanupDirectories = @(Get-PackagePathRegistrationCleanupDirectories -PackageResult $PackageResult)
    $registrationResult = Register-PathEnvironment -Mode $mode -RegisteredPath $registeredPath -CleanupDirectories $cleanupDirectories

    $pathRegistrationResult = [pscustomobject]@{
        Status             = $registrationResult.Status
        Mode               = $registrationResult.Mode
        SourceKind         = $sourceKind
        SourceValue        = $sourceValue
        SourcePath         = $sourcePath
        RegisteredPath     = $registrationResult.RegisteredPath
        CleanupDirectories = @($registrationResult.CleanupDirectories)
        CleanedTargets     = @($registrationResult.CleanedTargets)
        UpdatedTargets     = @($registrationResult.UpdatedTargets)
    }
    if ($PackageResult.PSObject.Properties['PathRegistration']) {
        $PackageResult.PathRegistration = $pathRegistrationResult
    }
    else {
        $PackageResult | Add-Member -MemberType NoteProperty -Name PathRegistration -Value $pathRegistrationResult
    }

    Write-PackageExecutionMessage -Message ("[STATE] PATH registration resolved source kind='{0}' value='{1}' to '{2}'." -f $sourceKind, $sourceValue, $registeredPath)
    if ($cleanupDirectories.Count -gt 0) {
        Write-PackageExecutionMessage -Message ("[STATE] PATH cleanup directories for this Package install slot: {0}" -f ($cleanupDirectories -join ', '))
    }
    Write-PackageExecutionMessage -Message ("[ACTION] PATH registration status='{0}' mode='{1}' updatedTargets='{2}' cleanedTargets='{3}'." -f $PackageResult.PathRegistration.Status, $mode, $(if ($registrationResult.UpdatedTargets.Count -gt 0) { @($registrationResult.UpdatedTargets) -join ',' } else { '<none>' }), $(if ($registrationResult.CleanedTargets.Count -gt 0) { @($registrationResult.CleanedTargets) -join ',' } else { '<none>' }))

    return $PackageResult
}

