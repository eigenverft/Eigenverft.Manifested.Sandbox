<#
    Eigenverft.Manifested.Sandbox.Package.Ownership
#>

function Get-PackageInstallSlotId {
<#
.SYNOPSIS
Builds the logical Package install-slot id for a result.

.DESCRIPTION
Combines the definition id, release track, and flavor into the stable install
slot identity used by the package-state index.

.PARAMETER PackageResult
The current Package result object.

.EXAMPLE
Get-PackageInstallSlotId -PackageResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $definitionId = [string]$PackageResult.DefinitionId
    $releaseTrack = if ($PackageResult.Package -and $PackageResult.Package.PSObject.Properties['releaseTrack']) { [string]$PackageResult.Package.releaseTrack } else { [string]$PackageResult.ReleaseTrack }
    $flavor = if ($PackageResult.Package -and $PackageResult.Package.PSObject.Properties['flavor']) { [string]$PackageResult.Package.flavor } else { 'default' }
    return ('{0}:{1}:{2}' -f $definitionId, $releaseTrack, $flavor)
}

function Get-PackagePackageStateIndex {
<#
.SYNOPSIS
Loads the Package package-state index.

.DESCRIPTION
Returns the configured package-state index document, or an empty record set
when the index file does not exist yet.

.PARAMETER PackageConfig
The resolved Package config object.

.EXAMPLE
Get-PackagePackageStateIndex -PackageConfig $config
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageConfig
    )

    $indexPath = $PackageConfig.PackageStateIndexFilePath
    if ([string]::IsNullOrWhiteSpace($indexPath)) {
        throw 'Package package-state index path is not configured.'
    }

    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
        return [pscustomobject]@{
            Path    = $indexPath
            Records = @()
        }
    }

    $documentInfo = Read-PackageJsonDocument -Path $indexPath
    $records = if ($documentInfo.Document.PSObject.Properties['records']) { @($documentInfo.Document.records) } else { @() }
    return [pscustomobject]@{
        Path    = $documentInfo.Path
        Records = $records
    }
}

function Save-PackagePackageStateIndex {
<#
.SYNOPSIS
Writes the Package package-state index to disk.

.DESCRIPTION
Persists the normalized package-state index document to the configured index path.

.PARAMETER IndexPath
The target index file path.

.PARAMETER Records
The package-state records to persist.

.EXAMPLE
Save-PackagePackageStateIndex -IndexPath $path -Records $records
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$IndexPath,

        [Parameter(Mandatory = $true)]
        [object[]]$Records
    )

    $directoryPath = Split-Path -Parent $IndexPath
    if (-not [string]::IsNullOrWhiteSpace($directoryPath)) {
        $null = New-Item -ItemType Directory -Path $directoryPath -Force
    }

    [ordered]@{
        schemaVersion = 1
        records = @($Records)
    } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $IndexPath -Encoding UTF8
}

function Copy-PackageDefinitionToLocalRepository {
<#
.SYNOPSIS
Copies the loaded Package definition into the local repository cache.

.DESCRIPTION
Stores the original definition JSON file under the configured local repository
root using the source repository id and original filename. The copy stays a
plain package definition document.

.PARAMETER PackageResult
The current Package result object.

.EXAMPLE
Copy-PackageDefinitionToLocalRepository -PackageResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $config = $PackageResult.PackageConfig
    $sourcePath = [string]$config.DefinitionPath
    if ([string]::IsNullOrWhiteSpace($sourcePath) -or -not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Package definition source path '$sourcePath' is not available for local repository copy."
    }

    $repositoryId = if ($config.PSObject.Properties['DefinitionRepositoryId'] -and
        -not [string]::IsNullOrWhiteSpace([string]$config.DefinitionRepositoryId)) {
        [string]$config.DefinitionRepositoryId
    }
    else {
        Get-PackageDefaultRepositoryId
    }

    $definitionFileName = if ($config.PSObject.Properties['DefinitionFileName'] -and
        -not [string]::IsNullOrWhiteSpace([string]$config.DefinitionFileName)) {
        [string]$config.DefinitionFileName
    }
    else {
        Split-Path -Leaf $sourcePath
    }

    $localRepositoryRoot = if ($config.PSObject.Properties['LocalRepositoryRoot'] -and
        -not [string]::IsNullOrWhiteSpace([string]$config.LocalRepositoryRoot)) {
        [string]$config.LocalRepositoryRoot
    }
    else {
        Get-PackageDefaultLocalRepositoryRoot
    }

    $repositoryDirectory = [System.IO.Path]::GetFullPath((Join-Path $localRepositoryRoot $repositoryId))
    $null = New-Item -ItemType Directory -Path $repositoryDirectory -Force
    $localDefinitionPath = [System.IO.Path]::GetFullPath((Join-Path $repositoryDirectory $definitionFileName))
    Copy-FileToPath -SourcePath $sourcePath -TargetPath $localDefinitionPath -Overwrite | Out-Null

    return [pscustomobject]@{
        RepositoryId = $repositoryId
        FileName     = $definitionFileName
        SourcePath   = [System.IO.Path]::GetFullPath($sourcePath)
        LocalPath    = $localDefinitionPath
    }
}

