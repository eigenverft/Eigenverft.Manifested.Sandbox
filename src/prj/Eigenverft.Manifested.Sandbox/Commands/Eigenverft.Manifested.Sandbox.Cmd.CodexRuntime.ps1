<#
    Eigenverft.Manifested.Sandbox.Cmd.CodexRuntime
#>

function Invoke-CodexRuntime {
<#
.SYNOPSIS
Ensures the configured Codex CLI runtime is available through PackageModel.

.DESCRIPTION
Installs or reuses the pinned Codex CLI npm package through the PackageModel
npm backend, using PackageModel-owned Node.js as the package-manager dependency.

.EXAMPLE
Invoke-CodexRuntime
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageModelDefinitionCommand -DefinitionId 'CodexRuntime' -CommandName 'Invoke-CodexRuntime')
}

