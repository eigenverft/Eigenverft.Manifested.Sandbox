<#
    Eigenverft.Manifested.Sandbox.Runtime.Python.Package
#>

function Get-PythonReleaseDescriptionForFlavor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Flavor
    )

    switch ($Flavor) {
        'amd64' { return 'Windows embeddable package (64-bit)' }
        'arm64' { return 'Windows embeddable package (ARM64)' }
        default { throw "Unsupported Python flavor '$Flavor'." }
    }
}

function Get-PythonPersistedPackageDetails {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $commandState = Get-ManifestedCommandState -CommandName 'Initialize-PythonRuntime' -LocalRoot $LocalRoot
    if ($commandState -and $commandState.PSObject.Properties['Details']) {
        return $commandState.Details
    }

    return $null
}

function Get-PythonReleaseCandidates {
    [CmdletBinding()]
    param()

    $response = Invoke-WebRequestEx -Uri 'https://www.python.org/downloads/windows/' -Headers @{ 'User-Agent' = 'Eigenverft.Manifested.Sandbox' } -UseBasicParsing
    $releaseMatches = [regex]::Matches($response.Content, '(?is)<a href="/downloads/release/python-(?<slug>313\d+)/">Python (?<version>3\.13\.\d+) - (?<releaseDate>[^<]+)</a>')
    $items = New-Object System.Collections.Generic.List[object]
    $seenVersions = @{}

    foreach ($match in $releaseMatches) {
        $versionText = $match.Groups['version'].Value.Trim()
        if ([string]::IsNullOrWhiteSpace($versionText) -or $seenVersions.ContainsKey($versionText)) {
            continue
        }

        $versionObject = ConvertTo-PythonVersion -VersionText $versionText
        if (-not $versionObject -or -not (Test-PythonManagedReleaseVersion -Version $versionObject)) {
            continue
        }

        $seenVersions[$versionText] = $true
        $items.Add([pscustomobject]@{
            ReleaseId   = $match.Groups['slug'].Value.Trim()
            Version     = $versionText
            ReleaseDate = $match.Groups['releaseDate'].Value.Trim()
            ReleaseUrl  = ('https://www.python.org/downloads/release/python-{0}/' -f $match.Groups['slug'].Value.Trim())
        }) | Out-Null
    }

    return @($items | Sort-Object -Descending -Property @{ Expression = { ConvertTo-PythonVersion -VersionText $_.Version } })
}

function Get-PythonReleaseAssetDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReleaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$Flavor
    )

    $descriptionPattern = switch ($Flavor) {
        'amd64' { 'Windows\s+embeddable\s+package\s+\(64-bit\)' }
        'arm64' { 'Windows\s+embeddable\s+package\s+\(ARM64\)' }
        default { throw "Unsupported Python flavor '$Flavor'." }
    }

    $response = Invoke-WebRequestEx -Uri $ReleaseUrl -Headers @{ 'User-Agent' = 'Eigenverft.Manifested.Sandbox' } -UseBasicParsing
    $pattern = '(?is)<tr>\s*<td><a href="(?<url>[^"]+)">' + $descriptionPattern + '</a>.*?<td><code class="checksum">(?<checksumHtml>.*?)</code></td>\s*</tr>'
    $match = [regex]::Match($response.Content, $pattern)
    if (-not $match.Success) {
        throw "Could not find the Python embeddable package row for flavor '$Flavor' in $ReleaseUrl."
    }

    $downloadUrl = $match.Groups['url'].Value.Trim()
    $checksumText = ($match.Groups['checksumHtml'].Value -replace '<[^>]+>', '')
    $checksum = ($checksumText -replace '[^0-9a-fA-F]', '').ToLowerInvariant()
    if ($checksum.Length -ne 64) {
        throw "Could not resolve a trusted SHA256 checksum for '$downloadUrl'."
    }

    [pscustomobject]@{
        DownloadUrl = $downloadUrl
        FileName    = [System.IO.Path]::GetFileName(([uri]$downloadUrl).AbsolutePath)
        Sha256      = $checksum
        ShaSource   = 'ReleaseHtml'
    }
}

function Get-PythonRelease {
    [CmdletBinding()]
    param(
        [string]$Flavor
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-PythonFlavor
    }

    foreach ($candidate in @(Get-PythonReleaseCandidates)) {
        try {
            $assetDetails = Get-PythonReleaseAssetDetails -ReleaseUrl $candidate.ReleaseUrl -Flavor $Flavor
            return [pscustomobject]@{
                ReleaseId   = $candidate.ReleaseId
                Version     = $candidate.Version
                Flavor      = $Flavor
                FileName    = $assetDetails.FileName
                Path        = $null
                Source      = 'online'
                Action      = 'SelectedOnline'
                DownloadUrl = $assetDetails.DownloadUrl
                Sha256      = $assetDetails.Sha256
                ShaSource   = $assetDetails.ShaSource
                ReleaseUrl  = $candidate.ReleaseUrl
                ReleaseDate = $candidate.ReleaseDate
            }
        }
        catch {
            continue
        }
    }

    throw 'Unable to determine the latest stable Python 3.13 embeddable release.'
}

