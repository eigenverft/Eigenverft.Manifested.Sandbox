<#
    Eigenverft.Manifested.Sandbox.PackageModel.PathRegistration
#>

function Get-PackageModelPathRegistrationSourcePath {
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
        [psobject]$PackageModelResult,

        [string]$InstallDirectoryOverride
    )

    $install = $PackageModelResult.Package.install
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
        throw "PackageModel pathRegistration requires source.kind and source.value when pathRegistration.mode is not 'none'."
    }

    $baseInstallDirectory = if (-not [string]::IsNullOrWhiteSpace($InstallDirectoryOverride)) {
        $InstallDirectoryOverride
    }
    else {
        $PackageModelResult.InstallDirectory
    }

    switch -Exact ($sourceKind) {
        'commandEntryPoint' {
            foreach ($entryPoint in @($PackageModelResult.PackageModelConfig.Definition.providedTools.commands)) {
                if ([string]::Equals([string]$entryPoint.name, $sourceValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return (Join-Path $baseInstallDirectory (([string]$entryPoint.relativePath) -replace '/', '\'))
                }
            }
            throw "PackageModel pathRegistration source commandEntryPoint '$sourceValue' was not found in providedTools.commands."
        }
        'appEntryPoint' {
            foreach ($entryPoint in @($PackageModelResult.PackageModelConfig.Definition.providedTools.apps)) {
                if ([string]::Equals([string]$entryPoint.name, $sourceValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return (Join-Path $baseInstallDirectory (([string]$entryPoint.relativePath) -replace '/', '\'))
                }
            }
            throw "PackageModel pathRegistration source appEntryPoint '$sourceValue' was not found in providedTools.apps."
        }
        'installRelativeDirectory' {
            return (Join-Path $baseInstallDirectory (($sourceValue) -replace '/', '\'))
        }
        'shim' {
            throw "PackageModel pathRegistration source kind 'shim' is reserved but not implemented yet."
        }
        default {
            throw "Unsupported PackageModel pathRegistration source kind '$sourceKind'."
        }
    }
}

function Test-PackageModelShouldApplyPathRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    return ([string]$PackageModelResult.InstallOrigin) -in @('PackageModelInstalled', 'PackageModelReused')
}

function Get-PackageModelPathRegistrationCleanupDirectories {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    $currentInstallDirectory = Get-NormalizedPathEntry -PathEntry ([string]$PackageModelResult.InstallDirectory)
    $cleanupDirectories = New-Object System.Collections.Generic.List[string]
    $candidateInstallDirectories = New-Object System.Collections.Generic.List[string]

    if ($PackageModelResult.ExistingPackage -and
        [string]::Equals([string]$PackageModelResult.ExistingPackage.Classification, 'PackageModelOwned', [System.StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::IsNullOrWhiteSpace([string]$PackageModelResult.ExistingPackage.InstallDirectory)) {
        $candidateInstallDirectories.Add([string]$PackageModelResult.ExistingPackage.InstallDirectory) | Out-Null
    }

    if ($PackageModelResult.Ownership -and
        $PackageModelResult.Ownership.OwnershipRecord -and
        $PackageModelResult.Ownership.OwnershipRecord.PSObject.Properties['installDirectory'] -and
        -not [string]::IsNullOrWhiteSpace([string]$PackageModelResult.Ownership.OwnershipRecord.installDirectory)) {
        $candidateInstallDirectories.Add([string]$PackageModelResult.Ownership.OwnershipRecord.installDirectory) | Out-Null
    }

    foreach ($candidateInstallDirectory in @($candidateInstallDirectories.ToArray())) {
        $normalizedCandidateInstallDirectory = Get-NormalizedPathEntry -PathEntry $candidateInstallDirectory
        if ([string]::IsNullOrWhiteSpace($normalizedCandidateInstallDirectory) -or
            [string]::Equals($normalizedCandidateInstallDirectory, $currentInstallDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $candidateSourcePath = Get-PackageModelPathRegistrationSourcePath -PackageModelResult $PackageModelResult -InstallDirectoryOverride $candidateInstallDirectory
        $candidateSourceKind = if ($PackageModelResult.Package.install.pathRegistration.source.PSObject.Properties['kind']) {
            [string]$PackageModelResult.Package.install.pathRegistration.source.kind
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

function Register-PackageModelPath {
<#
.SYNOPSIS
Applies PackageModel PATH registration for a validated install.

.DESCRIPTION
Updates process and persisted PATH scopes according to install.pathRegistration.
User mode updates Process and User PATH. Machine mode updates Process and
Machine PATH. None skips registration. PackageModel only writes PATH entries
for PackageModel-owned outcomes and only cleans stale PackageModel-owned paths
for the same install slot.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    $install = $PackageModelResult.Package.install
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
        if ($PackageModelResult.PSObject.Properties['PathRegistration']) {
            $PackageModelResult.PathRegistration = $pathRegistrationResult
        }
        else {
            $PackageModelResult | Add-Member -MemberType NoteProperty -Name PathRegistration -Value $pathRegistrationResult
        }
        Write-PackageModelExecutionMessage -Message '[STATE] PATH registration skipped because mode is none.'
        return $PackageModelResult
    }

    if ($mode -notin @('user', 'machine')) {
        throw "Unsupported PackageModel pathRegistration.mode '$mode'."
    }

    if (-not (Test-PackageModelShouldApplyPathRegistration -PackageModelResult $PackageModelResult)) {
        $pathRegistrationResult = [pscustomobject]@{
            Status             = 'SkippedNotPackageModelOwned'
            Mode               = $mode
            SourceKind         = $sourceKind
            SourceValue        = $sourceValue
            SourcePath         = $null
            RegisteredPath     = $null
            CleanupDirectories = @()
            CleanedTargets     = @()
            UpdatedTargets     = @()
        }
        if ($PackageModelResult.PSObject.Properties['PathRegistration']) {
            $PackageModelResult.PathRegistration = $pathRegistrationResult
        }
        else {
            $PackageModelResult | Add-Member -MemberType NoteProperty -Name PathRegistration -Value $pathRegistrationResult
        }

        Write-PackageModelExecutionMessage -Message ("[STATE] PATH registration skipped because installOrigin '{0}' is not PackageModel-owned." -f [string]$PackageModelResult.InstallOrigin)
        return $PackageModelResult
    }

    $sourcePath = Get-PackageModelPathRegistrationSourcePath -PackageModelResult $PackageModelResult
    if ([string]::IsNullOrWhiteSpace($sourcePath) -or -not (Test-Path -LiteralPath $sourcePath)) {
        throw "PackageModel PATH registration source path '$sourcePath' was not found."
    }

    $registeredPath = Resolve-PathRegistrationDirectory -SourcePath $sourcePath -SourceKind $sourceKind
    $cleanupDirectories = @(Get-PackageModelPathRegistrationCleanupDirectories -PackageModelResult $PackageModelResult)
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
    if ($PackageModelResult.PSObject.Properties['PathRegistration']) {
        $PackageModelResult.PathRegistration = $pathRegistrationResult
    }
    else {
        $PackageModelResult | Add-Member -MemberType NoteProperty -Name PathRegistration -Value $pathRegistrationResult
    }

    Write-PackageModelExecutionMessage -Message ("[STATE] PATH registration resolved source kind='{0}' value='{1}' to '{2}'." -f $sourceKind, $sourceValue, $registeredPath)
    if ($cleanupDirectories.Count -gt 0) {
        Write-PackageModelExecutionMessage -Message ("[STATE] PATH cleanup directories for this PackageModel install slot: {0}" -f ($cleanupDirectories -join ', '))
    }
    Write-PackageModelExecutionMessage -Message ("[ACTION] PATH registration status='{0}' mode='{1}' updatedTargets='{2}' cleanedTargets='{3}'." -f $PackageModelResult.PathRegistration.Status, $mode, $(if ($registrationResult.UpdatedTargets.Count -gt 0) { @($registrationResult.UpdatedTargets) -join ',' } else { '<none>' }), $(if ($registrationResult.CleanedTargets.Count -gt 0) { @($registrationResult.CleanedTargets) -join ',' } else { '<none>' }))

    return $PackageModelResult
}
