<#
    Eigenverft.Manifested.Sandbox.Cmd.GHCliRuntimeAndCache
#>

function ConvertTo-GHCliVersion {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    $match = [regex]::Match($VersionText, 'v?(\d+\.\d+\.\d+)')
    if (-not $match.Success) {
        return $null
    }

    return [version]$match.Groups[1].Value
}

function Get-GHCliReleaseVersion {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    $versionObject = ConvertTo-GHCliVersion -VersionText $VersionText
    if (-not $versionObject) {
        throw "Could not parse the GitHub CLI release version '$VersionText'."
    }

    return $versionObject.ToString()
}

function Get-GHCliFlavor {
    [CmdletBinding()]
    param()

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        throw 'Only Windows hosts are supported by this GitHub CLI runtime bootstrap.'
    }

    $archHints = @($env:PROCESSOR_ARCHITECTURE, $env:PROCESSOR_ARCHITEW6432) -join ';'
    if ($archHints -match 'ARM64') {
        return 'windows_arm64'
    }

    if ([Environment]::Is64BitOperatingSystem) {
        return 'windows_amd64'
    }

    throw 'Only 64-bit Windows targets are supported by this GitHub CLI runtime bootstrap.'
}

function Get-GHCliPersistedPackageDetails {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $commandState = Get-ManifestedCommandState -CommandName 'Initialize-GHCliRuntime' -LocalRoot $LocalRoot
    if ($commandState -and $commandState.PSObject.Properties['Details']) {
        return $commandState.Details
    }

    return $null
}

function Get-GHCliRelease {
    [CmdletBinding()]
    param(
        [string]$Flavor
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-GHCliFlavor
    }

    $owner = 'cli'
    $repository = 'cli'

    try {
        $release = Get-ManifestedGitHubLatestRelease -Owner $owner -Repository $repository
        if ($release.Draft -or $release.Prerelease) {
            throw 'The latest GitHub CLI release is not a stable release.'
        }

        $version = Get-GHCliReleaseVersion -VersionText $release.TagName
        $fileName = 'gh_{0}_{1}.zip' -f $version, $Flavor
        $asset = Get-ManifestedGitHubReleaseAsset -Release $release -AssetName $fileName
        if (-not $asset) {
            throw "Could not find the expected GitHub CLI asset '$fileName' in the latest release."
        }

        $checksumAssetName = 'gh_{0}_checksums.txt' -f $version
        $checksum = Get-ManifestedGitHubReleaseAssetChecksum -Release $release -Owner $owner -Repository $repository -TagName $release.TagName -AssetName $fileName -FallbackSource ChecksumAsset -ChecksumAssetName $checksumAssetName
        if (-not $checksum) {
            throw "Could not resolve a trusted checksum for '$fileName'."
        }

        return [pscustomobject]@{
            TagName     = $release.TagName
            Version     = $version
            Flavor      = $Flavor
            FileName    = $fileName
            Path        = $null
            Source      = 'online'
            Action      = 'SelectedOnline'
            DownloadUrl = $asset.BrowserDownloadUrl
            Sha256      = $checksum.Sha256
            ShaSource   = $checksum.Source
            ReleaseUrl  = $release.HtmlUrl
        }
    }
    catch {
        $tagInfo = Get-ManifestedGitHubLatestReleaseTag -Owner $owner -Repository $repository
        if (-not $tagInfo) {
            throw 'Unable to determine the latest stable GitHub CLI release.'
        }

        $version = Get-GHCliReleaseVersion -VersionText $tagInfo.TagName
        $fileName = 'gh_{0}_{1}.zip' -f $version, $Flavor
        $checksumAssetName = 'gh_{0}_checksums.txt' -f $version
        $checksum = Get-ManifestedGitHubReleaseAssetChecksum -Owner $owner -Repository $repository -TagName $tagInfo.TagName -AssetName $fileName -FallbackSource ChecksumAsset -ChecksumAssetName $checksumAssetName
        if (-not $checksum) {
            throw "Could not resolve a trusted checksum for '$fileName'."
        }

        return [pscustomobject]@{
            TagName     = $tagInfo.TagName
            Version     = $version
            Flavor      = $Flavor
            FileName    = $fileName
            Path        = $null
            Source      = 'online'
            Action      = 'SelectedOnline'
            DownloadUrl = New-ManifestedGitHubReleaseAssetUrl -Owner $owner -Repository $repository -TagName $tagInfo.TagName -AssetName $fileName
            Sha256      = $checksum.Sha256
            ShaSource   = $checksum.Source
            ReleaseUrl  = $tagInfo.HtmlUrl
        }
    }
}

