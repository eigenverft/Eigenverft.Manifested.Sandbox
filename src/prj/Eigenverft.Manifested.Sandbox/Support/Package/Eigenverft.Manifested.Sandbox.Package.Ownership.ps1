<#
    Eigenverft.Manifested.Sandbox.Package.Ownership
#>

function Get-PackageModelInstallSlotId {
<#
.SYNOPSIS
Builds the logical PackageModel install-slot id for a result.

.DESCRIPTION
Combines the definition id, release track, and flavor into the stable install
slot identity used by the package-state index.

.PARAMETER PackageModelResult
The current PackageModel result object.

.EXAMPLE
Get-PackageModelInstallSlotId -PackageModelResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    $definitionId = [string]$PackageModelResult.DefinitionId
    $releaseTrack = if ($PackageModelResult.Package -and $PackageModelResult.Package.PSObject.Properties['releaseTrack']) { [string]$PackageModelResult.Package.releaseTrack } else { [string]$PackageModelResult.ReleaseTrack }
    $flavor = if ($PackageModelResult.Package -and $PackageModelResult.Package.PSObject.Properties['flavor']) { [string]$PackageModelResult.Package.flavor } else { 'default' }
    return ('{0}:{1}:{2}' -f $definitionId, $releaseTrack, $flavor)
}

function Get-PackageModelPackageStateIndex {
<#
.SYNOPSIS
Loads the PackageModel package-state index.

.DESCRIPTION
Returns the configured package-state index document, or an empty record set
when the index file does not exist yet.

.PARAMETER PackageModelConfig
The resolved PackageModel config object.

.EXAMPLE
Get-PackageModelPackageStateIndex -PackageModelConfig $config
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelConfig
    )

    $indexPath = $PackageModelConfig.PackageStateIndexFilePath
    if ([string]::IsNullOrWhiteSpace($indexPath)) {
        throw 'PackageModel package-state index path is not configured.'
    }

    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
        return [pscustomobject]@{
            Path    = $indexPath
            Records = @()
        }
    }

    $documentInfo = Read-PackageModelJsonDocument -Path $indexPath
    $records = if ($documentInfo.Document.PSObject.Properties['records']) { @($documentInfo.Document.records) } else { @() }
    return [pscustomobject]@{
        Path    = $documentInfo.Path
        Records = $records
    }
}

