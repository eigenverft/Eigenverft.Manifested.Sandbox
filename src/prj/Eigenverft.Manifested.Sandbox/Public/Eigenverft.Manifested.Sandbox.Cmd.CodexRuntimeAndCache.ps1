<#
    Eigenverft.Manifested.Sandbox.Cmd.CodexRuntimeAndCache
#>

$script:ManifestedSandboxCodexPackage = '@openai/codex@latest'

function ConvertTo-CodexVersion {
<#
.SYNOPSIS
Normalizes Codex version text to the managed semantic version string.

.DESCRIPTION
Extracts a Codex semantic version from raw command or package version text and
returns only the normalized version component when one is present.

.PARAMETER VersionText
Raw version text reported by Codex or stored in package metadata.

.EXAMPLE
ConvertTo-CodexVersion -VersionText 'codex 1.2.3'

.NOTES
Returns $null when no supported semantic version can be detected.
#>
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    $match = [regex]::Match($VersionText, 'v?(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.\-]+)?)')
    if (-not $match.Success) {
        return $null
    }

    return $match.Groups[1].Value
}

function ConvertTo-CodexVersionObject {
<#
.SYNOPSIS
Converts Codex version text into a PowerShell version object.

.DESCRIPTION
Normalizes raw Codex version text and returns the comparable semantic version
portion as a System.Version instance for sorting and selection logic.

.PARAMETER VersionText
Raw version text reported by Codex or stored in package metadata.

.EXAMPLE
ConvertTo-CodexVersionObject -VersionText 'v1.2.3'

.NOTES
Returns $null when the version cannot be normalized to a comparable value.
#>
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    $normalizedVersion = ConvertTo-CodexVersion -VersionText $VersionText
    if ([string]::IsNullOrWhiteSpace($normalizedVersion)) {
        return $null
    }

    $match = [regex]::Match($normalizedVersion, '(\d+\.\d+\.\d+)')
    if (-not $match.Success) {
        return $null
    }

    return [version]$match.Groups[1].Value
}

function Get-CodexRuntimePackageJsonPath {
<#
.SYNOPSIS
Builds the package manifest path for a managed Codex runtime.

.DESCRIPTION
Returns the expected package.json path under a managed Codex runtime home so
callers can inspect the installed package metadata.

.PARAMETER RuntimeHome
Managed Codex runtime directory to inspect.

.EXAMPLE
Get-CodexRuntimePackageJsonPath -RuntimeHome 'C:\manifested\tools\codex\1.2.3'
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    return (Join-Path $RuntimeHome 'node_modules\@openai\codex\package.json')
}

function Get-CodexRuntimePackageVersion {
<#
.SYNOPSIS
Reads the installed Codex package version from package metadata.

.DESCRIPTION
Loads the package.json document for a managed Codex runtime and returns the
normalized package version when it can be read successfully.

.PARAMETER PackageJsonPath
Path to the Codex package.json file.

.EXAMPLE
Get-CodexRuntimePackageVersion -PackageJsonPath 'C:\manifested\tools\codex\1.2.3\node_modules\@openai\codex\package.json'

.NOTES
Returns $null when the package metadata is missing or unreadable.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageJsonPath
    )

    if (-not (Test-Path -LiteralPath $PackageJsonPath)) {
        return $null
    }

    try {
        $packageDocument = Get-Content -LiteralPath $PackageJsonPath -Raw -ErrorAction Stop | ConvertFrom-Json
        return (ConvertTo-CodexVersion -VersionText ([string]$packageDocument.version))
    }
    catch {
        return $null
    }
}

function Test-CodexRuntime {
<#
.SYNOPSIS
Validates a Codex runtime home.

.DESCRIPTION
Checks that the Codex executable and package metadata exist, compares the
reported command version to the installed package version, and returns a
normalized readiness result for the runtime directory.

.PARAMETER RuntimeHome
Runtime directory to validate.

.EXAMPLE
Test-CodexRuntime -RuntimeHome 'C:\manifested\tools\codex\1.2.3'
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    $codexCmd = Join-Path $RuntimeHome 'codex.cmd'
    $packageJsonPath = Get-CodexRuntimePackageJsonPath -RuntimeHome $RuntimeHome
    $packageVersion = $null
    $reportedVersion = $null

    if (-not (Test-Path -LiteralPath $RuntimeHome)) {
        $status = 'Missing'
    }
    elseif (-not (Test-Path -LiteralPath $codexCmd) -or -not (Test-Path -LiteralPath $packageJsonPath)) {
        $status = 'NeedsRepair'
    }
    else {
        $packageVersion = Get-CodexRuntimePackageVersion -PackageJsonPath $packageJsonPath

        try {
            $reportedVersion = (& $codexCmd --version 2>$null | Select-Object -First 1)
            if ($reportedVersion) {
                $reportedVersion = (ConvertTo-CodexVersion -VersionText $reportedVersion.ToString().Trim())
            }
        }
        catch {
            $reportedVersion = $null
        }

        if ([string]::IsNullOrWhiteSpace($packageVersion) -or [string]::IsNullOrWhiteSpace($reportedVersion)) {
            $status = 'NeedsRepair'
        }
        elseif ($packageVersion -ne $reportedVersion) {
            $status = 'NeedsRepair'
        }
        else {
            $status = 'Ready'
        }
    }

    [pscustomobject]@{
        Status          = $status
        IsReady         = ($status -eq 'Ready')
        RuntimeHome     = $RuntimeHome
        CodexCmd        = $codexCmd
        PackageJsonPath = $packageJsonPath
        PackageVersion  = $packageVersion
        ReportedVersion = $reportedVersion
    }
}

