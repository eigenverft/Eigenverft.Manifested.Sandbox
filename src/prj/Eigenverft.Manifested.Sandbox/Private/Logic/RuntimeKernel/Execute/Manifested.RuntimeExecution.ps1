function Invoke-ManifestedDescriptorRepairStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [Parameter(Mandatory = $true)]
        [hashtable]$CommandOptions
    )

    $facts = Get-ManifestedRuntimeFactsFromContext -Context $Descriptor -LocalRoot $CommandOptions.LocalRoot -FactsCache $(if ($CommandOptions.ContainsKey('FactsCache')) { $CommandOptions['FactsCache'] } else { @{} })
    $rawResult = if ($Descriptor.PSObject.Properties['ExecutionModel'] -and $Descriptor.ExecutionModel -eq 'DefinitionBlocks' -and $Descriptor.Definition) {
        Invoke-ManifestedRuntimeRepairFromDefinition -Definition $Descriptor.Definition -Facts $facts -LocalRoot $CommandOptions.LocalRoot
    }
    else {
        & $Descriptor.RepairFunction -State $facts -LocalRoot $CommandOptions.LocalRoot
    }

    return [pscustomobject]@{
        Changed         = ($rawResult -and $rawResult.PSObject.Properties['Action'] -and ($rawResult.Action -ne 'Skipped'))
        RestartRequired = $false
        Result          = $rawResult
        Warnings        = @()
        Dependency      = $null
    }
}

