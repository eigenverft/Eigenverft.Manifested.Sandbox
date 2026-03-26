<#
    Eigenverft.Manifested.Sandbox.Cmd.GeminiRuntimeAndCache
#>

$script:ManifestedSandboxGeminiPackage = '@google/gemini-cli@latest'

function ConvertTo-GeminiVersion {
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

function ConvertTo-GeminiVersionObject {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    $normalizedVersion = ConvertTo-GeminiVersion -VersionText $VersionText
    if ([string]::IsNullOrWhiteSpace($normalizedVersion)) {
        return $null
    }

    $match = [regex]::Match($normalizedVersion, '(\d+\.\d+\.\d+)')
    if (-not $match.Success) {
        return $null
    }

    return [version]$match.Groups[1].Value
}

function Get-GeminiRequiredNodeVersion {
    [CmdletBinding()]
    param()

    return [version]'20.0.0'
}

function Test-GeminiNodeRuntime {
    [CmdletBinding()]
    param(
        [pscustomobject]$NodeState
    )

    $requiredVersion = Get-GeminiRequiredNodeVersion
    $currentVersion = $null
    if ($NodeState -and $NodeState.PSObject.Properties['CurrentVersion']) {
        $currentVersion = ConvertTo-NodeVersion -VersionText $NodeState.CurrentVersion
    }

    $npmCmd = $null
    if ($NodeState -and $NodeState.PSObject.Properties['Runtime'] -and $NodeState.Runtime -and $NodeState.Runtime.PSObject.Properties['NpmCmd']) {
        $npmCmd = $NodeState.Runtime.NpmCmd
    }
    if ([string]::IsNullOrWhiteSpace($npmCmd) -and $NodeState -and $NodeState.PSObject.Properties['RuntimeHome'] -and -not [string]::IsNullOrWhiteSpace($NodeState.RuntimeHome)) {
        $candidateNpmCmd = Join-Path $NodeState.RuntimeHome 'npm.cmd'
        if (Test-Path -LiteralPath $candidateNpmCmd) {
            $npmCmd = $candidateNpmCmd
        }
    }

    $isReady = ($NodeState -and $NodeState.PSObject.Properties['Status'] -and ($NodeState.Status -eq 'Ready'))
    $hasCompatibleNode = ($currentVersion -and ($currentVersion -ge $requiredVersion))
    $hasUsableNpm = (-not [string]::IsNullOrWhiteSpace($npmCmd)) -and (Test-Path -LiteralPath $npmCmd)
    $needsRefresh = $isReady -and (-not $hasCompatibleNode)

    [pscustomobject]@{
        RequiredVersion = ('v' + $requiredVersion.ToString())
        CurrentVersion  = if ($currentVersion) { ('v' + $currentVersion.ToString()) } else { $null }
        IsReady         = [bool]$isReady
        HasCompatibleNode = [bool]$hasCompatibleNode
        HasUsableNpm    = [bool]$hasUsableNpm
        IsCompatible    = [bool]($isReady -and $hasCompatibleNode -and $hasUsableNpm)
        NeedsRefresh    = [bool]$needsRefresh
        NpmCmd          = $npmCmd
    }
}

function Get-GeminiRuntimePackageJsonPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    return (Join-Path $RuntimeHome 'node_modules\@google\gemini-cli\package.json')
}

function Get-GeminiRuntimePackageVersion {
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
        return (ConvertTo-GeminiVersion -VersionText ([string]$packageDocument.version))
    }
    catch {
        return $null
    }
}

