<#
    Eigenverft.Manifested.Sandbox.Runtime.Codex.Install
#>

function Repair-CodexRuntime {
    [CmdletBinding()]
    param(
        [pscustomobject]$State,
        [string[]]$CorruptRuntimeHomes = @(),
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Repair-ManifestedNpmCliRuntime -Definition (Get-ManifestedCodexNpmCliRuntimeDefinition) -State $State -CorruptRuntimeHomes $CorruptRuntimeHomes -LocalRoot $LocalRoot)
}

function Install-CodexRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NpmCmd,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Install-ManifestedNpmCliRuntime -Definition (Get-ManifestedCodexNpmCliRuntimeDefinition) -NpmCmd $NpmCmd -LocalRoot $LocalRoot)
}

