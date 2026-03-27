<#
    Eigenverft.Manifested.Sandbox.Cmd.Ps7RuntimeAndCache
#>

$script:ManifestedPs7RuntimeVersionSpec = Get-ManifestedVersionSpec -Definition (Get-ManifestedCommandDefinition -CommandName 'Initialize-Ps7Runtime')

function Get-Ps7PersistedPackageDetails {
    [CmdletBinding()]
    param(
        [string]$ArtifactPath,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not [string]::IsNullOrWhiteSpace($ArtifactPath)) {
        return (Get-ManifestedArtifactMetadata -ArtifactPath $ArtifactPath)
    }

    return $null
}

function Get-Ps7Release {
<#
.SYNOPSIS
Resolves the latest stable PowerShell 7 package for the current Windows flavor.

.DESCRIPTION
Queries the PowerShell GitHub releases feed, skips draft and prerelease entries,
and returns the expected ZIP asset together with a trusted SHA256 checksum. If
the full release payload cannot be resolved, it falls back to tag-only metadata
and reconstructs the asset URL.

.PARAMETER Flavor
Runtime package flavor such as `win-x64` or `win-arm64`. When omitted, the
current host flavor is detected automatically.

.EXAMPLE
Get-Ps7Release

.EXAMPLE
Get-Ps7Release -Flavor 'win-x64'

.NOTES
This helper is used by the managed PowerShell runtime bootstrap flow.
#>
    [CmdletBinding()]
    param(
        [string]$Flavor
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-ManifestedCommandFlavor -CommandName 'Initialize-Ps7Runtime'
    }

    $owner = 'PowerShell'
    $repository = 'PowerShell'

    try {
        $release = Get-ManifestedGitHubLatestRelease -Owner $owner -Repository $repository
        if ($release.Draft -or $release.Prerelease) {
            throw 'The latest GitHub release is not a stable PowerShell release.'
        }

        $version = ConvertTo-ManifestedVersionTextFromRule -VersionText $release.TagName -Rule $script:ManifestedPs7RuntimeVersionSpec.ReleaseVersionRule
        $fileName = 'PowerShell-{0}-{1}.zip' -f $version, $Flavor
        $asset = Get-ManifestedGitHubReleaseAsset -Release $release -AssetName $fileName
        if (-not $asset) {
            throw "Could not find the expected PowerShell asset '$fileName' in the latest release."
        }

        $checksum = Get-ManifestedGitHubReleaseAssetChecksum -Release $release -Owner $owner -Repository $repository -TagName $release.TagName -AssetName $fileName -FallbackSource ChecksumAsset -ChecksumAssetName 'hashes.sha256'
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
            throw 'Unable to determine the latest stable PowerShell 7 release.'
        }

        $version = ConvertTo-ManifestedVersionTextFromRule -VersionText $tagInfo.TagName -Rule $script:ManifestedPs7RuntimeVersionSpec.ReleaseVersionRule
        $fileName = 'PowerShell-{0}-{1}.zip' -f $version, $Flavor
        $checksum = Get-ManifestedGitHubReleaseAssetChecksum -Owner $owner -Repository $repository -TagName $tagInfo.TagName -AssetName $fileName -FallbackSource ChecksumAsset -ChecksumAssetName 'hashes.sha256'
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

function Get-CachedPs7RuntimePackages {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-ManifestedCommandFlavor -CommandName 'Initialize-Ps7Runtime'
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    if (-not (Test-Path -LiteralPath $layout.Ps7CacheRoot)) {
        return @()
    }

    $pattern = '^PowerShell-(\d+\.\d+\.\d+)-' + [regex]::Escape($Flavor) + '\.zip$'

    $items = Get-ChildItem -LiteralPath $layout.Ps7CacheRoot -File -Filter '*.zip' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $pattern } |
        ForEach-Object {
            $persistedDetails = Get-Ps7PersistedPackageDetails -ArtifactPath $_.FullName -LocalRoot $layout.LocalRoot
            $sha256 = $null
            $tagName = $null
            $downloadUrl = $null
            $shaSource = $null

            if ($persistedDetails) {
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
        Sort-Object -Descending -Property @{ Expression = { ConvertTo-ManifestedVersionObjectFromRule -VersionText $_.Version -Rule $script:ManifestedPs7RuntimeVersionSpec.RuntimeVersionRule } }

    return @($items)
}

function Get-LatestCachedPs7RuntimePackage {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $cachedPackages = @(Get-CachedPs7RuntimePackages -Flavor $Flavor -LocalRoot $LocalRoot)
    $trustedPackage = @($cachedPackages | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Sha256) } | Select-Object -First 1)
    if ($trustedPackage) {
        return $trustedPackage[0]
    }

    return ($cachedPackages | Select-Object -First 1)
}

