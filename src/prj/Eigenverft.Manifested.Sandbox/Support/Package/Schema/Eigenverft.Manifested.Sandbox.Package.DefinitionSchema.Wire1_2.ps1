<#
    Eigenverft.Manifested.Sandbox.Package.DefinitionSchema.Wire1_2
    Validators and runtime projection for package definition schemaVersion 1.2.
#>

function Get-PackageObjectPropertyValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [psobject]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not $InputObject -or -not $InputObject.PSObject.Properties[$Name]) {
        return $null
    }

    return $InputObject.$Name
}

function Test-PackageObjectHasProperty {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [psobject]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return ($InputObject -and $InputObject.PSObject.Properties[$Name])
}

function Get-PackageDiscoveryEntryPoints {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Definition,

        [Parameter(Mandatory = $true)]
        [ValidateSet('commands', 'apps')]
        [string]$ToolKind,

        [switch]$ExposedOnly
    )

    if (-not (Test-PackageObjectHasProperty -InputObject $Definition -Name 'discovery') -or
        -not (Test-PackageObjectHasProperty -InputObject $Definition.discovery -Name $ToolKind)) {
        return @()
    }

    return @(
        foreach ($entryPoint in @($Definition.discovery.$ToolKind)) {
            if ($null -eq $entryPoint) {
                continue
            }
            if ($ExposedOnly -and
                $entryPoint.PSObject.Properties['exposed'] -and
                -not [bool]$entryPoint.exposed) {
                continue
            }
            $entryPoint
        }
    )
}

function Get-PackageDiscoveryEntryPoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Definition,

        [Parameter(Mandatory = $true)]
        [ValidateSet('commands', 'apps')]
        [string]$ToolKind,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [switch]$ExposedOnly
    )

    foreach ($entryPoint in @(Get-PackageDiscoveryEntryPoints -Definition $Definition -ToolKind $ToolKind -ExposedOnly:$ExposedOnly)) {
        if ([string]::Equals([string]$entryPoint.name, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $entryPoint
        }
    }

    return $null
}

function Resolve-PackageDiscoveredToolEntryPointPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$EntryPoint,

        [Parameter(Mandatory = $true)]
        [string]$InstallDirectory
    )

    return (Join-Path $InstallDirectory (([string]$EntryPoint.relativePath) -replace '/', '\'))
}

function Resolve-PackageDiscoveredToolPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Definition,

        [Parameter(Mandatory = $true)]
        [ValidateSet('commands', 'apps')]
        [string]$ToolKind,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$InstallDirectory
    )

    $entryPoint = Get-PackageDiscoveryEntryPoint -Definition $Definition -ToolKind $ToolKind -Name $Name
    if (-not $entryPoint) {
        return $null
    }

    return (Resolve-PackageDiscoveredToolEntryPointPath -EntryPoint $entryPoint -InstallDirectory $InstallDirectory)
}

function Assert-PackageDefinitionNoRetiredNestedProperty_1_2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DefinitionId,

        [AllowNull()]
        [psobject]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName,

        [Parameter(Mandatory = $true)]
        [string]$PropertyPath,

        [Parameter(Mandatory = $true)]
        [string]$ReplacementPath
    )

    if ($InputObject -and $InputObject.PSObject.Properties[$PropertyName]) {
        throw "Package definition '$DefinitionId' still uses retired schemaVersion 1.1 property '$PropertyPath'. Use '$ReplacementPath'."
    }
}

