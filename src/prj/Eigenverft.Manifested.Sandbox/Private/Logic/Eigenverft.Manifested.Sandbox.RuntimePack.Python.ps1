<#
    Eigenverft.Manifested.Sandbox.RuntimePack.Python
#>

function Get-ManifestedPythonRuntimeDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    $descriptor = Get-ManifestedRuntimeDescriptor -CommandName $CommandName
    if (-not $descriptor) {
        throw "Could not resolve runtime descriptor for '$CommandName'."
    }
    if ($descriptor.RuntimeFamily -ne 'Python') {
        throw "Runtime '$CommandName' does not belong to the Python runtime family."
    }

    return $descriptor
}

function Get-ManifestedPythonPlannedActions {
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
        $plannedActions.Add('Ensure-PythonPip') | Out-Null
    }
    elseif ($RuntimeState -and $RuntimeState.PSObject.Properties['RuntimeSource'] -and ($RuntimeState.RuntimeSource -eq 'Managed')) {
        $plannedActions.Add('Ensure-PythonPip') | Out-Null
    }

    $plannedActions.Add('Sync-ManifestedCommandLineEnvironment') | Out-Null
    return @($plannedActions)
}

function Get-ManifestedPythonPersistedDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [pscustomobject]$FinalState,

        [pscustomobject]$PackageInfo,

        [pscustomobject]$RuntimeTest,

        [pscustomobject]$PipSetupResult
    )

    return @{
        Version        = if ($FinalState -and $FinalState.PSObject.Properties['CurrentVersion']) { $FinalState.CurrentVersion } else { $null }
        Flavor         = if ($FinalState -and $FinalState.PSObject.Properties['Flavor']) { $FinalState.Flavor } else { $null }
        RuntimeHome    = if ($FinalState -and $FinalState.PSObject.Properties['RuntimeHome']) { $FinalState.RuntimeHome } else { $null }
        RuntimeSource  = if ($FinalState -and $FinalState.PSObject.Properties['RuntimeSource']) { $FinalState.RuntimeSource } else { $null }
        ExecutablePath = if ($FinalState -and $FinalState.PSObject.Properties['ExecutablePath']) { $FinalState.ExecutablePath } else { $null }
        PipVersion     = if ($RuntimeTest -and $RuntimeTest.PSObject.Properties['PipVersion']) { $RuntimeTest.PipVersion } else { $null }
        PipConfigPath  = if ($PipSetupResult -and $PipSetupResult.PSObject.Properties['PipProxyConfiguration'] -and $PipSetupResult.PipProxyConfiguration -and $PipSetupResult.PipProxyConfiguration.PSObject.Properties['PipConfigPath']) { $PipSetupResult.PipProxyConfiguration.PipConfigPath } else { $null }
        AssetName      = if ($PackageInfo -and $PackageInfo.PSObject.Properties['FileName']) { $PackageInfo.FileName } else { $null }
        Sha256         = if ($PackageInfo -and $PackageInfo.PSObject.Properties['Sha256']) { $PackageInfo.Sha256 } else { $null }
        ShaSource      = if ($PackageInfo -and $PackageInfo.PSObject.Properties['ShaSource']) { $PackageInfo.ShaSource } else { $null }
        DownloadUrl    = if ($PackageInfo -and $PackageInfo.PSObject.Properties['DownloadUrl']) { $PackageInfo.DownloadUrl } else { $null }
        ReleaseUrl     = if ($PackageInfo -and $PackageInfo.PSObject.Properties['ReleaseUrl']) { $PackageInfo.ReleaseUrl } else { $null }
        ReleaseId      = if ($PackageInfo -and $PackageInfo.PSObject.Properties['ReleaseId']) { $PackageInfo.ReleaseId } else { $null }
    }
}

function Get-ManifestedPythonManagedFinalizerStatus {
    [CmdletBinding()]
    param(
        [pscustomobject]$RuntimeState
    )

    $applicable = $false
    if ($RuntimeState -and $RuntimeState.PSObject.Properties['RuntimeSource'] -and $RuntimeState.PSObject.Properties['ExecutablePath']) {
        $applicable = ($RuntimeState.RuntimeSource -eq 'Managed') -and (-not [string]::IsNullOrWhiteSpace($RuntimeState.ExecutablePath))
    }

    return [pscustomobject]@{
        Applicable = [bool]$applicable
        ActionName = 'Ensure-PythonPip'
        Target     = if ($applicable -and $RuntimeState.PSObject.Properties['RuntimeHome']) { $RuntimeState.RuntimeHome } else { $null }
    }
}

