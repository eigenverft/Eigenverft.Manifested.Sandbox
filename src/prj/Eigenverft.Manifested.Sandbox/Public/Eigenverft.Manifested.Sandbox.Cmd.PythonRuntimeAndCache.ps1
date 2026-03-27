<#
    Eigenverft.Manifested.Sandbox.Cmd.PythonRuntimeAndCache
#>

function Initialize-PythonRuntime {
<#
.SYNOPSIS
Ensures a managed or reusable Python runtime is available for the sandbox.

.DESCRIPTION
Routes Python runtime initialization through the shared block-driven kernel and
the packaged command definition for Python.

.PARAMETER RefreshPython
Forces reacquisition or reinstall planning for the managed Python runtime.

.EXAMPLE
Initialize-PythonRuntime

.EXAMPLE
Initialize-PythonRuntime -RefreshPython
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshPython
    )

    return (Invoke-ManifestedCommandInitialization -Name 'Initialize-PythonRuntime' -PSCmdletObject $PSCmdlet -RefreshRequested:$RefreshPython -WhatIfMode:$WhatIfPreference)
}
