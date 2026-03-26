<#
    Eigenverft.Manifested.Sandbox.Shared.Pip
#>

function Get-ManagedPythonPipConfigPath {
<#
.SYNOPSIS
Returns the managed pip configuration file path for a Python home.

.DESCRIPTION
Builds the runtime-local `pip.ini` path that the sandbox-managed Python
wrappers and pip helpers use for persisted pip settings.

.PARAMETER PythonHome
The root directory that contains the managed Python executable.

.EXAMPLE
Get-ManagedPythonPipConfigPath -PythonHome 'C:\Sandbox\tools\python\3.13.12\amd64'

.NOTES
This helper only composes the path and does not create the file.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonHome
    )

    return (Join-Path $PythonHome 'pip.ini')
}

function Get-ManagedPythonPipCacheRoot {
<#
.SYNOPSIS
Returns the managed pip cache directory.

.DESCRIPTION
Resolves the sandbox-owned pip cache root beneath the manifested Python cache
layout for the supplied or default local root.

.PARAMETER LocalRoot
The sandbox local root used to calculate the managed cache layout.

.EXAMPLE
Get-ManagedPythonPipCacheRoot

.NOTES
The returned path is used for `PIP_CACHE_DIR` in managed runtimes.
#>
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    return (Join-Path $layout.PythonCacheRoot 'pip')
}

function Test-ManifestedManagedPythonCommand {
<#
.SYNOPSIS
Determines whether a Python executable belongs to the managed sandbox layout.

.DESCRIPTION
Checks whether the supplied Python executable path resolves underneath the
manifested Python tools root for the selected sandbox local root.

.PARAMETER PythonExe
The Python executable path to evaluate.

.PARAMETER LocalRoot
The sandbox local root used to resolve the managed tools directory.

.EXAMPLE
Test-ManifestedManagedPythonCommand -PythonExe 'C:\Sandbox\tools\python\3.13.12\amd64\python.exe'

.NOTES
This guard is used to avoid applying managed pip settings to external runtimes.
#>
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
<#
.SYNOPSIS
Returns the canonical pip package-index URI.

.DESCRIPTION
Provides the package-index endpoint used when evaluating direct versus proxied
network routes for pip traffic.

.EXAMPLE
Get-ManifestedPipIndexUri

.NOTES
The current implementation targets the public PyPI simple index.
#>
    [CmdletBinding()]
    param()

    return [uri]'https://pypi.org/simple/'
}

function Resolve-ManifestedPipProxyRoute {
<#
.SYNOPSIS
Determines whether pip traffic should use a system proxy.

.DESCRIPTION
Consults the system web proxy for the requested package index URI and reports
whether the route is direct or proxied, including the effective proxy URI when
one is required.

.PARAMETER IndexUri
The package index URI whose network route should be evaluated.

.EXAMPLE
Resolve-ManifestedPipProxyRoute -IndexUri (Get-ManifestedPipIndexUri)

.NOTES
Proxy discovery failures are treated as direct access to keep the helper safe.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [uri]$IndexUri
    )

    $proxyRoute = Resolve-ManifestedProxyRoute -TargetUri $IndexUri

    [pscustomobject]@{
        IndexUri      = $proxyRoute.TargetUri
        IndexHost     = $proxyRoute.TargetHost
        ProxyUri      = $proxyRoute.ProxyUri
        ProxyRequired = $proxyRoute.ProxyRequired
        Route         = $proxyRoute.Route
    }
}

