<#
    Eigenverft.Manifested.Sandbox.Cmd.GeminiRuntimeAndCache
#>

function Initialize-GeminiRuntime {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshGemini
    )

    return (Invoke-ManifestedCommandInitialization -Name 'Initialize-GeminiRuntime' -PSCmdletObject $PSCmdlet -RefreshRequested:$RefreshGemini -WhatIfMode:$WhatIfPreference)
}
