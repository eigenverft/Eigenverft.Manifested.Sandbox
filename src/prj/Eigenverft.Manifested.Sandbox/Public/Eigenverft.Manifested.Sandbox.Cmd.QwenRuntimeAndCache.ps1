<#
    Eigenverft.Manifested.Sandbox.Cmd.QwenRuntimeAndCache
#>

function Initialize-QwenRuntime {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshQwen
    )

    return (Invoke-ManifestedCommandInitialization -Name 'Initialize-QwenRuntime' -PSCmdletObject $PSCmdlet -RefreshRequested:$RefreshQwen -WhatIfMode:$WhatIfPreference)
}
