<#
    Eigenverft.Manifested.Sandbox.Cmd.GHCliRuntimeAndCache
#>

function Initialize-GHCliRuntime {
<#
.SYNOPSIS
Ensures the managed GitHub CLI runtime is available for the sandbox toolchain.

.DESCRIPTION
Delegates GitHub CLI runtime orchestration to the shared GitHub-portable
runtime helper, which repairs partial state, acquires and installs the runtime
when needed, and keeps the command-line environment aligned.

.PARAMETER RefreshGHCli
Forces the managed runtime package to be reacquired and reinstalled instead of
reusing the cached or installed copy.

.EXAMPLE
Initialize-GHCliRuntime

.EXAMPLE
Initialize-GHCliRuntime -RefreshGHCli

.NOTES
Supports `-WhatIf` and keeps the public command as a thin facade over the
shared runtime-family flow.
#>
    [Diagnostics.CodeAnalysis.SuppressMessage('PSShouldProcess', '', Justification = 'Thin facade delegates ShouldProcess handling to the shared GitHub-portable runtime helper.')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshGHCli
    )

    return (Invoke-ManifestedGitHubPortableRuntimeInitialization -CommandName 'Initialize-GHCliRuntime' -Refresh:$RefreshGHCli)
}
