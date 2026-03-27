<#
    Eigenverft.Manifested.Sandbox.Shared.State
#>

function Get-ManifestedStateDocument {
    [CmdletBinding()]
    param(
        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return [pscustomobject]@{
        SchemaVersion      = 2
        UpdatedAtUtc       = (Get-Date).ToUniversalTime().ToString('o')
        PersistenceEnabled = $false
        Commands           = [pscustomobject]@{}
        LocalRoot          = $LocalRoot
    }
}

function Get-ManifestedCommandState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return $null
}

function Convert-ManifestedFactsToReportSummary {
    [CmdletBinding()]
    param(
        [pscustomobject]$Facts
    )

    if (-not $Facts) {
        return $null
    }

    return [pscustomobject]@{
        PlatformSupported    = if ($Facts.PSObject.Properties['PlatformSupported']) { [bool]$Facts.PlatformSupported } else { $false }
        HasUsableRuntime     = if ($Facts.PSObject.Properties['HasUsableRuntime']) { [bool]$Facts.HasUsableRuntime } else { $false }
        RuntimeSource        = if ($Facts.PSObject.Properties['RuntimeSource']) { $Facts.RuntimeSource } else { $null }
        CurrentVersion       = if ($Facts.PSObject.Properties['CurrentVersion']) { $Facts.CurrentVersion } else { $null }
        RuntimeHome          = if ($Facts.PSObject.Properties['RuntimeHome']) { $Facts.RuntimeHome } else { $null }
        ExecutablePath       = if ($Facts.PSObject.Properties['ExecutablePath']) { $Facts.ExecutablePath } else { $null }
        ArtifactPath         = if ($Facts.PSObject.Properties['ArtifactPath']) { $Facts.ArtifactPath } else { $null }
        HasRepairableResidue = if ($Facts.PSObject.Properties['HasRepairableResidue']) { [bool]$Facts.HasRepairableResidue } else { $false }
        BlockedReason        = if ($Facts.PSObject.Properties['BlockedReason']) { $Facts.BlockedReason } else { $null }
    }
}

function Get-ManifestedCommandReportPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    $fileName = (($CommandName -replace '[^A-Za-z0-9._-]', '-') + '.json')
    return (Join-Path $layout.ReportsRoot $fileName)
}

function Get-ManifestedCommandReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $reportPath = Get-ManifestedCommandReportPath -CommandName $CommandName -LocalRoot $LocalRoot
    if (-not (Test-Path -LiteralPath $reportPath)) {
        return $null
    }

    return ((Get-Content -LiteralPath $reportPath -Raw -ErrorAction Stop) | ConvertFrom-Json)
}

function Get-ManifestedCommandReportSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $report = Get-ManifestedCommandReport -CommandName $CommandName -LocalRoot $LocalRoot
    if (-not $report) {
        return $null
    }

    return [pscustomobject]@{
        CommandName       = if ($report.PSObject.Properties['commandName']) { $report.commandName } else { $CommandName }
        RuntimeName       = if ($report.PSObject.Properties['runtimeName']) { $report.runtimeName } else { $null }
        RequestedAtUtc    = if ($report.PSObject.Properties['requestedAtUtc']) { $report.requestedAtUtc } else { $null }
        CompletedAtUtc    = if ($report.PSObject.Properties['completedAtUtc']) { $report.completedAtUtc } else { $null }
        RestartRequired   = if ($report.PSObject.Properties['restartRequired']) { [bool]$report.restartRequired } else { $false }
        WarningCount      = if ($report.PSObject.Properties['warnings'] -and $report.warnings) { @($report.warnings).Count } else { 0 }
        ErrorCount        = if ($report.PSObject.Properties['errors'] -and $report.errors) { @($report.errors).Count } else { 0 }
        ExecutedStepCount = if ($report.PSObject.Properties['executedSteps'] -and $report.executedSteps) { @($report.executedSteps).Count } else { 0 }
        Input             = if ($report.PSObject.Properties['input']) { $report.input } else { $null }
    }
}

