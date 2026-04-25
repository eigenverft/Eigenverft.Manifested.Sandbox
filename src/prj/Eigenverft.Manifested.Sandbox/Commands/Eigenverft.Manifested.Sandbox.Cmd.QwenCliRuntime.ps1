<#
    Eigenverft.Manifested.Sandbox.Cmd.QwenCliRuntime
#>

function Invoke-QwenCliRuntime {
<#
.SYNOPSIS
Ensures the configured Qwen CLI runtime is available through PackageModel.

.DESCRIPTION
Installs or reuses the pinned Qwen CLI npm package through the PackageModel
npm backend, using PackageModel-owned Node.js as the package-manager dependency.

.EXAMPLE
Invoke-QwenCliRuntime
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageModelDefinitionCommand -DefinitionId 'QwenCliRuntime' -CommandName 'Invoke-QwenCliRuntime')
}

