<#
    Eigenverft.Manifested.Sandbox.Cmd.OpenCodeRuntimeAndCache
#>

function Initialize-OpenCodeRuntime {
<#
.SYNOPSIS
Ensures the OpenCode runtime is available and ready for command-line use.

.DESCRIPTION
Delegates OpenCode runtime orchestration to the shared npm CLI runtime helper,
which repairs partial state, ensures Node.js dependencies are available,
installs the managed runtime when needed, and keeps the command-line
environment aligned.

.PARAMETER RefreshOpenCode
Forces the managed OpenCode runtime to be reinstalled even when one is already
ready.

.EXAMPLE
Initialize-OpenCodeRuntime

.EXAMPLE
Initialize-OpenCodeRuntime -RefreshOpenCode

.NOTES
Supports `-WhatIf` and keeps the public command as a thin facade over the
shared runtime-family flow.
#>
    [Diagnostics.CodeAnalysis.SuppressMessage('PSShouldProcess', '', Justification = 'Thin facade delegates ShouldProcess handling to the shared npm CLI runtime helper.')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshOpenCode
    )

    return (Invoke-ManifestedNpmCliRuntimeInitialization -CommandName 'Initialize-OpenCodeRuntime' -Refresh:$RefreshOpenCode)
}
