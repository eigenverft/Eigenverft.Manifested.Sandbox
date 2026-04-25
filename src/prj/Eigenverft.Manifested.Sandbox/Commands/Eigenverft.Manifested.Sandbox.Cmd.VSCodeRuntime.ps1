<#
    Eigenverft.Manifested.Sandbox.Cmd.VSCodeRuntime
#>

function Invoke-VSCodeRuntime {
<#
.SYNOPSIS
Ensures the configured VS Code package is available through PackageModel.

.DESCRIPTION
Loads the shipped PackageModel JSON documents through the neutral PackageModel
config loader, resolves the effective VS Code release for the current runtime
context, evaluates existing-install ownership and policy, saves the package
file when needed, installs or reuses the package, validates the installed
package, updates the ownership index, and returns the resolved entry points.

.EXAMPLE
Invoke-VSCodeRuntime
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageModelDefinitionCommand -DefinitionId 'VSCodeRuntime' -CommandName 'Invoke-VSCodeRuntime')
}

