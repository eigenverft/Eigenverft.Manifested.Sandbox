<#
    Root entry helpers: Get-SandboxVersion and Sandbox (-Update / -Version bootstrap).
    Imported by Eigenverft.Manifested.Sandbox.psm1.
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

function Sandbox {
<#
.SYNOPSIS
Install or update Eigenverft.Manifested.Sandbox from the PowerShell Gallery, or print module version information.

.DESCRIPTION
Thin bootstrap surface (similar intent to Eigenverft.Manifested.Drydock). Main switches are mutually exclusive:
- -Update : Install/update from PSGallery (stable; -Scope). On Windows, Initialize-ProxyAccessProfile (gallery URI) sets session + Global:ProxyParamsInstallModule for Install-Module; manual proxy UI is allowed when automatic resolution cannot reach the gallery. Non-Windows: minimal TLS/proxy only. Requires network.
- -Version : Print the same summary as Get-SandboxVersion (resolved module version and exported commands).

Without a main switch, prints a short usage note.

.PARAMETER Update
Install or update the module from PSGallery.

.PARAMETER Version
Show module version and exported command names (delegates to Get-SandboxVersion).

.PARAMETER Scope
With -Update, CurrentUser (default) or AllUsers (elevation required).

.EXAMPLE
Sandbox -Update -Scope CurrentUser

.EXAMPLE
Sandbox -Version
#>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Manual')]
    param(
        [Parameter(ParameterSetName = 'UpdateSet', Mandatory = $true)]
        [switch]$Update,

        [Parameter(ParameterSetName = 'VersionSet', Mandatory = $true)]
        [Alias('v')]
        [switch]$Version,

        [Parameter(ParameterSetName = 'UpdateSet')]
        [ValidateSet('CurrentUser', 'AllUsers')]
        [string]$Scope = 'CurrentUser'
    )

    $ModuleName = 'Eigenverft.Manifested.Sandbox'
    $Repository = 'PSGallery'

    function Show-SandboxManual {
        @(
            "-Update   : Install/update module from $Repository (stable; supports -Scope)."
            "  Example : Sandbox -Update -Scope CurrentUser"
            "  -Scope  : CurrentUser (default) or AllUsers (elevation)."
            ""
            "-Version  : Show module version and exported commands (same as Get-SandboxVersion)."
            "  Example : Sandbox -Version"
        ) | ForEach-Object { Write-Output $_ }
    }

    switch ($PSCmdlet.ParameterSetName) {
        'Manual' {
            Show-SandboxManual
            return
        }
        'VersionSet' {
            Get-SandboxVersion
            return
        }
        'UpdateSet' {
            $params = @{
                Name         = $ModuleName
                Repository   = $Repository
                Scope        = $Scope
                Force        = $true
                AllowClobber = $true
                ErrorAction  = 'Stop'
            }

            $proxyModuleParams = @{}
            $sandboxIsWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

            if ($sandboxIsWindows) {
                # Manual proxy UI and non-interactive failure are handled inside Initialize-ProxyAccessProfile (UserInteractive + optional -SkipManualProxyPrompt).
                Initialize-ProxyAccessProfile -TestUri ([uri]'https://www.powershellgallery.com/api/v2/')

                if ($null -ne $Global:ProxyParamsPrepareSession) {
                    $null = $Global:ProxyParamsPrepareSession.Invoke()
                }
                $installGv = Get-Variable -Scope Global -Name ProxyParamsInstallModule -ErrorAction SilentlyContinue
                if ($installGv -and $installGv.Value -is [hashtable] -and $installGv.Value.Count -gt 0) {
                    $proxyModuleParams = $installGv.Value
                }
            }
            else {
                try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
                try {
                    $wp = [System.Net.WebRequest]::GetSystemWebProxy()
                    [System.Net.WebRequest]::DefaultWebProxy = $wp
                    if ($wp) { $wp.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials }
                } catch { }
            }

            if ($PSCmdlet.ShouldProcess($params.Name, "Install ($Scope) from $Repository")) {
                Install-Module @proxyModuleParams @params
            }
            return
        }
    }
}
