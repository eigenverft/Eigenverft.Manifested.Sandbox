<#
    Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.Registry
#>

function Test-RegistryPathExists {
<#
.SYNOPSIS
Returns whether a registry path exists.

.DESCRIPTION
Uses the PowerShell registry provider to test for the existence of a registry
path. Failures are treated as non-existent so callers can decide how to handle
missing or unreadable paths.

.EXAMPLE
Test-RegistryPathExists -Path 'HKLM:\SOFTWARE\Vendor\Product'
#>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        return (Test-Path -LiteralPath $Path)
    }
    catch {
        return $false
    }
}

function Get-RegistryValueData {
<#
.SYNOPSIS
Reads a value from a registry path.

.DESCRIPTION
Returns the read result in a normalized object so callers can distinguish
between missing paths, read failures, and successful value reads without
embedding registry-provider mechanics in higher-level workflows.

.EXAMPLE
Get-RegistryValueData -Path 'HKLM:\SOFTWARE\Vendor\Product' -ValueName 'Version'
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [AllowNull()]
        [string]$ValueName
    )

    if (-not (Test-RegistryPathExists -Path $Path)) {
        return [pscustomobject]@{
            Path          = $Path
            ValueName     = $ValueName
            Value         = $null
            Exists        = $false
            ReadSucceeded = $false
            Status        = 'Missing'
        }
    }

    if ([string]::IsNullOrWhiteSpace($ValueName)) {
        return [pscustomobject]@{
            Path          = $Path
            ValueName     = $null
            Value         = $null
            Exists        = $true
            ReadSucceeded = $true
            Status        = 'Ready'
        }
    }

    try {
        $properties = Get-ItemProperty -LiteralPath $Path -Name $ValueName -ErrorAction Stop
        return [pscustomobject]@{
            Path          = $Path
            ValueName     = $ValueName
            Value         = $properties.$ValueName
            Exists        = $true
            ReadSucceeded = $true
            Status        = 'Ready'
        }
    }
    catch {
        return [pscustomobject]@{
            Path          = $Path
            ValueName     = $ValueName
            Value         = $null
            Exists        = $true
            ReadSucceeded = $false
            Status        = 'Failed'
        }
    }
}

function Resolve-RegistryValueFromPaths {
<#
.SYNOPSIS
Finds the first usable registry path from a candidate list.

.DESCRIPTION
Evaluates registry candidate paths in order and returns the first successful
match. If no candidate succeeds, the last failed candidate is preserved so
callers can surface a meaningful path in diagnostics.

.EXAMPLE
Resolve-RegistryValueFromPaths -Paths @('HKLM:\A', 'HKLM:\B') -ValueName 'Version'
#>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [string[]]$Paths,

        [AllowNull()]
        [string]$ValueName
    )

    $candidatePaths = @($Paths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $result = [pscustomobject]@{
        Path         = if ($candidatePaths.Count -gt 0) { $candidatePaths[0] } else { $null }
        Paths        = @($candidatePaths)
        ValueName    = $ValueName
        ActualValue  = $null
        Status       = 'Missing'
    }

    foreach ($candidatePath in $candidatePaths) {
        $candidateResult = Get-RegistryValueData -Path $candidatePath -ValueName $ValueName
        if ($candidateResult.Status -eq 'Missing') {
            continue
        }

        $result.Path = $candidateResult.Path
        $result.ActualValue = $candidateResult.Value
        $result.Status = $candidateResult.Status

        if ($candidateResult.Status -eq 'Ready') {
            break
        }
    }

    return $result
}
