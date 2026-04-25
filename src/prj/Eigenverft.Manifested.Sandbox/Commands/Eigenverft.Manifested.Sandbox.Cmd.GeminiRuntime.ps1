<#
    Eigenverft.Manifested.Sandbox.Cmd.GeminiRuntime
#>

function Invoke-GeminiRuntime {
<#
.SYNOPSIS
Ensures the configured Gemini CLI runtime is available through PackageModel.

.DESCRIPTION
Installs or reuses the pinned Gemini CLI npm package through the PackageModel
npm backend, using PackageModel-owned Node.js as the package-manager dependency.

.EXAMPLE
Invoke-GeminiRuntime
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageModelDefinitionCommand -DefinitionId 'GeminiRuntime' -CommandName 'Invoke-GeminiRuntime')
}