function Invoke-ManifestedDescriptorEnsureArtifactStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [Parameter(Mandatory = $true)]
        [hashtable]$CommandOptions
    )

    $facts = Get-ManifestedRuntimeFactsFromContext -Context $Descriptor -LocalRoot $CommandOptions.LocalRoot -FactsCache $(if ($CommandOptions.ContainsKey('FactsCache')) { $CommandOptions['FactsCache'] } else { @{} })
    $artifact = if ($facts.PSObject.Properties['Package']) { $facts.Package } elseif ($facts.PSObject.Properties['Artifact']) { $facts.Artifact } else { $null }
    $artifactPath = if ($facts.PSObject.Properties['PackagePath']) { $facts.PackagePath } elseif ($facts.PSObject.Properties['ArtifactPath']) { $facts.ArtifactPath } else { $null }
    $refreshRequested = [bool]$CommandOptions.RefreshRequested
    $needsAcquire = $refreshRequested -or [string]::IsNullOrWhiteSpace($artifactPath)

    if (-not $needsAcquire -and $Descriptor.PSObject.Properties['RequireTrustedArtifact'] -and $Descriptor.RequireTrustedArtifact) {
        $needsAcquire = -not $facts.ArtifactIsTrusted
    }

    if ($needsAcquire) {
        $artifact = if ($Descriptor.PSObject.Properties['ExecutionModel'] -and $Descriptor.ExecutionModel -eq 'DefinitionBlocks' -and $Descriptor.Definition) {
            Get-ManifestedSuppliedArtifactFromDefinition -Definition $Descriptor.Definition -RefreshRequested:$refreshRequested -LocalRoot $CommandOptions.LocalRoot
        }
        else {
            $acquireParameters = @{
                LocalRoot = $CommandOptions.LocalRoot
            }
            if ($Descriptor.PSObject.Properties['ArtifactAcquireRefreshParameterName'] -and -not [string]::IsNullOrWhiteSpace($Descriptor.ArtifactAcquireRefreshParameterName)) {
                $acquireParameters[$Descriptor.ArtifactAcquireRefreshParameterName] = $refreshRequested
            }

            & $Descriptor.EnsureArtifactFunction @acquireParameters
        }
    }

    if ($null -eq $artifact) {
        throw "The '$($Descriptor.RuntimeName)' artifact could not be resolved."
    }

    $validation = if ($Descriptor.PSObject.Properties['ExecutionModel'] -and $Descriptor.ExecutionModel -eq 'DefinitionBlocks' -and $Descriptor.Definition) {
        Test-ManifestedArtifactTrustFromDefinition -Definition $Descriptor.Definition -Artifact $artifact
    }
    else {
        $validationParameters = @{}
        $validationParameters[$Descriptor.ArtifactValidationParameterName] = $artifact
        & $Descriptor.ValidateArtifactFunction @validationParameters
    }

    if ($validation -and $validation.PSObject.Properties['CanRepair'] -and $validation.CanRepair) {
        if ($Descriptor.PSObject.Properties['ExecutionModel'] -and $Descriptor.ExecutionModel -eq 'DefinitionBlocks' -and $Descriptor.Definition) {
            Invoke-ManifestedRuntimeRepairFromDefinition -Definition $Descriptor.Definition -Facts $facts -CorruptArtifactPaths @($artifact.Path) -LocalRoot $CommandOptions.LocalRoot | Out-Null
            $artifact = Get-ManifestedSuppliedArtifactFromDefinition -Definition $Descriptor.Definition -RefreshRequested:$true -LocalRoot $CommandOptions.LocalRoot
            $validation = Test-ManifestedArtifactTrustFromDefinition -Definition $Descriptor.Definition -Artifact $artifact
        }
        elseif ($Descriptor.PSObject.Properties['RepairCorruptArtifactParameterName'] -and -not [string]::IsNullOrWhiteSpace($Descriptor.RepairCorruptArtifactParameterName)) {
            $repairParameters = @{
                State     = $facts
                LocalRoot = $CommandOptions.LocalRoot
            }
            $repairParameters[$Descriptor.RepairCorruptArtifactParameterName] = @($artifact.Path)
            & $Descriptor.RepairFunction @repairParameters | Out-Null

            $reacquireParameters = @{
                LocalRoot = $CommandOptions.LocalRoot
            }
            if ($Descriptor.PSObject.Properties['ArtifactAcquireRefreshParameterName'] -and -not [string]::IsNullOrWhiteSpace($Descriptor.ArtifactAcquireRefreshParameterName)) {
                $reacquireParameters[$Descriptor.ArtifactAcquireRefreshParameterName] = $true
            }

            $artifact = & $Descriptor.EnsureArtifactFunction @reacquireParameters
            $validationParameters = @{}
            $validationParameters[$Descriptor.ArtifactValidationParameterName] = $artifact
            $validation = & $Descriptor.ValidateArtifactFunction @validationParameters
        }
    }

    if ($validation -and $validation.PSObject.Properties['Exists'] -and -not $validation.Exists) {
        throw "$($Descriptor.RuntimeName) artifact validation failed because the artifact does not exist."
    }

    if ($validation -and $Descriptor.PSObject.Properties['RequireTrustedArtifact'] -and $Descriptor.RequireTrustedArtifact -and $validation.PSObject.Properties['IsTrusted'] -and -not $validation.IsTrusted) {
        $failureReason = if ($validation.PSObject.Properties['FailureReason']) { $validation.FailureReason } else { 'ArtifactNotTrusted' }
        throw "$($Descriptor.RuntimeName) artifact validation failed because the artifact is not trusted ($failureReason)."
    }

    return [pscustomobject]@{
        Changed         = [bool]$needsAcquire
        RestartRequired = $false
        Result          = [pscustomobject]@{
            Artifact   = $artifact
            Validation = $validation
        }
        Warnings        = @()
        Dependency      = $null
    }
}

function Invoke-ManifestedDescriptorInstallStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [Parameter(Mandatory = $true)]
        [hashtable]$CommandOptions
    )

    $facts = Get-ManifestedRuntimeFactsFromContext -Context $Descriptor -LocalRoot $CommandOptions.LocalRoot -FactsCache $(if ($CommandOptions.ContainsKey('FactsCache')) { $CommandOptions['FactsCache'] } else { @{} })
    $rawResult = if ($Descriptor.PSObject.Properties['ExecutionModel'] -and $Descriptor.ExecutionModel -eq 'DefinitionBlocks' -and $Descriptor.Definition) {
        Install-ManifestedRuntime -Definition $Descriptor.Definition -Facts $facts -RefreshRequested:$CommandOptions.RefreshRequested -CommandOptions $CommandOptions -LocalRoot $CommandOptions.LocalRoot
    }
    else {
        & $Descriptor.InstallActionFunction -Descriptor $Descriptor -Facts $facts -CommandOptions $CommandOptions
    }

    return [pscustomobject]@{
        Changed         = ($rawResult -and $rawResult.PSObject.Properties['Action'] -and ($rawResult.Action -ne 'Skipped'))
        RestartRequired = if ($rawResult -and $rawResult.PSObject.Properties['RestartRequired']) { [bool]$rawResult.RestartRequired } else { $false }
        Result          = $rawResult
        Warnings        = @()
        Dependency      = $null
    }
}

function Invoke-ManifestedDescriptorPostInstallStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [Parameter(Mandatory = $true)]
        [hashtable]$CommandOptions
    )

    $facts = Get-ManifestedRuntimeFactsFromContext -Context $Descriptor -LocalRoot $CommandOptions.LocalRoot -FactsCache $(if ($CommandOptions.ContainsKey('FactsCache')) { $CommandOptions['FactsCache'] } else { @{} })
    $rawResult = Invoke-ManifestedPostInstallSteps -Definition $Descriptor.Definition -Facts $facts -LocalRoot $CommandOptions.LocalRoot

    return [pscustomobject]@{
        Changed         = ($rawResult -and $rawResult.PSObject.Properties['Action'] -and ($rawResult.Action -notin @('Skipped', 'Reused')))
        RestartRequired = $false
        Result          = $rawResult
        Warnings        = @()
        Dependency      = $null
    }
}

function Invoke-ManifestedDescriptorEnvironmentSyncStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [Parameter(Mandatory = $true)]
        [hashtable]$CommandOptions
    )

    $facts = Get-ManifestedRuntimeFactsFromContext -Context $Descriptor -LocalRoot $CommandOptions.LocalRoot -FactsCache $(if ($CommandOptions.ContainsKey('FactsCache')) { $CommandOptions['FactsCache'] } else { @{} })
    $environmentResult = Get-ManifestedCommandEnvironmentResult -Descriptor $Descriptor -Facts $facts
    if (-not $environmentResult.Applicable -or $environmentResult.IsAligned) {
        return [pscustomobject]@{
            Changed         = $false
            RestartRequired = $false
            Result          = $environmentResult
            Warnings        = @()
            Dependency      = $null
        }
    }

    $syncedResult = Sync-ManifestedCommandLineEnvironment -Descriptor $Descriptor -Facts $facts

    return [pscustomobject]@{
        Changed         = [bool]($syncedResult.ProcessPathUpdated -or $syncedResult.UserPathUpdated)
        RestartRequired = $false
        Result          = $syncedResult
        Warnings        = @()
        Dependency      = $null
    }
}

function Invoke-ManifestedDependencyRuntimeStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Step
    )

    $commandParameters = @{}
    if ($Step.HandlerArguments.ContainsKey('RefreshParameterName') -and -not [string]::IsNullOrWhiteSpace($Step.HandlerArguments['RefreshParameterName']) -and $Step.HandlerArguments.ContainsKey('RefreshRequested') -and $Step.HandlerArguments['RefreshRequested']) {
        $commandParameters[$Step.HandlerArguments['RefreshParameterName']] = $true
    }

    $dependencyResult = & $Step.HandlerArguments['DependencyCommandName'] @commandParameters
    $dependencyChanged = $false
    if ($dependencyResult -and $dependencyResult.PSObject.Properties['ExecutedSteps']) {
        $dependencyChanged = (@($dependencyResult.ExecutedSteps | Where-Object { $_.Changed }).Count -gt 0)
    }

    return [pscustomobject]@{
        Changed         = $dependencyChanged
        RestartRequired = if ($dependencyResult -and $dependencyResult.PSObject.Properties['RestartRequired']) { [bool]$dependencyResult.RestartRequired } else { $false }
        Result          = $dependencyResult
        Warnings        = @()
        Dependency      = [pscustomobject]@{
            RuntimeName  = $Step.HandlerArguments['DependencyRuntimeName']
            CommandName  = $Step.HandlerArguments['DependencyCommandName']
            Result       = $dependencyResult
            WasExecuted  = $dependencyChanged
        }
    }
}

