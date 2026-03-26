<#
    Eigenverft.Manifested.Sandbox.Cmd.VsCodeRuntimeAndCache
#>

function Initialize-VSCodeRuntime {
<#
.SYNOPSIS
Ensures the managed VS Code runtime is available for the sandbox toolchain.

.DESCRIPTION
Delegates VS Code runtime orchestration to the shared GitHub-portable runtime
helper, which repairs partial state, acquires and installs the runtime when
needed, and keeps the command-line environment aligned.

.PARAMETER RefreshVSCode
Forces the managed runtime package to be reacquired and reinstalled instead of
reusing the cached or installed copy.

.EXAMPLE
Initialize-VSCodeRuntime

.EXAMPLE
Initialize-VSCodeRuntime -RefreshVSCode

.NOTES
Supports `-WhatIf` and keeps the public command as a thin facade over the
shared runtime-family flow.
#>
    [Diagnostics.CodeAnalysis.SuppressMessage('PSShouldProcess', '', Justification = 'Thin facade delegates ShouldProcess handling to the shared GitHub-portable runtime helper.')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshVSCode
    )

    return (Invoke-ManifestedGitHubPortableRuntimeInitialization -CommandName 'Initialize-VSCodeRuntime' -Refresh:$RefreshVSCode)
}
