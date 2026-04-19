<#
    Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.StandardMessage
#>

function Write-PackageModelStandardMessage {
<#
.SYNOPSIS
Writes a lightweight PackageModel execution-engine status message.

.DESCRIPTION
Provides a small, package-model-local counterpart to the older StateModel
`Write-StandardMessage` helper. This first pass is intentionally minimal:
severity gating is preserved, but the output stays plain and easy to replace
later when the PackageModel execution engine grows a richer logging contract.

.PARAMETER Message
The message text to write.

.PARAMETER Level
The message severity.

.PARAMETER MinLevel
Optional minimum severity gate. When omitted, the helper first checks
`PackageModelConsoleLogMinLevel`, then `ConsoleLogMinLevel`, and finally falls
back to `INF`.

.EXAMPLE
Write-PackageModelStandardMessage -Message '[STATUS] Resolving VS Code package.'
#>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessage('PSUseApprovedVerbs', '')]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter()]
        [ValidateSet('TRC', 'DBG', 'INF', 'WRN', 'ERR', 'FTL')]
        [string]$Level = 'INF',

        [Parameter()]
        [ValidateSet('TRC', 'DBG', 'INF', 'WRN', 'ERR', 'FTL')]
        [string]$MinLevel
    )

    if ($null -eq $Message) {
        $Message = [string]::Empty
    }

    $severityMap = @{
        TRC = 0
        DBG = 1
        INF = 2
        WRN = 3
        ERR = 4
        FTL = 5
    }

    if (-not $PSBoundParameters.ContainsKey('MinLevel')) {
        $packageModelLevel = Get-Variable PackageModelConsoleLogMinLevel -Scope Global -ErrorAction SilentlyContinue
        $sharedLevel = Get-Variable ConsoleLogMinLevel -Scope Global -ErrorAction SilentlyContinue

        if ($packageModelLevel -and $packageModelLevel.Value -and -not [string]::IsNullOrWhiteSpace([string]$packageModelLevel.Value)) {
            $MinLevel = [string]$packageModelLevel.Value
        }
        elseif ($sharedLevel -and $sharedLevel.Value -and -not [string]::IsNullOrWhiteSpace([string]$sharedLevel.Value)) {
            $MinLevel = [string]$sharedLevel.Value
        }
        else {
            $MinLevel = 'INF'
        }
    }

    $resolvedLevel = $Level.ToUpperInvariant()
    $resolvedMinLevel = $MinLevel.ToUpperInvariant()
    $resolvedSeverity = $severityMap[$resolvedLevel]
    if ($null -eq $resolvedSeverity) {
        $resolvedLevel = 'INF'
        $resolvedSeverity = $severityMap['INF']
    }

    $gatedSeverity = $severityMap[$resolvedMinLevel]
    if ($null -eq $gatedSeverity) {
        $resolvedMinLevel = 'INF'
        $gatedSeverity = $severityMap['INF']
    }

    if ($resolvedSeverity -ge 4 -and $resolvedSeverity -lt $gatedSeverity -and $gatedSeverity -ge 4) {
        $resolvedLevel = $resolvedMinLevel
        $resolvedSeverity = $gatedSeverity
    }

    if ($resolvedSeverity -lt $gatedSeverity) {
        return
    }

    $timestamp = [DateTime]::UtcNow.ToString('yy-MM-dd HH:mm:ss')
    Write-Host ("[{0} {1}] {2}" -f $timestamp, $resolvedLevel, $Message)

    if ($resolvedSeverity -ge 4 -and $ErrorActionPreference -eq 'Stop') {
        throw ("PackageModel.ConsoleLog.{0}: {1}" -f $resolvedLevel, $Message)
    }
}
