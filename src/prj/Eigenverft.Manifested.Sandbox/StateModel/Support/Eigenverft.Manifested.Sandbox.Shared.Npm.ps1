<#
    Eigenverft.Manifested.Sandbox.Shared.Npm
#>

function Get-ManagedNodeNpmGlobalConfigPath {
<#
.SYNOPSIS
Builds the managed npm global config path for a Node runtime home.

.DESCRIPTION
Returns the npm global config path used by sandbox-managed Node runtimes.

.PARAMETER NodeHome
The managed Node runtime home directory.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeHome
    )

    return (Join-Path $NodeHome 'etc\npmrc')
}

function Test-ManifestedManagedNpmCommand {
<#
.SYNOPSIS
Checks whether an npm command belongs to the managed sandbox runtime.

.DESCRIPTION
Verifies that the supplied npm command path lives under the sandbox-managed
Node tools root for the current local layout.

.PARAMETER NpmCmd
The npm command path to test.

.PARAMETER LocalRoot
The sandbox local root used to resolve the managed Node tools root.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NpmCmd,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    return (Test-ManifestedPathIsUnderRoot -Path $NpmCmd -RootPath $layout.NodeToolsRoot)
}

function Get-ManifestedNpmGlobalConfigPath {
<#
.SYNOPSIS
Returns the managed npm global config path for an npm command.

.DESCRIPTION
Resolves the managed npm global config path when the npm command belongs to the
sandbox-managed runtime, otherwise returns `$null`.

.PARAMETER NpmCmd
The npm command path to inspect.

.PARAMETER LocalRoot
The sandbox local root used to resolve the managed runtime layout.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NpmCmd,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not (Test-ManifestedManagedNpmCommand -NpmCmd $NpmCmd -LocalRoot $LocalRoot)) {
        return $null
    }

    $nodeHome = Split-Path -Parent $NpmCmd
    return (Get-ManagedNodeNpmGlobalConfigPath -NodeHome $nodeHome)
}

function Get-ManifestedManagedNpmCommandArguments {
<#
.SYNOPSIS
Builds extra npm arguments for managed runtimes.

.DESCRIPTION
Returns the managed global config path and the command-line arguments needed to
force npm to use that config file when the runtime is sandbox-managed.

.PARAMETER NpmCmd
The npm command path to inspect.

.PARAMETER LocalRoot
The sandbox local root used to resolve the managed runtime layout.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NpmCmd,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $globalConfigPath = Get-ManifestedNpmGlobalConfigPath -NpmCmd $NpmCmd -LocalRoot $LocalRoot
    $commandArguments = @()
    if (-not [string]::IsNullOrWhiteSpace($globalConfigPath)) {
        $commandArguments += @('--globalconfig', $globalConfigPath)
    }

    [pscustomobject]@{
        IsManagedNpm    = (-not [string]::IsNullOrWhiteSpace($globalConfigPath))
        GlobalConfigPath = $globalConfigPath
        CommandArguments = @($commandArguments)
    }
}

function Get-ManifestedNpmRegistryUri {
<#
.SYNOPSIS
Resolves the active npm registry URI.

.DESCRIPTION
Reads the npm registry configuration and returns a normalized URI, falling back
to the public npm registry when the configured value is missing or invalid.

.PARAMETER NpmCmd
The npm command used to query the registry configuration.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NpmCmd
    )

    $defaultRegistryUri = [uri]'https://registry.npmjs.org/'
    $registryValue = $null

    try {
        $registryOutput = & $NpmCmd config get registry 2>$null
        if ($LASTEXITCODE -eq 0 -and $null -ne $registryOutput) {
            $registryValue = ($registryOutput | Select-Object -First 1).ToString().Trim()
        }
    }
    catch {
        $registryValue = $null
    }

    if ([string]::IsNullOrWhiteSpace($registryValue) -or $registryValue -in @('undefined', 'null')) {
        return $defaultRegistryUri
    }

    try {
        return [uri]$registryValue
    }
    catch {
        return $defaultRegistryUri
    }
}

function Resolve-ManifestedNpmProxyRoute {
<#
.SYNOPSIS
Detects whether npm registry access uses a system proxy.

.DESCRIPTION
Queries the system web proxy for the target npm registry URI and reports
whether access is direct or proxied, including the resolved proxy URI when one
is required.

.PARAMETER RegistryUri
The npm registry URI to evaluate.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [uri]$RegistryUri
    )

    $proxyUri = $null

    try {
        $systemProxy = [System.Net.WebRequest]::GetSystemWebProxy()
        if ($null -ne $systemProxy) {
            $systemProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials

            if (-not $systemProxy.IsBypassed($RegistryUri)) {
                $candidateProxyUri = $systemProxy.GetProxy($RegistryUri)
                if ($null -ne $candidateProxyUri -and $candidateProxyUri.AbsoluteUri -ne $RegistryUri.AbsoluteUri) {
                    $proxyUri = $candidateProxyUri
                }
            }
        }
    }
    catch {
        $proxyUri = $null
    }

    [pscustomobject]@{
        RegistryUri   = $RegistryUri.AbsoluteUri
        RegistryHost  = $RegistryUri.Host
        ProxyUri      = if ($proxyUri) { $proxyUri.AbsoluteUri } else { $null }
        ProxyRequired = ($null -ne $proxyUri)
        Route         = if ($proxyUri) { 'Proxy' } else { 'Direct' }
    }
}

