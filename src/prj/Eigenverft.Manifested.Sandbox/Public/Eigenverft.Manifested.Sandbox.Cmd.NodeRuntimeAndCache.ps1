<#
    Eigenverft.Manifested.Sandbox.Cmd.NodeRuntimeAndCache
#>

function Initialize-NodeRuntime {
<#
.SYNOPSIS
Ensures a managed or reusable Node.js runtime is available for the sandbox.

.DESCRIPTION
Delegates Node runtime orchestration to the shared Node runtime-family helper,
which repairs partial managed state, acquires and installs the managed runtime
when needed, synchronizes managed npm proxy settings, and keeps the command-line
environment aligned for follow-up tooling.

.PARAMETER RefreshNode
Forces the managed Node package to be reacquired and reinstalled instead of
reusing the currently installed or cached copy.

.EXAMPLE
Initialize-NodeRuntime

.EXAMPLE
Initialize-NodeRuntime -RefreshNode

.NOTES
Supports `-WhatIf` and preserves the module's shared runtime state and
environment synchronization behavior.
#>
    [Diagnostics.CodeAnalysis.SuppressMessage('PSShouldProcess', '', Justification = 'Thin facade delegates ShouldProcess handling to the shared Node runtime helper.')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshNode
    )

    return (Invoke-ManifestedNodeRuntimeInitialization -CommandName 'Initialize-NodeRuntime' -Refresh:$RefreshNode)
}
