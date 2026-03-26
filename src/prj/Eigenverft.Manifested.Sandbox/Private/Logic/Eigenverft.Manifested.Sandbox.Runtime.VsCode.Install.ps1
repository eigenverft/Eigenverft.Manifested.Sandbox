<#
    Eigenverft.Manifested.Sandbox.Runtime.VsCode.Install
#>

function Repair-VSCodeRuntime {
    [CmdletBinding()]
    param(
        [pscustomobject]$State,
        [string[]]$CorruptPackagePaths = @(),
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $State) {
        $State = Get-VSCodeRuntimeState -Flavor $Flavor -LocalRoot $LocalRoot
    }

    return (Repair-ManifestedArchiveRuntimeArtifacts -State $State -CorruptPackagePaths $CorruptPackagePaths)
}

function Install-VSCodeRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo,

        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = if ($PackageInfo.Flavor) { $PackageInfo.Flavor } else { Get-VSCodeFlavor }
    }

    $runtimeHome = Get-ManagedVSCodeRuntimeHome -Version $PackageInfo.Version -Flavor $Flavor -LocalRoot $LocalRoot
    $installResult = Install-ManifestedArchiveRuntimeFromPackage -PackageInfo $PackageInfo -RuntimeHome $runtimeHome -StagePrefix 'vscode' -DisplayName 'VS Code' -TestRuntime {
        param($candidateRuntimeHome)
        Test-VSCodeRuntime -RuntimeHome $candidateRuntimeHome -RequirePortableMode
    } -PostInstall {
        param($candidateRuntimeHome)
        New-ManifestedDirectory -Path (Join-Path $candidateRuntimeHome 'data') | Out-Null
    }
    $validation = $installResult.Validation

    [pscustomobject]@{
        Action       = $installResult.Action
        TagName      = $PackageInfo.TagName
        Version      = $PackageInfo.Version
        Flavor       = $Flavor
        Channel      = $PackageInfo.Channel
        RuntimeHome  = $runtimeHome
        CodePath     = $validation.CodePath
        CodeCmd      = $validation.CodeCmd
        PortableMode = $validation.PortableMode
        Source       = $PackageInfo.Source
        DownloadUrl  = $PackageInfo.DownloadUrl
        Sha256       = $PackageInfo.Sha256
    }
}