function Get-CachedGHCliRuntimePackages {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-GHCliFlavor
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    if (-not (Test-Path -LiteralPath $layout.GHCliCacheRoot)) {
        return @()
    }

    $persistedDetails = Get-GHCliPersistedPackageDetails -LocalRoot $layout.LocalRoot
    $pattern = '^gh_(\d+\.\d+\.\d+)_' + [regex]::Escape($Flavor) + '\.zip$'

    $items = Get-ChildItem -LiteralPath $layout.GHCliCacheRoot -File -Filter '*.zip' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $pattern } |
        ForEach-Object {
            $sha256 = $null
            $tagName = $null
            $downloadUrl = $null
            $shaSource = $null

            if ($persistedDetails -and $persistedDetails.PSObject.Properties['AssetName'] -and $persistedDetails.AssetName -eq $_.Name) {
                $sha256 = if ($persistedDetails.PSObject.Properties['Sha256']) { $persistedDetails.Sha256 } else { $null }
                $tagName = if ($persistedDetails.PSObject.Properties['Tag']) { $persistedDetails.Tag } else { $null }
                $downloadUrl = if ($persistedDetails.PSObject.Properties['DownloadUrl']) { $persistedDetails.DownloadUrl } else { $null }
                $shaSource = if ($persistedDetails.PSObject.Properties['ShaSource']) { $persistedDetails.ShaSource } else { $null }
            }

            [pscustomobject]@{
                TagName     = $tagName
                Version     = $matches[1]
                Flavor      = $Flavor
                FileName    = $_.Name
                Path        = $_.FullName
                Source      = 'cache'
                Action      = 'SelectedCache'
                DownloadUrl = $downloadUrl
                Sha256      = $sha256
                ShaSource   = $shaSource
                ReleaseUrl  = $null
            }
        } |
        Sort-Object -Descending -Property @{ Expression = { ConvertTo-GHCliVersion -VersionText $_.Version } }

    return @($items)
}

function Get-LatestCachedGHCliRuntimePackage {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $cachedPackages = @(Get-CachedGHCliRuntimePackages -Flavor $Flavor -LocalRoot $LocalRoot)
    $trustedPackage = @($cachedPackages | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Sha256) } | Select-Object -First 1)
    if ($trustedPackage) {
        return $trustedPackage[0]
    }

    return ($cachedPackages | Select-Object -First 1)
}

function Get-ManagedGHCliRuntimeHome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$Flavor,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    return (Join-Path $layout.GHCliToolsRoot ($Version + '\' + $Flavor))
}

function Get-GHCliCommandPathFromRuntimeHome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    $candidatePaths = @(
        (Join-Path $RuntimeHome 'bin\gh.exe'),
        (Join-Path $RuntimeHome 'gh.exe')
    )

    foreach ($candidatePath in $candidatePaths) {
        if (Test-Path -LiteralPath $candidatePath) {
            return $candidatePath
        }
    }

    return (Join-Path $RuntimeHome 'bin\gh.exe')
}

function Test-GHCliRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    $ghCmd = Get-GHCliCommandPathFromRuntimeHome -RuntimeHome $RuntimeHome

    if (-not (Test-Path -LiteralPath $RuntimeHome)) {
        $status = 'Missing'
        $reportedVersion = $null
        $reportedBanner = $null
    }
    elseif (-not (Test-Path -LiteralPath $ghCmd)) {
        $status = 'NeedsRepair'
        $reportedVersion = $null
        $reportedBanner = $null
    }
    else {
        $reportedBanner = $null
        try {
            $reportedBanner = (& $ghCmd --version 2>$null | Select-Object -First 1)
            if ($reportedBanner) {
                $reportedBanner = $reportedBanner.ToString().Trim()
            }
        }
        catch {
            $reportedBanner = $null
        }

        $reportedVersionObject = ConvertTo-GHCliVersion -VersionText $reportedBanner
        $reportedVersion = if ($reportedVersionObject) { $reportedVersionObject.ToString() } else { $null }
        $status = if ($reportedVersion) { 'Ready' } else { 'NeedsRepair' }
    }

    [pscustomobject]@{
        Status          = $status
        IsReady         = ($status -eq 'Ready')
        RuntimeHome     = $RuntimeHome
        GhCmd           = $ghCmd
        ReportedVersion = $reportedVersion
        ReportedBanner  = $reportedBanner
    }
}

