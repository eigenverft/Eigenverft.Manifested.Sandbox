<#
    Eigenverft.Manifested.Sandbox.Runtime.Python.Discovery
#>

function ConvertTo-PythonVersion {
<#
.SYNOPSIS
Normalizes Python version text into a comparable version object.

.DESCRIPTION
Extracts the first `major.minor.patch` fragment from arbitrary Python version
text and converts it into a `[version]` instance so runtime release checks can
compare versions consistently.

.PARAMETER VersionText
Raw version text emitted by Python tooling or release metadata.

.EXAMPLE
ConvertTo-PythonVersion -VersionText 'Python 3.13.2'

.EXAMPLE
ConvertTo-PythonVersion -VersionText '3.13.2rc1'

.NOTES
Returns `$null` when no semantic version fragment can be found.
#>
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    $match = [regex]::Match($VersionText, '(\d+\.\d+\.\d+)')
    if (-not $match.Success) {
        return $null
    }

    return [version]$match.Groups[1].Value
}

function Get-PythonManagedBaselineVersion {
    [CmdletBinding()]
    param()

    return [version]'3.13.0'
}

function Test-PythonManagedReleaseVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [version]$Version
    )

    $baseline = Get-PythonManagedBaselineVersion
    return ($Version.Major -eq $baseline.Major) -and ($Version.Minor -eq $baseline.Minor) -and ($Version -ge $baseline)
}

function Test-PythonExternalRuntimeVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [version]$Version
    )

    $baseline = Get-PythonManagedBaselineVersion
    return ($Version.Major -gt $baseline.Major) -or (($Version.Major -eq $baseline.Major) -and ($Version.Minor -ge $baseline.Minor))
}

function Get-PythonFlavor {
    [CmdletBinding()]
    param()

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        throw 'Only Windows hosts are supported by this Python runtime bootstrap.'
    }

    $archHints = @($env:PROCESSOR_ARCHITECTURE, $env:PROCESSOR_ARCHITEW6432) -join ';'
    if ($archHints -match 'ARM64') {
        return 'arm64'
    }

    if ([Environment]::Is64BitOperatingSystem) {
        return 'amd64'
    }

    throw 'Only 64-bit Windows targets are supported by this Python runtime bootstrap.'
}

function Get-ManagedPythonRuntimeHome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$Flavor,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    return (Join-Path $layout.PythonToolsRoot ($Version + '\' + $Flavor))
}

function Get-PythonRuntimePthPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonHome
    )

    if (-not (Test-Path -LiteralPath $PythonHome)) {
        return $null
    }

    $pthFile = @(Get-ChildItem -LiteralPath $PythonHome -File -Filter 'python*._pth' -ErrorAction SilentlyContinue | Sort-Object -Property Name | Select-Object -First 1)
    if (-not $pthFile) {
        return $null
    }

    return $pthFile[0].FullName
}

