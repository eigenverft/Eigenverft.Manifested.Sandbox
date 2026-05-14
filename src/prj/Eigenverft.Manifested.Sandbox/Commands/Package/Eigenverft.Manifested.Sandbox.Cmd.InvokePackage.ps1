<#
    Public package command surface.

    Optional -RepositoryId narrows definition resolution to JSON documents whose repositoryId matches (all enabled trusted endpoints are still scanned first).
#>

function Invoke-Package {
    <#
    .SYNOPSIS
        Runs package definition lifecycle for one or more definitions.

    .PARAMETER FailFast
        When set, stops after the first result whose Status is not 'Ready'.
        By default every DefinitionId is attempted and each result is written to the pipeline.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$RepositoryId = $null,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$DefinitionId,

        [ValidateSet('Assigned', 'Removed')]
        [string]$DesiredState = 'Assigned',

        [switch]$FailFast
    )

    foreach ($definition in $DefinitionId) {
        $result = Invoke-PackageDefinitionCommandCore -RepositoryId $RepositoryId -DefinitionId $definition -DesiredState $DesiredState
        $result
        if ($FailFast -and $result -and -not [string]::Equals([string]$result.Status, 'Ready', [System.StringComparison]::OrdinalIgnoreCase)) {
            break
        }
    }
}
