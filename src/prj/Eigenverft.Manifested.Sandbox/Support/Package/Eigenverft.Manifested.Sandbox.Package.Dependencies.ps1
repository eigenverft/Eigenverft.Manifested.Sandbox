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
    if (-not $currentStack) {
        $currentStack = @([string]$PackageResult.DefinitionId)
    }

    foreach ($dependency in @($definition.dependencies)) {
        if (-not $dependency.PSObject.Properties['definitionId'] -or [string]::IsNullOrWhiteSpace([string]$dependency.definitionId)) {
            throw "Package definition '$($definition.id)' has dependency without definitionId."
        }

        $dependencyDefinitionId = [string]$dependency.definitionId
        if ([string]::Equals($dependencyDefinitionId, [string]$PackageResult.DefinitionId, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package definition '$($PackageResult.DefinitionId)' cannot depend on itself."
        }
        if (-not $seenDependencyIds.Add($dependencyDefinitionId)) {
            continue
        }
        if ($currentStack -contains $dependencyDefinitionId) {
            throw ("Package dependency cycle detected: {0} -> {1}." -f (($currentStack -join ' -> ')), $dependencyDefinitionId)
        }

        Write-PackageExecutionMessage -Message ("[STEP] Ensuring package dependency '{0}'." -f $dependencyDefinitionId)
        $dependencyResult = Invoke-PackageDefinitionCommand -DefinitionId $dependencyDefinitionId -CommandName ("Invoke-{0}" -f $dependencyDefinitionId) -DependencyStack (@($currentStack) + $dependencyDefinitionId)
        $dependencyStatus = if ($dependencyResult) { [string]$dependencyResult.Status } else { '<none>' }
        if (-not $dependencyResult -or -not [string]::Equals($dependencyStatus, 'Ready', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package dependency '$dependencyDefinitionId' did not become ready. Status='$dependencyStatus'."
        }

        $dependencyRecords.Add([pscustomobject]@{
            DefinitionId   = $dependencyDefinitionId
            Status         = $dependencyStatus
            InstallOrigin  = [string]$dependencyResult.InstallOrigin
            InstallStatus  = if ($dependencyResult.Install -and $dependencyResult.Install.PSObject.Properties['Status']) { [string]$dependencyResult.Install.Status } else { $null }
            EntryPoints    = if ($dependencyResult.PSObject.Properties['EntryPoints']) { $dependencyResult.EntryPoints } else { $null }
            Commands       = @(Resolve-PackageDependencyCommandEntryPoints -DependencyResult $dependencyResult)
            Result         = $dependencyResult
        }) | Out-Null

        Write-PackageExecutionMessage -Message ("[STATE] Package dependency ready: definition='{0}', installOrigin='{1}', installStatus='{2}'." -f $dependencyDefinitionId, [string]$dependencyResult.InstallOrigin, $(if ($dependencyResult.Install -and $dependencyResult.Install.PSObject.Properties['Status']) { [string]$dependencyResult.Install.Status } else { '<none>' }))
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
