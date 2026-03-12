<#
    Eigenverft.Manifested.Sandbox.Shared.GitHubReleases
#>

function Enable-ManifestedTls12Support {
    [CmdletBinding()]
    param()

    try {
        $tls12 = [System.Net.SecurityProtocolType]::Tls12
        if (([System.Net.ServicePointManager]::SecurityProtocol -band $tls12) -ne $tls12) {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor $tls12
        }
    }
    catch {
    }
}

function Get-ManifestedGitHubRequestHeaders {
    [CmdletBinding()]
    param()

    return @{
        'User-Agent' = 'Eigenverft.Manifested.Sandbox'
        'Accept' = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
}

function Invoke-ManifestedGitHubJsonRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    Enable-ManifestedTls12Support
    return (Invoke-RestMethod -Uri $Uri -Headers (Get-ManifestedGitHubRequestHeaders) -ErrorAction Stop)
}

function Invoke-ManifestedGitHubWebRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    Enable-ManifestedTls12Support
    return (Invoke-WebRequest -Uri $Uri -Headers @{ 'User-Agent' = 'Eigenverft.Manifested.Sandbox' } -UseBasicParsing -ErrorAction Stop)
}

function ConvertTo-ManifestedSha256Digest {
    [CmdletBinding()]
    param(
        [string]$Digest
    )

    if ([string]::IsNullOrWhiteSpace($Digest)) {
        return $null
    }

    $match = [regex]::Match($Digest, 'sha256:([0-9a-fA-F]{64})')
    if ($match.Success) {
        return $match.Groups[1].Value.ToLowerInvariant()
    }

    if ($Digest -match '^[0-9a-fA-F]{64}$') {
        return $Digest.ToLowerInvariant()
    }

    return $null
}

function Get-ManifestedGitHubLatestRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,

        [Parameter(Mandatory = $true)]
        [string]$Repository
    )

    $release = Invoke-ManifestedGitHubJsonRequest -Uri ("https://api.github.com/repos/{0}/{1}/releases/latest" -f $Owner, $Repository)
    $assets = @(
        foreach ($asset in @($release.assets)) {
            [pscustomobject]@{
                Name               = $asset.name
                BrowserDownloadUrl = $asset.browser_download_url
                Digest             = ConvertTo-ManifestedSha256Digest -Digest $asset.digest
                ContentType        = $asset.content_type
                Size               = $asset.size
            }
        }
    )

    return [pscustomobject]@{
        Owner      = $Owner
        Repository = $Repository
        TagName    = [string]$release.tag_name
        Name       = [string]$release.name
        HtmlUrl    = [string]$release.html_url
        Body       = [string]$release.body
        Draft      = [bool]$release.draft
        Prerelease = [bool]$release.prerelease
        Assets     = @($assets)
        Source     = 'GitHubApi'
    }
}

function Get-ManifestedGitHubLatestReleaseTag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,

        [Parameter(Mandatory = $true)]
        [string]$Repository
    )

    $response = Invoke-ManifestedGitHubWebRequest -Uri ("https://github.com/{0}/{1}/releases/latest" -f $Owner, $Repository)
    $resolvedUri = $null
    if ($response.BaseResponse -and $response.BaseResponse.ResponseUri) {
        $resolvedUri = $response.BaseResponse.ResponseUri.AbsoluteUri
    }

    if ([string]::IsNullOrWhiteSpace($resolvedUri)) {
        return $null
    }

    $match = [regex]::Match($resolvedUri, '/releases/tag/([^/?#]+)')
    if (-not $match.Success) {
        return $null
    }

    return [pscustomobject]@{
        Owner      = $Owner
        Repository = $Repository
        TagName    = [uri]::UnescapeDataString($match.Groups[1].Value)
        HtmlUrl    = $resolvedUri
        Source     = 'GitHubLatestRedirect'
    }
}

function Get-ManifestedGitHubReleaseAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Release,

        [Parameter(Mandatory = $true)]
        [string]$AssetName
    )

    return (@($Release.Assets | Where-Object { $_.Name -eq $AssetName }) | Select-Object -First 1)
}

function New-ManifestedGitHubReleaseAssetUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$TagName,

        [Parameter(Mandatory = $true)]
        [string]$AssetName
    )

    return ('https://github.com/{0}/{1}/releases/download/{2}/{3}' -f $Owner, $Repository, $TagName, $AssetName)
}

function Get-ManifestedSha256FromText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$FileName
    )

    $escapedFileName = [regex]::Escape($FileName)
    $patterns = @(
        '(?im)^\s*([0-9a-f]{64})\s+[\*\s]?' + $escapedFileName + '\s*$',
        '(?im)^\s*' + $escapedFileName + '\s*\|\s*([0-9a-f]{64})\s*$'
    )

    foreach ($pattern in $patterns) {
        $match = [regex]::Match($Content, $pattern)
        if ($match.Success) {
            return $match.Groups[1].Value.ToLowerInvariant()
        }
    }

    return $null
}

function Get-ManifestedSha256FromHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Html,

        [Parameter(Mandatory = $true)]
        [string]$AssetName
    )

    $pattern = [regex]::Escape($AssetName) + '.{0,1000}?([0-9a-fA-F]{64})'
    $match = [regex]::Match(
        $Html,
        $pattern,
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    if ($match.Success) {
        return $match.Groups[1].Value.ToLowerInvariant()
    }

    return $null
}

function Get-ManifestedGitHubReleaseAssetChecksum {
    [CmdletBinding()]
    param(
        [pscustomobject]$Release,

        [Parameter(Mandatory = $true)]
        [string]$Owner,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$TagName,

        [Parameter(Mandatory = $true)]
        [string]$AssetName,

        [ValidateSet('None', 'ReleaseHtml', 'ChecksumAsset')]
        [string]$FallbackSource = 'None',

        [string]$ChecksumAssetName
    )

    if ($Release) {
        $asset = Get-ManifestedGitHubReleaseAsset -Release $Release -AssetName $AssetName
        if ($asset -and $asset.Digest) {
            return [pscustomobject]@{
                Sha256 = $asset.Digest
                Source = 'GitHubAssetDigest'
            }
        }
    }

    switch ($FallbackSource) {
        'ChecksumAsset' {
            if ([string]::IsNullOrWhiteSpace($ChecksumAssetName)) {
                throw 'ChecksumAssetName is required when FallbackSource is ChecksumAsset.'
            }

            $checksumAsset = $null
            if ($Release) {
                $checksumAsset = Get-ManifestedGitHubReleaseAsset -Release $Release -AssetName $ChecksumAssetName
            }

            $checksumUrl = if ($checksumAsset) {
                $checksumAsset.BrowserDownloadUrl
            }
            else {
                New-ManifestedGitHubReleaseAssetUrl -Owner $Owner -Repository $Repository -TagName $TagName -AssetName $ChecksumAssetName
            }

            $response = Invoke-ManifestedGitHubWebRequest -Uri $checksumUrl
            $sha256 = Get-ManifestedSha256FromText -Content $response.Content -FileName $AssetName
            if ($sha256) {
                return [pscustomobject]@{
                    Sha256 = $sha256
                    Source = 'GitHubChecksumAsset'
                }
            }
        }
        'ReleaseHtml' {
            $response = Invoke-ManifestedGitHubWebRequest -Uri ("https://github.com/{0}/{1}/releases/tag/{2}" -f $Owner, $Repository, $TagName)
            $sha256 = Get-ManifestedSha256FromHtml -Html $response.Content -AssetName $AssetName
            if ($sha256) {
                return [pscustomobject]@{
                    Sha256 = $sha256
                    Source = 'GitHubReleaseHtml'
                }
            }
        }
    }

    return $null
}
