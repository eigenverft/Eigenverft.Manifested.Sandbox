<#
    Eigenverft.Manifested.Sandbox.Cmd.OpenCodeRuntimeAndCache
#>

$script:ManifestedSandboxOpenCodePackage = 'opencode-ai@latest'

function ConvertTo-OpenCodeVersion {
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

function ConvertTo-OpenCodeVersionObject {
    [CmdletBinding()]
    param(
        [string]$VersionText
    )

    $normalizedVersion = ConvertTo-OpenCodeVersion -VersionText $VersionText
    if ([string]::IsNullOrWhiteSpace($normalizedVersion)) {
        return $null
    }

    $match = [regex]::Match($normalizedVersion, '(\d+\.\d+\.\d+)')
    if (-not $match.Success) {
        return $null
    }

    return [version]$match.Groups[1].Value
}

function Get-OpenCodeRuntimePackageJsonPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    return (Join-Path $RuntimeHome 'node_modules\opencode-ai\package.json')
}

function Get-OpenCodeRuntimePackageVersion {
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
        return (ConvertTo-OpenCodeVersion -VersionText ([string]$packageDocument.version))
    }
    catch {
        return $null
    }
}

function Test-OpenCodeRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    $openCodeCmd = Join-Path $RuntimeHome 'opencode.cmd'
    $packageJsonPath = Get-OpenCodeRuntimePackageJsonPath -RuntimeHome $RuntimeHome
    $packageVersion = $null
    $reportedVersion = $null

    if (-not (Test-Path -LiteralPath $RuntimeHome)) {
        $status = 'Missing'
    }
    elseif (-not (Test-Path -LiteralPath $openCodeCmd) -or -not (Test-Path -LiteralPath $packageJsonPath)) {
        $status = 'NeedsRepair'
    }
    else {
        $packageVersion = Get-OpenCodeRuntimePackageVersion -PackageJsonPath $packageJsonPath

        try {
            $reportedVersion = (& $openCodeCmd --version 2>$null | Select-Object -First 1)
            if ($reportedVersion) {
                $reportedVersion = (ConvertTo-OpenCodeVersion -VersionText $reportedVersion.ToString().Trim())
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
        OpenCodeCmd     = $openCodeCmd
        PackageJsonPath = $packageJsonPath
        PackageVersion  = $packageVersion
        ReportedVersion = $reportedVersion
    }
}

function Get-InstalledOpenCodeRuntime {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $entries = @()

    if (Test-Path -LiteralPath $layout.OpenCodeToolsRoot) {
        $runtimeRoots = Get-ChildItem -LiteralPath $layout.OpenCodeToolsRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike '_stage_opencode_*' } |
            Sort-Object -Descending -Property @{ Expression = { ConvertTo-OpenCodeVersionObject -VersionText $_.Name } }, Name

        foreach ($runtimeRoot in $runtimeRoots) {
            $validation = Test-OpenCodeRuntime -RuntimeHome $runtimeRoot.FullName
            $expectedVersion = ConvertTo-OpenCodeVersion -VersionText $runtimeRoot.Name
            $runtimeVersion = if ($validation.PackageVersion) { $validation.PackageVersion } else { $expectedVersion }
            $versionMatches = (-not $expectedVersion) -or (-not $validation.PackageVersion) -or ($expectedVersion -eq $validation.PackageVersion)

            $entries += [pscustomobject]@{
                Version         = $runtimeVersion
                RuntimeHome     = $runtimeRoot.FullName
                OpenCodeCmd     = $validation.OpenCodeCmd
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

function Get-ManifestedOpenCodeRuntimeFromCandidatePath {
    [CmdletBinding()]
    param(
        [string]$CandidatePath
    )

    $resolvedCandidatePath = Get-ManifestedFullPath -Path $CandidatePath
    if ([string]::IsNullOrWhiteSpace($resolvedCandidatePath) -or -not (Test-Path -LiteralPath $resolvedCandidatePath)) {
        return $null
    }

    $leafName = Split-Path -Leaf $resolvedCandidatePath
    if ($leafName -ine 'opencode.cmd' -and $leafName -ine 'opencode') {
        return $null
    }

    $runtimeHome = Split-Path -Parent $resolvedCandidatePath
    $validation = Test-OpenCodeRuntime -RuntimeHome $runtimeHome
    if (-not $validation.IsReady) {
        return $null
    }

    [pscustomobject]@{
        Version         = $validation.PackageVersion
        RuntimeHome     = $runtimeHome
        OpenCodeCmd     = $validation.OpenCodeCmd
        PackageJsonPath = $validation.PackageJsonPath
        Validation      = $validation
        IsReady         = $true
        Source          = 'External'
        Discovery       = 'Path'
    }
}

function Get-SystemOpenCodeRuntime {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $candidatePaths = New-Object System.Collections.Generic.List[string]

    $openCodeCmdPath = Get-ManifestedApplicationPath -CommandName 'opencode.cmd' -ExcludedRoots @($layout.OpenCodeToolsRoot)
    if (-not [string]::IsNullOrWhiteSpace($openCodeCmdPath)) {
        $candidatePaths.Add($openCodeCmdPath) | Out-Null
    }

    $openCodePath = Get-ManifestedApplicationPath -CommandName 'opencode' -ExcludedRoots @($layout.OpenCodeToolsRoot)
    if (-not [string]::IsNullOrWhiteSpace($openCodePath)) {
        $candidatePaths.Add($openCodePath) | Out-Null
    }

    foreach ($candidatePath in @($candidatePaths | Select-Object -Unique)) {
        $runtime = Get-ManifestedOpenCodeRuntimeFromCandidatePath -CandidatePath $candidatePath
        if ($runtime) {
            return $runtime
        }
    }

    return $null
}

function Get-OpenCodeRuntimeState {
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
            BlockedReason       = 'Only Windows hosts are supported by this OpenCode runtime bootstrap.'
            PackageJsonPath     = $null
        }
    }

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $partialPaths = @()
    $partialPaths += @(Get-ManifestedStageDirectories -Prefix 'opencode' -Mode TemporaryShort -LegacyRootPaths @($layout.OpenCodeToolsRoot) | Select-Object -ExpandProperty FullName)

    $installed = Get-InstalledOpenCodeRuntime -LocalRoot $layout.LocalRoot
    $managedRuntime = $installed.Current
    $externalRuntime = $null
    if (-not $managedRuntime) {
        $externalRuntime = Get-SystemOpenCodeRuntime -LocalRoot $layout.LocalRoot
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
        ExecutablePath      = if ($currentRuntime) { $currentRuntime.OpenCodeCmd } else { $null }
        Runtime             = if ($currentRuntime) { $currentRuntime.Validation } else { $null }
        InvalidRuntimeHomes = $invalidRuntimeHomes
        PartialPaths        = $partialPaths
        BlockedReason       = $null
        PackageJsonPath     = if ($currentRuntime) { $currentRuntime.PackageJsonPath } else { $null }
    }
}

function Repair-OpenCodeRuntime {
    [CmdletBinding()]
    param(
        [pscustomobject]$State,
        [string[]]$CorruptRuntimeHomes = @(),
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $State) {
        $State = Get-OpenCodeRuntimeState -LocalRoot $LocalRoot
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

function Install-OpenCodeRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NpmCmd,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    New-ManifestedDirectory -Path $layout.OpenCodeCacheRoot | Out-Null
    New-ManifestedDirectory -Path $layout.OpenCodeToolsRoot | Out-Null

    $stagePath = New-ManifestedStageDirectory -Prefix 'opencode' -Mode TemporaryShort
    $npmConfiguration = Get-ManifestedManagedNpmCommandArguments -NpmCmd $NpmCmd -LocalRoot $LocalRoot
    $npmArguments = @('install', '-g', '--prefix', $stagePath, '--cache', $layout.OpenCodeCacheRoot)
    $npmArguments += @($npmConfiguration.CommandArguments)
    $npmArguments += $script:ManifestedSandboxOpenCodePackage

    Write-Host 'Installing OpenCode CLI into managed sandbox tools...'
    & $NpmCmd @npmArguments
    if ($LASTEXITCODE -ne 0) {
        throw "npm install for OpenCode exited with code $LASTEXITCODE."
    }

    $stageValidation = Test-OpenCodeRuntime -RuntimeHome $stagePath
    if (-not $stageValidation.IsReady) {
        throw "OpenCode runtime validation failed after staged install at $stagePath."
    }

    $version = if ($stageValidation.PackageVersion) { $stageValidation.PackageVersion } else { ConvertTo-OpenCodeVersion -VersionText $stageValidation.ReportedVersion }
    if ([string]::IsNullOrWhiteSpace($version)) {
        throw "Could not determine the installed OpenCode version from $($stageValidation.PackageJsonPath)."
    }

    $runtimeHome = Join-Path $layout.OpenCodeToolsRoot $version
    if (Test-Path -LiteralPath $runtimeHome) {
        Remove-ManifestedPath -Path $runtimeHome | Out-Null
    }

    Move-Item -LiteralPath $stagePath -Destination $runtimeHome -Force

    $validation = Test-OpenCodeRuntime -RuntimeHome $runtimeHome
    if (-not $validation.IsReady) {
        throw "OpenCode runtime validation failed after install at $runtimeHome."
    }

    [pscustomobject]@{
        Action          = 'Installed'
        Version         = $validation.PackageVersion
        RuntimeHome     = $runtimeHome
        OpenCodeCmd     = $validation.OpenCodeCmd
        PackageJsonPath = $validation.PackageJsonPath
        Source          = 'Managed'
        CacheRoot       = $layout.OpenCodeCacheRoot
        NpmCmd          = $NpmCmd
    }
}

function Initialize-OpenCodeRuntime {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshOpenCode
    )

    $LocalRoot = (Get-ManifestedLayout).LocalRoot
    $selfElevationContext = Get-ManifestedSelfElevationContext

    $actionsTaken = New-Object System.Collections.Generic.List[string]
    $plannedActions = New-Object System.Collections.Generic.List[string]
    $repairResult = $null
    $installResult = $null
    $commandEnvironment = $null

    $initialState = Get-OpenCodeRuntimeState -LocalRoot $LocalRoot
    $state = $initialState
    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName 'Initialize-OpenCodeRuntime' -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($state.Status -eq 'Blocked') {
        $commandEnvironment = Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-OpenCodeRuntime' -RuntimeState $state
        $result = [pscustomobject]@{
            LocalRoot          = $state.LocalRoot
            Layout             = $state.Layout
            InitialState       = $initialState
            FinalState         = $state
            ActionTaken        = @('None')
            PlannedActions     = @()
            RestartRequired    = $false
            RuntimeTest        = $null
            RepairResult       = $null
            InstallResult      = $null
            CommandEnvironment = $commandEnvironment
            Elevation          = $elevationPlan
        }

        if ($WhatIfPreference) {
            Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $null -Force
            return $result
        }

        $statePath = Save-ManifestedInvokeState -CommandName 'Initialize-OpenCodeRuntime' -Result $result -LocalRoot $LocalRoot -Details @{
            Version         = $state.CurrentVersion
            RuntimeHome     = $state.RuntimeHome
            RuntimeSource   = $state.RuntimeSource
            ExecutablePath  = $state.ExecutablePath
            PackageJsonPath = $state.PackageJsonPath
        }
        Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $statePath -Force
        return $result
    }

    $needsRepair = $state.Status -in @('Partial', 'NeedsRepair')
    $needsInstall = $RefreshOpenCode -or ($state.Status -ne 'Ready')

    if ($needsRepair) {
        $plannedActions.Add('Repair-OpenCodeRuntime') | Out-Null
    }
    if ($needsInstall) {
        $nodePlanState = Get-NodeRuntimeState -LocalRoot $LocalRoot
        if ($nodePlanState.Status -ne 'Ready') {
            $plannedActions.Add('Initialize-NodeRuntime') | Out-Null
        }

        $plannedActions.Add('Install-OpenCodeRuntime') | Out-Null
    }
    $plannedActions.Add('Sync-ManifestedCommandLineEnvironment') | Out-Null

    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName 'Initialize-OpenCodeRuntime' -PlannedActions @($plannedActions) -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($needsRepair) {
        if (-not $PSCmdlet.ShouldProcess($state.Layout.OpenCodeToolsRoot, 'Repair OpenCode runtime state')) {
            return [pscustomobject]@{
                LocalRoot          = $state.LocalRoot
                Layout             = $state.Layout
                InitialState       = $initialState
                FinalState         = $state
                ActionTaken        = @('WhatIf')
                PlannedActions     = @($plannedActions)
                RestartRequired    = $false
                RuntimeTest        = $state.Runtime
                RepairResult       = $null
                InstallResult      = $null
                CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-OpenCodeRuntime' -RuntimeState $state)
                PersistedStatePath = $null
                Elevation          = $elevationPlan
            }
        }

        $repairResult = Repair-OpenCodeRuntime -State $state -LocalRoot $state.LocalRoot
        if ($repairResult.Action -eq 'Repaired') {
            $actionsTaken.Add('Repair-OpenCodeRuntime') | Out-Null
        }

        $state = Get-OpenCodeRuntimeState -LocalRoot $state.LocalRoot
        $needsInstall = $RefreshOpenCode -or ($state.Status -ne 'Ready')
    }

    if ($needsInstall) {
        if (-not $PSCmdlet.ShouldProcess($state.Layout.OpenCodeToolsRoot, 'Ensure OpenCode runtime dependencies and install OpenCode runtime')) {
            return [pscustomobject]@{
                LocalRoot          = $state.LocalRoot
                Layout             = $state.Layout
                InitialState       = $initialState
                FinalState         = $state
                ActionTaken        = @('WhatIf')
                PlannedActions     = @($plannedActions)
                RestartRequired    = $false
                RuntimeTest        = $state.Runtime
                RepairResult       = $repairResult
                InstallResult      = $null
                CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-OpenCodeRuntime' -RuntimeState $state)
                PersistedStatePath = $null
                Elevation          = $elevationPlan
            }
        }

        $nodeState = Get-NodeRuntimeState -LocalRoot $LocalRoot
        if ($nodeState.Status -ne 'Ready') {
            $nodeResult = Initialize-NodeRuntime
            if (@(@($nodeResult.ActionTaken) | Where-Object { $_ -and $_ -ne 'None' }).Count -gt 0) {
                $actionsTaken.Add('Initialize-NodeRuntime') | Out-Null
            }

            $nodeState = Get-NodeRuntimeState -LocalRoot $LocalRoot
        }

        $npmCmd = $null
        if ($nodeState.Runtime -and $nodeState.Runtime.PSObject.Properties['NpmCmd']) {
            $npmCmd = $nodeState.Runtime.NpmCmd
        }
        if ([string]::IsNullOrWhiteSpace($npmCmd) -and -not [string]::IsNullOrWhiteSpace($nodeState.RuntimeHome)) {
            $npmCmd = Join-Path $nodeState.RuntimeHome 'npm.cmd'
        }

        if ($nodeState.Status -ne 'Ready' -or [string]::IsNullOrWhiteSpace($npmCmd) -or -not (Test-Path -LiteralPath $npmCmd)) {
            throw 'A usable npm command was not available after ensuring OpenCode dependencies.'
        }

        $installResult = Install-OpenCodeRuntime -NpmCmd $npmCmd -LocalRoot $LocalRoot
        if ($installResult.Action -eq 'Installed') {
            $actionsTaken.Add('Install-OpenCodeRuntime') | Out-Null
        }
    }

    $finalState = Get-OpenCodeRuntimeState -LocalRoot $LocalRoot
    $runtimeTest = if ($finalState.RuntimeHome) {
        Test-OpenCodeRuntime -RuntimeHome $finalState.RuntimeHome
    }
    else {
        [pscustomobject]@{
            Status          = 'Missing'
            IsReady         = $false
            RuntimeHome     = $null
            OpenCodeCmd     = $null
            PackageJsonPath = $null
            PackageVersion  = $null
            ReportedVersion = $null
        }
    }

    $commandEnvironment = Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-OpenCodeRuntime' -RuntimeState $finalState
    if ($commandEnvironment.Applicable) {
        if (-not $PSCmdlet.ShouldProcess($commandEnvironment.DesiredCommandDirectory, 'Synchronize OpenCode command-line environment')) {
            return [pscustomobject]@{
                LocalRoot          = $finalState.LocalRoot
                Layout             = $finalState.Layout
                InitialState       = $initialState
                FinalState         = $finalState
                ActionTaken        = @('WhatIf')
                PlannedActions     = @($plannedActions)
                RestartRequired    = $false
                RuntimeTest        = $runtimeTest
                RepairResult       = $repairResult
                InstallResult      = $installResult
                CommandEnvironment = $commandEnvironment
                PersistedStatePath = $null
                Elevation          = $elevationPlan
            }
        }

        $commandEnvironment = Sync-ManifestedCommandLineEnvironment -Specification (Get-ManifestedCommandEnvironmentSpec -CommandName 'Initialize-OpenCodeRuntime' -RuntimeState $finalState)
        if ($commandEnvironment.Status -eq 'Updated') {
            $actionsTaken.Add('Sync-ManifestedCommandLineEnvironment') | Out-Null
        }
    }

    $result = [pscustomobject]@{
        LocalRoot          = $finalState.LocalRoot
        Layout             = $finalState.Layout
        InitialState       = $initialState
        FinalState         = $finalState
        ActionTaken        = if ($actionsTaken.Count -gt 0) { @($actionsTaken) } else { @('None') }
        PlannedActions     = @($plannedActions)
        RestartRequired    = $false
        RuntimeTest        = $runtimeTest
        RepairResult       = $repairResult
        InstallResult      = $installResult
        CommandEnvironment = $commandEnvironment
        Elevation          = $elevationPlan
    }

    if ($WhatIfPreference) {
        Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $null -Force
        return $result
    }

    $statePath = Save-ManifestedInvokeState -CommandName 'Initialize-OpenCodeRuntime' -Result $result -LocalRoot $LocalRoot -Details @{
        Version         = $finalState.CurrentVersion
        RuntimeHome     = $finalState.RuntimeHome
        RuntimeSource   = $finalState.RuntimeSource
        ExecutablePath  = $finalState.ExecutablePath
        PackageJsonPath = $finalState.PackageJsonPath
    }
    Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $statePath -Force

    return $result
}
