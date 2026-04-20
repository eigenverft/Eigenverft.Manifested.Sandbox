<#
    Eigenverft.Manifested.Sandbox.PackageModel.ExecutionEngine.StandardMessage
#>

function Write-PackageModelExecutionMessage {
<#
.SYNOPSIS
Writes a PackageModel execution message with a safe console fallback.

.DESCRIPTION
Routes messages through the older `Write-StandardMessage` helper when it is
available in the current session. If that helper is missing or throws, this
wrapper falls back to plain `Write-Host` so PackageModel flow tracing stays
visible even after the older StateModel code is removed.

.PARAMETER Message
The message text to write.

.PARAMETER Level
The message severity.

.EXAMPLE
Write-PackageModelExecutionMessage -Message '[STEP] ResolvePackage'
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter()]
        [ValidateSet('TRC', 'DBG', 'INF', 'WRN', 'ERR', 'FTL')]
        [string]$Level = 'INF'
    )

    if ($null -eq $Message) {
        $Message = [string]::Empty
    }

    $resolvedLevel = if ([string]::IsNullOrWhiteSpace($Level)) {
        'INF'
    }
    else {
        $Level.ToUpperInvariant()
    }

    $standardMessageCommand = Get-Command -Name 'Write-StandardMessage' -CommandType Function -ErrorAction SilentlyContinue
    if ($standardMessageCommand) {
        try {
            & $standardMessageCommand.Name -Message $Message -Level $resolvedLevel
            return
        }
        catch {
        }
    }

    $timestamp = [DateTime]::UtcNow.ToString('yy-MM-dd HH:mm:ss')
    Write-Host ("[{0} {1}] {2}" -f $timestamp, $resolvedLevel, $Message)
}
