<#
    Eigenverft.Manifested.Sandbox.Runtime.Codex.Package
#>

function Get-CodexRuntimePackageJsonPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    return (Get-ManifestedNpmCliRuntimePackageJsonPath -Definition (Get-ManifestedCodexNpmCliRuntimeDefinition) -RuntimeHome $RuntimeHome)
}

function Get-CodexRuntimePackageVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageJsonPath
    )

    return (Get-ManifestedNpmCliRuntimePackageVersion -Definition (Get-ManifestedCodexNpmCliRuntimeDefinition) -PackageJsonPath $PackageJsonPath)
}

