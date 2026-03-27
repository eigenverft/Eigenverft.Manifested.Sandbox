function Get-ManifestedArtifactCacheRootFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Layout
    )

    $artifactBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'artifact' -BlockName 'zipPackage'
    if (-not $artifactBlock) {
        $artifactBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'artifact' -BlockName 'executableInstaller'
    }
    if (-not $artifactBlock) {
        return $null
    }

    $layoutPropertyName = if ($artifactBlock.PSObject.Properties.Match('cacheRootLayoutProperty').Count -gt 0) { $artifactBlock.cacheRootLayoutProperty } else { $null }
    if ([string]::IsNullOrWhiteSpace($layoutPropertyName)) {
        return $null
    }

    if (-not $Layout.PSObject.Properties.Match($layoutPropertyName).Count) {
        throw "Definition '$($Definition.commandName)' references unknown layout property '$layoutPropertyName'."
    }

    return $Layout.$layoutPropertyName
}

function Get-ManifestedArtifactFileRegexFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [string]$Flavor
    )

    $artifactBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'artifact' -BlockName 'zipPackage'
    if (-not $artifactBlock) {
        $artifactBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'artifact' -BlockName 'executableInstaller'
    }
    if (-not $artifactBlock -or -not $artifactBlock.PSObject.Properties.Match('fileNamePattern').Count) {
        return $null
    }

    return (Expand-ManifestedDefinitionTemplate -Template $artifactBlock.fileNamePattern -Flavor ([regex]::Escape($Flavor)))
}

function Save-ManifestedArtifactMetadataFromPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo
    )

    if (-not $PackageInfo -or [string]::IsNullOrWhiteSpace($PackageInfo.Path)) {
        return
    }

    $metadata = [ordered]@{}
    if ($PackageInfo.PSObject.Properties['TagName'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.TagName)) { $metadata['Tag'] = $PackageInfo.TagName }
    if ($PackageInfo.PSObject.Properties['Version'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.Version)) { $metadata['Version'] = $PackageInfo.Version }
    if ($PackageInfo.PSObject.Properties['Flavor'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.Flavor)) { $metadata['Flavor'] = $PackageInfo.Flavor }
    if ($PackageInfo.PSObject.Properties['FileName'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.FileName)) { $metadata['AssetName'] = $PackageInfo.FileName }
    if ($PackageInfo.PSObject.Properties['DownloadUrl'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.DownloadUrl)) { $metadata['DownloadUrl'] = $PackageInfo.DownloadUrl }
    if ($PackageInfo.PSObject.Properties['Sha256'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.Sha256)) { $metadata['Sha256'] = $PackageInfo.Sha256 }
    if ($PackageInfo.PSObject.Properties['ShaSource'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.ShaSource)) { $metadata['ShaSource'] = $PackageInfo.ShaSource }
    if ($PackageInfo.PSObject.Properties['ReleaseUrl'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.ReleaseUrl)) { $metadata['ReleaseUrl'] = $PackageInfo.ReleaseUrl }
    if ($PackageInfo.PSObject.Properties['ReleaseId'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.ReleaseId)) { $metadata['ReleaseId'] = $PackageInfo.ReleaseId }
    if ($PackageInfo.PSObject.Properties['ReleaseDate'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.ReleaseDate)) { $metadata['ReleaseDate'] = $PackageInfo.ReleaseDate }
    if ($PackageInfo.PSObject.Properties['Channel'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.Channel)) { $metadata['Channel'] = $PackageInfo.Channel }
    if ($PackageInfo.PSObject.Properties['ShasumsUrl'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.ShasumsUrl)) { $metadata['ShasumsUrl'] = $PackageInfo.ShasumsUrl }
    if ($PackageInfo.PSObject.Properties['NpmVersion'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.NpmVersion)) { $metadata['NpmVersion'] = $PackageInfo.NpmVersion }
    if ($PackageInfo.PSObject.Properties['SignatureStatus'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.SignatureStatus)) { $metadata['SignatureStatus'] = $PackageInfo.SignatureStatus }
    if ($PackageInfo.PSObject.Properties['SignerSubject'] -and -not [string]::IsNullOrWhiteSpace($PackageInfo.SignerSubject)) { $metadata['SignerSubject'] = $PackageInfo.SignerSubject }
    $metadata['AcquiredAtUtc'] = (Get-Date).ToUniversalTime().ToString('o')

    Save-ManifestedArtifactMetadata -ArtifactPath $PackageInfo.Path -Metadata $metadata | Out-Null
}

function Get-ManifestedCachedZipArtifactsFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [string]$Flavor,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-ManifestedDefinitionFlavor -Definition $Definition
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $cacheRoot = Get-ManifestedArtifactCacheRootFromDefinition -Definition $Definition -Layout $layout
    if ([string]::IsNullOrWhiteSpace($cacheRoot) -or -not (Test-Path -LiteralPath $cacheRoot)) {
        return @()
    }

    $pattern = Get-ManifestedArtifactFileRegexFromDefinition -Definition $Definition -Flavor $Flavor
    if ([string]::IsNullOrWhiteSpace($pattern)) {
        return @()
    }

    $items = Get-ChildItem -LiteralPath $cacheRoot -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $pattern } |
        ForEach-Object {
            $metadata = Get-ManifestedArtifactMetadata -ArtifactPath $_.FullName
            [pscustomobject]@{
                TagName     = if ($metadata -and $metadata.PSObject.Properties['Tag']) { $metadata.Tag } else { $null }
                ReleaseId   = if ($metadata -and $metadata.PSObject.Properties['ReleaseId']) { $metadata.ReleaseId } else { $null }
                Version     = if ($metadata -and $metadata.PSObject.Properties['Version']) { $metadata.Version } elseif ($matches.Count -gt 1) { $matches[1] } else { $null }
                Flavor      = $Flavor
                Channel     = if ($metadata -and $metadata.PSObject.Properties['Channel']) { $metadata.Channel } else { $null }
                FileName    = $_.Name
                Path        = $_.FullName
                Source      = 'cache'
                Action      = 'SelectedCache'
                DownloadUrl = if ($metadata -and $metadata.PSObject.Properties['DownloadUrl']) { $metadata.DownloadUrl } else { $null }
                Sha256      = if ($metadata -and $metadata.PSObject.Properties['Sha256']) { $metadata.Sha256 } else { $null }
                ShaSource   = if ($metadata -and $metadata.PSObject.Properties['ShaSource']) { $metadata.ShaSource } else { $null }
                ReleaseUrl  = if ($metadata -and $metadata.PSObject.Properties['ReleaseUrl']) { $metadata.ReleaseUrl } else { $null }
                ReleaseDate = if ($metadata -and $metadata.PSObject.Properties['ReleaseDate']) { $metadata.ReleaseDate } else { $null }
                ShasumsUrl  = if ($metadata -and $metadata.PSObject.Properties['ShasumsUrl']) { $metadata.ShasumsUrl } else { $null }
                NpmVersion  = if ($metadata -and $metadata.PSObject.Properties['NpmVersion']) { $metadata.NpmVersion } else { $null }
                SignatureStatus = if ($metadata -and $metadata.PSObject.Properties['SignatureStatus']) { $metadata.SignatureStatus } else { $null }
                SignerSubject = if ($metadata -and $metadata.PSObject.Properties['SignerSubject']) { $metadata.SignerSubject } else { $null }
            }
        } |
        Sort-Object -Descending -Property @{ Expression = { ConvertTo-ManifestedComparableVersion -VersionText $_.Version } }

    return @($items)
}

function Get-LatestCachedZipArtifactFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [string]$Flavor,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $cachedArtifacts = @(Get-ManifestedCachedZipArtifactsFromDefinition -Definition $Definition -Flavor $Flavor -LocalRoot $LocalRoot)
    if ([bool]$Definition.policies.requireTrustedArtifact) {
        $trustedArtifact = @($cachedArtifacts | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Sha256) } | Select-Object -First 1)
        if ($trustedArtifact) {
            return $trustedArtifact[0]
        }
    }

    return ($cachedArtifacts | Select-Object -First 1)
}

function Get-ManifestedCachedInstallerArtifactFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [string]$Flavor,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $artifacts = @(Get-ManifestedCachedZipArtifactsFromDefinition -Definition $Definition -Flavor $Flavor -LocalRoot $LocalRoot)
    if ($artifacts.Count -gt 0) {
        return $artifacts[0]
    }

    return $null
}

function Get-ManifestedOnlineGitHubReleaseArtifactFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [string]$Flavor
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-ManifestedDefinitionFlavor -Definition $Definition
    }

    $versionSpec = Get-ManifestedVersionSpec -Definition $Definition
    $supplyBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'supply' -BlockName 'githubRelease'
    if (-not $supplyBlock) {
        return $null
    }

    $repositoryParts = @($supplyBlock.repository -split '/', 2)
    if ($repositoryParts.Count -ne 2) {
        throw "Command definition '$($Definition.commandName)' has invalid githubRelease.repository value '$($supplyBlock.repository)'."
    }

    $owner = $repositoryParts[0]
    $repository = $repositoryParts[1]

    try {
        $release = Get-ManifestedGitHubLatestRelease -Owner $owner -Repository $repository
        if ($release.Draft -or $release.Prerelease) {
            throw "The latest release for '$($supplyBlock.repository)' is not stable."
        }

        $tagName = $release.TagName
        $version = ConvertTo-ManifestedVersionTextFromRule -VersionText $tagName -Rule $versionSpec.ReleaseVersionRule
        if ([string]::IsNullOrWhiteSpace($version)) {
            $version = (ConvertTo-ManifestedComparableVersion -VersionText $tagName).ToString()
        }
        $fileName = Expand-ManifestedDefinitionTemplate -Template $supplyBlock.assetNamePattern -Version $version -TagName $tagName -Flavor $Flavor
        $asset = Get-ManifestedGitHubReleaseAsset -Release $release -AssetName $fileName
        if (-not $asset) {
            throw "Could not find the expected GitHub release asset '$fileName'."
        }

        $checksumAssetName = $null
        if ($supplyBlock.PSObject.Properties.Match('checksum').Count -gt 0 -and $supplyBlock.checksum) {
            if ($supplyBlock.checksum.PSObject.Properties.Match('assetNamePattern').Count -gt 0) {
                $checksumAssetName = Expand-ManifestedDefinitionTemplate -Template $supplyBlock.checksum.assetNamePattern -Version $version -TagName $tagName -Flavor $Flavor
            }
            elseif ($supplyBlock.checksum.PSObject.Properties.Match('assetName').Count -gt 0) {
                $checksumAssetName = $supplyBlock.checksum.assetName
            }
        }

        $checksum = if ($checksumAssetName) {
            Get-ManifestedGitHubReleaseAssetChecksum -Release $release -Owner $owner -Repository $repository -TagName $tagName -AssetName $fileName -FallbackSource $(if ($supplyBlock.checksum.PSObject.Properties.Match('fallbackSource').Count -gt 0) { $supplyBlock.checksum.fallbackSource } else { 'ChecksumAsset' }) -ChecksumAssetName $checksumAssetName
        }
        else {
            $null
        }

        return [pscustomobject]@{
            TagName     = $tagName
            Version     = $version
            Flavor      = $Flavor
            FileName    = $fileName
            Path        = $null
            Source      = 'online'
            Action      = 'SelectedOnline'
            DownloadUrl = $asset.BrowserDownloadUrl
            Sha256      = if ($checksum) { $checksum.Sha256 } else { $null }
            ShaSource   = if ($checksum) { $checksum.Source } else { $null }
            ReleaseUrl  = $release.HtmlUrl
        }
    }
    catch {
        $tagInfo = Get-ManifestedGitHubLatestReleaseTag -Owner $owner -Repository $repository
        if (-not $tagInfo) {
            throw
        }

        $tagName = $tagInfo.TagName
        $version = ConvertTo-ManifestedVersionTextFromRule -VersionText $tagName -Rule $versionSpec.ReleaseVersionRule
        if ([string]::IsNullOrWhiteSpace($version)) {
            $version = (ConvertTo-ManifestedComparableVersion -VersionText $tagName).ToString()
        }
        $fileName = Expand-ManifestedDefinitionTemplate -Template $supplyBlock.assetNamePattern -Version $version -TagName $tagName -Flavor $Flavor

        $checksumAssetName = $null
        if ($supplyBlock.PSObject.Properties.Match('checksum').Count -gt 0 -and $supplyBlock.checksum) {
            if ($supplyBlock.checksum.PSObject.Properties.Match('assetNamePattern').Count -gt 0) {
                $checksumAssetName = Expand-ManifestedDefinitionTemplate -Template $supplyBlock.checksum.assetNamePattern -Version $version -TagName $tagName -Flavor $Flavor
            }
            elseif ($supplyBlock.checksum.PSObject.Properties.Match('assetName').Count -gt 0) {
                $checksumAssetName = $supplyBlock.checksum.assetName
            }
        }

        $checksum = if ($checksumAssetName) {
            Get-ManifestedGitHubReleaseAssetChecksum -Owner $owner -Repository $repository -TagName $tagName -AssetName $fileName -FallbackSource $(if ($supplyBlock.checksum.PSObject.Properties.Match('fallbackSource').Count -gt 0) { $supplyBlock.checksum.fallbackSource } else { 'ChecksumAsset' }) -ChecksumAssetName $checksumAssetName
        }
        else {
            $null
        }

        return [pscustomobject]@{
            TagName     = $tagName
            Version     = $version
            Flavor      = $Flavor
            FileName    = $fileName
            Path        = $null
            Source      = 'online'
            Action      = 'SelectedOnline'
            DownloadUrl = New-ManifestedGitHubReleaseAssetUrl -Owner $owner -Repository $repository -TagName $tagName -AssetName $fileName
            Sha256      = if ($checksum) { $checksum.Sha256 } else { $null }
            ShaSource   = if ($checksum) { $checksum.Source } else { $null }
            ReleaseUrl  = $tagInfo.HtmlUrl
        }
    }
}

