<#
    Public package command surface.
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

        [AllowNull()]
        [string]$PublisherId = $null,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$DefinitionId,

        [ValidateSet('Assigned', 'Removed')]
        [string]$DesiredState = 'Assigned',

        [switch]$FailFast
    )

    foreach ($definition in $DefinitionId) {
        $result = Invoke-PackageDefinitionCommandCore -RepositoryId $RepositoryId -PublisherId $PublisherId -DefinitionId $definition -DesiredState $DesiredState
        $result
        if ($FailFast -and $result -and -not [string]::Equals([string]$result.Status, 'Ready', [System.StringComparison]::OrdinalIgnoreCase)) {
            break
        }
    }
}
