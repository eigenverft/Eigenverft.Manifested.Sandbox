function Get-ManifestedCommandDefinitionsRoot {
    [CmdletBinding()]
    param()

    $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    return (Join-Path $moduleRoot 'Definitions\Commands')
}

function Convert-ManifestedDefinitionKindToRuntimeKind {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Kind
    )

    switch ($Kind) {
        'portable-package' { return 'PortablePackage' }
        'npm-cli' { return 'NpmCli' }
        'machine-prerequisite' { return 'MachinePrerequisite' }
        default { throw "Unsupported command definition kind '$Kind'." }
    }
}

function Get-ManifestedDefinitionSectionValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [string]$SectionName
    )

    if (-not $Definition.PSObject.Properties.Match($SectionName).Count) {
        return $null
    }

    return $Definition.$SectionName
}

function Get-ManifestedDefinitionBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [string]$SectionName,

        [Parameter(Mandatory = $true)]
        [string]$BlockName
    )

    $sectionValue = Get-ManifestedDefinitionSectionValue -Definition $Definition -SectionName $SectionName
    if (-not $sectionValue) {
        return $null
    }

    if (-not $sectionValue.PSObject.Properties.Match($BlockName).Count) {
        return $null
    }

    $value = $sectionValue.$BlockName
    if ($null -eq $value) {
        return $null
    }

    if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    return $value
}

function Get-ManifestedActiveDefinitionBlockNames {
    [CmdletBinding()]
    param(
        [psobject]$SectionValue
    )

    if ($null -eq $SectionValue) {
        return @()
    }

    $activeBlocks = New-Object System.Collections.Generic.List[string]
    foreach ($property in @($SectionValue.PSObject.Properties)) {
        if ($null -eq $property.Value) {
            continue
        }

        if ($property.Value -is [string] -and [string]::IsNullOrWhiteSpace($property.Value)) {
            continue
        }

        $activeBlocks.Add($property.Name) | Out-Null
    }

    return @($activeBlocks)
}

function ConvertTo-ManifestedRuntimeDisplayName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeName
    )

    $stem = ($RuntimeName -replace 'Runtime$', '').Trim()
    if ([string]::IsNullOrWhiteSpace($stem)) {
        return $RuntimeName
    }

    return (($stem -creplace '([a-z0-9])([A-Z])', '$1 $2').Trim() + ' runtime')
}

function Assert-ManifestedCommandDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [string]$DefinitionFileName
    )

    foreach ($propertyName in @('schemaVersion', 'commandName', 'runtimeName', 'kind', 'wrapperCommand', 'refreshSwitchName', 'facts', 'supply', 'artifact', 'install', 'environment', 'dependencies', 'policies', 'hooks')) {
        if (-not $Definition.PSObject.Properties[$propertyName]) {
            throw "Command definition '$DefinitionFileName' is missing '$propertyName'."
        }
    }

    if ($Definition.kind -notin @('portable-package', 'npm-cli', 'machine-prerequisite')) {
        throw "Command definition '$($Definition.commandName)' has unsupported kind '$($Definition.kind)'."
    }

    if ($Definition.PSObject.Properties.Match('handlerIds').Count -gt 0) {
        throw "Command definition '$($Definition.commandName)' may not define handlerIds in the block-driven registry."
    }

    $factsBlocks = @(Get-ManifestedActiveDefinitionBlockNames -SectionValue (Get-ManifestedDefinitionSectionValue -Definition $Definition -SectionName 'facts'))
    if ($factsBlocks.Count -ne 1) {
        throw "Command definition '$($Definition.commandName)' must define exactly one active facts block."
    }
    foreach ($factsBlock in @($factsBlocks)) {
        if ($factsBlock -notin @('portableRuntime', 'pythonEmbeddableRuntime', 'machinePrerequisite', 'npmCli')) {
            throw "Command definition '$($Definition.commandName)' uses unsupported facts block '$factsBlock'."
        }
    }

    $supplyBlocks = @(Get-ManifestedActiveDefinitionBlockNames -SectionValue (Get-ManifestedDefinitionSectionValue -Definition $Definition -SectionName 'supply'))
    if ($supplyBlocks.Count -gt 1) {
        throw "Command definition '$($Definition.commandName)' may define at most one active supply block."
    }
    foreach ($supplyBlock in @($supplyBlocks)) {
        if ($supplyBlock -notin @('githubRelease', 'nodeDist', 'directDownload', 'pythonEmbed', 'vsCodeUpdate')) {
            throw "Command definition '$($Definition.commandName)' uses unsupported supply block '$supplyBlock'."
        }
    }

    if ($Definition.kind -in @('portable-package', 'machine-prerequisite')) {
        if ($supplyBlocks.Count -ne 1) {
            throw "Command definition '$($Definition.commandName)' must define exactly one active supply block."
        }
    }

    $portableArchiveInstall = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'install' -BlockName 'portableArchive'
    $pythonZipInstall = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'install' -BlockName 'pythonEmbeddableZip'
    $machineInstallerInstall = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'install' -BlockName 'machineInstaller'
    $npmInstall = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'install' -BlockName 'npmGlobalPackage'
    $zipPackageArtifact = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'artifact' -BlockName 'zipPackage'
    $executableInstallerArtifact = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'artifact' -BlockName 'executableInstaller'
    if ($portableArchiveInstall -and -not $zipPackageArtifact) {
        throw "Command definition '$($Definition.commandName)' must pair install.portableArchive with artifact.zipPackage."
    }
    if ($pythonZipInstall -and -not $zipPackageArtifact) {
        throw "Command definition '$($Definition.commandName)' must pair install.pythonEmbeddableZip with artifact.zipPackage."
    }
    if ($machineInstallerInstall -and -not $executableInstallerArtifact) {
        throw "Command definition '$($Definition.commandName)' must pair install.machineInstaller with artifact.executableInstaller."
    }
    if ($npmInstall -and $Definition.kind -ne 'npm-cli') {
        throw "Command definition '$($Definition.commandName)' may only use install.npmGlobalPackage for npm-cli definitions."
    }

    if ([bool]$Definition.policies.supportsEnvironmentSync) {
        $commandProjection = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'environment' -BlockName 'commandProjection'
        if (-not $commandProjection) {
            throw "Command definition '$($Definition.commandName)' must define environment.commandProjection when supportsEnvironmentSync is enabled."
        }
    }

    foreach ($dependency in @($Definition.dependencies)) {
        foreach ($dependencyProperty in @('runtimeName', 'minimumVersion', 'satisfactionMode', 'autoInstall', 'reason')) {
            if (-not $dependency.PSObject.Properties[$dependencyProperty]) {
                throw "Dependency entry in '$($Definition.commandName)' is missing '$dependencyProperty'."
            }
        }
    }
}

function New-ManifestedCommandExecutionContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition
    )

    $runtimeDisplayName = ConvertTo-ManifestedRuntimeDisplayName -RuntimeName $Definition.runtimeName
    $zipArtifactBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'artifact' -BlockName 'zipPackage'
    $installerArtifactBlock = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'artifact' -BlockName 'executableInstaller'
    $artifactBlock = if ($zipArtifactBlock) { $zipArtifactBlock } else { $installerArtifactBlock }

    return [pscustomobject]@{
        ExecutionModel          = 'DefinitionBlocks'
        RuntimeName             = $Definition.runtimeName
        CommandName             = $Definition.commandName
        RuntimeKind             = Convert-ManifestedDefinitionKindToRuntimeKind -Kind $Definition.kind
        Definition              = $Definition
        SupportsEnvironmentSync = [bool]$Definition.policies.supportsEnvironmentSync
        InstallRequiresElevation = [bool]$Definition.policies.installRequiresElevation
        RequireTrustedArtifact  = [bool]$Definition.policies.requireTrustedArtifact
        RepairTarget            = ('managed ' + $runtimeDisplayName + ' artifacts')
        ArtifactTarget          = if ($installerArtifactBlock) { ('managed ' + $runtimeDisplayName + ' installer') } elseif ($artifactBlock) { ('managed ' + $runtimeDisplayName + ' package') } else { $null }
        InstallTarget           = ('managed ' + $runtimeDisplayName)
        EnvironmentTarget       = if ([bool]$Definition.policies.supportsEnvironmentSync) { ($runtimeDisplayName + ' command-line environment') } else { $null }
    }
}

function Get-ManifestedCommandProjectionFromDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Facts
    )

    $environment = Get-ManifestedDefinitionBlock -Definition $Definition -SectionName 'environment' -BlockName 'commandProjection'

    if (-not $environment) {
        return [pscustomobject]@{
            Applicable              = $false
            DesiredExecutablePath   = $null
            DesiredCommandDirectory = $null
            ExpectedCommandPaths    = [ordered]@{}
        }
    }

    $desiredDirectoryFact = if ($environment.PSObject.Properties.Match('desiredDirectoryFact').Count -gt 0) { $environment.desiredDirectoryFact } else { 'RuntimeHome' }
    $executableFact = if ($environment.PSObject.Properties.Match('executableFact').Count -gt 0) { $environment.executableFact } else { 'ExecutablePath' }

    $desiredCommandDirectory = if ($Facts.PSObject.Properties.Match($desiredDirectoryFact).Count -gt 0) { $Facts.($desiredDirectoryFact) } else { $null }
    $desiredExecutablePath = if ($Facts.PSObject.Properties.Match($executableFact).Count -gt 0) { $Facts.($executableFact) } else { $null }

    if ([string]::IsNullOrWhiteSpace($desiredCommandDirectory) -and -not [string]::IsNullOrWhiteSpace($desiredExecutablePath)) {
        $desiredCommandDirectory = Split-Path -Parent $desiredExecutablePath
    }

    $expectedCommandPaths = [ordered]@{}
    foreach ($commandName in @($environment.expectedCommands)) {
        if ([string]::IsNullOrWhiteSpace($commandName)) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($desiredExecutablePath) -and ((Split-Path -Leaf $desiredExecutablePath) -ieq $commandName)) {
            $expectedCommandPaths[$commandName] = (Get-ManifestedFullPath -Path $desiredExecutablePath)
        }
        elseif (-not [string]::IsNullOrWhiteSpace($desiredCommandDirectory)) {
            $expectedCommandPaths[$commandName] = (Get-ManifestedFullPath -Path (Join-Path $desiredCommandDirectory $commandName))
        }
    }

    return [pscustomobject]@{
        Applicable              = (-not [string]::IsNullOrWhiteSpace($desiredCommandDirectory)) -and ($expectedCommandPaths.Count -gt 0)
        DesiredExecutablePath   = $desiredExecutablePath
        DesiredCommandDirectory = $desiredCommandDirectory
        ExpectedCommandPaths    = $expectedCommandPaths
    }
}

function Import-ManifestedCommandDefinitions {
    [CmdletBinding()]
    param(
        [string]$DefinitionsRoot = (Get-ManifestedCommandDefinitionsRoot)
    )

    $script:ManifestedCommandDefinitions = @()
    $script:ManifestedCommandDefinitionsByCommandName = @{}
    $script:ManifestedCommandDefinitionsByRuntimeName = @{}

    if ([string]::IsNullOrWhiteSpace($DefinitionsRoot) -or -not (Test-Path -LiteralPath $DefinitionsRoot)) {
        return @()
    }

    $definitionFiles = @(Get-ChildItem -LiteralPath $DefinitionsRoot -Filter '*.json' -File | Sort-Object Name)
    foreach ($definitionFile in $definitionFiles) {
        $definition = Get-Content -LiteralPath $definitionFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json

        Assert-ManifestedCommandDefinition -Definition $definition -DefinitionFileName $definitionFile.Name

        if ($script:ManifestedCommandDefinitionsByCommandName.ContainsKey($definition.commandName)) {
            throw "Duplicate command definition for '$($definition.commandName)'."
        }

        if ($script:ManifestedCommandDefinitionsByRuntimeName.ContainsKey($definition.runtimeName)) {
            throw "Duplicate runtime definition for '$($definition.runtimeName)'."
        }

        $script:ManifestedCommandDefinitions += $definition
        $script:ManifestedCommandDefinitionsByCommandName[$definition.commandName] = $definition
        $script:ManifestedCommandDefinitionsByRuntimeName[$definition.runtimeName] = $definition
    }

    return @($script:ManifestedCommandDefinitions | Sort-Object runtimeName)
}

function Get-ManifestedCommandDefinitions {
    [CmdletBinding()]
    param()

    return @($script:ManifestedCommandDefinitions | Sort-Object runtimeName)
}

function Get-ManifestedCommandDefinition {
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByCommandName')]
        [string]$CommandName,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByRuntimeName')]
        [string]$RuntimeName
    )

    switch ($PSCmdlet.ParameterSetName) {
        'ByCommandName' {
            if ($script:ManifestedCommandDefinitionsByCommandName.ContainsKey($CommandName)) {
                return $script:ManifestedCommandDefinitionsByCommandName[$CommandName]
            }
        }

        'ByRuntimeName' {
            if ($script:ManifestedCommandDefinitionsByRuntimeName.ContainsKey($RuntimeName)) {
                return $script:ManifestedCommandDefinitionsByRuntimeName[$RuntimeName]
            }
        }

        'ByName' {
            foreach ($definition in @(Get-ManifestedCommandDefinitions)) {
                if (($definition.commandName -eq $Name) -or ($definition.runtimeName -eq $Name) -or ($definition.wrapperCommand -eq $Name)) {
                    return $definition
                }
            }
        }
    }

    return $null
}

function Get-ManifestedCommandContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    $definition = Get-ManifestedCommandDefinition -CommandName $CommandName
    if (-not $definition) {
        return $null
    }

    return (New-ManifestedCommandExecutionContext -Definition $definition)
}

function Get-ManifestedRuntimeContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeName
    )

    $definition = Get-ManifestedCommandDefinition -RuntimeName $RuntimeName
    if (-not $definition) {
        return $null
    }

    return (New-ManifestedCommandExecutionContext -Definition $definition)
}