function Get-ManagedPs7RuntimeHome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$Flavor,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    return (Join-Path $layout.Ps7ToolsRoot ($Version + '\' + $Flavor))
}

function Test-Ps7Runtime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    $pwshPath = Join-Path $RuntimeHome 'pwsh.exe'

    if (-not (Test-Path -LiteralPath $RuntimeHome)) {
        $status = 'Missing'
        $reportedVersion = $null
    }
    elseif (-not (Test-Path -LiteralPath $pwshPath)) {
        $status = 'NeedsRepair'
        $reportedVersion = $null
    }
    else {
        $reportedVersion = $null
        try {
            $reportedVersion = (& $pwshPath -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null | Select-Object -First 1)
            if ($reportedVersion) {
                $reportedVersion = $reportedVersion.ToString().Trim()
            }
        }
        catch {
            $reportedVersion = $null
        }

        $status = if ([string]::IsNullOrWhiteSpace($reportedVersion)) { 'NeedsRepair' } else { 'Ready' }
    }

    [pscustomobject]@{
        Status          = $status
        IsReady         = ($status -eq 'Ready')
        RuntimeHome     = $RuntimeHome
        PwshPath        = $pwshPath
        ReportedVersion = $reportedVersion
    }
}

function Get-InstalledPs7Runtime {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-ManifestedCommandFlavor -CommandName 'Initialize-Ps7Runtime'
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $entries = @()

    if (Test-Path -LiteralPath $layout.Ps7ToolsRoot) {
        $versionRoots = Get-ChildItem -LiteralPath $layout.Ps7ToolsRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object -Descending -Property @{ Expression = { ConvertTo-ManifestedVersionObjectFromRule -VersionText $_.Name -Rule $script:ManifestedPs7RuntimeVersionSpec.RuntimeVersionRule } }

        foreach ($versionRoot in $versionRoots) {
            $runtimeHome = Join-Path $versionRoot.FullName $Flavor
            if (-not (Test-Path -LiteralPath $runtimeHome)) {
                continue
            }

            $validation = Test-Ps7Runtime -RuntimeHome $runtimeHome
            $expectedVersion = ConvertTo-ManifestedVersionObjectFromRule -VersionText $versionRoot.Name -Rule $script:ManifestedPs7RuntimeVersionSpec.RuntimeVersionRule
            $reportedVersion = ConvertTo-ManifestedVersionObjectFromRule -VersionText $validation.ReportedVersion -Rule $script:ManifestedPs7RuntimeVersionSpec.RuntimeVersionRule
            $versionMatches = (-not $reportedVersion) -or (-not $expectedVersion) -or ($reportedVersion -eq $expectedVersion)

            $entries += [pscustomobject]@{
                Version        = $versionRoot.Name
                Flavor         = $Flavor
                RuntimeHome    = $runtimeHome
                PwshPath       = $validation.PwshPath
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

function Get-SystemPs7Runtime {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $additionalPaths = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $programFilesPowerShellRoot = Join-Path $env:ProgramFiles 'PowerShell'
        if (Test-Path -LiteralPath $programFilesPowerShellRoot) {
            foreach ($directory in @(Get-ChildItem -LiteralPath $programFilesPowerShellRoot -Directory -ErrorAction SilentlyContinue |
                Sort-Object -Descending -Property @{ Expression = { ConvertTo-ManifestedVersionObjectFromRule -VersionText $_.Name -Rule $script:ManifestedPs7RuntimeVersionSpec.RuntimeVersionRule } })) {
                $additionalPaths.Add((Join-Path $directory.FullName 'pwsh.exe')) | Out-Null
            }
        }
    }

    $pwshPath = Get-ManifestedApplicationPath -CommandName 'pwsh.exe' -ExcludedRoots @($layout.Ps7ToolsRoot) -AdditionalPaths @($additionalPaths)
    if ([string]::IsNullOrWhiteSpace($pwshPath)) {
        return $null
    }

    $runtimeHome = Split-Path -Parent $pwshPath
    $validation = Test-Ps7Runtime -RuntimeHome $runtimeHome
    if (-not $validation.IsReady) {
        return $null
    }

    $versionObject = ConvertTo-ManifestedVersionObjectFromRule -VersionText $validation.ReportedVersion -Rule $script:ManifestedPs7RuntimeVersionSpec.RuntimeVersionRule
    if (-not $versionObject) {
        return $null
    }

    [pscustomobject]@{
        Version     = $versionObject.ToString()
        Flavor      = $null
        RuntimeHome = $runtimeHome
        PwshPath    = $validation.PwshPath
        Validation  = $validation
        IsReady     = $true
        Source      = 'External'
        Discovery   = 'Path'
    }
}

function Test-Ps7RuntimePackage {
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

function Get-Ps7RuntimeState {
<#
.SYNOPSIS
Builds the current managed PowerShell 7 runtime state snapshot.

.DESCRIPTION
Collects the effective runtime flavor, cache state, installed managed runtimes,
external runtime fallback, and any partial or invalid paths that may require
repair before `Initialize-Ps7Runtime` can complete successfully.

.PARAMETER Flavor
Runtime package flavor such as `win-x64` or `win-arm64`. When omitted, the
current host flavor is detected automatically.

.PARAMETER LocalRoot
Local sandbox state root used for cache, tool, and persisted command metadata.

.EXAMPLE
Get-Ps7RuntimeState

.EXAMPLE
Get-Ps7RuntimeState -Flavor 'win-x64' -LocalRoot 'C:\SandboxState'

.NOTES
Returns a custom object that downstream install and repair helpers consume.
#>
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Flavor)) {
            $Flavor = Get-ManifestedCommandFlavor -CommandName 'Initialize-Ps7Runtime'
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
    if (Test-Path -LiteralPath $layout.Ps7CacheRoot) {
        $partialPaths += @(Get-ChildItem -LiteralPath $layout.Ps7CacheRoot -File -Filter '*.download' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    }
    $partialPaths += @(Get-ManifestedStageDirectories -Prefix 'ps7' -Mode TemporaryShort -LegacyRootPaths @($layout.ToolsRoot) | Select-Object -ExpandProperty FullName)

    $installed = Get-InstalledPs7Runtime -Flavor $Flavor -LocalRoot $layout.LocalRoot
    $managedRuntime = $installed.Current
    $externalRuntime = $null
    if (-not $managedRuntime) {
        $externalRuntime = Get-SystemPs7Runtime -LocalRoot $layout.LocalRoot
    }

    $currentRuntime = if ($managedRuntime) { $managedRuntime } else { $externalRuntime }
    $runtimeSource = if ($managedRuntime) { 'Managed' } elseif ($externalRuntime) { 'External' } else { $null }
    $invalidRuntimeHomes = @($installed.Invalid | Select-Object -ExpandProperty RuntimeHome)
    $package = Get-LatestCachedPs7RuntimePackage -Flavor $Flavor -LocalRoot $layout.LocalRoot

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
        ExecutablePath      = if ($currentRuntime) { $currentRuntime.PwshPath } else { $null }
        Runtime             = if ($currentRuntime) { $currentRuntime.Validation } else { $null }
        InvalidRuntimeHomes = $invalidRuntimeHomes
        Package             = $package
        PackagePath         = if ($package) { $package.Path } else { $null }
        PartialPaths        = $partialPaths
        BlockedReason       = $null
    }
}

function Repair-Ps7Runtime {
    [CmdletBinding()]
    param(
        [pscustomobject]$State,
        [string[]]$CorruptPackagePaths = @(),
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $State) {
        $State = Get-Ps7RuntimeState -Flavor $Flavor -LocalRoot $LocalRoot
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

function Save-Ps7RuntimePackage {
    [CmdletBinding()]
    param(
        [switch]$RefreshPs7,
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-ManifestedCommandFlavor -CommandName 'Initialize-Ps7Runtime'
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    New-ManifestedDirectory -Path $layout.Ps7CacheRoot | Out-Null

    $release = $null
    try {
        $release = Get-Ps7Release -Flavor $Flavor
    }
    catch {
        $release = $null
    }

    if ($release) {
        $packagePath = Join-Path $layout.Ps7CacheRoot $release.FileName
        $downloadPath = Get-ManifestedDownloadPath -TargetPath $packagePath
        $action = 'ReusedCache'

        if ($RefreshPs7 -or -not (Test-Path -LiteralPath $packagePath)) {
            Remove-ManifestedPath -Path $downloadPath | Out-Null

            try {
                Write-Host "Downloading PowerShell $($release.Version) ($Flavor)..."
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

                Write-Warning ('Could not refresh the PowerShell package. Using cached copy. ' + $_.Exception.Message)
                $action = 'ReusedCache'
            }
        }

        $packageInfo = [pscustomobject]@{
            TagName     = $release.TagName
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
        }

        Save-ManifestedArtifactMetadata -ArtifactPath $packagePath -Metadata ([ordered]@{
            Tag         = $packageInfo.TagName
            Version     = $packageInfo.Version
            Flavor      = $packageInfo.Flavor
            AssetName   = $packageInfo.FileName
            DownloadUrl = $packageInfo.DownloadUrl
            Sha256      = $packageInfo.Sha256
            ShaSource   = $packageInfo.ShaSource
            ReleaseUrl  = $packageInfo.ReleaseUrl
        }) | Out-Null

        return $packageInfo
    }

    $cachedPackage = Get-LatestCachedPs7RuntimePackage -Flavor $Flavor -LocalRoot $LocalRoot
    if (-not $cachedPackage) {
        throw 'Could not reach GitHub and no cached PowerShell ZIP was found.'
    }

    $packageInfo = [pscustomobject]@{
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

    if (-not [string]::IsNullOrWhiteSpace($packageInfo.Path) -and -not [string]::IsNullOrWhiteSpace($packageInfo.Sha256)) {
        Save-ManifestedArtifactMetadata -ArtifactPath $packageInfo.Path -Metadata ([ordered]@{
            Tag         = $packageInfo.TagName
            Version     = $packageInfo.Version
            Flavor      = $packageInfo.Flavor
            AssetName   = $packageInfo.FileName
            DownloadUrl = $packageInfo.DownloadUrl
            Sha256      = $packageInfo.Sha256
            ShaSource   = $packageInfo.ShaSource
            ReleaseUrl  = $packageInfo.ReleaseUrl
        }) | Out-Null
    }

    return $packageInfo
}

function Install-Ps7Runtime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo,

        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = if ($PackageInfo.Flavor) { $PackageInfo.Flavor } else { Get-ManifestedCommandFlavor -CommandName 'Initialize-Ps7Runtime' }
    }

    $runtimeHome = Get-ManagedPs7RuntimeHome -Version $PackageInfo.Version -Flavor $Flavor -LocalRoot $LocalRoot
    $currentValidation = Test-Ps7Runtime -RuntimeHome $runtimeHome

    if ($currentValidation.Status -ne 'Ready') {
        New-ManifestedDirectory -Path (Split-Path -Parent $runtimeHome) | Out-Null

        $stageInfo = $null
        try {
            $stageInfo = Expand-ManifestedArchiveToStage -PackagePath $PackageInfo.Path -Prefix 'ps7'

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

    $validation = Test-Ps7Runtime -RuntimeHome $runtimeHome
    if ($validation.Status -ne 'Ready') {
        throw "PowerShell runtime validation failed after install at $runtimeHome."
    }

    [pscustomobject]@{
        Action      = if ($currentValidation.Status -eq 'Ready') { 'Skipped' } else { 'Installed' }
        TagName     = $PackageInfo.TagName
        Version     = $PackageInfo.Version
        Flavor      = $Flavor
        RuntimeHome = $runtimeHome
        PwshPath    = $validation.PwshPath
        Source      = $PackageInfo.Source
        DownloadUrl = $PackageInfo.DownloadUrl
        Sha256      = $PackageInfo.Sha256
    }
}

function Get-Ps7RuntimeFacts {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = $null
    try {
        if ([string]::IsNullOrWhiteSpace($Flavor)) {
            $Flavor = Get-ManifestedCommandFlavor -CommandName 'Initialize-Ps7Runtime'
        }

        $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    }
    catch {
        return (New-ManifestedRuntimeFacts -RuntimeName 'Ps7Runtime' -CommandName 'Initialize-Ps7Runtime' -RuntimeKind 'PortablePackage' -LocalRoot $LocalRoot -Layout $layout -PlatformSupported:$false -BlockedReason $_.Exception.Message -AdditionalProperties @{
            Flavor              = $Flavor
            Package             = $null
            PackagePath         = $null
            InvalidRuntimeHomes = @()
        })
    }

    $partialPaths = @()
    if (Test-Path -LiteralPath $layout.Ps7CacheRoot) {
        $partialPaths += @(Get-ChildItem -LiteralPath $layout.Ps7CacheRoot -File -Filter '*.download' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    }
    $partialPaths += @(Get-ManifestedStageDirectories -Prefix 'ps7' -Mode TemporaryShort -LegacyRootPaths @($layout.ToolsRoot) | Select-Object -ExpandProperty FullName)

    $installed = Get-InstalledPs7Runtime -Flavor $Flavor -LocalRoot $layout.LocalRoot
    $managedRuntime = $installed.Current
    $externalRuntime = $null
    if (-not $managedRuntime) {
        $externalRuntime = Get-SystemPs7Runtime -LocalRoot $layout.LocalRoot
    }

    $currentRuntime = if ($managedRuntime) { $managedRuntime } else { $externalRuntime }
    $package = Get-LatestCachedPs7RuntimePackage -Flavor $Flavor -LocalRoot $layout.LocalRoot
    $invalidRuntimeHomes = @($installed.Invalid | Select-Object -ExpandProperty RuntimeHome)

    $currentVersion = $null
    if ($currentRuntime) {
        $currentVersion = $currentRuntime.Version
    }
    elseif ($package) {
        $currentVersion = $package.Version
    }

    $runtimeHome = $null
    $runtimeSource = $null
    $executablePath = $null
    $runtimeValidation = $null
    if ($currentRuntime) {
        $runtimeHome = $currentRuntime.RuntimeHome
        $executablePath = $currentRuntime.PwshPath
        $runtimeValidation = $currentRuntime.Validation
    }
    if ($managedRuntime) {
        $runtimeSource = 'Managed'
    }
    elseif ($externalRuntime) {
        $runtimeSource = 'External'
    }

    return (New-ManifestedRuntimeFacts -RuntimeName 'Ps7Runtime' -CommandName 'Initialize-Ps7Runtime' -RuntimeKind 'PortablePackage' -LocalRoot $layout.LocalRoot -Layout $layout -ManagedRuntime $managedRuntime -ExternalRuntime $externalRuntime -Artifact $package -PartialPaths $partialPaths -InvalidPaths $invalidRuntimeHomes -Version $currentVersion -RuntimeHome $runtimeHome -RuntimeSource $runtimeSource -ExecutablePath $executablePath -RuntimeValidation $runtimeValidation -AdditionalProperties @{
        Flavor              = $Flavor
        Package             = $package
        PackagePath         = if ($package) { $package.Path } else { $null }
        InvalidRuntimeHomes = $invalidRuntimeHomes
    })
}

function Initialize-Ps7Runtime {
<#
.SYNOPSIS
Ensures the managed PowerShell 7 runtime is available for the sandbox toolchain.

.DESCRIPTION
Uses the shared runtime kernel to collect facts, derive the execution plan,
perform any required acquisition or install steps, and synchronize command
resolution for the managed PowerShell runtime.

.PARAMETER RefreshPs7
Forces package reacquisition and reinstall planning for the managed runtime.

.EXAMPLE
Initialize-Ps7Runtime

.EXAMPLE
Initialize-Ps7Runtime -RefreshPs7
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshPs7
    )

    return (Invoke-ManifestedCommandInitialization -Name 'Initialize-Ps7Runtime' -PSCmdletObject $PSCmdlet -RefreshRequested:$RefreshPs7 -WhatIfMode:$WhatIfPreference)
}
