<#
    Eigenverft.Manifested.Sandbox.Cmd.GHCliRuntimeAndCache
#>

function Initialize-GHCliRuntime {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshGHCli
    )

    return (Invoke-ManifestedCommandInitialization -Name 'Initialize-GHCliRuntime' -PSCmdletObject $PSCmdlet -RefreshRequested:$RefreshGHCli -WhatIfMode:$WhatIfPreference)
}
