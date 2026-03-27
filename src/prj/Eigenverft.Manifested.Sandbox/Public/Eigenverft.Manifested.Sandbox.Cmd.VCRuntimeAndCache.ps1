<#
    Eigenverft.Manifested.Sandbox.Cmd.VCRuntimeAndCache
#>

function Initialize-VCRuntime {
<#
.SYNOPSIS
Ensures the managed VC runtime prerequisite is available for dependent tools.

.DESCRIPTION
Uses the shared runtime kernel to compute facts, acquire and validate the
installer when needed, and execute the machine-prerequisite install flow.

.PARAMETER RefreshVCRuntime
Forces reacquisition and reinstall planning for the cached installer.

.PARAMETER InstallTimeoutSec
Sets the installer timeout in seconds for the managed VC prerequisite flow.

.EXAMPLE
Initialize-VCRuntime

.EXAMPLE
Initialize-VCRuntime -RefreshVCRuntime -InstallTimeoutSec 600
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshVCRuntime,
        [int]$InstallTimeoutSec = 300
    )

    return (Invoke-ManifestedCommandInitialization -Name 'Initialize-VCRuntime' -PSCmdletObject $PSCmdlet -RefreshRequested:$RefreshVCRuntime -CommandOptions @{
            InstallTimeoutSec = $InstallTimeoutSec
        } -WhatIfMode:$WhatIfPreference)
}
