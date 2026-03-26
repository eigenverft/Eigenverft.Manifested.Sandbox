<#
    Eigenverft.Manifested.Sandbox.Runtime.Git.Install
#>

function Repair-GitRuntime {
    [CmdletBinding()]
    param(
        [pscustomobject]$State,
        [string[]]$CorruptPackagePaths = @(),
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $State) {
        $State = Get-GitRuntimeState -Flavor $Flavor -LocalRoot $LocalRoot
    }

    return (Repair-ManifestedArchiveRuntimeArtifacts -State $State -CorruptPackagePaths $CorruptPackagePaths)
}

function Install-GitRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo,

        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = if ($PackageInfo.Flavor) { $PackageInfo.Flavor } else { Get-GitFlavor }
    }

    $runtimeHome = Get-ManagedGitRuntimeHome -Version $PackageInfo.Version -Flavor $Flavor -LocalRoot $LocalRoot
    $installResult = Install-ManifestedArchiveRuntimeFromPackage -PackageInfo $PackageInfo -RuntimeHome $runtimeHome -StagePrefix 'git' -DisplayName 'MinGit' -TestRuntime {
        param($candidateRuntimeHome)
        Test-GitRuntime -RuntimeHome $candidateRuntimeHome
    }
    $validation = $installResult.Validation

    [pscustomobject]@{
        Action      = $installResult.Action
        TagName     = $PackageInfo.TagName
        Version     = $PackageInfo.Version
        Flavor      = $Flavor
        RuntimeHome = $runtimeHome
        GitCmd      = $validation.GitCmd
        Source      = $PackageInfo.Source
        DownloadUrl = $PackageInfo.DownloadUrl
        Sha256      = $PackageInfo.Sha256
    }
}

