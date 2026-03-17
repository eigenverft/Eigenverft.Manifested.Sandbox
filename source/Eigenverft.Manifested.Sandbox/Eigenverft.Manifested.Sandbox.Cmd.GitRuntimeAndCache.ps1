<#
    Eigenverft.Manifested.Sandbox.Cmd.GitRuntimeAndCache
#>

function ConvertTo-GitVersion {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    $match = [regex]::Match($VersionText, '(\d+\.\d+\.\d+)(?:\.windows\.(\d+)|\.(\d+))?')
    if (-not $match.Success) {
        return $null
    }

    $revision = if ($match.Groups[2].Success) { $match.Groups[2].Value } elseif ($match.Groups[3].Success) { $match.Groups[3].Value } else { $null }
    $normalized = if ($revision) { '{0}.{1}' -f $match.Groups[1].Value, $revision } else { $match.Groups[1].Value }
    return [version]$normalized
}

function ConvertTo-GitReleaseVersion {
    [CmdletBinding()]
    param(
        [string]$TagName
    )

    $versionObject = ConvertTo-GitVersion -VersionText $TagName
    if (-not $versionObject) {
        throw "Could not parse the Git for Windows release tag '$TagName'."
    }

    return $versionObject.ToString()
}

function Get-GitFlavor {
    [CmdletBinding()]
    param()

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        throw 'Only Windows hosts are supported by this MinGit runtime bootstrap.'
    }

    $archHints = @($env:PROCESSOR_ARCHITECTURE, $env:PROCESSOR_ARCHITEW6432) -join ';'
    if ($archHints -match 'ARM64') {
        return 'arm64'
    }

    if ([Environment]::Is64BitOperatingSystem) {
        return '64-bit'
    }

    throw 'Only 64-bit Windows targets are supported by this MinGit runtime bootstrap.'
}

function Get-GitPersistedPackageDetails {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $commandState = Get-ManifestedCommandState -CommandName 'Initialize-GitRuntime' -LocalRoot $LocalRoot
    if ($commandState -and $commandState.PSObject.Properties['Details']) {
        return $commandState.Details
    }

    return $null
}

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
    if (-not (Test-Path -LiteralPath $layout.GitCacheRoot)) {
        return @()
    }

    $persistedDetails = Get-GitPersistedPackageDetails -LocalRoot $layout.LocalRoot
    $pattern = '^MinGit-(\d+\.\d+\.\d+\.\d+)-' + [regex]::Escape($Flavor) + '\.zip$'

    $items = Get-ChildItem -LiteralPath $layout.GitCacheRoot -File -Filter '*.zip' -ErrorAction SilentlyContinue |
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
        Sort-Object -Descending -Property @{ Expression = { ConvertTo-GitVersion -VersionText $_.Version } }

    return @($items)
}

function Get-LatestCachedGitRuntimePackage {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $cachedPackages = @(Get-CachedGitRuntimePackages -Flavor $Flavor -LocalRoot $LocalRoot)
    $trustedPackage = @($cachedPackages | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Sha256) } | Select-Object -First 1)
    if ($trustedPackage) {
        return $trustedPackage[0]
    }

    return ($cachedPackages | Select-Object -First 1)
}

