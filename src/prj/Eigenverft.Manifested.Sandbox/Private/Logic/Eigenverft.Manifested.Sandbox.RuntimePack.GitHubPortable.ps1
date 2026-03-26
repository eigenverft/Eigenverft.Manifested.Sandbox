<#
    Eigenverft.Manifested.Sandbox.RuntimePack.GitHubPortable
#>

function Get-ManifestedGitHubPortableRuntimeDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    $descriptor = Get-ManifestedRuntimeDescriptor -CommandName $CommandName
    if (-not $descriptor) {
        throw "Could not resolve runtime descriptor for '$CommandName'."
    }
    if ($descriptor.RuntimeFamily -ne 'GitHubPortable') {
        throw "Runtime '$CommandName' does not belong to the GitHub portable runtime family."
    }

    return $descriptor
}

function Get-ManifestedGitHubPortableStateParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [pscustomobject]$RuntimeState,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $parameters = @{
        LocalRoot = $LocalRoot
    }

    if ($RuntimeState -and $RuntimeState.PSObject.Properties['Flavor'] -and -not [string]::IsNullOrWhiteSpace($RuntimeState.Flavor)) {
        $parameters['Flavor'] = $RuntimeState.Flavor
    }

    return $parameters
}

function Get-ManifestedGitHubPortableRepairParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$RuntimeState,

        [string[]]$CorruptPackagePaths = @(),

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $parameters = @{
        State     = $RuntimeState
        LocalRoot = $LocalRoot
    }

    if ($RuntimeState.PSObject.Properties['Flavor'] -and -not [string]::IsNullOrWhiteSpace($RuntimeState.Flavor)) {
        $parameters['Flavor'] = $RuntimeState.Flavor
    }
    if (@($CorruptPackagePaths).Count -gt 0) {
        $parameters['CorruptPackagePaths'] = @($CorruptPackagePaths)
    }

    return $parameters
}

function Get-ManifestedGitHubPortableSavePackageParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [Parameter(Mandatory = $true)]
        [bool]$Refresh,

        [pscustomobject]$RuntimeState,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $parameters = @{
        LocalRoot = $LocalRoot
    }

    if ($Descriptor.RefreshParameterName) {
        $parameters[$Descriptor.RefreshParameterName] = $Refresh
    }
    if ($RuntimeState -and $RuntimeState.PSObject.Properties['Flavor'] -and -not [string]::IsNullOrWhiteSpace($RuntimeState.Flavor)) {
        $parameters['Flavor'] = $RuntimeState.Flavor
    }

    return $parameters
}

function Get-ManifestedGitHubPortableInstallParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo,

        [pscustomobject]$RuntimeState,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $parameters = @{
        PackageInfo = $PackageInfo
        LocalRoot   = $LocalRoot
    }

    if ($RuntimeState -and $RuntimeState.PSObject.Properties['Flavor'] -and -not [string]::IsNullOrWhiteSpace($RuntimeState.Flavor)) {
        $parameters['Flavor'] = $RuntimeState.Flavor
    }

    return $parameters
}

function Get-ManifestedGitHubPortableRuntimeTestParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$RuntimeState
    )

    $parameters = @{
        RuntimeHome = $RuntimeState.RuntimeHome
    }

    if ($Descriptor.PSObject.Properties['RuntimeTestParameterResolver'] -and $Descriptor.RuntimeTestParameterResolver) {
        $resolvedParameters = & $Descriptor.RuntimeTestParameterResolver $RuntimeState
        if ($resolvedParameters) {
            foreach ($entry in $resolvedParameters.GetEnumerator()) {
                $parameters[$entry.Key] = $entry.Value
            }
        }
    }

    return $parameters
}

function Get-ManifestedGitHubPortablePersistedDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [pscustomobject]$FinalState,

        [pscustomobject]$PackageInfo
    )

    $detailsPackage = if ($PackageInfo) { $PackageInfo } else { $null }
    $details = [ordered]@{
        Tag            = if ($detailsPackage -and $detailsPackage.PSObject.Properties['TagName']) { $detailsPackage.TagName } else { $null }
        Version        = if ($FinalState -and $FinalState.PSObject.Properties['CurrentVersion']) { $FinalState.CurrentVersion } else { $null }
        Flavor         = if ($FinalState -and $FinalState.PSObject.Properties['Flavor']) { $FinalState.Flavor } else { $null }
        AssetName      = if ($detailsPackage -and $detailsPackage.PSObject.Properties['FileName']) { $detailsPackage.FileName } else { $null }
        PackagePath    = if ($detailsPackage -and $detailsPackage.PSObject.Properties['Path']) { $detailsPackage.Path } elseif ($FinalState -and $FinalState.PSObject.Properties['PackagePath']) { $FinalState.PackagePath } else { $null }
        RuntimeHome    = if ($FinalState -and $FinalState.PSObject.Properties['RuntimeHome']) { $FinalState.RuntimeHome } else { $null }
        RuntimeSource  = if ($FinalState -and $FinalState.PSObject.Properties['RuntimeSource']) { $FinalState.RuntimeSource } else { $null }
        ExecutablePath = if ($FinalState -and $FinalState.PSObject.Properties['ExecutablePath']) { $FinalState.ExecutablePath } else { $null }
        DownloadUrl    = if ($detailsPackage -and $detailsPackage.PSObject.Properties['DownloadUrl']) { $detailsPackage.DownloadUrl } else { $null }
        Sha256         = if ($detailsPackage -and $detailsPackage.PSObject.Properties['Sha256']) { $detailsPackage.Sha256 } else { $null }
        ShaSource      = if ($detailsPackage -and $detailsPackage.PSObject.Properties['ShaSource']) { $detailsPackage.ShaSource } else { $null }
    }

    foreach ($propertyName in @($Descriptor.PersistedExtraStateProperties)) {
        $details[$propertyName] = if ($FinalState -and $FinalState.PSObject.Properties[$propertyName]) { $FinalState.$propertyName } else { $null }
    }

    return $details
}

function Get-ManifestedGitHubPortablePlannedActions {
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

    $plannedActions.Add('Sync-ManifestedCommandLineEnvironment') | Out-Null
    return @($plannedActions)
}