function Get-InstalledGHCliRuntime {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-GHCliFlavor
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $entries = @()

    if (Test-Path -LiteralPath $layout.GHCliToolsRoot) {
        $versionRoots = Get-ChildItem -LiteralPath $layout.GHCliToolsRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object -Descending -Property @{ Expression = { ConvertTo-GHCliVersion -VersionText $_.Name } }

        foreach ($versionRoot in $versionRoots) {
            $runtimeHome = Join-Path $versionRoot.FullName $Flavor
            if (-not (Test-Path -LiteralPath $runtimeHome)) {
                continue
            }

            $validation = Test-GHCliRuntime -RuntimeHome $runtimeHome
            $expectedVersion = ConvertTo-GHCliVersion -VersionText $versionRoot.Name
            $reportedVersion = ConvertTo-GHCliVersion -VersionText $validation.ReportedVersion
            $versionMatches = (-not $reportedVersion) -or (-not $expectedVersion) -or ($reportedVersion -eq $expectedVersion)

            $entries += [pscustomobject]@{
                Version        = $versionRoot.Name
                Flavor         = $Flavor
                RuntimeHome    = $runtimeHome
                GhCmd          = $validation.GhCmd
                Validation     = $validation
                VersionMatches = $versionMatches
                IsReady        = ($validation.IsReady -and $versionMatches)
            }
        }
    }

    [pscustomobject]@{
        Current = ($entries | Where-Object { $_.IsReady } | Select-Object -First 1)
        Valid   = @($entries | Where-Object { $_.IsReady })
        Invalid = @($entries | Where-Object { -not $_.IsReady })
    }
}

function Get-ManifestedGHCliRuntimeFromCandidatePath {
    [CmdletBinding()]
    param(
        [string]$CandidatePath
    )

    $resolvedCandidatePath = Get-ManifestedFullPath -Path $CandidatePath
    if ([string]::IsNullOrWhiteSpace($resolvedCandidatePath) -or -not (Test-Path -LiteralPath $resolvedCandidatePath)) {
        return $null
    }

    $leafName = Split-Path -Leaf $resolvedCandidatePath
    if ($leafName -ine 'gh.exe' -and $leafName -ine 'gh') {
        return $null
    }

    $runtimeHome = Split-Path -Parent $resolvedCandidatePath
    if ((Split-Path -Leaf $runtimeHome) -ieq 'bin') {
        $runtimeHome = Split-Path -Parent $runtimeHome
    }

    $validation = Test-GHCliRuntime -RuntimeHome $runtimeHome
    if (-not $validation.IsReady) {
        return $null
    }

    $versionObject = ConvertTo-GHCliVersion -VersionText $validation.ReportedVersion
    if (-not $versionObject) {
        return $null
    }

    [pscustomobject]@{
        Version     = $versionObject.ToString()
        Flavor      = $null
        RuntimeHome = $runtimeHome
        GhCmd       = $validation.GhCmd
        Validation  = $validation
        IsReady     = $true
        Source      = 'External'
        Discovery   = 'Path'
    }
}

function Get-SystemGHCliRuntime {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $candidatePaths = New-Object System.Collections.Generic.List[string]
    $additionalPaths = @()

    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $additionalPaths += (Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe')
        $additionalPaths += (Join-Path $env:ProgramFiles 'GitHub CLI\bin\gh.exe')
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $additionalPaths += (Join-Path $env:LOCALAPPDATA 'Programs\GitHub CLI\gh.exe')
        $additionalPaths += (Join-Path $env:LOCALAPPDATA 'Programs\GitHub CLI\bin\gh.exe')
    }

    $ghExePath = Get-ManifestedApplicationPath -CommandName 'gh.exe' -ExcludedRoots @($layout.GHCliToolsRoot) -AdditionalPaths $additionalPaths
    if (-not [string]::IsNullOrWhiteSpace($ghExePath)) {
        $candidatePaths.Add($ghExePath) | Out-Null
    }

    $ghPath = Get-ManifestedApplicationPath -CommandName 'gh' -ExcludedRoots @($layout.GHCliToolsRoot) -AdditionalPaths $additionalPaths
    if (-not [string]::IsNullOrWhiteSpace($ghPath)) {
        $candidatePaths.Add($ghPath) | Out-Null
    }

    foreach ($candidatePath in @($candidatePaths | Select-Object -Unique)) {
        $runtime = Get-ManifestedGHCliRuntimeFromCandidatePath -CandidatePath $candidatePath
        if ($runtime) {
            return $runtime
        }
    }

    return $null
}

