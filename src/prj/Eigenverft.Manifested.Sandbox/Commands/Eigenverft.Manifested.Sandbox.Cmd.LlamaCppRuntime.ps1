<#
    Eigenverft.Manifested.Sandbox.Cmd.LlamaCppRuntime
#>

function Invoke-LlamaCppRuntime {
<#
.SYNOPSIS
Ensures the configured llama.cpp package is available through Package.

.DESCRIPTION
Loads the shipped Package JSON documents through the neutral Package
config loader, resolves the effective llama.cpp release for the current
runtime context, evaluates existing-install ownership and policy, saves the
package file when needed, installs or reuses the package, validates the
installed package, updates the ownership index, and returns the resolved entry
points.

.EXAMPLE
Invoke-LlamaCppRuntime
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageDefinitionCommand -RepositoryId 'EigenverftModule' -DefinitionId 'LlamaCppRuntime' -DesiredState Assigned)
}

