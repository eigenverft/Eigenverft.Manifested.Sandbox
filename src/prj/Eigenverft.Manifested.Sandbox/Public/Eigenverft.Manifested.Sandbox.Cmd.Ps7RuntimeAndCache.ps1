<#
    Eigenverft.Manifested.Sandbox.Cmd.Ps7RuntimeAndCache
#>

function Initialize-Ps7Runtime {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshPs7
    )

    return (Invoke-ManifestedCommandInitialization -Name 'Initialize-Ps7Runtime' -PSCmdletObject $PSCmdlet -RefreshRequested:$RefreshPs7 -WhatIfMode:$WhatIfPreference)
}
