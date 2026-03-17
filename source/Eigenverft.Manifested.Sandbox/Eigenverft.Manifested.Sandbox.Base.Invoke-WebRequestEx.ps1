function Write-StandardMessage {
    [Diagnostics.CodeAnalysis.SuppressMessage("PSUseApprovedVerbs","")]
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Message,
        [Parameter()][ValidateSet('TRC','DBG','INF','WRN','ERR','FTL')][string]$Level='INF',
        [Parameter()][ValidateSet('TRC','DBG','INF','WRN','ERR','FTL')][string]$MinLevel
    )
    if ($null -eq $Message) { $Message = [string]::Empty }
    $sevMap=@{TRC=0;DBG=1;INF=2;WRN=3;ERR=4;FTL=5}
    if(-not $PSBoundParameters.ContainsKey('MinLevel')){
        $gv=Get-Variable ConsoleLogMinLevel -Scope Global -ErrorAction SilentlyContinue
        $MinLevel=if($gv -and $gv.Value -and -not [string]::IsNullOrEmpty([string]$gv.Value)){[string]$gv.Value}else{'INF'}
    }
    $lvl=$Level.ToUpperInvariant()
    $min=$MinLevel.ToUpperInvariant()
    $sev=$sevMap[$lvl];if($null -eq $sev){$lvl='INF';$sev=$sevMap['INF']}
    $gate=$sevMap[$min];if($null -eq $gate){$min='INF';$gate=$sevMap['INF']}
    if($sev -ge 4 -and $sev -lt $gate -and $gate -ge 4){$lvl=$min;$sev=$gate}
    if($sev -lt $gate){return}
    $ts=[DateTime]::UtcNow.ToString('yy-MM-dd HH:mm:ss')
    $stack=Get-PSCallStack ; $helperName=$MyInvocation.MyCommand.Name ; $helperScript=$MyInvocation.MyCommand.ScriptBlock.File ; $caller=$null
    if($stack){
        # 1: prefer first non-underscore function not defined in the helper's own file
        for($i=0;$i -lt $stack.Count;$i++){
            $f=$stack[$i];$fn=$f.FunctionName;$sn=$f.ScriptName
            if($fn -and $fn -ne $helperName -and -not $fn.StartsWith('_') -and (-not $helperScript -or -not $sn -or $sn -ne $helperScript)){$caller=$f;break}
        }
        # 2: fallback to first non-underscore function (any file)
        if(-not $caller){
            for($i=0;$i -lt $stack.Count;$i++){
                $f=$stack[$i];$fn=$f.FunctionName
                if($fn -and $fn -ne $helperName -and -not $fn.StartsWith('_')){$caller=$f;break}
            }
        }
        # 3: fallback to first non-helper frame not from helper's own file
        if(-not $caller){
            for($i=0;$i -lt $stack.Count;$i++){
                $f=$stack[$i];$fn=$f.FunctionName;$sn=$f.ScriptName
                if($fn -and $fn -ne $helperName -and (-not $helperScript -or -not $sn -or $sn -ne $helperScript)){$caller=$f;break}
            }
        }
        # 4: final fallback to first non-helper frame
        if(-not $caller){
            for($i=0;$i -lt $stack.Count;$i++){
                $f=$stack[$i];$fn=$f.FunctionName
                if($fn -and $fn -ne $helperName){$caller=$f;break}
            }
        }
    }
    if(-not $caller){$caller=[pscustomobject]@{ScriptName=$PSCommandPath;FunctionName=$null}}
    $lineNumber=$null ; 
    $p=$caller.PSObject.Properties['ScriptLineNumber'];if($p -and $p.Value){$lineNumber=[string]$p.Value}
    if(-not $lineNumber){
        $p=$caller.PSObject.Properties['Position']
        if($p -and $p.Value){
            $sp=$p.Value.PSObject.Properties['StartLineNumber'];if($sp -and $sp.Value){$lineNumber=[string]$sp.Value}
        }
    }
    if(-not $lineNumber){
        $p=$caller.PSObject.Properties['Location']
        if($p -and $p.Value){
            $m=[regex]::Match([string]$p.Value,':(\d+)\s+char:','IgnoreCase');if($m.Success -and $m.Groups.Count -gt 1){$lineNumber=$m.Groups[1].Value}
        }
    }
    $file=if($caller.ScriptName){Split-Path -Leaf $caller.ScriptName}else{'cmd'}
    if($file -ne 'console' -and $lineNumber){$file="{0}:{1}" -f $file,$lineNumber}
    $prefix="[$ts "
    #$suffix="] [$file] $Message"
    $suffix="] $Message"
    $cfg=@{TRC=@{Fore='DarkGray';Back=$null};DBG=@{Fore='Cyan';Back=$null};INF=@{Fore='Green';Back=$null};WRN=@{Fore='Yellow';Back=$null};ERR=@{Fore='Red';Back=$null};FTL=@{Fore='Red';Back='DarkRed'}}[$lvl]
    $fore=$cfg.Fore
    $back=$cfg.Back
    $isInteractive = [System.Environment]::UserInteractive
    if($isInteractive -and ($fore -or $back)){
        Write-Host -NoNewline $prefix
        if($fore -and $back){Write-Host -NoNewline $lvl -ForegroundColor $fore -BackgroundColor $back}
        elseif($fore){Write-Host -NoNewline $lvl -ForegroundColor $fore}
        elseif($back){Write-Host -NoNewline $lvl -BackgroundColor $back}
        Write-Host $suffix
    } else {
        Write-Host "$prefix$lvl$suffix"
    }

    if($sev -ge 4 -and $ErrorActionPreference -eq 'Stop'){throw ("ConsoleLog.{0}: {1}" -f $lvl,$Message)}
}