function Invoke-ManifestedPythonManagedFinalization {
    [CmdletBinding()]
    param(
        [pscustomobject]$Status,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$RuntimeState
    )

    if (-not $Status) {
        $Status = Get-ManifestedPythonManagedFinalizerStatus -RuntimeState $RuntimeState
    }

    if (-not $Status.Applicable) {
        return $null
    }

    return (Ensure-PythonPip -PythonExe $RuntimeState.ExecutablePath -PythonHome $RuntimeState.RuntimeHome -LocalRoot $RuntimeState.LocalRoot)
}

function Invoke-ManifestedPythonRuntimeInitialization {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [switch]$Refresh
    )

    $descriptor = Get-ManifestedPythonRuntimeDescriptor -CommandName $CommandName
    $LocalRoot = (Get-ManifestedLayout).LocalRoot
    $selfElevationContext = Get-ManifestedSelfElevationContext

    $actionsTaken = New-Object System.Collections.Generic.List[string]
    $repairResult = $null
    $packageInfo = $null
    $packageTest = $null
    $installResult = $null
    $pipSetupResult = $null
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
            PipSetupResult        = $null
            PipProxyConfiguration = $null
            CommandEnvironment    = $commandEnvironment
            Elevation             = $elevationPlan
        })

        return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -Result $result -LocalRoot $LocalRoot -Details @{} -PersistState:(-not $WhatIfPreference))
    }

    $needsRepair = $state.Status -in @('Partial', 'NeedsRepair')
    $needsInstall = $Refresh -or -not $state.RuntimeHome
    $needsAcquire = $Refresh -or (-not $state.PackagePath) -or (-not (Test-PythonRuntimePackageHasTrustedHash -PackageInfo $state.Package))
    $plannedActions = @(Get-ManifestedPythonPlannedActions -Descriptor $descriptor -NeedsRepair:$needsRepair -NeedsInstall:$needsInstall -NeedsAcquire:$needsAcquire -RuntimeState $state)
    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName $descriptor.InitializeCommandName -PlannedActions @($plannedActions) -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($WhatIfPreference) {
        return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -PersistState:$false -Result (
            New-ManifestedRuntimeResult -LocalRoot $state.LocalRoot -Layout $state.Layout -InitialState $initialState -FinalState $state -ActionTaken @('WhatIf') -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
                Package               = $state.Package
                PackageTest           = $null
                RuntimeTest           = $state.Runtime
                RepairResult          = $null
                InstallResult         = $null
                PipSetupResult        = $null
                PipProxyConfiguration = $null
                CommandEnvironment    = (Get-ManifestedCommandEnvironmentResult -CommandName $descriptor.InitializeCommandName -RuntimeState $state)
                Elevation             = $elevationPlan
            })
        ))
    }

    if ($needsRepair) {
        if (-not $PSCmdlet.ShouldProcess($state.Layout.($descriptor.ToolsRootPropertyName), ('Repair {0} runtime state' -f $descriptor.DisplayName))) {
            return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -PersistState:$false -Result (
                New-ManifestedRuntimeResult -LocalRoot $state.LocalRoot -Layout $state.Layout -InitialState $initialState -FinalState $state -ActionTaken @('Cancelled') -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
                    Package               = $state.Package
                    PackageTest           = $null
                    RuntimeTest           = $state.Runtime
                    RepairResult          = $null
                    InstallResult         = $null
                    PipSetupResult        = $null
                    PipProxyConfiguration = $null
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
    }

    $needsInstall = $Refresh -or -not $state.RuntimeHome
    $needsAcquire = $Refresh -or (-not $state.PackagePath) -or (-not (Test-PythonRuntimePackageHasTrustedHash -PackageInfo $state.Package))

    if ($needsInstall) {
        if ($needsAcquire) {
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
        if ($packageTest.Status -eq 'UnverifiedCache') {
            $trustedPackageResolution = Resolve-PythonRuntimeTrustedPackageInfo -PackageInfo $packageInfo -Flavor $state.Flavor -LocalRoot $state.LocalRoot
            $packageInfo = $trustedPackageResolution.PackageInfo
            $packageTest = & $descriptor.TestPackageFunctionName -PackageInfo $packageInfo

            if ($packageTest.Status -eq 'UnverifiedCache') {
                throw (New-PythonRuntimePackageTrustFailureMessage -PackageInfo $packageInfo -MetadataRefreshError $trustedPackageResolution.MetadataRefreshError)
            }
        }

        if ($packageTest.Status -eq 'CorruptCache') {
            if (-not $PSCmdlet.ShouldProcess($packageInfo.Path, ('Repair corrupt {0} runtime package' -f $descriptor.DisplayName))) {
                return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -PersistState:$false -Result (
                    New-ManifestedRuntimeResult -LocalRoot $state.LocalRoot -Layout $state.Layout -InitialState $initialState -FinalState $state -ActionTaken @('Cancelled') -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
                        Package               = $packageInfo
                        PackageTest           = $packageTest
                        RuntimeTest           = $state.Runtime
                        RepairResult          = $repairResult
                        InstallResult         = $null
                        PipSetupResult        = $null
                        PipProxyConfiguration = $null
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
                New-ManifestedRuntimeResult -LocalRoot $state.LocalRoot -Layout $state.Layout -InitialState $initialState -FinalState $state -ActionTaken @('Cancelled') -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
                    Package               = $packageInfo
                    PackageTest           = $packageTest
                    RuntimeTest           = $state.Runtime
                    RepairResult          = $repairResult
                    InstallResult         = $null
                    PipSetupResult        = $null
                    PipProxyConfiguration = $null
                    CommandEnvironment    = (Get-ManifestedCommandEnvironmentResult -CommandName $descriptor.InitializeCommandName -RuntimeState $state)
                    Elevation             = $elevationPlan
                })
            ))
        }

        $installResult = & $descriptor.InstallFunctionName -PackageInfo $packageInfo -Flavor $state.Flavor -LocalRoot $state.LocalRoot -ForceInstall:$Refresh
        if ($installResult.Action -eq 'Installed') {
            $actionsTaken.Add($descriptor.InstallFunctionName) | Out-Null
        }
        if ($installResult.PSObject.Properties['PipResult'] -and $installResult.PipResult) {
            if ($installResult.PipResult.Action -ne 'Reused') {
                $actionsTaken.Add('Ensure-PythonPip') | Out-Null
            }
            elseif ($installResult.PipResult.PipProxyConfiguration -and $installResult.PipResult.PipProxyConfiguration.Action -eq 'ConfiguredManagedProxy') {
                $actionsTaken.Add('Sync-ManifestedPipProxyConfiguration') | Out-Null
            }
        }
    }

    $finalState = & $descriptor.StateFunctionName -Flavor $state.Flavor -LocalRoot $state.LocalRoot
    $runtimeTestParameters = if ($descriptor.PSObject.Properties['RuntimeTestParameterResolver'] -and $descriptor.RuntimeTestParameterResolver) {
        & $descriptor.RuntimeTestParameterResolver $finalState
    }
    else {
        @{}
    }

    $runtimeTest = & $descriptor.RuntimeTestFunctionName @runtimeTestParameters
    if ($finalState.Status -ne 'Ready' -or -not $runtimeTest -or -not $runtimeTest.IsReady) {
        throw 'Python runtime validation did not reach the Ready state.'
    }

    $pythonManagedFinalizerStatus = Get-ManifestedPythonManagedFinalizerStatus -RuntimeState $finalState
    if ($pythonManagedFinalizerStatus.Applicable) {
        $pipSetupResult = & $descriptor.ManagedFinalizerFunctionName -Status $pythonManagedFinalizerStatus -RuntimeState $finalState
        if ($pipSetupResult.Action -ne 'Reused') {
            $actionsTaken.Add('Ensure-PythonPip') | Out-Null
        }
        elseif ($pipSetupResult.PipProxyConfiguration -and $pipSetupResult.PipProxyConfiguration.Action -eq 'ConfiguredManagedProxy') {
            $actionsTaken.Add('Sync-ManifestedPipProxyConfiguration') | Out-Null
        }

        $runtimeTest = & $descriptor.RuntimeTestFunctionName @runtimeTestParameters
    }

    $commandEnvironmentSync = Invoke-ManifestedRuntimeCommandEnvironmentSync -Cmdlet $PSCmdlet -CommandName $descriptor.InitializeCommandName -DisplayName $descriptor.DisplayName -RuntimeState $finalState -ActionsTaken $actionsTaken -UseShouldProcess:$false -RequireNeedsSync:$true
    $commandEnvironment = $commandEnvironmentSync.CommandEnvironment

    $effectivePackageInfo = if ($packageInfo) { $packageInfo } elseif ($finalState.Package) { $finalState.Package } else { $null }
    $result = New-ManifestedRuntimeResult -LocalRoot $finalState.LocalRoot -Layout $finalState.Layout -InitialState $initialState -FinalState $finalState -ActionTaken (if ($actionsTaken.Count -gt 0) { @($actionsTaken) } else { @('None') }) -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
        Package               = $effectivePackageInfo
        PackageTest           = $packageTest
        RuntimeTest           = $runtimeTest
        RepairResult          = $repairResult
        InstallResult         = $installResult
        PipSetupResult        = $pipSetupResult
        PipProxyConfiguration = if ($pipSetupResult) { $pipSetupResult.PipProxyConfiguration } else { $null }
        CommandEnvironment    = $commandEnvironment
        Elevation             = $elevationPlan
    })

    return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -Result $result -LocalRoot $LocalRoot -Details (& $descriptor.PersistedDetailsFunctionName -Descriptor $descriptor -FinalState $finalState -PackageInfo $effectivePackageInfo -RuntimeTest $runtimeTest -PipSetupResult $pipSetupResult))
}