function Invoke-ManifestedRuntimePlanStep {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Step,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]$PSCmdletObject,

        [Parameter(Mandatory = $true)]
        [hashtable]$CommandOptions
    )

    if ($Step.IsMutation -and -not $PSCmdletObject.ShouldProcess($Step.Target, $Step.Action)) {
        return [pscustomobject]@{
            ExecutedStep = [pscustomobject]@{
                Name              = $Step.Name
                Kind              = $Step.Kind
                Reason            = $Step.Reason
                Action            = $Step.Action
                Target            = $Step.Target
                Changed           = $false
                RestartRequired   = $false
                Outcome           = 'Skipped'
                Result            = $null
                RequiresElevation = [bool]$Step.RequiresElevation
            }
            Dependency = $null
            Stopped    = $true
        }
    }

    $invokeParameters = @{
        Descriptor     = $Descriptor
        CommandOptions = $CommandOptions
    }
    foreach ($entry in $Step.HandlerArguments.GetEnumerator()) {
        $invokeParameters[$entry.Key] = $entry.Value
    }

    if ($CommandOptions.ContainsKey('FactsCache') -and $CommandOptions['FactsCache']) {
        $CommandOptions['FactsCache'].Clear()
    }

    $rawExecution = & $Step.HandlerFunction @invokeParameters

    return [pscustomobject]@{
        ExecutedStep = [pscustomobject]@{
            Name              = $Step.Name
            Kind              = $Step.Kind
            Reason            = $Step.Reason
            Action            = $Step.Action
            Target            = $Step.Target
            Changed           = [bool]$rawExecution.Changed
            RestartRequired   = [bool]$rawExecution.RestartRequired
            Outcome           = 'Executed'
            Result            = $rawExecution.Result
            RequiresElevation = [bool]$Step.RequiresElevation
        }
        Dependency = $rawExecution.Dependency
        Stopped    = $false
    }
}

