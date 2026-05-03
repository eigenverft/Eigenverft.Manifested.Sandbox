<#
    Eigenverft.Manifested.Sandbox.Cmd.PythonRuntime
#>

function Invoke-PythonRuntime {
<#
.SYNOPSIS
Ensures the configured Python runtime is available through Package.

.DESCRIPTION
Loads the shipped Package JSON documents, resolves the effective Python
release for the current runtime context, saves the package file when needed,
installs or reuses the package, validates python and module-based pip, applies
user PATH registration, updates package inventory, and returns resolved entry
points.

.EXAMPLE
Invoke-PythonRuntime
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageDefinitionCommand -RepositoryId 'EigenverftModule' -DefinitionId 'PythonRuntime' -DesiredState Assigned)
}

