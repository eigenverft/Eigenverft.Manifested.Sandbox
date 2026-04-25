<#
    Eigenverft.Manifested.Sandbox.PackageModel.Cmd.PythonRuntime
#>

function Invoke-PackageModel-PythonRuntime {
<#
.SYNOPSIS
Ensures the configured Python runtime is available through PackageModel.

.DESCRIPTION
Loads the shipped PackageModel JSON documents, resolves the effective Python
release for the current runtime context, saves the package file when needed,
installs or reuses the package, validates python and module-based pip, applies
user PATH registration, updates ownership tracking, and returns resolved entry
points.

.EXAMPLE
Invoke-PackageModel-PythonRuntime
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageModelDefinitionCommand -DefinitionId 'PythonRuntime' -CommandName 'Invoke-PackageModel-PythonRuntime')
}
