<#
    Eigenverft.Manifested.Sandbox.Cmd.QwenRuntimeAndCache
#>

function Initialize-QwenRuntime {
<#
.SYNOPSIS
Ensures the Qwen runtime is available and ready for command-line use.

.DESCRIPTION
Delegates Qwen runtime orchestration to the shared npm CLI runtime helper,
which repairs partial state, ensures Node.js dependencies are available,
installs the managed runtime when needed, and keeps the command-line
environment aligned.

.PARAMETER RefreshQwen
Forces the managed Qwen runtime to be reinstalled even when one is already
ready.

.EXAMPLE
Initialize-QwenRuntime

.EXAMPLE
Initialize-QwenRuntime -RefreshQwen

.NOTES
Supports `-WhatIf` and keeps the public command as a thin facade over the
shared runtime-family flow.
#>
    [Diagnostics.CodeAnalysis.SuppressMessage('PSShouldProcess', '', Justification = 'Thin facade delegates ShouldProcess handling to the shared npm CLI runtime helper.')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshQwen
    )

    return (Invoke-ManifestedNpmCliRuntimeInitialization -CommandName 'Initialize-QwenRuntime' -Refresh:$RefreshQwen)
}
