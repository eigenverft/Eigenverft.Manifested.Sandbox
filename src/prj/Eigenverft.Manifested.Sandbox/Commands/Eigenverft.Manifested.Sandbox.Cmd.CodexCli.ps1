<#
    Eigenverft.Manifested.Sandbox.Cmd.CodexCli
#>

function Invoke-CodexCli {
<#
.SYNOPSIS
Ensures the configured Codex CLI package is available through Package.

.DESCRIPTION
Installs or reuses the pinned Codex CLI npm package through the Package
npm backend, using Package-owned Node.js as the package-manager dependency.

.EXAMPLE
Invoke-CodexCli
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageDefinitionCommand -DefinitionId 'CodexCli' -CommandName 'Invoke-CodexCli')
}

