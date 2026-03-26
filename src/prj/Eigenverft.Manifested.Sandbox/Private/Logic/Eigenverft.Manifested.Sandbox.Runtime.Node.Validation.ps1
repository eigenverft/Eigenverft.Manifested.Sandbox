<#
    Eigenverft.Manifested.Sandbox.Runtime.Node.Validation
#>

function Get-NodePackageExpectedSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ShasumsUrl,

        [Parameter(Mandatory = $true)]
        [string]$FileName
    )

    $response = Invoke-WebRequestEx -Uri $ShasumsUrl -UseBasicParsing
    $line = ($response.Content -split "`n" | Where-Object { $_ -match ('\s' + [regex]::Escape($FileName) + '$') } | Select-Object -First 1)

    if (-not $line) {
        throw "Could not find SHA256 for $FileName."
    }

    return (($line -split '\s+')[0]).Trim().ToLowerInvariant()
}

function Test-NodeRuntimePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$PackageInfo
    )

    if (-not (Test-Path -LiteralPath $PackageInfo.Path)) {
        return [pscustomobject]@{
            Status       = 'Missing'
            Version      = $PackageInfo.Version
            Flavor       = $PackageInfo.Flavor
            FileName     = $PackageInfo.FileName
            Path         = $PackageInfo.Path
            Source       = $PackageInfo.Source
            Verified     = $false
            Verification = 'Missing'
            ExpectedHash = $null
            ActualHash   = $null
        }
    }

    $status = 'Ready'
    $verified = $false
    $verification = 'OfflineCache'
    $expectedHash = $null
    $actualHash = $null

    if ($PackageInfo.ShasumsUrl) {
        $expectedHash = Get-NodePackageExpectedSha256 -ShasumsUrl $PackageInfo.ShasumsUrl -FileName $PackageInfo.FileName
        $actualHash = (Get-FileHash -LiteralPath $PackageInfo.Path -Algorithm SHA256).Hash.ToLowerInvariant()
        $verified = $true
        $verification = 'SHA256'
        if ($actualHash -ne $expectedHash) {
            $status = 'CorruptCache'
        }
    }

    [pscustomobject]@{
        Status       = $status
        Version      = $PackageInfo.Version
        Flavor       = $PackageInfo.Flavor
        FileName     = $PackageInfo.FileName
        Path         = $PackageInfo.Path
        Source       = $PackageInfo.Source
        Verified     = $verified
        Verification = $verification
        ExpectedHash = $expectedHash
        ActualHash   = $actualHash
    }
}

