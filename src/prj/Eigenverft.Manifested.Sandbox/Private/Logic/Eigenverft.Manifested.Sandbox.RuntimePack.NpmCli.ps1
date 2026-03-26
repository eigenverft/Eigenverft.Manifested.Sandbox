<#
    Eigenverft.Manifested.Sandbox.RuntimePack.NpmCli
#>

function Get-ManifestedNpmCliRuntimeDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    $descriptor = Get-ManifestedRuntimeDescriptor -CommandName $CommandName
    if (-not $descriptor) {
        throw "Could not resolve runtime descriptor for '$CommandName'."
    }
    if ($descriptor.RuntimeFamily -ne 'NpmCli') {
        throw "Runtime '$CommandName' does not belong to the npm CLI runtime family."
    }

    return $descriptor
}

function Test-ManifestedNpmCliNodeRuntime {
    [CmdletBinding()]
    param(
        [pscustomobject]$NodeState,

        [version]$MinimumVersion
    )

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
    $hasCompatibleNode = if ($MinimumVersion) {
        ($currentVersion -and ($currentVersion -ge $MinimumVersion))
    }
    else {
        $isReady
    }
    $hasUsableNpm = (-not [string]::IsNullOrWhiteSpace($npmCmd)) -and (Test-Path -LiteralPath $npmCmd)
    $needsRefresh = $isReady -and $MinimumVersion -and (-not $hasCompatibleNode)

    [pscustomobject]@{
        RequiredVersion   = if ($MinimumVersion) { 'v' + $MinimumVersion.ToString() } else { $null }
        CurrentVersion    = if ($currentVersion) { 'v' + $currentVersion.ToString() } else { $null }
        IsReady           = [bool]$isReady
        HasCompatibleNode = [bool]$hasCompatibleNode
        HasUsableNpm      = [bool]$hasUsableNpm
        IsCompatible      = [bool]($isReady -and $hasCompatibleNode -and $hasUsableNpm)
        NeedsRefresh      = [bool]$needsRefresh
        NpmCmd            = $npmCmd
    }
}

function Get-ManifestedNpmCliPlannedActions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [Parameter(Mandatory = $true)]
        [bool]$NeedsRepair,

        [Parameter(Mandatory = $true)]
        [bool]$NeedsInstall,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $plannedActions = New-Object System.Collections.Generic.List[string]

    if ($NeedsRepair) {
        $plannedActions.Add($Descriptor.RepairFunctionName) | Out-Null
    }

    if ($NeedsInstall) {
        foreach ($dependency in @($Descriptor.DirectInstallDependencies)) {
            if ($dependency -and $dependency.PSObject.Properties['CommandName'] -and $dependency.CommandName) {
                $plannedActions.Add($dependency.CommandName) | Out-Null
            }
        }

        if ($Descriptor.NodeDependency -and $Descriptor.NodeDependency.Required) {
            $nodeRequirement = Test-ManifestedNpmCliNodeRuntime -NodeState (Get-NodeRuntimeState -LocalRoot $LocalRoot) -MinimumVersion $Descriptor.NodeDependency.MinimumVersion
            if (-not $nodeRequirement.IsCompatible) {
                $plannedActions.Add('Initialize-NodeRuntime') | Out-Null
            }
        }

        $plannedActions.Add($Descriptor.InstallFunctionName) | Out-Null
    }

    $plannedActions.Add('Sync-ManifestedCommandLineEnvironment') | Out-Null
    return @($plannedActions)
}

