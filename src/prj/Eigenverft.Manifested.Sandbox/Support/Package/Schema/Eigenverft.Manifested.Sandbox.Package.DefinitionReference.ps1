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

        [AllowNull()]
        [string]$DefinitionRepositorySegment = $null,

        [Parameter(Mandatory = $true)]
        [string]$DefinitionId
    )

    $safePublisherId = ConvertTo-PackageSafePathSegment -Value $PublisherId
    $safeDefinitionId = ConvertTo-PackageSafePathSegment -Value $DefinitionId
    if ([string]::Equals($Role, 'Candidate', [System.StringComparison]::OrdinalIgnoreCase)) {
        if ([string]::IsNullOrWhiteSpace($DefinitionRepositorySegment)) {
            throw 'DefinitionRepositorySegment (JSON repositoryId) is required when resolving a Candidate definition path.'
        }
        $safeRepositorySegment = ConvertTo-PackageSafePathSegment -Value $DefinitionRepositorySegment
        return [System.IO.Path]::GetFullPath((Join-Path (Join-Path (Join-Path (Join-Path $LocalRepositoryRoot $Role) $safePublisherId) $safeRepositorySegment) ($safeDefinitionId + '.json')))
    }

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

        [AllowNull()]
        [string]$DefinitionRepositorySegment = $null,

        [Parameter(Mandatory = $true)]
        [string]$DefinitionId,

        [Parameter(Mandatory = $true)]
        [int]$DefinitionRevision
    )

    $targetPath = Get-PackageLocalDefinitionPath -Role $Role -LocalRepositoryRoot $LocalRepositoryRoot -PublisherId $PublisherId -DefinitionRepositorySegment $DefinitionRepositorySegment -DefinitionId $DefinitionId
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

function Get-PackageDefinitionJsonPathsUnderDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath
    )

    if (-not (Test-Path -LiteralPath $DirectoryPath -PathType Container)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $DirectoryPath -Filter '*.json' -File -Recurse | Select-Object -ExpandProperty FullName)
}

function Select-PackageDefinitionCandidatesFromEndpointScanRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EndpointName,

        [Parameter(Mandatory = $true)]
        [psobject]$EndpointSource,

        [Parameter(Mandatory = $true)]
        [string]$ScanRootPath,

        [Parameter(Mandatory = $true)]
        [string]$DefinitionId
    )

    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($definitionPath in @(Get-PackageDefinitionJsonPathsUnderDirectory -DirectoryPath $ScanRootPath)) {
        try {
            $definitionInfo = Read-PackageJsonDocument -Path $definitionPath
            $definition = $definitionInfo.Document
            $docDefinitionId = if ($definition.PSObject.Properties['definitionId'] -and -not [string]::IsNullOrWhiteSpace([string]$definition.definitionId)) {
                [string]$definition.definitionId
            }
            elseif ($definition.PSObject.Properties['id']) {
                [string]$definition.id
            }
            else {
                $null
            }
            if ([string]::IsNullOrWhiteSpace($docDefinitionId) -or
                -not [string]::Equals($docDefinitionId, $DefinitionId, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $definitionDataRepositoryId = if ($definition.PSObject.Properties['repositoryId'] -and -not [string]::IsNullOrWhiteSpace([string]$definition.repositoryId)) {
                [string]$definition.repositoryId
            }
            else {
                [string](Get-PackageDefaultRepositoryId)
            }

            $publication = Get-PackageDefinitionPublication -DefinitionDocument $definition -DefinitionPath $definitionPath

            $candidates.Add([pscustomobject]@{
                EndpointName               = $EndpointName
                RepositorySourceId         = $EndpointName
                RepositoryId               = $EndpointName
                DefinitionDataRepositoryId = $definitionDataRepositoryId
                EndpointSourceKind         = [string]$EndpointSource.kind
                DefinitionScanRootPath     = $ScanRootPath
                DefinitionId               = $docDefinitionId
                DefinitionPath             = [System.IO.Path]::GetFullPath($definitionPath)
                PublisherId                = [string]$publication.PublisherId
                PublisherName              = [string]$publication.PublisherName
                DefinitionRevision         = [int]$publication.DefinitionRevision
                PublishedAtUtc             = [string]$publication.PublishedAtUtc
                SourceHash                 = Get-PackageFileSha256 -Path $definitionPath
            }) | Out-Null
        }
        catch {
            Write-PackageExecutionMessage -Level 'WRN' -Message ("[WARN] Skipped package definition candidate '{0}' from endpoint '{1}': {2}" -f $definitionPath, $EndpointName, $_.Exception.Message)
        }
    }

    return @($candidates.ToArray())
}

function Get-PackageEnabledTrustedEndpointSources {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$EndpointInventoryDocument
    )

    $sources = @(
        foreach ($source in @(Get-PackageEndpointSourceEntries -Document $EndpointInventoryDocument)) {
            if (-not [bool]$source.enabled) {
                continue
            }
            if (-not [bool]$source.trusted) {
                continue
            }
            $endpointName = [string]$source.endpointName
            [pscustomobject]@{
                EndpointName       = $endpointName
                RepositorySourceId = $endpointName
                RepositoryId       = $endpointName
                Source               = $source
                SearchOrder          = if ($source.PSObject.Properties['searchOrder']) { [int]$source.searchOrder } else { 1000 }
            }
        }
    )

    return @($sources | Sort-Object -Property SearchOrder, EndpointName)
}

