<#
    Eigenverft.Manifested.Sandbox.Cmd.VisualCppRedistributable
#>

function Invoke-VisualCppRedistributable {
<#
.SYNOPSIS
Ensures the configured Microsoft Visual C++ Redistributable prerequisite is present.

.DESCRIPTION
Loads the shipped PackageModel JSON documents, validates whether the machine
prerequisite is already satisfied, and only acquires and runs the signed
installer when the registry checks show the runtime is missing.

.EXAMPLE
Invoke-VisualCppRedistributable
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageModelDefinitionCommand -DefinitionId 'VisualCppRedistributable' -CommandName 'Invoke-VisualCppRedistributable')
}