function Get-PackageOwnershipRecord {
<#
.SYNOPSIS
Returns the ownership record for the current install slot and install directory.

.DESCRIPTION
Finds the best matching ownership record for a Package result by using the
logical install slot together with the discovered install directory.

.PARAMETER PackageResult
The current Package result object.

.EXAMPLE
Get-PackageOwnershipRecord -PackageResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $existingPackage = $PackageResult.ExistingPackage
    if (-not $existingPackage -or [string]::IsNullOrWhiteSpace($existingPackage.InstallDirectory)) {
        return $null
    }

    $index = Get-PackagePackageStateIndex -PackageConfig $PackageResult.PackageConfig
    $installSlotId = Get-PackageInstallSlotId -PackageResult $PackageResult
    $normalizedInstallDirectory = [System.IO.Path]::GetFullPath($existingPackage.InstallDirectory)
    foreach ($record in @($index.Records)) {
        if ([string]::Equals([string]$record.installSlotId, $installSlotId, [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals([string]$record.installDirectory, $normalizedInstallDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $record
        }
    }

    return $null
}

function Resolve-PackageOwnershipKindText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$OwnershipKind
    )

    switch -Exact ([string]$OwnershipKind) {
        'ManagedInstalled' { return 'PackageInstalled' }
        'ManagedReused' { return 'PackageInstalled' }
        default { return $OwnershipKind }
    }
}

function Classify-PackageExistingPackage {
<#
.SYNOPSIS
Classifies a discovered existing install against the package-state index.

.DESCRIPTION
Attaches ownership classification data from the package-state index to the
current existing install so later helpers can decide whether the install is
Package-owned, adopted, or external.

.PARAMETER PackageResult
The Package result object to enrich.

.EXAMPLE
Classify-PackageExistingPackage -PackageResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    if (-not $PackageResult.ExistingPackage) {
        $PackageResult.Ownership = [pscustomobject]@{
            IndexPath       = $PackageResult.PackageConfig.PackageStateIndexFilePath
            InstallSlotId   = Get-PackageInstallSlotId -PackageResult $PackageResult
            Classification  = 'NotFound'
            OwnershipRecord = $null
        }
        return $PackageResult
    }

    $record = Get-PackageOwnershipRecord -PackageResult $PackageResult
    $classification = if ($record -or [string]::Equals([string]$PackageResult.ExistingPackage.SearchKind, 'packageTargetInstallPath', [System.StringComparison]::OrdinalIgnoreCase)) {
        'PackageOwned'
    }
    else {
        'ExternalInstall'
    }
    $installSlotId = Get-PackageInstallSlotId -PackageResult $PackageResult
    $PackageResult.Ownership = [pscustomobject]@{
        IndexPath       = $PackageResult.PackageConfig.PackageStateIndexFilePath
        InstallSlotId   = $installSlotId
        Classification  = $classification
        OwnershipRecord = $record
    }
    $PackageResult.ExistingPackage.Classification = $classification
    $PackageResult.ExistingPackage.OwnershipRecord = $record
    $ownershipKindText = if ($record -and $record.PSObject.Properties['ownershipKind']) {
        Resolve-PackageOwnershipKindText -OwnershipKind ([string]$record.ownershipKind)
    }
    else {
        '<none>'
    }
    Write-PackageExecutionMessage -Message ("[STATE] Ownership classification for installSlotId '{0}' is '{1}' (ownershipKind='{2}')." -f $installSlotId, $classification, $ownershipKindText)

    return $PackageResult
}

function Update-PackageOwnershipRecord {
<#
.SYNOPSIS
Updates the package-state record after a Package run.

.DESCRIPTION
Writes or refreshes the package-state record for Package-owned installs,
Package-owned reuse, and adopted external installs. External installs that were ignored are not
written to the package-state index.

.PARAMETER PackageResult
The finalized Package result object.

.EXAMPLE
Update-PackageOwnershipRecord -PackageResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    if (-not $PackageResult.Validation -or -not $PackageResult.Validation.Accepted) {
        return $PackageResult
    }

    $ownershipKind = switch -Exact ([string]$PackageResult.InstallOrigin) {
        'PackageInstalled' { 'PackageInstalled'; break }
        'PackageReused' { 'PackageInstalled'; break }
        'PackageApplied' { 'PackageApplied'; break }
        'AdoptedExternal' { 'AdoptedExternal'; break }
        default { $null }
    }

    if ([string]::IsNullOrWhiteSpace($ownershipKind)) {
        return $PackageResult
    }

    $index = Get-PackagePackageStateIndex -PackageConfig $PackageResult.PackageConfig
    $normalizedInstallDirectory = if ([string]::IsNullOrWhiteSpace([string]$PackageResult.InstallDirectory)) {
        $null
    }
    else {
        [System.IO.Path]::GetFullPath($PackageResult.InstallDirectory)
    }
    $installSlotId = Get-PackageInstallSlotId -PackageResult $PackageResult
    $definitionCopy = Copy-PackageDefinitionToLocalRepository -PackageResult $PackageResult
    $records = @(
        foreach ($record in @($index.Records)) {
            $sameInstallSlot = [string]::Equals([string]$record.installSlotId, $installSlotId, [System.StringComparison]::OrdinalIgnoreCase)
            $sameInstallDirectory = (-not [string]::IsNullOrWhiteSpace([string]$normalizedInstallDirectory)) -and
                [string]::Equals([string]$record.installDirectory, $normalizedInstallDirectory, [System.StringComparison]::OrdinalIgnoreCase)
            if (-not $sameInstallSlot -and -not $sameInstallDirectory) {
                $record
            }
        }
    )

    $newRecord = [pscustomobject]@{
        installSlotId   = $installSlotId
        definitionId    = $PackageResult.DefinitionId
        definitionRepositoryId = $definitionCopy.RepositoryId
        definitionFileName = $definitionCopy.FileName
        definitionSourcePath = $definitionCopy.SourcePath
        definitionLocalPath = $definitionCopy.LocalPath
        releaseTrack    = if ($PackageResult.Package -and $PackageResult.Package.PSObject.Properties['releaseTrack']) { [string]$PackageResult.Package.releaseTrack } else { [string]$PackageResult.ReleaseTrack }
        flavor          = if ($PackageResult.Package -and $PackageResult.Package.PSObject.Properties['flavor']) { [string]$PackageResult.Package.flavor } else { $null }
        currentReleaseId = $PackageResult.PackageId
        currentVersion  = $PackageResult.PackageVersion
        installDirectory = $normalizedInstallDirectory
        ownershipKind   = $ownershipKind
        updatedAtUtc    = [DateTime]::UtcNow.ToString('o')
    }
    $records += $newRecord

    Save-PackagePackageStateIndex -IndexPath $index.Path -Records $records

    $PackageResult.Ownership = [pscustomobject]@{
        IndexPath       = $index.Path
        InstallSlotId   = $installSlotId
        Classification  = if ($ownershipKind -eq 'AdoptedExternal') { 'AdoptedExternal' } else { 'PackageOwned' }
        OwnershipRecord = $newRecord
    }

    Write-PackageExecutionMessage -Message ("[STATE] Updated package-state record for installSlotId '{0}' with ownershipKind='{1}' at '{2}'." -f $installSlotId, $ownershipKind, $index.Path)

    return $PackageResult
}