function Sync-PackageRepositoryCandidateDefinitions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$SourceRows,

        [AllowNull()]
        [string]$ApplicationRootDirectory = $null,

        [Parameter(Mandatory = $true)]
        [string]$LocalRepositoryRoot
    )

    $materializedCount = 0
    foreach ($sourceRow in @($SourceRows)) {
        $endpointName = [string]$sourceRow.EndpointName
        try {
            $scanRootPath = Resolve-PackageEndpointRootPath -EndpointName $endpointName -Source $sourceRow.Source -ApplicationRootDirectory $ApplicationRootDirectory
            foreach ($definitionPath in @(Get-PackageDefinitionJsonPathsUnderDirectory -DirectoryPath $scanRootPath)) {
                try {
                    $definitionInfo = Read-PackageJsonDocument -Path $definitionPath
                    $doc = $definitionInfo.Document
                    $docDefinitionId = if ($doc.PSObject.Properties['definitionId'] -and -not [string]::IsNullOrWhiteSpace([string]$doc.definitionId)) {
                        [string]$doc.definitionId
                    }
                    elseif ($doc.PSObject.Properties['id']) {
                        [string]$doc.id
                    }
                    else {
                        continue
                    }
                    if ([string]::IsNullOrWhiteSpace($docDefinitionId)) {
                        continue
                    }
                    $definitionRepositorySegment = if ($doc.PSObject.Properties['repositoryId'] -and -not [string]::IsNullOrWhiteSpace([string]$doc.repositoryId)) {
                        [string]$doc.repositoryId
                    }
                    else {
                        [string](Get-PackageDefaultRepositoryId)
                    }
                    $publication = Get-PackageDefinitionPublication -DefinitionDocument $doc -DefinitionPath $definitionPath
                    Copy-PackageDefinitionToLocalDefinitionStore -Role 'Candidate' -SourcePath $definitionPath -LocalRepositoryRoot $LocalRepositoryRoot -PublisherId ([string]$publication.PublisherId) -DefinitionRepositorySegment $definitionRepositorySegment -DefinitionId $docDefinitionId -DefinitionRevision ([int]$publication.DefinitionRevision) | Out-Null
                    $materializedCount++
                }
                catch {
                    Write-PackageExecutionMessage -Level 'WRN' -Message ("[WARN] Skipped repository-focused Candidate materialization for '{0}' from endpoint '{1}': {2}" -f $definitionPath, $endpointName, $_.Exception.Message)
                }
            }
        }
        catch {
            Write-PackageExecutionMessage -Level 'WRN' -Message ("[WARN] Skipped repository-focused Candidate materialization for endpoint '{0}': {1}" -f $endpointName, $_.Exception.Message)
        }
    }

    return $materializedCount
}

