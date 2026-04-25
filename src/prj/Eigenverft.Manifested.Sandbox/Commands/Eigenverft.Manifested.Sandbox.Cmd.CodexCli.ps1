<#
    Eigenverft.Manifested.Sandbox.Cmd.CodexCli
#>

function Invoke-CodexCli {
<#
.SYNOPSIS
Ensures the configured Codex CLI package is available through PackageModel.

.DESCRIPTION
Installs or reuses the pinned Codex CLI npm package through the PackageModel
npm backend, using PackageModel-owned Node.js as the package-manager dependency.

.EXAMPLE
Invoke-CodexCli
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageModelDefinitionCommand -DefinitionId 'CodexCli' -CommandName 'Invoke-CodexCli')
}

