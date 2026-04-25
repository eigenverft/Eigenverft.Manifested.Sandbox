<#
    Eigenverft.Manifested.Sandbox.Cmd.GHCliRuntime
#>

function Invoke-GHCliRuntime {
<#
.SYNOPSIS
Ensures the configured GitHub CLI runtime is available through PackageModel.

.DESCRIPTION
Loads the shipped PackageModel JSON documents through the neutral PackageModel
config loader, resolves the effective GitHub CLI release for the current
runtime context, saves the package file when needed, installs or reuses the
package, validates the installed package, applies PATH registration, updates
the ownership index, and returns the resolved entry points.

.EXAMPLE
Invoke-GHCliRuntime
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageModelDefinitionCommand -DefinitionId 'GHCliRuntime' -CommandName 'Invoke-GHCliRuntime')
}