function Assert-PackageArtifactTrustMetadata_1_2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DefinitionId,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$TargetId,

        [AllowNull()]
        [psobject]$Artifact
    )

    if (-not $Artifact) {
        return
    }

    foreach ($retiredProperty in @('autoUpdateSupported', 'integrity', 'authenticode')) {
        if ($Artifact.PSObject.Properties[$retiredProperty]) {
            throw "Package definition '$DefinitionId' version '$Version' artifact '$TargetId' still uses retired packageFile.$retiredProperty. Use artifact contentHash or publisherSignature metadata."
        }
    }

    if ($Artifact.PSObject.Properties['contentHash']) {
        $contentHash = $Artifact.contentHash
        if (-not $contentHash -or
            -not $contentHash.PSObject.Properties['algorithm'] -or
            [string]::IsNullOrWhiteSpace([string]$contentHash.algorithm)) {
            throw "Package definition '$DefinitionId' version '$Version' artifact '$TargetId' defines packageFile.contentHash without algorithm."
        }
        if (-not [string]::Equals([string]$contentHash.algorithm, 'sha256', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package definition '$DefinitionId' version '$Version' artifact '$TargetId' uses unsupported packageFile.contentHash algorithm '$($contentHash.algorithm)'. Use sha256."
        }
        if (-not $contentHash.PSObject.Properties['value'] -or [string]::IsNullOrWhiteSpace([string]$contentHash.value)) {
            throw "Package definition '$DefinitionId' version '$Version' artifact '$TargetId' defines packageFile.contentHash without value."
        }
    }

    if ($Artifact.PSObject.Properties['publisherSignature']) {
        $publisherSignature = $Artifact.publisherSignature
        if (-not $publisherSignature -or
            -not $publisherSignature.PSObject.Properties['kind'] -or
            [string]::IsNullOrWhiteSpace([string]$publisherSignature.kind)) {
            throw "Package definition '$DefinitionId' version '$Version' artifact '$TargetId' defines packageFile.publisherSignature without kind."
        }
        if (-not [string]::Equals([string]$publisherSignature.kind, 'authenticode', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package definition '$DefinitionId' version '$Version' artifact '$TargetId' uses unsupported packageFile.publisherSignature kind '$($publisherSignature.kind)'. Use authenticode."
        }
        if (-not $publisherSignature.PSObject.Properties['requireValid']) {
            throw "Package definition '$DefinitionId' version '$Version' artifact '$TargetId' defines packageFile.publisherSignature without requireValid."
        }
        if (-not $publisherSignature.PSObject.Properties['subjectContains'] -or [string]::IsNullOrWhiteSpace([string]$publisherSignature.subjectContains)) {
            throw "Package definition '$DefinitionId' version '$Version' artifact '$TargetId' defines packageFile.publisherSignature without subjectContains."
        }
    }
}

function Assert-PackageDefinitionSchema_1_2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$DefinitionDocumentInfo,

        [Parameter(Mandatory = $true)]
        [string]$DefinitionId,

        [string]$DefinitionRepositoryId = (Get-PackageDefaultRepositoryId)
    )

    $definition = $DefinitionDocumentInfo.Document
    foreach ($retiredProperty in @('releases', 'providedTools', 'shared', 'releaseDefaults', 'existingInstallDiscovery', 'existingInstallPolicy')) {
        if ($definition.PSObject.Properties[$retiredProperty]) {
            throw "Package definition '$($DefinitionDocumentInfo.Path)' still uses retired schemaVersion 1.1 property '$retiredProperty'. Use schemaVersion 1.2 packageTargets, versionCatalog, discovery, stateDiscovery, and packageOperations."
        }
    }

    foreach ($requiredProperty in @('schemaVersion', 'id', 'display', 'packageTargets', 'versionCatalog', 'discovery', 'stateDiscovery', 'upstreamSources', 'packageOperations')) {
        if (-not $definition.PSObject.Properties[$requiredProperty]) {
            throw "Package definition '$($DefinitionDocumentInfo.Path)' is missing required schemaVersion 1.2 property '$requiredProperty'."
        }
    }
    if (-not [string]::Equals([string]$definition.id, $DefinitionId, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Package definition id '$($definition.id)' does not match expected id '$DefinitionId'."
    }

    $targetIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $targetsById = @{}
    foreach ($target in @($definition.packageTargets)) {
        if (-not $target.PSObject.Properties['id'] -or [string]::IsNullOrWhiteSpace([string]$target.id)) {
            throw "Package definition '$DefinitionId' has packageTarget without id."
        }
        if (-not $targetIds.Add([string]$target.id)) {
            throw "Package definition '$DefinitionId' has duplicate packageTarget id '$($target.id)'."
        }
        $targetsById[[string]$target.id] = $target
        foreach ($requiredTargetProperty in @('channel', 'platformTarget', 'constraints', 'versionSelection')) {
            if (-not $target.PSObject.Properties[$requiredTargetProperty]) {
                throw "Package definition '$DefinitionId' packageTarget '$($target.id)' is missing '$requiredTargetProperty'."
            }
        }
        if (-not [string]::Equals([string]$target.versionSelection.strategy, 'latestByVersion', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Package definition '$DefinitionId' packageTarget '$($target.id)' uses unsupported versionSelection.strategy '$($target.versionSelection.strategy)'. Use latestByVersion."
        }
    }

    $dependencies = if (Test-PackageObjectHasProperty -InputObject $definition -Name 'dependencies') { @($definition.dependencies) } else { @() }
    foreach ($dependency in @($dependencies)) {
        if ($null -eq $dependency) {
            continue
        }
        if (-not $dependency.PSObject.Properties['repositoryId'] -or [string]::IsNullOrWhiteSpace([string]$dependency.repositoryId)) {
            throw "Package definition '$DefinitionId' has dependency without repositoryId."
        }
        if (-not $dependency.PSObject.Properties['definitionId'] -or [string]::IsNullOrWhiteSpace([string]$dependency.definitionId)) {
            throw "Package definition '$DefinitionId' has dependency without definitionId."
        }
    }

    $sharedOperation = if ($definition.packageOperations.PSObject.Properties['shared']) { $definition.packageOperations.shared } else { $null }
    $ownershipPolicy = if ($sharedOperation -and $sharedOperation.PSObject.Properties['ownershipPolicy']) { $sharedOperation.ownershipPolicy } else { $null }
    Assert-PackageDefinitionNoRetiredNestedProperty_1_2 -DefinitionId $DefinitionId -InputObject $ownershipPolicy -PropertyName 'requireManagedOwnership' -PropertyPath 'packageOperations.shared.ownershipPolicy.requireManagedOwnership' -ReplacementPath 'packageOperations.shared.ownershipPolicy.requirePackageOwnership'

    $assignedOperation = if ($definition.packageOperations.PSObject.Properties['assigned']) { $definition.packageOperations.assigned } else { $null }
    Assert-PackageDefinitionNoRetiredNestedProperty_1_2 -DefinitionId $DefinitionId -InputObject $assignedOperation -PropertyName 'managerDependency' -PropertyPath 'packageOperations.assigned.managerDependency' -ReplacementPath 'dependencies plus packageOperations.assigned.installerCommand'
    Assert-PackageDefinitionNoRetiredNestedProperty_1_2 -DefinitionId $DefinitionId -InputObject $assignedOperation -PropertyName 'managerKind' -PropertyPath 'packageOperations.assigned.managerKind' -ReplacementPath 'packageOperations.assigned.kind = npmGlobalPackage'

    foreach ($versionEntry in @($definition.versionCatalog)) {
        if (-not $versionEntry.PSObject.Properties['version'] -or [string]::IsNullOrWhiteSpace([string]$versionEntry.version)) {
            throw "Package definition '$DefinitionId' has versionCatalog entry without version."
        }
        if (-not $versionEntry.PSObject.Properties['artifactsByTarget'] -or $null -eq $versionEntry.artifactsByTarget) {
            throw "Package definition '$DefinitionId' version '$($versionEntry.version)' is missing artifactsByTarget."
        }
        foreach ($artifactProperty in @($versionEntry.artifactsByTarget.PSObject.Properties)) {
            if (-not $targetIds.Contains([string]$artifactProperty.Name)) {
                throw "Package definition '$DefinitionId' version '$($versionEntry.version)' references unknown packageTarget '$($artifactProperty.Name)'."
            }
            Assert-PackageArtifactTrustMetadata_1_2 -DefinitionId $DefinitionId -Version ([string]$versionEntry.version) -TargetId ([string]$artifactProperty.Name) -Artifact $artifactProperty.Value
        }
    }

    foreach ($sourceProperty in @($definition.upstreamSources.PSObject.Properties)) {
        $source = $sourceProperty.Value
        if (-not $source.PSObject.Properties['kind'] -or [string]::IsNullOrWhiteSpace([string]$source.kind)) {
            throw "Package definition '$DefinitionId' upstream source '$($sourceProperty.Name)' is missing kind."
        }
    }

    foreach ($target in @($definition.packageTargets)) {
        $targetArtifactSources = if ($target.PSObject.Properties['artifactDefaults'] -and $target.artifactDefaults.PSObject.Properties['artifactSources']) { @($target.artifactDefaults.artifactSources) } else { @() }
        foreach ($source in @($targetArtifactSources)) {
            if ([string]::Equals([string]$source.kind, 'download', [System.StringComparison]::OrdinalIgnoreCase) -and
                -not (Test-PackageObjectHasProperty -InputObject $definition.upstreamSources -Name ([string]$source.sourceId))) {
                throw "Package definition '$DefinitionId' packageTarget '$($target.id)' references unknown upstream source '$($source.sourceId)'."
            }
            if ($source.PSObject.Properties['priority']) {
                throw "Package definition '$DefinitionId' packageTarget '$($target.id)' still uses retired artifact source property 'priority'. Use searchOrder."
            }
        }
    }

    foreach ($versionEntry in @($definition.versionCatalog)) {
        foreach ($artifactProperty in @($versionEntry.artifactsByTarget.PSObject.Properties)) {
            $artifact = $artifactProperty.Value
            $target = $targetsById[[string]$artifactProperty.Name]
            $artifactSources = if ($artifact.PSObject.Properties['artifactSources']) {
                @($artifact.artifactSources)
            }
            elseif ($target -and $target.PSObject.Properties['artifactDefaults'] -and $target.artifactDefaults.PSObject.Properties['artifactSources']) {
                @($target.artifactDefaults.artifactSources)
            }
            else {
                @()
            }
            foreach ($source in @($artifactSources)) {
                if ([string]::Equals([string]$source.kind, 'download', [System.StringComparison]::OrdinalIgnoreCase) -and
                    -not (Test-PackageObjectHasProperty -InputObject $definition.upstreamSources -Name ([string]$source.sourceId))) {
                    throw "Package definition '$DefinitionId' version '$($versionEntry.version)' artifact '$($artifactProperty.Name)' references unknown upstream source '$($source.sourceId)'."
                }
                if ($source.PSObject.Properties['priority']) {
                    throw "Package definition '$DefinitionId' version '$($versionEntry.version)' artifact '$($artifactProperty.Name)' still uses retired artifact source property 'priority'. Use searchOrder."
                }
                if ([string]::Equals([string]$source.kind, 'download', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $sourceDefinition = Get-PackageObjectPropertyValue -InputObject $definition.upstreamSources -Name ([string]$source.sourceId)
                    if ($sourceDefinition -and
                        [string]::Equals([string]$sourceDefinition.kind, 'githubRelease', [System.StringComparison]::OrdinalIgnoreCase) -and
                        (-not $versionEntry.PSObject.Properties['releaseTag'] -or [string]::IsNullOrWhiteSpace([string]$versionEntry.releaseTag))) {
                        throw "Package definition '$DefinitionId' version '$($versionEntry.version)' artifact '$($artifactProperty.Name)' requires releaseTag because it uses GitHub release source '$($source.sourceId)'."
                    }
                }
            }
        }
    }

    $exposedCommands = @(Get-PackageDiscoveryEntryPoints -Definition $definition -ToolKind 'commands' -ExposedOnly)
    $assigned = $definition.packageOperations.assigned
    if ($assigned.PSObject.Properties['pathRegistration'] -and
        $assigned.pathRegistration.PSObject.Properties['source'] -and
        [string]::Equals([string]$assigned.pathRegistration.source.kind, 'shim', [System.StringComparison]::OrdinalIgnoreCase)) {
        if (-not [string]::Equals([string]$assigned.pathRegistration.source.use, 'discovery.commands', [System.StringComparison]::Ordinal)) {
            throw "Package definition '$DefinitionId' pathRegistration.source kind 'shim' requires use='discovery.commands'."
        }
        if ($exposedCommands.Count -eq 0) {
            throw "Package definition '$DefinitionId' uses shim PATH registration but has no exposed discovery.commands."
        }
    }
}

function Get-PackageArtifactForTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$VersionEntry,

        [Parameter(Mandatory = $true)]
        [string]$TargetId
    )

    foreach ($property in @($VersionEntry.artifactsByTarget.PSObject.Properties)) {
        if ([string]::Equals([string]$property.Name, $TargetId, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $property.Value
        }
    }

    return $null
}

function Resolve-PackageTargetArtifactText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [psobject]$Target,

        [Parameter(Mandatory = $true)]
        [psobject]$VersionEntry
    )

    if ($null -eq $Text) {
        return $null
    }

    return Resolve-TemplateText -Text $Text -Tokens @{
        version        = [string]$VersionEntry.version
        releaseTag     = if ($VersionEntry.PSObject.Properties['releaseTag']) { [string]$VersionEntry.releaseTag } else { $null }
        channel        = [string]$Target.channel
        platformTarget = [string]$Target.platformTarget
    }
}