function Invoke-ManifestedGitHubPortableRuntimeInitialization {
<#
.SYNOPSIS
Runs the shared acquire-verify-install flow for GitHub-downloaded runtimes.

.DESCRIPTION
Uses the runtime registry descriptor to preserve each public command's current
state, package validation, repair, installation, and environment-sync behavior
while moving the orchestration into one shared family helper.

.PARAMETER CommandName
Public initialize command name, such as `Initialize-Ps7Runtime`.

.PARAMETER Refresh
Forces package reacquisition and runtime reinstall for the selected runtime.

.EXAMPLE
Invoke-ManifestedGitHubPortableRuntimeInitialization -CommandName 'Initialize-Ps7Runtime'

.EXAMPLE
Invoke-ManifestedGitHubPortableRuntimeInitialization -CommandName 'Initialize-VSCodeRuntime' -Refresh
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [switch]$Refresh
    )

    $descriptor = Get-ManifestedGitHubPortableRuntimeDescriptor -CommandName $CommandName
    $LocalRoot = (Get-ManifestedLayout).LocalRoot
    $selfElevationContext = Get-ManifestedSelfElevationContext

    $actionsTaken = New-Object System.Collections.Generic.List[string]
    $repairResult = $null
    $packageInfo = $null
    $packageTest = $null
    $installResult = $null
    $commandEnvironment = $null

    $stateParameters = Get-ManifestedGitHubPortableStateParameters -Descriptor $descriptor -LocalRoot $LocalRoot
    $initialState = & $descriptor.StateFunctionName @stateParameters
    $state = $initialState
    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($state.Status -eq 'Blocked') {
        $commandEnvironment = Get-ManifestedCommandEnvironmentResult -CommandName $descriptor.InitializeCommandName -RuntimeState $state
        $result = New-ManifestedRuntimeResult -LocalRoot $state.LocalRoot -Layout $state.Layout -InitialState $initialState -FinalState $state -ActionTaken @('None') -PlannedActions @() -RestartRequired:$false -AdditionalProperties ([ordered]@{
            Package            = $null
            PackageTest        = $null
            RuntimeTest        = $null
            RepairResult       = $null
            InstallResult      = $null
            CommandEnvironment = $commandEnvironment
            Elevation          = $elevationPlan
        })

        return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -Result $result -LocalRoot $LocalRoot -Details (Get-ManifestedGitHubPortablePersistedDetails -Descriptor $descriptor -FinalState $state -PackageInfo $null) -PersistState:(-not $WhatIfPreference))
    }

    $needsRepair = $state.Status -in @('Partial', 'NeedsRepair')
    $needsInstall = $Refresh -or -not $state.RuntimeHome
    $needsAcquire = $Refresh -or (-not $state.PackagePath)
    $plannedActions = @(Get-ManifestedGitHubPortablePlannedActions -Descriptor $descriptor -NeedsRepair:$needsRepair -NeedsInstall:$needsInstall -NeedsAcquire:$needsAcquire)
    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName $descriptor.InitializeCommandName -PlannedActions @($plannedActions) -LocalRoot $LocalRoot -SkipSelfElevation:$selfElevationContext.SkipSelfElevation -WasSelfElevated:$selfElevationContext.WasSelfElevated -WhatIfMode:$WhatIfPreference

    if ($needsRepair) {
        $repairTarget = if ($state.Layout -and $descriptor.ToolsRootPropertyName -and $state.Layout.PSObject.Properties[$descriptor.ToolsRootPropertyName]) { $state.Layout.($descriptor.ToolsRootPropertyName) } else { $state.LocalRoot }
        if (-not $PSCmdlet.ShouldProcess($repairTarget, ('Repair {0} runtime state' -f $descriptor.DisplayName))) {
            return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -PersistState:$false -Result (
                New-ManifestedRuntimeResult -LocalRoot $state.LocalRoot -Layout $state.Layout -InitialState $initialState -FinalState $state -ActionTaken @('WhatIf') -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
                    Package            = $null
                    PackageTest        = $null
                    RuntimeTest        = $state.Runtime
                    RepairResult       = $null
                    InstallResult      = $null
                    CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName $descriptor.InitializeCommandName -RuntimeState $state)
                    Elevation          = $elevationPlan
                })
            ))
        }

        $repairParameters = Get-ManifestedGitHubPortableRepairParameters -Descriptor $descriptor -RuntimeState $state -LocalRoot $state.LocalRoot
        $repairResult = & $descriptor.RepairFunctionName @repairParameters
        if ($repairResult.Action -eq 'Repaired') {
            $actionsTaken.Add($descriptor.RepairFunctionName) | Out-Null
        }

        $stateParameters = Get-ManifestedGitHubPortableStateParameters -Descriptor $descriptor -RuntimeState $state -LocalRoot $state.LocalRoot
        $state = & $descriptor.StateFunctionName @stateParameters
        $needsInstall = $Refresh -or -not $state.RuntimeHome
        $needsAcquire = $Refresh -or (-not $state.PackagePath)
    }

    if ($needsInstall) {
        if ($needsAcquire) {
            $acquireTarget = if ($state.Layout -and $descriptor.CacheRootPropertyName -and $state.Layout.PSObject.Properties[$descriptor.CacheRootPropertyName]) { $state.Layout.($descriptor.CacheRootPropertyName) } else { $state.LocalRoot }
            if (-not $PSCmdlet.ShouldProcess($acquireTarget, ('Acquire {0} runtime package' -f $descriptor.DisplayName))) {
                return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -PersistState:$false -Result (
                    New-ManifestedRuntimeResult -LocalRoot $state.LocalRoot -Layout $state.Layout -InitialState $initialState -FinalState $state -ActionTaken @('WhatIf') -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
                        Package            = $null
                        PackageTest        = $null
                        RuntimeTest        = $state.Runtime
                        RepairResult       = $repairResult
                        InstallResult      = $null
                        CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName $descriptor.InitializeCommandName -RuntimeState $state)
                        Elevation          = $elevationPlan
                    })
                ))
            }

            $savePackageParameters = Get-ManifestedGitHubPortableSavePackageParameters -Descriptor $descriptor -Refresh:[bool]$Refresh -RuntimeState $state -LocalRoot $state.LocalRoot
            $packageInfo = & $descriptor.SavePackageFunctionName @savePackageParameters
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
                        Package            = $packageInfo
                        PackageTest        = $packageTest
                        RuntimeTest        = $state.Runtime
                        RepairResult       = $repairResult
                        InstallResult      = $null
                        CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName $descriptor.InitializeCommandName -RuntimeState $state)
                        Elevation          = $elevationPlan
                    })
                ))
            }

            $repairParameters = Get-ManifestedGitHubPortableRepairParameters -Descriptor $descriptor -RuntimeState $state -CorruptPackagePaths @($packageInfo.Path) -LocalRoot $state.LocalRoot
            $repairResult = & $descriptor.RepairFunctionName @repairParameters
            if ($repairResult.Action -eq 'Repaired') {
                $actionsTaken.Add($descriptor.RepairFunctionName) | Out-Null
            }

            $savePackageParameters = Get-ManifestedGitHubPortableSavePackageParameters -Descriptor $descriptor -Refresh:$true -RuntimeState $state -LocalRoot $state.LocalRoot
            $packageInfo = & $descriptor.SavePackageFunctionName @savePackageParameters
            if ($packageInfo.Action -eq 'Downloaded') {
                $actionsTaken.Add($descriptor.SavePackageFunctionName) | Out-Null
            }

            $packageTest = & $descriptor.TestPackageFunctionName -PackageInfo $packageInfo
        }

        if ($packageTest.Status -eq 'UnverifiedCache') {
            throw ('{0} runtime package validation failed because no trusted checksum could be resolved for {1}.' -f $descriptor.DisplayName, $packageInfo.FileName)
        }

        if ($packageTest.Status -ne 'Ready') {
            throw ('{0} runtime package validation failed with status {1}.' -f $descriptor.DisplayName, $packageTest.Status)
        }

        $commandParameters = @{}
        if ($Refresh -and $descriptor.RefreshParameterName) {
            $commandParameters[$descriptor.RefreshParameterName] = $true
        }
        if ($PSBoundParameters.ContainsKey('WhatIf')) {
            $commandParameters['WhatIf'] = $true
        }

        $elevatedResult = Invoke-ManifestedElevatedCommand -ElevationPlan $elevationPlan -CommandName $descriptor.InitializeCommandName -CommandParameters $commandParameters
        if ($null -ne $elevatedResult) {
            return $elevatedResult
        }

        $installTarget = if ($state.Layout -and $descriptor.ToolsRootPropertyName -and $state.Layout.PSObject.Properties[$descriptor.ToolsRootPropertyName]) { $state.Layout.($descriptor.ToolsRootPropertyName) } else { $state.LocalRoot }
        if (-not $PSCmdlet.ShouldProcess($installTarget, ('Install {0} runtime' -f $descriptor.DisplayName))) {
            return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -PersistState:$false -Result (
                New-ManifestedRuntimeResult -LocalRoot $state.LocalRoot -Layout $state.Layout -InitialState $initialState -FinalState $state -ActionTaken @('WhatIf') -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
                    Package            = $packageInfo
                    PackageTest        = $packageTest
                    RuntimeTest        = $state.Runtime
                    RepairResult       = $repairResult
                    InstallResult      = $null
                    CommandEnvironment = (Get-ManifestedCommandEnvironmentResult -CommandName $descriptor.InitializeCommandName -RuntimeState $state)
                    Elevation          = $elevationPlan
                })
            ))
        }

        $installParameters = Get-ManifestedGitHubPortableInstallParameters -Descriptor $descriptor -PackageInfo $packageInfo -RuntimeState $state -LocalRoot $state.LocalRoot
        $installResult = & $descriptor.InstallFunctionName @installParameters
        if ($installResult.Action -eq 'Installed') {
            $actionsTaken.Add($descriptor.InstallFunctionName) | Out-Null
        }
    }

    $stateParameters = Get-ManifestedGitHubPortableStateParameters -Descriptor $descriptor -RuntimeState $state -LocalRoot $state.LocalRoot
    $finalState = & $descriptor.StateFunctionName @stateParameters
    $runtimeTest = if ($finalState.RuntimeHome) {
        $runtimeTestParameters = Get-ManifestedGitHubPortableRuntimeTestParameters -Descriptor $descriptor -RuntimeState $finalState
        & $descriptor.RuntimeTestFunctionName @runtimeTestParameters
    }
    else {
        $null
    }

    $commandEnvironmentSync = Invoke-ManifestedRuntimeCommandEnvironmentSync -Cmdlet $PSCmdlet -CommandName $descriptor.InitializeCommandName -DisplayName $descriptor.DisplayName -RuntimeState $finalState -ActionsTaken $actionsTaken -UseShouldProcess:$true
    $commandEnvironment = $commandEnvironmentSync.CommandEnvironment
    if ($commandEnvironmentSync.StopProcessing) {
        return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -LocalRoot $LocalRoot -PersistState:$false -Result (
            New-ManifestedRuntimeResult -LocalRoot $finalState.LocalRoot -Layout $finalState.Layout -InitialState $initialState -FinalState $finalState -ActionTaken @('WhatIf') -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
                Package            = $packageInfo
                PackageTest        = $packageTest
                RuntimeTest        = $runtimeTest
                RepairResult       = $repairResult
                InstallResult      = $installResult
                CommandEnvironment = $commandEnvironment
                Elevation          = $elevationPlan
            })
        ))
    }

    $result = New-ManifestedRuntimeResult -LocalRoot $finalState.LocalRoot -Layout $finalState.Layout -InitialState $initialState -FinalState $finalState -ActionTaken (if ($actionsTaken.Count -gt 0) { @($actionsTaken) } else { @('None') }) -PlannedActions @($plannedActions) -RestartRequired:$false -AdditionalProperties ([ordered]@{
        Package            = $packageInfo
        PackageTest        = $packageTest
        RuntimeTest        = $runtimeTest
        RepairResult       = $repairResult
        InstallResult      = $installResult
        CommandEnvironment = $commandEnvironment
        Elevation          = $elevationPlan
    })

    return (Complete-ManifestedRuntimeResult -CommandName $descriptor.InitializeCommandName -Result $result -LocalRoot $LocalRoot -Details (Get-ManifestedGitHubPortablePersistedDetails -Descriptor $descriptor -FinalState $finalState -PackageInfo $packageInfo) -PersistState:(-not $WhatIfPreference))
}
