<#
    Placeholder for future combined command implementation.
    Keep this file imported by the module load order.
#>

function Get-SandboxVersion {
<#
.SYNOPSIS
Shows the resolved module version and the available exported commands.

.DESCRIPTION
Resolves the highest available or loaded Eigenverft.Manifested.Sandbox module
version for the current session and appends the exported command names that
can be called in the current session.

.EXAMPLE
Get-SandboxVersion

Displays labeled module information followed by each exported command in a
user-facing alphabetically ordered list.
#>
    [CmdletBinding()]
    param()

    $moduleName = 'Eigenverft.Manifested.Sandbox'
    $moduleInfo = @(Get-Module -ListAvailable -Name $moduleName | Sort-Object -Descending -Property Version | Select-Object -First 1)
    $loadedModule = @(Get-Module -Name $moduleName | Sort-Object -Descending -Property Version | Select-Object -First 1)

    if (-not $moduleInfo) {
        if ($loadedModule) {
            $moduleInfo = $loadedModule
        }
        elseif ($ExecutionContext.SessionState.Module -and $ExecutionContext.SessionState.Module.Name -eq $moduleName) {
            $moduleInfo = @($ExecutionContext.SessionState.Module)
        }
    }

    if (-not $moduleInfo) {
        throw "Could not resolve the installed or loaded version of module '$moduleName'."
    }

    $commandSourceModule = $loadedModule | Select-Object -First 1
    if (-not $commandSourceModule -and $ExecutionContext.SessionState.Module -and $ExecutionContext.SessionState.Module.Name -eq $moduleName) {
        $commandSourceModule = $ExecutionContext.SessionState.Module
    }

    $exportedCommandNames = @()
    if ($commandSourceModule -and $commandSourceModule.ExportedCommands) {
        $exportedCommandNames = @(
            $commandSourceModule.ExportedCommands.Keys |
                Sort-Object
        )
    }

    if (-not $exportedCommandNames) {
        $exportedCommandNames = @(
            Get-Command -Module $moduleName -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty Name -Unique |
                Sort-Object
        )
    }

    $outputLines = @(
        'Module: {0}' -f $moduleName
        'Version: {0}' -f $moduleInfo[0].Version.ToString()
        'Available Commands:'
    )

    if ($exportedCommandNames) {
        $outputLines += @(
            $exportedCommandNames | ForEach-Object { '- {0}' -f $_ }
        )
    }
    else {
        $outputLines += '- None found'
    }

    return ($outputLines -join [Environment]::NewLine)
}
