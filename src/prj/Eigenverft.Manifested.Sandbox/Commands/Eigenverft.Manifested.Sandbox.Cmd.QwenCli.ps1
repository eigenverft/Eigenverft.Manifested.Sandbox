<#
    Eigenverft.Manifested.Sandbox.Cmd.QwenCli
#>

function Invoke-QwenCli {
<#
.SYNOPSIS
Ensures the configured Qwen CLI package is available through PackageModel.

.DESCRIPTION
Installs or reuses the pinned Qwen CLI npm package through the PackageModel
npm backend, using PackageModel-owned Node.js as the package-manager dependency.

.EXAMPLE
Invoke-QwenCli
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageModelDefinitionCommand -DefinitionId 'QwenCli' -CommandName 'Invoke-QwenCli')
}