function Test-GHCliRuntimePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo
    )

    if (-not (Test-Path -LiteralPath $PackageInfo.Path)) {
        return [pscustomobject]@{
            Status       = 'Missing'
            TagName      = $PackageInfo.TagName
            Version      = $PackageInfo.Version
            Flavor       = $PackageInfo.Flavor
            FileName     = $PackageInfo.FileName
            Path         = $PackageInfo.Path
            Source       = $PackageInfo.Source
            Verified     = $false
            Verification = 'Missing'
            ExpectedHash = $null
            ActualHash   = $null
        }
    }

    if ([string]::IsNullOrWhiteSpace($PackageInfo.Sha256)) {
        return [pscustomobject]@{
            Status       = 'UnverifiedCache'
            TagName      = $PackageInfo.TagName
            Version      = $PackageInfo.Version
            Flavor       = $PackageInfo.Flavor
            FileName     = $PackageInfo.FileName
            Path         = $PackageInfo.Path
            Source       = $PackageInfo.Source
            Verified     = $false
            Verification = 'MissingTrustedHash'
            ExpectedHash = $null
            ActualHash   = $null
        }
    }

    $actualHash = (Get-FileHash -LiteralPath $PackageInfo.Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = $PackageInfo.Sha256.ToLowerInvariant()

    [pscustomobject]@{
        Status       = if ($actualHash -eq $expectedHash) { 'Ready' } else { 'CorruptCache' }
        TagName      = $PackageInfo.TagName
        Version      = $PackageInfo.Version
        Flavor       = $PackageInfo.Flavor
        FileName     = $PackageInfo.FileName
        Path         = $PackageInfo.Path
        Source       = $PackageInfo.Source
        Verified     = $true
        Verification = if ($PackageInfo.ShaSource) { $PackageInfo.ShaSource } else { 'SHA256' }
        ExpectedHash = $expectedHash
        ActualHash   = $actualHash
    }
}