function Get-InstalledCodexRuntime {
<#
.SYNOPSIS
Enumerates managed Codex runtimes in the sandbox.

.DESCRIPTION
Scans the managed Codex tools root, validates discovered runtime directories,
and returns the current ready runtime together with valid and invalid entries.

.PARAMETER LocalRoot
Overrides the manifested sandbox local root to inspect.

.EXAMPLE
Get-InstalledCodexRuntime
#>
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $entries = @()

    if (Test-Path -LiteralPath $layout.CodexToolsRoot) {
        $runtimeRoots = Get-ChildItem -LiteralPath $layout.CodexToolsRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike '_stage_codex_*' } |
            Sort-Object -Descending -Property @{ Expression = { ConvertTo-CodexVersionObject -VersionText $_.Name } }, Name

        foreach ($runtimeRoot in $runtimeRoots) {
            $validation = Test-CodexRuntime -RuntimeHome $runtimeRoot.FullName
            $expectedVersion = ConvertTo-CodexVersion -VersionText $runtimeRoot.Name
            $runtimeVersion = if ($validation.PackageVersion) { $validation.PackageVersion } else { $expectedVersion }
            $versionMatches = (-not $expectedVersion) -or (-not $validation.PackageVersion) -or ($expectedVersion -eq $validation.PackageVersion)

            $entries += [pscustomobject]@{
                Version         = $runtimeVersion
                RuntimeHome     = $runtimeRoot.FullName
                CodexCmd        = $validation.CodexCmd
                PackageJsonPath = $validation.PackageJsonPath
                Validation      = $validation
                VersionMatches  = $versionMatches
                IsReady         = ($validation.IsReady -and $versionMatches)
                Source          = 'Managed'
            }
        }
    }

    [pscustomobject]@{
        Current = ($entries | Where-Object { $_.IsReady } | Select-Object -First 1)
        Valid   = @($entries | Where-Object { $_.IsReady })
        Invalid = @($entries | Where-Object { -not $_.IsReady })
    }
}

function Get-ManifestedCodexRuntimeFromCandidatePath {
<#
.SYNOPSIS
Builds Codex runtime metadata from a discovered executable path.

.DESCRIPTION
Resolves an external Codex executable candidate, validates the surrounding
runtime layout, and returns normalized runtime metadata when the candidate is
usable.

.PARAMETER CandidatePath
Potential path to a Codex executable discovered from the command environment.

.EXAMPLE
Get-ManifestedCodexRuntimeFromCandidatePath -CandidatePath 'C:\tools\codex\codex.cmd'

.NOTES
Returns $null when the candidate does not resolve to a ready Codex runtime.
#>
    [CmdletBinding()]
    param(
        [string]$CandidatePath
    )

    $resolvedCandidatePath = Get-ManifestedFullPath -Path $CandidatePath
    if ([string]::IsNullOrWhiteSpace($resolvedCandidatePath) -or -not (Test-Path -LiteralPath $resolvedCandidatePath)) {
        return $null
    }

    $leafName = Split-Path -Leaf $resolvedCandidatePath
    if ($leafName -ine 'codex.cmd' -and $leafName -ine 'codex') {
        return $null
    }

    $runtimeHome = Split-Path -Parent $resolvedCandidatePath
    $validation = Test-CodexRuntime -RuntimeHome $runtimeHome
    if (-not $validation.IsReady) {
        return $null
    }

    [pscustomobject]@{
        Version         = $validation.PackageVersion
        RuntimeHome     = $runtimeHome
        CodexCmd        = $validation.CodexCmd
        PackageJsonPath = $validation.PackageJsonPath
        Validation      = $validation
        IsReady         = $true
        Source          = 'External'
        Discovery       = 'Path'
    }
}

