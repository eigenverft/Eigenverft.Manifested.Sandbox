<#
    Eigenverft.Manifested.Sandbox.Cmd.GitHubCli
#>

function Invoke-GitHubCli {
<#
.SYNOPSIS
Ensures the configured GitHub CLI package is available through PackageModel.

.DESCRIPTION
Loads the shipped PackageModel JSON documents through the neutral PackageModel
config loader, resolves the effective GitHub CLI release for the current
runtime context, saves the package file when needed, installs or reuses the
package, validates the installed package, applies PATH registration, updates
the ownership index, and returns the resolved entry points.

.EXAMPLE
Invoke-GitHubCli
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageModelDefinitionCommand -DefinitionId 'GitHubCli' -CommandName 'Invoke-GitHubCli')
}

