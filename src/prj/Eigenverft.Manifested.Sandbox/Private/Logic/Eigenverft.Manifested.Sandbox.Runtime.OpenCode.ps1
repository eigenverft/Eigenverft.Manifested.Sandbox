<#
    Eigenverft.Manifested.Sandbox.Cmd.OpenCodeRuntimeAndCache
#>

function ConvertTo-OpenCodeVersion {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    return (ConvertTo-ManifestedNpmCliVersion -VersionText $VersionText)
}

function ConvertTo-OpenCodeVersionObject {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    return (ConvertTo-ManifestedNpmCliVersionObject -VersionText $VersionText)
}

function Get-OpenCodeRuntimePackageJsonPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    return (Get-ManifestedNpmCliRuntimePackageJsonPath -Definition (Get-ManifestedOpenCodeNpmCliRuntimeDefinition) -RuntimeHome $RuntimeHome)
}

function Get-OpenCodeRuntimePackageVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageJsonPath
    )

    return (Get-ManifestedNpmCliRuntimePackageVersion -Definition (Get-ManifestedOpenCodeNpmCliRuntimeDefinition) -PackageJsonPath $PackageJsonPath)
}

function Test-OpenCodeRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    return (Test-ManifestedNpmCliRuntime -Definition (Get-ManifestedOpenCodeNpmCliRuntimeDefinition) -RuntimeHome $RuntimeHome)
}

function Get-InstalledOpenCodeRuntime {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Get-InstalledManifestedNpmCliRuntime -Definition (Get-ManifestedOpenCodeNpmCliRuntimeDefinition) -LocalRoot $LocalRoot)
}

function Get-ManifestedOpenCodeRuntimeFromCandidatePath {
    [CmdletBinding()]
    param(
        [string]$CandidatePath
    )

    return (Get-ManifestedNpmCliRuntimeFromCandidatePath -Definition (Get-ManifestedOpenCodeNpmCliRuntimeDefinition) -CandidatePath $CandidatePath)
}

function Get-SystemOpenCodeRuntime {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Get-SystemManifestedNpmCliRuntime -Definition (Get-ManifestedOpenCodeNpmCliRuntimeDefinition) -LocalRoot $LocalRoot)
}

function Get-OpenCodeRuntimeState {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Get-ManifestedNpmCliRuntimeState -Definition (Get-ManifestedOpenCodeNpmCliRuntimeDefinition) -LocalRoot $LocalRoot)
}

function Repair-OpenCodeRuntime {
    [CmdletBinding()]
    param(
        [pscustomobject]$State,
        [string[]]$CorruptRuntimeHomes = @(),
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Repair-ManifestedNpmCliRuntime -Definition (Get-ManifestedOpenCodeNpmCliRuntimeDefinition) -State $State -CorruptRuntimeHomes $CorruptRuntimeHomes -LocalRoot $LocalRoot)
}

function Install-OpenCodeRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NpmCmd,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Install-ManifestedNpmCliRuntime -Definition (Get-ManifestedOpenCodeNpmCliRuntimeDefinition) -NpmCmd $NpmCmd -LocalRoot $LocalRoot)
}
