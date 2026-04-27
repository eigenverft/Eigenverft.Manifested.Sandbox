<#
    Eigenverft.Manifested.Sandbox.Cmd.OpenCodeCli
#>

function Invoke-OpenCodeCli {
<#
.SYNOPSIS
Ensures the configured OpenCode CLI package is available through Package.

.DESCRIPTION
Installs or reuses the pinned OpenCode CLI npm package through the Package
npm backend, using Package-owned Node.js as the package-manager dependency.

.EXAMPLE
Invoke-OpenCodeCli
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageDefinitionCommand -DefinitionId 'OpenCodeCli' -CommandName 'Invoke-OpenCodeCli')
}

