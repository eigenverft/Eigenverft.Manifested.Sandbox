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
