<#
    Eigenverft.Manifested.Sandbox.Cmd.QwenCli
#>

function Invoke-QwenCli {
<#
.SYNOPSIS
Ensures the configured Qwen CLI package is available through Package.

.DESCRIPTION
Installs or reuses the pinned Qwen CLI npm package through the Package
npm backend, using Package-owned Node.js as the package-manager dependency.

.EXAMPLE
Invoke-QwenCli
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageDefinitionCommand -RepositoryId 'EigenverftModule' -DefinitionId 'QwenCli' -DesiredState Assigned)
}

