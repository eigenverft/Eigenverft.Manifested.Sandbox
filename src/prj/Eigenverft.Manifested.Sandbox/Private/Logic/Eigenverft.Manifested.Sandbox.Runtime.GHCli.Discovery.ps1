<#
    Eigenverft.Manifested.Sandbox.Runtime.GHCli.Discovery
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

    return (Get-ManifestedArchivePersistedPackageDetails -CommandName 'Initialize-GHCliRuntime' -LocalRoot $LocalRoot)
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
    return (Get-ManagedManifestedArchiveRuntimeHome -ToolsRootPath $layout.GHCliToolsRoot -Version $Version -Flavor $Flavor)
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

    $partialPaths = @(Get-ManifestedArchiveRuntimePartialPaths -CacheRootPath $layout.GHCliCacheRoot -StagePrefix 'ghcli' -LegacyRootPaths @($layout.ToolsRoot))

    $installed = Get-InstalledGHCliRuntime -Flavor $Flavor -LocalRoot $layout.LocalRoot
    $managedRuntime = $installed.Current
    $externalRuntime = $null
    if (-not $managedRuntime) {
        $externalRuntime = Get-SystemGHCliRuntime -LocalRoot $layout.LocalRoot
    }

    $package = Get-LatestCachedGHCliRuntimePackage -Flavor $Flavor -LocalRoot $layout.LocalRoot
    $runtimeSelection = Get-ManifestedArchiveRuntimeSelection -Installed $installed -ExternalRuntime $externalRuntime -Package $package -PartialPaths $partialPaths

    [pscustomobject]@{
        Status              = $runtimeSelection.Status
        LocalRoot           = $layout.LocalRoot
        Layout              = $layout
        Flavor              = $Flavor
        CurrentVersion      = if ($runtimeSelection.CurrentRuntime) { $runtimeSelection.CurrentRuntime.Version } elseif ($package) { $package.Version } else { $null }
        RuntimeHome         = if ($runtimeSelection.CurrentRuntime) { $runtimeSelection.CurrentRuntime.RuntimeHome } else { $null }
        RuntimeSource       = $runtimeSelection.RuntimeSource
        ExecutablePath      = if ($runtimeSelection.CurrentRuntime) { $runtimeSelection.CurrentRuntime.GhCmd } else { $null }
        Runtime             = if ($runtimeSelection.CurrentRuntime) { $runtimeSelection.CurrentRuntime.Validation } else { $null }
        InvalidRuntimeHomes = $runtimeSelection.InvalidRuntimeHomes
        Package             = $package
        PackagePath         = if ($package) { $package.Path } else { $null }
        PartialPaths        = $partialPaths
        BlockedReason       = $null
    }
}

