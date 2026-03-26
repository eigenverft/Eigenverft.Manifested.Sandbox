<#
    Eigenverft.Manifested.Sandbox.Cmd.Ps7RuntimeAndCache
#>

function Initialize-Ps7Runtime {
<#
.SYNOPSIS
Ensures the managed PowerShell 7 runtime is available for the sandbox toolchain.

.DESCRIPTION
Delegates PowerShell 7 runtime orchestration to the shared GitHub-portable
runtime helper, which repairs partial state, acquires and installs the runtime
when needed, and keeps the command-line environment aligned.

.PARAMETER RefreshPs7
Forces the managed runtime package to be reacquired and reinstalled instead of
reusing the cached or installed copy.

.EXAMPLE
Initialize-Ps7Runtime

.EXAMPLE
Initialize-Ps7Runtime -RefreshPs7

.NOTES
Supports `-WhatIf` and keeps the public command as a thin facade over the
shared runtime-family flow.
#>
    [Diagnostics.CodeAnalysis.SuppressMessage('PSShouldProcess', '', Justification = 'Thin facade delegates ShouldProcess handling to the shared GitHub-portable runtime helper.')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshPs7
    )

    return (Invoke-ManifestedGitHubPortableRuntimeInitialization -CommandName 'Initialize-Ps7Runtime' -Refresh:$RefreshPs7)
}
