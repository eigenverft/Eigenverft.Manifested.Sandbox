<#
    Eigenverft.Manifested.Sandbox.Cmd.CodexRuntimeAndCache
#>

function Initialize-CodexRuntime {
<#
.SYNOPSIS
Ensures the Codex runtime is available and ready for command-line use.

.DESCRIPTION
Delegates Codex runtime orchestration to the shared npm CLI runtime helper,
which repairs partial state, ensures required dependencies are present,
installs the managed runtime when needed, and keeps the command-line
environment aligned.

.PARAMETER RefreshCodex
Forces the managed Codex runtime to be reinstalled even when one is already
ready.

.EXAMPLE
Initialize-CodexRuntime

.EXAMPLE
Initialize-CodexRuntime -RefreshCodex

.NOTES
Supports `-WhatIf` and keeps the public command as a thin facade over the
shared runtime-family flow.
#>
    [Diagnostics.CodeAnalysis.SuppressMessage('PSShouldProcess', '', Justification = 'Thin facade delegates ShouldProcess handling to the shared npm CLI runtime helper.')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshCodex
    )

    return (Invoke-ManifestedNpmCliRuntimeInitialization -CommandName 'Initialize-CodexRuntime' -Refresh:$RefreshCodex)
}