function Get-ManifestedPipConfigDocument {
<#
.SYNOPSIS
Reads a pip configuration file into an in-memory document.

.DESCRIPTION
Parses a `pip.ini`-style configuration file into nested ordered hashtables,
preserving section and key ordering for later read and write operations.

.PARAMETER ConfigPath
The configuration file to parse.

.EXAMPLE
Get-ManifestedPipConfigDocument -ConfigPath 'C:\Sandbox\tools\python\3.13.12\amd64\pip.ini'

.NOTES
Missing files return an empty ordered hashtable.
#>
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
<#
.SYNOPSIS
Reads a single value from a pip configuration document.

.DESCRIPTION
Loads the pip configuration file and returns the requested key from the named
section when it exists; otherwise returns `$null`.

.PARAMETER ConfigPath
The configuration file to inspect.

.PARAMETER Section
The section name that should contain the key.

.PARAMETER Key
The key to read from the selected section.

.EXAMPLE
Get-ManifestedPipConfigValue -ConfigPath $pipIni -Section 'global' -Key 'proxy'

.NOTES
This helper does not create missing sections or keys.
#>
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
<#
.SYNOPSIS
Writes a single value into a pip configuration file.

.DESCRIPTION
Ensures the requested section exists, updates the selected key, and rewrites
the runtime-local pip configuration file in a stable ordered format.

.PARAMETER ConfigPath
The configuration file to update.

.PARAMETER Section
The section that should contain the key.

.PARAMETER Key
The key name to write.

.PARAMETER Value
The value to assign to the selected key.

.EXAMPLE
Set-ManifestedPipConfigValue -ConfigPath $pipIni -Section 'global' -Key 'proxy' -Value 'http://proxy:8080'

.NOTES
The file is written with ASCII encoding to match the surrounding module style.
#>
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
<#
.SYNOPSIS
Summarizes the current pip proxy configuration state for a Python runtime.

.DESCRIPTION
Combines the managed-runtime test, effective network route, and any existing
pip proxy setting to describe what action, if any, is needed before running
pip-related commands.

.PARAMETER PythonExe
The Python executable whose pip configuration should be evaluated.

.PARAMETER LocalRoot
The sandbox local root used to resolve managed layout paths.

.EXAMPLE
Get-ManifestedPipProxyConfigurationStatus -PythonExe $pythonExe

.NOTES
The returned object is designed to be reusable by
`Sync-ManifestedPipProxyConfiguration`.
#>
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

    $action = Get-ManifestedManagedProxyAction -IsManagedTarget:$pipConfiguration.IsManagedPython -Route $proxyRoute.Route -DesiredProxyUri $proxyRoute.ProxyUri -CurrentValues @($currentProxy) -ExternalAction 'SkippedExternalPip' -DirectAction 'DirectNoChange' -ReusedAction 'ReusedManagedProxy' -NeedsAction 'NeedsManagedProxy'

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
<#
.SYNOPSIS
Creates pip wrapper commands for a managed Python runtime.

.DESCRIPTION
Writes `pip.cmd` and `pip3.cmd` wrappers that pin the managed `pip.ini` file
and pip cache directory before delegating to `python.exe -m pip`.

.PARAMETER PythonHome
The root directory of the managed Python runtime that should receive wrappers.

.PARAMETER LocalRoot
The sandbox local root used to resolve the shared pip cache directory.

.EXAMPLE
Set-ManifestedManagedPipWrappers -PythonHome 'C:\Sandbox\tools\python\3.13.12\amd64'

.NOTES
This helper is intended for managed runtimes only.
#>
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
        ('set "PIP_CACHE_DIR={0}"' -f $pipCacheRoot),
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

function Get-ManagedPythonSanitizedEnvironmentVariableNames {
<#
.SYNOPSIS
Returns Python environment variables that should be cleared for managed runtimes.

.DESCRIPTION
Lists session-level Python environment variables that can interfere with the
isolated embeddable runtime layout when a sandbox-managed Python executable is
launched from a host shell that already has Python-specific configuration.

.EXAMPLE
Get-ManagedPythonSanitizedEnvironmentVariableNames

.NOTES
These variables are only cleared for sandbox-managed runtimes.
#>
    [CmdletBinding()]
    param()

    return @(
        'PYTHONHOME',
        'PYTHONPATH'
    )
}

function Invoke-ManifestedPythonCommand {
<#
.SYNOPSIS
Invokes Python with managed sandbox environment adjustments when applicable.

.DESCRIPTION
Runs a Python command, temporarily applying the runtime-local pip config and
cache variables for managed runtimes when requested and clearing conflicting
Python host variables such as `PYTHONHOME` and `PYTHONPATH`. The previous
process environment is restored even when the Python process fails to start.

.PARAMETER PythonExe
The Python executable to run.

.PARAMETER Arguments
The argument vector passed to the Python process.

.PARAMETER IncludeManagedPipEnvironment
Adds managed `PIP_CONFIG_FILE` and `PIP_CACHE_DIR` variables when the Python
executable belongs to the sandbox-managed runtime layout.

.PARAMETER LocalRoot
The pinned sandbox root used to derive managed pip settings.

.EXAMPLE
Invoke-ManifestedPythonCommand -PythonExe $pythonExe -Arguments @('-V')

.EXAMPLE
Invoke-ManifestedPythonCommand -PythonExe $pythonExe -Arguments @('-m', 'pip', '--version') -IncludeManagedPipEnvironment

.NOTES
External Python runtimes are executed without managed environment sanitization.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$IncludeManagedPipEnvironment,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $configuration = Get-ManifestedPythonPipConfiguration -PythonExe $PythonExe -LocalRoot $LocalRoot
    $environmentVariables = [ordered]@{}
    $previousValues = @{}
    $sanitizedVariables = @()
    $output = @()
    $exitCode = $null
    $exceptionMessage = $null

    if ($configuration.IsManagedPython) {
        foreach ($variableName in @(Get-ManagedPythonSanitizedEnvironmentVariableNames)) {
            $environmentVariables[$variableName] = $null
        }

        $sanitizedVariables = @($environmentVariables.Keys)

        if ($IncludeManagedPipEnvironment) {
            foreach ($variableName in @($configuration.EnvironmentVariables.Keys)) {
                $environmentVariables[$variableName] = $configuration.EnvironmentVariables[$variableName]
            }
        }
    }

    try {
        foreach ($variableName in @($environmentVariables.Keys)) {
            $previousValues[$variableName] = [System.Environment]::GetEnvironmentVariable($variableName, 'Process')
            $targetValue = $environmentVariables[$variableName]
            [System.Environment]::SetEnvironmentVariable($variableName, $targetValue, 'Process')
            if ($null -eq $targetValue) {
                Remove-Item -Path ('Env:' + $variableName) -ErrorAction SilentlyContinue
            }
            else {
                Set-Item -Path ('Env:' + $variableName) -Value $targetValue
            }
        }

        $output = @(& $PythonExe @Arguments 2>&1)
        $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
    }
    catch {
        $exceptionMessage = $_.Exception.Message
        $output += $_
        if ($null -eq $exitCode -and $null -ne $LASTEXITCODE) {
            $exitCode = [int]$LASTEXITCODE
        }
    }
    finally {
        foreach ($variableName in @($environmentVariables.Keys)) {
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

    $outputLines = @(
        $output |
            ForEach-Object {
                if ($null -eq $_) {
                    return $null
                }

                $_.ToString().Trim()
            } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    [pscustomobject]@{
        Output                    = @($output)
        OutputLines               = @($outputLines)
        OutputText                = ($outputLines -join [Environment]::NewLine)
        ExitCode                  = $exitCode
        ExceptionMessage          = $exceptionMessage
        Succeeded                 = ($null -ne $exitCode -and $exitCode -eq 0 -and [string]::IsNullOrWhiteSpace($exceptionMessage))
        Configuration             = $configuration
        IsManagedPython           = $configuration.IsManagedPython
        AppliedEnvironmentVariables = $environmentVariables
        SanitizedVariables        = @($sanitizedVariables)
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

    return (Invoke-ManifestedPythonCommand -PythonExe $PythonExe -Arguments $Arguments -IncludeManagedPipEnvironment -LocalRoot $LocalRoot)
}
