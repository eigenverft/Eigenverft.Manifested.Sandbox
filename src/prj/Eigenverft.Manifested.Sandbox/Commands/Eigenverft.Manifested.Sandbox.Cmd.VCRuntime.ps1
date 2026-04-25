<#
    Eigenverft.Manifested.Sandbox.Cmd.VCRuntime
#>

function Invoke-VCRuntime {
<#
.SYNOPSIS
Ensures the configured Microsoft Visual C++ Runtime prerequisite is present.

.DESCRIPTION
Loads the shipped PackageModel JSON documents, validates whether the machine
prerequisite is already satisfied, and only acquires and runs the signed
installer when the registry checks show the runtime is missing.

.EXAMPLE
Invoke-VCRuntime
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageModelDefinitionCommand -DefinitionId 'VCRuntime' -CommandName 'Invoke-VCRuntime')
}

