<#
    Eigenverft.Manifested.Sandbox.Package.DefinitionReference
#>

function Resolve-PackageDefinitionReference {
<#
.SYNOPSIS
Resolves a Package definition identity to a concrete definition document path.

.DESCRIPTION
Creates the repository-resolution seam used by the generic Package command
surface. This first pass intentionally supports only the shipped
EigenverftModule repository while preserving a clear extension point for later
local or remote repository depots.
#>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$RepositoryId = (Get-PackageDefaultRepositoryId),

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DefinitionId
    )

    $defaultRepositoryId = Get-PackageDefaultRepositoryId
    $resolvedRepositoryId = if ([string]::IsNullOrWhiteSpace($RepositoryId)) {
        $defaultRepositoryId
    }
    else {
        [string]$RepositoryId
    }

    if (-not [string]::Equals($resolvedRepositoryId, $defaultRepositoryId, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Package repository '$resolvedRepositoryId' is not implemented yet. Only '$defaultRepositoryId' is currently supported."
    }

    return [pscustomobject]@{
        RepositoryId   = $defaultRepositoryId
        DefinitionId   = [string]$DefinitionId
        DefinitionPath = Get-PackageDefinitionPath -DefinitionId $DefinitionId
        SourceKind     = 'moduleLocal'
    }
}
