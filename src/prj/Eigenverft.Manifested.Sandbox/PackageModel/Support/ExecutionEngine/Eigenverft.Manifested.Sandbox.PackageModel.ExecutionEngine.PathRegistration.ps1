<#
    Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.PathRegistration
#>

function Get-PackageModelEnvironmentVariableValue {
<#
.SYNOPSIS
Reads an environment variable for one target scope.

.DESCRIPTION
Returns the current environment variable value for the requested Process, User,
or Machine target.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Process', 'User', 'Machine')]
        [string]$Target
    )

    return [Environment]::GetEnvironmentVariable($Name, $Target)
}

function Set-PackageModelEnvironmentVariableValue {
<#
.SYNOPSIS
Writes an environment variable for one target scope.

.DESCRIPTION
Persists the requested environment variable value to the Process, User, or
Machine target scope.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowNull()]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Process', 'User', 'Machine')]
        [string]$Target
    )

    [Environment]::SetEnvironmentVariable($Name, $Value, $Target)
}

function Get-PackageModelNormalizedPathEntry {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$PathEntry
    )

    if ([string]::IsNullOrWhiteSpace($PathEntry)) {
        return $null
    }

    $expandedEntry = [Environment]::ExpandEnvironmentVariables($PathEntry.Trim()) -replace '/', '\'
    if ([string]::IsNullOrWhiteSpace($expandedEntry)) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($expandedEntry)) {
        try {
            return [System.IO.Path]::GetFullPath($expandedEntry).TrimEnd('\')
        }
        catch {
            return $expandedEntry.TrimEnd('\')
        }
    }

    return $expandedEntry.TrimEnd('\')
}

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

function Resolve-PackageModelPathRegistrationDirectory {
<#
.SYNOPSIS
Resolves the directory that should be added to PATH.

.DESCRIPTION
Turns a raw source path into the concrete directory entry that should be
registered in PATH. Existing files resolve to their parent directory.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [string]$SourceKind
    )

    $resolvedSourcePath = [System.IO.Path]::GetFullPath($SourcePath)
    if ($SourceKind -in @('commandEntryPoint', 'appEntryPoint', 'shim')) {
        return [System.IO.Path]::GetFullPath((Split-Path -Parent $resolvedSourcePath))
    }

    if (Test-Path -LiteralPath $resolvedSourcePath -PathType Leaf) {
        return [System.IO.Path]::GetFullPath((Split-Path -Parent $resolvedSourcePath))
    }

    return [System.IO.Path]::GetFullPath($resolvedSourcePath)
}

function Add-PackageModelPathEntry {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$CurrentValue,

        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath
    )

    $normalizedTargetDirectory = Get-PackageModelNormalizedPathEntry -PathEntry $DirectoryPath
    $existingEntries = @()
    foreach ($entry in @(([string]$CurrentValue) -split ';')) {
        if ([string]::IsNullOrWhiteSpace($entry)) {
            continue
        }

        $existingEntries += $entry.Trim()
    }

    foreach ($entry in @($existingEntries)) {
        $normalizedEntry = Get-PackageModelNormalizedPathEntry -PathEntry $entry
        if ([string]::Equals($normalizedEntry, $normalizedTargetDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{
                Value   = ($existingEntries -join ';')
                Changed = $false
            }
        }
    }

    $updatedEntries = @($existingEntries) + @($DirectoryPath)
    return [pscustomobject]@{
        Value   = ($updatedEntries -join ';')
        Changed = $true
    }
}

function Remove-PackageModelPathEntries {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$CurrentValue,

        [string[]]$DirectoryPaths
    )

    $normalizedDirectoriesToRemove = @(
        foreach ($directoryPath in @($DirectoryPaths)) {
            $normalizedDirectoryPath = Get-PackageModelNormalizedPathEntry -PathEntry $directoryPath
            if (-not [string]::IsNullOrWhiteSpace($normalizedDirectoryPath)) {
                $normalizedDirectoryPath
            }
        }
    )

    if (@($normalizedDirectoriesToRemove).Count -eq 0) {
        return [pscustomobject]@{
            Value          = [string]$CurrentValue
            Changed        = $false
            RemovedEntries = @()
        }
    }

    $filteredEntries = New-Object System.Collections.Generic.List[string]
    $removedEntries = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @(([string]$CurrentValue) -split ';')) {
        if ([string]::IsNullOrWhiteSpace($entry)) {
            continue
        }

        $trimmedEntry = $entry.Trim()
        $normalizedEntry = Get-PackageModelNormalizedPathEntry -PathEntry $trimmedEntry
        if ($normalizedEntry -and $normalizedEntry -in $normalizedDirectoriesToRemove) {
            $removedEntries.Add($trimmedEntry) | Out-Null
            continue
        }

        $filteredEntries.Add($trimmedEntry) | Out-Null
    }

    return [pscustomobject]@{
        Value          = (@($filteredEntries.ToArray()) -join ';')
        Changed        = ($removedEntries.Count -gt 0)
        RemovedEntries = @($removedEntries.ToArray())
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

    $currentInstallDirectory = Get-PackageModelNormalizedPathEntry -PathEntry ([string]$PackageModelResult.InstallDirectory)
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
        $normalizedCandidateInstallDirectory = Get-PackageModelNormalizedPathEntry -PathEntry $candidateInstallDirectory
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
        $candidateRegisteredDirectory = Resolve-PackageModelPathRegistrationDirectory -SourcePath $candidateSourcePath -SourceKind $candidateSourceKind
        $normalizedCandidateRegisteredDirectory = Get-PackageModelNormalizedPathEntry -PathEntry $candidateRegisteredDirectory
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

    $registeredPath = Resolve-PackageModelPathRegistrationDirectory -SourcePath $sourcePath -SourceKind $sourceKind
    $cleanupDirectories = @(Get-PackageModelPathRegistrationCleanupDirectories -PackageModelResult $PackageModelResult)
    $targets = @('Process')
    if ($mode -eq 'user') {
        $targets += 'User'
    }
    elseif ($mode -eq 'machine') {
        $targets += 'Machine'
    }

    $updatedTargets = New-Object System.Collections.Generic.List[string]
    $cleanedTargets = New-Object System.Collections.Generic.List[string]
    foreach ($target in @($targets)) {
        $currentValue = Get-PackageModelEnvironmentVariableValue -Name 'Path' -Target $target
        $cleanupResult = Remove-PackageModelPathEntries -CurrentValue $currentValue -DirectoryPaths $cleanupDirectories
        $updateResult = Add-PackageModelPathEntry -CurrentValue $cleanupResult.Value -DirectoryPath $registeredPath
        if ($cleanupResult.Changed -or $updateResult.Changed) {
            Set-PackageModelEnvironmentVariableValue -Name 'Path' -Value $updateResult.Value -Target $target
            $updatedTargets.Add($target) | Out-Null
        }
        if ($cleanupResult.Changed) {
            $cleanedTargets.Add($target) | Out-Null
        }
    }

    $pathRegistrationResult = [pscustomobject]@{
        Status             = if ($updatedTargets.Count -gt 0) { 'Registered' } else { 'AlreadyRegistered' }
        Mode               = $mode
        SourceKind         = $sourceKind
        SourceValue        = $sourceValue
        SourcePath         = $sourcePath
        RegisteredPath     = $registeredPath
        CleanupDirectories = $cleanupDirectories
        CleanedTargets     = @($cleanedTargets.ToArray())
        UpdatedTargets     = @($updatedTargets.ToArray())
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
    Write-PackageModelExecutionMessage -Message ("[ACTION] PATH registration status='{0}' mode='{1}' updatedTargets='{2}' cleanedTargets='{3}'." -f $PackageModelResult.PathRegistration.Status, $mode, $(if ($updatedTargets.Count -gt 0) { @($updatedTargets.ToArray()) -join ',' } else { '<none>' }), $(if ($cleanedTargets.Count -gt 0) { @($cleanedTargets.ToArray()) -join ',' } else { '<none>' }))

    return $PackageModelResult
}
