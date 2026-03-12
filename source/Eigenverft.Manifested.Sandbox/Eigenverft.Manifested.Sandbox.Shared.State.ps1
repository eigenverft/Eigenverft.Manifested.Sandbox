<#
    Eigenverft.Manifested.Sandbox.Shared.State
#>

function Get-ManifestedStateDocument {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    if (-not (Test-Path -LiteralPath $layout.StatePath)) {
        return [pscustomobject]@{
            SchemaVersion = 1
            UpdatedAtUtc  = $null
            Commands      = [pscustomobject]@{}
        }
    }

    $raw = Get-Content -LiteralPath $layout.StatePath -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{
            SchemaVersion = 1
            UpdatedAtUtc  = $null
            Commands      = [pscustomobject]@{}
        }
    }

    $document = $raw | ConvertFrom-Json
    if (-not $document.PSObject.Properties['Commands']) {
        Add-Member -InputObject $document -NotePropertyName Commands -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    return $document
}

function Save-ManifestedStateDocument {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$StateDocument,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    New-ManifestedDirectory -Path $layout.LocalRoot | Out-Null

    $StateDocument.UpdatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    if ($PSCmdlet.ShouldProcess($layout.StatePath, 'Set Content')) {
        $StateDocument | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $layout.StatePath -Encoding UTF8
    }

    return $layout.StatePath
}

function Save-ManifestedInvokeState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Result,

        [hashtable]$Details = @{},

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $document = Get-ManifestedStateDocument -LocalRoot $LocalRoot
    if (-not $document.PSObject.Properties['Commands']) {
        Add-Member -InputObject $document -NotePropertyName Commands -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    $layout = $Result.Layout
    if (-not $layout -and $Result.FinalState) {
        $layout = $Result.FinalState.Layout
    }

    Add-Member -InputObject $document.Commands -NotePropertyName $CommandName -NotePropertyValue ([pscustomobject]@{
        Command          = $CommandName
        LastInvokedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        ActionTaken      = @($Result.ActionTaken)
        Status           = if ($Result.FinalState) { $Result.FinalState.Status } else { $null }
        RestartRequired  = [bool]$Result.RestartRequired
        Paths            = if ($layout) {
            [ordered]@{
                LocalRoot          = $layout.LocalRoot
                CacheRoot          = $layout.CacheRoot
                NodeCacheRoot      = $layout.NodeCacheRoot
                VCRuntimeCacheRoot = $layout.VCRuntimeCacheRoot
                ToolsRoot          = $layout.ToolsRoot
                NodeToolsRoot      = $layout.NodeToolsRoot
                StatePath          = $layout.StatePath
            }
        }
        else {
            $null
        }
        SystemState      = $Result.FinalState
        Details          = $Details
    }) -Force

    return (Save-ManifestedStateDocument -StateDocument $document -LocalRoot $LocalRoot)
}
