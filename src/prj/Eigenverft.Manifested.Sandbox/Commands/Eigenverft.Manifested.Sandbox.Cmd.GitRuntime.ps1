<#
    Eigenverft.Manifested.Sandbox.Cmd.GitRuntime
#>

function Invoke-GitRuntime {
<#
.SYNOPSIS
Ensures the configured Git runtime is available through Package.

.DESCRIPTION
Loads the shipped Package JSON documents through the neutral Package
config loader, resolves the effective Git release for the current runtime
context, saves the package file when needed, installs or reuses the package,
validates the installed package, applies PATH registration, updates the
ownership index, and returns the resolved entry points.

.EXAMPLE
Invoke-GitRuntime
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageDefinitionCommand -DefinitionId 'GitRuntime' -CommandName 'Invoke-GitRuntime')
}