function Save-PackageModelPackageStateIndex {
<#
.SYNOPSIS
Writes the PackageModel package-state index to disk.

.DESCRIPTION
Persists the normalized package-state index document to the configured index path.

.PARAMETER IndexPath
The target index file path.

.PARAMETER Records
The package-state records to persist.

.EXAMPLE
Save-PackageModelPackageStateIndex -IndexPath $path -Records $records
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

function Copy-PackageModelDefinitionToLocalRepository {
<#
.SYNOPSIS
Copies the loaded PackageModel definition into the local repository cache.

.DESCRIPTION
Stores the original definition JSON file under the configured local repository
root using the source repository id and original filename. The copy stays a
plain package definition document.

.PARAMETER PackageModelResult
The current PackageModel result object.

.EXAMPLE
Copy-PackageModelDefinitionToLocalRepository -PackageModelResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    $config = $PackageModelResult.PackageModelConfig
    $sourcePath = [string]$config.DefinitionPath
    if ([string]::IsNullOrWhiteSpace($sourcePath) -or -not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "PackageModel definition source path '$sourcePath' is not available for local repository copy."
    }

    $repositoryId = if ($config.PSObject.Properties['DefinitionRepositoryId'] -and
        -not [string]::IsNullOrWhiteSpace([string]$config.DefinitionRepositoryId)) {
        [string]$config.DefinitionRepositoryId
    }
    else {
        Get-PackageModelDefaultRepositoryId
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
        Get-PackageModelDefaultLocalRepositoryRoot
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

function Get-PackageModelOwnershipRecord {
<#
.SYNOPSIS
Returns the ownership record for the current install slot and install directory.

.DESCRIPTION
Finds the best matching ownership record for a PackageModel result by using the
logical install slot together with the discovered install directory.

.PARAMETER PackageModelResult
The current PackageModel result object.

.EXAMPLE
Get-PackageModelOwnershipRecord -PackageModelResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    $existingPackage = $PackageModelResult.ExistingPackage
    if (-not $existingPackage -or [string]::IsNullOrWhiteSpace($existingPackage.InstallDirectory)) {
        return $null
    }

    $index = Get-PackageModelPackageStateIndex -PackageModelConfig $PackageModelResult.PackageModelConfig
    $installSlotId = Get-PackageModelInstallSlotId -PackageModelResult $PackageModelResult
    $normalizedInstallDirectory = [System.IO.Path]::GetFullPath($existingPackage.InstallDirectory)
    foreach ($record in @($index.Records)) {
        if ([string]::Equals([string]$record.installSlotId, $installSlotId, [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals([string]$record.installDirectory, $normalizedInstallDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $record
        }
    }

    return $null
}

function Resolve-PackageModelOwnershipKindText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$OwnershipKind
    )

    switch -Exact ([string]$OwnershipKind) {
        'ManagedInstalled' { return 'PackageModelInstalled' }
        'ManagedReused' { return 'PackageModelInstalled' }
        default { return $OwnershipKind }
    }
}

function Classify-PackageModelExistingPackage {
<#
.SYNOPSIS
Classifies a discovered existing install against the package-state index.

.DESCRIPTION
Attaches ownership classification data from the package-state index to the
current existing install so later helpers can decide whether the install is
PackageModel-owned, adopted, or external.

.PARAMETER PackageModelResult
The PackageModel result object to enrich.

.EXAMPLE
Classify-PackageModelExistingPackage -PackageModelResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    if (-not $PackageModelResult.ExistingPackage) {
        $PackageModelResult.Ownership = [pscustomobject]@{
            IndexPath       = $PackageModelResult.PackageModelConfig.PackageStateIndexFilePath
            InstallSlotId   = Get-PackageModelInstallSlotId -PackageModelResult $PackageModelResult
            Classification  = 'NotFound'
            OwnershipRecord = $null
        }
        return $PackageModelResult
    }

    $record = Get-PackageModelOwnershipRecord -PackageModelResult $PackageModelResult
    $classification = if ($record -or [string]::Equals([string]$PackageModelResult.ExistingPackage.SearchKind, 'packageModelTargetInstallPath', [System.StringComparison]::OrdinalIgnoreCase)) {
        'PackageModelOwned'
    }
    else {
        'ExternalInstall'
    }
    $installSlotId = Get-PackageModelInstallSlotId -PackageModelResult $PackageModelResult
    $PackageModelResult.Ownership = [pscustomobject]@{
        IndexPath       = $PackageModelResult.PackageModelConfig.PackageStateIndexFilePath
        InstallSlotId   = $installSlotId
        Classification  = $classification
        OwnershipRecord = $record
    }
    $PackageModelResult.ExistingPackage.Classification = $classification
    $PackageModelResult.ExistingPackage.OwnershipRecord = $record
    $ownershipKindText = if ($record -and $record.PSObject.Properties['ownershipKind']) {
        Resolve-PackageModelOwnershipKindText -OwnershipKind ([string]$record.ownershipKind)
    }
    else {
        '<none>'
    }
    Write-PackageModelExecutionMessage -Message ("[STATE] Ownership classification for installSlotId '{0}' is '{1}' (ownershipKind='{2}')." -f $installSlotId, $classification, $ownershipKindText)

    return $PackageModelResult
}

function Update-PackageModelOwnershipRecord {
<#
.SYNOPSIS
Updates the package-state record after a PackageModel run.

.DESCRIPTION
Writes or refreshes the package-state record for PackageModel-owned installs,
PackageModel-owned reuse, and adopted external installs. External installs that were ignored are not
written to the package-state index.

.PARAMETER PackageModelResult
The finalized PackageModel result object.

.EXAMPLE
Update-PackageModelOwnershipRecord -PackageModelResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    if (-not $PackageModelResult.Validation -or -not $PackageModelResult.Validation.Accepted) {
        return $PackageModelResult
    }

    $ownershipKind = switch -Exact ([string]$PackageModelResult.InstallOrigin) {
        'PackageModelInstalled' { 'PackageModelInstalled'; break }
        'PackageModelReused' { 'PackageModelInstalled'; break }
        'PackageModelApplied' { 'PackageModelApplied'; break }
        'AdoptedExternal' { 'AdoptedExternal'; break }
        default { $null }
    }

    if ([string]::IsNullOrWhiteSpace($ownershipKind)) {
        return $PackageModelResult
    }

    $index = Get-PackageModelPackageStateIndex -PackageModelConfig $PackageModelResult.PackageModelConfig
    $normalizedInstallDirectory = if ([string]::IsNullOrWhiteSpace([string]$PackageModelResult.InstallDirectory)) {
        $null
    }
    else {
        [System.IO.Path]::GetFullPath($PackageModelResult.InstallDirectory)
    }
    $installSlotId = Get-PackageModelInstallSlotId -PackageModelResult $PackageModelResult
    $definitionCopy = Copy-PackageModelDefinitionToLocalRepository -PackageModelResult $PackageModelResult
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
        definitionId    = $PackageModelResult.DefinitionId
        definitionRepositoryId = $definitionCopy.RepositoryId
        definitionFileName = $definitionCopy.FileName
        definitionSourcePath = $definitionCopy.SourcePath
        definitionLocalPath = $definitionCopy.LocalPath
        releaseTrack    = if ($PackageModelResult.Package -and $PackageModelResult.Package.PSObject.Properties['releaseTrack']) { [string]$PackageModelResult.Package.releaseTrack } else { [string]$PackageModelResult.ReleaseTrack }
        flavor          = if ($PackageModelResult.Package -and $PackageModelResult.Package.PSObject.Properties['flavor']) { [string]$PackageModelResult.Package.flavor } else { $null }
        currentReleaseId = $PackageModelResult.PackageId
        currentVersion  = $PackageModelResult.PackageVersion
        installDirectory = $normalizedInstallDirectory
        ownershipKind   = $ownershipKind
        updatedAtUtc    = [DateTime]::UtcNow.ToString('o')
    }
    $records += $newRecord

    Save-PackageModelPackageStateIndex -IndexPath $index.Path -Records $records

    $PackageModelResult.Ownership = [pscustomobject]@{
        IndexPath       = $index.Path
        InstallSlotId   = $installSlotId
        Classification  = if ($ownershipKind -eq 'AdoptedExternal') { 'AdoptedExternal' } else { 'PackageModelOwned' }
        OwnershipRecord = $newRecord
    }

    Write-PackageModelExecutionMessage -Message ("[STATE] Updated package-state record for installSlotId '{0}' with ownershipKind='{1}' at '{2}'." -f $installSlotId, $ownershipKind, $index.Path)

    return $PackageModelResult
}

