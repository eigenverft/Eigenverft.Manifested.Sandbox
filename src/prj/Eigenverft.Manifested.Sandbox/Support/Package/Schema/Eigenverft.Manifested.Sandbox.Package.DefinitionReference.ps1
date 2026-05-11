<#
    Eigenverft.Manifested.Sandbox.Package.DefinitionReference
#>

function Resolve-PackageDefinitionReference {
<#
.SYNOPSIS
Resolves a Package definition identity to a concrete definition document path.

.DESCRIPTION
Creates the repository-resolution seam used by the generic Package command
surface. PackageRepositoryInventory.json is the source of truth for live definition
sources. Local definition snapshots are used only by explicit removal fallback.
#>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$RepositoryId = (Get-PackageDefaultRepositoryId),

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DefinitionId,

        [AllowNull()]
        [string]$ApplicationRootDirectory = $null
    )

    $defaultRepositoryId = Get-PackageDefaultRepositoryId
    $resolvedRepositoryId = if ([string]::IsNullOrWhiteSpace($RepositoryId)) {
        $defaultRepositoryId
    }
    else {
        [string]$RepositoryId
    }

    $repositoryInventoryInfo = Get-PackageRepositoryInventoryInfo
    $repositoryProperty = Get-PackageRepositorySourceProperty -Document $repositoryInventoryInfo.Document -RepositoryId $resolvedRepositoryId
    if (-not $repositoryProperty) {
        throw "Package repository '$resolvedRepositoryId' was not found in '$($repositoryInventoryInfo.Path)'."
    }

    $repositorySource = $repositoryProperty.Value
    $repositoryRoot = Resolve-PackageRepositoryRootPath -RepositoryId $resolvedRepositoryId -Source $repositorySource -ApplicationRootDirectory $ApplicationRootDirectory
    $definitionPath = if ([string]::Equals([string]$repositorySource.kind, 'moduleLocal', [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals($resolvedRepositoryId, $defaultRepositoryId, [System.StringComparison]::OrdinalIgnoreCase)) {
        Get-PackageDefinitionPath -DefinitionId $DefinitionId
    }
    else {
        Join-Path $repositoryRoot ($DefinitionId + '.json')
    }

    $definitionPath = [System.IO.Path]::GetFullPath($definitionPath)
    if (-not (Test-Path -LiteralPath $definitionPath -PathType Leaf)) {
        throw "Package definition '$DefinitionId' was not found in repository '$resolvedRepositoryId' at '$definitionPath'."
    }

    return [pscustomobject]@{
        RepositoryId       = $resolvedRepositoryId
        DefinitionId       = [string]$DefinitionId
        DefinitionPath     = $definitionPath
        SourceKind         = [string]$repositorySource.kind
        SourcePath         = $repositoryRoot
        SourceHash         = Get-PackageFileSha256 -Path $definitionPath
        SnapshotPath       = $null
        SnapshotHash       = $null
        ResolvedAtUtc      = [DateTime]::UtcNow.ToString('o')
        SnapshotFallback   = $false
        RepositoryInventoryPath = $repositoryInventoryInfo.Path
        Trusted           = [bool]$repositorySource.trusted
        TrustMode         = [string]$repositorySource.trustMode
    }
}