function Test-GeminiRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    $geminiCmd = Join-Path $RuntimeHome 'gemini.cmd'
    $packageJsonPath = Get-GeminiRuntimePackageJsonPath -RuntimeHome $RuntimeHome
    $packageVersion = $null
    $reportedVersion = $null

    if (-not (Test-Path -LiteralPath $RuntimeHome)) {
        $status = 'Missing'
    }
    elseif (-not (Test-Path -LiteralPath $geminiCmd) -or -not (Test-Path -LiteralPath $packageJsonPath)) {
        $status = 'NeedsRepair'
    }
    else {
        $packageVersion = Get-GeminiRuntimePackageVersion -PackageJsonPath $packageJsonPath

        try {
            $reportedVersion = (& $geminiCmd --version 2>$null | Select-Object -First 1)
            if ($reportedVersion) {
                $reportedVersion = (ConvertTo-GeminiVersion -VersionText $reportedVersion.ToString().Trim())
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
        GeminiCmd       = $geminiCmd
        PackageJsonPath = $packageJsonPath
        PackageVersion  = $packageVersion
        ReportedVersion = $reportedVersion
    }
}

function Get-InstalledGeminiRuntime {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $entries = @()

    if (Test-Path -LiteralPath $layout.GeminiToolsRoot) {
        $runtimeRoots = Get-ChildItem -LiteralPath $layout.GeminiToolsRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike '_stage_gemini_*' } |
            Sort-Object -Descending -Property @{ Expression = { ConvertTo-GeminiVersionObject -VersionText $_.Name } }, Name

        foreach ($runtimeRoot in $runtimeRoots) {
            $validation = Test-GeminiRuntime -RuntimeHome $runtimeRoot.FullName
            $expectedVersion = ConvertTo-GeminiVersion -VersionText $runtimeRoot.Name
            $runtimeVersion = if ($validation.PackageVersion) { $validation.PackageVersion } else { $expectedVersion }
            $versionMatches = (-not $expectedVersion) -or (-not $validation.PackageVersion) -or ($expectedVersion -eq $validation.PackageVersion)

            $entries += [pscustomobject]@{
                Version         = $runtimeVersion
                RuntimeHome     = $runtimeRoot.FullName
                GeminiCmd       = $validation.GeminiCmd
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

function Get-ManifestedGeminiRuntimeFromCandidatePath {
    [CmdletBinding()]
    param(
        [string]$CandidatePath
    )

    $resolvedCandidatePath = Get-ManifestedFullPath -Path $CandidatePath
    if ([string]::IsNullOrWhiteSpace($resolvedCandidatePath) -or -not (Test-Path -LiteralPath $resolvedCandidatePath)) {
        return $null
    }

    $leafName = Split-Path -Leaf $resolvedCandidatePath
    if ($leafName -ine 'gemini.cmd' -and $leafName -ine 'gemini') {
        return $null
    }

    $runtimeHome = Split-Path -Parent $resolvedCandidatePath
    $validation = Test-GeminiRuntime -RuntimeHome $runtimeHome
    if (-not $validation.IsReady) {
        return $null
    }

    [pscustomobject]@{
        Version         = $validation.PackageVersion
        RuntimeHome     = $runtimeHome
        GeminiCmd       = $validation.GeminiCmd
        PackageJsonPath = $validation.PackageJsonPath
        Validation      = $validation
        IsReady         = $true
        Source          = 'External'
        Discovery       = 'Path'
    }
}

function Get-SystemGeminiRuntime {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $candidatePaths = New-Object System.Collections.Generic.List[string]

    $geminiCmdPath = Get-ManifestedApplicationPath -CommandName 'gemini.cmd' -ExcludedRoots @($layout.GeminiToolsRoot)
    if (-not [string]::IsNullOrWhiteSpace($geminiCmdPath)) {
        $candidatePaths.Add($geminiCmdPath) | Out-Null
    }

    $geminiPath = Get-ManifestedApplicationPath -CommandName 'gemini' -ExcludedRoots @($layout.GeminiToolsRoot)
    if (-not [string]::IsNullOrWhiteSpace($geminiPath)) {
        $candidatePaths.Add($geminiPath) | Out-Null
    }

    foreach ($candidatePath in @($candidatePaths | Select-Object -Unique)) {
        $runtime = Get-ManifestedGeminiRuntimeFromCandidatePath -CandidatePath $candidatePath
        if ($runtime) {
            return $runtime
        }
    }

    return $null
}

function Get-GeminiRuntimeState {
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
            BlockedReason       = 'Only Windows hosts are supported by this Gemini runtime bootstrap.'
            PackageJsonPath     = $null
        }
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $partialPaths = @()
    $partialPaths += @(Get-ManifestedStageDirectories -Prefix 'gemini' -Mode TemporaryShort -LegacyRootPaths @($layout.GeminiToolsRoot) | Select-Object -ExpandProperty FullName)

    $installed = Get-InstalledGeminiRuntime -LocalRoot $layout.LocalRoot
    $managedRuntime = $installed.Current
    $externalRuntime = $null
    if (-not $managedRuntime) {
        $externalRuntime = Get-SystemGeminiRuntime -LocalRoot $layout.LocalRoot
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
        ExecutablePath      = if ($currentRuntime) { $currentRuntime.GeminiCmd } else { $null }
        Runtime             = if ($currentRuntime) { $currentRuntime.Validation } else { $null }
        InvalidRuntimeHomes = $invalidRuntimeHomes
        PartialPaths        = $partialPaths
        BlockedReason       = $null
        PackageJsonPath     = if ($currentRuntime) { $currentRuntime.PackageJsonPath } else { $null }
    }
}

function Repair-GeminiRuntime {
    [CmdletBinding()]
    param(
        [pscustomobject]$State,
        [string[]]$CorruptRuntimeHomes = @(),
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $State) {
        $State = Get-GeminiRuntimeState -LocalRoot $LocalRoot
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

function Install-GeminiRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NpmCmd,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    New-ManifestedDirectory -Path $layout.GeminiCacheRoot | Out-Null
    New-ManifestedDirectory -Path $layout.GeminiToolsRoot | Out-Null

    $stagePath = New-ManifestedStageDirectory -Prefix 'gemini' -Mode TemporaryShort
    $npmConfiguration = Get-ManifestedManagedNpmCommandArguments -NpmCmd $NpmCmd -LocalRoot $LocalRoot
    $npmArguments = @('install', '-g', '--prefix', $stagePath, '--cache', $layout.GeminiCacheRoot)
    $npmArguments += @($npmConfiguration.CommandArguments)
    $npmArguments += $script:ManifestedSandboxGeminiPackage

    Write-Host 'Installing Gemini CLI into managed sandbox tools...'
    & $NpmCmd @npmArguments
    if ($LASTEXITCODE -ne 0) {
        throw "npm install for Gemini exited with code $LASTEXITCODE."
    }

    $stageValidation = Test-GeminiRuntime -RuntimeHome $stagePath
    if (-not $stageValidation.IsReady) {
        throw "Gemini runtime validation failed after staged install at $stagePath."
    }

    $version = if ($stageValidation.PackageVersion) { $stageValidation.PackageVersion } else { ConvertTo-GeminiVersion -VersionText $stageValidation.ReportedVersion }
    if ([string]::IsNullOrWhiteSpace($version)) {
        throw "Could not determine the installed Gemini version from $($stageValidation.PackageJsonPath)."
    }

    $runtimeHome = Join-Path $layout.GeminiToolsRoot $version
    if (Test-Path -LiteralPath $runtimeHome) {
        Remove-ManifestedPath -Path $runtimeHome | Out-Null
    }

    Move-Item -LiteralPath $stagePath -Destination $runtimeHome -Force

    $validation = Test-GeminiRuntime -RuntimeHome $runtimeHome
    if (-not $validation.IsReady) {
        throw "Gemini runtime validation failed after install at $runtimeHome."
    }

    [pscustomobject]@{
        Action          = 'Installed'
        Version         = $validation.PackageVersion
        RuntimeHome     = $runtimeHome
        GeminiCmd       = $validation.GeminiCmd
        PackageJsonPath = $validation.PackageJsonPath
        Source          = 'Managed'
        CacheRoot       = $layout.GeminiCacheRoot
        NpmCmd          = $NpmCmd
    }
}