function Get-CachedPythonRuntimePackages {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-PythonFlavor
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    if (-not (Test-Path -LiteralPath $layout.PythonCacheRoot)) {
        return @()
    }

    $persistedDetails = Get-PythonPersistedPackageDetails -LocalRoot $layout.LocalRoot
    $pattern = '^python-(\d+\.\d+\.\d+)-embed-' + [regex]::Escape($Flavor) + '\.zip$'

    $items = Get-ChildItem -LiteralPath $layout.PythonCacheRoot -File -Filter '*.zip' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $pattern } |
        ForEach-Object {
            $sha256 = $null
            $downloadUrl = $null
            $shaSource = $null
            $releaseUrl = $null
            $releaseId = $null

            if ($persistedDetails -and $persistedDetails.PSObject.Properties['AssetName'] -and $persistedDetails.AssetName -eq $_.Name) {
                $sha256 = if ($persistedDetails.PSObject.Properties['Sha256']) { $persistedDetails.Sha256 } else { $null }
                $downloadUrl = if ($persistedDetails.PSObject.Properties['DownloadUrl']) { $persistedDetails.DownloadUrl } else { $null }
                $shaSource = if ($persistedDetails.PSObject.Properties['ShaSource']) { $persistedDetails.ShaSource } else { $null }
                $releaseUrl = if ($persistedDetails.PSObject.Properties['ReleaseUrl']) { $persistedDetails.ReleaseUrl } else { $null }
                $releaseId = if ($persistedDetails.PSObject.Properties['ReleaseId']) { $persistedDetails.ReleaseId } else { $null }
            }

            [pscustomobject]@{
                ReleaseId   = $releaseId
                Version     = $matches[1]
                Flavor      = $Flavor
                FileName    = $_.Name
                Path        = $_.FullName
                Source      = 'cache'
                Action      = 'SelectedCache'
                DownloadUrl = $downloadUrl
                Sha256      = $sha256
                ShaSource   = $shaSource
                ReleaseUrl  = $releaseUrl
                ReleaseDate = $null
            }
        } |
        Sort-Object -Descending -Property @{ Expression = { ConvertTo-PythonVersion -VersionText $_.Version } }

    return @($items)
}

function Get-LatestCachedPythonRuntimePackage {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $cachedPackages = @(Get-CachedPythonRuntimePackages -Flavor $Flavor -LocalRoot $LocalRoot)
    $trustedPackage = @($cachedPackages | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Sha256) } | Select-Object -First 1)
    if ($trustedPackage) {
        return $trustedPackage[0]
    }

    return ($cachedPackages | Select-Object -First 1)
}

function Test-PythonRuntimePackageHasTrustedHash {
    [CmdletBinding()]
    param(
        [pscustomobject]$PackageInfo
    )

    return ($PackageInfo -and -not [string]::IsNullOrWhiteSpace($PackageInfo.Sha256))
}

function Test-PythonRuntimePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo
    )

    if (-not (Test-Path -LiteralPath $PackageInfo.Path)) {
        return [pscustomobject]@{
            Status       = 'Missing'
            ReleaseId    = if ($PackageInfo.PSObject.Properties['ReleaseId']) { $PackageInfo.ReleaseId } else { $null }
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
            ReleaseId    = if ($PackageInfo.PSObject.Properties['ReleaseId']) { $PackageInfo.ReleaseId } else { $null }
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
        ReleaseId    = if ($PackageInfo.PSObject.Properties['ReleaseId']) { $PackageInfo.ReleaseId } else { $null }
        Version      = $PackageInfo.Version
        Flavor       = $PackageInfo.Flavor
        FileName     = $PackageInfo.FileName
        Path         = $PackageInfo.Path
        Source       = $PackageInfo.Source
        Verified     = $true
        Verification = if ($PackageInfo.PSObject.Properties['ShaSource'] -and $PackageInfo.ShaSource) { $PackageInfo.ShaSource } else { 'SHA256' }
        ExpectedHash = $expectedHash
        ActualHash   = $actualHash
    }
}