function New-PackageValidationFromDiscovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Definition,

        [Parameter(Mandatory = $true)]
        [psobject]$Assigned
    )

    $require = if ($Assigned.PSObject.Properties['installedStateCheck'] -and $Assigned.installedStateCheck.PSObject.Properties['require']) {
        $Assigned.installedStateCheck.require
    }
    else {
        [pscustomobject]@{}
    }
    $discovery = $Definition.discovery

    $commandChecks = New-Object System.Collections.Generic.List[object]
    if ($require.PSObject.Properties['commands'] -and [bool]$require.commands) {
        foreach ($command in @($discovery.commands)) {
            foreach ($stateCheck in @($command.stateChecks)) {
                if ($null -eq $stateCheck) {
                    continue
                }
                $check = ConvertTo-PackageObject -InputObject $stateCheck
                $check | Add-Member -MemberType NoteProperty -Name 'entryPoint' -Value ([string]$command.name) -Force
                $commandChecks.Add($check) | Out-Null
            }
        }
    }

    return [pscustomobject]@{
        files          = if ($require.PSObject.Properties['files'] -and [bool]$require.files) { @($discovery.files) } else { @() }
        directories    = if ($require.PSObject.Properties['directories'] -and [bool]$require.directories) { @($discovery.directories) } else { @() }
        commandChecks  = @($commandChecks.ToArray())
        metadataFiles  = if ($require.PSObject.Properties['metadataFiles'] -and [bool]$require.metadataFiles) { @($discovery.metadataFiles) } else { @() }
        signatures     = if ($require.PSObject.Properties['signatures'] -and [bool]$require.signatures) { @($discovery.signatures) } else { @() }
        fileDetails    = if ($require.PSObject.Properties['fileDetails'] -and [bool]$require.fileDetails) { @($discovery.fileDetails) } else { @() }
        registryChecks = if ($require.PSObject.Properties['registry'] -and [bool]$require.registry) { @($discovery.registry) } else { @() }
    }
}

