<#
    Eigenverft.Manifested.Sandbox.RuntimePack.MachinePrerequisite
#>

function Get-ManifestedMachinePrerequisiteRuntimeDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    $descriptor = Get-ManifestedRuntimeDescriptor -CommandName $CommandName
    if (-not $descriptor) {
        throw "Could not resolve runtime descriptor for '$CommandName'."
    }
    if ($descriptor.RuntimeFamily -ne 'MachinePrerequisite') {
        throw "Runtime '$CommandName' does not belong to the machine prerequisite runtime family."
    }

    return $descriptor
}

function Get-ManifestedMachinePrerequisitePlannedActions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [Parameter(Mandatory = $true)]
        [bool]$NeedsRepair,

        [Parameter(Mandatory = $true)]
        [bool]$NeedsInstall,

        [Parameter(Mandatory = $true)]
        [bool]$NeedsAcquire
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

    return @($plannedActions)
}

function Get-ManifestedMachinePrerequisitePersistedDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [pscustomobject]$FinalState
    )

    return @{
        Version       = if ($FinalState -and $FinalState.PSObject.Properties['CurrentVersion']) { $FinalState.CurrentVersion } else { $null }
        InstallerPath = if ($FinalState -and $FinalState.PSObject.Properties['InstallerPath']) { $FinalState.InstallerPath } else { $null }
    }
}

