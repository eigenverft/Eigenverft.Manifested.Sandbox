<#
    Eigenverft.Manifested.Sandbox.Runtime.Codex.Validation
#>

function Test-CodexRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    return (Test-ManifestedNpmCliRuntime -Definition (Get-ManifestedCodexNpmCliRuntimeDefinition) -RuntimeHome $RuntimeHome)
}

