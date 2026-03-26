<#
    Eigenverft.Manifested.Sandbox.Cmd.QwenRuntimeAndCache
#>

$script:ManifestedSandboxQwenPackage = '@qwen-code/qwen-code@latest'

function ConvertTo-QwenVersion {
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

function ConvertTo-QwenVersionObject {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    $normalizedVersion = ConvertTo-QwenVersion -VersionText $VersionText
    if ([string]::IsNullOrWhiteSpace($normalizedVersion)) {
        return $null
    }

    $match = [regex]::Match($normalizedVersion, '(\d+\.\d+\.\d+)')
    if (-not $match.Success) {
        return $null
    }

    return [version]$match.Groups[1].Value
}

function Get-QwenRequiredNodeVersion {
    [CmdletBinding()]
    param()

    return [version]'20.0.0'
}

function Test-QwenNodeRuntime {
    [CmdletBinding()]
    param(
        [pscustomobject]$NodeState
    )

    $requiredVersion = Get-QwenRequiredNodeVersion
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
        RequiredVersion   = ('v' + $requiredVersion.ToString())
        CurrentVersion    = if ($currentVersion) { ('v' + $currentVersion.ToString()) } else { $null }
        IsReady           = [bool]$isReady
        HasCompatibleNode = [bool]$hasCompatibleNode
        HasUsableNpm      = [bool]$hasUsableNpm
        IsCompatible      = [bool]($isReady -and $hasCompatibleNode -and $hasUsableNpm)
        NeedsRefresh      = [bool]$needsRefresh
        NpmCmd            = $npmCmd
    }
}

function Get-QwenRuntimePackageJsonPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    return (Join-Path $RuntimeHome 'node_modules\@qwen-code\qwen-code\package.json')
}

function Get-QwenRuntimePackageVersion {
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
        return (ConvertTo-QwenVersion -VersionText ([string]$packageDocument.version))
    }
    catch {
        return $null
    }
}

