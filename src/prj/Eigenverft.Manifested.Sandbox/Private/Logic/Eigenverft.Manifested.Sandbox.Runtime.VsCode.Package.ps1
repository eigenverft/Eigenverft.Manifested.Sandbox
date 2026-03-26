<#
    Eigenverft.Manifested.Sandbox.Runtime.VsCode.Package
#>

function ConvertTo-VSCodeSha256 {
    [CmdletBinding()]
    param(
        [string]$Sha256
    )

    if ([string]::IsNullOrWhiteSpace($Sha256)) {
        return $null
    }

    $normalized = $Sha256.Trim().ToLowerInvariant()
    if ($normalized -notmatch '^[a-f0-9]{64}$') {
        return $null
    }

    return $normalized
}

function Invoke-ManifestedVSCodeHeadRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    Enable-ManifestedTls12Support

    $request = [System.Net.HttpWebRequest]::Create($Uri)
    $request.Method = 'HEAD'
    $request.AllowAutoRedirect = $false
    $request.UserAgent = 'Eigenverft.Manifested.Sandbox'

    $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    if ($proxy) {
        $proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        $request.Proxy = $proxy
    }

    $response = $null
    try {
        try {
            $response = [System.Net.HttpWebResponse]$request.GetResponse()
        }
        catch [System.Net.WebException] {
            if ($_.Exception.Response) {
                $response = [System.Net.HttpWebResponse]$_.Exception.Response
            }
            else {
                throw
            }
        }

        [pscustomobject]@{
            StatusCode = [int]$response.StatusCode
            Location   = $response.Headers['Location']
            Sha256     = ConvertTo-VSCodeSha256 -Sha256 $response.Headers['X-SHA256']
            Headers    = $response.Headers
        }
    }
    finally {
        if ($response) {
            $response.Close()
        }
    }
}

function Get-VSCodeRelease {
    [CmdletBinding()]
    param(
        [string]$Flavor
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-VSCodeFlavor
    }

    $channel = 'stable'
    $latestUri = 'https://update.code.visualstudio.com/latest/{0}/{1}' -f (Get-VSCodeUpdateTarget -Flavor $Flavor), $channel
    $headResult = Invoke-ManifestedVSCodeHeadRequest -Uri $latestUri

    if ($headResult.StatusCode -notin @(301, 302, 303, 307, 308)) {
        throw "Unexpected VS Code update response status code $($headResult.StatusCode)."
    }
    if ([string]::IsNullOrWhiteSpace($headResult.Location)) {
        throw 'The VS Code update service did not return a redirect location.'
    }
    if ([string]::IsNullOrWhiteSpace($headResult.Sha256)) {
        throw 'The VS Code update service did not return an X-SHA256 header.'
    }

    $resolvedUri = [uri]$headResult.Location
    $fileName = Split-Path -Leaf $resolvedUri.AbsolutePath
    $match = [regex]::Match($fileName, '^(VSCode-(win32-(?:x64|arm64))-(\d+\.\d+\.\d+)\.zip)$')
    if (-not $match.Success) {
        throw "Could not parse the VS Code archive name '$fileName'."
    }
    if ($match.Groups[2].Value -ne $Flavor) {
        throw "The VS Code update service resolved flavor '$($match.Groups[2].Value)' instead of '$Flavor'."
    }

    [pscustomobject]@{
        TagName     = $channel
        Version     = $match.Groups[3].Value
        Flavor      = $Flavor
        Channel     = $channel
        FileName    = $match.Groups[1].Value
        Path        = $null
        Source      = 'online'
        Action      = 'SelectedOnline'
        DownloadUrl = $resolvedUri.AbsoluteUri
        Sha256      = $headResult.Sha256
        ShaSource   = 'X-SHA256'
        ReleaseUrl  = $latestUri
    }
}

function Get-CachedVSCodeRuntimePackages {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-VSCodeFlavor
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $persistedDetails = Get-VSCodePersistedPackageDetails -LocalRoot $layout.LocalRoot
    $pattern = '^VSCode-(' + [regex]::Escape($Flavor) + ')-(\d+\.\d+\.\d+)\.zip$'

    return @(Get-ManifestedArchiveCachedPackages -CacheRootPath $layout.VsCodeCacheRoot -Pattern $pattern -BuildPackageInfo {
        param($item, $matchTable)

        $persistedAsset = Get-ManifestedArchivePersistedAssetDetails -PersistedDetails $persistedDetails -AssetName $item.Name
        $channel = if ($persistedAsset -and $persistedAsset.Channel) { $persistedAsset.Channel } else { 'stable' }
        [pscustomobject]@{
            TagName     = $channel
            Version     = $matchTable[2]
            Flavor      = $matchTable[1]
            Channel     = $channel
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
        ConvertTo-VSCodeVersion -VersionText $package.Version
    })
}

function Get-LatestCachedVSCodeRuntimePackage {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return (Get-LatestManifestedArchiveRuntimePackage -CachedPackages @(Get-CachedVSCodeRuntimePackages -Flavor $Flavor -LocalRoot $LocalRoot))
}

function Save-VSCodeRuntimePackage {
    [CmdletBinding()]
    param(
        [switch]$RefreshVSCode,
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-VSCodeFlavor
    }

    $release = $null
    try {
        $release = Get-VSCodeRelease -Flavor $Flavor
    }
    catch {
        $release = $null
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    return (Save-ManifestedArchiveRuntimePackage -Release $release -Refresh:$RefreshVSCode -CacheRootPath $layout.VsCodeCacheRoot -GetCachedPackage {
        Get-LatestCachedVSCodeRuntimePackage -Flavor $Flavor -LocalRoot $LocalRoot
    } -DownloadLabel 'VS Code' -RefreshWarningPrefix 'Could not refresh the VS Code package. Using cached copy. ' -OfflineErrorMessage 'Could not reach the VS Code update service and no cached VS Code ZIP was found.')
}

