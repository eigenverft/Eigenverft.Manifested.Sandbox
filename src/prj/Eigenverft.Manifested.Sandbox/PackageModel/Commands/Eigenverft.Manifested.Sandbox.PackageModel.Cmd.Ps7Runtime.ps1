<#
    Eigenverft.Manifested.Sandbox.PackageModel.Cmd.Ps7Runtime
#>

function Invoke-PackageModel-Ps7Runtime {
<#
.SYNOPSIS
Ensures the configured PowerShell 7 runtime is available through PackageModel.

.DESCRIPTION
Loads the shipped PackageModel JSON documents, resolves the effective
PowerShell 7 release for the current runtime context, saves the package file
when needed, installs or reuses the package, validates pwsh, applies user PATH
registration, updates ownership tracking, and returns resolved entry points.

.EXAMPLE
Invoke-PackageModel-Ps7Runtime
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageModelDefinitionCommand -DefinitionId 'Ps7Runtime' -CommandName 'Invoke-PackageModel-Ps7Runtime')
}
