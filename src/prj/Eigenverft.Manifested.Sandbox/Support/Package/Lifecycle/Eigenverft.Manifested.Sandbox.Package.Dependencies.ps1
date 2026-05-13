<#
    Eigenverft.Manifested.Sandbox.Package.Dependencies
#>

function Resolve-PackageDependencyStack {
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

function Get-PackageDependencyReferenceKey {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$RepositoryId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DefinitionId
    )

    $repositoryKey = if ([string]::IsNullOrWhiteSpace($RepositoryId)) { '*' } else { [string]$RepositoryId }
    return ('{0}:{1}' -f $repositoryKey, $DefinitionId)
}

function Get-PackageResultRepositoryId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    if ($PackageResult.PSObject.Properties['RepositoryId'] -and
        -not [string]::IsNullOrWhiteSpace([string]$PackageResult.RepositoryId)) {
        return [string]$PackageResult.RepositoryId
    }
    if ($PackageResult.PackageConfig -and
        $PackageResult.PackageConfig.PSObject.Properties['DefinitionRepositoryId'] -and
        -not [string]::IsNullOrWhiteSpace([string]$PackageResult.PackageConfig.DefinitionRepositoryId)) {
        return [string]$PackageResult.PackageConfig.DefinitionRepositoryId
    }

    return (Get-PackageDefaultRepositoryId)
}

function Resolve-PackageDependencyRepositoryId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult,

        [Parameter(Mandatory = $true)]
        [psobject]$Dependency
    )

    if ($Dependency.PSObject.Properties['repositoryId']) {
        if ([string]::IsNullOrWhiteSpace([string]$Dependency.repositoryId)) {
            throw "Package definition '$($PackageResult.DefinitionId)' has dependency '$($Dependency.definitionId)' with empty repositoryId."
        }
        return [string]$Dependency.repositoryId
    }

    return $null
}

function Resolve-PackageDependencyCommandEntryPoints {
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

function Resolve-PackageDependencyDefinition {
<#
.SYNOPSIS
Ensures a dependency definition is ready for a parent Package operation.

.DESCRIPTION
This first-pass seam inherits the parent repository id. Later repository-aware
dependency logic can extend this function without changing the command flow.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DefinitionId,

        [AllowNull()]
        [string]$RepositoryId,

        [object[]]$DependencyStack = @()
    )

    return (Invoke-PackageDefinitionCommandCore -RepositoryId $RepositoryId -DefinitionId $DefinitionId -DesiredState Assigned -DependencyStack $DependencyStack)
}

