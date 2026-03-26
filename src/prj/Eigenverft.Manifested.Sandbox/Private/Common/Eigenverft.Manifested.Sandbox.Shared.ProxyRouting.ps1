<#
    Eigenverft.Manifested.Sandbox.Shared.ProxyRouting
#>

function Resolve-ManifestedProxyRoute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [uri]$TargetUri
    )

    $proxyUri = $null

    try {
        $systemProxy = [System.Net.WebRequest]::GetSystemWebProxy()
        if ($null -ne $systemProxy) {
            $systemProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials

            if (-not $systemProxy.IsBypassed($TargetUri)) {
                $candidateProxyUri = $systemProxy.GetProxy($TargetUri)
                if ($null -ne $candidateProxyUri -and $candidateProxyUri.AbsoluteUri -ne $TargetUri.AbsoluteUri) {
                    $proxyUri = $candidateProxyUri
                }
            }
        }
    }
    catch {
        $proxyUri = $null
    }

    [pscustomobject]@{
        TargetUri      = $TargetUri.AbsoluteUri
        TargetHost     = $TargetUri.Host
        ProxyUri       = if ($proxyUri) { $proxyUri.AbsoluteUri } else { $null }
        ProxyRequired  = ($null -ne $proxyUri)
        Route          = if ($proxyUri) { 'Proxy' } else { 'Direct' }
    }
}

function Get-ManifestedManagedProxyAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$IsManagedTarget,

        [Parameter(Mandatory = $true)]
        [string]$Route,

        [string]$DesiredProxyUri,

        [string[]]$CurrentValues = @(),

        [Parameter(Mandatory = $true)]
        [string]$ExternalAction,

        [Parameter(Mandatory = $true)]
        [string]$DirectAction,

        [Parameter(Mandatory = $true)]
        [string]$ReusedAction,

        [Parameter(Mandatory = $true)]
        [string]$NeedsAction
    )

    if (-not $IsManagedTarget) {
        return $ExternalAction
    }

    if ($Route -eq 'Direct') {
        return $DirectAction
    }

    $hasCurrentValues = (@($CurrentValues).Count -gt 0)
    $allMatchDesiredProxy = $hasCurrentValues
    foreach ($currentValue in @($CurrentValues)) {
        if ($currentValue -ne $DesiredProxyUri) {
            $allMatchDesiredProxy = $false
            break
        }
    }

    if ($allMatchDesiredProxy) {
        return $ReusedAction
    }

    return $NeedsAction
}
