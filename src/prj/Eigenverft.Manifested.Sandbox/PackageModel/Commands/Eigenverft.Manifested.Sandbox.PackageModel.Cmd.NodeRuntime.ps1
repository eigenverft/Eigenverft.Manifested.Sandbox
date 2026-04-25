<#
    Eigenverft.Manifested.Sandbox.PackageModel.Cmd.NodeRuntime
#>

function Resolve-PackageModelNodeRuntimeNpmCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageModelResult
    )

    $npmEntryPoint = @(
        $PackageModelResult.EntryPoints.Commands |
            Where-Object { [string]::Equals([string]$_.Name, 'npm', [System.StringComparison]::OrdinalIgnoreCase) } |
            Select-Object -First 1
    )
    $npmCmd = if ($npmEntryPoint) {
        [string]$npmEntryPoint[0].Path
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$PackageModelResult.InstallDirectory)) {
        Join-Path ([string]$PackageModelResult.InstallDirectory) 'npm.cmd'
    }
    else {
        $null
    }

    if ([string]::IsNullOrWhiteSpace($npmCmd) -or -not (Test-Path -LiteralPath $npmCmd)) {
        throw 'A usable npm command was not available from Invoke-PackageModel-NodeRuntime.'
    }

    return $npmCmd
}

function Invoke-PackageModel-NodeRuntime {
<#
.SYNOPSIS
Ensures the configured Node.js runtime is available through PackageModel.

.DESCRIPTION
Loads the shipped PackageModel JSON documents, resolves the effective Node.js
release for the current runtime context, saves the package file when needed,
installs or reuses the package, validates node/npm/npx, applies user PATH
registration, updates ownership tracking, and returns resolved entry points.

.EXAMPLE
Invoke-PackageModel-NodeRuntime
#>
    [CmdletBinding()]
    param()

    return (Invoke-PackageModelDefinitionCommand -DefinitionId 'NodeRuntime' -CommandName 'Invoke-PackageModel-NodeRuntime')
}