function Resolve-PackageDependencies {
<#
.SYNOPSIS
Ensures direct Package dependencies for the selected definition.

.DESCRIPTION
Runs definition-level dependencies before acquisition/install. This is a
minimal direct dependency pass, not a general dependency graph solver.

.PARAMETER PackageResult
The current Package result object.

.EXAMPLE
Resolve-PackageDependencies -PackageResult $result
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult,

        [object[]]$DependencyStack = @()
    )

    $definition = $PackageResult.PackageConfig.Definition
    $dependencyRecords = New-Object System.Collections.Generic.List[object]
    $seenDependencyIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    if (-not $definition.PSObject.Properties['dependencies'] -or $null -eq $definition.dependencies) {
        $PackageResult.Dependencies = @()
        return $PackageResult
    }

    $currentStack = @(Resolve-PackageDependencyStack -DependencyStack $DependencyStack)
    $parentRepositoryId = Get-PackageResultRepositoryId -PackageResult $PackageResult
    if (-not $currentStack) {
        $currentStack = @(Get-PackageDependencyReferenceKey -RepositoryId $parentRepositoryId -DefinitionId ([string]$PackageResult.DefinitionId))
    }

    foreach ($dependency in @($definition.dependencies)) {
        if (-not $dependency.PSObject.Properties['definitionId'] -or [string]::IsNullOrWhiteSpace([string]$dependency.definitionId)) {
            throw "Package definition '$($definition.id)' has dependency without definitionId."
        }

        $dependencyDefinitionId = [string]$dependency.definitionId
        $dependencyRepositoryId = Resolve-PackageDependencyRepositoryId -PackageResult $PackageResult -Dependency $dependency
        $dependencyKey = Get-PackageDependencyReferenceKey -RepositoryId $dependencyRepositoryId -DefinitionId $dependencyDefinitionId
        $currentKey = Get-PackageDependencyReferenceKey -RepositoryId $parentRepositoryId -DefinitionId ([string]$PackageResult.DefinitionId)
        if ([string]::Equals($dependencyDefinitionId, [string]$PackageResult.DefinitionId, [System.StringComparison]::OrdinalIgnoreCase) -and
            ([string]::IsNullOrWhiteSpace($dependencyRepositoryId) -or [string]::Equals($dependencyRepositoryId, $parentRepositoryId, [System.StringComparison]::OrdinalIgnoreCase))) {
            throw "Package definition '$($PackageResult.DefinitionId)' cannot depend on itself."
        }
        if (-not $seenDependencyIds.Add($dependencyKey)) {
            continue
        }
        $dependencyKeyAlreadyInStack = ($currentStack -contains $dependencyKey)
        if (-not $dependencyKeyAlreadyInStack -and [string]::IsNullOrWhiteSpace($dependencyRepositoryId)) {
            foreach ($stackEntry in @($currentStack)) {
                if ([string]::Equals(([string]$stackEntry).Split(':')[-1], $dependencyDefinitionId, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $dependencyKeyAlreadyInStack = $true
                    break
                }
            }
        }
        if ($dependencyKeyAlreadyInStack) {
            throw ("Package dependency cycle detected: {0} -> {1}." -f (($currentStack -join ' -> ')), $dependencyKey)
        }

        $dependencyRepositoryText = if ([string]::IsNullOrWhiteSpace($dependencyRepositoryId)) { '<active repositories>' } else { $dependencyRepositoryId }
        Write-PackageExecutionMessage -Message ("[STEP] Ensuring package dependency '{0}' from repository '{1}'." -f $dependencyDefinitionId, $dependencyRepositoryText)
        $dependencyResult = Resolve-PackageDependencyDefinition -PackageResult $PackageResult -RepositoryId $dependencyRepositoryId -DefinitionId $dependencyDefinitionId -DependencyStack (@($currentStack) + $dependencyKey)
        $resolvedDependencyRepositoryId = if ($dependencyResult -and $dependencyResult.PSObject.Properties['RepositoryId']) { [string]$dependencyResult.RepositoryId } else { $dependencyRepositoryId }
        $dependencyStatus = if ($dependencyResult) { [string]$dependencyResult.Status } else { '<none>' }
        if (-not $dependencyResult -or -not [string]::Equals($dependencyStatus, 'Ready', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package dependency '$dependencyRepositoryText/$dependencyDefinitionId' did not become ready. Status='$dependencyStatus'."
        }

        $dependencyRecords.Add([pscustomobject]@{
            RepositoryId   = $resolvedDependencyRepositoryId
            DefinitionId   = $dependencyDefinitionId
            Status         = $dependencyStatus
            InstallOrigin  = [string]$dependencyResult.InstallOrigin
            InstallStatus  = if ($dependencyResult.Assigned -and $dependencyResult.Assigned.PSObject.Properties['Status']) { [string]$dependencyResult.Assigned.Status } else { $null }
            EntryPoints    = if ($dependencyResult.PSObject.Properties['EntryPoints']) { $dependencyResult.EntryPoints } else { $null }
            Commands       = @(Resolve-PackageDependencyCommandEntryPoints -DependencyResult $dependencyResult)
            Result         = $dependencyResult
        }) | Out-Null

        Write-PackageExecutionMessage -Message ("[STATE] Package dependency ready: repository='{0}', definition='{1}', installOrigin='{2}', installStatus='{3}'." -f $resolvedDependencyRepositoryId, $dependencyDefinitionId, [string]$dependencyResult.InstallOrigin, $(if ($dependencyResult.Assigned -and $dependencyResult.Assigned.PSObject.Properties['Status']) { [string]$dependencyResult.Assigned.Status } else { '<none>' }))
    }

    $PackageResult.Dependencies = @($dependencyRecords.ToArray())
    return $PackageResult
}

function Resolve-PackageDependencyCommandPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CommandName
    )

    foreach ($dependency in @($PackageResult.Dependencies)) {
        foreach ($command in @(Resolve-PackageDependencyCommandEntryPoints -DependencyResult $dependency)) {
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

    throw "Package install for '$($PackageResult.PackageId)' requires installer command '$CommandName', but no ready dependency exposes that command."
}
