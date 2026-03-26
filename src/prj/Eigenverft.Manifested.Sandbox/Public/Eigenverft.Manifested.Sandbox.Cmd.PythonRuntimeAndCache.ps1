<#
    Eigenverft.Manifested.Sandbox.Cmd.PythonRuntimeAndCache
#>

function Initialize-PythonRuntime {
<#
.SYNOPSIS
Ensures a managed or reusable Python runtime is available for the sandbox.

.DESCRIPTION
Discovers existing managed or external Python runtimes, repairs partial or
broken managed state, acquires a trusted CPython embeddable ZIP when needed,
installs the managed runtime, bootstraps pip, and synchronizes the command-line
environment so `python` resolves consistently for follow-up tooling.

.PARAMETER RefreshPython
Forces the managed Python package to be reacquired and reinstalled instead of
reusing the currently installed or cached copy.

.EXAMPLE
Initialize-PythonRuntime

.EXAMPLE
Initialize-PythonRuntime -RefreshPython

.NOTES
Supports `-WhatIf` and follows the module's shared state and environment
synchronization conventions for public runtime commands.
#>
    [Diagnostics.CodeAnalysis.SuppressMessage('PSShouldProcess', '', Justification = 'Thin facade delegates ShouldProcess handling to the shared Python runtime helper.')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshPython
    )

    return (Invoke-ManifestedPythonRuntimeInitialization -CommandName 'Initialize-PythonRuntime' -Refresh:$RefreshPython)
}