function Invoke-WebRequestEx {
<#
.SYNOPSIS
    Invokes a web request with retries, proxy/TLS handling, and optional streaming downloads.

.DESCRIPTION
    Wraps Invoke-WebRequest for Windows PowerShell 5.1 and adds:
    - TLS 1.2 enablement
    - OutFile parent directory creation
    - Proxy auto-discovery when the caller did not specify proxy settings
    - Retry handling for all HTTP methods
    - Optional total retry budget
    - Optional streaming download path for compatible GET + OutFile scenarios
    - Optional certificate validation bypass for development environments
    - Optional automatic upgrade to UseDefaultCredentials after an unauthenticated 401 response when WWW-Authenticate is present
      and the target resolves as intranet-like via dotless host, loopback, or private/link-local addressing

    Compatibility is prioritized. Native Invoke-WebRequest remains the default
    engine. The streaming engine is only used when the request looks like a
    simple download and no compatibility-sensitive parameters are present.

.PARAMETER Uri
    The request URI.

.PARAMETER RetryCount
    The maximum number of attempts for the request. Applies to all methods.

.PARAMETER RetryDelayMilliseconds
    The delay between retry attempts in milliseconds.

.PARAMETER TotalTimeoutSec
    Optional total retry budget in seconds. Zero disables the total retry
    budget and leaves timeout behavior to individual attempts.

.PARAMETER BufferSizeBytes
    The streaming download buffer size in bytes.

.PARAMETER ProgressIntervalPercent
    The streaming progress interval for known content length.

.PARAMETER ProgressIntervalBytes
    The streaming progress interval for unknown content length.

.PARAMETER UseStreamingDownload
    Prefer the streaming download engine when the request is compatible with it.

.PARAMETER SkipCertificateCheck
    Skips TLS server certificate validation for this request. Intended for
    development or lab scenarios only.

.PARAMETER DisableAutoUseDefaultCredentials
    Disables the automatic retry with UseDefaultCredentials when the initial
    unauthenticated request receives a 401 response with a WWW-Authenticate
    challenge and the target resolves as intranet-like.

.PARAMETER AllowSelfSigned
    Legacy alias for SkipCertificateCheck.

.EXAMPLE
    Invoke-WebRequestEx -Uri 'https://example.org'

.EXAMPLE
    Invoke-WebRequestEx -Uri 'https://example.org/file.iso' -OutFile 'C:\Temp\file.iso'

.EXAMPLE
    Invoke-WebRequestEx -Uri 'https://example.org/api' -Method Post -Body '{ "a": 1 }' -RetryCount 3

.EXAMPLE
    Invoke-WebRequestEx -Uri 'https://devbox.local/file.zip' -OutFile 'C:\Temp\file.zip' -SkipCertificateCheck
#>
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias('Url')]
        [uri]$Uri,

        [Parameter()]
        [switch]$UseBasicParsing,

        [Parameter()]
        [Microsoft.PowerShell.Commands.WebRequestSession]$WebSession,

        [Parameter()]
        [string]$SessionVariable,

        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter()]
        [switch]$UseDefaultCredentials,

        [Parameter()]
        [string]$CertificateThumbprint,

        [Parameter()]
        [System.Security.Cryptography.X509Certificates.X509Certificate]$Certificate,

        [Parameter()]
        [string]$UserAgent,

        [Parameter()]
        [switch]$DisableKeepAlive,

        [Parameter()]
        [int]$TimeoutSec,

        [Parameter()]
        [System.Collections.IDictionary]$Headers,

        [Parameter()]
        [int]$MaximumRedirection,

        [Parameter()]
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method,

        [Parameter()]
        [uri]$Proxy,

        [Parameter()]
        [System.Management.Automation.PSCredential]$ProxyCredential,

        [Parameter()]
        [switch]$ProxyUseDefaultCredentials,

        [Parameter()]
        [object]$Body,

        [Parameter()]
        [string]$ContentType,

        [Parameter()]
        [string]$TransferEncoding,

        [Parameter()]
        [string]$InFile,

        [Parameter()]
        [string]$OutFile,

        [Parameter()]
        [switch]$PassThru,

        [Parameter()]
        [Alias('AllowSelfSigned')]
        [switch]$SkipCertificateCheck,

        [Parameter()]
        [switch]$DisableAutoUseDefaultCredentials,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$RetryCount = 3,

        [Parameter()]
        [ValidateRange(0, 86400000)]
        [int]$RetryDelayMilliseconds = 1000,

        [Parameter()]
        [ValidateRange(0, 2147483647)]
        [int]$TotalTimeoutSec = 0,

        [Parameter()]
        [ValidateRange(1024, 268435456)]
        [Alias('BufferSize')]
        [int]$BufferSizeBytes = 4194304,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$ProgressIntervalPercent = 10,

        [Parameter()]
        [ValidateRange(1048576, 9223372036854775807)]
        [long]$ProgressIntervalBytes = 52428800,

        [Parameter()]
        [switch]$UseStreamingDownload
    )

    function _UriDisplayShortener {
        param(
            [Parameter(Mandatory = $true)]
            [uri]$TargetUri
        )

        $originalText = [string]$TargetUri
        if ([string]::IsNullOrWhiteSpace($originalText)) {
            return $originalText
        }

        try {
            $authority = $TargetUri.GetLeftPart([System.UriPartial]::Authority)
            $absolutePath = $TargetUri.AbsolutePath

            $querySuffix = if (-not [string]::IsNullOrEmpty($TargetUri.Query)) { '?...' } else { '' }
            $fragmentSuffix = if (-not [string]::IsNullOrEmpty($TargetUri.Fragment)) { '#...' } else { '' }

            if ([string]::IsNullOrEmpty($absolutePath) -or $absolutePath -eq '/') {
                return ($authority + '/' + $querySuffix + $fragmentSuffix)
            }

            $segments = @($absolutePath -split '/' | Where-Object { $_ -ne '' })

            if ($segments.Count -le 1) {
                return ($authority + $absolutePath + $querySuffix + $fragmentSuffix)
            }

            if ($segments.Count -eq 2) {
                return ($authority + '/' + $segments[0] + '/' + $segments[1] + $querySuffix + $fragmentSuffix)
            }

            if ($absolutePath.EndsWith('/')) {
                return ($authority + '/..../' + $querySuffix + $fragmentSuffix)
            }

            $lastSegment = $segments[$segments.Count - 1]
            return ($authority + '/..../' + $lastSegment + $querySuffix + $fragmentSuffix)
        }
        catch {
            return $originalText
        }
    }

    function _GetResponseFromErrorRecord {
        param(
            [Parameter(Mandatory = $true)]
            [System.Management.Automation.ErrorRecord]$ErrorRecord
        )

        foreach ($candidate in @($ErrorRecord.Exception, $ErrorRecord.Exception.InnerException)) {
            if ($null -eq $candidate) { continue }

            $responseProperty = $candidate.PSObject.Properties['Response']
            if ($responseProperty -and $null -ne $responseProperty.Value) {
                return $responseProperty.Value
            }
        }

        return $null
    }

    function _GetHttpStatusCodeFromErrorRecord {
        param(
            [Parameter(Mandatory = $true)]
            [System.Management.Automation.ErrorRecord]$ErrorRecord
        )

        $response = _GetResponseFromErrorRecord -ErrorRecord $ErrorRecord
        if ($null -ne $response) {
            try {
                if ($null -ne $response.StatusCode) {
                    return [int]$response.StatusCode
                }
            }
            catch {
            }
        }

        foreach ($candidate in @($ErrorRecord.Exception, $ErrorRecord.Exception.InnerException)) {
            if ($null -eq $candidate) { continue }

            $statusCodeProperty = $candidate.PSObject.Properties['StatusCode']
            if ($statusCodeProperty -and $null -ne $statusCodeProperty.Value) {
                try {
                    return [int]$statusCodeProperty.Value
                }
                catch {
                }
            }
        }

        return $null
    }

    function _GetWwwAuthenticateValuesFromErrorRecord {
        param(
            [Parameter(Mandatory = $true)]
            [System.Management.Automation.ErrorRecord]$ErrorRecord
        )

        $values = New-Object System.Collections.Generic.List[string]
        $response = _GetResponseFromErrorRecord -ErrorRecord $ErrorRecord

        if ($null -ne $response) {
            try {
                $headers = $response.Headers

                if ($null -ne $headers) {
                    $directValue = $headers['WWW-Authenticate']
                    if (-not [string]::IsNullOrWhiteSpace([string]$directValue)) {
                        $values.Add([string]$directValue)
                    }

                    $wwwAuthenticateProperty = $headers.PSObject.Properties['WwwAuthenticate']
                    if ($wwwAuthenticateProperty -and $null -ne $wwwAuthenticateProperty.Value) {
                        foreach ($headerValue in @($wwwAuthenticateProperty.Value)) {
                            if ($null -eq $headerValue) { continue }

                            $headerText = [string]$headerValue
                            if (-not [string]::IsNullOrWhiteSpace($headerText)) {
                                $values.Add($headerText)
                            }
                        }
                    }
                }
            }
            catch {
            }
        }

        $seen = @{}
        $result = New-Object System.Collections.Generic.List[string]

        foreach ($value in $values) {
            if (-not $seen.ContainsKey($value)) {
                $seen[$value] = $true
                $result.Add($value)
            }
        }

        return ,$result.ToArray()
    }

    function _TestIsPrivateOrIntranetAddress {
        param(
            [Parameter(Mandatory = $true)]
            [System.Net.IPAddress]$Address
        )

        if ([System.Net.IPAddress]::IsLoopback($Address)) {
            return $true
        }

        if ($Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
            if ($Address.IsIPv4MappedToIPv6) {
                try {
                    return _TestIsPrivateOrIntranetAddress -Address $Address.MapToIPv4()
                }
                catch {
                    return $false
                }
            }

            $bytes = $Address.GetAddressBytes()
            if ($bytes.Length -ge 2) {
                # fc00::/7 Unique Local Address
                if (($bytes[0] -band 0xFE) -eq 0xFC) {
                    return $true
                }

                # fe80::/10 Link-local
                if ($bytes[0] -eq 0xFE -and ($bytes[1] -band 0xC0) -eq 0x80) {
                    return $true
                }
            }

            return $false
        }

        if ($Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
            $bytes = $Address.GetAddressBytes()

            if ($bytes[0] -eq 10) { return $true }
            if ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) { return $true }
            if ($bytes[0] -eq 192 -and $bytes[1] -eq 168) { return $true }
            if ($bytes[0] -eq 169 -and $bytes[1] -eq 254) { return $true }
            if ($bytes[0] -eq 127) { return $true }

            return $false
        }

        return $false
    }

    function _GetAutoUseDefaultCredentialsGuardInfo {
        param(
            [Parameter(Mandatory = $true)]
            [uri]$TargetUri
        )

        $signals = New-Object System.Collections.Generic.List[string]
        $resolvedAddresses = New-Object System.Collections.Generic.List[string]

        $hostname = if (-not [string]::IsNullOrWhiteSpace($TargetUri.DnsSafeHost)) {
            $TargetUri.DnsSafeHost
        }
        else {
            $TargetUri.Host
        }

        if ($TargetUri.IsLoopback) {
            $signals.Add("The URI is loopback.")
        }

        if (-not [string]::IsNullOrWhiteSpace($hostname)) {
            $hostAddress = $null

            if ([System.Net.IPAddress]::TryParse($hostname, [ref]$hostAddress)) {
                $resolvedAddresses.Add($hostAddress.IPAddressToString)

                if (_TestIsPrivateOrIntranetAddress -Address $hostAddress) {
                    $signals.Add("The host is a private, link-local, or loopback IP address ('$($hostAddress.IPAddressToString)').")
                }
            }
            else {
                if ($hostname.IndexOf('.') -lt 0) {
                    $signals.Add("The host '$hostname' is dotless and intranet-like.")
                }

                try {
                    $addresses = [System.Net.Dns]::GetHostAddresses($hostname)

                    foreach ($address in $addresses) {
                        $addressText = $address.IPAddressToString

                        if (-not $resolvedAddresses.Contains($addressText)) {
                            $resolvedAddresses.Add($addressText)
                        }

                        if (_TestIsPrivateOrIntranetAddress -Address $address) {
                            $signals.Add("DNS resolved '$hostname' to private, link-local, or loopback address '$addressText'.")
                            break
                        }
                    }
                }
                catch {
                }
            }
        }

        return [pscustomobject]@{
            IsIntranetLike    = ($signals.Count -gt 0)
            Signals           = @($signals.ToArray())
            ResolvedAddresses = @($resolvedAddresses.ToArray())
        }
    }

    $uriDisplay = _UriDisplayShortener -TargetUri $Uri

    Write-StandardMessage -Message ("[STATUS] Initializing Invoke-WebRequestEx for '{0}'." -f $uriDisplay) -Level INF

    $effectiveMethod = if ($PSBoundParameters.ContainsKey('Method') -and $null -ne $Method) {
        $Method.ToString().ToUpperInvariant()
    }
    else {
        'GET'
    }

    $runningOnPwsh = $PSVersionTable.PSEdition -eq 'Core'
    $nativeSupportsSkipCertificateCheck = $runningOnPwsh -and $PSVersionTable.PSVersion -ge [version]'7.0'

    $explicitCredentialSupplied = $PSBoundParameters.ContainsKey('Credential') -and $null -ne $Credential
    $explicitUseDefaultCredentialsSupplied = $PSBoundParameters.ContainsKey('UseDefaultCredentials')
    $autoUseDefaultCredentialsAllowed =
        (-not $DisableAutoUseDefaultCredentials) -and
        (-not $explicitCredentialSupplied) -and
        (-not $explicitUseDefaultCredentialsSupplied)

    $autoUpgradedToDefaultCredentials = $false
    $autoUseDefaultCredentialsGuardInfo = $null
    $autoUseDefaultCredentialsGuardInfoResolved = $false

    $callParams = @{}
    foreach ($entry in $PSBoundParameters.GetEnumerator()) {
        switch ($entry.Key) {
            'SkipCertificateCheck' {
                if ($nativeSupportsSkipCertificateCheck) {
                    $callParams[$entry.Key] = $entry.Value
                }
                continue
            }
            'DisableAutoUseDefaultCredentials' { continue }
            'RetryCount' { continue }
            'RetryDelayMilliseconds' { continue }
            'TotalTimeoutSec' { continue }
            'BufferSizeBytes' { continue }
            'ProgressIntervalPercent' { continue }
            'ProgressIntervalBytes' { continue }
            'UseStreamingDownload' { continue }
            default { $callParams[$entry.Key] = $entry.Value }
        }
    }

    # --- TLS: Ensure TLS 1.2 is enabled (additive; do not remove other flags) ---
    try {
        $tls12 = [System.Net.SecurityProtocolType]::Tls12
        $currentProtocols = [System.Net.ServicePointManager]::SecurityProtocol

        if (($currentProtocols -band $tls12) -ne $tls12) {
            [System.Net.ServicePointManager]::SecurityProtocol = $currentProtocols -bor $tls12
            Write-StandardMessage -Message "[STATUS] Added TLS 1.2 to the current process security protocol flags." -Level INF
        }
    }
    catch {
        Write-StandardMessage -Message ("[WRN] Failed to ensure TLS 1.2: {0}" -f $_.Exception.Message) -Level WRN
    }

    # --- OutFile: Ensure parent directory exists ---
    if ($PSBoundParameters.ContainsKey('OutFile')) {
        try {
            $directory = [System.IO.Path]::GetDirectoryName($OutFile)

            if (-not [string]::IsNullOrWhiteSpace($directory)) {
                if (-not [System.IO.Directory]::Exists($directory)) {
                    [void][System.IO.Directory]::CreateDirectory($directory)
                    Write-StandardMessage -Message ("[STATUS] Created output directory '{0}'." -f $directory) -Level INF
                }
            }
        }
        catch {
            Write-StandardMessage -Message ("[ERR] Failed to prepare output directory for '{0}': {1}" -f $OutFile, $_.Exception.Message) -Level ERR
            throw
        }
    }

    # --- Proxy: auto-discover unless caller explicitly handled proxy settings ---
    $callerHandledProxy =
        $PSBoundParameters.ContainsKey('Proxy') -or
        $PSBoundParameters.ContainsKey('ProxyCredential') -or
        $PSBoundParameters.ContainsKey('ProxyUseDefaultCredentials')

    if (-not $callerHandledProxy) {
        try {
            $systemProxy = [System.Net.WebRequest]::GetSystemWebProxy()
            $systemProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials

            if (-not $systemProxy.IsBypassed($Uri)) {
                $proxyUri = $systemProxy.GetProxy($Uri)

                if ($null -ne $proxyUri -and $proxyUri.AbsoluteUri -ne $Uri.AbsoluteUri) {
                    $callParams['Proxy'] = $proxyUri
                    $callParams['ProxyUseDefaultCredentials'] = $true
                    Write-StandardMessage -Message ("[STATUS] Using auto-discovered proxy '{0}' for '{1}'." -f $proxyUri.AbsoluteUri, $uriDisplay) -Level INF
                }
                else {
                    Write-StandardMessage -Message ("[STATUS] System proxy configuration resolved no distinct proxy for '{0}'." -f $uriDisplay) -Level INF
                }
            }
            else {
                Write-StandardMessage -Message ("[STATUS] System proxy bypass is active for '{0}'." -f $uriDisplay) -Level INF
            }
        }
        catch {
            Write-StandardMessage -Message ("[WRN] Failed to auto-discover proxy for '{0}': {1}" -f $uriDisplay, $_.Exception.Message) -Level WRN
        }
    }
    else {
        Write-StandardMessage -Message ("[STATUS] Caller supplied proxy-related parameters for '{0}'. Auto-discovery is skipped." -f $uriDisplay) -Level INF
    }

    # --- Decide whether the streaming download engine can be used safely ---
    $useStreamingEngine = $false
    $streamingCompatible = $false

    $isDownloadShape =
        $PSBoundParameters.ContainsKey('OutFile') -and
        $effectiveMethod -eq 'GET'

    if ($UseStreamingDownload -or $isDownloadShape) {
        $streamingCompatible = $true

        if (-not $PSBoundParameters.ContainsKey('OutFile')) { $streamingCompatible = $false }
        if ($effectiveMethod -ne 'GET') { $streamingCompatible = $false }

        $incompatibleParameters = @(
            'PassThru',
            'WebSession',
            'SessionVariable',
            'InFile',
            'Body',
            'ContentType',
            'TransferEncoding',
            'CertificateThumbprint',
            'Certificate'
        )

        foreach ($parameterName in $incompatibleParameters) {
            if ($PSBoundParameters.ContainsKey($parameterName)) {
                $streamingCompatible = $false
                break
            }
        }

        if ($streamingCompatible -and $Headers) {
            foreach ($headerKey in $Headers.Keys) {
                $headerName = [string]$headerKey
                if ($headerName -match '^(?i:Cookie|Date|Range)$') {
                    $streamingCompatible = $false
                    break
                }
            }
        }

        if ($streamingCompatible) {
            $useStreamingEngine = $true
        }
        elseif ($UseStreamingDownload) {
            Write-StandardMessage -Message (
                "[WRN] Streaming download was requested, but the current parameter combination is not safely compatible. Falling back to native Invoke-WebRequest for '{0}'." -f $uriDisplay
            ) -Level WRN
        }
    }

    if ($nativeSupportsSkipCertificateCheck -and $SkipCertificateCheck) {
        $useStreamingEngine = $false
        Write-StandardMessage -Message (
            "[STATUS] PowerShell {0} will pass -SkipCertificateCheck directly to native Invoke-WebRequest. Streaming path is disabled for '{1}'." -f
            $PSVersionTable.PSVersion, $uriDisplay
        ) -Level INF
    }

    if ($useStreamingEngine) {
        Write-StandardMessage -Message ("[STATUS] Using the streaming download path for '{0}'." -f $uriDisplay) -Level INF
    }
    else {
        Write-StandardMessage -Message ("[STATUS] Using the native Invoke-WebRequest path for '{0}'." -f $uriDisplay) -Level INF
    }

    # --- Certificate validation bypass for PS 5.1 (.NET Framework) ---
    $previousCertificateValidationCallback = $null
    $skipCertificateCheckEnabled = $false

    try {
        if ($SkipCertificateCheck -and -not $nativeSupportsSkipCertificateCheck) {
            Write-StandardMessage -Message ("[STATUS] Enabling temporary certificate validation bypass for '{0}'." -f $uriDisplay) -Level INF

            if (-not ('CertificateValidationHelper' -as [type])) {
                Add-Type -TypeDefinition @'
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

public static class CertificateValidationHelper
{
    public static bool AcceptAll(
        object sender,
        X509Certificate certificate,
        X509Chain chain,
        SslPolicyErrors sslPolicyErrors)
    {
        return true;
    }
}
'@
            }

            $bindingFlags =
                [System.Reflection.BindingFlags]::Public -bor
                [System.Reflection.BindingFlags]::Static

            $methodInfo = [CertificateValidationHelper].GetMethod('AcceptAll', $bindingFlags)

            if ($null -eq $methodInfo) {
                throw "Failed to resolve CertificateValidationHelper.AcceptAll."
            }

            $acceptAllCallback = [System.Net.Security.RemoteCertificateValidationCallback](
                [System.Delegate]::CreateDelegate(
                    [System.Net.Security.RemoteCertificateValidationCallback],
                    $methodInfo
                )
            )

            $previousCertificateValidationCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $acceptAllCallback
            $skipCertificateCheckEnabled = $true
        }

        $retryStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        for ($attemptIndex = 1; $attemptIndex -le $RetryCount; $attemptIndex++) {
            $requestUseDefaultCredentials =
                ($autoUpgradedToDefaultCredentials) -or
                ($explicitUseDefaultCredentialsSupplied -and [bool]$UseDefaultCredentials)

            if (-not $requestUseDefaultCredentials -and $callParams.ContainsKey('UseDefaultCredentials') -and -not $explicitUseDefaultCredentialsSupplied) {
                [void]$callParams.Remove('UseDefaultCredentials')
            }

            if ($requestUseDefaultCredentials -and -not $useStreamingEngine) {
                $callParams['UseDefaultCredentials'] = $true
            }

            if ($attemptIndex -gt 1) {
                Write-StandardMessage -Message (
                    "[STATUS] Starting attempt {0} of {1} for {2} {3}." -f $attemptIndex, $RetryCount, $effectiveMethod, $uriDisplay
                ) -Level INF
            }

            while ($true) {
                try {
                    if ($useStreamingEngine) {
                        $request = $null
                        $response = $null
                        $responseStream = $null
                        $fileStream = $null

                        try {
                            $request = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($Uri)
                            if ($null -eq $request) {
                                throw ("Failed to create HttpWebRequest for '{0}'." -f $uriDisplay)
                            }

                            $request.Method = 'GET'
                            $request.AutomaticDecompression =
                                [System.Net.DecompressionMethods]::GZip -bor
                                [System.Net.DecompressionMethods]::Deflate

                            if ($DisableKeepAlive) {
                                $request.KeepAlive = $false
                            }

                            if ($PSBoundParameters.ContainsKey('MaximumRedirection')) {
                                if ($MaximumRedirection -le 0) {
                                    $request.AllowAutoRedirect = $false
                                }
                                else {
                                    $request.AllowAutoRedirect = $true
                                    $request.MaximumAutomaticRedirections = $MaximumRedirection
                                }
                            }

                            if ($TimeoutSec -gt 0) {
                                $timeoutMilliseconds = $TimeoutSec * 1000
                                $request.Timeout = $timeoutMilliseconds
                                $request.ReadWriteTimeout = $timeoutMilliseconds
                            }

                            if ($explicitCredentialSupplied) {
                                $request.Credentials = $Credential
                            }
                            elseif ($requestUseDefaultCredentials) {
                                $request.Credentials = [System.Net.CredentialCache]::DefaultCredentials
                            }

                            if ($callParams.ContainsKey('Proxy') -and $null -ne $callParams['Proxy']) {
                                $webProxy = New-Object System.Net.WebProxy(([uri]$callParams['Proxy']).AbsoluteUri, $true)

                                if ($PSBoundParameters.ContainsKey('ProxyCredential') -and $null -ne $ProxyCredential) {
                                    $webProxy.Credentials = $ProxyCredential
                                }
                                elseif ($callParams.ContainsKey('ProxyUseDefaultCredentials') -and [bool]$callParams['ProxyUseDefaultCredentials']) {
                                    $webProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
                                }

                                $request.Proxy = $webProxy
                            }

                            if ($PSBoundParameters.ContainsKey('UserAgent') -and -not [string]::IsNullOrWhiteSpace($UserAgent)) {
                                $request.UserAgent = $UserAgent
                            }

                            if ($Headers) {
                                foreach ($headerKey in $Headers.Keys) {
                                    $headerName = [string]$headerKey
                                    $headerValue = [string]$Headers[$headerKey]

                                    switch -Regex ($headerName) {
                                        '^(?i:Accept)$' {
                                            $request.Accept = $headerValue
                                            continue
                                        }
                                        '^(?i:Connection)$' {
                                            if ($headerValue -match '^(?i:close)$') {
                                                $request.KeepAlive = $false
                                            }
                                            else {
                                                $request.Connection = $headerValue
                                            }
                                            continue
                                        }
                                        '^(?i:Content-Type)$' {
                                            $request.ContentType = $headerValue
                                            continue
                                        }
                                        '^(?i:Expect)$' {
                                            $request.Expect = $headerValue
                                            continue
                                        }
                                        '^(?i:Host)$' {
                                            $request.Host = $headerValue
                                            continue
                                        }
                                        '^(?i:If-Modified-Since)$' {
                                            $request.IfModifiedSince = [DateTime]::Parse($headerValue, [System.Globalization.CultureInfo]::InvariantCulture)
                                            continue
                                        }
                                        '^(?i:Referer)$' {
                                            $request.Referer = $headerValue
                                            continue
                                        }
                                        '^(?i:Transfer-Encoding)$' {
                                            $request.SendChunked = $true
                                            $request.TransferEncoding = $headerValue
                                            continue
                                        }
                                        '^(?i:User-Agent)$' {
                                            if ([string]::IsNullOrWhiteSpace($request.UserAgent)) {
                                                $request.UserAgent = $headerValue
                                            }
                                            continue
                                        }
                                        default {
                                            $request.Headers[$headerName] = $headerValue
                                            continue
                                        }
                                    }
                                }
                            }

                            Write-StandardMessage -Message ("[STATUS] Sending streaming GET request to '{0}'." -f $uriDisplay) -Level INF

                            $response = [System.Net.HttpWebResponse]$request.GetResponse()
                            $responseStream = $response.GetResponseStream()

                            if ($null -eq $responseStream) {
                                throw ("The remote server returned an empty response stream for '{0}'." -f $uriDisplay)
                            }

                            $fileStream = [System.IO.File]::Open(
                                $OutFile,
                                [System.IO.FileMode]::Create,
                                [System.IO.FileAccess]::Write,
                                [System.IO.FileShare]::None
                            )

                            $buffer = New-Object byte[] $BufferSizeBytes
                            $totalBytes = 0L
                            $contentLength = [long]$response.ContentLength
                            $displayThresholdBytes = 1048576L
                            $useMegabyteDisplay = $contentLength -gt $displayThresholdBytes

                            if ($contentLength -gt 0) {
                                $progressThresholdBytes = [long][Math]::Floor($contentLength * ($ProgressIntervalPercent / 100.0))
                                if ($progressThresholdBytes -lt 1048576) {
                                    $progressThresholdBytes = 1048576
                                }
                            }
                            else {
                                $progressThresholdBytes = $ProgressIntervalBytes
                            }

                            if ($progressThresholdBytes -le 0) {
                                $progressThresholdBytes = 1048576
                            }

                            $nextProgressBytes = $progressThresholdBytes

                            while ($true) {
                                $bytesRead = $responseStream.Read($buffer, 0, $buffer.Length)
                                if ($bytesRead -le 0) {
                                    break
                                }

                                $fileStream.Write($buffer, 0, $bytesRead)
                                $totalBytes += [long]$bytesRead

                                if ($totalBytes -ge $nextProgressBytes) {
                                    if ($contentLength -gt 0) {
                                        $percent = [Math]::Round(($totalBytes * 100.0) / $contentLength, 1)
                                        if ($percent -gt 100) {
                                            $percent = 100
                                        }

                                        if ($useMegabyteDisplay) {
                                            $downloadedMb = [Math]::Round($totalBytes / 1048576.0, 1)
                                            $contentLengthMb = [Math]::Round($contentLength / 1048576.0, 1)

                                            Write-StandardMessage -Message (
                                                "[PROGRESS] Downloaded {0} MB of {1} MB ({2} percent) for '{3}'." -f
                                                $downloadedMb, $contentLengthMb, $percent, $uriDisplay
                                            ) -Level INF
                                        }
                                        else {
                                            Write-StandardMessage -Message (
                                                "[PROGRESS] Downloaded {0} of {1} bytes ({2} percent) for '{3}'." -f
                                                $totalBytes, $contentLength, $percent, $uriDisplay
                                            ) -Level INF
                                        }
                                    }
                                    else {
                                        $megaBytes = [Math]::Round($totalBytes / 1048576.0, 1)
                                        Write-StandardMessage -Message (
                                            "[PROGRESS] Downloaded approximately {0} MB from '{1}'." -f
                                            $megaBytes, $uriDisplay
                                        ) -Level INF
                                    }

                                    $nextProgressBytes += $progressThresholdBytes
                                }
                            }

                            if ($contentLength -gt 0) {
                                if ($useMegabyteDisplay) {
                                    $totalMb = [Math]::Round($totalBytes / 1048576.0, 1)
                                    $contentLengthMb = [Math]::Round($contentLength / 1048576.0, 1)

                                    Write-StandardMessage -Message (
                                        "[PROGRESS] Downloaded {0} MB of {1} MB (100 percent) for '{2}'." -f
                                        $totalMb, $contentLengthMb, $uriDisplay
                                    ) -Level INF
                                }
                                else {
                                    Write-StandardMessage -Message (
                                        "[PROGRESS] Downloaded {0} of {1} bytes (100 percent) for '{2}'." -f
                                        $totalBytes, $contentLength, $uriDisplay
                                    ) -Level INF
                                }
                            }
                            else {
                                $finalMb = [Math]::Round($totalBytes / 1048576.0, 1)
                                Write-StandardMessage -Message (
                                    "[PROGRESS] Download complete, total {0} MB from '{1}'." -f
                                    $finalMb, $uriDisplay
                                ) -Level INF
                            }

                            Write-StandardMessage -Message (
                                "[OK] Downloaded {0} bytes from '{1}' to '{2}' on attempt {3} of {4}." -f
                                $totalBytes, $uriDisplay, $OutFile, $attemptIndex, $RetryCount
                            ) -Level INF

                            return
                        }
                        finally {
                            if ($null -ne $responseStream) {
                                $responseStream.Dispose()
                            }

                            if ($null -ne $fileStream) {
                                $fileStream.Dispose()
                            }

                            if ($null -ne $response) {
                                $response.Close()
                            }
                        }
                    }
                    else {
                        $result = Invoke-WebRequest @callParams

                        Write-StandardMessage -Message (
                            "[OK] Request completed successfully on attempt {0} of {1} for {2} {3}." -f
                            $attemptIndex, $RetryCount, $effectiveMethod, $uriDisplay
                        ) -Level INF

                        return $result
                    }
                }
                catch {
                    $statusCode = _GetHttpStatusCodeFromErrorRecord -ErrorRecord $_
                    $wwwAuthenticateValues = _GetWwwAuthenticateValuesFromErrorRecord -ErrorRecord $_
                    $hasWwwAuthenticateChallenge = $wwwAuthenticateValues.Count -gt 0

                    $hasAutoUpgradeTrigger =
                        $autoUseDefaultCredentialsAllowed -and
                        (-not $requestUseDefaultCredentials) -and
                        ($statusCode -eq 401) -and
                        $hasWwwAuthenticateChallenge

                    if ($hasAutoUpgradeTrigger -and -not $autoUseDefaultCredentialsGuardInfoResolved) {
                        $autoUseDefaultCredentialsGuardInfo = _GetAutoUseDefaultCredentialsGuardInfo -TargetUri $Uri
                        $autoUseDefaultCredentialsGuardInfoResolved = $true

                        if ($autoUseDefaultCredentialsGuardInfo.IsIntranetLike) {
                            Write-StandardMessage -Message (
                                "[STATUS] Automatic default-credentials guard passed for '{0}'. Signal(s): {1}" -f
                                $uriDisplay, ($autoUseDefaultCredentialsGuardInfo.Signals -join '; ')
                            ) -Level INF
                        }
                        else {
                            $resolvedAddressText = if ($autoUseDefaultCredentialsGuardInfo.ResolvedAddresses.Count -gt 0) {
                                $autoUseDefaultCredentialsGuardInfo.ResolvedAddresses -join ', '
                            }
                            else {
                                'none'
                            }

                            Write-StandardMessage -Message (
                                "[STATUS] Automatic default-credentials guard blocked upgrade for '{0}'. No intranet-like signals were found. Resolved address(es): {1}" -f
                                $uriDisplay, $resolvedAddressText
                            ) -Level INF
                        }
                    }

                    $shouldAutoUpgradeToDefaultCredentials =
                        $hasAutoUpgradeTrigger -and
                        $autoUseDefaultCredentialsGuardInfoResolved -and
                        $autoUseDefaultCredentialsGuardInfo.IsIntranetLike

                    if ($shouldAutoUpgradeToDefaultCredentials) {
                        $requestUseDefaultCredentials = $true
                        $autoUpgradedToDefaultCredentials = $true

                        if (-not $useStreamingEngine) {
                            $callParams['UseDefaultCredentials'] = $true
                        }

                        Write-StandardMessage -Message (
                            "[STATUS] Received 401 with WWW-Authenticate challenge for '{0}'. Retrying the current attempt with default credentials. Challenge(s): {1}" -f
                            $uriDisplay, ($wwwAuthenticateValues -join ', ')
                        ) -Level WRN

                        continue
                    }

                    $remainingMilliseconds = [int]::MaxValue
                    if ($TotalTimeoutSec -gt 0) {
                        $remainingMilliseconds = [int](($TotalTimeoutSec * 1000) - $retryStopwatch.ElapsedMilliseconds)
                    }

                    $isLastAttempt = $attemptIndex -ge $RetryCount
                    $retryBudgetExpired = ($TotalTimeoutSec -gt 0 -and $remainingMilliseconds -le 0)

                    if ($isLastAttempt -or $retryBudgetExpired) {
                        if ($retryBudgetExpired) {
                            Write-StandardMessage -Message (
                                "[ERR] Retry budget expired after {0} ms while processing {1} {2}: {3}" -f
                                $retryStopwatch.ElapsedMilliseconds, $effectiveMethod, $uriDisplay, $_.Exception.Message
                            ) -Level ERR
                        }
                        else {
                            Write-StandardMessage -Message (
                                "[ERR] Attempt {0} of {1} failed and no retries remain for {2} {3}: {4}" -f
                                $attemptIndex, $RetryCount, $effectiveMethod, $uriDisplay, $_.Exception.Message
                            ) -Level ERR
                        }

                        throw
                    }

                    $sleepMilliseconds = $RetryDelayMilliseconds
                    if ($TotalTimeoutSec -gt 0 -and $sleepMilliseconds -gt $remainingMilliseconds) {
                        $sleepMilliseconds = $remainingMilliseconds
                    }

                    if ($sleepMilliseconds -lt 0) {
                        $sleepMilliseconds = 0
                    }

                    Write-StandardMessage -Message (
                        "[RETRY] Attempt {0} of {1} failed for {2} {3}: {4}. Retrying in {5} ms." -f
                        $attemptIndex, $RetryCount, $effectiveMethod, $uriDisplay, $_.Exception.Message, $sleepMilliseconds
                    ) -Level WRN

                    if ($sleepMilliseconds -gt 0) {
                        Start-Sleep -Milliseconds $sleepMilliseconds
                    }

                    break
                }
            }
        }
    }
    finally {
        if ($skipCertificateCheckEnabled) {
            if ($null -eq $previousCertificateValidationCallback) {
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback =
                    [System.Net.Security.RemoteCertificateValidationCallback]$null
            }
            else {
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $previousCertificateValidationCallback
            }
        }
    }
}