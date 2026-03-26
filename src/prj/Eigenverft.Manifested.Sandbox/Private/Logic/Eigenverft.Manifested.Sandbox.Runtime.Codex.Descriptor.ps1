<#
    Eigenverft.Manifested.Sandbox.Runtime.Codex.Descriptor
#>

function Get-ManifestedCodexRuntimeRegistryDescriptor {
    [CmdletBinding()]
    param()

    return (New-ManifestedNpmCliRuntimeRegistryDescriptor -Definition (Get-ManifestedCodexNpmCliRuntimeDefinition))
}
