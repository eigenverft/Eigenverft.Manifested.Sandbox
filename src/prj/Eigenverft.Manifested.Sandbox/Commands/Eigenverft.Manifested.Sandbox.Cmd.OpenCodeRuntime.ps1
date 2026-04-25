<#
    Eigenverft.Manifested.Sandbox.Cmd.OpenCodeRuntime
#>

function Invoke-OpenCodeRuntime {
<#
.SYNOPSIS
Ensures the configured OpenCode CLI runtime is available through PackageModel.

.DESCRIPTION
Installs or reuses the pinned OpenCode CLI npm package through the PackageModel
npm backend, using PackageModel-owned Node.js as the package-manager dependency.

.EXAMPLE
Invoke-OpenCodeRuntime
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageModelDefinitionCommand -DefinitionId 'OpenCodeRuntime' -CommandName 'Invoke-OpenCodeRuntime')
}