function Invoke-ManifestedRuntimeInitialization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]$PSCmdletObject,

        [bool]$RefreshRequested = $false,

        [hashtable]$CommandOptions = @{},

        [switch]$WhatIfMode
    )

    $descriptor = Get-ManifestedCommandContext -CommandName $CommandName
    if (-not $descriptor) {
        throw "Could not resolve a runtime descriptor for command '$CommandName'."
    }

    $requestedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $localRoot = (Get-ManifestedLayout).LocalRoot
    $commandOptions = @{}
    foreach ($entry in $CommandOptions.GetEnumerator()) {
        $commandOptions[$entry.Key] = $entry.Value
    }
    $commandOptions['LocalRoot'] = $localRoot
    $commandOptions['RefreshRequested'] = [bool]$RefreshRequested
    $commandOptions['FactsCache'] = @{}

    $factsBefore = Get-ManifestedRuntimeFactsFromContext -Context $descriptor -LocalRoot $localRoot -FactsCache $commandOptions['FactsCache']
    $plan = @(Get-ManifestedCommandPlanFromContext -Context $descriptor -Facts $factsBefore -RefreshRequested:$RefreshRequested)
    $elevationPlan = Get-ManifestedCommandElevationPlan -CommandName $descriptor.CommandName -PlanSteps $plan -LocalRoot $localRoot -WhatIfMode:$WhatIfMode

    if ($WhatIfMode) {
        $factsAfter = Get-ManifestedRuntimeFactsFromContext -Context $descriptor -LocalRoot $localRoot -FactsCache @{}
        $environmentResult = $null
        if ($descriptor.PSObject.Properties['SupportsEnvironmentSync'] -and $descriptor.SupportsEnvironmentSync) {
            $environmentResult = Get-ManifestedCommandEnvironmentResult -Descriptor $descriptor -Facts $factsAfter
        }

        return [pscustomobject]@{
            CommandName       = $descriptor.CommandName
            RuntimeName       = $descriptor.RuntimeName
            FactsBefore       = $factsBefore
            Dependencies      = @()
            Plan              = @($plan | ForEach-Object { Convert-ManifestedPlanStepForOutput -Step $_ })
            ExecutedSteps     = @()
            FactsAfter        = $factsAfter
            EnvironmentResult = $environmentResult
            RestartRequired   = $false
            Warnings          = @()
            Errors            = @()
            Elevation         = $elevationPlan
        }
    }

    $elevatedCommandParameters = @{}
    if ($descriptor.PSObject.Properties['Definition'] -and $descriptor.Definition) {
        $refreshSwitchName = if ($descriptor.Definition.PSObject.Properties.Match('refreshSwitchName').Count -gt 0) { $descriptor.Definition.refreshSwitchName } else { $null }
        if (-not [string]::IsNullOrWhiteSpace($refreshSwitchName) -and $RefreshRequested) {
            $elevatedCommandParameters[$refreshSwitchName] = $true
        }
    }
    foreach ($entry in $CommandOptions.GetEnumerator()) {
        if ($entry.Key -in @('LocalRoot', 'RefreshRequested')) {
            continue
        }
        if ($null -ne $entry.Value) {
            $elevatedCommandParameters[$entry.Key] = $entry.Value
        }
    }

    $elevatedResult = Invoke-ManifestedElevatedCommand -ElevationPlan $elevationPlan -CommandName $descriptor.CommandName -CommandParameters $elevatedCommandParameters
    if ($null -ne $elevatedResult) {
        return $elevatedResult
    }

    $executedSteps = New-Object System.Collections.Generic.List[object]
    $dependencyReports = New-Object System.Collections.Generic.List[object]
    $restartRequired = $false

    foreach ($step in @($plan)) {
        $execution = Invoke-ManifestedRuntimePlanStep -Descriptor $descriptor -Step $step -PSCmdletObject $PSCmdletObject -CommandOptions $commandOptions
        $executedSteps.Add($execution.ExecutedStep) | Out-Null

        if ($execution.Dependency) {
            $dependencyReports.Add($execution.Dependency) | Out-Null
        }

        if ($execution.ExecutedStep.RestartRequired) {
            $restartRequired = $true
        }

        if ($execution.Stopped) {
            break
        }
    }

    $factsAfter = Get-ManifestedRuntimeFactsFromContext -Context $descriptor -LocalRoot $localRoot -FactsCache @{}
    $environmentResult = $null
    if ($descriptor.PSObject.Properties['SupportsEnvironmentSync'] -and $descriptor.SupportsEnvironmentSync) {
        $environmentResult = Get-ManifestedCommandEnvironmentResult -Descriptor $descriptor -Facts $factsAfter
    }

    $result = [pscustomobject]@{
        CommandName       = $descriptor.CommandName
        RuntimeName       = $descriptor.RuntimeName
        FactsBefore       = $factsBefore
        Dependencies      = @($dependencyReports)
        Plan              = @($plan | ForEach-Object { Convert-ManifestedPlanStepForOutput -Step $_ })
        ExecutedSteps     = @($executedSteps)
        FactsAfter        = $factsAfter
        EnvironmentResult = $environmentResult
        RestartRequired   = [bool]$restartRequired
        Warnings          = @()
        Errors            = @()
        Elevation         = $elevationPlan
    }

    Save-ManifestedCommandReport -CommandName $descriptor.CommandName -RuntimeName $descriptor.RuntimeName -Result $result -InvocationInput @{
        RefreshRequested = [bool]$RefreshRequested
        WhatIfMode       = [bool]$WhatIfMode
        Options          = [pscustomobject]$elevatedCommandParameters
    } -RequestedAtUtc $requestedAtUtc -CompletedAtUtc ((Get-Date).ToUniversalTime().ToString('o')) -LocalRoot $localRoot | Out-Null

    return $result
}

function Invoke-ManifestedCommandInitialization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]$PSCmdletObject,

        [bool]$RefreshRequested = $false,

        [hashtable]$CommandOptions = @{},

        [switch]$WhatIfMode
    )

    $definition = Get-ManifestedCommandDefinition -Name $Name
    if (-not $definition) {
        throw "Could not resolve a packaged command definition for '$Name'."
    }

    return (Invoke-ManifestedRuntimeInitialization -CommandName $definition.commandName -PSCmdletObject $PSCmdletObject -RefreshRequested:$RefreshRequested -CommandOptions $CommandOptions -WhatIfMode:$WhatIfMode)
}

