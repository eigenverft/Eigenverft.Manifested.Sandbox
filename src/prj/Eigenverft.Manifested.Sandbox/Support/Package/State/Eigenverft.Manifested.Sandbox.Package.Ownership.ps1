<#
    Eigenverft.Manifested.Sandbox.Package.Ownership
#>

function Get-PackageInstallSlotId {
<#
.SYNOPSIS
Builds the logical Package install-slot id for a result.

.DESCRIPTION
Combines the definition id, release track, and artifact distribution variant
into the stable install slot identity used by the package inventory.

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
    $artifactDistributionVariant = if ($PackageResult.Package -and $PackageResult.Package.PSObject.Properties['artifactDistributionVariant']) { [string]$PackageResult.Package.artifactDistributionVariant } else { 'default' }
    return ('{0}:{1}:{2}' -f $definitionId, $releaseTrack, $artifactDistributionVariant)
}

function Assert-PackageInventoryRecordOptionalExtensions {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Record
    )

    if ($null -eq $Record) {
        return
    }

    if ($Record.PSObject.Properties['dependencyInstallSlotIds'] -and $null -ne $Record.dependencyInstallSlotIds) {
        $raw = $Record.dependencyInstallSlotIds
        if ($raw -is [string]) {
            throw "Package inventory record for installSlotId '$([string]$Record.installSlotId)' has invalid dependencyInstallSlotIds (expected a JSON array of strings, not a single string)."
        }

        foreach ($entry in @($raw)) {
            if ($null -eq $entry) {
                continue
            }

            if ($entry -isnot [string]) {
                throw "Package inventory record for installSlotId '$([string]$Record.installSlotId)' has invalid dependencyInstallSlotIds entry (expected string)."
            }
        }
    }
}

function Get-PackageInventory {
<#
.SYNOPSIS
Loads the Package inventory.

.DESCRIPTION
Returns the configured package inventory document, or an empty record set
when the index file does not exist yet.

.PARAMETER PackageConfig
The resolved Package config object.

.EXAMPLE
Get-PackageInventory -PackageConfig $config
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageConfig
    )

    $indexPath = $PackageConfig.PackageInventoryFilePath
    if ([string]::IsNullOrWhiteSpace($indexPath)) {
        throw 'Package inventory path is not configured.'
    }

    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
        return [pscustomobject]@{
            Path    = $indexPath
            Records = @()
        }
    }

    $documentInfo = Read-PackageJsonDocument -Path $indexPath
    $records = if ($documentInfo.Document.PSObject.Properties['records']) { @($documentInfo.Document.records) } else { @() }
    foreach ($record in @($records)) {
        Assert-PackageInventoryRecordOptionalExtensions -Record $record
    }

    return [pscustomobject]@{
        Path    = $documentInfo.Path
        Records = $records
    }
}

