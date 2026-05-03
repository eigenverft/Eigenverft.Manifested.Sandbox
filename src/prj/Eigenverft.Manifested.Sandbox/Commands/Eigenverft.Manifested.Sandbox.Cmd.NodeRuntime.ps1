<#
    Eigenverft.Manifested.Sandbox.Cmd.NodeRuntime
#>

function Resolve-PackageNodeRuntimeNpmCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageResult
    )

    $npmEntryPoint = @(
        $PackageResult.EntryPoints.Commands |
            Where-Object { [string]::Equals([string]$_.Name, 'npm', [System.StringComparison]::OrdinalIgnoreCase) } |
            Select-Object -First 1
    )
    $npmCmd = if ($npmEntryPoint) {
        [string]$npmEntryPoint[0].Path
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$PackageResult.InstallDirectory)) {
        Join-Path ([string]$PackageResult.InstallDirectory) 'npm.cmd'
    }
    else {
        $null
    }

    if ([string]::IsNullOrWhiteSpace($npmCmd) -or -not (Test-Path -LiteralPath $npmCmd)) {
        throw 'A usable npm command was not available from Invoke-NodeRuntime.'
    }

    return $npmCmd
}

function Invoke-NodeRuntime {
<#
.SYNOPSIS
Ensures the configured Node.js runtime is available through Package.

.DESCRIPTION
Loads the shipped Package JSON documents, resolves the effective Node.js
release for the current runtime context, saves the package file when needed,
installs or reuses the package, validates node/npm/npx, applies user PATH
registration, updates package inventory, and returns resolved entry points.

.EXAMPLE
Invoke-NodeRuntime
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageDefinitionCommand -RepositoryId 'EigenverftModule' -DefinitionId 'NodeRuntime' -DesiredState Assigned)
}

