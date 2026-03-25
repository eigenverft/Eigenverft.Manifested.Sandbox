<#
    Eigenverft.Manifested.Sandbox.Shared.Pip
#>

function Get-ManagedPythonPipConfigPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonHome
    )

    return (Join-Path $PythonHome 'pip.ini')
}

function Get-ManagedPythonPipCacheRoot {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    return (Join-Path $layout.PythonCacheRoot 'pip')
}

function Test-ManifestedManagedPythonCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    return (Test-ManifestedPathIsUnderRoot -Path $PythonExe -RootPath $layout.PythonToolsRoot)
}

function Get-ManifestedPythonPipConfiguration {
<#
.SYNOPSIS
Builds the effective pip configuration context for a Python command.

.DESCRIPTION
Determines whether the supplied Python executable belongs to a sandbox-managed
runtime and, when it does, resolves the runtime-local `pip.ini`,
`PIP_CONFIG_FILE`, and `PIP_CACHE_DIR` values that should be applied before
running pip-related commands.

.PARAMETER PythonExe
The Python executable path to inspect.

.PARAMETER LocalRoot
The pinned sandbox root used to derive managed cache and config locations.

.EXAMPLE
Get-ManifestedPythonPipConfiguration -PythonExe 'C:\Sandbox\tools\python\3.13.12\amd64\python.exe'

.EXAMPLE
Get-ManifestedPythonPipConfiguration -PythonExe 'C:\Python313\python.exe'

.NOTES
External Python runtimes return an empty environment-variable map.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $pythonHome = Split-Path -Parent $PythonExe
    $isManagedPython = Test-ManifestedManagedPythonCommand -PythonExe $PythonExe -LocalRoot $LocalRoot
    $pipConfigPath = $null
    $pipCacheRoot = $null
    $environmentVariables = [ordered]@{}

    if ($isManagedPython) {
        $pipConfigPath = Get-ManagedPythonPipConfigPath -PythonHome $pythonHome
        $pipCacheRoot = Get-ManagedPythonPipCacheRoot -LocalRoot $LocalRoot
        $environmentVariables['PIP_CONFIG_FILE'] = $pipConfigPath
        $environmentVariables['PIP_CACHE_DIR'] = $pipCacheRoot
    }

    [pscustomobject]@{
        IsManagedPython     = $isManagedPython
        PythonExe           = $PythonExe
        PythonHome          = $pythonHome
        PipConfigPath       = $pipConfigPath
        PipCacheRoot        = $pipCacheRoot
        EnvironmentVariables = $environmentVariables
    }
}

function Get-ManifestedPipIndexUri {
    [CmdletBinding()]
    param()

    return [uri]'https://pypi.org/simple/'
}

function Resolve-ManifestedPipProxyRoute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [uri]$IndexUri
    )

    $proxyUri = $null

    try {
        $systemProxy = [System.Net.WebRequest]::GetSystemWebProxy()
        if ($null -ne $systemProxy) {
            $systemProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials

            if (-not $systemProxy.IsBypassed($IndexUri)) {
                $candidateProxyUri = $systemProxy.GetProxy($IndexUri)
                if ($null -ne $candidateProxyUri -and $candidateProxyUri.AbsoluteUri -ne $IndexUri.AbsoluteUri) {
                    $proxyUri = $candidateProxyUri
                }
            }
        }
    }
    catch {
        $proxyUri = $null
    }

    [pscustomobject]@{
        IndexUri      = $IndexUri.AbsoluteUri
        IndexHost     = $IndexUri.Host
        ProxyUri      = if ($proxyUri) { $proxyUri.AbsoluteUri } else { $null }
        ProxyRequired = ($null -ne $proxyUri)
        Route         = if ($proxyUri) { 'Proxy' } else { 'Direct' }
    }
}

function Get-ManifestedPipConfigDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    $document = [ordered]@{}
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return $document
    }

    $currentSection = $null
    foreach ($rawLine in @(Get-Content -LiteralPath $ConfigPath -ErrorAction SilentlyContinue)) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        if ($line.StartsWith(';') -or $line.StartsWith('#')) {
            continue
        }

        $sectionMatch = [regex]::Match($line, '^\[(.+)\]$')
        if ($sectionMatch.Success) {
            $currentSection = $sectionMatch.Groups[1].Value.Trim()
            if (-not $document.Contains($currentSection)) {
                $document[$currentSection] = [ordered]@{}
            }

            continue
        }

        $keyValueMatch = [regex]::Match($line, '^(?<key>[^=]+?)\s*=\s*(?<value>.*)$')
        if ($keyValueMatch.Success -and -not [string]::IsNullOrWhiteSpace($currentSection)) {
            $document[$currentSection][$keyValueMatch.Groups['key'].Value.Trim()] = $keyValueMatch.Groups['value'].Value.Trim()
        }
    }

    return $document
}