function Get-ManifestedNpmCliDependencyResolution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $actionsTaken = New-Object System.Collections.Generic.List[string]

    foreach ($dependency in @($Descriptor.DirectInstallDependencies)) {
        if (-not $dependency -or -not $dependency.PSObject.Properties['CommandName'] -or [string]::IsNullOrWhiteSpace($dependency.CommandName)) {
            continue
        }

        $dependencyResult = & $dependency.CommandName
        if (@(@($dependencyResult.ActionTaken) | Where-Object { $_ -and $_ -ne 'None' }).Count -gt 0) {
            $actionsTaken.Add($dependency.CommandName) | Out-Null
        }
    }

    $nodeRequirement = $null
    if ($Descriptor.NodeDependency -and $Descriptor.NodeDependency.Required) {
        $nodeState = Get-NodeRuntimeState -LocalRoot $LocalRoot
        $nodeRequirement = Test-ManifestedNpmCliNodeRuntime -NodeState $nodeState -MinimumVersion $Descriptor.NodeDependency.MinimumVersion
        if (-not $nodeRequirement.IsCompatible) {
            $nodeCommandParameters = @{}
            if ($nodeRequirement.NeedsRefresh) {
                $nodeCommandParameters['RefreshNode'] = $true
            }

            $nodeResult = Initialize-NodeRuntime @nodeCommandParameters
            if (@(@($nodeResult.ActionTaken) | Where-Object { $_ -and $_ -ne 'None' }).Count -gt 0) {
                $actionsTaken.Add('Initialize-NodeRuntime') | Out-Null
            }

            $nodeState = Get-NodeRuntimeState -LocalRoot $LocalRoot
            $nodeRequirement = Test-ManifestedNpmCliNodeRuntime -NodeState $nodeState -MinimumVersion $Descriptor.NodeDependency.MinimumVersion
        }
    }

    $npmCmd = if ($nodeRequirement) { $nodeRequirement.NpmCmd } else { $null }
    if ($Descriptor.NodeDependency -and $Descriptor.NodeDependency.Required -and (-not $nodeRequirement.IsCompatible -or [string]::IsNullOrWhiteSpace($npmCmd) -or -not (Test-Path -LiteralPath $npmCmd))) {
        $requiredVersionMessage = if ($nodeRequirement.RequiredVersion) { " Required: $($nodeRequirement.RequiredVersion)." } else { '' }
        $currentVersionMessage = if ($nodeRequirement.CurrentVersion) { " Current: $($nodeRequirement.CurrentVersion)." } else { '' }
        throw ("A Node.js runtime compatible with {0} was not available after ensuring dependencies.{1}{2}" -f $Descriptor.DisplayName, $requiredVersionMessage, $currentVersionMessage)
    }

    return [pscustomobject]@{
        NpmCmd         = $npmCmd
        NodeRequirement = $nodeRequirement
        ActionTaken    = @($actionsTaken)
    }
}

