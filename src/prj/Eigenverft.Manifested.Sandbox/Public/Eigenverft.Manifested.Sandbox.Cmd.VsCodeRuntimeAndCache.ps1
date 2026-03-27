<#
    Eigenverft.Manifested.Sandbox.Cmd.VsCodeRuntimeAndCache
#>

function Initialize-VSCodeRuntime {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshVSCode
    )

    return (Invoke-ManifestedCommandInitialization -Name 'Initialize-VSCodeRuntime' -PSCmdletObject $PSCmdlet -RefreshRequested:$RefreshVSCode -WhatIfMode:$WhatIfPreference)
}
