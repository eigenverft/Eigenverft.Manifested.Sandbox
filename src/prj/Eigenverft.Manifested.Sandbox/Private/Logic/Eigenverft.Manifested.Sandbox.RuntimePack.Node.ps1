<#
    Eigenverft.Manifested.Sandbox.RuntimePack.Node
#>

function Get-ManifestedNodeRuntimeDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    $descriptor = Get-ManifestedRuntimeDescriptor -CommandName $CommandName
    if (-not $descriptor) {
        throw "Could not resolve runtime descriptor for '$CommandName'."
    }
    if ($descriptor.RuntimeFamily -ne 'Node') {
        throw "Runtime '$CommandName' does not belong to the Node runtime family."
    }

    return $descriptor
}

function Get-ManifestedNodePlannedActions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [Parameter(Mandatory = $true)]
        [bool]$NeedsRepair,

        [Parameter(Mandatory = $true)]
        [bool]$NeedsInstall,

        [Parameter(Mandatory = $true)]
        [bool]$NeedsAcquire,

        [pscustomobject]$RuntimeState
    )

    $plannedActions = New-Object System.Collections.Generic.List[string]

    if ($NeedsRepair) {
        $plannedActions.Add($Descriptor.RepairFunctionName) | Out-Null
    }
    if ($NeedsInstall -and $NeedsAcquire) {
        $plannedActions.Add($Descriptor.SavePackageFunctionName) | Out-Null
    }
    if ($NeedsInstall) {
        $plannedActions.Add($Descriptor.TestPackageFunctionName) | Out-Null
        $plannedActions.Add($Descriptor.InstallFunctionName) | Out-Null
    }
    if ($NeedsInstall -or ($RuntimeState -and $RuntimeState.PSObject.Properties['RuntimeSource'] -and ($RuntimeState.RuntimeSource -eq 'Managed'))) {
        $plannedActions.Add('Sync-ManifestedNpmProxyConfiguration') | Out-Null
    }

    $plannedActions.Add('Sync-ManifestedCommandLineEnvironment') | Out-Null
    return @($plannedActions)
}

function Get-ManifestedNodePersistedDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [pscustomobject]$FinalState
    )

    return @{
        Version        = if ($FinalState -and $FinalState.PSObject.Properties['CurrentVersion']) { $FinalState.CurrentVersion } else { $null }
        PackagePath    = if ($FinalState -and $FinalState.PSObject.Properties['PackagePath']) { $FinalState.PackagePath } else { $null }
        RuntimeHome    = if ($FinalState -and $FinalState.PSObject.Properties['RuntimeHome']) { $FinalState.RuntimeHome } else { $null }
        RuntimeSource  = if ($FinalState -and $FinalState.PSObject.Properties['RuntimeSource']) { $FinalState.RuntimeSource } else { $null }
        ExecutablePath = if ($FinalState -and $FinalState.PSObject.Properties['ExecutablePath']) { $FinalState.ExecutablePath } else { $null }
    }
}