function Invoke-ManifestedMachinePrerequisiteRuntimeInitialization {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [switch]$Refresh,

        [int]$InstallTimeoutSec = 300
    )

    $descriptor = Get-ManifestedMachinePrerequisiteRuntimeDescriptor -CommandName $CommandName
    $LocalRoot = (Get-ManifestedLayout).LocalRoot
    $selfElevationContext = Get-ManifestedSelfElevationContext

    $actionsTaken = New-Object System.Collections.Generic.List[string]
    $repairResult = $null
    $installerInfo = $null
    $installerTest = $null
    $installResult = $null

    $initialState = & $descriptor.StateFunctionName -LocalRoot $LocalRoot
    $state = $initialState
    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($state.Status -eq 'Blocked') {
        $result = New-ManifestedRuntimeResult -LocalRoot $state.LocalRoot -Layout $state.Layout -InitialState $initialState -FinalState $state -ActionTaken @('None') -PlannedActions @() -RestartRequired:$false -AdditionalProperties ([ordered]@{
            Installer     = $null
            InstallerTest = $null
            RuntimeTest   = $null
            RepairResult  = $null
            InstallResult = $null
            Elevation     = $elevationPlan
        })

        return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -Result $result -LocalRoot $LocalRoot -Details (& $descriptor.PersistedDetailsFunctionName -Descriptor $descriptor -FinalState $state) -PersistState:(-not $WhatIfPreference))
    }

    $needsRepair = $state.Status -in @('Partial', 'NeedsRepair')
    $needsInstall = $Refresh -or ($state.Status -ne 'Ready')
    $needsAcquire = $Refresh -or (-not $state.InstallerPath) -or (-not (Test-Path -LiteralPath $state.InstallerPath))
    $plannedActions = @(Get-ManifestedMachinePrerequisitePlannedActions -Descriptor $descriptor -NeedsRepair:$needsRepair -NeedsInstall:$needsInstall -NeedsAcquire:$needsAcquire)
    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName $descriptor.InitializeCommandName -PlannedActions @($plannedActions) -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($needsRepair) {
        if (-not $PSCmdlet.ShouldProcess($state.InstallerPath, ('Repair {0} runtime state' -f $descriptor.DisplayName))) {
            return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -PersistState:$false -Result (
                New-ManifestedRuntimeResult -LocalRoot $state.LocalRoot -Layout $state.Layout -InitialState $initialState -FinalState $state -ActionTaken @('WhatIf') -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
                    Installer     = $null
                    InstallerTest = $null
                    RuntimeTest   = $state.Runtime
                    RepairResult  = $null
                    InstallResult = $null
                    Elevation     = $elevationPlan
                })
            ))
        }

        $repairResult = & $descriptor.RepairFunctionName -State $state -LocalRoot $state.LocalRoot
        if ($repairResult.Action -eq 'Repaired') {
            $actionsTaken.Add($descriptor.RepairFunctionName) | Out-Null
        }

        $state = & $descriptor.StateFunctionName -LocalRoot $state.LocalRoot
        $needsInstall = $Refresh -or ($state.Status -ne 'Ready')
        $needsAcquire = $Refresh -or (-not $state.InstallerPath) -or (-not (Test-Path -LiteralPath $state.InstallerPath))
    }

    if ($needsInstall) {
        if ($needsAcquire) {
            if (-not $PSCmdlet.ShouldProcess($state.Layout.($descriptor.CacheRootPropertyName), ('Acquire {0} installer' -f $descriptor.DisplayName))) {
                return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -PersistState:$false -Result (
                    New-ManifestedRuntimeResult -LocalRoot $state.LocalRoot -Layout $state.Layout -InitialState $initialState -FinalState $state -ActionTaken @('WhatIf') -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
                        Installer     = $null
                        InstallerTest = $null
                        RuntimeTest   = $state.Runtime
                        RepairResult  = $repairResult
                        InstallResult = $null
                        Elevation     = $elevationPlan
                    })
                ))
            }

            $saveParameters = @{
                LocalRoot = $state.LocalRoot
            }
            $saveParameters[$descriptor.RefreshParameterName] = [bool]$Refresh
            $installerInfo = & $descriptor.SavePackageFunctionName @saveParameters
            if ($installerInfo.Action -eq 'Downloaded') {
                $actionsTaken.Add($descriptor.SavePackageFunctionName) | Out-Null
            }
        }
        else {
            $installerInfo = $state.Installer
        }

        $installerTest = & $descriptor.TestPackageFunctionName -InstallerInfo $installerInfo
        if ($installerTest.Status -eq 'CorruptCache') {
            if (-not $PSCmdlet.ShouldProcess($installerInfo.Path, ('Repair corrupt {0} installer' -f $descriptor.DisplayName))) {
                return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -PersistState:$false -Result (
                    New-ManifestedRuntimeResult -LocalRoot $state.LocalRoot -Layout $state.Layout -InitialState $initialState -FinalState $state -ActionTaken @('WhatIf') -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
                        Installer     = $installerInfo
                        InstallerTest = $installerTest
                        RuntimeTest   = $state.Runtime
                        RepairResult  = $repairResult
                        InstallResult = $null
                        Elevation     = $elevationPlan
                    })
                ))
            }

            $repairResult = & $descriptor.RepairFunctionName -State $state -CorruptInstallerPaths @($installerInfo.Path) -LocalRoot $state.LocalRoot
            if ($repairResult.Action -eq 'Repaired') {
                $actionsTaken.Add($descriptor.RepairFunctionName) | Out-Null
            }

            $refreshSaveParameters = @{
                LocalRoot = $state.LocalRoot
            }
            $refreshSaveParameters[$descriptor.RefreshParameterName] = $true
            $installerInfo = & $descriptor.SavePackageFunctionName @refreshSaveParameters
            if ($installerInfo.Action -eq 'Downloaded') {
                $actionsTaken.Add($descriptor.SavePackageFunctionName) | Out-Null
            }

            $installerTest = & $descriptor.TestPackageFunctionName -InstallerInfo $installerInfo
        }

        if ($installerTest.Status -ne 'Ready') {
            throw ('{0} installer validation failed with status {1}.' -f $descriptor.DisplayName, $installerTest.Status)
        }

        $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName $descriptor.InitializeCommandName -PlannedActions @($plannedActions) -Context @{
            InstalledRuntime = $state.InstalledRuntime
            InstallerInfo    = $installerInfo
        } -LocalRoot $state.LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

        $commandParameters = @{
            InstallTimeoutSec = $InstallTimeoutSec
        }
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

        if (-not $PSCmdlet.ShouldProcess('Microsoft Visual C++ Redistributable (x64)', ('Install {0}' -f $descriptor.DisplayName))) {
            return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -PersistState:$false -Result (
                New-ManifestedRuntimeResult -LocalRoot $state.LocalRoot -Layout $state.Layout -InitialState $initialState -FinalState $state -ActionTaken @('WhatIf') -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
                    Installer     = $installerInfo
                    InstallerTest = $installerTest
                    RuntimeTest   = $state.Runtime
                    RepairResult  = $repairResult
                    InstallResult = $null
                    Elevation     = $elevationPlan
                })
            ))
        }

        $installResult = & $descriptor.InstallFunctionName -InstallerInfo $installerInfo -InstallTimeoutSec $InstallTimeoutSec -LocalRoot $state.LocalRoot
        if ($installResult.Action -eq 'Installed') {
            $actionsTaken.Add($descriptor.InstallFunctionName) | Out-Null
        }
    }

    $finalState = & $descriptor.StateFunctionName -LocalRoot $state.LocalRoot
    $runtimeTestParameters = if ($descriptor.PSObject.Properties['RuntimeTestParameterResolver'] -and $descriptor.RuntimeTestParameterResolver) {
        & $descriptor.RuntimeTestParameterResolver $finalState
    }
    else {
        @{}
    }
    $runtimeTest = & $descriptor.RuntimeTestFunctionName @runtimeTestParameters

    $actionTaken = if ($actionsTaken.Count -gt 0) { @($actionsTaken) } else { @('None') }
    $restartRequired = if ($installResult) { [bool]$installResult.RestartRequired } else { $false }
    $result = New-ManifestedRuntimeResult -LocalRoot $finalState.LocalRoot -Layout $finalState.Layout -InitialState $initialState -FinalState $finalState -ActionTaken $actionTaken -PlannedActions @($plannedActions) -RestartRequired:$restartRequired -AdditionalProperties ([ordered]@{
        Installer     = $installerInfo
        InstallerTest = $installerTest
        RuntimeTest   = $runtimeTest
        RepairResult  = $repairResult
        InstallResult = $installResult
        Elevation     = $elevationPlan
    })

    return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -Result $result -LocalRoot $LocalRoot -Details (& $descriptor.PersistedDetailsFunctionName -Descriptor $descriptor -FinalState $finalState) -PersistState:(-not $WhatIfPreference))
}
