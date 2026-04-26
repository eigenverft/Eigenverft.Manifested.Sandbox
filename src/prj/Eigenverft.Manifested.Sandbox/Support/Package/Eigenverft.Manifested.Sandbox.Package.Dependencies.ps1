<#
    Eigenverft.Manifested.Sandbox.Package.Dependencies
#>

function Resolve-PackageModelDependencyStack {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$DependencyStack
    )

    if ($DependencyStack) {
        return @($DependencyStack | ForEach-Object { [string]$_ })
    }

    return @()
}

function Resolve-PackageModelDependencyCommandEntryPoints {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [psobject]$DependencyResult
    )

    if (-not $DependencyResult -or -not $DependencyResult.PSObject.Properties['EntryPoints'] -or -not $DependencyResult.EntryPoints) {
        if ($DependencyResult -and $DependencyResult.PSObject.Properties['Commands']) {
            return @($DependencyResult.Commands)
        }
        return @()
    }
    if (-not $DependencyResult.EntryPoints.PSObject.Properties['Commands']) {
        return @()
    }

    return @($DependencyResult.EntryPoints.Commands)
}

function Resolve-PackageModelDependencies {
<#
.SYNOPSIS
Ensures direct PackageModel dependencies for the selected definition.

.DESCRIPTION
Runs definition-level dependencies before acquisition/install. This is a
minimal direct dependency pass, not a general dependency graph solver.

.PARAMETER PackageModelResult
The current PackageModel result object.

.EXAMPLE
Resolve-PackageModelDependencies -PackageModelResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult,

        [object[]]$DependencyStack = @()
    )

    $definition = $PackageModelResult.PackageModelConfig.Definition
    $dependencyRecords = New-Object System.Collections.Generic.List[object]
    $seenDependencyIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    if (-not $definition.PSObject.Properties['dependencies'] -or $null -eq $definition.dependencies) {
        $PackageModelResult.Dependencies = @()
        return $PackageModelResult
    }

    $currentStack = @(Resolve-PackageModelDependencyStack -DependencyStack $DependencyStack)
    if (-not $currentStack) {
        $currentStack = @([string]$PackageModelResult.DefinitionId)
    }

    foreach ($dependency in @($definition.dependencies)) {
        if (-not $dependency.PSObject.Properties['definitionId'] -or [string]::IsNullOrWhiteSpace([string]$dependency.definitionId)) {
            throw "PackageModel definition '$($definition.id)' has dependency without definitionId."
        }

        $dependencyDefinitionId = [string]$dependency.definitionId
        if ([string]::Equals($dependencyDefinitionId, [string]$PackageModelResult.DefinitionId, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "PackageModel definition '$($PackageModelResult.DefinitionId)' cannot depend on itself."
        }
        if (-not $seenDependencyIds.Add($dependencyDefinitionId)) {
            continue
        }
        if ($currentStack -contains $dependencyDefinitionId) {
            throw ("PackageModel dependency cycle detected: {0} -> {1}." -f (($currentStack -join ' -> ')), $dependencyDefinitionId)
        }

        Write-PackageModelExecutionMessage -Message ("[STEP] Ensuring package dependency '{0}'." -f $dependencyDefinitionId)
        $dependencyResult = Invoke-PackageModelDefinitionCommand -DefinitionId $dependencyDefinitionId -CommandName ("Invoke-{0}" -f $dependencyDefinitionId) -DependencyStack (@($currentStack) + $dependencyDefinitionId)
        $dependencyStatus = if ($dependencyResult) { [string]$dependencyResult.Status } else { '<none>' }
        if (-not $dependencyResult -or -not [string]::Equals($dependencyStatus, 'Ready', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "PackageModel dependency '$dependencyDefinitionId' did not become ready. Status='$dependencyStatus'."
        }

        $dependencyRecords.Add([pscustomobject]@{
            DefinitionId   = $dependencyDefinitionId
            Status         = $dependencyStatus
            InstallOrigin  = [string]$dependencyResult.InstallOrigin
            InstallStatus  = if ($dependencyResult.Install -and $dependencyResult.Install.PSObject.Properties['Status']) { [string]$dependencyResult.Install.Status } else { $null }
            EntryPoints    = if ($dependencyResult.PSObject.Properties['EntryPoints']) { $dependencyResult.EntryPoints } else { $null }
            Commands       = @(Resolve-PackageModelDependencyCommandEntryPoints -DependencyResult $dependencyResult)
            Result         = $dependencyResult
        }) | Out-Null

        Write-PackageModelExecutionMessage -Message ("[STATE] Package dependency ready: definition='{0}', installOrigin='{1}', installStatus='{2}'." -f $dependencyDefinitionId, [string]$dependencyResult.InstallOrigin, $(if ($dependencyResult.Install -and $dependencyResult.Install.PSObject.Properties['Status']) { [string]$dependencyResult.Install.Status } else { '<none>' }))
    }

    $PackageModelResult.Dependencies = @($dependencyRecords.ToArray())
    return $PackageModelResult
}

function Resolve-PackageModelDependencyCommandPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CommandName
    )

    foreach ($dependency in @($PackageModelResult.Dependencies)) {
        foreach ($command in @(Resolve-PackageModelDependencyCommandEntryPoints -DependencyResult $dependency)) {
            if ([string]::Equals([string]$command.Name, $CommandName, [System.StringComparison]::OrdinalIgnoreCase) -and
                -not [string]::IsNullOrWhiteSpace([string]$command.Path) -and
                (Test-Path -LiteralPath ([string]$command.Path) -PathType Leaf)) {
                return [pscustomobject]@{
                    DefinitionId = [string]$dependency.DefinitionId
                    Command      = $CommandName
                    CommandPath  = [System.IO.Path]::GetFullPath([string]$command.Path)
                }
            }
        }
    }

    throw "PackageModel install for '$($PackageModelResult.PackageId)' requires installer command '$CommandName', but no ready dependency exposes that command."
}
