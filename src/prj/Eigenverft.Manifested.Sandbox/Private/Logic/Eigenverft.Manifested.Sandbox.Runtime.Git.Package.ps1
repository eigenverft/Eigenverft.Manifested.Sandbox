<#
    Eigenverft.Manifested.Sandbox.Runtime.Git.Package
#>

function Get-GitRelease {
    [CmdletBinding()]
    param(
        [string]$Flavor
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-GitFlavor
    }

    $owner = 'git-for-windows'
    $repository = 'git'

    try {
        $release = Get-ManifestedGitHubLatestRelease -Owner $owner -Repository $repository
        if ($release.Draft -or $release.Prerelease) {
            throw 'The latest Git for Windows release is not a stable release.'
        }

        $version = ConvertTo-GitReleaseVersion -TagName $release.TagName
        $fileName = 'MinGit-{0}-{1}.zip' -f $version, $Flavor
        $asset = Get-ManifestedGitHubReleaseAsset -Release $release -AssetName $fileName
        if (-not $asset) {
            throw "Could not find the expected MinGit asset '$fileName' in the latest release."
        }

        $checksum = Get-ManifestedGitHubReleaseAssetChecksum -Release $release -Owner $owner -Repository $repository -TagName $release.TagName -AssetName $fileName -FallbackSource ReleaseHtml
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
            throw 'Unable to determine the latest stable Git for Windows release.'
        }

        $version = ConvertTo-GitReleaseVersion -TagName $tagInfo.TagName
        $fileName = 'MinGit-{0}-{1}.zip' -f $version, $Flavor
        $checksum = Get-ManifestedGitHubReleaseAssetChecksum -Owner $owner -Repository $repository -TagName $tagInfo.TagName -AssetName $fileName -FallbackSource ReleaseHtml
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

function Get-CachedGitRuntimePackages {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-GitFlavor
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $persistedDetails = Get-GitPersistedPackageDetails -LocalRoot $layout.LocalRoot
    $pattern = '^MinGit-(\d+\.\d+\.\d+\.\d+)-' + [regex]::Escape($Flavor) + '\.zip$'

    return @(Get-ManifestedArchiveCachedPackages -CacheRootPath $layout.GitCacheRoot -Pattern $pattern -BuildPackageInfo {
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
        ConvertTo-GitVersion -VersionText $package.Version
    })
}

function Get-LatestCachedGitRuntimePackage {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Get-LatestManifestedArchiveRuntimePackage -CachedPackages @(Get-CachedGitRuntimePackages -Flavor $Flavor -LocalRoot $LocalRoot))
}

function Save-GitRuntimePackage {
    [CmdletBinding()]
    param(
        [switch]$RefreshGit,
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-GitFlavor
    }

    $release = $null
    try {
        $release = Get-GitRelease -Flavor $Flavor
    }
    catch {
        $release = $null
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    return (Save-ManifestedArchiveRuntimePackage -Release $release -Refresh:$RefreshGit -CacheRootPath $layout.GitCacheRoot -GetCachedPackage {
        Get-LatestCachedGitRuntimePackage -Flavor $Flavor -LocalRoot $LocalRoot
    } -DownloadLabel 'MinGit' -RefreshWarningPrefix 'Could not refresh the MinGit package. Using cached copy. ' -OfflineErrorMessage 'Could not reach GitHub and no cached MinGit ZIP was found.')
}