function Get-ManifestedOnlineNodeDistArtifactFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [string]$Flavor
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-ManifestedDefinitionFlavor -Definition $Definition
    }

    $versionSpec = Get-ManifestedVersionSpec -Definition $Definition
    $supplyBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'supply' -BlockName 'nodeDist'
    if (-not $supplyBlock) {
        return $null
    }

    $response = Invoke-WebRequestEx -Uri $supplyBlock.indexUrl -UseBasicParsing
    $items = $response.Content | ConvertFrom-Json
    $release = $items |
        Where-Object {
            if ($supplyBlock.PSObject.Properties.Match('releaseChannel').Count -gt 0 -and $supplyBlock.releaseChannel -eq 'lts') {
                return ($_.lts -and $_.lts -ne $false)
            }

            return $true
        } |
        Sort-Object -Descending -Property @{ Expression = { ConvertTo-ManifestedComparableVersion -VersionText $_.version } } |
        Select-Object -First 1

    if (-not $release) {
        throw "Unable to determine the requested Node.js release for '$($Definition.commandName)'."
    }

    $tagName = $release.version
    $fileName = Expand-ManifestedDefinitionTemplate -Template $supplyBlock.assetNamePattern -Version $tagName -TagName $tagName -Flavor $Flavor
    $baseUrl = Expand-ManifestedDefinitionTemplate -Template $supplyBlock.baseUrlPattern -Version $tagName -TagName $tagName -Flavor $Flavor

    return [pscustomobject]@{
        TagName     = $tagName
        Version     = $(if ($tagName) { ConvertTo-ManifestedVersionTextFromRule -VersionText $tagName -Rule $versionSpec.ReleaseVersionRule } else { $null })
        Flavor      = $Flavor
        FileName    = $fileName
        Path        = $null
        Source      = 'online'
        Action      = 'SelectedOnline'
        NpmVersion  = $release.npm
        DownloadUrl = ($baseUrl.TrimEnd('/') + '/' + $fileName)
        ShasumsUrl  = ($baseUrl.TrimEnd('/') + '/' + $supplyBlock.shasumsAssetName)
    }
}

