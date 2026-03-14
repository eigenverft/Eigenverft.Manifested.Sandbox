<#
    Eigenverft.Manifested.Sandbox.Cmd.CodexRuntimeAndCache
#>

$script:ManifestedSandboxCodexPackage = '@openai/codex@latest'

function ConvertTo-CodexVersion {
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeHome
    )

    return (Join-Path $RuntimeHome 'node_modules\@openai\codex\package.json')
}

function Get-CodexRuntimePackageVersion {
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

    Write-Host 'Installing Codex CLI into managed sandbox tools...'
    & $NpmCmd install -g --prefix $stagePath --cache $layout.CodexCacheRoot $script:ManifestedSandboxCodexPackage
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
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$RefreshCodex
    )

    $LocalRoot = (Get-ManifestedLayout).LocalRoot
    $selfElevationContext = Get-ManifestedSelfElevationContext

    $actionsTaken = New-Object System.Collections.Generic.List[string]
    $plannedActions = New-Object System.Collections.Generic.List[string]
    $repairResult = $null
    $installResult = $null
    $commandEnvironment = $null

    $initialState = Get-CodexRuntimeState -LocalRoot $LocalRoot
    $state = $initialState
    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName 'Initialize-CodexRuntime' -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($state.Status -eq 'Blocked') {
        $commandEnvironment = Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-CodexRuntime' -RuntimeState $state
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

        $statePath = Save-ManifestedInvokeState -CommandName 'Initialize-CodexRuntime' -Result $result -LocalRoot $LocalRoot -Details @{
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
    $needsInstall = $RefreshCodex -or ($state.Status -ne 'Ready')

    if ($needsRepair) {
        $plannedActions.Add('Repair-CodexRuntime') | Out-Null
    }
    if ($needsInstall) {
        $nodePlanState = Get-NodeRuntimeState -LocalRoot $LocalRoot
        if ($nodePlanState.Status -ne 'Ready') {
            $plannedActions.Add('Initialize-VCRuntime') | Out-Null
            $plannedActions.Add('Initialize-NodeRuntime') | Out-Null
        }

        $plannedActions.Add('Install-CodexRuntime') | Out-Null
    }
    $plannedActions.Add('Sync-ManifestedCommandLineEnvironment') | Out-Null

    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName 'Initialize-CodexRuntime' -PlannedActions @($plannedActions) -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($needsRepair) {
        if (-not $PSCmdlet.ShouldProcess($state.Layout.CodexToolsRoot, 'Repair Codex runtime state')) {
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
                CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-CodexRuntime' -RuntimeState $state)
                PersistedStatePath = $null
                Elevation          = $elevationPlan
            }
        }

        $repairResult = Repair-CodexRuntime -State $state -LocalRoot $state.LocalRoot
        if ($repairResult.Action -eq 'Repaired') {
            $actionsTaken.Add('Repair-CodexRuntime') | Out-Null
        }

        $state = Get-CodexRuntimeState -LocalRoot $state.LocalRoot
        $needsInstall = $RefreshCodex -or ($state.Status -ne 'Ready')
    }

    if ($needsInstall) {
        if (-not $PSCmdlet.ShouldProcess($state.Layout.CodexToolsRoot, 'Ensure Codex runtime dependencies and install Codex runtime')) {
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
                CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-CodexRuntime' -RuntimeState $state)
                PersistedStatePath = $null
                Elevation          = $elevationPlan
            }
        }

        $nodeState = Get-NodeRuntimeState -LocalRoot $LocalRoot
        if ($nodeState.Status -ne 'Ready') {
            $vcResult = Initialize-VCRuntime
            if (@(@($vcResult.ActionTaken) | Where-Object { $_ -and $_ -ne 'None' }).Count -gt 0) {
                $actionsTaken.Add('Initialize-VCRuntime') | Out-Null
            }

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
            throw 'A usable npm command was not available after ensuring Codex dependencies.'
        }

        $installResult = Install-CodexRuntime -NpmCmd $npmCmd -LocalRoot $LocalRoot
        if ($installResult.Action -eq 'Installed') {
            $actionsTaken.Add('Install-CodexRuntime') | Out-Null
        }
    }

    $finalState = Get-CodexRuntimeState -LocalRoot $LocalRoot
    $runtimeTest = if ($finalState.RuntimeHome) {
        Test-CodexRuntime -RuntimeHome $finalState.RuntimeHome
    }
    else {
        [pscustomobject]@{
            Status          = 'Missing'
            IsReady         = $false
            RuntimeHome     = $null
            CodexCmd        = $null
            PackageJsonPath = $null
            PackageVersion  = $null
            ReportedVersion = $null
        }
    }

    $commandEnvironment = Get-ManifestedCommandEnvironmentResult -CommandName 'Initialize-CodexRuntime' -RuntimeState $finalState
    if ($commandEnvironment.Applicable) {
        if (-not $PSCmdlet.ShouldProcess($commandEnvironment.DesiredCommandDirectory, 'Synchronize Codex command-line environment')) {
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

        $commandEnvironment = Sync-ManifestedCommandLineEnvironment -Specification (Get-ManifestedCommandEnvironmentSpec -CommandName 'Initialize-CodexRuntime' -RuntimeState $finalState)
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

    $statePath = Save-ManifestedInvokeState -CommandName 'Initialize-CodexRuntime' -Result $result -LocalRoot $LocalRoot -Details @{
        Version         = $finalState.CurrentVersion
        RuntimeHome     = $finalState.RuntimeHome
        RuntimeSource   = $finalState.RuntimeSource
        ExecutablePath  = $finalState.ExecutablePath
        PackageJsonPath = $finalState.PackageJsonPath
    }
    Add-Member -InputObject $result -NotePropertyName PersistedStatePath -NotePropertyValue $statePath -Force

    return $result
}
