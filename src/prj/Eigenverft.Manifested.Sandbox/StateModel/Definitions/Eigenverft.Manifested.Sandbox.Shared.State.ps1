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

function Get-ManifestedCommandState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $document = Get-ManifestedStateDocument -LocalRoot $LocalRoot
    if (-not $document.PSObject.Properties['Commands']) {
        return $null
    }

    $commandProperty = $document.Commands.PSObject.Properties[$CommandName]
    if (-not $commandProperty) {
        return $null
    }

    return $commandProperty.Value
}

function Get-ManifestedRuntimeSnapshots {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $definitions = @(
        @{ Name = 'PythonRuntime'; FunctionName = 'Get-PythonRuntimeState'; PathProperty = 'RuntimeHome' },
        @{ Name = 'NodeRuntime'; FunctionName = 'Get-NodeRuntimeState'; PathProperty = 'RuntimeHome' },
        @{ Name = 'OpenCodeRuntime'; FunctionName = 'Get-OpenCodeRuntimeState'; PathProperty = 'RuntimeHome' },
        @{ Name = 'GeminiRuntime'; FunctionName = 'Get-GeminiRuntimeState'; PathProperty = 'RuntimeHome' },
        @{ Name = 'QwenRuntime'; FunctionName = 'Get-QwenRuntimeState'; PathProperty = 'RuntimeHome' },
        @{ Name = 'CodexRuntime'; FunctionName = 'Get-CodexRuntimeState'; PathProperty = 'RuntimeHome' },
        @{ Name = 'Ps7Runtime'; FunctionName = 'Get-Ps7RuntimeState'; PathProperty = 'RuntimeHome' },
        @{ Name = 'VCRuntime'; FunctionName = 'Get-VCRuntimeState'; PathProperty = 'InstallerPath' }
    )

    $items = @()
    foreach ($definition in $definitions) {
        if (-not (Get-Command -Name $definition.FunctionName -CommandType Function -ErrorAction SilentlyContinue)) {
            continue
        }

        try {
            $state = & $definition.FunctionName -LocalRoot $layout.LocalRoot
            $resourcePath = $null
            if ($state -and $state.PSObject.Properties[$definition.PathProperty]) {
                $resourcePath = $state.($definition.PathProperty)
            }

            $items += [pscustomobject]@{
                Name           = $definition.Name
                Status         = if ($state -and $state.PSObject.Properties['Status']) { $state.Status } else { $null }
                RuntimeSource  = if ($state -and $state.PSObject.Properties['RuntimeSource']) { $state.RuntimeSource } else { $null }
                CurrentVersion = if ($state -and $state.PSObject.Properties['CurrentVersion']) { $state.CurrentVersion } else { $null }
                ResourcePath   = $resourcePath
                BlockedReason  = if ($state -and $state.PSObject.Properties['BlockedReason']) { $state.BlockedReason } else { $null }
                State          = $state
            }
        }
        catch {
            $items += [pscustomobject]@{
                Name           = $definition.Name
                Status         = 'Error'
                RuntimeSource  = $null
                CurrentVersion = $null
                ResourcePath   = $null
                BlockedReason  = $_.Exception.Message
                State          = $null
            }
        }
    }

    return @($items)
}

