<#
    Eigenverft.Manifested.Sandbox.Cmd.GeminiCli
#>

function Invoke-GeminiCli {
<#
.SYNOPSIS
Ensures the configured Gemini CLI package is available through Package.

.DESCRIPTION
Installs or reuses the pinned Gemini CLI npm package through the Package
npm backend, using Package-owned Node.js as the package-manager dependency.

.EXAMPLE
Invoke-GeminiCli
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageDefinitionCommand -DefinitionId 'GeminiCli' -CommandName 'Invoke-GeminiCli')
}

