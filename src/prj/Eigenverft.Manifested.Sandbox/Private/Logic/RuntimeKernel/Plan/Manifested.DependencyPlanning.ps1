function Get-ManifestedCommandPlanFromContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Facts,

        [bool]$RefreshRequested = $false
    )

    if ($Context.PSObject.Properties['ExecutionModel'] -and $Context.ExecutionModel -eq 'DefinitionBlocks' -and $Context.PSObject.Properties['Definition'] -and $Context.Definition) {
        if (Get-ManifestedDefinitionBlock -Definition $Context.Definition -SectionName 'facts' -BlockName 'npmCli') {
            return @(Get-ManifestedNpmCliRuntimePlan -Descriptor $Context -Facts $Facts -RefreshRequested:$RefreshRequested)
        }
        if (Get-ManifestedDefinitionBlock -Definition $Context.Definition -SectionName 'facts' -BlockName 'machinePrerequisite') {
            return @(Get-ManifestedMachinePrerequisiteRuntimePlan -Descriptor $Context -Facts $Facts -RefreshRequested:$RefreshRequested)
        }

        return @(Get-ManifestedPortableRuntimePlanFromFacts -Context $Context -Facts $Facts -RefreshRequested:$RefreshRequested)
    }

    return @(& $Context.PlanFunction -Descriptor $Context -Facts $Facts -RefreshRequested:$RefreshRequested)
}

function Test-ManifestedVersionSatisfiesMinimum {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$CurrentVersion,

        [string]$MinimumVersion
    )

    if ([string]::IsNullOrWhiteSpace($MinimumVersion)) {
        return $true
    }

    if ([string]::IsNullOrWhiteSpace($CurrentVersion)) {
        return $false
    }

    $normalizedCurrent = $CurrentVersion.Trim().TrimStart('v', 'V')
    $normalizedMinimum = $MinimumVersion.Trim().TrimStart('v', 'V')

    try {
        return ([version]$normalizedCurrent -ge [version]$normalizedMinimum)
    }
    catch {
        return ($normalizedCurrent -eq $normalizedMinimum)
    }
}

function Resolve-ManifestedCommandDependencies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [hashtable]$Visited = @{},

        [hashtable]$Visiting = @{},

        [System.Collections.Generic.List[object]]$Resolved
    )

    if ($null -eq $Resolved) {
        $Resolved = New-Object System.Collections.Generic.List[object]
    }

    if ($Visiting.ContainsKey($Definition.commandName)) {
        throw "Dependency cycle detected while resolving '$($Definition.commandName)'."
    }

    if ($Visited.ContainsKey($Definition.commandName)) {
        return $Resolved
    }

    $Visiting[$Definition.commandName] = $true

    foreach ($dependency in @($Definition.dependencies | Where-Object { $_.autoInstall })) {
        $dependencyDefinition = Get-ManifestedCommandDefinition -RuntimeName $dependency.runtimeName
        if (-not $dependencyDefinition) {
            throw "Command definition '$($Definition.commandName)' references unknown dependency runtime '$($dependency.runtimeName)'."
        }

        [void](Resolve-ManifestedCommandDependencies -Definition $dependencyDefinition -Visited $Visited -Visiting $Visiting -Resolved $Resolved)

        $alreadyResolved = $false
        foreach ($resolvedDependency in @($Resolved)) {
            if ($resolvedDependency.RuntimeName -eq $dependencyDefinition.runtimeName) {
                $alreadyResolved = $true
                break
            }
        }

        if (-not $alreadyResolved) {
            $Resolved.Add([pscustomobject]@{
                RuntimeName = $dependencyDefinition.runtimeName
                Definition  = $dependencyDefinition
                Dependency  = $dependency
            }) | Out-Null
        }
    }

    $Visiting.Remove($Definition.commandName) | Out-Null
    $Visited[$Definition.commandName] = $true
    return $Resolved
}

function Test-ManifestedRuntimeDependencySatisfied {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Dependency,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Facts,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$OwningDefinition
    )

    if (-not $Facts -or -not $Facts.PSObject.Properties['HasUsableRuntime'] -or -not $Facts.HasUsableRuntime) {
        return $false
    }

    $allowedSources = switch ($Dependency.satisfactionMode) {
        'managed-only' { @('Managed') }
        'external-only' { @('External') }
        'managed-or-external' { @('Managed', 'External') }
        default {
            if ($OwningDefinition.policies.allowExternalSatisfaction) { @('Managed', 'External') } else { @('Managed') }
        }
    }

    if ($allowedSources -notcontains $Facts.RuntimeSource) {
        return $false
    }

    return (Test-ManifestedVersionSatisfiesMinimum -CurrentVersion $Facts.CurrentVersion -MinimumVersion $Dependency.minimumVersion)
}

function Get-ManifestedDependencyPlanFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Facts,

        [bool]$RefreshRequested = $false,

        [hashtable]$FactsCache = @{}
    )

    $steps = New-Object System.Collections.Generic.List[object]
    if (-not $Context.PSObject.Properties['Definition'] -or -not $Context.Definition) {
        return $steps.ToArray()
    }

    foreach ($resolvedDependency in @(Resolve-ManifestedCommandDependencies -Definition $Context.Definition)) {
        $dependencyContext = Get-ManifestedRuntimeContext -RuntimeName $resolvedDependency.RuntimeName
        if (-not $dependencyContext) {
            throw "Could not resolve a runtime context for dependency '$($resolvedDependency.RuntimeName)'."
        }

        $dependencyFacts = Get-ManifestedRuntimeFactsFromContext -Context $dependencyContext -LocalRoot $Facts.LocalRoot -FactsCache $FactsCache
        if (Test-ManifestedRuntimeDependencySatisfied -Dependency $resolvedDependency.Dependency -Facts $dependencyFacts -OwningDefinition $Context.Definition) {
            continue
        }

        $steps.Add((New-ManifestedPlanStep -Name ('EnsureDependency_' + $resolvedDependency.RuntimeName) -Kind 'Dependency' -Reason $resolvedDependency.Dependency.reason -Action ('Initialize ' + $resolvedDependency.RuntimeName + ' dependency') -Target $dependencyContext.InstallTarget -HandlerFunction 'Invoke-ManifestedDependencyRuntimeStep' -HandlerArguments @{
                    DependencyRuntimeName = $resolvedDependency.RuntimeName
                    DependencyCommandName = $resolvedDependency.Definition.commandName
                    RefreshParameterName  = $resolvedDependency.Definition.refreshSwitchName
                    RefreshRequested      = [bool]$RefreshRequested
                })) | Out-Null
    }

    return $steps.ToArray()
}

function Get-ManifestedPortableRuntimePlanFromFacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Context,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Facts,

        [bool]$RefreshRequested = $false
    )

    $steps = New-Object System.Collections.Generic.List[object]
    if (-not $Facts.PlatformSupported) {
        return $steps.ToArray()
    }

    foreach ($dependencyStep in @(Get-ManifestedDependencyPlanFromDefinition -Context $Context -Facts $Facts -RefreshRequested:$RefreshRequested)) {
        $steps.Add($dependencyStep) | Out-Null
    }

    if ($Facts.HasRepairableResidue) {
        $steps.Add((New-ManifestedPlanStep -Name 'RepairRuntimeArtifacts' -Kind 'Repair' -Reason 'Remove invalid or partial managed artifacts before recomputing the runtime.' -Action ('Repair ' + $Context.RuntimeName + ' artifacts') -Target $Context.RepairTarget -HandlerFunction 'Invoke-ManifestedDescriptorRepairStep')) | Out-Null
    }

    $needsInstall = $RefreshRequested -or (-not $Facts.HasUsableRuntime)
    if ($needsInstall) {
        $steps.Add((New-ManifestedPlanStep -Name 'EnsureInstallArtifact' -Kind 'EnsureArtifact' -Reason 'Acquire and validate the install artifact required for a managed install.' -Action ('Ensure ' + $Context.RuntimeName + ' install artifact') -Target $Context.ArtifactTarget -HandlerFunction 'Invoke-ManifestedDescriptorEnsureArtifactStep')) | Out-Null
        $steps.Add((New-ManifestedPlanStep -Name 'InstallManagedRuntime' -Kind 'InstallRuntime' -Reason 'Install the managed runtime into the sandbox tools root.' -Action ('Install ' + $Context.RuntimeName) -Target $Context.InstallTarget -HandlerFunction 'Invoke-ManifestedDescriptorInstallStep')) | Out-Null
    }

    if ($Context.PSObject.Properties['Definition'] -and $Context.Definition -and (Get-ManifestedDefinitionBlock -Definition $Context.Definition -SectionName 'hooks' -BlockName 'postInstall') -and ($needsInstall -or $Facts.RuntimeSource -eq 'Managed')) {
        $steps.Add((New-ManifestedPlanStep -Name 'RunPostInstallHooks' -Kind 'PostInstall' -Reason 'Apply runtime-specific post-install normalization and bootstrap hooks.' -Action ('Run ' + $Context.RuntimeName + ' post-install hooks') -Target $Context.InstallTarget -HandlerFunction 'Invoke-ManifestedDescriptorPostInstallStep')) | Out-Null
    }

    if ($Context.PSObject.Properties['SupportsEnvironmentSync'] -and $Context.SupportsEnvironmentSync) {
        $steps.Add((New-ManifestedPlanStep -Name 'SyncCommandEnvironment' -Kind 'SyncEnvironment' -Reason 'Align command resolution with the effective runtime facts.' -Action ('Synchronize ' + $Context.RuntimeName + ' command-line environment') -Target $Context.EnvironmentTarget -HandlerFunction 'Invoke-ManifestedDescriptorEnvironmentSyncStep')) | Out-Null
    }

    return $steps.ToArray()
}

function Get-ManifestedNpmCliRuntimePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Facts,

        [bool]$RefreshRequested = $false
    )

    $steps = New-Object System.Collections.Generic.List[object]
    if (-not $Facts.PlatformSupported) {
        return $steps.ToArray()
    }

    $needsInstall = $RefreshRequested -or (-not $Facts.HasUsableRuntime)

    if ($needsInstall) {
        foreach ($dependencyStep in @(
            if ($Descriptor.PSObject.Properties['Definition'] -and $Descriptor.Definition) {
                Get-ManifestedDependencyPlanFromDefinition -Context $Descriptor -Facts $Facts -RefreshRequested:$RefreshRequested
            }
        )) {
            $steps.Add($dependencyStep) | Out-Null
        }
    }

    if ($Facts.HasRepairableResidue) {
        $steps.Add((New-ManifestedPlanStep -Name 'RepairRuntimeArtifacts' -Kind 'Repair' -Reason 'Remove invalid or partial managed artifacts before reinstalling the CLI.' -Action ('Repair ' + $Descriptor.RuntimeName + ' artifacts') -Target $Descriptor.RepairTarget -HandlerFunction 'Invoke-ManifestedDescriptorRepairStep')) | Out-Null
    }

    if ($needsInstall) {
        $steps.Add((New-ManifestedPlanStep -Name 'InstallManagedRuntime' -Kind 'InstallRuntime' -Reason 'Install the managed CLI runtime into the sandbox tools root.' -Action ('Install ' + $Descriptor.RuntimeName) -Target $Descriptor.InstallTarget -HandlerFunction 'Invoke-ManifestedDescriptorInstallStep')) | Out-Null
    }

    if ($Descriptor.PSObject.Properties['SupportsEnvironmentSync'] -and $Descriptor.SupportsEnvironmentSync) {
        $steps.Add((New-ManifestedPlanStep -Name 'SyncCommandEnvironment' -Kind 'SyncEnvironment' -Reason 'Align command resolution with the effective runtime facts.' -Action ('Synchronize ' + $Descriptor.RuntimeName + ' command-line environment') -Target $Descriptor.EnvironmentTarget -HandlerFunction 'Invoke-ManifestedDescriptorEnvironmentSyncStep')) | Out-Null
    }

    return $steps.ToArray()
}

function Get-ManifestedMachinePrerequisiteRuntimePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Descriptor,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Facts,

        [bool]$RefreshRequested = $false
    )

    $steps = New-Object System.Collections.Generic.List[object]
    if (-not $Facts.PlatformSupported) {
        return $steps.ToArray()
    }

    if ($Facts.HasRepairableResidue) {
        $steps.Add((New-ManifestedPlanStep -Name 'RepairInstallerArtifacts' -Kind 'Repair' -Reason 'Remove partial or corrupt prerequisite installer artifacts.' -Action ('Repair ' + $Descriptor.RuntimeName + ' artifacts') -Target $Descriptor.RepairTarget -HandlerFunction 'Invoke-ManifestedDescriptorRepairStep')) | Out-Null
    }

    $needsInstall = $RefreshRequested -or (-not $Facts.HasUsableRuntime)
    if ($needsInstall) {
        $steps.Add((New-ManifestedPlanStep -Name 'EnsureInstallArtifact' -Kind 'EnsureArtifact' -Reason 'Acquire and validate the prerequisite installer.' -Action ('Ensure ' + $Descriptor.RuntimeName + ' installer') -Target $Descriptor.ArtifactTarget -HandlerFunction 'Invoke-ManifestedDescriptorEnsureArtifactStep')) | Out-Null
        $steps.Add((New-ManifestedPlanStep -Name 'InstallRuntime' -Kind 'InstallRuntime' -Reason 'Install or repair the machine prerequisite.' -Action ('Install ' + $Descriptor.RuntimeName) -Target $Descriptor.InstallTarget -RequiresElevation:$Descriptor.InstallRequiresElevation -HandlerFunction 'Invoke-ManifestedDescriptorInstallStep')) | Out-Null
    }

    return $steps.ToArray()
}


