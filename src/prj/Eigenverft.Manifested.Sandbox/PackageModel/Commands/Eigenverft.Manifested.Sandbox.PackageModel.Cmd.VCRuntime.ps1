<#
    Eigenverft.Manifested.Sandbox.PackageModel.Cmd.VCRuntime
#>

function Invoke-PackageModel-VCRuntime {
<#
.SYNOPSIS
Ensures the configured Microsoft Visual C++ Runtime prerequisite is present.

.DESCRIPTION
Loads the shipped PackageModel JSON documents, validates whether the machine
prerequisite is already satisfied, and only acquires and runs the signed
installer when the registry checks show the runtime is missing.

.EXAMPLE
Invoke-PackageModel-VCRuntime
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageModelDefinitionCommand -DefinitionId 'VCRuntime' -CommandName 'Invoke-PackageModel-VCRuntime')
}
