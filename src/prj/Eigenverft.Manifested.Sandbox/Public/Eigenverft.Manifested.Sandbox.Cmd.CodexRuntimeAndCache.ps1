<#
    Eigenverft.Manifested.Sandbox.Cmd.CodexRuntimeAndCache
#>

function Initialize-CodexRuntime {
<#
.SYNOPSIS
Ensures a managed or reusable Codex runtime is available for the sandbox.

.DESCRIPTION
Routes Codex runtime initialization through the shared block-driven kernel and
the packaged command definition for Codex.

.PARAMETER RefreshCodex
Forces reacquisition or reinstall planning for the managed Codex runtime.

.EXAMPLE
Initialize-CodexRuntime

.EXAMPLE
Initialize-CodexRuntime -RefreshCodex
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshCodex
    )

    return (Invoke-ManifestedCommandInitialization -Name 'Initialize-CodexRuntime' -PSCmdletObject $PSCmdlet -RefreshRequested:$RefreshCodex -WhatIfMode:$WhatIfPreference)
}
