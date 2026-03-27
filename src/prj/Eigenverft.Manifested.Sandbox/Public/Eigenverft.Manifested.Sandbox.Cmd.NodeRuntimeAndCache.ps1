<#
    Eigenverft.Manifested.Sandbox.Cmd.NodeRuntimeAndCache
#>

function Initialize-NodeRuntime {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshNode
    )

    return (Invoke-ManifestedCommandInitialization -Name 'Initialize-NodeRuntime' -PSCmdletObject $PSCmdlet -RefreshRequested:$RefreshNode -WhatIfMode:$WhatIfPreference)
}