function Get-ManifestedPipConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $true)]
        [string]$Section,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $document = Get-ManifestedPipConfigDocument -ConfigPath $ConfigPath
    if (-not $document.Contains($Section)) {
        return $null
    }
    if (-not $document[$Section].Contains($Key)) {
        return $null
    }

    return $document[$Section][$Key]
}

function Set-ManifestedPipConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $true)]
        [string]$Section,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $document = Get-ManifestedPipConfigDocument -ConfigPath $ConfigPath
    if (-not $document.Contains($Section)) {
        $document[$Section] = [ordered]@{}
    }

    $document[$Section][$Key] = $Value

    New-ManifestedDirectory -Path (Split-Path -Parent $ConfigPath) | Out-Null

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($sectionName in @($document.Keys)) {
        $lines.Add('[' + $sectionName + ']') | Out-Null
        foreach ($keyName in @($document[$sectionName].Keys)) {
            $lines.Add($keyName + ' = ' + $document[$sectionName][$keyName]) | Out-Null
        }
        $lines.Add('') | Out-Null
    }

    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') {
        $lines.RemoveAt($lines.Count - 1)
    }

    Set-Content -LiteralPath $ConfigPath -Value $lines -Encoding ASCII
    return $ConfigPath
}

function Get-ManifestedPipProxyConfigurationStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $pipConfiguration = Get-ManifestedPythonPipConfiguration -PythonExe $PythonExe -LocalRoot $LocalRoot
    $indexUri = Get-ManifestedPipIndexUri
    $proxyRoute = Resolve-ManifestedPipProxyRoute -IndexUri $indexUri
    $currentProxy = $null

    if (-not [string]::IsNullOrWhiteSpace($pipConfiguration.PipConfigPath)) {
        $currentProxy = Get-ManifestedPipConfigValue -ConfigPath $pipConfiguration.PipConfigPath -Section 'global' -Key 'proxy'
    }

    if (-not $pipConfiguration.IsManagedPython) {
        $action = 'SkippedExternalPip'
    }
    elseif ($proxyRoute.Route -eq 'Direct') {
        $action = 'DirectNoChange'
    }
    elseif ($currentProxy -eq $proxyRoute.ProxyUri) {
        $action = 'ReusedManagedProxy'
    }
    else {
        $action = 'NeedsManagedProxy'
    }

    [pscustomobject]@{
        PythonExe      = $pipConfiguration.PythonExe
        PythonHome     = $pipConfiguration.PythonHome
        IndexUri       = $proxyRoute.IndexUri
        IndexHost      = $proxyRoute.IndexHost
        ProxyUri       = $proxyRoute.ProxyUri
        ProxyRequired  = $proxyRoute.ProxyRequired
        Route          = $proxyRoute.Route
        Action         = $action
        PipConfigPath  = $pipConfiguration.PipConfigPath
        PipCacheRoot   = $pipConfiguration.PipCacheRoot
        CurrentProxy   = $currentProxy
    }
}

function Sync-ManifestedPipProxyConfiguration {
<#
.SYNOPSIS
Synchronizes the managed pip proxy setting with the effective system route.

.DESCRIPTION
Examines the current proxy route to the configured Python package index and, for
sandbox-managed Python runtimes, writes a runtime-local `pip.ini` only when a
proxy is actually required and the existing config does not already match.

.PARAMETER PythonExe
The Python executable that owns the managed pip configuration.

.PARAMETER Status
Optional precomputed proxy-status object from
`Get-ManifestedPipProxyConfigurationStatus`.

.PARAMETER LocalRoot
The pinned sandbox root used for managed cache/config resolution.

.EXAMPLE
Sync-ManifestedPipProxyConfiguration -PythonExe 'C:\Sandbox\tools\python\3.13.12\amd64\python.exe'

.EXAMPLE
$status = Get-ManifestedPipProxyConfigurationStatus -PythonExe $pythonExe
Sync-ManifestedPipProxyConfiguration -PythonExe $pythonExe -Status $status

.NOTES
External Python runtimes are left unchanged.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [pscustomobject]$Status,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $Status) {
        $Status = Get-ManifestedPipProxyConfigurationStatus -PythonExe $PythonExe -LocalRoot $LocalRoot
    }

    if ($Status.Action -ne 'NeedsManagedProxy') {
        return $Status
    }

    if (-not [string]::IsNullOrWhiteSpace($Status.PipCacheRoot)) {
        New-ManifestedDirectory -Path $Status.PipCacheRoot | Out-Null
    }

    Set-ManifestedPipConfigValue -ConfigPath $Status.PipConfigPath -Section 'global' -Key 'proxy' -Value $Status.ProxyUri | Out-Null

    [pscustomobject]@{
        PythonExe      = $Status.PythonExe
        PythonHome     = $Status.PythonHome
        IndexUri       = $Status.IndexUri
        IndexHost      = $Status.IndexHost
        ProxyUri       = $Status.ProxyUri
        ProxyRequired  = $Status.ProxyRequired
        Route          = $Status.Route
        Action         = 'ConfiguredManagedProxy'
        PipConfigPath  = $Status.PipConfigPath
        PipCacheRoot   = $Status.PipCacheRoot
        CurrentProxy   = $Status.ProxyUri
    }
}

