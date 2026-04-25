<#
    Eigenverft.Manifested.Sandbox.Shared.Elevation
#>

function Test-ManifestedProcessElevation {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return $false
    }

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-ManifestedPowerShellHostPath {
    [CmdletBinding()]
    param()

    try {
        $process = Get-Process -Id $PID -ErrorAction Stop
        if ($process.Path) {
            return $process.Path
        }
    }
    catch {
    }

    $desktopHostPath = Join-Path $PSHOME 'powershell.exe'
    if (Test-Path -LiteralPath $desktopHostPath) {
        return $desktopHostPath
    }

    $coreHostPath = Join-Path $PSHOME 'pwsh.exe'
    if (Test-Path -LiteralPath $coreHostPath) {
        return $coreHostPath
    }

    throw 'Unable to resolve the current PowerShell host path for self-elevation.'
}

function Get-ManifestedModuleManifestPath {
    [CmdletBinding()]
    param()

    return (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Eigenverft.Manifested.Sandbox.psd1')
}

function Get-ManifestedSelfElevationContext {
    [CmdletBinding()]
    param()

    $wasSelfElevated = ([System.Environment]::GetEnvironmentVariable('EIGENVERFT_MANIFESTED_SELF_ELEVATED', 'Process') -eq '1')

    [pscustomobject]@{
        SkipSelfElevation = $wasSelfElevated
        WasSelfElevated   = $wasSelfElevated
    }
}

function Get-ManifestedCommandElevationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [string[]]$PlannedActions = @(),

        [hashtable]$Context = @{},

        [string]$LocalRoot = (Get-ManifestedLocalRoot),

        [switch]$SkipSelfElevation,
        [switch]$WasSelfElevated,
        [switch]$WhatIfMode
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $requiresElevation = $false
    $requirementSource = $null

    $processIsElevated = Test-ManifestedProcessElevation

    [pscustomobject]@{
        CommandName        = $CommandName
        LocalRoot          = $layout.LocalRoot
        Layout             = $layout
        PlannedActions     = @($PlannedActions)
        ProcessIsElevated  = $processIsElevated
        RequiresElevation  = $requiresElevation
        RequirementSource  = $requirementSource
        SkipSelfElevation  = [bool]$SkipSelfElevation
        WasSelfElevated    = [bool]$WasSelfElevated
        WhatIfMode         = [bool]$WhatIfMode
        ShouldSelfElevate  = ($requiresElevation -and -not $processIsElevated -and -not $SkipSelfElevation -and -not $WhatIfMode)
    }
}

function Invoke-ManifestedElevatedCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$ElevationPlan,

        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [Parameter(Mandatory = $true)]
        [hashtable]$CommandParameters
    )

    if (-not $ElevationPlan.ShouldSelfElevate) {
        return $null
    }

    $layout = Get-ManifestedLayout -LocalRoot $ElevationPlan.LocalRoot
    $stagePath = New-ManifestedStageDirectory -RootPath $layout.LocalRoot -Prefix 'elevated'
    $scriptPath = Join-Path $stagePath 'invoke-elevated.ps1'
    $parameterPath = Join-Path $stagePath 'invoke-parameters.json'
    $resultPath = Join-Path $stagePath 'invoke-result.json'
    $moduleManifestPath = Get-ManifestedModuleManifestPath
    $hostPath = Get-ManifestedPowerShellHostPath

    try {
        $invocationParameters = @{}
        foreach ($entry in $CommandParameters.GetEnumerator()) {
            if ($null -ne $entry.Value) {
                $invocationParameters[$entry.Key] = $entry.Value
            }
        }

        $invocationParameters | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $parameterPath -Encoding UTF8

        $scriptContent = @"
param(
    [Parameter(Mandatory = \$true)]
    [string]\$ModuleManifestPath,

    [Parameter(Mandatory = \$true)]
    [string]\$CommandName,

    [Parameter(Mandatory = \$true)]
    [string]\$ParameterPath,

    [Parameter(Mandatory = \$true)]
    [string]\$PinnedLocalRoot,

    [Parameter(Mandatory = \$true)]
    [string]\$ResultPath
)

Set-StrictMode -Version Latest
\$ErrorActionPreference = 'Stop'
\$env:EIGENVERFT_MANIFESTED_LOCALROOT = \$PinnedLocalRoot
\$env:EIGENVERFT_MANIFESTED_SELF_ELEVATED = '1'

Import-Module -Name \$ModuleManifestPath -Force

\$parameterDocument = Get-Content -LiteralPath \$ParameterPath -Raw -ErrorAction Stop | ConvertFrom-Json
\$invokeParameters = @{}

foreach (\$property in \$parameterDocument.PSObject.Properties) {
    \$invokeParameters[\$property.Name] = \$property.Value
}

\$result = & \$CommandName @invokeParameters
\$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath \$ResultPath -Encoding UTF8
"@

        Set-Content -LiteralPath $scriptPath -Value $scriptContent -Encoding UTF8

        $argumentList = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', $scriptPath,
            '-ModuleManifestPath', $moduleManifestPath,
            '-CommandName', $CommandName,
            '-ParameterPath', $parameterPath,
            '-PinnedLocalRoot', $layout.LocalRoot,
            '-ResultPath', $resultPath
        )

        try {
            $process = Start-Process -FilePath $hostPath -ArgumentList $argumentList -Verb RunAs -Wait -PassThru -ErrorAction Stop
        }
        catch {
            throw "Failed to start an elevated PowerShell process for $CommandName. $($_.Exception.Message)"
        }

        if ($process.ExitCode -ne 0) {
            throw "Elevated $CommandName exited with code $($process.ExitCode)."
        }

        if (-not (Test-Path -LiteralPath $resultPath)) {
            throw "Elevated $CommandName completed without producing a result payload at $resultPath."
        }

        return ((Get-Content -LiteralPath $resultPath -Raw -ErrorAction Stop) | ConvertFrom-Json)
    }
    finally {
        Remove-ManifestedPath -Path $stagePath | Out-Null
    }
}