function Get-ManifestedOnlineVSCodeArtifactFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [string]$Flavor
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-ManifestedDefinitionFlavor -Definition $Definition
    }

    $versionSpec = Get-ManifestedVersionSpec -Definition $Definition
    $supplyBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'supply' -BlockName 'vsCodeUpdate'
    if (-not $supplyBlock) {
        return $null
    }

    $channel = if ($supplyBlock.PSObject.Properties.Match('channel').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($supplyBlock.channel)) { $supplyBlock.channel } else { 'stable' }
    $updateTarget = Expand-ManifestedDefinitionTemplate -Template $supplyBlock.updateTargetPattern -Flavor $Flavor
    $latestUri = Expand-ManifestedDefinitionTemplate -Template $supplyBlock.latestUrlPattern -Flavor $Flavor -Version $channel -TagName $channel
    $latestUri = $latestUri.Replace('{updateTarget}', $updateTarget).Replace('{channel}', $channel)
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
    $match = [regex]::Match($fileName, (Expand-ManifestedDefinitionTemplate -Template $supplyBlock.fileNamePattern -Flavor ([regex]::Escape($Flavor))))
    if (-not $match.Success) {
        throw "Could not parse the VS Code archive name '$fileName'."
    }

    return [pscustomobject]@{
        TagName     = $channel
        Version     = $(ConvertTo-ManifestedVersionTextFromRule -VersionText $match.Groups[1].Value -Rule $versionSpec.ReleaseVersionRule)
        Flavor      = $Flavor
        Channel     = $channel
        FileName    = $fileName
        Path        = $null
        Source      = 'online'
        Action      = 'SelectedOnline'
        DownloadUrl = $resolvedUri.AbsoluteUri
        Sha256      = $headResult.Sha256
        ShaSource   = 'X-SHA256'
        ReleaseUrl  = $latestUri
    }
}

function Get-ManifestedOnlinePythonEmbedArtifactFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [string]$Flavor
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-ManifestedDefinitionFlavor -Definition $Definition
    }

    $versionSpec = Get-ManifestedVersionSpec -Definition $Definition
    $supplyBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'supply' -BlockName 'pythonEmbed'
    if (-not $supplyBlock) {
        return $null
    }

    foreach ($candidate in @(Get-ManifestedPythonReleaseCandidates -Definition $Definition -VersionSpec $versionSpec)) {
        try {
            $assetDetails = Get-ManifestedPythonReleaseAssetDetails -ReleaseUrl $candidate.ReleaseUrl -Flavor $Flavor -Definition $Definition
            return [pscustomobject]@{
                ReleaseId   = $candidate.ReleaseId
                Version     = $(ConvertTo-ManifestedVersionTextFromRule -VersionText $candidate.Version -Rule $versionSpec.ReleaseVersionRule)
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

    throw "Unable to determine the requested Python embeddable release for '$($Definition.commandName)'."
}

function Get-ManifestedDirectDownloadArtifactFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition
    )

    $supplyBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'supply' -BlockName 'directDownload'
    if (-not $supplyBlock) {
        return $null
    }

    return [pscustomobject]@{
        Version     = if ($supplyBlock.PSObject.Properties.Match('version').Count -gt 0) { $supplyBlock.version } else { $null }
        FileName    = $supplyBlock.fileName
        Path        = $null
        Source      = 'online'
        Action      = 'SelectedOnline'
        DownloadUrl = $supplyBlock.downloadUrl
    }
}