function Get-ManifestedNodeManagedFinalizerStatus {
    [CmdletBinding()]
    param(
        [pscustomobject]$RuntimeState,

        [pscustomobject]$RuntimeTest
    )

    $emptyStatus = [pscustomobject]@{
        Applicable = $false
        ActionName = 'Sync-ManifestedNpmProxyConfiguration'
        Target     = $null
        NpmCmd     = $null
        Status     = $null
    }

    if (-not $RuntimeState -or -not $RuntimeState.PSObject.Properties['RuntimeSource'] -or $RuntimeState.RuntimeSource -ne 'Managed') {
        return $emptyStatus
    }

    $npmCmd = $null
    if ($RuntimeTest -and $RuntimeTest.PSObject.Properties['NpmCmd']) {
        $npmCmd = $RuntimeTest.NpmCmd
    }
    elseif ($RuntimeState.PSObject.Properties['Runtime'] -and $RuntimeState.Runtime -and $RuntimeState.Runtime.PSObject.Properties['NpmCmd']) {
        $npmCmd = $RuntimeState.Runtime.NpmCmd
    }
    elseif ($RuntimeState.PSObject.Properties['RuntimeHome'] -and -not [string]::IsNullOrWhiteSpace($RuntimeState.RuntimeHome)) {
        $npmCmd = Join-Path $RuntimeState.RuntimeHome 'npm.cmd'
    }

    if ([string]::IsNullOrWhiteSpace($npmCmd) -or -not (Test-Path -LiteralPath $npmCmd)) {
        return $emptyStatus
    }

    $status = Get-ManifestedNpmProxyConfigurationStatus -NpmCmd $npmCmd -LocalRoot $RuntimeState.LocalRoot
    return [pscustomobject]@{
        Applicable = $true
        ActionName = 'Sync-ManifestedNpmProxyConfiguration'
        Target     = if ($status -and $status.PSObject.Properties['GlobalConfigPath']) { $status.GlobalConfigPath } else { $null }
        NpmCmd     = $npmCmd
        Status     = $status
    }
}

function Invoke-ManifestedNodeManagedFinalization {
    [CmdletBinding()]
    param(
        [pscustomobject]$Status,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$RuntimeState,

        [pscustomobject]$RuntimeTest
    )

    if (-not $Status) {
        $Status = Get-ManifestedNodeManagedFinalizerStatus -RuntimeState $RuntimeState -RuntimeTest $RuntimeTest
    }

    if (-not $Status.Applicable) {
        return if ($Status.PSObject.Properties['Status']) { $Status.Status } else { $null }
    }

    if ($Status.Status -and $Status.Status.PSObject.Properties['Action'] -and ($Status.Status.Action -eq 'NeedsManagedGlobalProxy')) {
        return (Sync-ManifestedNpmProxyConfiguration -NpmCmd $Status.NpmCmd -Status $Status.Status -LocalRoot $RuntimeState.LocalRoot)
    }

    return $Status.Status
}

