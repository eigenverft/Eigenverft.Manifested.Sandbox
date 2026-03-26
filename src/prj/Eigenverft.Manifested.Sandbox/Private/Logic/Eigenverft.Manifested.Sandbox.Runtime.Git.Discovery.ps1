<#
    Eigenverft.Manifested.Sandbox.Runtime.Git.Discovery
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

    return (Get-ManifestedArchivePersistedPackageDetails -CommandName 'Initialize-GitRuntime' -LocalRoot $LocalRoot)
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
    return (Get-ManagedManifestedArchiveRuntimeHome -ToolsRootPath $layout.GitToolsRoot -Version $Version -Flavor $Flavor)
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

    $partialPaths = @(Get-ManifestedArchiveRuntimePartialPaths -CacheRootPath $layout.GitCacheRoot -StagePrefix 'git' -LegacyRootPaths @($layout.ToolsRoot))

    $installed = Get-InstalledGitRuntime -Flavor $Flavor -LocalRoot $layout.LocalRoot
    $managedRuntime = $installed.Current
    $externalRuntime = $null
    if (-not $managedRuntime) {
        $externalRuntime = Get-SystemGitRuntime -LocalRoot $layout.LocalRoot
    }

    $package = Get-LatestCachedGitRuntimePackage -Flavor $Flavor -LocalRoot $layout.LocalRoot
    $runtimeSelection = Get-ManifestedArchiveRuntimeSelection -Installed $installed -ExternalRuntime $externalRuntime -Package $package -PartialPaths $partialPaths

    [pscustomobject]@{
        Status              = $runtimeSelection.Status
        LocalRoot           = $layout.LocalRoot
        Layout              = $layout
        Flavor              = $Flavor
        CurrentVersion      = if ($runtimeSelection.CurrentRuntime) { $runtimeSelection.CurrentRuntime.Version } elseif ($package) { $package.Version } else { $null }
        RuntimeHome         = if ($runtimeSelection.CurrentRuntime) { $runtimeSelection.CurrentRuntime.RuntimeHome } else { $null }
        RuntimeSource       = $runtimeSelection.RuntimeSource
        ExecutablePath      = if ($runtimeSelection.CurrentRuntime) { $runtimeSelection.CurrentRuntime.GitCmd } else { $null }
        Runtime             = if ($runtimeSelection.CurrentRuntime) { $runtimeSelection.CurrentRuntime.Validation } else { $null }
        InvalidRuntimeHomes = $runtimeSelection.InvalidRuntimeHomes
        Package             = $package
        PackagePath         = if ($package) { $package.Path } else { $null }
        PartialPaths        = $partialPaths
        BlockedReason       = $null
    }
}

