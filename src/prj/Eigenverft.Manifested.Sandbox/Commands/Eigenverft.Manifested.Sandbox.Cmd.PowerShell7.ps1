<#
    Eigenverft.Manifested.Sandbox.Cmd.PowerShell7
#>

function Invoke-PowerShell7 {
<#
.SYNOPSIS
Ensures the configured PowerShell 7 runtime is available through Package.

.DESCRIPTION
Loads the shipped Package JSON documents, resolves the effective
PowerShell 7 release for the current runtime context, saves the package file
when needed, installs or reuses the package, validates pwsh, applies user PATH
registration, updates ownership tracking, and returns resolved entry points.

.EXAMPLE
Invoke-PowerShell7
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageDefinitionCommand -RepositoryId 'EigenverftModule' -DefinitionId 'PowerShell7' -DesiredState Assigned)
}