function Resolve-PackageEffectivePackage_1_2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PackageConfig
    )

    $definition = $PackageConfig.Definition
    $channel = if ([string]::IsNullOrWhiteSpace([string]$PackageConfig.ReleaseTrack)) { 'none' } else { [string]$PackageConfig.ReleaseTrack }
    $matches = New-Object System.Collections.Generic.List[object]

    foreach ($target in @($definition.packageTargets)) {
        $constraints = $target.constraints
        $osConstraints = if ($constraints.PSObject.Properties['os']) { @($constraints.os) } else { @() }
        $cpuConstraints = if ($constraints.PSObject.Properties['cpu']) { @($constraints.cpu) } else { @() }
        if (-not [string]::Equals([string]$target.channel, $channel, [System.StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-PackageConstraintSetMatch -Values $osConstraints -ActualValue $PackageConfig.Platform) -or
            -not (Test-PackageConstraintSetMatch -Values $cpuConstraints -ActualValue $PackageConfig.Architecture)) {
            continue
        }

        foreach ($versionEntry in @($definition.versionCatalog)) {
            $channels = if ($versionEntry.PSObject.Properties['channels']) { @($versionEntry.channels) } else { @() }
            $versionIsInChannel = $false
            foreach ($versionChannel in @($channels)) {
                if ([string]::Equals([string]$versionChannel, [string]$target.channel, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $versionIsInChannel = $true
                    break
                }
            }
            if (-not $versionIsInChannel) {
                continue
            }

            $artifact = Get-PackageArtifactForTarget -VersionEntry $versionEntry -TargetId ([string]$target.id)
            if ($artifact) {
                $matches.Add([pscustomobject]@{
                    Target       = $target
                    VersionEntry = $versionEntry
                    Artifact     = $artifact
                    SortVersion  = ConvertTo-PackageVersion -VersionText ([string]$versionEntry.version)
                }) | Out-Null
            }
        }
    }

    if ($matches.Count -eq 0) {
        throw "No Package target/catalog entry matched platform '$($PackageConfig.Platform)', architecture '$($PackageConfig.Architecture)', and channel '$channel'."
    }

    $selected = @($matches.ToArray()) | Sort-Object -Descending -Property SortVersion | Select-Object -First 1
    $target = $selected.Target
    $versionEntry = $selected.VersionEntry
    $artifact = $selected.Artifact
    $assigned = ConvertTo-PackageObject -InputObject $definition.packageOperations.assigned
    $artifactDefaults = if ($target.PSObject.Properties['artifactDefaults']) { $target.artifactDefaults } else { $null }
    $fileName = if ($artifact.PSObject.Properties['fileName'] -and -not [string]::IsNullOrWhiteSpace([string]$artifact.fileName)) {
        [string]$artifact.fileName
    }
    elseif ($artifactDefaults -and $artifactDefaults.PSObject.Properties['fileNameTemplate']) {
        Resolve-PackageTargetArtifactText -Text ([string]$artifactDefaults.fileNameTemplate) -Target $target -VersionEntry $versionEntry
    }
    else {
        $null
    }

    $packageFile = $null
    if (-not [string]::IsNullOrWhiteSpace($fileName) -or
        $artifact.PSObject.Properties['contentHash'] -or
        $artifact.PSObject.Properties['publisherSignature']) {
        $packageFile = [ordered]@{}
        if (-not [string]::IsNullOrWhiteSpace($fileName)) { $packageFile.fileName = $fileName }
        if ($artifact.PSObject.Properties['contentHash']) { $packageFile.contentHash = ConvertTo-PackageObject -InputObject $artifact.contentHash }
        if ($artifact.PSObject.Properties['publisherSignature']) { $packageFile.publisherSignature = ConvertTo-PackageObject -InputObject $artifact.publisherSignature }
    }

    $artifactSources = if ($artifact.PSObject.Properties['artifactSources']) { @($artifact.artifactSources) }
        elseif ($artifactDefaults -and $artifactDefaults.PSObject.Properties['artifactSources']) { @($artifactDefaults.artifactSources) }
        else { @() }
    $artifactSourcePath = if ($artifact.PSObject.Properties['sourcePath']) {
        Resolve-PackageTargetArtifactText -Text ([string]$artifact.sourcePath) -Target $target -VersionEntry $versionEntry
    }
    else {
        $null
    }
    $acquisitionCandidates = @(
        foreach ($source in @($artifactSources)) {
            $candidate = ConvertTo-PackageObject -InputObject $source
            if ([string]::Equals([string]$candidate.kind, 'download', [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($candidate.PSObject.Properties['sourcePath'] -and -not [string]::IsNullOrWhiteSpace([string]$candidate.sourcePath)) {
                    $candidate.sourcePath = Resolve-PackageTargetArtifactText -Text ([string]$candidate.sourcePath) -Target $target -VersionEntry $versionEntry
                }
                elseif (-not [string]::IsNullOrWhiteSpace($artifactSourcePath)) {
                    $candidate | Add-Member -MemberType NoteProperty -Name 'sourcePath' -Value $artifactSourcePath -Force
                }
            }
            $candidate
        }
    )

    $packageId = if ($artifact.PSObject.Properties['releaseId'] -and -not [string]::IsNullOrWhiteSpace([string]$artifact.releaseId)) {
        [string]$artifact.releaseId
    }
    else {
        '{0}-{1}-{2}' -f [string]$definition.id, [string]$target.id, [string]$versionEntry.version
    }

    return [pscustomobject]@{
        id                    = $packageId
        version               = [string]$versionEntry.version
        releaseTag            = if ($versionEntry.PSObject.Properties['releaseTag']) { [string]$versionEntry.releaseTag } else { $null }
        releaseTrack          = [string]$target.channel
        channel               = [string]$target.channel
        flavor                = [string]$target.platformTarget
        platformTarget        = [string]$target.platformTarget
        packageTargetId       = [string]$target.id
        constraints           = ConvertTo-PackageObject -InputObject $target.constraints
        packageFile           = if ($packageFile) { [pscustomobject]$packageFile } else { $null }
        acquisitionCandidates = @($acquisitionCandidates)
        compatibility         = ConvertTo-PackageObject -InputObject $definition.packageOperations.shared.compatibility
        stateDiscovery        = ConvertTo-PackageObject -InputObject $definition.stateDiscovery
        ownershipPolicy       = ConvertTo-PackageObject -InputObject $definition.packageOperations.shared.ownershipPolicy
        assigned              = $assigned
        removed               = ConvertTo-PackageObject -InputObject $definition.packageOperations.removed
        validation            = New-PackageValidationFromDiscovery -Definition $definition -Assigned $assigned
    }
}