function Get-ManagedGitRuntimeHome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$Flavor,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    return (Join-Path $layout.GitToolsRoot ($Version + '\' + $Flavor))
}

function Test-GitRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    $gitCmd = Join-Path $RuntimeHome 'cmd\git.exe'

    if (-not (Test-Path -LiteralPath $RuntimeHome)) {
        $status = 'Missing'
        $reportedVersion = $null
        $reportedBanner = $null
    }
    elseif (-not (Test-Path -LiteralPath $gitCmd)) {
        $status = 'NeedsRepair'
        $reportedVersion = $null
        $reportedBanner = $null
    }
    else {
        $reportedBanner = $null
        try {
            $reportedBanner = (& $gitCmd --version 2>$null | Select-Object -First 1)
            if ($reportedBanner) {
                $reportedBanner = $reportedBanner.ToString().Trim()
            }
        }
        catch {
            $reportedBanner = $null
        }

        $reportedVersionObject = ConvertTo-GitVersion -VersionText $reportedBanner
        $reportedVersion = if ($reportedVersionObject) { $reportedVersionObject.ToString() } else { $null }
        $status = if ($reportedVersion) { 'Ready' } else { 'NeedsRepair' }
    }

    [pscustomobject]@{
        Status          = $status
        IsReady         = ($status -eq 'Ready')
        RuntimeHome     = $RuntimeHome
        GitCmd          = $gitCmd
        ReportedVersion = $reportedVersion
        ReportedBanner  = $reportedBanner
    }
}