function Get-SystemCodexRuntime {
<#
.SYNOPSIS
Finds a usable external Codex runtime on the system path.

.DESCRIPTION
Searches for Codex executables outside the managed tools root and returns the
first validated external runtime that can be used by the sandbox.

.PARAMETER LocalRoot
Overrides the manifested sandbox local root so managed paths can be excluded.

.EXAMPLE
Get-SystemCodexRuntime
#>
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $candidatePaths = New-Object System.Collections.Generic.List[string]

    $codexCmdPath = Get-ManifestedApplicationPath -CommandName 'codex.cmd' -ExcludedRoots @($layout.CodexToolsRoot)
    if (-not [string]::IsNullOrWhiteSpace($codexCmdPath)) {
        $candidatePaths.Add($codexCmdPath) | Out-Null
    }

    $codexPath = Get-ManifestedApplicationPath -CommandName 'codex' -ExcludedRoots @($layout.CodexToolsRoot)
    if (-not [string]::IsNullOrWhiteSpace($codexPath)) {
        $candidatePaths.Add($codexPath) | Out-Null
    }

    foreach ($candidatePath in @($candidatePaths | Select-Object -Unique)) {
        $runtime = Get-ManifestedCodexRuntimeFromCandidatePath -CandidatePath $candidatePath
        if ($runtime) {
            return $runtime
        }
    }

    return $null
}

function Get-CodexRuntimeState {
<#
.SYNOPSIS
Gets the current Codex runtime state for the manifested sandbox.

.DESCRIPTION
Inspects managed and externally discovered Codex installations, staged directories,
and repair indicators to build the normalized runtime state used by bootstrap flows.

.PARAMETER LocalRoot
Overrides the manifested sandbox local root to inspect.

.EXAMPLE
Get-CodexRuntimeState

.EXAMPLE
Get-CodexRuntimeState -LocalRoot 'C:\manifested'

.NOTES
Returns a Blocked state on non-Windows hosts.
#>
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return [pscustomobject]@{
            Status              = 'Blocked'
            LocalRoot           = $LocalRoot
            Layout              = $null
            CurrentVersion      = $null
            RuntimeHome         = $null
            RuntimeSource       = $null
            ExecutablePath      = $null
            Runtime             = $null
            InvalidRuntimeHomes = @()
            PartialPaths        = @()
            BlockedReason       = 'Only Windows hosts are supported by this Codex runtime bootstrap.'
            PackageJsonPath     = $null
        }
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $partialPaths = @()
    $partialPaths += @(Get-ManifestedStageDirectories -Prefix 'codex' -Mode TemporaryShort -LegacyRootPaths @($layout.CodexToolsRoot) | Select-Object -ExpandProperty FullName)

    $installed = Get-InstalledCodexRuntime -LocalRoot $layout.LocalRoot
    $managedRuntime = $installed.Current
    $externalRuntime = $null
    if (-not $managedRuntime) {
        $externalRuntime = Get-SystemCodexRuntime -LocalRoot $layout.LocalRoot
    }

    $currentRuntime = if ($managedRuntime) { $managedRuntime } else { $externalRuntime }
    $runtimeSource = if ($managedRuntime) { 'Managed' } elseif ($externalRuntime) { 'External' } else { $null }
    $invalidRuntimeHomes = @($installed.Invalid | Select-Object -ExpandProperty RuntimeHome)

    if ($invalidRuntimeHomes.Count -gt 0) {
        $status = 'NeedsRepair'
    }
    elseif ($partialPaths.Count -gt 0) {
        $status = 'Partial'
    }
    elseif ($currentRuntime) {
        $status = 'Ready'
    }
    else {
        $status = 'Missing'
    }

    [pscustomobject]@{
        Status              = $status
        LocalRoot           = $layout.LocalRoot
        Layout              = $layout
        CurrentVersion      = if ($currentRuntime) { $currentRuntime.Version } else { $null }
        RuntimeHome         = if ($currentRuntime) { $currentRuntime.RuntimeHome } else { $null }
        RuntimeSource       = $runtimeSource
        ExecutablePath      = if ($currentRuntime) { $currentRuntime.CodexCmd } else { $null }
        Runtime             = if ($currentRuntime) { $currentRuntime.Validation } else { $null }
        InvalidRuntimeHomes = $invalidRuntimeHomes
        PartialPaths        = $partialPaths
        BlockedReason       = $null
        PackageJsonPath     = if ($currentRuntime) { $currentRuntime.PackageJsonPath } else { $null }
    }
}