function Set-ManifestedManagedPipWrappers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonHome,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $pipConfigPath = Get-ManagedPythonPipConfigPath -PythonHome $PythonHome
    $pipCacheRoot = Get-ManagedPythonPipCacheRoot -LocalRoot $LocalRoot
    New-ManifestedDirectory -Path $pipCacheRoot | Out-Null

    $wrapperLines = @(
        '@echo off',
        'setlocal',
        'set "PIP_CONFIG_FILE=%~dp0pip.ini"',
        'set "PIP_CACHE_DIR=' + $pipCacheRoot + '"',
        '"%~dp0python.exe" -m pip %*',
        'exit /b %ERRORLEVEL%'
    )

    $wrapperPaths = @(
        (Join-Path $PythonHome 'pip.cmd'),
        (Join-Path $PythonHome 'pip3.cmd')
    )

    foreach ($wrapperPath in $wrapperPaths) {
        Set-Content -LiteralPath $wrapperPath -Value $wrapperLines -Encoding ASCII
    }

    [pscustomobject]@{
        PythonHome    = $PythonHome
        PipConfigPath = $pipConfigPath
        PipCacheRoot  = $pipCacheRoot
        WrapperPaths  = @($wrapperPaths)
    }
}

function Invoke-ManifestedPipAwarePythonCommand {
<#
.SYNOPSIS
Invokes Python with the sandbox-managed pip environment when applicable.

.DESCRIPTION
Temporarily applies the runtime-local pip configuration and cache environment
variables for a managed Python runtime, executes the requested Python command,
captures its combined output, and restores the previous process environment
afterward.

.PARAMETER PythonExe
The Python executable to run.

.PARAMETER Arguments
The argument vector passed to the Python process.

.PARAMETER LocalRoot
The pinned sandbox root used to derive managed pip settings.

.EXAMPLE
Invoke-ManifestedPipAwarePythonCommand -PythonExe $pythonExe -Arguments @('-m', 'pip', '--version')

.EXAMPLE
Invoke-ManifestedPipAwarePythonCommand -PythonExe $pythonExe -Arguments @($getPipScriptPath)

.NOTES
This helper is the common execution path for managed pip bootstrap and pip
inspection calls.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $configuration = Get-ManifestedPythonPipConfiguration -PythonExe $PythonExe -LocalRoot $LocalRoot
    $previousValues = @{}
    $output = @()
    $exitCode = 0

    try {
        foreach ($variableName in @($configuration.EnvironmentVariables.Keys)) {
            $previousValues[$variableName] = [System.Environment]::GetEnvironmentVariable($variableName, 'Process')
            [System.Environment]::SetEnvironmentVariable($variableName, $configuration.EnvironmentVariables[$variableName], 'Process')
            Set-Item -Path ('Env:' + $variableName) -Value $configuration.EnvironmentVariables[$variableName]
        }

        $output = @(& $PythonExe @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        foreach ($variableName in @($configuration.EnvironmentVariables.Keys)) {
            $previousValue = $previousValues[$variableName]
            [System.Environment]::SetEnvironmentVariable($variableName, $previousValue, 'Process')
            if ($null -eq $previousValue) {
                Remove-Item -Path ('Env:' + $variableName) -ErrorAction SilentlyContinue
            }
            else {
                Set-Item -Path ('Env:' + $variableName) -Value $previousValue
            }
        }
    }

    [pscustomobject]@{
        Output        = @($output)
        ExitCode      = $exitCode
        Configuration = $configuration
    }
}