function Get-InstalledGitRuntime {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-GitFlavor
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $entries = @()

    if (Test-Path -LiteralPath $layout.GitToolsRoot) {
        $versionRoots = Get-ChildItem -LiteralPath $layout.GitToolsRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object -Descending -Property @{ Expression = { ConvertTo-GitVersion -VersionText $_.Name } }

        foreach ($versionRoot in $versionRoots) {
            $runtimeHome = Join-Path $versionRoot.FullName $Flavor
            if (-not (Test-Path -LiteralPath $runtimeHome)) {
                continue
            }

            $validation = Test-GitRuntime -RuntimeHome $runtimeHome
            $expectedVersion = ConvertTo-GitVersion -VersionText $versionRoot.Name
            $reportedVersion = ConvertTo-GitVersion -VersionText $validation.ReportedVersion
            $versionMatches = (-not $reportedVersion) -or (-not $expectedVersion) -or ($reportedVersion -eq $expectedVersion)

            $entries += [pscustomobject]@{
                Version        = $versionRoot.Name
                Flavor         = $Flavor
                RuntimeHome    = $runtimeHome
                GitCmd         = $validation.GitCmd
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

function Get-SystemGitRuntime {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $additionalPaths = @()
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $additionalPaths += (Join-Path $env:ProgramFiles 'Git\cmd\git.exe')
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $additionalPaths += (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')
    }

    $gitCmd = Get-ManifestedApplicationPath -CommandName 'git.exe' -ExcludedRoots @($layout.GitToolsRoot) -AdditionalPaths $additionalPaths
    if ([string]::IsNullOrWhiteSpace($gitCmd)) {
        return $null
    }

    $runtimeHome = Split-Path (Split-Path -Parent $gitCmd) -Parent
    $validation = Test-GitRuntime -RuntimeHome $runtimeHome
    if (-not $validation.IsReady) {
        return $null
    }

    $versionObject = ConvertTo-GitVersion -VersionText $validation.ReportedVersion
    if (-not $versionObject) {
        return $null
    }

    [pscustomobject]@{
        Version     = $versionObject.ToString()
        Flavor      = $null
        RuntimeHome = $runtimeHome
        GitCmd      = $validation.GitCmd
        Validation  = $validation
        IsReady     = $true
        Source      = 'External'
        Discovery   = 'Path'
    }
}

function Test-GitRuntimePackage {
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

function Get-GitRuntimeState {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Flavor)) {
            $Flavor = Get-GitFlavor
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
    if (Test-Path -LiteralPath $layout.GitCacheRoot) {
        $partialPaths += @(Get-ChildItem -LiteralPath $layout.GitCacheRoot -File -Filter '*.download' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    }
    $partialPaths += @(Get-ManifestedStageDirectories -Prefix 'git' -Mode TemporaryShort -LegacyRootPaths @($layout.ToolsRoot) | Select-Object -ExpandProperty FullName)

    $installed = Get-InstalledGitRuntime -Flavor $Flavor -LocalRoot $layout.LocalRoot
    $managedRuntime = $installed.Current
    $externalRuntime = $null
    if (-not $managedRuntime) {
        $externalRuntime = Get-SystemGitRuntime -LocalRoot $layout.LocalRoot
    }

    $currentRuntime = if ($managedRuntime) { $managedRuntime } else { $externalRuntime }
    $runtimeSource = if ($managedRuntime) { 'Managed' } elseif ($externalRuntime) { 'External' } else { $null }
    $invalidRuntimeHomes = @($installed.Invalid | Select-Object -ExpandProperty RuntimeHome)
    $package = Get-LatestCachedGitRuntimePackage -Flavor $Flavor -LocalRoot $layout.LocalRoot

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
        ExecutablePath      = if ($currentRuntime) { $currentRuntime.GitCmd } else { $null }
        Runtime             = if ($currentRuntime) { $currentRuntime.Validation } else { $null }
        InvalidRuntimeHomes = $invalidRuntimeHomes
        Package             = $package
        PackagePath         = if ($package) { $package.Path } else { $null }
        PartialPaths        = $partialPaths
        BlockedReason       = $null
    }
}

function Repair-GitRuntime {
    [CmdletBinding()]
    param(
        [pscustomobject]$State,
        [string[]]$CorruptPackagePaths = @(),
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $State) {
        $State = Get-GitRuntimeState -Flavor $Flavor -LocalRoot $LocalRoot
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

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    New-ManifestedDirectory -Path $layout.GitCacheRoot | Out-Null

    $release = $null
    try {
        $release = Get-GitRelease -Flavor $Flavor
    }
    catch {
        $release = $null
    }

    if ($release) {
        $packagePath = Join-Path $layout.GitCacheRoot $release.FileName
        $downloadPath = Get-ManifestedDownloadPath -TargetPath $packagePath
        $action = 'ReusedCache'

        if ($RefreshGit -or -not (Test-Path -LiteralPath $packagePath)) {
            Remove-ManifestedPath -Path $downloadPath | Out-Null

            try {
                Write-Host "Downloading MinGit $($release.Version) ($Flavor)..."
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

                Write-Warning ('Could not refresh the MinGit package. Using cached copy. ' + $_.Exception.Message)
                $action = 'ReusedCache'
            }
        }

        return [pscustomobject]@{
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
    }

    $cachedPackage = Get-LatestCachedGitRuntimePackage -Flavor $Flavor -LocalRoot $LocalRoot
    if (-not $cachedPackage) {
        throw 'Could not reach GitHub and no cached MinGit ZIP was found.'
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

function Install-GitRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo,

        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = if ($PackageInfo.Flavor) { $PackageInfo.Flavor } else { Get-GitFlavor }
    }

    $runtimeHome = Get-ManagedGitRuntimeHome -Version $PackageInfo.Version -Flavor $Flavor -LocalRoot $LocalRoot
    $currentValidation = Test-GitRuntime -RuntimeHome $runtimeHome

    if ($currentValidation.Status -ne 'Ready') {
        $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
        New-ManifestedDirectory -Path (Split-Path -Parent $runtimeHome) | Out-Null

        $stageInfo = $null
        try {
            $stageInfo = Expand-ManifestedArchiveToStage -PackagePath $PackageInfo.Path -Prefix 'git'

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

    $validation = Test-GitRuntime -RuntimeHome $runtimeHome
    if ($validation.Status -ne 'Ready') {
        throw "MinGit runtime validation failed after install at $runtimeHome."
    }

    [pscustomobject]@{
        Action      = if ($currentValidation.Status -eq 'Ready') { 'Skipped' } else { 'Installed' }
        TagName     = $PackageInfo.TagName
        Version     = $PackageInfo.Version
        Flavor      = $Flavor
        RuntimeHome = $runtimeHome
        GitCmd      = $validation.GitCmd
        Source      = $PackageInfo.Source
        DownloadUrl = $PackageInfo.DownloadUrl
        Sha256      = $PackageInfo.Sha256
    }
}

function Initialize-GitRuntime {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshGit
    )

    $LocalRoot = (Get-ManifestedLayout).LocalRoot
    $selfElevationContext = Get-ManifestedSelfElevationContext

    $actionsTaken = New-Object System.Collections.Generic.List[string]
    $plannedActions = New-Object System.Collections.Generic.List[string]
    $repairResult = $null
    $packageInfo = $null
    $packageTest = $null
    $installResult = $null
    $commandEnvironment = $null

    $initialState = Get-GitRuntimeState -LocalRoot $LocalRoot
    $state = $initialState
    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName 'Initialize-GitRuntime' -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($state.Status -eq 'Blocked') {
        $commandEnvironment = Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-GitRuntime' -RuntimeState $state
        $result = [pscustomobject]@{
            LocalRoot       = $state.LocalRoot
            Layout          = $state.Layout
            InitialState    = $initialState
            FinalState      = $state
            ActionTaken     = @('None')
            PlannedActions  = @()
            RestartRequired = $false
            Package         = $null
            PackageTest     = $null
            RuntimeTest     = $null
            RepairResult    = $null
            InstallResult   = $null
            CommandEnvironment = $commandEnvironment
            Elevation       = $elevationPlan
        }

        if ($WhatIfPreference) {
            Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $null -Force
            return $result
        }

        $statePath = Save-ManifestedInvokeState -CommandName 'Initialize-GitRuntime' -Result $result -LocalRoot $LocalRoot -Details @{
            Version = $state.CurrentVersion
            Flavor  = $state.Flavor
            RuntimeHome = $state.RuntimeHome
            RuntimeSource = $state.RuntimeSource
            ExecutablePath = $state.ExecutablePath
        }
        Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $statePath -Force
        return $result
    }

    $needsRepair = $state.Status -in @('Partial', 'NeedsRepair')
    $needsInstall = $RefreshGit -or -not $state.RuntimeHome
    $needsAcquire = $RefreshGit -or (-not $state.PackagePath)

    if ($needsRepair) {
        $plannedActions.Add('Repair-GitRuntime') | Out-Null
    }
    if ($needsInstall -and $needsAcquire) {
        $plannedActions.Add('Save-GitRuntimePackage') | Out-Null
    }
    if ($needsInstall) {
        $plannedActions.Add('Test-GitRuntimePackage') | Out-Null
        $plannedActions.Add('Install-GitRuntime') | Out-Null
    }
    $plannedActions.Add('Sync-ManifestedCommandLineEnvironment') | Out-Null

    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName 'Initialize-GitRuntime' -PlannedActions @($plannedActions) -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($needsRepair) {
        if (-not $PSCmdlet.ShouldProcess($state.Layout.GitToolsRoot, 'Repair MinGit runtime state')) {
            return [pscustomobject]@{
                LocalRoot          = $state.LocalRoot
                Layout             = $state.Layout
                InitialState       = $initialState
                FinalState         = $state
                ActionTaken        = @('WhatIf')
                PlannedActions     = @($plannedActions)
                RestartRequired    = $false
                Package            = $null
                PackageTest        = $null
                RuntimeTest        = $state.Runtime
                RepairResult       = $null
                InstallResult      = $null
                CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-GitRuntime' -RuntimeState $state)
                PersistedStatePath = $null
                Elevation          = $elevationPlan
            }
        }

        $repairResult = Repair-GitRuntime -State $state -Flavor $state.Flavor -LocalRoot $state.LocalRoot
        if ($repairResult.Action -eq 'Repaired') {
            $actionsTaken.Add('Repair-GitRuntime') | Out-Null
        }

        $state = Get-GitRuntimeState -Flavor $state.Flavor -LocalRoot $state.LocalRoot
        $needsInstall = $RefreshGit -or -not $state.RuntimeHome
        $needsAcquire = $RefreshGit -or (-not $state.PackagePath)
    }

    if ($needsInstall) {
        if ($needsAcquire) {
            if (-not $PSCmdlet.ShouldProcess($state.Layout.GitCacheRoot, 'Acquire MinGit runtime package')) {
                return [pscustomobject]@{
                    LocalRoot          = $state.LocalRoot
                    Layout             = $state.Layout
                    InitialState       = $initialState
                    FinalState         = $state
                    ActionTaken        = @('WhatIf')
                    PlannedActions     = @($plannedActions)
                    RestartRequired    = $false
                    Package            = $null
                    PackageTest        = $null
                    RuntimeTest        = $state.Runtime
                    RepairResult       = $repairResult
                    InstallResult      = $null
                    CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-GitRuntime' -RuntimeState $state)
                    PersistedStatePath = $null
                    Elevation          = $elevationPlan
                }
            }

            $packageInfo = Save-GitRuntimePackage -RefreshGit:$RefreshGit -Flavor $state.Flavor -LocalRoot $state.LocalRoot
            if ($packageInfo.Action -eq 'Downloaded') {
                $actionsTaken.Add('Save-GitRuntimePackage') | Out-Null
            }
        }
        else {
            $packageInfo = $state.Package
        }

        $packageTest = Test-GitRuntimePackage -PackageInfo $packageInfo
        if ($packageTest.Status -eq 'CorruptCache') {
            if (-not $PSCmdlet.ShouldProcess($packageInfo.Path, 'Repair corrupt MinGit runtime package')) {
                return [pscustomobject]@{
                    LocalRoot          = $state.LocalRoot
                    Layout             = $state.Layout
                    InitialState       = $initialState
                    FinalState         = $state
                    ActionTaken        = @('WhatIf')
                    PlannedActions     = @($plannedActions)
                    RestartRequired    = $false
                    Package            = $packageInfo
                    PackageTest        = $packageTest
                    RuntimeTest        = $state.Runtime
                    RepairResult       = $repairResult
                    InstallResult      = $null
                    CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-GitRuntime' -RuntimeState $state)
                    PersistedStatePath = $null
                    Elevation          = $elevationPlan
                }
            }

            $repairResult = Repair-GitRuntime -State $state -CorruptPackagePaths @($packageInfo.Path) -Flavor $state.Flavor -LocalRoot $state.LocalRoot
            if ($repairResult.Action -eq 'Repaired') {
                $actionsTaken.Add('Repair-GitRuntime') | Out-Null
            }

            $packageInfo = Save-GitRuntimePackage -RefreshGit:$true -Flavor $state.Flavor -LocalRoot $state.LocalRoot
            if ($packageInfo.Action -eq 'Downloaded') {
                $actionsTaken.Add('Save-GitRuntimePackage') | Out-Null
            }

            $packageTest = Test-GitRuntimePackage -PackageInfo $packageInfo
        }

        if ($packageTest.Status -eq 'UnverifiedCache') {
            throw "MinGit runtime package validation failed because no trusted checksum could be resolved for $($packageInfo.FileName)."
        }

        if ($packageTest.Status -ne 'Ready') {
            throw "MinGit runtime package validation failed with status $($packageTest.Status)."
        }

        $commandParameters = @{}
        if ($RefreshGit) {
            $commandParameters['RefreshGit'] = $true
        }
        if ($PSBoundParameters.ContainsKey('WhatIf')) {
            $commandParameters['WhatIf'] = $true
        }

        $elevatedResult = Invoke-ManifestedElevatedCommand -ElevationPlan $elevationPlan -CommandName 'Initialize-GitRuntime' -CommandParameters $commandParameters
        if ($null -ne $elevatedResult) {
            return $elevatedResult
        }

        if (-not $PSCmdlet.ShouldProcess($state.Layout.GitToolsRoot, 'Install MinGit runtime')) {
            return [pscustomobject]@{
                LocalRoot          = $state.LocalRoot
                Layout             = $state.Layout
                InitialState       = $initialState
                FinalState         = $state
                ActionTaken        = @('WhatIf')
                PlannedActions     = @($plannedActions)
                RestartRequired    = $false
                Package            = $packageInfo
                PackageTest        = $packageTest
                RuntimeTest        = $state.Runtime
                RepairResult       = $repairResult
                InstallResult      = $null
                CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-GitRuntime' -RuntimeState $state)
                PersistedStatePath = $null
                Elevation          = $elevationPlan
            }
        }

        $installResult = Install-GitRuntime -PackageInfo $packageInfo -Flavor $state.Flavor -LocalRoot $state.LocalRoot
        if ($installResult.Action -eq 'Installed') {
            $actionsTaken.Add('Install-GitRuntime') | Out-Null
        }
    }

    $finalState = Get-GitRuntimeState -Flavor $state.Flavor -LocalRoot $state.LocalRoot
    $runtimeTest = if ($finalState.RuntimeHome) { Test-GitRuntime -RuntimeHome $finalState.RuntimeHome } else { $null }

    $commandEnvironment = Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-GitRuntime' -RuntimeState $finalState
    if ($commandEnvironment.Applicable) {
        if (-not $PSCmdlet.ShouldProcess($commandEnvironment.DesiredCommandDirectory, 'Synchronize Git command-line environment')) {
            return [pscustomobject]@{
                LocalRoot          = $finalState.LocalRoot
                Layout             = $finalState.Layout
                InitialState       = $initialState
                FinalState         = $finalState
                ActionTaken        = @('WhatIf')
                PlannedActions     = @($plannedActions)
                RestartRequired    = $false
                Package            = $packageInfo
                PackageTest        = $packageTest
                RuntimeTest        = $runtimeTest
                RepairResult       = $repairResult
                InstallResult      = $installResult
                CommandEnvironment = $commandEnvironment
                PersistedStatePath = $null
                Elevation          = $elevationPlan
            }
        }

        $commandEnvironment = Sync-ManifestedCommandLineEnvironment -Specification (Get-ManifestedCommandEnvironmentSpec -CommandName 'Initialize-GitRuntime' -RuntimeState $finalState)
        if ($commandEnvironment.Status -eq 'Updated') {
            $actionsTaken.Add('Sync-ManifestedCommandLineEnvironment') | Out-Null
        }
    }

    $result = [pscustomobject]@{
        LocalRoot       = $finalState.LocalRoot
        Layout          = $finalState.Layout
        InitialState    = $initialState
        FinalState      = $finalState
        ActionTaken     = if ($actionsTaken.Count -gt 0) { @($actionsTaken) } else { @('None') }
        PlannedActions  = @($plannedActions)
        RestartRequired = $false
        Package         = $packageInfo
        PackageTest     = $packageTest
        RuntimeTest     = $runtimeTest
        RepairResult    = $repairResult
        InstallResult   = $installResult
        CommandEnvironment = $commandEnvironment
        Elevation       = $elevationPlan
    }

    if ($WhatIfPreference) {
        Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $null -Force
        return $result
    }

    $statePath = Save-ManifestedInvokeState -CommandName 'Initialize-GitRuntime' -Result $result -LocalRoot $LocalRoot -Details @{
        Tag         = if ($packageInfo) { $packageInfo.TagName } else { $null }
        Version     = $finalState.CurrentVersion
        Flavor      = $finalState.Flavor
        AssetName   = if ($packageInfo) { $packageInfo.FileName } else { $null }
        PackagePath = if ($packageInfo) { $packageInfo.Path } else { $finalState.PackagePath }
        RuntimeHome = $finalState.RuntimeHome
        RuntimeSource = $finalState.RuntimeSource
        ExecutablePath = $finalState.ExecutablePath
        DownloadUrl = if ($packageInfo) { $packageInfo.DownloadUrl } else { $null }
        Sha256      = if ($packageInfo) { $packageInfo.Sha256 } else { $null }
        ShaSource   = if ($packageInfo) { $packageInfo.ShaSource } else { $null }
    }
    Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $statePath -Force

    return $result
}