function Resolve-PackageDefinitionReference {
<#
.SYNOPSIS
Resolves a Package definition identity to a local materialized definition path.

.DESCRIPTION
PackageEndpointInventory.json lists scan endpoints. All enabled trusted endpoints are searched in searchOrder.
Matching uses JSON definitionId. Optional RepositoryId filters
to definitions whose JSON repositoryId equals that value (data-level, not an endpoint row key).
The winning live definition (highest definitionRevision, then searchOrder, endpointName, publisherId, path) is copied under
PkgRepos using publisher and JSON repositoryId path segments.
#>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$RepositoryId = $null,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DefinitionId,

        [AllowNull()]
        [string]$ApplicationRootDirectory = $null,

        [AllowNull()]
        [string]$LocalRepositoryRoot = $null,

        [ValidateSet('packageFocused', 'repositoryFocused')]
        [string]$RepositoryMaterializationMode = 'packageFocused'
    )

    $endpointInventoryInfo = Get-PackageEndpointInventoryInfo
    $candidateRows = New-Object System.Collections.Generic.List[object]
    $sourceRows = @(Get-PackageEnabledTrustedEndpointSources -EndpointInventoryDocument $endpointInventoryInfo.Document)

    $resolvedLocalRepositoryRoot = if ([string]::IsNullOrWhiteSpace($LocalRepositoryRoot)) {
        Get-PackageDefaultLocalRepositoryRoot
    }
    else {
        [string]$LocalRepositoryRoot
    }

    if ([string]::Equals($RepositoryMaterializationMode, 'repositoryFocused', [System.StringComparison]::OrdinalIgnoreCase)) {
        $count = Sync-PackageRepositoryCandidateDefinitions -SourceRows $sourceRows -ApplicationRootDirectory $ApplicationRootDirectory -LocalRepositoryRoot $resolvedLocalRepositoryRoot
        Write-PackageExecutionMessage -Message ("[STATE] Repository-focused definition materialization refreshed {0} Candidate definition file(s)." -f $count)
    }

    foreach ($sourceRow in @($sourceRows)) {
        $endpointName = [string]$sourceRow.EndpointName
        $scanRootPath = Resolve-PackageEndpointRootPath -EndpointName $endpointName -Source $sourceRow.Source -ApplicationRootDirectory $ApplicationRootDirectory
        foreach ($candidate in @(Select-PackageDefinitionCandidatesFromEndpointScanRoot -EndpointName $endpointName -EndpointSource $sourceRow.Source -ScanRootPath $scanRootPath -DefinitionId $DefinitionId)) {
            $candidate | Add-Member -MemberType NoteProperty -Name SearchOrder -Value ([int]$sourceRow.SearchOrder) -Force
            $candidateRows.Add($candidate) | Out-Null
        }
    }

    $candidates = @($candidateRows.ToArray())
    if (-not [string]::IsNullOrWhiteSpace($RepositoryId)) {
        $candidates = @($candidates | Where-Object {
            [string]::Equals([string]$_.DefinitionDataRepositoryId, [string]$RepositoryId, [System.StringComparison]::OrdinalIgnoreCase)
        })
    }

    if ($candidates.Count -eq 0) {
        $narrow = if ([string]::IsNullOrWhiteSpace($RepositoryId)) { '' } else { " with JSON repositoryId filter '$RepositoryId'" }
        throw "Package definition '$DefinitionId' was not found in enabled trusted endpoints$narrow."
    }

    $bestRevision = (@($candidates) | Measure-Object -Property DefinitionRevision -Maximum).Maximum
    $bestRevisionCandidates = @($candidates | Where-Object { [int]$_.DefinitionRevision -eq [int]$bestRevision })
    $bestHashes = @($bestRevisionCandidates | Select-Object -ExpandProperty SourceHash -Unique)
    if ($bestHashes.Count -gt 1) {
        $locations = (@($bestRevisionCandidates) | ForEach-Object { "'$($_.EndpointName):$($_.DefinitionPath) hash=$($_.SourceHash)'" }) -join ', '
        throw "Package definition '$DefinitionId' publisher '$($bestRevisionCandidates[0].PublisherId)' reused definitionRevision '$bestRevision' with different content across endpoints. Matching candidates: $locations. Use -RepositoryId to narrow by JSON repositoryId or publish a higher revision."
    }

    $selected = @($bestRevisionCandidates | Sort-Object -Property SearchOrder, EndpointName, PublisherId, DefinitionPath | Select-Object -First 1)[0]
    $selectedSourceRow = @($sourceRows | Where-Object { [string]::Equals([string]$_.EndpointName, [string]$selected.EndpointName, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)[0]
    $candidateCopy = Copy-PackageDefinitionToLocalDefinitionStore -Role 'Candidate' -SourcePath $selected.DefinitionPath -LocalRepositoryRoot $resolvedLocalRepositoryRoot -PublisherId $selected.PublisherId -DefinitionRepositorySegment $selected.DefinitionDataRepositoryId -DefinitionId $selected.DefinitionId -DefinitionRevision $selected.DefinitionRevision

    return [pscustomobject]@{
        EndpointName                  = [string]$selected.EndpointName
        RepositorySourceId            = [string]$selected.EndpointName
        RepositoryId                  = [string]$selected.EndpointName
        DefinitionDataRepositoryId    = [string]$selected.DefinitionDataRepositoryId
        DefinitionId                  = [string]$selected.DefinitionId
        DefinitionPath                = [System.IO.Path]::GetFullPath($candidateCopy.Path)
        SourceKind                    = [string]$selected.EndpointSourceKind
        SourcePath                    = [string]$selected.DefinitionPath
        SourceDefinitionScanRootPath  = [string]$selected.DefinitionScanRootPath
        SourceHash                    = [string]$selected.SourceHash
        CandidatePath                 = [System.IO.Path]::GetFullPath($candidateCopy.Path)
        CandidateHash                 = [string]$candidateCopy.Hash
        SnapshotPath                  = $null
        SnapshotHash                  = $null
        ResolvedAtUtc                 = [DateTime]::UtcNow.ToString('o')
        SnapshotFallback              = $false
        EndpointInventoryPath         = $endpointInventoryInfo.Path
        Trusted                       = $true
        TrustMode                     = if ($selectedSourceRow) { [string]$selectedSourceRow.Source.trustMode } else { $null }
        PublisherId                   = [string]$selected.PublisherId
        PublisherName                 = [string]$selected.PublisherName
        DefinitionRevision            = [int]$selected.DefinitionRevision
        PublishedAtUtc                = [string]$selected.PublishedAtUtc
        MaterializationStatus         = [string]$candidateCopy.Status
        RepositoryMaterializationMode = [string]$RepositoryMaterializationMode
    }
}