function Test-QwenRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    $qwenCmd = Join-Path $RuntimeHome 'qwen.cmd'
    $packageJsonPath = Get-QwenRuntimePackageJsonPath -RuntimeHome $RuntimeHome
    $packageVersion = $null
    $reportedVersion = $null

    if (-not (Test-Path -LiteralPath $RuntimeHome)) {
        $status = 'Missing'
    }
    elseif (-not (Test-Path -LiteralPath $qwenCmd) -or -not (Test-Path -LiteralPath $packageJsonPath)) {
        $status = 'NeedsRepair'
    }
    else {
        $packageVersion = Get-QwenRuntimePackageVersion -PackageJsonPath $packageJsonPath

        try {
            $reportedVersion = (& $qwenCmd --version 2>$null | Select-Object -First 1)
            if ($reportedVersion) {
                $reportedVersion = (ConvertTo-QwenVersion -VersionText $reportedVersion.ToString().Trim())
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
        QwenCmd         = $qwenCmd
        PackageJsonPath = $packageJsonPath
        PackageVersion  = $packageVersion
        ReportedVersion = $reportedVersion
    }
}

function Get-InstalledQwenRuntime {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $entries = @()

    if (Test-Path -LiteralPath $layout.QwenToolsRoot) {
        $runtimeRoots = Get-ChildItem -LiteralPath $layout.QwenToolsRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike '_stage_qwen_*' } |
            Sort-Object -Descending -Property @{ Expression = { ConvertTo-QwenVersionObject -VersionText $_.Name } }, Name

        foreach ($runtimeRoot in $runtimeRoots) {
            $validation = Test-QwenRuntime -RuntimeHome $runtimeRoot.FullName
            $expectedVersion = ConvertTo-QwenVersion -VersionText $runtimeRoot.Name
            $runtimeVersion = if ($validation.PackageVersion) { $validation.PackageVersion } else { $expectedVersion }
            $versionMatches = (-not $expectedVersion) -or (-not $validation.PackageVersion) -or ($expectedVersion -eq $validation.PackageVersion)

            $entries += [pscustomobject]@{
                Version         = $runtimeVersion
                RuntimeHome     = $runtimeRoot.FullName
                QwenCmd         = $validation.QwenCmd
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

function Get-ManifestedQwenRuntimeFromCandidatePath {
    [CmdletBinding()]
    param(
        [string]$CandidatePath
    )

    $resolvedCandidatePath = Get-ManifestedFullPath -Path $CandidatePath
    if ([string]::IsNullOrWhiteSpace($resolvedCandidatePath) -or -not (Test-Path -LiteralPath $resolvedCandidatePath)) {
        return $null
    }

    $leafName = Split-Path -Leaf $resolvedCandidatePath
    if ($leafName -ine 'qwen.cmd' -and $leafName -ine 'qwen') {
        return $null
    }

    $runtimeHome = Split-Path -Parent $resolvedCandidatePath
    $validation = Test-QwenRuntime -RuntimeHome $runtimeHome
    if (-not $validation.IsReady) {
        return $null
    }

    [pscustomobject]@{
        Version         = $validation.PackageVersion
        RuntimeHome     = $runtimeHome
        QwenCmd         = $validation.QwenCmd
        PackageJsonPath = $validation.PackageJsonPath
        Validation      = $validation
        IsReady         = $true
        Source          = 'External'
        Discovery       = 'Path'
    }
}

function Get-SystemQwenRuntime {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $candidatePaths = New-Object System.Collections.Generic.List[string]

    $qwenCmdPath = Get-ManifestedApplicationPath -CommandName 'qwen.cmd' -ExcludedRoots @($layout.QwenToolsRoot)
    if (-not [string]::IsNullOrWhiteSpace($qwenCmdPath)) {
        $candidatePaths.Add($qwenCmdPath) | Out-Null
    }

    $qwenPath = Get-ManifestedApplicationPath -CommandName 'qwen' -ExcludedRoots @($layout.QwenToolsRoot)
    if (-not [string]::IsNullOrWhiteSpace($qwenPath)) {
        $candidatePaths.Add($qwenPath) | Out-Null
    }

    foreach ($candidatePath in @($candidatePaths | Select-Object -Unique)) {
        $runtime = Get-ManifestedQwenRuntimeFromCandidatePath -CandidatePath $candidatePath
        if ($runtime) {
            return $runtime
        }
    }

    return $null
}

function Get-QwenRuntimeState {
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
            BlockedReason       = 'Only Windows hosts are supported by this Qwen runtime bootstrap.'
            PackageJsonPath     = $null
        }
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $partialPaths = @()
    $partialPaths += @(Get-ManifestedStageDirectories -Prefix 'qwen' -Mode TemporaryShort -LegacyRootPaths @($layout.QwenToolsRoot) | Select-Object -ExpandProperty FullName)

    $installed = Get-InstalledQwenRuntime -LocalRoot $layout.LocalRoot
    $managedRuntime = $installed.Current
    $externalRuntime = $null
    if (-not $managedRuntime) {
        $externalRuntime = Get-SystemQwenRuntime -LocalRoot $layout.LocalRoot
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
        ExecutablePath      = if ($currentRuntime) { $currentRuntime.QwenCmd } else { $null }
        Runtime             = if ($currentRuntime) { $currentRuntime.Validation } else { $null }
        InvalidRuntimeHomes = $invalidRuntimeHomes
        PartialPaths        = $partialPaths
        BlockedReason       = $null
        PackageJsonPath     = if ($currentRuntime) { $currentRuntime.PackageJsonPath } else { $null }
    }
}

function Repair-QwenRuntime {
    [CmdletBinding()]
    param(
        [pscustomobject]$State,
        [string[]]$CorruptRuntimeHomes = @(),
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $State) {
        $State = Get-QwenRuntimeState -LocalRoot $LocalRoot
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

function Install-QwenRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NpmCmd,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    New-ManifestedDirectory -Path $layout.QwenCacheRoot | Out-Null
    New-ManifestedDirectory -Path $layout.QwenToolsRoot | Out-Null

    $stagePath = New-ManifestedStageDirectory -Prefix 'qwen' -Mode TemporaryShort
    $npmConfiguration = Get-ManifestedManagedNpmCommandArguments -NpmCmd $NpmCmd -LocalRoot $LocalRoot
    $npmArguments = @('install', '-g', '--prefix', $stagePath, '--cache', $layout.QwenCacheRoot)
    $npmArguments += @($npmConfiguration.CommandArguments)
    $npmArguments += $script:ManifestedSandboxQwenPackage

    Write-Host 'Installing Qwen CLI into managed sandbox tools...'
    & $NpmCmd @npmArguments
    if ($LASTEXITCODE -ne 0) {
        throw "npm install for Qwen exited with code $LASTEXITCODE."
    }

    $stageValidation = Test-QwenRuntime -RuntimeHome $stagePath
    if (-not $stageValidation.IsReady) {
        throw "Qwen runtime validation failed after staged install at $stagePath."
    }

    $version = if ($stageValidation.PackageVersion) { $stageValidation.PackageVersion } else { ConvertTo-QwenVersion -VersionText $stageValidation.ReportedVersion }
    if ([string]::IsNullOrWhiteSpace($version)) {
        throw "Could not determine the installed Qwen version from $($stageValidation.PackageJsonPath)."
    }

    $runtimeHome = Join-Path $layout.QwenToolsRoot $version
    if (Test-Path -LiteralPath $runtimeHome) {
        Remove-ManifestedPath -Path $runtimeHome | Out-Null
    }

    Move-Item -LiteralPath $stagePath -Destination $runtimeHome -Force

    $validation = Test-QwenRuntime -RuntimeHome $runtimeHome
    if (-not $validation.IsReady) {
        throw "Qwen runtime validation failed after install at $runtimeHome."
    }

    [pscustomobject]@{
        Action          = 'Installed'
        Version         = $validation.PackageVersion
        RuntimeHome     = $runtimeHome
        QwenCmd         = $validation.QwenCmd
        PackageJsonPath = $validation.PackageJsonPath
        Source          = 'Managed'
        CacheRoot       = $layout.QwenCacheRoot
        NpmCmd          = $NpmCmd
    }
}
