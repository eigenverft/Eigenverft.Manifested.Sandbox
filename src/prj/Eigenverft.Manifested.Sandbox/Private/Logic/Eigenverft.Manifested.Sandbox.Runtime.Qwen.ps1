<#
    Eigenverft.Manifested.Sandbox.Cmd.QwenRuntimeAndCache
#>

function ConvertTo-QwenVersion {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    return (ConvertTo-ManifestedNpmCliVersion -VersionText $VersionText)
}

function ConvertTo-QwenVersionObject {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    return (ConvertTo-ManifestedNpmCliVersionObject -VersionText $VersionText)
}

function Get-QwenRuntimePackageJsonPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    return (Get-ManifestedNpmCliRuntimePackageJsonPath -Definition (Get-ManifestedQwenNpmCliRuntimeDefinition) -RuntimeHome $RuntimeHome)
}

function Get-QwenRuntimePackageVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageJsonPath
    )

    return (Get-ManifestedNpmCliRuntimePackageVersion -Definition (Get-ManifestedQwenNpmCliRuntimeDefinition) -PackageJsonPath $PackageJsonPath)
}

function Test-QwenRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    return (Test-ManifestedNpmCliRuntime -Definition (Get-ManifestedQwenNpmCliRuntimeDefinition) -RuntimeHome $RuntimeHome)
}

function Get-InstalledQwenRuntime {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Get-InstalledManifestedNpmCliRuntime -Definition (Get-ManifestedQwenNpmCliRuntimeDefinition) -LocalRoot $LocalRoot)
}

function Get-ManifestedQwenRuntimeFromCandidatePath {
    [CmdletBinding()]
    param(
        [string]$CandidatePath
    )

    return (Get-ManifestedNpmCliRuntimeFromCandidatePath -Definition (Get-ManifestedQwenNpmCliRuntimeDefinition) -CandidatePath $CandidatePath)
}

function Get-SystemQwenRuntime {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Get-SystemManifestedNpmCliRuntime -Definition (Get-ManifestedQwenNpmCliRuntimeDefinition) -LocalRoot $LocalRoot)
}

function Get-QwenRuntimeState {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Get-ManifestedNpmCliRuntimeState -Definition (Get-ManifestedQwenNpmCliRuntimeDefinition) -LocalRoot $LocalRoot)
}

function Repair-QwenRuntime {
    [CmdletBinding()]
    param(
        [pscustomobject]$State,
        [string[]]$CorruptRuntimeHomes = @(),
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Repair-ManifestedNpmCliRuntime -Definition (Get-ManifestedQwenNpmCliRuntimeDefinition) -State $State -CorruptRuntimeHomes $CorruptRuntimeHomes -LocalRoot $LocalRoot)
}

function Install-QwenRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NpmCmd,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Install-ManifestedNpmCliRuntime -Definition (Get-ManifestedQwenNpmCliRuntimeDefinition) -NpmCmd $NpmCmd -LocalRoot $LocalRoot)
}