function Get-SandboxState {
    [CmdletBinding()]
    param(
        [switch]$Raw
    )

    $layout = Get-ManifestedLayout
    $stateExists = Test-Path -LiteralPath $layout.StatePath
    $document = Get-ManifestedStateDocument -LocalRoot $layout.LocalRoot
    $runtimeSnapshots = Get-ManifestedRuntimeSnapshots -LocalRoot $layout.LocalRoot

    if ($Raw) {
        return [pscustomobject]@{
            LocalRoot   = $layout.LocalRoot
            Layout      = $layout
            StatePath   = $layout.StatePath
            StateExists = $stateExists
            Runtimes    = @($runtimeSnapshots)
            Document    = $document
        }
    }

    $commands = @()
    foreach ($property in $document.Commands.PSObject.Properties) {
        $commandState = $property.Value

        $commands += [pscustomobject]@{
            Command          = $property.Name
            Status           = if ($commandState.PSObject.Properties['Status']) { $commandState.Status } else { $null }
            LastInvokedAtUtc = if ($commandState.PSObject.Properties['LastInvokedAtUtc']) { $commandState.LastInvokedAtUtc } else { $null }
            ActionTaken      = if ($commandState.PSObject.Properties['ActionTaken']) { [string[]]@($commandState.ActionTaken) } else { [string[]]@() }
            RestartRequired  = if ($commandState.PSObject.Properties['RestartRequired']) { [bool]$commandState.RestartRequired } else { $false }
            StatePath        = if ($commandState.PSObject.Properties['Paths'] -and $commandState.Paths) { $commandState.Paths.StatePath } else { $layout.StatePath }
            LocalRoot        = if ($commandState.PSObject.Properties['Paths'] -and $commandState.Paths) { $commandState.Paths.LocalRoot } else { $layout.LocalRoot }
            Elevation        = if ($commandState.PSObject.Properties['Elevation']) { $commandState.Elevation } else { $null }
            CommandEnvironment = if ($commandState.PSObject.Properties['CommandEnvironment']) { $commandState.CommandEnvironment } else { $null }
            Details          = if ($commandState.PSObject.Properties['Details']) { $commandState.Details } else { $null }
        }
    }

    [pscustomobject]@{
        LocalRoot     = $layout.LocalRoot
        Layout        = $layout
        StatePath     = $layout.StatePath
        StateExists   = $stateExists
        SchemaVersion = if ($document.PSObject.Properties['SchemaVersion']) { $document.SchemaVersion } else { $null }
        UpdatedAtUtc  = if ($document.PSObject.Properties['UpdatedAtUtc']) { $document.UpdatedAtUtc } else { $null }
        CommandCount  = @($commands).Count
        Commands      = @($commands)
        Runtimes      = @($runtimeSnapshots | Select-Object Name, Status, RuntimeSource, CurrentVersion, ResourcePath, BlockedReason)
        Document      = $document
    }
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
        $StateDocument | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $layout.StatePath -Encoding UTF8
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
                Ps7CacheRoot       = $layout.Ps7CacheRoot
                PythonCacheRoot    = $layout.PythonCacheRoot
                NodeCacheRoot      = $layout.NodeCacheRoot
                OpenCodeCacheRoot  = $layout.OpenCodeCacheRoot
                GeminiCacheRoot    = $layout.GeminiCacheRoot
                QwenCacheRoot      = $layout.QwenCacheRoot
                CodexCacheRoot     = $layout.CodexCacheRoot
                GHCliCacheRoot     = $layout.GHCliCacheRoot
                GitCacheRoot       = $layout.GitCacheRoot
                VsCodeCacheRoot    = $layout.VsCodeCacheRoot
                VCRuntimeCacheRoot = $layout.VCRuntimeCacheRoot
                ToolsRoot          = $layout.ToolsRoot
                Ps7ToolsRoot       = $layout.Ps7ToolsRoot
                PythonToolsRoot    = $layout.PythonToolsRoot
                NodeToolsRoot      = $layout.NodeToolsRoot
                OpenCodeToolsRoot  = $layout.OpenCodeToolsRoot
                GeminiToolsRoot    = $layout.GeminiToolsRoot
                QwenToolsRoot      = $layout.QwenToolsRoot
                CodexToolsRoot     = $layout.CodexToolsRoot
                GHCliToolsRoot     = $layout.GHCliToolsRoot
                GitToolsRoot       = $layout.GitToolsRoot
                VsCodeToolsRoot    = $layout.VsCodeToolsRoot
                StatePath          = $layout.StatePath
            }
        }
        else {
            $null
        }
        SystemState      = $Result.FinalState
        Elevation        = if ($Result.PSObject.Properties['Elevation']) { $Result.Elevation } else { $null }
        CommandEnvironment = if ($Result.PSObject.Properties['CommandEnvironment']) { $Result.CommandEnvironment } else { $null }
        Details          = $Details
    }) -Force

    return (Save-ManifestedStateDocument -StateDocument $document -LocalRoot $LocalRoot)
}