function Get-GHCliRuntimeState {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Flavor)) {
            $Flavor = Get-GHCliFlavor
        }

        $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    }
    catch {
        return [pscustomobject]@{
            Status              = 'Blocked'
            LocalRoot           = $LocalRoot
            Layout              = $null
            Flavor              = $Flavor
            CurrentVersion      = $null
            RuntimeHome         = $null
            RuntimeSource       = $null
            ExecutablePath      = $null
            Runtime             = $null
            InvalidRuntimeHomes = @()
            Package             = $null
            PackagePath         = $null
            PartialPaths        = @()
            BlockedReason       = $_.Exception.Message
        }
    }

    $partialPaths = @()
    if (Test-Path -LiteralPath $layout.GHCliCacheRoot) {
        $partialPaths += @(Get-ChildItem -LiteralPath $layout.GHCliCacheRoot -File -Filter '*.download' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    }
    $partialPaths += @(Get-ManifestedStageDirectories -Prefix 'ghcli' -Mode TemporaryShort -LegacyRootPaths @($layout.ToolsRoot) | Select-Object -ExpandProperty FullName)

    $installed = Get-InstalledGHCliRuntime -Flavor $Flavor -LocalRoot $layout.LocalRoot
    $managedRuntime = $installed.Current
    $externalRuntime = $null
    if (-not $managedRuntime) {
        $externalRuntime = Get-SystemGHCliRuntime -LocalRoot $layout.LocalRoot
    }

    $currentRuntime = if ($managedRuntime) { $managedRuntime } else { $externalRuntime }
    $runtimeSource = if ($managedRuntime) { 'Managed' } elseif ($externalRuntime) { 'External' } else { $null }
    $invalidRuntimeHomes = @($installed.Invalid | Select-Object -ExpandProperty RuntimeHome)
    $package = Get-LatestCachedGHCliRuntimePackage -Flavor $Flavor -LocalRoot $layout.LocalRoot

    if ($invalidRuntimeHomes.Count -gt 0) {
        $status = 'NeedsRepair'
    }
    elseif ($partialPaths.Count -gt 0) {
        $status = 'Partial'
    }
    elseif ($currentRuntime) {
        $status = 'Ready'
    }
    elseif ($package) {
        $status = 'NeedsInstall'
    }
    else {
        $status = 'Missing'
    }

    [pscustomobject]@{
        Status              = $status
        LocalRoot           = $layout.LocalRoot
        Layout              = $layout
        Flavor              = $Flavor
        CurrentVersion      = if ($currentRuntime) { $currentRuntime.Version } elseif ($package) { $package.Version } else { $null }
        RuntimeHome         = if ($currentRuntime) { $currentRuntime.RuntimeHome } else { $null }
        RuntimeSource       = $runtimeSource
        ExecutablePath      = if ($currentRuntime) { $currentRuntime.GhCmd } else { $null }
        Runtime             = if ($currentRuntime) { $currentRuntime.Validation } else { $null }
        InvalidRuntimeHomes = $invalidRuntimeHomes
        Package             = $package
        PackagePath         = if ($package) { $package.Path } else { $null }
        PartialPaths        = $partialPaths
        BlockedReason       = $null
    }
}

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
    foreach ($path in ($pathsToRemove | Select-Object -Unique)) {
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

function Save-GHCliRuntimePackage {
    [CmdletBinding()]
    param(
        [switch]$RefreshGHCli,
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-GHCliFlavor
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    New-ManifestedDirectory -Path $layout.GHCliCacheRoot | Out-Null

    $release = $null
    try {
        $release = Get-GHCliRelease -Flavor $Flavor
    }
    catch {
        $release = $null
    }

    if ($release) {
        $packagePath = Join-Path $layout.GHCliCacheRoot $release.FileName
        $downloadPath = Get-ManifestedDownloadPath -TargetPath $packagePath
        $action = 'ReusedCache'

        if ($RefreshGHCli -or -not (Test-Path -LiteralPath $packagePath)) {
            Remove-ManifestedPath -Path $downloadPath | Out-Null

            try {
                Write-Host "Downloading GitHub CLI $($release.Version) ($Flavor)..."
                Enable-ManifestedTls12Support
                Invoke-WebRequestEx -Uri $release.DownloadUrl -Headers @{ 'User-Agent' = 'Eigenverft.Manifested.Sandbox' } -OutFile $downloadPath -UseBasicParsing
                Move-Item -LiteralPath $downloadPath -Destination $packagePath -Force
                $action = 'Downloaded'
            }
            catch {
                Remove-ManifestedPath -Path $downloadPath | Out-Null
                if (-not (Test-Path -LiteralPath $packagePath)) {
                    throw
                }

                Write-Warning ('Could not refresh the GitHub CLI package. Using cached copy. ' + $_.Exception.Message)
                $action = 'ReusedCache'
            }
        }

        return [pscustomobject]@{
            TagName     = $release.TagName
            Version     = $release.Version
            Flavor      = $release.Flavor
            FileName    = $release.FileName
            Path        = $packagePath
            Source      = if ($action -eq 'Downloaded') { 'online' } else { 'cache' }
            Action      = $action
            DownloadUrl = $release.DownloadUrl
            Sha256      = $release.Sha256
            ShaSource   = $release.ShaSource
            ReleaseUrl  = $release.ReleaseUrl
        }
    }

    $cachedPackage = Get-LatestCachedGHCliRuntimePackage -Flavor $Flavor -LocalRoot $LocalRoot
    if (-not $cachedPackage) {
        throw 'Could not reach GitHub and no cached GitHub CLI ZIP was found.'
    }

    return [pscustomobject]@{
        TagName     = $cachedPackage.TagName
        Version     = $cachedPackage.Version
        Flavor      = $cachedPackage.Flavor
        FileName    = $cachedPackage.FileName
        Path        = $cachedPackage.Path
        Source      = 'cache'
        Action      = 'SelectedCache'
        DownloadUrl = $cachedPackage.DownloadUrl
        Sha256      = $cachedPackage.Sha256
        ShaSource   = $cachedPackage.ShaSource
        ReleaseUrl  = $cachedPackage.ReleaseUrl
    }
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
    $currentValidation = Test-GHCliRuntime -RuntimeHome $runtimeHome

    if ($currentValidation.Status -ne 'Ready') {
        New-ManifestedDirectory -Path (Split-Path -Parent $runtimeHome) | Out-Null

        $stageInfo = $null
        try {
            $stageInfo = Expand-ManifestedArchiveToStage -PackagePath $PackageInfo.Path -Prefix 'ghcli'

            if (Test-Path -LiteralPath $runtimeHome) {
                Remove-Item -LiteralPath $runtimeHome -Recurse -Force
            }

            New-ManifestedDirectory -Path $runtimeHome | Out-Null
            Get-ChildItem -LiteralPath $stageInfo.ExpandedRoot -Force | ForEach-Object {
                Move-Item -LiteralPath $_.FullName -Destination $runtimeHome -Force
            }
        }
        finally {
            if ($stageInfo) {
                Remove-ManifestedPath -Path $stageInfo.StagePath | Out-Null
            }
        }
    }

    $validation = Test-GHCliRuntime -RuntimeHome $runtimeHome
    if ($validation.Status -ne 'Ready') {
        throw "GitHub CLI runtime validation failed after install at $runtimeHome."
    }

    [pscustomobject]@{
        Action      = if ($currentValidation.Status -eq 'Ready') { 'Skipped' } else { 'Installed' }
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

