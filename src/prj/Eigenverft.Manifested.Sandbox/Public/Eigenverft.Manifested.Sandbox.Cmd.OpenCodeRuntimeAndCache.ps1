<#
    Eigenverft.Manifested.Sandbox.Cmd.OpenCodeRuntimeAndCache
#>

function Initialize-OpenCodeRuntime {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshOpenCode
    )

    return (Invoke-ManifestedCommandInitialization -Name 'Initialize-OpenCodeRuntime' -PSCmdletObject $PSCmdlet -RefreshRequested:$RefreshOpenCode -WhatIfMode:$WhatIfPreference)
}
