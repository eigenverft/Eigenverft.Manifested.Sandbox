<#
    Eigenverft.Manifested.Sandbox.Cmd.GitRuntimeAndCache
#>

function Initialize-GitRuntime {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshGit
    )

    return (Invoke-ManifestedCommandInitialization -Name 'Initialize-GitRuntime' -PSCmdletObject $PSCmdlet -RefreshRequested:$RefreshGit -WhatIfMode:$WhatIfPreference)
}