function Get-InstalledPythonRuntime {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([string]::IsNullOrWhiteSpace($Flavor)) {
        $Flavor = Get-PythonFlavor
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $entries = @()

    if (Test-Path -LiteralPath $layout.PythonToolsRoot) {
        $versionRoots = Get-ChildItem -LiteralPath $layout.PythonToolsRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object -Descending -Property @{ Expression = { ConvertTo-PythonVersion -VersionText $_.Name } }

        foreach ($versionRoot in $versionRoots) {
            $pythonHome = Join-Path $versionRoot.FullName $Flavor
            if (-not (Test-Path -LiteralPath $pythonHome)) {
                continue
            }

            $validation = Test-PythonRuntime -PythonHome $pythonHome -LocalRoot $layout.LocalRoot
            $expectedVersion = ConvertTo-PythonVersion -VersionText $versionRoot.Name
            $reportedVersion = ConvertTo-PythonVersion -VersionText $validation.ReportedVersion
            $versionMatches = (-not $reportedVersion) -or (-not $expectedVersion) -or ($reportedVersion -eq $expectedVersion)

            $entries += [pscustomobject]@{
                Version        = $versionRoot.Name
                Flavor         = $Flavor
                PythonHome     = $pythonHome
                PythonExe      = $validation.PythonExe
                Validation     = $validation
                VersionMatches = $versionMatches
                PipVersion     = $validation.PipVersion
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

function Get-ManifestedPythonExternalPaths {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $candidatePaths = New-Object System.Collections.Generic.List[string]

    foreach ($commandName in @('python.exe', 'python')) {
        foreach ($command in @(Get-Command -Name $commandName -CommandType Application -All -ErrorAction SilentlyContinue)) {
            $commandPath = $null
            if ($command.PSObject.Properties['Path'] -and $command.Path) {
                $commandPath = $command.Path
            }
            elseif ($command.PSObject.Properties['Source'] -and $command.Source) {
                $commandPath = $command.Source
            }

            if (-not [string]::IsNullOrWhiteSpace($commandPath) -and $commandPath -like '*.exe') {
                $candidatePaths.Add($commandPath) | Out-Null
            }
        }
    }

    $additionalPatterns = @()
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $additionalPatterns += (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python*\python.exe')
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $additionalPatterns += (Join-Path $env:ProgramFiles 'Python*\python.exe')
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $additionalPatterns += (Join-Path $env:USERPROFILE '.pyenv\pyenv-win\versions\*\python.exe')
    }

    foreach ($pattern in $additionalPatterns) {
        foreach ($candidate in @(Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue)) {
            $candidatePaths.Add($candidate.FullName) | Out-Null
        }
    }

    $resolvedPaths = New-Object System.Collections.Generic.List[string]
    foreach ($candidatePath in @($candidatePaths | Select-Object -Unique)) {
        $fullCandidatePath = Get-ManifestedFullPath -Path $candidatePath
        if ([string]::IsNullOrWhiteSpace($fullCandidatePath) -or -not (Test-Path -LiteralPath $fullCandidatePath)) {
            continue
        }
        if (Test-ManifestedPathIsUnderRoot -Path $fullCandidatePath -RootPath $layout.PythonToolsRoot) {
            continue
        }
        if ($fullCandidatePath -like '*\WindowsApps\python.exe') {
            continue
        }

        $resolvedPaths.Add($fullCandidatePath) | Out-Null
    }

    return @($resolvedPaths | Select-Object -Unique)
}

function Test-ExternalPythonRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $versionProbe = Get-PythonReportedVersionProbe -PythonExe $PythonExe -LocalRoot $LocalRoot
    $reportedVersion = $versionProbe.ReportedVersion
    $versionObject = ConvertTo-PythonVersion -VersionText $reportedVersion
    $pipProbe = if ($versionObject -and (Test-PythonExternalRuntimeVersion -Version $versionObject)) { Get-PythonPipVersionProbe -PythonExe $PythonExe -LocalRoot $LocalRoot } else { $null }
    $pipVersion = if ($pipProbe) { $pipProbe.PipVersion } else { $null }
    $isReady = ($versionObject -and (Test-PythonExternalRuntimeVersion -Version $versionObject) -and -not [string]::IsNullOrWhiteSpace($pipVersion))

    [pscustomobject]@{
        Status          = if ($isReady) { 'Ready' } else { 'Invalid' }
        IsReady         = $isReady
        PythonHome      = if (Test-Path -LiteralPath $PythonExe) { Split-Path -Parent $PythonExe } else { $null }
        PythonExe       = $PythonExe
        ReportedVersion = if ($versionObject) { $versionObject.ToString() } else { $reportedVersion }
        PipVersion      = $pipVersion
        VersionCommandResult = $versionProbe.CommandResult
        PipCommandResult = if ($pipProbe) { $pipProbe.CommandResult } else { $null }
    }
}

function Get-ManifestedPythonRuntimeFromCandidatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CandidatePath,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $validation = Test-ExternalPythonRuntime -PythonExe $CandidatePath -LocalRoot $LocalRoot
    if (-not $validation.IsReady) {
        return $null
    }

    [pscustomobject]@{
        Version     = $validation.ReportedVersion
        Flavor      = $null
        PythonHome  = $validation.PythonHome
        PythonExe   = $validation.PythonExe
        Validation  = $validation
        PipVersion  = $validation.PipVersion
        IsReady     = $true
        Source      = 'External'
        Discovery   = 'Path'
    }
}

function Get-SystemPythonRuntime {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    foreach ($candidatePath in @(Get-ManifestedPythonExternalPaths -LocalRoot $LocalRoot)) {
        $runtime = Get-ManifestedPythonRuntimeFromCandidatePath -CandidatePath $candidatePath -LocalRoot $LocalRoot
        if ($runtime) {
            return $runtime
        }
    }

    return $null
}

function Get-PythonRuntimeState {
    [CmdletBinding()]
    param(
        [string]$Flavor,
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Flavor)) {
            $Flavor = Get-PythonFlavor
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
            PipVersion          = $null
            InvalidRuntimeHomes = @()
            Package             = $null
            PackagePath         = $null
            PartialPaths        = @()
            BlockedReason       = $_.Exception.Message
        }
    }

    $partialPaths = @()
    if (Test-Path -LiteralPath $layout.PythonCacheRoot) {
        $partialPaths += @(Get-ChildItem -LiteralPath $layout.PythonCacheRoot -File -Filter '*.download' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    }
    $partialPaths += @(Get-ManifestedStageDirectories -Prefix 'python' -Mode TemporaryShort -LegacyRootPaths @($layout.ToolsRoot) | Select-Object -ExpandProperty FullName)

    $installed = Get-InstalledPythonRuntime -Flavor $Flavor -LocalRoot $layout.LocalRoot
    $managedRuntime = $installed.Current
    $externalRuntime = $null
    if (-not $managedRuntime) {
        $externalRuntime = Get-SystemPythonRuntime -LocalRoot $layout.LocalRoot
    }

    $currentRuntime = if ($managedRuntime) { $managedRuntime } else { $externalRuntime }
    $runtimeSource = if ($managedRuntime) { 'Managed' } elseif ($externalRuntime) { 'External' } else { $null }
    $invalidRuntimeHomes = @($installed.Invalid | Select-Object -ExpandProperty PythonHome)
    $package = Get-LatestCachedPythonRuntimePackage -Flavor $Flavor -LocalRoot $layout.LocalRoot

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
        RuntimeHome         = if ($currentRuntime) { $currentRuntime.PythonHome } else { $null }
        RuntimeSource       = $runtimeSource
        ExecutablePath      = if ($currentRuntime) { $currentRuntime.PythonExe } else { $null }
        Runtime             = if ($currentRuntime) { $currentRuntime.Validation } else { $null }
        PipVersion          = if ($currentRuntime -and $currentRuntime.PSObject.Properties['PipVersion']) { $currentRuntime.PipVersion } else { $null }
        InvalidRuntimeHomes = $invalidRuntimeHomes
        Package             = $package
        PackagePath         = if ($package) { $package.Path } else { $null }
        PartialPaths        = $partialPaths
        BlockedReason       = $null
    }
}

