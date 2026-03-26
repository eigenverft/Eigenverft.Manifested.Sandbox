<#
    Eigenverft.Manifested.Sandbox.Runtime.Qwen.Descriptor
#>

function Get-ManifestedQwenRuntimeRegistryDescriptor {
    [CmdletBinding()]
    param()

    return (New-ManifestedNpmCliRuntimeRegistryDescriptor -Definition (Get-ManifestedQwenNpmCliRuntimeDefinition))
}
