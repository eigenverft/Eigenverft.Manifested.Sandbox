<#
    Eigenverft.Manifested.Sandbox.Cmd.GeminiCli
#>

function Invoke-GeminiCli {
<#
.SYNOPSIS
Ensures the configured Gemini CLI package is available through PackageModel.

.DESCRIPTION
Installs or reuses the pinned Gemini CLI npm package through the PackageModel
npm backend, using PackageModel-owned Node.js as the package-manager dependency.

.EXAMPLE
Invoke-GeminiCli
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageModelDefinitionCommand -DefinitionId 'GeminiCli' -CommandName 'Invoke-GeminiCli')
}