function Save-ManifestedCommandReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [string]$RuntimeName,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Result,

        [hashtable]$InvocationInput = @{},

        [hashtable]$Details = @{},

        [string]$RequestedAtUtc = (Get-Date).ToUniversalTime().ToString('o'),

        [string]$CompletedAtUtc = (Get-Date).ToUniversalTime().ToString('o'),

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $layout = Get-ManifestedLayout -LocalRoot $LocalRoot
    New-ManifestedDirectory -Path $layout.ReportsRoot | Out-Null
    $reportPath = Get-ManifestedCommandReportPath -CommandName $CommandName -LocalRoot $LocalRoot

    $reportDocument = [ordered]@{
        commandName        = $CommandName
        runtimeName        = if (-not [string]::IsNullOrWhiteSpace($RuntimeName)) { $RuntimeName } elseif ($Result.PSObject.Properties['RuntimeName']) { $Result.RuntimeName } else { $null }
        requestedAtUtc     = $RequestedAtUtc
        completedAtUtc     = $CompletedAtUtc
        input              = [pscustomobject]$InvocationInput
        factsBeforeSummary = Convert-ManifestedFactsToReportSummary -Facts $(if ($Result.PSObject.Properties['FactsBefore']) { $Result.FactsBefore } else { $null })
        dependencyResults  = if ($Result.PSObject.Properties['Dependencies']) { @($Result.Dependencies) } else { @() }
        plan               = if ($Result.PSObject.Properties['Plan']) { @($Result.Plan) } else { @() }
        executedSteps      = if ($Result.PSObject.Properties['ExecutedSteps']) { @($Result.ExecutedSteps) } else { @() }
        factsAfterSummary  = Convert-ManifestedFactsToReportSummary -Facts $(if ($Result.PSObject.Properties['FactsAfter']) { $Result.FactsAfter } else { $null })
        environmentResult  = if ($Result.PSObject.Properties['EnvironmentResult']) { $Result.EnvironmentResult } else { $null }
        warnings           = if ($Result.PSObject.Properties['Warnings']) { @($Result.Warnings) } else { @() }
        errors             = if ($Result.PSObject.Properties['Errors']) { @($Result.Errors) } else { @() }
        restartRequired    = if ($Result.PSObject.Properties['RestartRequired']) { [bool]$Result.RestartRequired } else { $false }
    }

    if ($Details.Count -gt 0) {
        $reportDocument['details'] = [pscustomobject]$Details
    }

    $reportDocument | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    return $reportPath
}