function Repair-CodexRuntime {
<#
.SYNOPSIS
Removes partial or invalid Codex runtime artifacts.

.DESCRIPTION
Collects partial stage directories, invalid managed runtime homes, and
optionally supplied corrupt runtime paths, then removes them to clear the way
for a clean reinstall.

.PARAMETER State
Existing Codex runtime state to repair. When omitted, the state is discovered.

.PARAMETER CorruptRuntimeHomes
Additional runtime paths to remove during repair.

.PARAMETER LocalRoot
Overrides the manifested sandbox local root used for state discovery.

.EXAMPLE
Repair-CodexRuntime -State (Get-CodexRuntimeState)
#>
    [CmdletBinding()]
    param(
        [pscustomobject]$State,
        [string[]]$CorruptRuntimeHomes = @(),
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $State) {
        $State = Get-CodexRuntimeState -LocalRoot $LocalRoot
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
    foreach ($path in @($CorruptRuntimeHomes)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $pathsToRemove.Add($path) | Out-Null
        }
    }

    $removedPaths = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($pathsToRemove | Select-Object -Unique)) {
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

function Install-CodexRuntime {
<#
.SYNOPSIS
Installs the managed Codex runtime into the manifested sandbox.

.DESCRIPTION
Creates the cache and tools directories, performs a staged npm-based installation
of the Codex CLI, validates the staged runtime, and promotes it into the managed
tools root as a versioned runtime directory.

.PARAMETER NpmCmd
Path to the npm executable used to install the Codex package.

.PARAMETER LocalRoot
Overrides the manifested sandbox local root that receives the managed runtime.

.EXAMPLE
Install-CodexRuntime -NpmCmd 'C:\tools\node\npm.cmd'

.EXAMPLE
Install-CodexRuntime -NpmCmd 'C:\tools\node\npm.cmd' -LocalRoot 'C:\manifested'

.NOTES
This function expects Node.js prerequisites to already be available.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NpmCmd,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    New-ManifestedDirectory -Path $layout.CodexCacheRoot | Out-Null
    New-ManifestedDirectory -Path $layout.CodexToolsRoot | Out-Null

    $stagePath = New-ManifestedStageDirectory -Prefix 'codex' -Mode TemporaryShort
    $npmConfiguration = Get-ManifestedManagedNpmCommandArguments -NpmCmd $NpmCmd -LocalRoot $LocalRoot
    $npmArguments = @('install', '-g', '--prefix', $stagePath, '--cache', $layout.CodexCacheRoot)
    $npmArguments += @($npmConfiguration.CommandArguments)
    $npmArguments += $script:ManifestedSandboxCodexPackage

    Write-Host 'Installing Codex CLI into managed sandbox tools...'
    & $NpmCmd @npmArguments
    if ($LASTEXITCODE -ne 0) {
        throw "npm install for Codex exited with code $LASTEXITCODE."
    }

    $stageValidation = Test-CodexRuntime -RuntimeHome $stagePath
    if (-not $stageValidation.IsReady) {
        throw "Codex runtime validation failed after staged install at $stagePath."
    }

    $version = if ($stageValidation.PackageVersion) { $stageValidation.PackageVersion } else { ConvertTo-CodexVersion -VersionText $stageValidation.ReportedVersion }
    if ([string]::IsNullOrWhiteSpace($version)) {
        throw "Could not determine the installed Codex version from $($stageValidation.PackageJsonPath)."
    }

    $runtimeHome = Join-Path $layout.CodexToolsRoot $version
    if (Test-Path -LiteralPath $runtimeHome) {
        Remove-ManifestedPath -Path $runtimeHome | Out-Null
    }

    Move-Item -LiteralPath $stagePath -Destination $runtimeHome -Force

    $validation = Test-CodexRuntime -RuntimeHome $runtimeHome
    if (-not $validation.IsReady) {
        throw "Codex runtime validation failed after install at $runtimeHome."
    }

    [pscustomobject]@{
        Action          = 'Installed'
        Version         = $validation.PackageVersion
        RuntimeHome     = $runtimeHome
        CodexCmd        = $validation.CodexCmd
        PackageJsonPath = $validation.PackageJsonPath
        Source          = 'Managed'
        CacheRoot       = $layout.CodexCacheRoot
        NpmCmd          = $NpmCmd
    }
}

function Initialize-CodexRuntime {
<#
.SYNOPSIS
Ensures the Codex runtime is available and ready for command-line use.

.DESCRIPTION
Evaluates the current Codex runtime state, repairs partial or invalid installs,
ensures required dependencies are present, installs the managed runtime when
needed, and synchronizes the command-line environment metadata.

.PARAMETER RefreshCodex
Forces the managed Codex runtime to be reinstalled even when one is already ready.

.EXAMPLE
Initialize-CodexRuntime

.EXAMPLE
Initialize-CodexRuntime -RefreshCodex

.NOTES
Supports WhatIf and may trigger dependent runtime initialization steps.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshCodex
    )

    return (Invoke-ManifestedNpmCliRuntimeInitialization -CommandName 'Initialize-CodexRuntime' -Refresh:$RefreshCodex)
}
