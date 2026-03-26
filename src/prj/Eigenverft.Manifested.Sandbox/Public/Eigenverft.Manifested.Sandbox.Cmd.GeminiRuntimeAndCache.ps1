<#
    Eigenverft.Manifested.Sandbox.Cmd.GeminiRuntimeAndCache
#>

function Initialize-GeminiRuntime {
<#
.SYNOPSIS
Ensures the Gemini runtime is available and ready for command-line use.

.DESCRIPTION
Delegates Gemini runtime orchestration to the shared npm CLI runtime helper,
which repairs partial state, ensures required Node.js dependencies are present,
installs the managed runtime when needed, and keeps the command-line
environment aligned.

.PARAMETER RefreshGemini
Forces the managed Gemini runtime to be reinstalled even when one is already
ready.

.EXAMPLE
Initialize-GeminiRuntime

.EXAMPLE
Initialize-GeminiRuntime -RefreshGemini

.NOTES
Supports `-WhatIf` and keeps the public command as a thin facade over the
shared runtime-family flow.
#>
    [Diagnostics.CodeAnalysis.SuppressMessage('PSShouldProcess', '', Justification = 'Thin facade delegates ShouldProcess handling to the shared npm CLI runtime helper.')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshGemini
    )

    return (Invoke-ManifestedNpmCliRuntimeInitialization -CommandName 'Initialize-GeminiRuntime' -Refresh:$RefreshGemini)
}
