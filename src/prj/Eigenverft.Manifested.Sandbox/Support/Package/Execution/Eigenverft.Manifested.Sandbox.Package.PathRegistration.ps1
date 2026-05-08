<#
    Eigenverft.Manifested.Sandbox.Package.PathRegistration
#>

function Add-PackagePathCleanupDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$CleanupDirectories,

        [AllowNull()]
        [string]$DirectoryPath
    )

    $normalizedDirectoryPath = Get-NormalizedPathEntry -PathEntry $DirectoryPath
    if ([string]::IsNullOrWhiteSpace($normalizedDirectoryPath)) {
        return
    }

    if ($normalizedDirectoryPath -notin @($CleanupDirectories.ToArray())) {
        $CleanupDirectories.Add($normalizedDirectoryPath) | Out-Null
    }
}

function Get-PackagePathRegistrationSourceValues {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [psobject]$Source
    )

    $values = New-Object System.Collections.Generic.List[string]
    if ($Source -and $Source.PSObject.Properties['value'] -and
        -not [string]::IsNullOrWhiteSpace([string]$Source.value)) {
        $values.Add([string]$Source.value) | Out-Null
    }

    if ($Source -and $Source.PSObject.Properties['values'] -and $null -ne $Source.values) {
        foreach ($value in @($Source.values)) {
            $textValue = ([string]$value).Trim()
            if ([string]::IsNullOrWhiteSpace($textValue)) {
                continue
            }
            if ($textValue -notin @($values.ToArray())) {
                $values.Add($textValue) | Out-Null
            }
        }
    }

    return @($values.ToArray())
}

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

    $install = Get-PackageEffectiveReleaseAssignedBlock -Release $PackageResult.Package
    if (-not $install -or -not $install.PSObject.Properties['pathRegistration'] -or $null -eq $install.pathRegistration) {
        return $null
    }

    $pathRegistration = $install.pathRegistration
    if (-not $pathRegistration.PSObject.Properties['source'] -or $null -eq $pathRegistration.source) {
        return $null
    }

    $source = $pathRegistration.source
    $sourceKind = if ($source.PSObject.Properties['kind']) { [string]$source.kind } else { $null }
    $sourceValues = @(Get-PackagePathRegistrationSourceValues -Source $source)
    $sourceValue = if ($sourceValues.Count -gt 0) { [string]$sourceValues[0] } else { $null }
    if ([string]::IsNullOrWhiteSpace($sourceKind) -or $sourceValues.Count -eq 0) {
        throw "Package pathRegistration requires source.kind and source.value or source.values when pathRegistration.mode is not 'none'."
    }

    $baseInstallDirectory = if (-not [string]::IsNullOrWhiteSpace($InstallDirectoryOverride)) {
        $InstallDirectoryOverride
    }
    else {
        $PackageResult.InstallDirectory
    }

    switch -Exact ($sourceKind) {
        'commandEntryPoint' {
            if ($sourceValues.Count -gt 1) {
                throw "Package pathRegistration source kind 'commandEntryPoint' supports only one source value."
            }
            $sourcePath = Resolve-PackageProvidedToolPath -Definition $PackageResult.PackageConfig.Definition -ToolKind 'commands' -Name $sourceValue -InstallDirectory $baseInstallDirectory
            if (-not [string]::IsNullOrWhiteSpace($sourcePath)) {
                return $sourcePath
            }
            throw "Package pathRegistration source commandEntryPoint '$sourceValue' was not found in providedTools.commands."
        }
        'appEntryPoint' {
            if ($sourceValues.Count -gt 1) {
                throw "Package pathRegistration source kind 'appEntryPoint' supports only one source value."
            }
            $sourcePath = Resolve-PackageProvidedToolPath -Definition $PackageResult.PackageConfig.Definition -ToolKind 'apps' -Name $sourceValue -InstallDirectory $baseInstallDirectory
            if (-not [string]::IsNullOrWhiteSpace($sourcePath)) {
                return $sourcePath
            }
            throw "Package pathRegistration source appEntryPoint '$sourceValue' was not found in providedTools.apps."
        }
        'installRelativeDirectory' {
            if ($sourceValues.Count -gt 1) {
                throw "Package pathRegistration source kind 'installRelativeDirectory' supports only one source value."
            }
            return (Join-Path $baseInstallDirectory (($sourceValue) -replace '/', '\'))
        }
        'shim' {
            if (-not [string]::IsNullOrWhiteSpace($InstallDirectoryOverride)) {
                return (Get-PackageCommandShimPath -PackageResult $PackageResult -CommandName $sourceValues[0])
            }

            $shimResults = @(
                foreach ($commandName in $sourceValues) {
                    New-PackageCommandShim -PackageResult $PackageResult -CommandName $commandName
                }
            )
            return $shimResults[0].ShimPath
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
    $assignedForPath = Get-PackageEffectiveReleaseAssignedBlock -Release $PackageResult.Package
    if (-not $assignedForPath -or -not $assignedForPath.PSObject.Properties['pathRegistration'] -or $null -eq $assignedForPath.pathRegistration) {
        return @()
    }
    $currentSource = $assignedForPath.pathRegistration.source
    $currentSourceKind = if ($currentSource.PSObject.Properties['kind']) {
        [string]$assignedForPath.pathRegistration.source.kind
    }
    else {
        $null
    }
    $currentSourceValues = @(Get-PackagePathRegistrationSourceValues -Source $currentSource)

    if ($PackageResult.ExistingPackage -and
        [string]::Equals([string]$PackageResult.ExistingPackage.Classification, 'PackageTarget', [System.StringComparison]::OrdinalIgnoreCase) -and
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

        if ([string]::Equals($currentSourceKind, 'shim', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $candidateSourcePath = Get-PackagePathRegistrationSourcePath -PackageResult $PackageResult -InstallDirectoryOverride $candidateInstallDirectory
        $candidateSourceKind = $currentSourceKind
        $candidateRegisteredDirectory = Resolve-PathRegistrationDirectory -SourcePath $candidateSourcePath -SourceKind $candidateSourceKind
        Add-PackagePathCleanupDirectory -CleanupDirectories $cleanupDirectories -DirectoryPath $candidateRegisteredDirectory
    }

    if ([string]::Equals($currentSourceKind, 'shim', [System.StringComparison]::OrdinalIgnoreCase) -and
        $currentSourceValues.Count -gt 0) {
        $directCleanupInstallDirectories = New-Object System.Collections.Generic.List[string]
        $directCandidateInstallDirectories = @($candidateInstallDirectories.ToArray()) + @([string]$PackageResult.InstallDirectory)
        foreach ($candidateInstallDirectory in $directCandidateInstallDirectories) {
            if ([string]::IsNullOrWhiteSpace($candidateInstallDirectory)) {
                continue
            }
            $normalizedCandidateInstallDirectory = Get-NormalizedPathEntry -PathEntry $candidateInstallDirectory
            if ([string]::IsNullOrWhiteSpace($normalizedCandidateInstallDirectory) -or
                $normalizedCandidateInstallDirectory -in @($directCleanupInstallDirectories.ToArray())) {
                continue
            }
            $directCleanupInstallDirectories.Add($normalizedCandidateInstallDirectory) | Out-Null
        }

        foreach ($candidateInstallDirectory in @($directCleanupInstallDirectories.ToArray())) {
            foreach ($currentSourceValue in $currentSourceValues) {
                $directCommandPath = Resolve-PackageProvidedToolPath -Definition $PackageResult.PackageConfig.Definition -ToolKind 'commands' -Name $currentSourceValue -InstallDirectory $candidateInstallDirectory
                if ([string]::IsNullOrWhiteSpace($directCommandPath)) {
                    continue
                }
                $directCommandDirectory = Resolve-PathRegistrationDirectory -SourcePath $directCommandPath -SourceKind 'commandEntryPoint'
                Add-PackagePathCleanupDirectory -CleanupDirectories $cleanupDirectories -DirectoryPath $directCommandDirectory
            }
        }
    }

    return @($cleanupDirectories.ToArray())
}

function Register-PackagePath {
<#
.SYNOPSIS
Applies Package PATH registration for a validated install.

.DESCRIPTION
Updates process and persisted PATH scopes according to assigned.pathRegistration.
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

    $install = Get-PackageEffectiveReleaseAssignedBlock -Release $PackageResult.Package
    $pathRegistration = if ($install -and $install.PSObject.Properties['pathRegistration']) { $install.pathRegistration } else { $null }
    $mode = if ($pathRegistration -and $pathRegistration.PSObject.Properties['mode'] -and -not [string]::IsNullOrWhiteSpace([string]$pathRegistration.mode)) {
        ([string]$pathRegistration.mode).ToLowerInvariant()
    }
    else {
        'none'
    }

    $source = if ($pathRegistration -and $pathRegistration.PSObject.Properties['source']) { $pathRegistration.source } else { $null }
    $sourceKind = if ($source -and $source.PSObject.Properties['kind']) { [string]$source.kind } else { $null }
    $sourceValues = @(Get-PackagePathRegistrationSourceValues -Source $source)
    $sourceValue = if ($sourceValues.Count -gt 0) { $sourceValues -join ',' } else { $null }

    if ($mode -eq 'none') {
        $pathRegistrationResult = [pscustomobject]@{
            Status             = 'Skipped'
            Mode               = 'none'
            SourceKind         = $sourceKind
            SourceValue        = $sourceValue
            SourceValues       = @($sourceValues)
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
            SourceValues       = @($sourceValues)
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
        SourceValues       = @($sourceValues)
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

