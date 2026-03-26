<#
    Eigenverft.Manifested.Sandbox.Cmd.GitRuntimeAndCache
#>

function Initialize-GitRuntime {
<#
.SYNOPSIS
Ensures the managed Git runtime is available for the sandbox toolchain.

.DESCRIPTION
Delegates MinGit runtime orchestration to the shared GitHub-portable runtime
helper, which repairs partial state, acquires and installs the runtime when
needed, and keeps the command-line environment aligned.

.PARAMETER RefreshGit
Forces the managed runtime package to be reacquired and reinstalled instead of
reusing the cached or installed copy.

.EXAMPLE
Initialize-GitRuntime

.EXAMPLE
Initialize-GitRuntime -RefreshGit

.NOTES
Supports `-WhatIf` and keeps the public command as a thin facade over the
shared runtime-family flow.
#>
    [Diagnostics.CodeAnalysis.SuppressMessage('PSShouldProcess', '', Justification = 'Thin facade delegates ShouldProcess handling to the shared GitHub-portable runtime helper.')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshGit
    )

    return (Invoke-ManifestedGitHubPortableRuntimeInitialization -CommandName 'Initialize-GitRuntime' -Refresh:$RefreshGit)
}
