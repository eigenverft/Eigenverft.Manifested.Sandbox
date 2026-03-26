<#
    Eigenverft.Manifested.Sandbox.Cmd.VCRuntimeAndCache
#>

function Initialize-VCRuntime {
<#
.SYNOPSIS
Ensures the VC runtime prerequisite is available for the sandbox toolchain.

.DESCRIPTION
Delegates VC runtime orchestration to the shared machine-prerequisite runtime
helper, which repairs partial state, acquires the installer when needed,
installs the prerequisite, and preserves restart-required signaling.

.PARAMETER RefreshVCRuntime
Forces the VC runtime installer to be reacquired and rerun instead of reusing a
cached ready state when possible.

.PARAMETER InstallTimeoutSec
Maximum number of seconds to wait for the VC runtime installer to complete.

.EXAMPLE
Initialize-VCRuntime

.EXAMPLE
Initialize-VCRuntime -RefreshVCRuntime -InstallTimeoutSec 600

.NOTES
Supports `-WhatIf` and keeps the public command as a thin facade over the
shared runtime-family flow.
#>
    [Diagnostics.CodeAnalysis.SuppressMessage('PSShouldProcess', '', Justification = 'Thin facade delegates ShouldProcess handling to the shared machine-prerequisite runtime helper.')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshVCRuntime,
        [int]$InstallTimeoutSec = 300
    )

    return (Invoke-ManifestedMachinePrerequisiteRuntimeInitialization -CommandName 'Initialize-VCRuntime' -Refresh:$RefreshVCRuntime -InstallTimeoutSec $InstallTimeoutSec)
}
