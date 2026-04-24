<#
    Eigenverft.Manifested.Sandbox.PackageModel.Cmd.GitRuntime
#>

function Invoke-PackageModel-GitRuntime {
<#
.SYNOPSIS
Ensures the configured Git runtime is available through PackageModel.

.DESCRIPTION
Loads the shipped PackageModel JSON documents through the neutral PackageModel
config loader, resolves the effective Git release for the current runtime
context, saves the package file when needed, installs or reuses the package,
validates the installed package, applies PATH registration, updates the
ownership index, and returns the resolved entry points.

.EXAMPLE
Invoke-PackageModel-GitRuntime
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageModelDefinitionCommand -DefinitionId 'GitRuntime' -CommandName 'Invoke-PackageModel-GitRuntime')
}
