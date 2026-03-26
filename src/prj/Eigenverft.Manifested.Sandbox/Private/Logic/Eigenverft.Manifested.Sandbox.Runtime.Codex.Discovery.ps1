<#
    Eigenverft.Manifested.Sandbox.Runtime.Codex.Discovery
#>

function ConvertTo-CodexVersion {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    return (ConvertTo-ManifestedNpmCliVersion -VersionText $VersionText)
}

function ConvertTo-CodexVersionObject {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    return (ConvertTo-ManifestedNpmCliVersionObject -VersionText $VersionText)
}

function Get-InstalledCodexRuntime {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Get-InstalledManifestedNpmCliRuntime -Definition (Get-ManifestedCodexNpmCliRuntimeDefinition) -LocalRoot $LocalRoot)
}

function Get-ManifestedCodexRuntimeFromCandidatePath {
    [CmdletBinding()]
    param(
        [string]$CandidatePath
    )

    return (Get-ManifestedNpmCliRuntimeFromCandidatePath -Definition (Get-ManifestedCodexNpmCliRuntimeDefinition) -CandidatePath $CandidatePath)
}

function Get-SystemCodexRuntime {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Get-SystemManifestedNpmCliRuntime -Definition (Get-ManifestedCodexNpmCliRuntimeDefinition) -LocalRoot $LocalRoot)
}

function Get-CodexRuntimeState {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Get-ManifestedNpmCliRuntimeState -Definition (Get-ManifestedCodexNpmCliRuntimeDefinition) -LocalRoot $LocalRoot)
}

