<#
    Eigenverft.Manifested.Sandbox.Runtime.Archive.Shared
#>

function Get-ManifestedArchivePersistedPackageDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $commandState = Get-ManifestedCommandState -CommandName $CommandName -LocalRoot $LocalRoot
    if ($commandState -and $commandState.PSObject.Properties['Details']) {
        return $commandState.Details
    }

    return $null
}

function Get-ManagedManifestedArchiveRuntimeHome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolsRootPath,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$Flavor
    )

    return (Join-Path $ToolsRootPath ($Version + '\' + $Flavor))
}

function Get-ManifestedArchivePersistedAssetDetails {
    [CmdletBinding()]
    param(
        [pscustomobject]$PersistedDetails,

        [Parameter(Mandatory = $true)]
        [string]$AssetName
    )

    if (-not $PersistedDetails) {
        return $null
    }
    if (-not $PersistedDetails.PSObject.Properties['AssetName']) {
        return $null
    }
    if ($PersistedDetails.AssetName -ne $AssetName) {
        return $null
    }

    return [pscustomobject]@{
        TagName     = if ($PersistedDetails.PSObject.Properties['Tag']) { $PersistedDetails.Tag } else { $null }
        DownloadUrl = if ($PersistedDetails.PSObject.Properties['DownloadUrl']) { $PersistedDetails.DownloadUrl } else { $null }
        Sha256      = if ($PersistedDetails.PSObject.Properties['Sha256']) { $PersistedDetails.Sha256 } else { $null }
        ShaSource   = if ($PersistedDetails.PSObject.Properties['ShaSource']) { $PersistedDetails.ShaSource } else { $null }
        Channel     = if ($PersistedDetails.PSObject.Properties['Channel']) { $PersistedDetails.Channel } else { $null }
    }
}

function Get-ManifestedArchiveCachedPackages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CacheRootPath,

        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [Parameter(Mandatory = $true)]
        [scriptblock]$BuildPackageInfo,

        [Parameter(Mandatory = $true)]
        [scriptblock]$SortVersion,

        [string]$FileFilter = '*.zip'
    )

    if (-not (Test-Path -LiteralPath $CacheRootPath)) {
        return @()
    }

    $items = Get-ChildItem -LiteralPath $CacheRootPath -File -Filter $FileFilter -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $Pattern } |
        ForEach-Object {
            $matchTable = @{}
            foreach ($matchKey in @($matches.Keys)) {
                $matchTable[$matchKey] = $matches[$matchKey]
            }

            & $BuildPackageInfo $_ $matchTable
        } |
        Sort-Object -Descending -Property @{ Expression = { & $SortVersion $_ } }

    return @($items)
}

function Get-LatestManifestedArchiveRuntimePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$CachedPackages
    )

    $trustedPackage = @($CachedPackages | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Sha256) } | Select-Object -First 1)
    if ($trustedPackage) {
        return $trustedPackage[0]
    }

    return ($CachedPackages | Select-Object -First 1)
}

function Get-ManifestedArchiveRuntimePartialPaths {
    [CmdletBinding()]
    param(
        [string]$CacheRootPath,

        [Parameter(Mandatory = $true)]
        [string]$StagePrefix,

        [string[]]$LegacyRootPaths = @()
    )

    $partialPaths = @()
    if (-not [string]::IsNullOrWhiteSpace($CacheRootPath) -and (Test-Path -LiteralPath $CacheRootPath)) {
        $partialPaths += @(Get-ChildItem -LiteralPath $CacheRootPath -File -Filter '*.download' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    }

    $partialPaths += @(
        Get-ManifestedStageDirectories -Prefix $StagePrefix -Mode TemporaryShort -LegacyRootPaths $LegacyRootPaths |
            Select-Object -ExpandProperty FullName
    )

    return @($partialPaths)
}

function Get-ManifestedArchiveRuntimeSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Installed,

        [pscustomobject]$ExternalRuntime,

        [pscustomobject]$Package,

        [string[]]$PartialPaths = @()
    )

    $managedRuntime = $Installed.Current
    $currentRuntime = if ($managedRuntime) { $managedRuntime } else { $ExternalRuntime }
    $runtimeSource = if ($managedRuntime) { 'Managed' } elseif ($ExternalRuntime) { 'External' } else { $null }
    $invalidRuntimeHomes = @($Installed.Invalid | Select-Object -ExpandProperty RuntimeHome)

    if ($invalidRuntimeHomes.Count -gt 0) {
        $status = 'NeedsRepair'
    }
    elseif (@($PartialPaths).Count -gt 0) {
        $status = 'Partial'
    }
    elseif ($currentRuntime) {
        $status = 'Ready'
    }
    elseif ($Package) {
        $status = 'NeedsInstall'
    }
    else {
        $status = 'Missing'
    }

    [pscustomobject]@{
        Status              = $status
        CurrentRuntime      = $currentRuntime
        RuntimeSource       = $runtimeSource
        InvalidRuntimeHomes = $invalidRuntimeHomes
    }
}

function Repair-ManifestedArchiveRuntimeArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$State,

        [string[]]$CorruptPackagePaths = @()
    )

    $pathsToRemove = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($State.PartialPaths)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $pathsToRemove.Add($path) | Out-Null
        }
    }
    foreach ($path in @($State.InvalidRuntimeHomes)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $pathsToRemove.Add($path) | Out-Null
        }
    }
    foreach ($path in @($CorruptPackagePaths)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $pathsToRemove.Add($path) | Out-Null
        }
    }

    $removedPaths = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($pathsToRemove | Select-Object -Unique)) {
        if (Remove-ManifestedPath -Path $path) {
            $removedPaths.Add($path) | Out-Null
        }
    }

    [pscustomobject]@{
        Action       = if ($removedPaths.Count -gt 0) { 'Repaired' } else { 'Skipped' }
        RemovedPaths = @($removedPaths)
        LocalRoot    = $State.LocalRoot
        Layout       = $State.Layout
    }
}

function Save-ManifestedArchiveRuntimePackage {
    [CmdletBinding()]
    param(
        [pscustomobject]$Release,

        [switch]$Refresh,

        [Parameter(Mandatory = $true)]
        [string]$CacheRootPath,

        [Parameter(Mandatory = $true)]
        [scriptblock]$GetCachedPackage,

        [Parameter(Mandatory = $true)]
        [string]$DownloadLabel,

        [Parameter(Mandatory = $true)]
        [string]$RefreshWarningPrefix,

        [Parameter(Mandatory = $true)]
        [string]$OfflineErrorMessage
    )

    New-ManifestedDirectory -Path $CacheRootPath | Out-Null

    if ($Release) {
        $packagePath = Join-Path $CacheRootPath $Release.FileName
        $downloadPath = Get-ManifestedDownloadPath -TargetPath $packagePath
        $action = 'ReusedCache'

        if ($Refresh -or -not (Test-Path -LiteralPath $packagePath)) {
            Remove-ManifestedPath -Path $downloadPath | Out-Null

            try {
                Write-Host ("Downloading {0} {1} ({2})..." -f $DownloadLabel, $Release.Version, $Release.Flavor)
                Enable-ManifestedTls12Support
                Invoke-WebRequestEx -Uri $Release.DownloadUrl -Headers @{ 'User-Agent' = 'Eigenverft.Manifested.Sandbox' } -OutFile $downloadPath -UseBasicParsing
                Move-Item -LiteralPath $downloadPath -Destination $packagePath -Force
                $action = 'Downloaded'
            }
            catch {
                Remove-ManifestedPath -Path $downloadPath | Out-Null
                if (-not (Test-Path -LiteralPath $packagePath)) {
                    throw
                }

                Write-Warning ($RefreshWarningPrefix + $_.Exception.Message)
                $action = 'ReusedCache'
            }
        }

        $packageProperties = [ordered]@{}
        foreach ($property in @($Release.PSObject.Properties)) {
            $packageProperties[$property.Name] = $property.Value
        }
        $packageProperties['Path'] = $packagePath
        $packageProperties['Source'] = if ($action -eq 'Downloaded') { 'online' } else { 'cache' }
        $packageProperties['Action'] = $action
        return [pscustomobject]$packageProperties
    }

    $cachedPackage = & $GetCachedPackage
    if (-not $cachedPackage) {
        throw $OfflineErrorMessage
    }

    $packageProperties = [ordered]@{}
    foreach ($property in @($cachedPackage.PSObject.Properties)) {
        $packageProperties[$property.Name] = $property.Value
    }
    $packageProperties['Source'] = 'cache'
    $packageProperties['Action'] = 'SelectedCache'
    return [pscustomobject]$packageProperties
}

function Install-ManifestedArchiveRuntimeFromPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo,

        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome,

        [Parameter(Mandatory = $true)]
        [string]$StagePrefix,

        [Parameter(Mandatory = $true)]
        [scriptblock]$TestRuntime,

        [Parameter(Mandatory = $true)]
        [string]$DisplayName,

        [scriptblock]$PostInstall
    )

    $currentValidation = & $TestRuntime $RuntimeHome

    if ($currentValidation.Status -ne 'Ready') {
        New-ManifestedDirectory -Path (Split-Path -Parent $RuntimeHome) | Out-Null

        $stageInfo = $null
        try {
            $stageInfo = Expand-ManifestedArchiveToStage -PackagePath $PackageInfo.Path -Prefix $StagePrefix

            if (Test-Path -LiteralPath $RuntimeHome) {
                Remove-Item -LiteralPath $RuntimeHome -Recurse -Force
            }

            New-ManifestedDirectory -Path $RuntimeHome | Out-Null
            Get-ChildItem -LiteralPath $stageInfo.ExpandedRoot -Force | ForEach-Object {
                Move-Item -LiteralPath $_.FullName -Destination $RuntimeHome -Force
            }

            if ($PostInstall) {
                & $PostInstall $RuntimeHome
            }
        }
        finally {
            if ($stageInfo) {
                Remove-ManifestedPath -Path $stageInfo.StagePath | Out-Null
            }
        }
    }

    $validation = & $TestRuntime $RuntimeHome
    if ($validation.Status -ne 'Ready') {
        throw ("{0} runtime validation failed after install at {1}." -f $DisplayName, $RuntimeHome)
    }

    [pscustomobject]@{
        Action            = if ($currentValidation.Status -eq 'Ready') { 'Skipped' } else { 'Installed' }
        RuntimeHome       = $RuntimeHome
        CurrentValidation = $currentValidation
        Validation        = $validation
    }
}
