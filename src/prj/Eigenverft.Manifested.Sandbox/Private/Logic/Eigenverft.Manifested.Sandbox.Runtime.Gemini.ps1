<#
    Eigenverft.Manifested.Sandbox.Cmd.GeminiRuntimeAndCache
#>

function ConvertTo-GeminiVersion {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    return (ConvertTo-ManifestedNpmCliVersion -VersionText $VersionText)
}

function ConvertTo-GeminiVersionObject {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    return (ConvertTo-ManifestedNpmCliVersionObject -VersionText $VersionText)
}

function Get-GeminiRuntimePackageJsonPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    return (Get-ManifestedNpmCliRuntimePackageJsonPath -Definition (Get-ManifestedGeminiNpmCliRuntimeDefinition) -RuntimeHome $RuntimeHome)
}

function Get-GeminiRuntimePackageVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageJsonPath
    )

    return (Get-ManifestedNpmCliRuntimePackageVersion -Definition (Get-ManifestedGeminiNpmCliRuntimeDefinition) -PackageJsonPath $PackageJsonPath)
}

function Test-GeminiRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    return (Test-ManifestedNpmCliRuntime -Definition (Get-ManifestedGeminiNpmCliRuntimeDefinition) -RuntimeHome $RuntimeHome)
}

function Get-InstalledGeminiRuntime {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Get-InstalledManifestedNpmCliRuntime -Definition (Get-ManifestedGeminiNpmCliRuntimeDefinition) -LocalRoot $LocalRoot)
}

function Get-ManifestedGeminiRuntimeFromCandidatePath {
    [CmdletBinding()]
    param(
        [string]$CandidatePath
    )

    return (Get-ManifestedNpmCliRuntimeFromCandidatePath -Definition (Get-ManifestedGeminiNpmCliRuntimeDefinition) -CandidatePath $CandidatePath)
}

function Get-SystemGeminiRuntime {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Get-SystemManifestedNpmCliRuntime -Definition (Get-ManifestedGeminiNpmCliRuntimeDefinition) -LocalRoot $LocalRoot)
}

function Get-GeminiRuntimeState {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Get-ManifestedNpmCliRuntimeState -Definition (Get-ManifestedGeminiNpmCliRuntimeDefinition) -LocalRoot $LocalRoot)
}

function Repair-GeminiRuntime {
    [CmdletBinding()]
    param(
        [pscustomobject]$State,
        [string[]]$CorruptRuntimeHomes = @(),
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Repair-ManifestedNpmCliRuntime -Definition (Get-ManifestedGeminiNpmCliRuntimeDefinition) -State $State -CorruptRuntimeHomes $CorruptRuntimeHomes -LocalRoot $LocalRoot)
}

function Install-GeminiRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NpmCmd,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Install-ManifestedNpmCliRuntime -Definition (Get-ManifestedGeminiNpmCliRuntimeDefinition) -NpmCmd $NpmCmd -LocalRoot $LocalRoot)
}