function Get-ManifestedNpmConfigValue {
<#
.SYNOPSIS
Reads a single npm config value.

.DESCRIPTION
Runs `npm config get` for the requested key and returns the normalized value,
or `$null` when the setting is absent, false-like, or could not be read.

.PARAMETER NpmCmd
The npm command used to query configuration.

.PARAMETER Key
The npm configuration key to read.

.PARAMETER GlobalConfigPath
An optional managed global config path to query explicitly.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NpmCmd,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [string]$GlobalConfigPath
    )

    $arguments = @('config', 'get', $Key)
    if (-not [string]::IsNullOrWhiteSpace($GlobalConfigPath)) {
        $arguments += @('--location=global', '--globalconfig', $GlobalConfigPath)
    }

    try {
        $valueOutput = & $NpmCmd @arguments 2>$null
        if ($LASTEXITCODE -ne 0 -or $null -eq $valueOutput) {
            return $null
        }

        $valueText = ($valueOutput | Select-Object -First 1).ToString().Trim()
        if ([string]::IsNullOrWhiteSpace($valueText) -or $valueText -in @('undefined', 'null', 'false')) {
            return $null
        }

        return $valueText
    }
    catch {
        return $null
    }
}

function Get-ManifestedNpmProxyConfigurationStatus {
<#
.SYNOPSIS
Reports the npm proxy configuration state.

.DESCRIPTION
Combines registry resolution, proxy route detection, and current managed npm
proxy settings to decide whether the sandbox-owned npm config needs changes.

.PARAMETER NpmCmd
The npm command to inspect.

.PARAMETER LocalRoot
The sandbox local root used to resolve the managed runtime layout.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NpmCmd,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $registryUri = Get-ManifestedNpmRegistryUri -NpmCmd $NpmCmd
    $proxyRoute = Resolve-ManifestedNpmProxyRoute -RegistryUri $registryUri
    $globalConfigPath = Get-ManifestedNpmGlobalConfigPath -NpmCmd $NpmCmd -LocalRoot $LocalRoot
    $currentProxy = $null
    $currentHttpsProxy = $null

    if (-not [string]::IsNullOrWhiteSpace($globalConfigPath)) {
        $currentProxy = Get-ManifestedNpmConfigValue -NpmCmd $NpmCmd -Key 'proxy' -GlobalConfigPath $globalConfigPath
        $currentHttpsProxy = Get-ManifestedNpmConfigValue -NpmCmd $NpmCmd -Key 'https-proxy' -GlobalConfigPath $globalConfigPath
    }

    if ([string]::IsNullOrWhiteSpace($globalConfigPath)) {
        $action = 'SkippedExternalNpm'
    }
    elseif ($proxyRoute.Route -eq 'Direct') {
        $action = 'DirectNoChange'
    }
    elseif ($currentProxy -eq $proxyRoute.ProxyUri -and $currentHttpsProxy -eq $proxyRoute.ProxyUri) {
        $action = 'ReusedManagedGlobalProxy'
    }
    else {
        $action = 'NeedsManagedGlobalProxy'
    }

    [pscustomobject]@{
        NpmCmd          = $NpmCmd
        RegistryUri     = $proxyRoute.RegistryUri
        RegistryHost    = $proxyRoute.RegistryHost
        ProxyUri        = $proxyRoute.ProxyUri
        ProxyRequired   = $proxyRoute.ProxyRequired
        Route           = $proxyRoute.Route
        Action          = $action
        GlobalConfigPath = $globalConfigPath
        CurrentProxy    = $currentProxy
        CurrentHttpsProxy = $currentHttpsProxy
    }
}

function Sync-ManifestedNpmProxyConfiguration {
<#
.SYNOPSIS
Applies the managed npm proxy configuration when required.

.DESCRIPTION
Uses the computed proxy status to write sandbox-owned npm proxy settings into
the managed global config file when the registry route requires a proxy.

.PARAMETER NpmCmd
The npm command used to write configuration.

.PARAMETER Status
An optional precomputed proxy status object.

.PARAMETER LocalRoot
The sandbox local root used to resolve the managed runtime layout.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NpmCmd,

        [pscustomobject]$Status,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    if (-not $Status) {
        $Status = Get-ManifestedNpmProxyConfigurationStatus -NpmCmd $NpmCmd -LocalRoot $LocalRoot
    }

    if ($Status.Action -ne 'NeedsManagedGlobalProxy') {
        return $Status
    }

    New-ManifestedDirectory -Path (Split-Path -Parent $Status.GlobalConfigPath) | Out-Null

    & $NpmCmd config set ("proxy=" + $Status.ProxyUri) ("https-proxy=" + $Status.ProxyUri) --location=global --globalconfig $Status.GlobalConfigPath
    if ($LASTEXITCODE -ne 0) {
        throw "npm config set for proxy exited with code $LASTEXITCODE."
    }

    [pscustomobject]@{
        NpmCmd          = $Status.NpmCmd
        RegistryUri     = $Status.RegistryUri
        RegistryHost    = $Status.RegistryHost
        ProxyUri        = $Status.ProxyUri
        ProxyRequired   = $Status.ProxyRequired
        Route           = $Status.Route
        Action          = 'ConfiguredManagedGlobalProxy'
        GlobalConfigPath = $Status.GlobalConfigPath
        CurrentProxy    = $Status.ProxyUri
        CurrentHttpsProxy = $Status.ProxyUri
    }
}