function Save-PackageInventory {
<#
.SYNOPSIS
Writes the Package inventory to disk.

.DESCRIPTION
Persists the normalized package inventory document to the configured inventory path.

.PARAMETER InventoryPath
The target inventory file path.

.PARAMETER Records
The package inventory records to persist.

.EXAMPLE
Save-PackageInventory -InventoryPath $path -Records $records
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InventoryPath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Records
    )

    $directoryPath = Split-Path -Parent $InventoryPath
    if (-not [string]::IsNullOrWhiteSpace($directoryPath)) {
        $null = New-Item -ItemType Directory -Path $directoryPath -Force
    }

    [ordered]@{
        schemaVersion = 1
        records = @($Records)
    } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $InventoryPath -Encoding UTF8
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

    $sourceHash = Get-PackageFileSha256 -Path $sourcePath
    $snapshotHash = Get-PackageFileSha256 -Path $localDefinitionPath

    return [pscustomobject]@{
        RepositoryId  = $repositoryId
        FileName      = $definitionFileName
        SourceKind    = if ($config.PSObject.Properties['DefinitionSourceKind']) { [string]$config.DefinitionSourceKind } else { $null }
        SourcePath    = [System.IO.Path]::GetFullPath($sourcePath)
        SourceHash    = $sourceHash
        SnapshotPath  = $localDefinitionPath
        SnapshotHash  = $snapshotHash
        ResolvedAtUtc = if ($config.PSObject.Properties['DefinitionResolvedAtUtc'] -and -not [string]::IsNullOrWhiteSpace([string]$config.DefinitionResolvedAtUtc)) { [string]$config.DefinitionResolvedAtUtc } else { [DateTime]::UtcNow.ToString('o') }
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

    $index = Get-PackageInventory -PackageConfig $PackageResult.PackageConfig
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

function Set-PackageExistingPackage {
<#
.SYNOPSIS
Classifies a discovered existing install against the package inventory.

.DESCRIPTION
Attaches ownership classification data from the package inventory to the
current existing install so later helpers can decide whether the install is
Package-owned, adopted, or external.

.PARAMETER PackageResult
The Package result object to enrich.

.EXAMPLE
Set-PackageExistingPackage -PackageResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    if (-not $PackageResult.ExistingPackage) {
        $PackageResult.Ownership = [pscustomobject]@{
            InventoryPath   = $PackageResult.PackageConfig.PackageInventoryFilePath
            InstallSlotId   = Get-PackageInstallSlotId -PackageResult $PackageResult
            Classification  = 'NotFound'
            OwnershipRecord = $null
        }
        return $PackageResult
    }

    $record = Get-PackageOwnershipRecord -PackageResult $PackageResult
    $classification = if ($record -or [string]::Equals([string]$PackageResult.ExistingPackage.SearchKind, 'packageTargetInstallPath', [System.StringComparison]::OrdinalIgnoreCase)) {
        'PackageTarget'
    }
    else {
        'ExternalInstall'
    }
    $installSlotId = Get-PackageInstallSlotId -PackageResult $PackageResult
    $PackageResult.Ownership = [pscustomobject]@{
        InventoryPath   = $PackageResult.PackageConfig.PackageInventoryFilePath
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

function Update-PackageInventoryRecord {
<#
.SYNOPSIS
Updates the package inventory record after a Package run.

.DESCRIPTION
Writes or refreshes the package inventory record for Package-owned installs,
Package-owned reuse, and adopted external installs. External installs that were ignored are not
written to the package inventory.

.PARAMETER PackageResult
The finalized Package result object.

.EXAMPLE
Update-PackageInventoryRecord -PackageResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    if (-not $PackageResult.Readiness -or -not $PackageResult.Readiness.Accepted) {
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

    $index = Get-PackageInventory -PackageConfig $PackageResult.PackageConfig
    $normalizedInstallDirectory = if ([string]::IsNullOrWhiteSpace([string]$PackageResult.InstallDirectory)) {
        $null
    }
    else {
        [System.IO.Path]::GetFullPath($PackageResult.InstallDirectory)
    }
    $installSlotId = Get-PackageInstallSlotId -PackageResult $PackageResult
    $definitionCopy = Copy-PackageDefinitionToLocalRepository -PackageResult $PackageResult
    $pathRegistrationRecord = $null
    if ($PackageResult.PSObject.Properties['PathRegistration'] -and $null -ne $PackageResult.PathRegistration) {
        $pathRegistrationRecord = [pscustomobject]@{
            mode           = [string]$PackageResult.PathRegistration.Mode
            sourceKind     = [string]$PackageResult.PathRegistration.SourceKind
            sourceValue    = [string]$PackageResult.PathRegistration.SourceValue
            sourceValues   = @($PackageResult.PathRegistration.SourceValues)
            sourcePath     = [string]$PackageResult.PathRegistration.SourcePath
            registeredPath = [string]$PackageResult.PathRegistration.RegisteredPath
            status         = [string]$PackageResult.PathRegistration.Status
        }
    }
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

    $dependencyInstallSlotIds = @(
        foreach ($dependencyRow in @($PackageResult.Dependencies)) {
            $dependencyResult = if ($dependencyRow.PSObject.Properties['Result']) { $dependencyRow.Result } else { $null }
            if (-not $dependencyResult) {
                continue
            }

            Get-PackageInstallSlotId -PackageResult $dependencyResult
        }
    ) | Select-Object -Unique

    $newRecord = [pscustomobject]@{
        installSlotId   = $installSlotId
        definitionId    = $PackageResult.DefinitionId
        definitionRepositoryId = $definitionCopy.RepositoryId
        definitionFileName = $definitionCopy.FileName
        definitionSourceKind = $definitionCopy.SourceKind
        definitionSourcePath = $definitionCopy.SourcePath
        definitionSourceHash = $definitionCopy.SourceHash
        definitionSnapshotPath = $definitionCopy.SnapshotPath
        definitionSnapshotHash = $definitionCopy.SnapshotHash
        definitionResolvedAtUtc = $definitionCopy.ResolvedAtUtc
        releaseTrack    = if ($PackageResult.Package -and $PackageResult.Package.PSObject.Properties['releaseTrack']) { [string]$PackageResult.Package.releaseTrack } else { [string]$PackageResult.ReleaseTrack }
        artifactDistributionVariant = if ($PackageResult.Package -and $PackageResult.Package.PSObject.Properties['artifactDistributionVariant']) { [string]$PackageResult.Package.artifactDistributionVariant } else { $null }
        currentReleaseId = $PackageResult.PackageId
        currentVersion  = $PackageResult.PackageVersion
        installDirectory = $normalizedInstallDirectory
        ownershipKind   = $ownershipKind
        pathRegistration = $pathRegistrationRecord
        dependencyInstallSlotIds = @($dependencyInstallSlotIds)
        updatedAtUtc    = [DateTime]::UtcNow.ToString('o')
    }
    $records += $newRecord

    Save-PackageInventory -InventoryPath $index.Path -Records $records

    $PackageResult.Ownership = [pscustomobject]@{
        InventoryPath   = $index.Path
        InstallSlotId   = $installSlotId
        Classification  = if ($ownershipKind -eq 'AdoptedExternal') { 'AdoptedExternal' } else { 'PackageTarget' }
        OwnershipRecord = $newRecord
    }

    Write-PackageExecutionMessage -Message ("[STATE] Updated package inventory record for installSlotId '{0}' with ownershipKind='{1}' at '{2}'." -f $installSlotId, $ownershipKind, $index.Path)

    return $PackageResult
}

function Remove-PackageInventoryRecordForInstallSlot {
<#
.SYNOPSIS
Removes the inventory record for the current Package install slot.

.DESCRIPTION
Loads the inventory, drops records matching installSlotId (or the same
normalized install directory when present), and persists the document.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $index = Get-PackageInventory -PackageConfig $PackageResult.PackageConfig
    $installSlotId = Get-PackageInstallSlotId -PackageResult $PackageResult
    $normalizedInstallDirectory = if ([string]::IsNullOrWhiteSpace([string]$PackageResult.InstallDirectory)) {
        $null
    }
    else {
        [System.IO.Path]::GetFullPath([string]$PackageResult.InstallDirectory)
    }

    $records = @(
        foreach ($record in @($index.Records)) {
            $sameSlot = [string]::Equals([string]$record.installSlotId, $installSlotId, [System.StringComparison]::OrdinalIgnoreCase)
            $sameDir = (-not [string]::IsNullOrWhiteSpace($normalizedInstallDirectory)) -and
                [string]::Equals([string]$record.installDirectory, $normalizedInstallDirectory, [System.StringComparison]::OrdinalIgnoreCase)
            if (-not $sameSlot -and -not $sameDir) {
                $record
            }
        }
    )

    Save-PackageInventory -InventoryPath $index.Path -Records $records
    Write-PackageExecutionMessage -Message ("[ACTION] Removed package inventory record for installSlotId '{0}'." -f $installSlotId)

    return $PackageResult
}