function Invoke-ManifestedNodeRuntimeInitialization {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [switch]$Refresh
    )

    $descriptor = Get-ManifestedNodeRuntimeDescriptor -CommandName $CommandName
    $LocalRoot = (Get-ManifestedLayout).LocalRoot
    $selfElevationContext = Get-ManifestedSelfElevationContext

    $actionsTaken = New-Object System.Collections.Generic.List[string]
    $repairResult = $null
    $packageInfo = $null
    $packageTest = $null
    $installResult = $null
    $npmProxyConfiguration = $null
    $commandEnvironment = $null

    $initialState = & $descriptor.StateFunctionName -LocalRoot $LocalRoot
    $state = $initialState
    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($state.Status -eq 'Blocked') {
        $commandEnvironment = Get-ManifestedCommandEnvironmentResult -CommandName $descriptor.InitializeCommandName -RuntimeState $state
        $result = New-ManifestedRuntimeResult -LocalRoot $state.LocalRoot -Layout $state.Layout -InitialState $initialState -FinalState $state -ActionTaken @('None') -PlannedActions @() -RestartRequired:$false -AdditionalProperties ([ordered]@{
            Package               = $null
            PackageTest           = $null
            RuntimeTest           = $null
            RepairResult          = $null
            InstallResult         = $null
            NpmProxyConfiguration = $null
            CommandEnvironment    = $commandEnvironment
            Elevation             = $elevationPlan
        })

        return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -Result $result -LocalRoot $LocalRoot -Details (& $descriptor.PersistedDetailsFunctionName -Descriptor $descriptor -FinalState $state) -PersistState:(-not $WhatIfPreference))
    }

    $needsRepair = $state.Status -in @('Partial', 'NeedsRepair')
    $needsInstall = $Refresh -or -not $state.RuntimeHome
    $needsAcquire = $Refresh -or (-not $state.PackagePath)
    $plannedActions = @(Get-ManifestedNodePlannedActions -Descriptor $descriptor -NeedsRepair:$needsRepair -NeedsInstall:$needsInstall -NeedsAcquire:$needsAcquire -RuntimeState $state)
    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName $descriptor.InitializeCommandName -PlannedActions @($plannedActions) -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($needsRepair) {
        if (-not $PSCmdlet.ShouldProcess($state.Layout.($descriptor.ToolsRootPropertyName), ('Repair {0} runtime state' -f $descriptor.DisplayName))) {
            return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -PersistState:$false -Result (
                New-ManifestedRuntimeResult -LocalRoot $state.LocalRoot -Layout $state.Layout -InitialState $initialState -FinalState $state -ActionTaken @('WhatIf') -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
                    Package               = $null
                    PackageTest           = $null
                    RuntimeTest           = $state.Runtime
                    RepairResult          = $null
                    InstallResult         = $null
                    NpmProxyConfiguration = $null
                    CommandEnvironment    = (Get-ManifestedCommandEnvironmentResult -CommandName $descriptor.InitializeCommandName -RuntimeState $state)
                    Elevation             = $elevationPlan
                })
            ))
        }

        $repairResult = & $descriptor.RepairFunctionName -State $state -Flavor $state.Flavor -LocalRoot $state.LocalRoot
        if ($repairResult.Action -eq 'Repaired') {
            $actionsTaken.Add($descriptor.RepairFunctionName) | Out-Null
        }

        $state = & $descriptor.StateFunctionName -Flavor $state.Flavor -LocalRoot $state.LocalRoot
        $needsInstall = $Refresh -or -not $state.RuntimeHome
        $needsAcquire = $Refresh -or (-not $state.PackagePath)
    }

    if ($needsInstall) {
        if ($needsAcquire) {
            if (-not $PSCmdlet.ShouldProcess($state.Layout.($descriptor.CacheRootPropertyName), ('Acquire {0} runtime package' -f $descriptor.DisplayName))) {
                return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -PersistState:$false -Result (
                    New-ManifestedRuntimeResult -LocalRoot $state.LocalRoot -Layout $state.Layout -InitialState $initialState -FinalState $state -ActionTaken @('WhatIf') -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
                        Package               = $null
                        PackageTest           = $null
                        RuntimeTest           = $state.Runtime
                        RepairResult          = $repairResult
                        InstallResult         = $null
                        NpmProxyConfiguration = $null
                        CommandEnvironment    = (Get-ManifestedCommandEnvironmentResult -CommandName $descriptor.InitializeCommandName -RuntimeState $state)
                        Elevation             = $elevationPlan
                    })
                ))
            }

            $saveParameters = @{
                LocalRoot = $state.LocalRoot
                Flavor    = $state.Flavor
            }
            $saveParameters[$descriptor.RefreshParameterName] = [bool]$Refresh
            $packageInfo = & $descriptor.SavePackageFunctionName @saveParameters
            if ($packageInfo.Action -eq 'Downloaded') {
                $actionsTaken.Add($descriptor.SavePackageFunctionName) | Out-Null
            }
        }
        else {
            $packageInfo = $state.Package
        }

        $packageTest = & $descriptor.TestPackageFunctionName -PackageInfo $packageInfo
        if ($packageTest.Status -eq 'CorruptCache') {
            if (-not $PSCmdlet.ShouldProcess($packageInfo.Path, ('Repair corrupt {0} runtime package' -f $descriptor.DisplayName))) {
                return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -PersistState:$false -Result (
                    New-ManifestedRuntimeResult -LocalRoot $state.LocalRoot -Layout $state.Layout -InitialState $initialState -FinalState $state -ActionTaken @('WhatIf') -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
                        Package               = $packageInfo
                        PackageTest           = $packageTest
                        RuntimeTest           = $state.Runtime
                        RepairResult          = $repairResult
                        InstallResult         = $null
                        NpmProxyConfiguration = $null
                        CommandEnvironment    = (Get-ManifestedCommandEnvironmentResult -CommandName $descriptor.InitializeCommandName -RuntimeState $state)
                        Elevation             = $elevationPlan
                    })
                ))
            }

            $repairResult = & $descriptor.RepairFunctionName -State $state -CorruptPackagePaths @($packageInfo.Path) -Flavor $state.Flavor -LocalRoot $state.LocalRoot
            if ($repairResult.Action -eq 'Repaired') {
                $actionsTaken.Add($descriptor.RepairFunctionName) | Out-Null
            }

            $refreshSaveParameters = @{
                LocalRoot = $state.LocalRoot
                Flavor    = $state.Flavor
            }
            $refreshSaveParameters[$descriptor.RefreshParameterName] = $true
            $packageInfo = & $descriptor.SavePackageFunctionName @refreshSaveParameters
            if ($packageInfo.Action -eq 'Downloaded') {
                $actionsTaken.Add($descriptor.SavePackageFunctionName) | Out-Null
            }

            $packageTest = & $descriptor.TestPackageFunctionName -PackageInfo $packageInfo
        }

        if ($packageTest.Status -ne 'Ready') {
            throw ('{0} runtime package validation failed with status {1}.' -f $descriptor.DisplayName, $packageTest.Status)
        }

        $commandParameters = @{}
        if ($Refresh) {
            $commandParameters[$descriptor.RefreshParameterName] = $true
        }
        if ($PSBoundParameters.ContainsKey('WhatIf')) {
            $commandParameters['WhatIf'] = $true
        }

        $elevatedResult = Invoke-ManifestedElevatedCommand -ElevationPlan $elevationPlan -CommandName $descriptor.InitializeCommandName -CommandParameters $commandParameters
        if ($null -ne $elevatedResult) {
            return $elevatedResult
        }

        if (-not $PSCmdlet.ShouldProcess($state.Layout.($descriptor.ToolsRootPropertyName), ('Install {0} runtime' -f $descriptor.DisplayName))) {
            return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -PersistState:$false -Result (
                New-ManifestedRuntimeResult -LocalRoot $state.LocalRoot -Layout $state.Layout -InitialState $initialState -FinalState $state -ActionTaken @('WhatIf') -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
                    Package               = $packageInfo
                    PackageTest           = $packageTest
                    RuntimeTest           = $state.Runtime
                    RepairResult          = $repairResult
                    InstallResult         = $null
                    NpmProxyConfiguration = $null
                    CommandEnvironment    = (Get-ManifestedCommandEnvironmentResult -CommandName $descriptor.InitializeCommandName -RuntimeState $state)
                    Elevation             = $elevationPlan
                })
            ))
        }

        $installResult = & $descriptor.InstallFunctionName -PackageInfo $packageInfo -Flavor $state.Flavor -LocalRoot $state.LocalRoot
        if ($installResult.Action -eq 'Installed') {
            $actionsTaken.Add($descriptor.InstallFunctionName) | Out-Null
        }
    }

    $finalState = & $descriptor.StateFunctionName -Flavor $state.Flavor -LocalRoot $state.LocalRoot
    $runtimeTest = if ($finalState.RuntimeHome) {
        $runtimeTestParameters = if ($descriptor.PSObject.Properties['RuntimeTestParameterResolver'] -and $descriptor.RuntimeTestParameterResolver) {
            & $descriptor.RuntimeTestParameterResolver $finalState
        }
        else {
            @{}
        }

        & $descriptor.RuntimeTestFunctionName @runtimeTestParameters
    }
    else {
        [pscustomobject]@{
            Status   = 'Missing'
            IsReady  = $false
            NodeHome = $null
            NodeExe  = $null
            NpmCmd   = $null
        }
    }

    $nodeManagedFinalizerStatus = Get-ManifestedNodeManagedFinalizerStatus -RuntimeState $finalState -RuntimeTest $runtimeTest
    $npmProxyConfiguration = if ($nodeManagedFinalizerStatus.Status) { $nodeManagedFinalizerStatus.Status } else { $null }

    if ($nodeManagedFinalizerStatus.Applicable -and $nodeManagedFinalizerStatus.Status -and $nodeManagedFinalizerStatus.Status.PSObject.Properties['Action'] -and ($nodeManagedFinalizerStatus.Status.Action -eq 'NeedsManagedGlobalProxy')) {
        if (-not $PSCmdlet.ShouldProcess($nodeManagedFinalizerStatus.Target, 'Configure managed npm proxy settings')) {
            return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -PersistState:$false -Result (
                New-ManifestedRuntimeResult -LocalRoot $finalState.LocalRoot -Layout $finalState.Layout -InitialState $initialState -FinalState $finalState -ActionTaken @('WhatIf') -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
                    Package               = $packageInfo
                    PackageTest           = $packageTest
                    RuntimeTest           = $runtimeTest
                    RepairResult          = $repairResult
                    InstallResult         = $installResult
                    NpmProxyConfiguration = $npmProxyConfiguration
                    CommandEnvironment    = (Get-ManifestedCommandEnvironmentResult -CommandName $descriptor.InitializeCommandName -RuntimeState $finalState)
                    Elevation             = $elevationPlan
                })
            ))
        }

        $npmProxyConfiguration = & $descriptor.ManagedFinalizerFunctionName -Status $nodeManagedFinalizerStatus -RuntimeState $finalState -RuntimeTest $runtimeTest
        if ($npmProxyConfiguration -and $npmProxyConfiguration.PSObject.Properties['Action'] -and ($npmProxyConfiguration.Action -eq 'ConfiguredManagedGlobalProxy')) {
            $actionsTaken.Add('Sync-ManifestedNpmProxyConfiguration') | Out-Null
        }
    }

    $commandEnvironmentSync = Invoke-ManifestedRuntimeCommandEnvironmentSync -Cmdlet $PSCmdlet -CommandName $descriptor.InitializeCommandName -DisplayName $descriptor.DisplayName -RuntimeState $finalState -ActionsTaken $actionsTaken -UseShouldProcess:$true
    $commandEnvironment = $commandEnvironmentSync.CommandEnvironment
    if ($commandEnvironmentSync.StopProcessing) {
        return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -PersistState:$false -Result (
            New-ManifestedRuntimeResult -LocalRoot $finalState.LocalRoot -Layout $finalState.Layout -InitialState $initialState -FinalState $finalState -ActionTaken @('WhatIf') -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
                Package               = $packageInfo
                PackageTest           = $packageTest
                RuntimeTest           = $runtimeTest
                RepairResult          = $repairResult
                InstallResult         = $installResult
                NpmProxyConfiguration = $npmProxyConfiguration
                CommandEnvironment    = $commandEnvironment
                Elevation             = $elevationPlan
            })
        ))
    }

    $result = New-ManifestedRuntimeResult -LocalRoot $finalState.LocalRoot -Layout $finalState.Layout -InitialState $initialState -FinalState $finalState -ActionTaken (if ($actionsTaken.Count -gt 0) { @($actionsTaken) } else { @('None') }) -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
        Package               = $packageInfo
        PackageTest           = $packageTest
        RuntimeTest           = $runtimeTest
        RepairResult          = $repairResult
        InstallResult         = $installResult
        NpmProxyConfiguration = $npmProxyConfiguration
        CommandEnvironment    = $commandEnvironment
        Elevation             = $elevationPlan
    })

    return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -Result $result -LocalRoot $LocalRoot -Details (& $descriptor.PersistedDetailsFunctionName -Descriptor $descriptor -FinalState $finalState) -PersistState:(-not $WhatIfPreference))
}