function Invoke-ManifestedNpmCliRuntimeInitialization {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [switch]$Refresh
    )

    $descriptor = Get-ManifestedNpmCliRuntimeDescriptor -CommandName $CommandName
    $LocalRoot = (Get-ManifestedLayout).LocalRoot
    $selfElevationContext = Get-ManifestedSelfElevationContext

    $actionsTaken = New-Object System.Collections.Generic.List[string]
    $repairResult = $null
    $installResult = $null
    $commandEnvironment = $null

    $initialState = & $descriptor.StateFunctionName -LocalRoot $LocalRoot
    $state = $initialState
    $needsRepair = $state.Status -in @('Partial', 'NeedsRepair')
    $needsInstall = $Refresh -or ($state.Status -ne 'Ready')
    $plannedActions = @(Get-ManifestedNpmCliPlannedActions -Descriptor $descriptor -NeedsRepair:$needsRepair -NeedsInstall:$needsInstall -LocalRoot $LocalRoot)
    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName $descriptor.InitializeCommandName -PlannedActions $plannedActions -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($state.Status -eq 'Blocked') {
        $commandEnvironment = Get-ManifestedCommandEnvironmentResult -CommandName $descriptor.InitializeCommandName -RuntimeState $state
        $result = New-ManifestedRuntimeResult -LocalRoot $state.LocalRoot -Layout $state.Layout -InitialState $initialState -FinalState $state -ActionTaken @('None') -PlannedActions @() -RestartRequired:$false -AdditionalProperties ([ordered]@{
            RuntimeTest        = $null
            RepairResult       = $null
            InstallResult      = $null
            CommandEnvironment = $commandEnvironment
            Elevation          = $elevationPlan
        })

        return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -Result $result -LocalRoot $LocalRoot -Details @{
            Version         = $state.CurrentVersion
            RuntimeHome     = $state.RuntimeHome
            RuntimeSource   = $state.RuntimeSource
            ExecutablePath  = $state.ExecutablePath
            PackageJsonPath = if ($state.PSObject.Properties[$descriptor.PackageJsonPropertyName]) { $state.($descriptor.PackageJsonPropertyName) } else { $null }
        } -PersistState:(-not $WhatIfPreference))
    }

    if ($needsRepair) {
        $repairTarget = if ($state.Layout -and $descriptor.ToolsRootPropertyName -and $state.Layout.PSObject.Properties[$descriptor.ToolsRootPropertyName]) { $state.Layout.($descriptor.ToolsRootPropertyName) } else { $state.LocalRoot }
        if (-not $PSCmdlet.ShouldProcess($repairTarget, ('Repair {0} runtime state' -f $descriptor.DisplayName))) {
            return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -PersistState:$false -Result (
                New-ManifestedRuntimeResult -LocalRoot $state.LocalRoot -Layout $state.Layout -InitialState $initialState -FinalState $state -ActionTaken @('WhatIf') -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
                    RuntimeTest        = $state.Runtime
                    RepairResult       = $null
                    InstallResult      = $null
                    CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName $descriptor.InitializeCommandName -RuntimeState $state)
                    Elevation          = $elevationPlan
                })
            ))
        }

        $repairResult = & $descriptor.RepairFunctionName -State $state -LocalRoot $state.LocalRoot
        if ($repairResult.Action -eq 'Repaired') {
            $actionsTaken.Add($descriptor.RepairFunctionName) | Out-Null
        }

        $state = & $descriptor.StateFunctionName -LocalRoot $state.LocalRoot
        $needsInstall = $Refresh -or ($state.Status -ne 'Ready')
    }

    if ($needsInstall) {
        $installTarget = if ($state.Layout -and $descriptor.ToolsRootPropertyName -and $state.Layout.PSObject.Properties[$descriptor.ToolsRootPropertyName]) { $state.Layout.($descriptor.ToolsRootPropertyName) } else { $state.LocalRoot }
        if (-not $PSCmdlet.ShouldProcess($installTarget, ('Ensure {0} runtime dependencies and install {0} runtime' -f $descriptor.DisplayName))) {
            return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -PersistState:$false -Result (
                New-ManifestedRuntimeResult -LocalRoot $state.LocalRoot -Layout $state.Layout -InitialState $initialState -FinalState $state -ActionTaken @('WhatIf') -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
                    RuntimeTest        = $state.Runtime
                    RepairResult       = $repairResult
                    InstallResult      = $null
                    CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName $descriptor.InitializeCommandName -RuntimeState $state)
                    Elevation          = $elevationPlan
                })
            ))
        }

        $dependencyResolution = Get-ManifestedNpmCliDependencyResolution -Descriptor $descriptor -LocalRoot $LocalRoot
        foreach ($action in @($dependencyResolution.ActionTaken)) {
            $actionsTaken.Add($action) | Out-Null
        }

        $installResult = & $descriptor.InstallFunctionName -NpmCmd $dependencyResolution.NpmCmd -LocalRoot $LocalRoot
        if ($installResult.Action -eq 'Installed') {
            $actionsTaken.Add($descriptor.InstallFunctionName) | Out-Null
        }
    }

    $finalState = & $descriptor.StateFunctionName -LocalRoot $LocalRoot
    $runtimeTest = if ($finalState.RuntimeHome) {
        & $descriptor.RuntimeTestFunctionName -RuntimeHome $finalState.RuntimeHome
    }
    else {
        [pscustomobject]@{
            Status          = 'Missing'
            IsReady         = $false
            RuntimeHome     = $null
            PackageJsonPath = $null
            PackageVersion  = $null
            ReportedVersion = $null
        }
    }

    $commandEnvironmentSync = Invoke-ManifestedRuntimeCommandEnvironmentSync -Cmdlet $PSCmdlet -CommandName $descriptor.InitializeCommandName -DisplayName $descriptor.DisplayName -RuntimeState $finalState -ActionsTaken $actionsTaken -UseShouldProcess:$true
    $commandEnvironment = $commandEnvironmentSync.CommandEnvironment
    if ($commandEnvironmentSync.StopProcessing) {
        return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -PersistState:$false -Result (
            New-ManifestedRuntimeResult -LocalRoot $finalState.LocalRoot -Layout $finalState.Layout -InitialState $initialState -FinalState $finalState -ActionTaken @('WhatIf') -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
                RuntimeTest        = $runtimeTest
                RepairResult       = $repairResult
                InstallResult      = $installResult
                CommandEnvironment = $commandEnvironment
                Elevation          = $elevationPlan
            })
        ))
    }

    $actionTaken = if ($actionsTaken.Count -gt 0) { @($actionsTaken) } else { @('None') }
    $result = New-ManifestedRuntimeResult -LocalRoot $finalState.LocalRoot -Layout $finalState.Layout -InitialState $initialState -FinalState $finalState -ActionTaken $actionTaken -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
        RuntimeTest        = $runtimeTest
        RepairResult       = $repairResult
        InstallResult      = $installResult
        CommandEnvironment = $commandEnvironment
        Elevation          = $elevationPlan
    })

    return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -Result $result -LocalRoot $LocalRoot -Details @{
        Version         = $finalState.CurrentVersion
        RuntimeHome     = $finalState.RuntimeHome
        RuntimeSource   = $finalState.RuntimeSource
        ExecutablePath  = $finalState.ExecutablePath
        PackageJsonPath = if ($finalState.PSObject.Properties[$descriptor.PackageJsonPropertyName]) { $finalState.($descriptor.PackageJsonPropertyName) } else { $null }
    } -PersistState:(-not $WhatIfPreference))
}
