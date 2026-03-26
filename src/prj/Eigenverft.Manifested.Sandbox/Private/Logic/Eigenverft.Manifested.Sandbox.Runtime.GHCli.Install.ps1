<#
    Eigenverft.Manifested.Sandbox.Runtime.GHCli.Install
#>

function Repair-GHCliRuntime {
    [CmdletBinding()]
    param(
        [pscustomobject]$State,
        [string[]]$CorruptPackagePaths = @(),
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $State) {
        $State = Get-GHCliRuntimeState -Flavor $Flavor -LocalRoot $LocalRoot
    }

    return (Repair-ManifestedArchiveRuntimeArtifacts -State $State -CorruptPackagePaths $CorruptPackagePaths)
}

function Install-GHCliRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo,

        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = if ($PackageInfo.Flavor) { $PackageInfo.Flavor } else { Get-GHCliFlavor }
    }

    $runtimeHome = Get-ManagedGHCliRuntimeHome -Version $PackageInfo.Version -Flavor $Flavor -LocalRoot $LocalRoot
    $installResult = Install-ManifestedArchiveRuntimeFromPackage -PackageInfo $PackageInfo -RuntimeHome $runtimeHome -StagePrefix 'ghcli' -DisplayName 'GitHub CLI' -TestRuntime {
        param($candidateRuntimeHome)
        Test-GHCliRuntime -RuntimeHome $candidateRuntimeHome
    }
    $validation = $installResult.Validation

    [pscustomobject]@{
        Action      = $installResult.Action
        TagName     = $PackageInfo.TagName
        Version     = $PackageInfo.Version
        Flavor      = $Flavor
        RuntimeHome = $runtimeHome
        GhCmd       = $validation.GhCmd
        Source      = $PackageInfo.Source
        DownloadUrl = $PackageInfo.DownloadUrl
        Sha256      = $PackageInfo.Sha256
    }
}

