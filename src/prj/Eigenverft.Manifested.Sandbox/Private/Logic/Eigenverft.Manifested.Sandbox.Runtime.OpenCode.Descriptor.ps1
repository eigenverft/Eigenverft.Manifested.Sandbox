<#
    Eigenverft.Manifested.Sandbox.Runtime.OpenCode.Descriptor
#>

function Get-ManifestedOpenCodeRuntimeRegistryDescriptor {
    [CmdletBinding()]
    param()

    return (New-ManifestedNpmCliRuntimeRegistryDescriptor -Definition (Get-ManifestedOpenCodeNpmCliRuntimeDefinition))
}
