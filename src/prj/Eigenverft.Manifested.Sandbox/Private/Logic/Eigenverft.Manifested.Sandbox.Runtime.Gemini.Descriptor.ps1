<#
    Eigenverft.Manifested.Sandbox.Runtime.Gemini.Descriptor
#>

function Get-ManifestedGeminiRuntimeRegistryDescriptor {
    [CmdletBinding()]
    param()

    return (New-ManifestedNpmCliRuntimeRegistryDescriptor -Definition (Get-ManifestedGeminiNpmCliRuntimeDefinition))
}
