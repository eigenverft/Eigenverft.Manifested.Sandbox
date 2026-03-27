<#
    Placeholder for future combined command implementation.
    Keep this file imported by the module load order.
#>

function Get-SandboxVersion {
    [CmdletBinding()]
    param()

    $moduleName = 'Eigenverft.Manifested.Sandbox'
    $moduleInfo = @(Get-Module -ListAvailable -Name $moduleName | Sort-Object -Descending -Property Version | Select-Object -First 1)

    if (-not $moduleInfo) {
        $loadedModule = @(Get-Module -Name $moduleName | Sort-Object -Descending -Property Version | Select-Object -First 1)
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

    return ('{0} {1}' -f $moduleName, $moduleInfo[0].Version.ToString())
}

function Initialize-SandboxCommand {
<#
.SYNOPSIS
Initializes a sandbox-managed command through the JSON-backed registry.

.DESCRIPTION
Resolves the requested command definition from the packaged command
definitions, computes live facts, derives the execution plan, and runs the
shared runtime kernel for that command.

.PARAMETER Name
The packaged command definition name to initialize. This matches the exported
wrapper command name such as Initialize-NodeRuntime.

.PARAMETER Refresh
Forces reacquisition or reinstall planning for the selected command.

.EXAMPLE
Initialize-SandboxCommand -Name 'Initialize-NodeRuntime'

.EXAMPLE
Initialize-SandboxCommand -Name 'Initialize-GHCliRuntime' -Refresh
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [switch]$Refresh
    )

    return (Invoke-ManifestedCommandInitialization -Name $Name -PSCmdletObject $PSCmdlet -RefreshRequested:$Refresh -WhatIfMode:$WhatIfPreference)
}
