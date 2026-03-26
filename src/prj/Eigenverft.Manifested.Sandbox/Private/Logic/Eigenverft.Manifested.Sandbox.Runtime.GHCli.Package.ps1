<#
    Eigenverft.Manifested.Sandbox.Runtime.GHCli.Package
#>

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
    $persistedDetails = Get-GHCliPersistedPackageDetails -LocalRoot $layout.LocalRoot
    $pattern = '^gh_(\d+\.\d+\.\d+)_' + [regex]::Escape($Flavor) + '\.zip$'

    return @(Get-ManifestedArchiveCachedPackages -CacheRootPath $layout.GHCliCacheRoot -Pattern $pattern -BuildPackageInfo {
        param($item, $matchTable)

        $persistedAsset = Get-ManifestedArchivePersistedAssetDetails -PersistedDetails $persistedDetails -AssetName $item.Name
        [pscustomobject]@{
            TagName     = if ($persistedAsset) { $persistedAsset.TagName } else { $null }
            Version     = $matchTable[1]
            Flavor      = $Flavor
            FileName    = $item.Name
            Path        = $item.FullName
            Source      = 'cache'
            Action      = 'SelectedCache'
            DownloadUrl = if ($persistedAsset) { $persistedAsset.DownloadUrl } else { $null }
            Sha256      = if ($persistedAsset) { $persistedAsset.Sha256 } else { $null }
            ShaSource   = if ($persistedAsset) { $persistedAsset.ShaSource } else { $null }
            ReleaseUrl  = $null
        }
    } -SortVersion {
        param($package)
        ConvertTo-GHCliVersion -VersionText $package.Version
    })
}

function Get-LatestCachedGHCliRuntimePackage {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Get-LatestManifestedArchiveRuntimePackage -CachedPackages @(Get-CachedGHCliRuntimePackages -Flavor $Flavor -LocalRoot $LocalRoot))
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

    $release = $null
    try {
        $release = Get-GHCliRelease -Flavor $Flavor
    }
    catch {
        $release = $null
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    return (Save-ManifestedArchiveRuntimePackage -Release $release -Refresh:$RefreshGHCli -CacheRootPath $layout.GHCliCacheRoot -GetCachedPackage {
        Get-LatestCachedGHCliRuntimePackage -Flavor $Flavor -LocalRoot $LocalRoot
    } -DownloadLabel 'GitHub CLI' -RefreshWarningPrefix 'Could not refresh the GitHub CLI package. Using cached copy. ' -OfflineErrorMessage 'Could not reach GitHub and no cached GitHub CLI ZIP was found.')
}

