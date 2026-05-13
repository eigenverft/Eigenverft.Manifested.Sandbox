<#
    Eigenverft.Manifested.Sandbox.Package.DefinitionReference
#>

function Get-PackageDefinitionPublication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$DefinitionDocument,

        [Parameter(Mandatory = $true)]
        [string]$DefinitionPath
    )

    if (-not $DefinitionDocument.PSObject.Properties['definitionPublication']) {
        throw "Package definition '$DefinitionPath' is missing required definitionPublication metadata."
    }

    $publication = $DefinitionDocument.definitionPublication
    foreach ($requiredProperty in @('publisherId', 'publisherName', 'definitionRevision', 'publishedAtUtc')) {
        if (-not $publication.PSObject.Properties[$requiredProperty] -or [string]::IsNullOrWhiteSpace([string]$publication.$requiredProperty)) {
            throw "Package definition '$DefinitionPath' is missing definitionPublication.$requiredProperty."
        }
    }

    return [pscustomobject]@{
        PublisherId        = [string]$publication.publisherId
        PublisherName      = [string]$publication.publisherName
        DefinitionRevision = [int]$publication.definitionRevision
        PublishedAtUtc     = [string]$publication.publishedAtUtc
    }
}

function Get-PackageLocalDefinitionPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Candidate', 'Assigned')]
        [string]$Role,

        [Parameter(Mandatory = $true)]
        [string]$LocalRepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string]$PublisherId,

        [Parameter(Mandatory = $true)]
        [string]$DefinitionId
    )

    $safePublisherId = ConvertTo-PackageSafePathSegment -Value $PublisherId
    $safeDefinitionId = ConvertTo-PackageSafePathSegment -Value $DefinitionId
    return [System.IO.Path]::GetFullPath((Join-Path (Join-Path (Join-Path $LocalRepositoryRoot $Role) $safePublisherId) ($safeDefinitionId + '.json')))
}

function Copy-PackageDefinitionToLocalDefinitionStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Candidate', 'Assigned')]
        [string]$Role,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$LocalRepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string]$PublisherId,

        [Parameter(Mandatory = $true)]
        [string]$DefinitionId,

        [Parameter(Mandatory = $true)]
        [int]$DefinitionRevision
    )

    $targetPath = Get-PackageLocalDefinitionPath -Role $Role -LocalRepositoryRoot $LocalRepositoryRoot -PublisherId $PublisherId -DefinitionId $DefinitionId
    $targetDirectory = Split-Path -Parent $targetPath
    $null = New-Item -ItemType Directory -Path $targetDirectory -Force

    $sourceHash = Get-PackageFileSha256 -Path $SourcePath
    $targetExists = Test-Path -LiteralPath $targetPath -PathType Leaf
    if ($targetExists) {
        $targetHash = Get-PackageFileSha256 -Path $targetPath
        if ([string]::Equals($sourceHash, $targetHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{
                Path          = $targetPath
                Hash          = $targetHash
                Status        = 'Reused'
                RevisionReuse = $false
            }
        }

        try {
            $existingInfo = Read-PackageJsonDocument -Path $targetPath
            $existingPublication = Get-PackageDefinitionPublication -DefinitionDocument $existingInfo.Document -DefinitionPath $targetPath
            if ($existingPublication.DefinitionRevision -eq $DefinitionRevision) {
                Write-PackageExecutionMessage -Level 'WRN' -Message ("[WARN] Package definition publisher '{0}' reused definitionRevision '{1}' for definition '{2}' with different content; updating local {3} materialized copy." -f $PublisherId, $DefinitionRevision, $DefinitionId, $Role)
            }
        }
        catch {
            Write-PackageExecutionMessage -Level 'WRN' -Message ("[WARN] Existing local {0} definition copy '{1}' could not be inspected before replacement: {2}" -f $Role, $targetPath, $_.Exception.Message)
        }
    }

    Copy-FileToPath -SourcePath $SourcePath -TargetPath $targetPath -Overwrite | Out-Null
    return [pscustomobject]@{
        Path          = $targetPath
        Hash          = Get-PackageFileSha256 -Path $targetPath
        Status        = if ($targetExists) { 'Updated' } else { 'Copied' }
        RevisionReuse = $targetExists
    }
}

function Get-PackageRepositoryDefinitionFilePaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    if (-not (Test-Path -LiteralPath $RepositoryRoot -PathType Container)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $RepositoryRoot -Filter '*.json' -File -Recurse | Select-Object -ExpandProperty FullName)
}

function Select-PackageDefinitionCandidatesFromRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryId,

        [Parameter(Mandatory = $true)]
        [psobject]$RepositorySource,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string]$DefinitionId,

        [AllowNull()]
        [string]$PublisherId = $null
    )

    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($definitionPath in @(Get-PackageRepositoryDefinitionFilePaths -RepositoryRoot $RepositoryRoot)) {
        try {
            $definitionInfo = Read-PackageJsonDocument -Path $definitionPath
            $definition = $definitionInfo.Document
            if (-not $definition.PSObject.Properties['id'] -or
                -not [string]::Equals([string]$definition.id, $DefinitionId, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $publication = Get-PackageDefinitionPublication -DefinitionDocument $definition -DefinitionPath $definitionPath
            if (-not [string]::IsNullOrWhiteSpace($PublisherId) -and
                -not [string]::Equals([string]$publication.PublisherId, $PublisherId, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $candidates.Add([pscustomobject]@{
                RepositoryId       = $RepositoryId
                RepositoryKind     = [string]$RepositorySource.kind
                RepositoryRoot     = $RepositoryRoot
                DefinitionId       = [string]$definition.id
                DefinitionPath     = [System.IO.Path]::GetFullPath($definitionPath)
                PublisherId        = [string]$publication.PublisherId
                PublisherName      = [string]$publication.PublisherName
                DefinitionRevision = [int]$publication.DefinitionRevision
                PublishedAtUtc     = [string]$publication.PublishedAtUtc
                SourceHash         = Get-PackageFileSha256 -Path $definitionPath
            }) | Out-Null
        }
        catch {
            Write-PackageExecutionMessage -Level 'WRN' -Message ("[WARN] Skipped package definition candidate '{0}' from repository '{1}': {2}" -f $definitionPath, $RepositoryId, $_.Exception.Message)
        }
    }

    return @($candidates.ToArray())
}

function Get-PackageEnabledTrustedRepositorySources {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$RepositoryInventoryDocument
    )

    $sources = @(
        foreach ($property in @($RepositoryInventoryDocument.repositorySources.PSObject.Properties)) {
            $source = $property.Value
            if (-not [bool]$source.enabled) {
                continue
            }
            if (-not [bool]$source.trusted) {
                continue
            }
            [pscustomobject]@{
                RepositoryId = [string]$property.Name
                Source       = $source
                SearchOrder  = if ($source.PSObject.Properties['searchOrder']) { [int]$source.searchOrder } else { 1000 }
            }
        }
    )

    return @($sources | Sort-Object -Property SearchOrder, RepositoryId)
}

function Resolve-PackageDefinitionReference {
<#
.SYNOPSIS
Resolves a Package definition identity to a local materialized definition path.

.DESCRIPTION
PackageRepositoryInventory.json is the source of truth for live definition
sources. Without RepositoryId, enabled and trusted repositories are searched by
searchOrder. Matching uses JSON id and optional definitionPublication.publisherId;
filenames are only storage detail. The selected live definition is copied to the
local Candidate definition store and that copy is used for Assigned execution.
#>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$RepositoryId = $null,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DefinitionId,

        [AllowNull()]
        [string]$PublisherId = $null,

        [AllowNull()]
        [string]$ApplicationRootDirectory = $null,

        [AllowNull()]
        [string]$LocalRepositoryRoot = $null
    )

    $repositoryInventoryInfo = Get-PackageRepositoryInventoryInfo
    $candidateRows = New-Object System.Collections.Generic.List[object]
    $sourceRows = @()

    if ([string]::IsNullOrWhiteSpace($RepositoryId)) {
        $sourceRows = @(Get-PackageEnabledTrustedRepositorySources -RepositoryInventoryDocument $repositoryInventoryInfo.Document)
    }
    else {
        $repositoryProperty = Get-PackageRepositorySourceProperty -Document $repositoryInventoryInfo.Document -RepositoryId $RepositoryId
        if (-not $repositoryProperty) {
            throw "Package repository '$RepositoryId' was not found in '$($repositoryInventoryInfo.Path)'."
        }
        $sourceRows = @([pscustomobject]@{
            RepositoryId = [string]$RepositoryId
            Source       = $repositoryProperty.Value
            SearchOrder  = if ($repositoryProperty.Value.PSObject.Properties['searchOrder']) { [int]$repositoryProperty.Value.searchOrder } else { 1000 }
        })
    }

    foreach ($sourceRow in @($sourceRows)) {
        $repositoryRoot = Resolve-PackageRepositoryRootPath -RepositoryId $sourceRow.RepositoryId -Source $sourceRow.Source -ApplicationRootDirectory $ApplicationRootDirectory
        foreach ($candidate in @(Select-PackageDefinitionCandidatesFromRepository -RepositoryId $sourceRow.RepositoryId -RepositorySource $sourceRow.Source -RepositoryRoot $repositoryRoot -DefinitionId $DefinitionId -PublisherId $PublisherId)) {
            $candidate | Add-Member -MemberType NoteProperty -Name SearchOrder -Value ([int]$sourceRow.SearchOrder) -Force
            $candidateRows.Add($candidate) | Out-Null
        }
    }

    $candidates = @($candidateRows.ToArray() | Sort-Object -Property SearchOrder, RepositoryId, PublisherId, DefinitionRevision)
    if ($candidates.Count -eq 0) {
        $sourceText = if ([string]::IsNullOrWhiteSpace($RepositoryId)) { 'enabled trusted repositories' } else { "repository '$RepositoryId'" }
        $publisherText = if ([string]::IsNullOrWhiteSpace($PublisherId)) { '' } else { " and publisher '$PublisherId'" }
        throw "Package definition '$DefinitionId'$publisherText was not found in $sourceText."
    }

    $bestOrder = [int]$candidates[0].SearchOrder
    $sameOrder = @($candidates | Where-Object { [int]$_.SearchOrder -eq $bestOrder })
    if ($sameOrder.Count -gt 1) {
        $locations = (@($sameOrder) | ForEach-Object { "'$($_.RepositoryId):$($_.DefinitionPath)'" }) -join ', '
        throw "Package definition '$DefinitionId' is ambiguous at repository searchOrder '$bestOrder'. Matching candidates: $locations. Use -RepositoryId or -PublisherId."
    }

    $selected = $candidates[0]
    $selectedSourceRow = @($sourceRows | Where-Object { [string]::Equals([string]$_.RepositoryId, [string]$selected.RepositoryId, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)[0]
    $resolvedLocalRepositoryRoot = if ([string]::IsNullOrWhiteSpace($LocalRepositoryRoot)) {
        Get-PackageDefaultLocalRepositoryRoot
    }
    else {
        [string]$LocalRepositoryRoot
    }
    $candidateCopy = Copy-PackageDefinitionToLocalDefinitionStore -Role 'Candidate' -SourcePath $selected.DefinitionPath -LocalRepositoryRoot $resolvedLocalRepositoryRoot -PublisherId $selected.PublisherId -DefinitionId $selected.DefinitionId -DefinitionRevision $selected.DefinitionRevision

    return [pscustomobject]@{
        RepositoryId              = [string]$selected.RepositoryId
        DefinitionId              = [string]$selected.DefinitionId
        DefinitionPath            = [System.IO.Path]::GetFullPath($candidateCopy.Path)
        SourceKind                = [string]$selected.RepositoryKind
        SourcePath                = [string]$selected.DefinitionPath
        SourceRepositoryRoot      = [string]$selected.RepositoryRoot
        SourceHash                = [string]$selected.SourceHash
        CandidatePath             = [System.IO.Path]::GetFullPath($candidateCopy.Path)
        CandidateHash             = [string]$candidateCopy.Hash
        SnapshotPath              = $null
        SnapshotHash              = $null
        ResolvedAtUtc             = [DateTime]::UtcNow.ToString('o')
        SnapshotFallback          = $false
        RepositoryInventoryPath   = $repositoryInventoryInfo.Path
        Trusted                   = $true
        TrustMode                 = if ($selectedSourceRow) { [string]$selectedSourceRow.Source.trustMode } else { $null }
        PublisherId               = [string]$selected.PublisherId
        PublisherName             = [string]$selected.PublisherName
        DefinitionRevision        = [int]$selected.DefinitionRevision
        PublishedAtUtc            = [string]$selected.PublishedAtUtc
        MaterializationStatus     = [string]$candidateCopy.Status
    }
}