function Save-PythonRuntimePackage {
    [CmdletBinding()]
    param(
        [switch]$RefreshPython,
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-PythonFlavor
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    New-ManifestedDirectory -Path $layout.PythonCacheRoot | Out-Null

    $release = $null
    try {
        $release = Get-PythonRelease -Flavor $Flavor
    }
    catch {
        $release = $null
    }

    if ($release) {
        $packagePath = Join-Path $layout.PythonCacheRoot $release.FileName
        $downloadPath = Get-ManifestedDownloadPath -TargetPath $packagePath
        $action = 'ReusedCache'

        if ($RefreshPython -or -not (Test-Path -LiteralPath $packagePath)) {
            Remove-ManifestedPath -Path $downloadPath | Out-Null

            try {
                Write-Host "Downloading Python $($release.Version) embeddable runtime ($Flavor)..."
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

                Write-Warning ('Could not refresh the Python runtime package. Using cached copy. ' + $_.Exception.Message)
                $action = 'ReusedCache'
            }
        }

        return [pscustomobject]@{
            ReleaseId   = $release.ReleaseId
            Version     = $release.Version
            Flavor      = $Flavor
            FileName    = $release.FileName
            Path        = $packagePath
            Source      = if ($action -eq 'Downloaded') { 'online' } else { 'cache' }
            Action      = $action
            DownloadUrl = $release.DownloadUrl
            Sha256      = $release.Sha256
            ShaSource   = $release.ShaSource
            ReleaseUrl  = $release.ReleaseUrl
            ReleaseDate = $release.ReleaseDate
        }
    }

    $cachedPackage = Get-LatestCachedPythonRuntimePackage -Flavor $Flavor -LocalRoot $LocalRoot
    if (-not $cachedPackage) {
        throw 'Could not reach python.org and no cached Python embeddable ZIP was found.'
    }

    return [pscustomobject]@{
        ReleaseId   = $cachedPackage.ReleaseId
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
        ReleaseDate = $cachedPackage.ReleaseDate
    }
}

function Resolve-PythonRuntimeTrustedPackageInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo,

        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (Test-PythonRuntimePackageHasTrustedHash -PackageInfo $PackageInfo) {
        return [pscustomobject]@{
            PackageInfo           = $PackageInfo
            MetadataRefreshError  = $null
            MetadataRefreshTried  = $false
            UsedTrustedPackage    = $true
        }
    }

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = if ($PackageInfo.PSObject.Properties['Flavor'] -and $PackageInfo.Flavor) { $PackageInfo.Flavor } else { Get-PythonFlavor }
    }

    $refreshedPackage = $null
    $metadataRefreshError = $null
    try {
        $refreshedPackage = Save-PythonRuntimePackage -RefreshPython:$false -Flavor $Flavor -LocalRoot $LocalRoot
    }
    catch {
        $metadataRefreshError = $_.Exception.Message
    }

    if ($refreshedPackage -and (Test-Path -LiteralPath $PackageInfo.Path) -and (Test-PythonRuntimePackageHasTrustedHash -PackageInfo $refreshedPackage)) {
        $samePackagePath = ((Get-ManifestedFullPath -Path $refreshedPackage.Path) -eq (Get-ManifestedFullPath -Path $PackageInfo.Path))
        $samePackageName = ($refreshedPackage.FileName -eq $PackageInfo.FileName)

        if ($samePackagePath -or $samePackageName) {
            return [pscustomobject]@{
                PackageInfo           = $refreshedPackage
                MetadataRefreshError  = $metadataRefreshError
                MetadataRefreshTried  = $true
                UsedTrustedPackage    = $true
            }
        }
    }

    return [pscustomobject]@{
        PackageInfo           = $PackageInfo
        MetadataRefreshError  = $metadataRefreshError
        MetadataRefreshTried  = $true
        UsedTrustedPackage    = (Test-PythonRuntimePackageHasTrustedHash -PackageInfo $PackageInfo)
    }
}

function New-PythonRuntimePackageTrustFailureMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo,

        [string]$MetadataRefreshError
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(("Python runtime package verification could not establish a trusted SHA256 for cached package '{0}'." -f $PackageInfo.FileName)) | Out-Null
    $lines.Add(("Cached path: {0}" -f $PackageInfo.Path)) | Out-Null

    if ($PackageInfo.PSObject.Properties['Version'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.Version)) {
        $lines.Add(("Cached version: {0}" -f $PackageInfo.Version)) | Out-Null
    }
    if ($PackageInfo.PSObject.Properties['Flavor'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.Flavor)) {
        $lines.Add(("Cached flavor: {0}" -f $PackageInfo.Flavor)) | Out-Null
    }
    if ($PackageInfo.PSObject.Properties['Source'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.Source)) {
        $lines.Add(("Package source: {0}" -f $PackageInfo.Source)) | Out-Null
    }

    $lines.Add('The cached ZIP is present, but this run does not have trusted release metadata attached to verify it.') | Out-Null
    $lines.Add('This usually happens when an earlier Python bootstrap downloaded the ZIP but failed before package metadata was persisted.') | Out-Null

    if (-not [string]::IsNullOrWhiteSpace($MetadataRefreshError)) {
        $lines.Add(("Metadata refresh attempt failed: {0}" -f $MetadataRefreshError)) | Out-Null
    }
    else {
        $lines.Add('A metadata refresh attempt did not produce a trusted checksum for the cached ZIP.') | Out-Null
    }

    $lines.Add('Retry with normal network access so python.org release metadata can be resolved, or use Initialize-PythonRuntime -RefreshPython to reacquire the package.') | Out-Null
    return (@($lines) -join [Environment]::NewLine)
}