function Get-ManifestedRuntimeSnapshots {
    [CmdletBinding()]
    param(
        [switch]$IncludeLastReportSummary,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    $items = @()
    $factsCache = @{}
    foreach ($definition in @(Get-ManifestedCommandDefinitions)) {
        $descriptor = New-ManifestedCommandExecutionContext -Definition $definition
        try {
            $facts = Get-ManifestedRuntimeFactsFromContext -Context $descriptor -LocalRoot $LocalRoot -FactsCache $factsCache
            $environment = $null
            if ($facts -and $descriptor.PSObject.Properties['SupportsEnvironmentSync'] -and $descriptor.SupportsEnvironmentSync) {
                $environment = Get-ManifestedCommandEnvironmentResult -Descriptor $descriptor -Facts $facts
            }

            $lastReportSummary = $null
            if ($IncludeLastReportSummary) {
                $lastReportSummary = Get-ManifestedCommandReportSummary -CommandName $descriptor.CommandName -LocalRoot $LocalRoot
            }

            $items += [pscustomobject]@{
                Name                 = $descriptor.RuntimeName
                CommandName          = $descriptor.CommandName
                WrapperCommand       = if ($definition -and $definition.PSObject.Properties['wrapperCommand']) { $definition.wrapperCommand } else { $descriptor.CommandName }
                RuntimeKind          = if ($descriptor.PSObject.Properties['RuntimeKind']) { $descriptor.RuntimeKind } else { $null }
                PlatformSupported    = if ($facts -and $facts.PSObject.Properties['PlatformSupported']) { [bool]$facts.PlatformSupported } else { $false }
                HasUsableRuntime     = if ($facts -and $facts.PSObject.Properties['HasUsableRuntime']) { [bool]$facts.HasUsableRuntime } else { $false }
                RuntimeSource        = if ($facts -and $facts.PSObject.Properties['RuntimeSource']) { $facts.RuntimeSource } else { $null }
                CurrentVersion       = if ($facts -and $facts.PSObject.Properties['CurrentVersion']) { $facts.CurrentVersion } else { $null }
                RuntimeHome          = if ($facts -and $facts.PSObject.Properties['RuntimeHome']) { $facts.RuntimeHome } else { $null }
                ExecutablePath       = if ($facts -and $facts.PSObject.Properties['ExecutablePath']) { $facts.ExecutablePath } else { $null }
                ArtifactPath         = if ($facts -and $facts.PSObject.Properties['ArtifactPath']) { $facts.ArtifactPath } else { $null }
                HasRepairableResidue = if ($facts -and $facts.PSObject.Properties['HasRepairableResidue']) { [bool]$facts.HasRepairableResidue } else { $false }
                BlockedReason        = if ($facts -and $facts.PSObject.Properties['BlockedReason']) { $facts.BlockedReason } else { $null }
                DefinitionKind       = if ($definition -and $definition.PSObject.Properties['kind']) { $definition.kind } else { $null }
                Dependencies         = if ($definition -and $definition.PSObject.Properties.Match('dependencies').Count -gt 0) { @($definition.dependencies) } else { @() }
                Definition           = $definition
                LastReportSummary    = $lastReportSummary
                Environment          = $environment
                Facts                = $facts
            }
        }
        catch {
            $items += [pscustomobject]@{
                Name                 = $descriptor.RuntimeName
                CommandName          = $descriptor.CommandName
                WrapperCommand       = if ($definition -and $definition.PSObject.Properties['wrapperCommand']) { $definition.wrapperCommand } else { $descriptor.CommandName }
                RuntimeKind          = if ($descriptor.PSObject.Properties['RuntimeKind']) { $descriptor.RuntimeKind } else { $null }
                PlatformSupported    = $false
                HasUsableRuntime     = $false
                RuntimeSource        = $null
                CurrentVersion       = $null
                RuntimeHome          = $null
                ExecutablePath       = $null
                ArtifactPath         = $null
                HasRepairableResidue = $false
                BlockedReason        = $_.Exception.Message
                DefinitionKind       = if ($definition -and $definition.PSObject.Properties['kind']) { $definition.kind } else { $null }
                Dependencies         = if ($definition -and $definition.PSObject.Properties.Match('dependencies').Count -gt 0) { @($definition.dependencies) } else { @() }
                Definition           = $definition
                LastReportSummary    = if ($IncludeLastReportSummary) { Get-ManifestedCommandReportSummary -CommandName $descriptor.CommandName -LocalRoot $LocalRoot } else { $null }
                Environment          = $null
                Facts                = $null
            }
        }
    }

    return @($items)
}

function Get-SandboxState {
    [CmdletBinding()]
    param(
        [switch]$IncludeLastReportSummary,

        [switch]$Raw
    )

    $layout = Get-ManifestedLayout
    $runtimeSnapshots = Get-ManifestedRuntimeSnapshots -IncludeLastReportSummary:$IncludeLastReportSummary -LocalRoot $layout.LocalRoot

    $summaryProperties = @(
        'Name',
        'CommandName',
        'WrapperCommand',
        'RuntimeKind',
        'DefinitionKind',
        'PlatformSupported',
        'HasUsableRuntime',
        'RuntimeSource',
        'CurrentVersion',
        'RuntimeHome',
        'ExecutablePath',
        'ArtifactPath',
        'HasRepairableResidue',
        'BlockedReason',
        'Dependencies',
        'Environment'
    )
    if ($IncludeLastReportSummary) {
        $summaryProperties += 'LastReportSummary'
    }

    if ($Raw) {
        return [pscustomobject]@{
            LocalRoot      = $layout.LocalRoot
            Layout         = $layout
            DefinitionCount = @((Get-ManifestedCommandDefinitions)).Count
            RuntimeCount   = @($runtimeSnapshots).Count
            Runtimes       = @($runtimeSnapshots)
        }
    }

    return [pscustomobject]@{
        LocalRoot      = $layout.LocalRoot
        Layout         = $layout
        DefinitionCount = @((Get-ManifestedCommandDefinitions)).Count
        RuntimeCount   = @($runtimeSnapshots).Count
        Runtimes       = @(
            $runtimeSnapshots |
                Select-Object -Property $summaryProperties
        )
    }
}

function Save-ManifestedStateDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$StateDocument,

        [string]$LocalRoot = (Get-ManifestedLocalRoot)
    )

    return $null
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

    return (Save-ManifestedCommandReport -CommandName $CommandName -Result $Result -Details $Details -InvocationInput @{ LegacyCompat = $true } -LocalRoot $LocalRoot)
}
