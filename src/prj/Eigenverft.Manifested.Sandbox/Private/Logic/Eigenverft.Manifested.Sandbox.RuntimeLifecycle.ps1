<#
    Eigenverft.Manifested.Sandbox.RuntimeLifecycle
#>

function New-ManifestedRuntimeResult {
<#
.SYNOPSIS
Creates a normalized runtime-operation result object.

.DESCRIPTION
Builds the shared result envelope used by runtime-family helpers while
preserving family-specific properties supplied through
`-AdditionalProperties`.

.PARAMETER LocalRoot
Sandbox root used for the runtime operation.

.PARAMETER Layout
Resolved layout object for the sandbox.

.PARAMETER InitialState
Runtime state before orchestration begins.

.PARAMETER FinalState
Runtime state after the current orchestration step.

.PARAMETER ActionTaken
Actions already taken for the current invocation.

.PARAMETER PlannedActions
Remaining or predicted actions for the current invocation.

.PARAMETER RestartRequired
Whether the operation requires a restart to finish cleanly.

.PARAMETER AdditionalProperties
Extra family-specific properties to append to the result object.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LocalRoot,

        [pscustomobject]$Layout,

        [pscustomobject]$InitialState,

        [pscustomobject]$FinalState,

        [string[]]$ActionTaken = @('None'),

        [string[]]$PlannedActions = @(),

        [bool]$RestartRequired = $false,

        [hashtable]$AdditionalProperties = ([ordered]@{})
    )

    $resultData = [ordered]@{
        LocalRoot       = $LocalRoot
        Layout          = $Layout
        InitialState    = $InitialState
        FinalState      = $FinalState
        ActionTaken     = if (@($ActionTaken).Count -gt 0) { @($ActionTaken) } else { @('None') }
        PlannedActions  = @($PlannedActions)
        RestartRequired = [bool]$RestartRequired
    }

    foreach ($entry in $AdditionalProperties.GetEnumerator()) {
        $resultData[$entry.Key] = $entry.Value
    }

    return [pscustomobject]$resultData
}

function Complete-ManifestedRuntimeResult {
<#
.SYNOPSIS
Finalizes a runtime-operation result object.

.DESCRIPTION
Appends the persisted state path for normal executions or explicitly records a
null persisted path for non-persisting flows such as `-WhatIf`.

.PARAMETER CommandName
Initialize command associated with the result.

.PARAMETER Result
Runtime result object to finalize.

.PARAMETER Details
Persisted detail payload written alongside the result.

.PARAMETER LocalRoot
Sandbox root used for state persistence.

.PARAMETER PersistState
Controls whether the invocation state should be written to disk.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Result,

        [hashtable]$Details = @{},

        [string]$LocalRoot = (Get-ManifestedLocalRoot),

        [bool]$PersistState = $true
    )

    if (-not $PersistState) {
        Add-Member -InputObject $Result -NotePropertyName PersistedStatePath -NotePropertyValue $null -Force
        return $Result
    }

    $statePath = Save-ManifestedInvokeState -CommandName $CommandName -Result $Result -LocalRoot $LocalRoot -Details $Details
    Add-Member -InputObject $Result -NotePropertyName PersistedStatePath -NotePropertyValue $statePath -Force
    return $Result
}

function Invoke-ManifestedRuntimeCommandEnvironmentSync {
<#
.SYNOPSIS
Runs shared command-environment synchronization for a runtime.

.DESCRIPTION
Evaluates the command-environment state for a runtime, optionally routes the
sync step through the caller's `ShouldProcess` flow, performs the sync when
needed, and records the shared sync action when the environment changes.

.PARAMETER Cmdlet
Caller cmdlet whose `ShouldProcess` implementation should be used.

.PARAMETER CommandName
Initialize command associated with the runtime.

.PARAMETER DisplayName
Human-readable runtime name used in `ShouldProcess` messaging.

.PARAMETER RuntimeState
Final runtime state used to resolve command-environment expectations.

.PARAMETER ActionsTaken
Mutable action list that receives the shared sync action when an update occurs.

.PARAMETER UseShouldProcess
Controls whether the shared sync should ask the caller cmdlet for confirmation.

.PARAMETER RequireNeedsSync
When set, skips synchronization unless the environment status is `NeedsSync`.
#>
    [Diagnostics.CodeAnalysis.SuppressMessage('PSShouldProcess', '', Justification = 'Delegates ShouldProcess decisions to the caller cmdlet passed via -Cmdlet.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]$Cmdlet,

        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [Parameter(Mandatory = $true)]
        [string]$DisplayName,

        [pscustomobject]$RuntimeState,

        [System.Collections.Generic.List[string]]$ActionsTaken,

        [bool]$UseShouldProcess = $true,

        [bool]$RequireNeedsSync = $false
    )

    $commandEnvironment = Get-ManifestedCommandEnvironmentResult -CommandName $CommandName -RuntimeState $RuntimeState
    if (-not $commandEnvironment.Applicable) {
        return [pscustomobject]@{
            CommandEnvironment = $commandEnvironment
            StopProcessing     = $false
        }
    }

    if ($RequireNeedsSync -and $commandEnvironment.Status -ne 'NeedsSync') {
        return [pscustomobject]@{
            CommandEnvironment = $commandEnvironment
            StopProcessing     = $false
        }
    }

    if ($UseShouldProcess -and -not $Cmdlet.ShouldProcess($commandEnvironment.DesiredCommandDirectory, ('Synchronize {0} command-line environment' -f $DisplayName))) {
        return [pscustomobject]@{
            CommandEnvironment = $commandEnvironment
            StopProcessing     = $true
        }
    }

    $commandEnvironment = Sync-ManifestedCommandLineEnvironment -Specification (Get-ManifestedCommandEnvironmentSpec -CommandName $CommandName -RuntimeState $RuntimeState)
    if ($null -ne $ActionsTaken -and $commandEnvironment.Status -eq 'Updated') {
        $ActionsTaken.Add('Sync-ManifestedCommandLineEnvironment') | Out-Null
    }

    return [pscustomobject]@{
        CommandEnvironment = $commandEnvironment
        StopProcessing     = $false
    }
}
